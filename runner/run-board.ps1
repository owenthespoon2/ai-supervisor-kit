param(
    # Project root (default: current directory). The board, data dir and git repo are resolved from here.
    [string]$Project = "",
    # Config file (default: <Project>\kit.config.json; missing keys fall back to the kit's kit.config.example.json).
    [string]$Config = "",
    [int]$MaxTasks = 6,
    [int]$CooldownSeconds = 5,
    # Overrides claude.defaultEffort for tasks without an [effort:...] tag (low|medium|high|xhigh|max).
    [string]$Effort = "",
    # Fallback reset time (HH:mm, local) if a usage-limit message doesn't say when it resets.
    [string]$ResumeAt = "",
    # How many times one task may wait for a usage reset before the run stops.
    [int]$MaxLimitWaits = 4,
    # Minutes to wait past the reset time before resuming.
    [int]$ResumeGraceMinutes = 2,
    # Print the next task, model/effort and the exact claude command, then exit. Reads only; runs nothing.
    [switch]$DryRun
)

# Board runner: one fresh `claude -p` session per open board task ("- [ ] **ID:** ...").
# - Live, readable progress in this window and in <dataDir>/logs/<run>.log
# - One JSON line per task + one per run in <dataDir>/runs.jsonl (tokens per model and per subagent)
# - Current state in <dataDir>/status.json, summary in <dataDir>/latest-summary.md
# - Stops on: a [!] task, a CLI error, a task left unfinished, a commit touching a protected path.
# - Usage limit: parses the reset time from the message, waits, then resumes the SAME task from its uncommitted work.

$ErrorActionPreference = "Stop"
$KitDir = Split-Path -Parent $PSScriptRoot
$Root = if ($Project) { (Resolve-Path $Project).Path } else { (Get-Location).Path }
Set-Location $Root
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$Utf8 = New-Object System.Text.UTF8Encoding $false

# ---- Config: kit defaults, overlaid by the project's kit.config.json ----
function Merge-Obj($Base, $Over) {
    if ($null -eq $Over) { return $Base }
    if ($Over -isnot [System.Management.Automation.PSCustomObject] -or $Base -isnot [System.Management.Automation.PSCustomObject]) { return $Over }
    $out = $Base.PSObject.Copy()
    foreach ($p in $Over.PSObject.Properties) {
        $cur = $out.PSObject.Properties[$p.Name]
        if ($cur) { $out.($p.Name) = Merge-Obj $cur.Value $p.Value } else { $out | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
    return $out
}
$cfg = Get-Content -Raw -Encoding UTF8 (Join-Path $KitDir "kit.config.example.json") | ConvertFrom-Json
$cfgPath = if ($Config) { $Config } else { Join-Path $Root "kit.config.json" }
if (Test-Path $cfgPath) { $cfg = Merge-Obj $cfg (Get-Content -Raw -Encoding UTF8 $cfgPath | ConvertFrom-Json) }
else { Write-Host "No kit.config.json at $cfgPath - using kit defaults." -ForegroundColor Yellow }

$BoardFile = Join-Path $Root $cfg.board
$PromptFile = if ($cfg.taskPrompt) { Join-Path $Root $cfg.taskPrompt } else { Join-Path $KitDir "protocol\TASK-PROMPT.md" }
$DefaultModel = if ($cfg.claude.defaultModel) { $cfg.claude.defaultModel } else { "opus" }
$DefaultEffort = if ($Effort) { $Effort } elseif ($cfg.claude.defaultEffort) { $cfg.claude.defaultEffort } else { "medium" }
$Protected = @($cfg.protectedPaths | Where-Object { $_ })

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "Claude Code CLI ('claude') not found in PATH." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $BoardFile) -or -not (Test-Path $PromptFile)) {
    Write-Host "Missing board ($BoardFile) or task prompt ($PromptFile)" -ForegroundColor Red
    exit 1
}

$DataDir = Join-Path $Root $cfg.dataDir
$LogDir = Join-Path $DataDir "logs"
$RunId = (Get-Date).ToString("yyyyMMdd-HHmmss")
$RunLog = Join-Path $LogDir "$RunId.log"
$RunsFile = Join-Path $DataDir "runs.jsonl"
$StatusFile = Join-Path $DataDir "status.json"
$SummaryFile = Join-Path $DataDir "latest-summary.md"
$RunStarted = Get-Date

