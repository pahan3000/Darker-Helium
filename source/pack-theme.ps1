# Package a Playnite theme into a .pthm
# Run from PowerShell:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\pack-theme.ps1
#
# Optional:
#   .\pack-theme.ps1 -ThemeDirectory ".\Darker-Helium"
#   .\pack-theme.ps1 -ToolboxPath "C:\path\to\Toolbox.exe"

param(
    [string]$ThemeDirectory = "",
    [string]$ToolboxPath = "",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
$ExitCode = 1
$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$LogPath = Join-Path $Root "pack.log"

function Log([string]$m, [string]$c = "Gray") {
    switch ($c) {
        "Red"    { Write-Host $m -ForegroundColor Red }
        "Green"  { Write-Host $m -ForegroundColor Green }
        "Cyan"   { Write-Host $m -ForegroundColor Cyan }
        "Yellow" { Write-Host $m -ForegroundColor Yellow }
        default  { Write-Host $m -ForegroundColor DarkGray }
    }
    try { Add-Content -LiteralPath $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m) } catch {}
}

try {
    Set-Content -LiteralPath $LogPath -Value ("theme pack start " + (Get-Date -Format "o")) -Encoding UTF8
    Log ("Root: " + $Root)

    # Find the theme directory.
    if ($ThemeDirectory) {
        $Theme = [System.IO.Path]::GetFullPath((Join-Path $Root $ThemeDirectory))
        if (-not (Test-Path -LiteralPath $Theme -PathType Container)) {
            $Theme = [System.IO.Path]::GetFullPath($ThemeDirectory)
        }
    } else {
        $Theme = $null
        foreach ($candidate in @(
            (Join-Path $Root "Darker-Helium"),
            (Join-Path $Root "Theme"),
            $Root
        )) {
            if (Test-Path -LiteralPath (Join-Path $candidate "theme.yaml") -PathType Leaf) {
                $Theme = [System.IO.Path]::GetFullPath($candidate)
                break
            }
        }

        if (-not $Theme) {
            $found = Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "theme.yaml") } |
                Select-Object -First 1
            if ($found) { $Theme = $found.FullName }
        }
    }

    if (-not $Theme -or -not (Test-Path -LiteralPath $Theme -PathType Container)) {
        throw "Theme folder not found. Put the theme beside this script or use -ThemeDirectory."
    }

    $Yaml = Join-Path $Theme "theme.yaml"
    if (-not (Test-Path -LiteralPath $Yaml -PathType Leaf)) {
        throw "theme.yaml not found in: $Theme"
    }

    Log ("Theme: " + $Theme) "Cyan"

    # Read Name and Version from theme.yaml.
    $Name = "Darker Helium"
    $Version = "1.0.0"
    foreach ($line in Get-Content -LiteralPath $Yaml) {
        if ($line -match '^\s*Name\s*:\s*(.+?)\s*$') {
            $Name = $Matches[1].Trim().Trim('"', "'")
        }
        if ($line -match '^\s*Version\s*:\s*(.+?)\s*$') {
            $Version = $Matches[1].Trim().Trim('"', "'")
        }
    }

    $SafeName = ($Name -replace '[^\w\.-]+', '_').Trim('_')
    if (-not $SafeName) { $SafeName = "Darker-Helium" }
    $SafeVersion = ($Version -replace '[^\w\.-]+', '_').Trim('_')
    if (-not $SafeVersion) { $SafeVersion = "1.0.0" }

    $Dist = if ($OutputDirectory) {
        [System.IO.Path]::GetFullPath((Join-Path $Root $OutputDirectory))
    } else {
        Join-Path $Root "dist"
    }
    New-Item -ItemType Directory -Path $Dist -Force | Out-Null

    # Find Toolbox.exe. Explicit path > PATH > common Playnite locations.
    $Toolbox = $null

    if ($ToolboxPath) {
        $candidate = [System.IO.Path]::GetFullPath($ToolboxPath)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $Toolbox = $candidate
        } else {
            throw "Toolbox.exe was not found at: $candidate"
        }
    }

    if (-not $Toolbox) {
        $cmd = Get-Command Toolbox.exe -ErrorAction SilentlyContinue
        if ($cmd) { $Toolbox = $cmd.Source }
    }

    if (-not $Toolbox) {
        $locations = @(
            (Join-Path $env:LOCALAPPDATA "Playnite\Toolbox.exe"),
            (Join-Path $env:ProgramFiles "Playnite\Toolbox.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "Playnite\Toolbox.exe"),
            (Join-Path $env:LOCALAPPDATA "Playnite\Toolbox\Toolbox.exe"),
            (Join-Path $env:ProgramFiles "Playnite\Toolbox\Toolbox.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "Playnite\Toolbox\Toolbox.exe")
        )
        foreach ($candidate in $locations) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $Toolbox = $candidate
                break
            }
        }
    }

    if (-not $Toolbox) {
        throw "Toolbox.exe not found. Use -ToolboxPath ""C:\...\Toolbox.exe""."
    }

    Log ("Toolbox: " + $Toolbox) "Green"

    # Toolbox's official syntax is:
    # Toolbox.exe pack <add-on-directory> <destination-directory>
    Log ("Packing -> " + $Dist) "Cyan"
    # Toolbox prints a theme API version warning on every pack. It is only a
    # notice, so filter it out. All other Toolbox output is still shown/logged.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $toolboxOutput = & $Toolbox pack $Theme $Dist 2>&1 | ForEach-Object { $_.ToString() }
    $toolboxExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap

    foreach ($line in $toolboxOutput) {
        if (-not $line -or -not $line.Trim()) { continue }
        if ($line -match 'latest supported API version' -or $line -match 'Playnite/issues/1259') { continue }
        Log $line
    }

    if ($toolboxExit -ne 0) {
        throw "Toolbox failed with exit code $toolboxExit."
    }

    # Find the package Toolbox created.
    $Pthm = Get-ChildItem -LiteralPath $Dist -Filter "*.pthm" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $Pthm) {
        throw "Toolbox returned success, but no .pthm was found in: $Dist"
    }

    # Give it a predictable filename.
    $Wanted = Join-Path $Dist ($SafeName + "_" + $SafeVersion + ".pthm")
    if ($Pthm.FullName -ne $Wanted) {
        if (Test-Path -LiteralPath $Wanted) { Remove-Item -LiteralPath $Wanted -Force }
        Move-Item -LiteralPath $Pthm.FullName -Destination $Wanted -Force
        $Pthm = Get-Item -LiteralPath $Wanted
    }

    $kb = [math]::Round($Pthm.Length / 1KB, 1)
    Log ""
    Log "========================================" "Green"
    Log ("  PTHM READY: " + $Pthm.FullName) "Green"
    Log ("  Size: " + $kb + " KB") "Green"
    Log "========================================" "Green"
    $ExitCode = 0
}
catch {
    Log "PACK FAILED" "Red"
    Log $_.Exception.Message "Red"
    try { Add-Content -LiteralPath $LogPath -Value $_.Exception.ToString() } catch {}
    $ExitCode = 1
}

Write-Host ""
Write-Host ("Log: " + $LogPath) -ForegroundColor DarkGray
Write-Host "Press Enter to close..." -ForegroundColor DarkGray
try { [void](Read-Host) } catch {}
exit $ExitCode
