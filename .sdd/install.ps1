<#
.SYNOPSIS
  Installs (or initializes) the SDD harness in a project.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .sdd\install.ps1 -Target D:\Proyectos\OtroProyecto
  powershell -NoProfile -ExecutionPolicy Bypass -File .sdd\install.ps1 -Target .      # initialize state here

.NOTES
  - Harness files (hooks, commands, protocol, templates) are copied; with -Force they are overwritten
    (useful to upgrade). Project state (STATE.md, journal.md, constitution.md, config.json, specs/)
    is only created when missing, never overwritten.
  - An existing .claude/settings.json is merged (hooks + permissions); a backup is kept.
  - ASCII-only file: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
#>
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$Src = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $Target)) { New-Item -ItemType Directory -Path $Target -Force | Out-Null }
$Dst = (Resolve-Path -LiteralPath $Target).Path
$SameRoot = ($Src.TrimEnd('\') -ieq $Dst.TrimEnd('\'))

function Say([string]$Msg) { Write-Host "  $Msg" }

function Copy-HarnessFile([string]$Rel, [switch]$Always) {
    $from = Join-Path $Src $Rel
    $to = Join-Path $Dst $Rel
    if ($SameRoot) { return }
    if ((Test-Path -LiteralPath $to) -and -not ($Force -or $Always)) { Say "skip (exists)  $Rel"; return }
    $dir = Split-Path -Parent $to
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $from -Destination $to -Force
    Say "copied         $Rel"
}

function New-FromTemplate([string]$TemplateRel, [string]$Rel) {
    $to = Join-Path $Dst $Rel
    if (Test-Path -LiteralPath $to) { Say "keep (state)   $Rel"; return }
    $dir = Split-Path -Parent $to
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $Src $TemplateRel) -Destination $to
    Say "created        $Rel"
}

function Set-Prop($Obj, [string]$Name, $Value) {
    if ($Obj.PSObject.Properties[$Name]) { $Obj.$Name = $Value }
    else { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Merge-Settings([string]$SrcPath, [string]$DstPath) {
    $s = [IO.File]::ReadAllText($SrcPath, $Utf8NoBom) | ConvertFrom-Json
    $d = [IO.File]::ReadAllText($DstPath, $Utf8NoBom) | ConvertFrom-Json

    if (-not $d.PSObject.Properties['permissions']) { Set-Prop $d 'permissions' ([pscustomobject]@{}) }
    $allow = New-Object System.Collections.ArrayList
    if ($d.permissions.PSObject.Properties['allow']) { foreach ($a in $d.permissions.allow) { [void]$allow.Add($a) } }
    foreach ($a in $s.permissions.allow) { if (-not $allow.Contains($a)) { [void]$allow.Add($a) } }
    Set-Prop $d.permissions 'allow' ([object[]]$allow.ToArray())

    if (-not $d.PSObject.Properties['hooks']) { Set-Prop $d 'hooks' ([pscustomobject]@{}) }
    foreach ($ev in $s.hooks.PSObject.Properties) {
        $list = New-Object System.Collections.ArrayList
        $existingJson = ''
        if ($d.hooks.PSObject.Properties[$ev.Name]) {
            foreach ($g in $d.hooks.($ev.Name)) { [void]$list.Add($g) }
            $existingJson = ($d.hooks.($ev.Name) | ConvertTo-Json -Depth 20)
        }
        foreach ($group in $ev.Value) {
            $script = ''
            if ($group.hooks[0].command -match '([\w-]+\.ps1)') { $script = $Matches[1] }
            if ($script -and $existingJson.Contains($script)) { continue }
            [void]$list.Add($group)
        }
        Set-Prop $d.hooks $ev.Name ([object[]]$list.ToArray())
    }

    # Keep the first (pre-harness) version as backup; later runs must not overwrite it.
    if (-not (Test-Path -LiteralPath ($DstPath + '.bak-sdd'))) { Copy-Item -LiteralPath $DstPath -Destination ($DstPath + '.bak-sdd') }
    [IO.File]::WriteAllText($DstPath, ($d | ConvertTo-Json -Depth 20), $Utf8NoBom)
    Say "merged         .claude/settings.json (backup: settings.json.bak-sdd)"
}

Write-Host "SDD harness -> $Dst"

# 1. Harness files
Get-ChildItem -LiteralPath (Join-Path $Src '.claude\hooks') -Filter '*.ps1' | ForEach-Object { Copy-HarnessFile ".claude\hooks\$($_.Name)" }
Get-ChildItem -LiteralPath (Join-Path $Src '.claude\commands') -Filter 'sdd-*.md' | ForEach-Object { Copy-HarnessFile ".claude\commands\$($_.Name)" }
Get-ChildItem -LiteralPath (Join-Path $Src '.sdd\templates') -File | ForEach-Object { Copy-HarnessFile ".sdd\templates\$($_.Name)" }
foreach ($f in @('.sdd\PROTOCOL.md', '.sdd\README.md', '.sdd\install.ps1')) { Copy-HarnessFile $f }

# 2. settings.json (copy or merge)
if (-not $SameRoot) {
    $dstSettings = Join-Path $Dst '.claude\settings.json'
    if (Test-Path -LiteralPath $dstSettings) { Merge-Settings (Join-Path $Src '.claude\settings.json') $dstSettings }
    else { Copy-HarnessFile '.claude\settings.json' }
}

# 3. Project state (never overwritten)
if ((-not $SameRoot) -and -not (Test-Path -LiteralPath (Join-Path $Dst '.sdd\config.json'))) {
    Copy-Item -LiteralPath (Join-Path $Src '.sdd\config.json') -Destination (Join-Path $Dst '.sdd\config.json')
    Say "created        .sdd\config.json"
}
New-FromTemplate '.sdd\templates\state.md' '.sdd\STATE.md'
New-FromTemplate '.sdd\templates\journal.md' '.sdd\journal.md'
New-FromTemplate '.sdd\templates\constitution.md' '.sdd\constitution.md'
$specs = Join-Path $Dst 'specs'
if (-not (Test-Path -LiteralPath $specs)) { New-Item -ItemType Directory -Path $specs | Out-Null }
if (-not (Test-Path -LiteralPath (Join-Path $specs '.gitkeep'))) { [IO.File]::WriteAllText((Join-Path $specs '.gitkeep'), '', $Utf8NoBom) }

# 4. CLAUDE.md imports the protocol
$section = [IO.File]::ReadAllText((Join-Path $Src '.sdd\templates\claude-md-section.md'), $Utf8NoBom)
$claudeMd = Join-Path $Dst 'CLAUDE.md'
if (-not (Test-Path -LiteralPath $claudeMd)) {
    [IO.File]::WriteAllText($claudeMd, "# CLAUDE.md`n`n<!-- Project description: goal, stack, build/test/lint commands, conventions. -->`n" + $section, $Utf8NoBom)
    Say "created        CLAUDE.md"
} elseif (-not ([IO.File]::ReadAllText($claudeMd, $Utf8NoBom)).Contains('@.sdd/PROTOCOL.md')) {
    [IO.File]::AppendAllText($claudeMd, "`n" + $section, $Utf8NoBom)
    Say "appended       SDD section to CLAUDE.md"
} else { Say "keep           CLAUDE.md (already imports the protocol)" }

# 5. .gitignore
$gi = Join-Path $Dst '.gitignore'
$giText = ''
if (Test-Path -LiteralPath $gi) { $giText = [IO.File]::ReadAllText($gi, $Utf8NoBom) }
foreach ($entry in @('.sdd/activity.log', '.claude/settings.local.json', '.claude/settings.json.bak-sdd')) {
    if ($giText -notmatch ('(?m)^' + [regex]::Escape($entry) + '\s*$')) {
        if ($giText -and -not $giText.EndsWith("`n")) { $giText += "`n" }
        $giText += "$entry`n"
        Say "gitignore      $entry"
    }
}
[IO.File]::WriteAllText($gi, $giText, $Utf8NoBom)

Write-Host 'Done. Open the project with Claude Code; the hooks load at session start.'
Write-Host 'Next: /sdd-constitution (optional) and /sdd-new <description>.'