function Now { (Get-Date).ToString("HH:mm:ss") }
function Iso([datetime]$d) { $d.ToString("yyyy-MM-ddTHH:mm:sszzz") }

function Write-Log([string]$Text, [string]$Color = "Gray") {
    $line = "[$(Now)] $Text"
    Write-Host $line -ForegroundColor $Color
    if (-not $DryRun) { [System.IO.File]::AppendAllText($RunLog, $line + "`n", $Utf8) }
}
function Add-Record($Obj) { [System.IO.File]::AppendAllText($RunsFile, ($Obj | ConvertTo-Json -Compress -Depth 6) + "`n", $Utf8) }
function Set-Status($Obj) { [System.IO.File]::WriteAllText($StatusFile, ($Obj | ConvertTo-Json -Depth 4), $Utf8) }

function Short([string]$s, [int]$n = 160) {
    if ($null -eq $s) { return "" }
    $s = ($s -replace "\s+", " ").Trim()
    if ($s.Length -gt $n) { return $s.Substring(0, $n) + "..." }
    return $s
}

function Describe-Tool($c) {
    $a = $c.input
    switch -Regex ($c.name) {
        "^Bash$"                  { return "run: " + (Short $a.command 140) }
        "^(Read|Edit|Write|MultiEdit|NotebookEdit)$" { return "$($c.name.ToLower()): " + ($a.file_path -replace [regex]::Escape($Root + "\"), "") }
        "^(Grep|Glob)$"           { return "search: " + (Short $a.pattern 100) }
        "^(Agent|Task)$"          { return "subagent ($((@($a.subagent_type, $a.model) | Where-Object { $_ }) -join ' ')): " + (Short $a.description 100) }
        default                   { return "$($c.name): " + (Short ($a | ConvertTo-Json -Compress -Depth 3) 120) }
    }
}

function Fmt-Tok([double]$n) {
    if ($n -ge 1000000) { return "{0:N1}M" -f ($n / 1000000) }
    if ($n -ge 1000) { return "{0:N0}k" -f ($n / 1000) }
    return "{0:N0}" -f $n
}

# Effective cost (see learnings/TOKEN-LEARNINGS.md): 0.1*cacheRead + input + 1.25*cacheWrite + 5*output.
function Eff($t) { return [math]::Round(0.1 * $t.cacheRead + $t.input + 1.25 * $t.cacheWrite + 5 * $t.output) }

# Per-message usage, keyed by message id (the same message can arrive in several events; keep the max).
function Track-Usage($e) {
    $u = $e.message.usage
    $mid = [string]$e.message.id
    if (-not $u -or -not $mid) { return }
    $bucket = if ($e.parent_tool_use_id) { [string]$e.parent_tool_use_id } else { "main" }
    $prev = $script:msgUsage[$mid]
    $row = @{
        bucket = $bucket; model = [string]$e.message.model
        input = [math]::Max([double]$u.input_tokens, $(if ($prev) { $prev.input } else { 0 }))
        output = [math]::Max([double]$u.output_tokens, $(if ($prev) { $prev.output } else { 0 }))
        cacheRead = [math]::Max([double]$u.cache_read_input_tokens, $(if ($prev) { $prev.cacheRead } else { 0 }))
        cacheWrite = [math]::Max([double]$u.cache_creation_input_tokens, $(if ($prev) { $prev.cacheWrite } else { 0 }))
    }
    $script:msgUsage[$mid] = $row
    if ($bucket -ne "main" -and -not $script:agentInfo.ContainsKey($bucket)) { $script:agentInfo[$bucket] = @{ label = "subagent"; model = "" } }
    if ($bucket -ne "main" -and $row.model -and -not $script:agentInfo[$bucket].model) { $script:agentInfo[$bucket].model = $row.model }
}

function Sum-Bucket([string]$Bucket) {
    $t = [ordered]@{ input = 0.0; output = 0.0; cacheRead = 0.0; cacheWrite = 0.0; messages = 0 }
    foreach ($r in $script:msgUsage.Values) {
        if ($Bucket -and $r.bucket -ne $Bucket) { continue }
        $t.input += $r.input; $t.output += $r.output; $t.cacheRead += $r.cacheRead; $t.cacheWrite += $r.cacheWrite; $t.messages++
    }
    $t.total = $t.input + $t.output + $t.cacheRead + $t.cacheWrite
    return $t
}

# Usage/rate-limit stop: only looked for when the session failed, so code that merely mentions limits can't trigger it.
# Wording seen: "You've hit your 5-hour limit · resets 5:10am (<Region/City>)" as the only text, exit 1. The reset time differs every time.
function Find-LimitMessage($ExitCode, $ResultEvt, $RawLines, $LastText, [bool]$Unfinished) {
    $failed = ($ExitCode -ne 0) -or ($ResultEvt -and $ResultEvt.is_error) -or $Unfinished
    if (-not $failed) { return $null }
    $texts = @()
    if ($ResultEvt -and $ResultEvt.result) { $texts += [string]$ResultEvt.result }
    if ($LastText) { $texts += [string]$LastText }
    if ($RawLines) { $texts += $RawLines }
    foreach ($t in $texts) {
        if ($t -match '(?i)(usage limit|limit reached|hit your .{0,24}limit|\d+-hour limit|weekly limit|rate.?limit|too many requests|out of (extra )?usage|limit.{0,40}resets?|\|\d{10})') { return $t }
    }
    return $null
}

# Reset time from the message ("...|1795030200", "resets 5:10am", "resets at 17:10"), else -ResumeAt, else 30 minutes.
function Get-ResumeTime([string]$Msg) {
    if ($Msg -match '\|(\d{10})') { return ([DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1])).LocalDateTime }
    $clock = $null
    if ($Msg -match '(?i)resets?\b.{0,30}?\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b') {
        $h = [int]$Matches[1] % 12; if ($Matches[3] -ieq 'pm') { $h += 12 }
        $clock = "{0:D2}:{1}" -f $h, $(if ($Matches[2]) { $Matches[2] } else { '00' })
    } elseif ($Msg -match '(?i)resets?\s+(?:at\s+)?(\d{1,2}):(\d{2})') {
        $clock = "{0:D2}:{1}" -f [int]$Matches[1], $Matches[2]
    } elseif ($ResumeAt) { $clock = $ResumeAt }
    if ($clock) {
        $t = [datetime]::ParseExact((Get-Date).ToString('yyyy-MM-dd') + ' ' + $clock, 'yyyy-MM-dd HH:mm', $null)
        if ($t -le (Get-Date)) { $t = $t.AddDays(1) }
        return $t
    }
    return (Get-Date).AddMinutes(30)
}

function Get-TaskState([string]$Board, [string]$TaskId) {
    $esc = [regex]::Escape($TaskId)
    if ($Board -match "(?m)^- \[x\] \*\*$esc(?![A-Za-z0-9_-])") { return "done" }
    if ($Board -match "(?m)^- \[!\] \*\*$esc(?![A-Za-z0-9_-])") { return "blocked" }
    return "incomplete"
}

function Read-Board { Get-Content -Raw -Encoding UTF8 $BoardFile }

$Prompt = (Get-Content -Raw -Encoding UTF8 $PromptFile) -replace '\{\{BOARD\}\}', $cfg.board
foreach ($p in $cfg.claude.env.PSObject.Properties) { Set-Item -Path "env:$($p.Name)" -Value ([string]$p.Value) }

function Build-Args([string]$Model, [string]$Eff) {
    $a = @('--model', $Model, '--effort', $Eff, '--max-turns', [string]$cfg.claude.maxTurns)
    if ($cfg.claude.settingSources) { $a += @('--setting-sources', $cfg.claude.settingSources) }
    if ($cfg.claude.tools) { $a += @('--tools', $cfg.claude.tools) }
    $a += @($cfg.claude.extraArgs | Where-Object { $_ })
    if ($cfg.claude.skipPermissions) { $a += '--dangerously-skip-permissions' }
    $a += @('--output-format', 'stream-json', '--verbose')
    return $a
}

function Next-Task([string]$Board) {
    $line = ($Board -split "`r?`n" | Where-Object { $_ -match '^- \[ \]' } | Select-Object -First 1)
    $id = if ($line -match '^- \[ \] \*\*([A-Za-z0-9_-]+)') { $Matches[1] } else { "TASK" }
    return [ordered]@{
        line = $line; id = $id
        title = Short (($line -replace '^- \[ \] \*\*[^*]+\*\*\s*', '')) 200
        model = if ($line -match '\[model:(opus|sonnet|haiku)\]') { $Matches[1] } else { $DefaultModel }
        effort = if ($line -match '\[effort:(low|medium|high|xhigh|max)\]') { $Matches[1] } else { $DefaultEffort }
    }
}

if ($DryRun) {
    $b = Read-Board
    if ($b -match '(?m)^- \[!\]') { Write-Host "DRY RUN: board has a [!] task - a real run would stop at once." -ForegroundColor Red; exit 0 }
    if ($b -notmatch '(?m)^- \[ \]') { Write-Host "DRY RUN: no open task." -ForegroundColor Green; exit 0 }
    $t = Next-Task $b
    Write-Host "DRY RUN (nothing executed)" -ForegroundColor Cyan
    Write-Host "  project : $Root"
    Write-Host "  board   : $BoardFile ($(@($b -split "`r?`n" | Where-Object { $_ -match '^- \[ \]' }).Count) open)"
    Write-Host "  prompt  : $PromptFile ($($Prompt.Length) chars)"
    Write-Host "  next    : $($t.id) [$($t.model)/$($t.effort)] $($t.title)"
    Write-Host "  env     : $(($cfg.claude.env.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')"
    Write-Host "  command : claude -p <prompt> $((Build-Args $t.model $t.effort) -join ' ')"
    Write-Host "  data    : $DataDir   protected: $($Protected -join ', ')"
    exit 0
}

New-Item -ItemType Directory -Force $LogDir | Out-Null
$TaskRecords = @()
$StopReason = "reached MaxTasks ($MaxTasks)"
$TotalTokens = 0.0

Write-Log "=== Run $RunId started (max $MaxTasks tasks) in $Root ===" "Green"
Write-Log "Live log file: $RunLog" "DarkGray"

for ($i = 1; $i -le $MaxTasks; $i++) {
    $board = Read-Board
    if ($board -match '(?m)^- \[!\]') { $StopReason = "circuit breaker: a task is marked [!] in the board"; Write-Log $StopReason "Red"; break }
    if ($board -notmatch '(?m)^- \[ \]') { $StopReason = "all board tasks complete"; Write-Log $StopReason "Green"; break }

    $t = Next-Task $board
    $taskId = $t.id; $taskTitle = $t.title; $taskModel = $t.model; $taskEffort = $t.effort
    $taskStart = Get-Date
    $headBefore = (git rev-parse HEAD).Trim()

    Write-Host ""
    Write-Log "=== Fresh session $i/$MaxTasks : $taskId [$taskModel/$taskEffort] ===" "Cyan"
    Write-Log "    $taskTitle" "Cyan"
    Set-Status ([ordered]@{ state = "running"; runId = $RunId; taskId = $taskId; taskTitle = $taskTitle; session = $i; maxTasks = $MaxTasks; taskStartedAt = (Iso $taskStart); lastActivity = "session starting"; updatedAt = (Iso (Get-Date)) })

    $limitWaits = 0
    $sessionPrompt = $Prompt
    $claudeArgs = Build-Args $taskModel $taskEffort
    while ($true) {
    $script:resultEvt = $null
    $script:toolCount = 0
    $script:msgUsage = @{}
    $script:agentInfo = @{}
    $script:rawLines = New-Object System.Collections.Generic.List[string]
    $script:lastText = $null
    $ErrorActionPreference = "Continue"
    # 2>&1 so a usage-limit message printed on stderr is seen too (non-JSON lines are logged and kept).
    claude -p $sessionPrompt @claudeArgs 2>&1 | ForEach-Object {
        $raw = [string]$_
        if (-not $raw.Trim()) { return }
        try { $e = $raw | ConvertFrom-Json } catch { $script:rawLines.Add($raw); Write-Log "    $(Short $raw 200)" "DarkGray"; return }
        $pre = if ($e.parent_tool_use_id) { "      | " } else { "  " }
        switch ($e.type) {
            "system" {
                # More than one "session ready" per task = the session woke again (background-and-wait). Costly: see learnings.
                if ($e.subtype -eq "init") { Write-Log "${pre}session ready (model: $($e.model), tools: $(@($e.tools).Count), MCP servers: $(@($e.mcp_servers).Count), plugins: $(@($e.plugins).Count))" "DarkGray" }
            }
            "assistant" {
                Track-Usage $e
                foreach ($c in $e.message.content) {
                    if ($c.type -eq "tool_use" -and $c.name -match '^(Agent|Task)$') {
                        $script:agentInfo[[string]$c.id] = @{ label = (Short ("$($c.input.subagent_type): $($c.input.description)".TrimStart(': ')) 80); model = [string]$c.input.model }
                    }
                    if ($c.type -eq "text" -and $c.text.Trim()) {
                        if (-not $e.parent_tool_use_id) { $script:lastText = $c.text }
                        Write-Log "${pre}says: $(Short $c.text 300)" "White"
                    } elseif ($c.type -eq "tool_use") {
                        $script:toolCount++
                        $desc = Describe-Tool $c
                        Write-Log "${pre}-> $desc" $(if ($e.parent_tool_use_id) { "DarkYellow" } else { "Yellow" })
                        Set-Status ([ordered]@{ state = "running"; runId = $RunId; taskId = $taskId; taskTitle = $taskTitle; session = $i; maxTasks = $MaxTasks; taskStartedAt = (Iso $taskStart); lastActivity = (Short $desc 200); toolCalls = $script:toolCount; tokens = (Sum-Bucket "").total; updatedAt = (Iso (Get-Date)) })
                    }
                }
            }
            "user" {
                foreach ($c in $e.message.content) {
                    if ($c.type -eq "tool_result" -and $script:agentInfo.ContainsKey([string]$c.tool_use_id)) {
                        $ai = $script:agentInfo[[string]$c.tool_use_id]
                        $s = Sum-Bucket ([string]$c.tool_use_id)
                        Write-Log "${pre}   subagent done ($($ai.label)): $(Fmt-Tok $s.total) tokens ($(Fmt-Tok $s.output) out, $(Fmt-Tok $s.cacheRead) cache-read)" "DarkCyan"
                    }
                    if ($c.type -eq "tool_result" -and $c.is_error) {
                        $msg = if ($c.content -is [string]) { $c.content } else { ($c.content | ForEach-Object { $_.text }) -join " " }
                        Write-Log "${pre}   tool error: $(Short $msg 200)" "Red"
                    }
                }
            }
            "result" { $script:resultEvt = $e }
        }
    }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"

    # ---- Usage limit: wait for the reset, then resume the SAME task from its partial work ----
    $unfinished = (Get-TaskState (Read-Board) $taskId) -eq "incomplete"
    $limitMsg = Find-LimitMessage $exitCode $script:resultEvt $script:rawLines $script:lastText $unfinished
    if ($limitMsg -and $limitWaits -lt $MaxLimitWaits) {
        $limitWaits++
        $resumeTime = Get-ResumeTime $limitMsg
        Add-Record ([ordered]@{ type = "limit"; runId = $RunId; taskId = $taskId; at = (Iso (Get-Date)); resumeAt = (Iso $resumeTime); message = (Short $limitMsg 200); wait = $limitWaits })
        Write-Log "=== Usage limit reached during $taskId. Waiting until $($resumeTime.ToString('HH:mm')) (+$ResumeGraceMinutes min), then resuming it. ===" "Magenta"
        while ((Get-Date) -lt $resumeTime.AddMinutes($ResumeGraceMinutes)) {
            Set-Status ([ordered]@{ state = "waiting-for-usage-reset"; runId = $RunId; taskId = $taskId; taskTitle = $taskTitle; resumeAt = (Iso $resumeTime); lastActivity = "usage limit - resumes at $($resumeTime.ToString('HH:mm'))"; updatedAt = (Iso (Get-Date)) })
            Start-Sleep -Seconds ([math]::Max(5, [math]::Min(600, ($resumeTime.AddMinutes($ResumeGraceMinutes) - (Get-Date)).TotalSeconds)))
        }
        Write-Log "=== Resuming $taskId after the usage reset (attempt $($limitWaits + 1)) ===" "Cyan"
        $sessionPrompt = $Prompt + "`n`nNOTE FROM THE RUNNER: the previous session on this same task was cut off by the usage limit. Its uncommitted changes are still in the working tree. Start with ``git status`` and ``git diff --stat``, keep the useful partial work, and finish the task instead of starting over."
        continue
    }
    break
    }

    $taskEnd = Get-Date
    $headAfter = (git rev-parse HEAD).Trim()
    $commits = @(); $files = @()
    if ($headAfter -ne $headBefore) {
        $commits = @(git log --format="%h %s" "$headBefore..$headAfter")
        $files = @(git diff --name-only $headBefore $headAfter)
    }
    $state = Get-TaskState (Read-Board) $taskId
    if ($exitCode -ne 0) { $state = "failed" }
    $hitProtected = @($files | Where-Object { $f = $_; $Protected | Where-Object { $f -eq $_ -or $f.StartsWith($_.TrimEnd('/') + '/') } })
    $r = $script:resultEvt

    $tok = Sum-Bucket ""
    $mainTok = if ($r -and $r.usage) { [ordered]@{ input = [double]$r.usage.input_tokens; output = [double]$r.usage.output_tokens; cacheRead = [double]$r.usage.cache_read_input_tokens; cacheWrite = [double]$r.usage.cache_creation_input_tokens } } else { $null }
    $byModel = @()
    if ($r -and $r.modelUsage) {
        foreach ($p in $r.modelUsage.PSObject.Properties) {
            $m = $p.Value
            $byModel += [ordered]@{ model = $p.Name; input = $m.inputTokens; output = $m.outputTokens; cacheRead = $m.cacheReadInputTokens; cacheWrite = $m.cacheCreationInputTokens }
        }
    }
    $agents = @()
    $mainSum = Sum-Bucket "main"
    $agents += [ordered]@{ label = "main session"; model = $taskModel; input = $mainSum.input; output = $mainSum.output; cacheRead = $mainSum.cacheRead; cacheWrite = $mainSum.cacheWrite; total = $mainSum.total; messages = $mainSum.messages }
    foreach ($k in $script:agentInfo.Keys) {
        $s = Sum-Bucket $k
        $agents += [ordered]@{ label = $script:agentInfo[$k].label; model = $script:agentInfo[$k].model; input = $s.input; output = $s.output; cacheRead = $s.cacheRead; cacheWrite = $s.cacheWrite; total = $s.total; messages = $s.messages }
    }
    $TotalTokens += $tok.total

    $rec = [ordered]@{
        type = "task"; runId = $RunId; session = $i; taskId = $taskId; title = $taskTitle
        status = $state; exitCode = $exitCode; effort = $taskEffort; model = $taskModel; limitWaits = $limitWaits
        startedAt = (Iso $taskStart); finishedAt = (Iso $taskEnd)
        minutes = [math]::Round(($taskEnd - $taskStart).TotalMinutes, 1)
        toolCalls = $script:toolCount; turns = $(if ($r) { $r.num_turns } else { $null })
        tokens = [ordered]@{ input = $tok.input; output = $tok.output; cacheRead = $tok.cacheRead; cacheWrite = $tok.cacheWrite; total = $tok.total }
        effective = (Eff $tok)
        perCallCacheRead = $(if ($script:toolCount) { [math]::Round($tok.cacheRead / $script:toolCount) } else { $null })
        resultUsage = $mainTok; byModel = $byModel; agents = $agents
        agentsNote = "per-agent output tokens are a lower bound (stream events carry partial output counts); byModel output is exact"
        commits = $commits; filesChanged = $files; protectedTouched = $hitProtected
        receipt = $(if ($r) { [string]$r.result } else { "" })
        log = "logs/$RunId.log"
    }
    Add-Record $rec
    $TaskRecords += $rec

    $color = switch ($state) { "done" { "Green" } "blocked" { "Red" } default { "Yellow" } }
    Write-Log "=== $taskId finished: $state in $($rec.minutes) min, $($script:toolCount) calls, $($files.Count) files, $($commits.Count) commit(s), effective $(Fmt-Tok $rec.effective) ===" $color
    foreach ($a in $agents) { Write-Log ("    tokens  {0,-40} {1,-18} total {2,7}  in {3,6}  out {4,6}  cache-read {5,7}  cache-write {6,6}" -f (Short $a.label 40), (Short $a.model 18), (Fmt-Tok $a.total), (Fmt-Tok $a.input), (Fmt-Tok $a.output), (Fmt-Tok $a.cacheRead), (Fmt-Tok $a.cacheWrite)) "DarkCyan" }
    if ($rec.receipt) { foreach ($l in ($rec.receipt -split "`r?`n")) { if ($l.Trim()) { Write-Log "    $l" $color } } }

    if ($hitProtected.Count) { $StopReason = "$taskId committed a protected path: $($hitProtected -join ', ')"; Write-Log $StopReason "Red"; break }
    if ($exitCode -ne 0) { $StopReason = "Claude CLI exited with code $exitCode (usage limit or error)"; Write-Log $StopReason "Yellow"; break }
    if ($state -eq "blocked") { $StopReason = "circuit breaker: $taskId marked [!]"; Write-Log $StopReason "Red"; break }
    if ($state -ne "done") { $StopReason = "$taskId was left unfinished (not marked [x]); stopping so it is not retried blindly"; Write-Log $StopReason "Yellow"; break }

    Start-Sleep -Seconds $CooldownSeconds
}

# ---- Summary ----
$runEnd = Get-Date
$done = @($TaskRecords | Where-Object { $_.status -eq "done" })
$notDone = @($TaskRecords | Where-Object { $_.status -ne "done" })
$nextUp = (Read-Board) -split "`r?`n" | Where-Object { $_ -match '^- \[ \]' } | Select-Object -First 1

Add-Record ([ordered]@{
    type = "run"; runId = $RunId; startedAt = (Iso $RunStarted); finishedAt = (Iso $runEnd)
    hours = [math]::Round(($runEnd - $RunStarted).TotalHours, 2)
    tasksAttempted = $TaskRecords.Count; tasksDone = @($done | ForEach-Object { $_.taskId })
    tasksNotDone = @($notDone | ForEach-Object { "$($_.taskId) ($($_.status))" })
    stopReason = $StopReason; totalTokens = $TotalTokens
    nextTask = $(if ($nextUp) { Short $nextUp 200 } else { "" })
    log = "logs/$RunId.log"
})

$md = @("# Run $RunId", "",
    "- Started: $(Iso $RunStarted)", "- Finished: $(Iso $runEnd)",
    "- Tasks done: $($done.Count) of $($TaskRecords.Count) attempted",
    "- Stopped because: $StopReason",
    "- Tokens used: $(Fmt-Tok $TotalTokens) in total",
    "- Next task on the board: $(if ($nextUp) { Short $nextUp 200 } else { 'none' })", "")
foreach ($t in $TaskRecords) {
    $md += "## $($t.taskId) - $($t.status) ($($t.minutes) min, $($t.toolCalls) calls, $($t.model)/$($t.effort))"
    $md += ""
    $md += $t.title
    $md += ""
    $md += "Tokens: effective $(Fmt-Tok $t.effective); $(Fmt-Tok $t.tokens.output) output, $(Fmt-Tok $t.tokens.cacheRead) cache-read, $(Fmt-Tok $t.tokens.cacheWrite) cache-write"
    foreach ($a in $t.agents) { $md += "- $($a.label) [$($a.model)]: $(Fmt-Tok $a.total)" }
    $md += ""
    if ($t.commits.Count) { $md += "Commits:"; $t.commits | ForEach-Object { $md += "- $_" }; $md += "" }
    if ($t.receipt) { $md += "Receipt:"; $md += ""; $md += $t.receipt; $md += "" }
}
[System.IO.File]::WriteAllText($SummaryFile, ($md -join "`n"), $Utf8)
Set-Status ([ordered]@{ state = "idle"; runId = $RunId; lastRunFinishedAt = (Iso $runEnd); stopReason = $StopReason; updatedAt = (Iso (Get-Date)) })

Write-Host ""
Write-Log "=== Run finished: $($done.Count)/$($TaskRecords.Count) tasks done. $StopReason ===" "Green"
Write-Log "Summary: $SummaryFile" "Green"
