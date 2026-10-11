# Shared helpers for the SDD harness hooks.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
# Hooks must never break the session: every entry script wraps its work in try/catch and exits 0.

$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $script:Utf8NoBom } catch {}
try { [Console]::InputEncoding = $script:Utf8NoBom } catch {}

function Get-ProjectRoot {
    if ($env:CLAUDE_PROJECT_DIR -and (Test-Path -LiteralPath $env:CLAUDE_PROJECT_DIR)) {
        return (Resolve-Path -LiteralPath $env:CLAUDE_PROJECT_DIR).Path.TrimEnd('\', '/')
    }
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\', '/')
}

function Read-HookInput {
    try {
        if ([Console]::IsInputRedirected) {
            $raw = [Console]::In.ReadToEnd()
            if ($raw -and $raw.Trim()) { return ($raw | ConvertFrom-Json) }
        }
    } catch {}
    return $null
}

function Read-Lines([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return [string[]][IO.File]::ReadAllLines($Path, $script:Utf8NoBom) }
    return [string[]]@()
}

function Add-Line([string]$Path, [string]$Line) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::AppendAllText($Path, $Line + "`n", $script:Utf8NoBom)
}

function Get-Config([string]$Root) {
    $cfg = [ordered]@{
        enforceCheckpointOnStop = $true
        requireApprovalGates    = $true
        autoCommitPerTask       = $true
        journalTailLines        = 20
        maxEditsShown           = 25
        gitStatusLines          = 25
    }
    $path = Join-Path $Root '.sdd\config.json'
    try {
        if (Test-Path -LiteralPath $path) {
            $json = [IO.File]::ReadAllText($path, $script:Utf8NoBom) | ConvertFrom-Json
            foreach ($p in $json.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
        }
    } catch {}
    return $cfg
}

function Write-Activity([string]$Root, [string]$Event, [string]$Detail) {
    $line = '{0} {1} {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $Event, $Detail
    Add-Line (Join-Path $Root '.sdd\activity.log') $line.TrimEnd()
}

function Get-StateField([string[]]$Lines, [string]$Name) {
    foreach ($l in $Lines) {
        if ($l -match ('^\s*' + [regex]::Escape($Name) + '\s*:\s*(.*?)\s*$')) { return $Matches[1] }
    }
    return $null
}

function Test-NoFeature([string]$Feature) {
    return (-not $Feature) -or ($Feature -match '^(ninguna|ninguno|none|-|)$')
}

# Returns project-relative path with forward slashes, or $null if the path is outside the project.
function Get-RelativePath([string]$Root, [string]$Path) {
    if (-not $Path) { return $null }
    $r = ($Root -replace '/', '\').TrimEnd('\') + '\'
    $p = $Path -replace '/', '\'
    if (-not [IO.Path]::IsPathRooted($p)) { return ($p -replace '\\', '/') }
    if ($p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) {
        return ($p.Substring($r.Length) -replace '\\', '/')
    }
    return $null
}

# Edits recorded in activity.log after the last CHECKPOINT (unique, in order).
function Get-ActivitySinceCheckpoint([string]$Root) {
    $lines = Read-Lines (Join-Path $Root '.sdd\activity.log')
    $lastIdx = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '^\S+ CHECKPOINT\b') { $lastIdx = $i; break }
    }
    $edits = New-Object System.Collections.Generic.List[string]
    $compactions = 0
    for ($i = $lastIdx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\S+ EDIT (.+)$') {
            $f = $Matches[1].Trim()
            if (-not $edits.Contains($f)) { $edits.Add($f) }
        } elseif ($lines[$i] -match '^\S+ COMPACT\b') {
            $compactions++
        }
    }
    $lastTs = $null
    if ($lastIdx -ge 0) { $lastTs = ($lines[$lastIdx] -split ' ')[0] }
    return [pscustomobject]@{ Edits = $edits; LastCheckpoint = $lastTs; Compactions = $compactions }
}

function Get-TaskInfo([string]$TasksPath) {
    $info = [pscustomobject]@{
        Exists = $false; Total = 0; Done = 0; Pending = 0; InProgress = 0; Blocked = 0; Discarded = 0
        InProgressLines = @(); BlockedLines = @(); NextLines = @()
    }
    if (-not (Test-Path -LiteralPath $TasksPath)) { return $info }
    $info.Exists = $true
    $inProg = New-Object System.Collections.Generic.List[string]
    $blocked = New-Object System.Collections.Generic.List[string]
    $next = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Read-Lines $TasksPath)) {
        # Only real task lines (with an ID like T001), not the legend or template placeholders.
        if ($l -notmatch '^\s*[-*]\s+\[(.)\]\s+(T\d+\w*\b.*)$') { continue }
        $mark = $Matches[1]; $text = $Matches[2].Trim()
        $info.Total++
        switch -Regex ($mark) {
            '^[xX]$' { $info.Done++; break }
            '^~$'    { $info.InProgress++; $inProg.Add($text); break }
            '^!$'    { $info.Blocked++; $blocked.Add($text); break }
            '^-$'    { $info.Discarded++; break }
            default  { $info.Pending++; if ($next.Count -lt 3) { $next.Add($text) } }
        }
    }
    $info.InProgressLines = $inProg.ToArray()
    $info.BlockedLines = $blocked.ToArray()
    $info.NextLines = $next.ToArray()
    return $info
}

# Drops <!-- ... --> blocks (template guidance) so they don't waste context on injection.
function Remove-HtmlComments([string[]]$Lines) {
    $result = New-Object System.Collections.Generic.List[string]
    $inComment = $false
    foreach ($l in $Lines) {
        $text = $l
        if ($inComment) {
            $end = $text.IndexOf('-->')
            if ($end -lt 0) { continue }
            $text = $text.Substring($end + 3); $inComment = $false
        }
        while ($true) {
            $start = $text.IndexOf('<!--')
            if ($start -lt 0) { break }
            $end = $text.IndexOf('-->', $start + 4)
            if ($end -lt 0) { $text = $text.Substring(0, $start); $inComment = $true; break }
            $text = $text.Substring(0, $start) + $text.Substring($end + 3)
        }
        if ($text.Trim() -or -not $l.Trim()) { $result.Add($text.TrimEnd()) }
    }
    return [string[]]$result.ToArray()
}

function Limit-Text([string]$Text, [int]$Max = 200) {
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max) + '...'
}
