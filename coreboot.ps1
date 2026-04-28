param(
    [Parameter(Position=0)]
    [string]$ProjectName,

    [Parameter(Position=1)]
    [ValidateSet("pc", "mobile", IgnoreCase=$true)]
    [string]$Platform,

    [string]$RootPath,

    [string]$ApiProxy,

    [switch]$Install,

    [switch]$IgnoreGIT
)

if ($Install) {
    $installDir  = Join-Path $env:LOCALAPPDATA "coreboot"
    $installPath = Join-Path $installDir "coreboot.ps1"
    $wrapperPath = Join-Path $installDir "coreboot.cmd"

    $sourcePath = $MyInvocation.MyCommand.Path
    if (-not $sourcePath) {
        Write-Host "  Could not determine script path. Run the installer via install-coreboot.cmd." -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Write-Host "  Created install directory: $installDir" -ForegroundColor DarkGray
    }

    Copy-Item -Path $sourcePath -Destination $installPath -Force
    Write-Host "  Copied script to: $installPath" -ForegroundColor DarkGray

    Set-Content -Path $wrapperPath -Value '@echo off powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0coreboot.ps1" %*' -Encoding ASCII
    Write-Host "  Created wrapper: $wrapperPath" -ForegroundColor DarkGray

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
        Write-Host "  Added $installDir to user PATH." -ForegroundColor Green
    } else {
        Write-Host "  $installDir already in PATH." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  Installed to: $installDir" -ForegroundColor Green
    Write-Host "  Restart your terminal, then run:" -ForegroundColor White
    Write-Host "    coreboot <project> <pc|mobile> [-RootPath `"path`"] [-ApiProxy `"domain.tld`"]" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

if (-not $ProjectName -or -not $Platform) {
    Write-Host ""
    Write-Host "  Usage:  coreboot <project> <pc|mobile> [-RootPath `"path`"] [-ApiProxy `"domain.tld`"] [-IgnoreGIT]" -ForegroundColor Cyan
    Write-Host "  Install: .\bootstrap.ps1 -Install" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

# --- Node version: require 14 or lower ---
$nodeVersion = node -v 2>$null
if ($nodeVersion) {
    $majorVersion = [int]($nodeVersion -replace '^v(\d+).*', '$1')
    if ($majorVersion -gt 14) {
        Write-Host ""
        Write-Host "  Error: Node $nodeVersion is not supported. This project requires Node 14 or lower." -ForegroundColor Red
        Write-Host ""
        exit 1
    }
}

# --- Install gulp and browser-sync globally if missing ---
$toInstall = @()
if (-not (Get-Command gulp -ErrorAction SilentlyContinue)) { $toInstall += "gulp" }
if (-not (Get-Command browser-sync -ErrorAction SilentlyContinue)) { $toInstall += "browser-sync" }
if ($toInstall.Count -gt 0) {
    Write-Host "  Installing $($toInstall -join ', ') globally..." -ForegroundColor Yellow
    npm install -g $toInstall
}

# --- Config directory ---
$configDir = Join-Path $env:LOCALAPPDATA "coreboot"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# --- RootPath: validate, persist, and resolve ---
$rootPathMapPath = Join-Path $configDir "rootpath-map.json"
$rootPathMap = @{}

if (Test-Path $rootPathMapPath) {
    try {
        $raw = Get-Content $rootPathMapPath -Raw | ConvertFrom-Json
        $raw.PSObject.Properties | ForEach-Object { $rootPathMap[$_.Name] = $_.Value }
    } catch {
        Write-Host "  Warning: could not read rootpath-map.json, starting fresh." -ForegroundColor Yellow
    }
}

if ($RootPath) {
    if (-not (Test-Path $RootPath)) {
        Write-Host ""
        Write-Host "  Error: -RootPath '$RootPath' does not exist." -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    $rootPathMap["default"] = $RootPath
    $rootPathMap | ConvertTo-Json | Set-Content $rootPathMapPath -Encoding UTF8
    Write-Host "  Saved root path: $RootPath" -ForegroundColor DarkGray
}

$DocsRoot = if ($RootPath) {
    $RootPath
} elseif ($rootPathMap.ContainsKey("default")) {
    $rootPathMap["default"]
} else {
    [Environment]::GetFolderPath("MyDocuments")
}

# --- ApiProxy: validate, persist, and resolve ---
$proxyMapPath = Join-Path $configDir "proxy-map.json"
$proxyMap = @{}

if (Test-Path $proxyMapPath) {
    try {
        $raw = Get-Content $proxyMapPath -Raw | ConvertFrom-Json
        $raw.PSObject.Properties | ForEach-Object { $proxyMap[$_.Name] = $_.Value }
    } catch {
        Write-Host "  Warning: could not read proxy-map.json, starting fresh." -ForegroundColor Yellow
    }
}

if ($ApiProxy) {
    if ($ApiProxy -notmatch '\.') {
        Write-Host ""
        Write-Host "  Error: -ApiProxy value '$ApiProxy' is invalid. It must contain at least one '.' (e.g. 'donbet.co')." -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    $proxyMap[$ProjectName] = $ApiProxy
    $proxyMap | ConvertTo-Json | Set-Content $proxyMapPath -Encoding UTF8
    Write-Host "  Saved api-proxy mapping: $ProjectName -> $ApiProxy" -ForegroundColor DarkGray
}

$ResolvedProxy = if ($ApiProxy) {
    $ApiProxy
} elseif ($proxyMap.ContainsKey($ProjectName)) {
    $proxyMap[$ProjectName]
} else {
    "$ProjectName.com"
}

$script:PlatformFolder = if ($Platform.ToLower() -eq "pc") { "PC" } else { "Mobile" }
$ProjectPath    = Join-Path $DocsRoot $ProjectName
$script:PlatformPath   = Join-Path $ProjectPath $script:PlatformFolder
$script:DistPath       = Join-Path $script:PlatformPath "dist"
$ApiProxyPath   = Join-Path $DocsRoot "api-proxy"
$CorePath       = Join-Path $DocsRoot "core"

if (-not (Test-Path $ProjectPath)) {
    Write-Host "Project not found: $ProjectPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $script:PlatformPath)) {
    Write-Host "Platform folder not found: $script:PlatformPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $ApiProxyPath)) {
    Write-Host "api-proxy not found at '$ApiProxyPath'. Clone the api-proxy repo into '$DocsRoot' and try again." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $CorePath)) {
    Write-Host "core not found at '$CorePath'. Clone the core repo into '$DocsRoot' and try again." -ForegroundColor Red
    exit 1
}

$isFirstRun = -not (Test-Path $script:DistPath)

if ($isFirstRun) {
    New-Item -ItemType Directory -Path $script:DistPath -Force | Out-Null
}

$script:CopyDistArgs = if ($script:PlatformFolder -eq "PC") { $ProjectName } else { "$ProjectName mobile" }

# --- UI Helpers ---
function Get-ConsoleWidth {
    try { [Console]::BufferWidth } catch { 80 }
}

function Write-Line {
    param(
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::White,
        [switch]$NoNewline
    )
    $width = Get-ConsoleWidth
    $padded = $Text.PadRight($width)
    if ($NoNewline) {
        Write-Host "`r$padded" -NoNewline -ForegroundColor $Color
    } else {
        Write-Host "`r$padded" -ForegroundColor $Color
    }
}

function Write-Divider {
    param([ConsoleColor]$Color = [ConsoleColor]::DarkGray)
    $width = Get-ConsoleWidth
    $line = [string]::new([char]0x2500, [Math]::Min($width - 4, 60))
    Write-Host "  $line" -ForegroundColor $Color
}

function Write-Section {
    param([string]$Title, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    Write-Host ""
    Write-Divider
    Write-Host "  $Title" -ForegroundColor $Color
    Write-Divider
    Write-Host ""
}

# --- Initial Setup ---
Write-Section "coreboot  -  Dev Environment"

Write-Host "  Project   : $ProjectName" -ForegroundColor White
Write-Host "  Platform  : $script:PlatformFolder" -ForegroundColor White
Write-Host "  Root      : $DocsRoot" -ForegroundColor DarkGray
Write-Host "  API Proxy : $ResolvedProxy" -ForegroundColor DarkGray
Write-Host ""

if ($isFirstRun) {
    Write-Host "  First run detected - installing dependencies..." -ForegroundColor Yellow
    Write-Host ""

    Push-Location $script:PlatformPath
    npm install
    Pop-Location

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Error: npm install failed. Please check the output above." -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    Write-Host ""
    Write-Host "  Dependencies installed successfully." -ForegroundColor Green
    Write-Host ""
    Start-Sleep -Milliseconds 800
}

# --- Clear terminal after setup, redraw header ---
Clear-Host

Write-Section "coreboot  -  Launching Services"

Write-Host "  Project   : $ProjectName ($script:PlatformFolder)" -ForegroundColor White
Write-Host "  API Proxy : $ResolvedProxy" -ForegroundColor DarkGray
Write-Host ""

$script:childProcs = [System.Collections.ArrayList]::new()

function Stop-AllChildren {
    Write-Host ""
    Write-Divider -Color Yellow
    Write-Host "  Shutting down all services..." -ForegroundColor Yellow
    Write-Divider -Color Yellow
    foreach ($proc in $script:childProcs) {
        try {
            if ($proc -and -not $proc.HasExited) {
                & taskkill /T /F /PID $proc.Id 2>$null | Out-Null
            }
        } catch {}
    }
    Write-Host ""
    Write-Host "  All services stopped." -ForegroundColor Green
    Write-Host ""
}

Register-EngineEvent PowerShell.Exiting -Action { Stop-AllChildren } | Out-Null

# --- Step 1: Gulp Build ---
Write-Host "  Starting Gulp build..." -ForegroundColor DarkCyan
$gulpCmd = if ($isFirstRun) { "git pull & gulp run" } else { "git pull & npm i & gulp run" }
$script:childProcs.Add((Start-Process cmd -ArgumentList "/k title GULP RUN $ProjectName & $gulpCmd" -WorkingDirectory $script:PlatformPath -PassThru)) | Out-Null

$waitSeconds = 15
$HtmlPath    = Join-Path $script:DistPath "html"
$tickMs      = 200
$totalTicks  = [int]($waitSeconds * 1000 / $tickMs)
$barWidth    = 20
$braille     = @([char]0x2801, [char]0x2802, [char]0x2804, [char]0x2840, [char]0x2880, [char]0x2820, [char]0x2810, [char]0x2808)

$tick  = 0
$found = $false

while ($tick -lt $totalTicks) {
    $elapsedSec  = [math]::Floor($tick * $tickMs / 1000)
    $progress    = [math]::Min($tick / $totalTicks, 1.0)
    $filledCount = [int]($progress * $barWidth)
    $emptyCount  = $barWidth - $filledCount
    $filledBar   = [string]::new([char]0x2588, $filledCount)
    $emptyBar    = [string]::new([char]0x2591, $emptyCount)
    $frame       = $braille[$tick % $braille.Length]
    $pct         = [int]($progress * 100)

    if ($found) {
        $status = "Build detected, finishing up..."
        $color  = [ConsoleColor]::Yellow
    } else {
        $status = "Waiting for initial build..."
        $color  = [ConsoleColor]::DarkCyan
    }

    Write-Line -Text "  $frame  $filledBar$emptyBar  ${pct}%  ${elapsedSec}s  $status" -Color $color -NoNewline

    if (-not $found -and (Test-Path (Join-Path $HtmlPath "index.html"))) {
        $found = $true
    }

    Start-Sleep -Milliseconds $tickMs
    $tick++
}

if ($found) {
    Write-Line -Text "  [OK] Build ready." -Color Green
} else {
    Write-Line -Text "  [..] Build not detected yet - BrowserSync will reload when files appear." -Color Yellow
}

Write-Host ""

# --- Step 2: Core - copy dist ---
Write-Host "  Starting Core (copydist)..." -ForegroundColor DarkCyan
$corePullCmd = if ($IgnoreGIT) { "npm run copydist $($script:CopyDistArgs)" } else { "git pull & npm run copydist $($script:CopyDistArgs)" }
$script:childProcs.Add((Start-Process cmd -ArgumentList "/k title CORE & $corePullCmd" -WorkingDirectory $CorePath -PassThru)) | Out-Null
Start-Sleep -Milliseconds 500

# --- Step 3: API Proxy ---
Write-Host "  Starting API Proxy ($ResolvedProxy)..." -ForegroundColor DarkCyan
$script:childProcs.Add((Start-Process cmd -ArgumentList "/k title API-PROXY & npm run start -- --host $ResolvedProxy" -WorkingDirectory $ApiProxyPath -PassThru)) | Out-Null
Start-Sleep -Milliseconds 500

# --- Step 4: BrowserSync ---
Write-Host "  Starting BrowserSync (localhost:3002)..." -ForegroundColor DarkCyan
$script:childProcs.Add((Start-Process cmd -ArgumentList "/k title BROWSERSYNC & browser-sync start --server --port 3002 --startPath /html --files **/*.*" -WorkingDirectory $script:DistPath -PassThru)) | Out-Null

# --- Platform Switch Function ---
function Switch-Platform {
    $newFolder = if ($script:PlatformFolder -eq "PC") { "Mobile" } else { "PC" }
    $newPlatformPath = Join-Path $ProjectPath $newFolder

    if (-not (Test-Path $newPlatformPath)) {
        Write-Host ""
        Write-Host "  Platform folder not found: $newPlatformPath" -ForegroundColor Red
        Write-Host "  Switch cancelled." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    $newDistPath = Join-Path $newPlatformPath "dist"
    $newCopyDistArgs = if ($newFolder -eq "PC") { $ProjectName } else { "$ProjectName mobile" }

    Write-Host ""
    Write-Divider -Color Yellow
    Write-Host "  Switching to $newFolder..." -ForegroundColor Yellow
    Write-Divider -Color Yellow

    # Kill Gulp (index 0), Core (index 1), BrowserSync (index 3)
    foreach ($i in @(0, 1, 3)) {
        try {
            if ($script:childProcs[$i] -and -not $script:childProcs[$i].HasExited) {
                & taskkill /T /F /PID $script:childProcs[$i].Id 2>$null | Out-Null
            }
        } catch {}
    }
    Start-Sleep -Milliseconds 500

    $script:PlatformFolder = $newFolder
    $script:PlatformPath   = $newPlatformPath
    $script:DistPath       = $newDistPath
    $script:CopyDistArgs   = $newCopyDistArgs

    if (-not (Test-Path $script:DistPath)) {
        New-Item -ItemType Directory -Path $script:DistPath -Force | Out-Null
    }

    $gulpCmd = "git pull & npm i & gulp run"
    $script:childProcs[0] = Start-Process cmd -ArgumentList "/k title GULP RUN $ProjectName & $gulpCmd" -WorkingDirectory $script:PlatformPath -PassThru
    Start-Sleep -Milliseconds 300

    $corePullCmd = if ($IgnoreGIT) { "npm run copydist $($script:CopyDistArgs)" } else { "git pull & npm run copydist $($script:CopyDistArgs)" }
    $script:childProcs[1] = Start-Process cmd -ArgumentList "/k title CORE & $corePullCmd" -WorkingDirectory $CorePath -PassThru
    Start-Sleep -Milliseconds 300

    $script:childProcs[3] = Start-Process cmd -ArgumentList "/k title BROWSERSYNC & browser-sync start --server --port 3002 --startPath /html --files **/*.*" -WorkingDirectory $script:DistPath -PassThru

    Write-Host "  Switched to $newFolder. Services restarting..." -ForegroundColor Green
    Start-Sleep -Milliseconds 500
}

function Draw-Dashboard {
    Clear-Host
    Write-Section "coreboot  -  $ProjectName ($($script:PlatformFolder))"

    $services = @(
        @{ Icon = [char]0x25B6; Name = "Gulp Build";    Detail = "pull + compile ($($script:PlatformFolder))";   Color = "Cyan"       }
        @{ Icon = [char]0x25B6; Name = "Core Copydist"; Detail = "pull + copydist $($script:CopyDistArgs)";      Color = "Green"      }
        @{ Icon = [char]0x25B6; Name = "API Proxy";     Detail = "proxying to $ResolvedProxy";                   Color = "DarkYellow" }
        @{ Icon = [char]0x25B6; Name = "BrowserSync";   Detail = "http://localhost:3002/html (live-reload)";     Color = "Magenta"    }
    )

    foreach ($svc in $services) {
        $icon   = $svc.Icon
        $name   = $svc.Name.PadRight(16)
        $detail = $svc.Detail
        Write-Host "  $icon  " -NoNewline -ForegroundColor $svc.Color
        Write-Host "$name" -NoNewline -ForegroundColor White
        Write-Host " $detail" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Divider

    $pcLabel     = " PC "
    $mobileLabel = " Mobile "
    if ($script:PlatformFolder -eq "PC") {
        $pcStyle     = @{ Fg = "Black"; Bg = "Cyan" }
        $mobileStyle = @{ Fg = "DarkGray"; Bg = "Black" }
    } else {
        $pcStyle     = @{ Fg = "DarkGray"; Bg = "Black" }
        $mobileStyle = @{ Fg = "Black"; Bg = "Cyan" }
    }

    Write-Host "  Platform:  " -NoNewline -ForegroundColor White
    Write-Host $pcLabel -NoNewline -ForegroundColor $pcStyle.Fg -BackgroundColor $pcStyle.Bg
    Write-Host "  " -NoNewline
    Write-Host $mobileLabel -ForegroundColor $mobileStyle.Fg -BackgroundColor $mobileStyle.Bg
    Write-Host ""
    Write-Host "  Press " -NoNewline -ForegroundColor White
    Write-Host "[P]" -NoNewline -ForegroundColor Cyan
    Write-Host " to switch platform   " -NoNewline -ForegroundColor White
    Write-Host "Ctrl+C" -NoNewline -ForegroundColor Yellow
    Write-Host " to stop all" -ForegroundColor White
    Write-Divider
    Write-Host ""
}

# --- Final Dashboard ---
Start-Sleep -Milliseconds 300
Draw-Dashboard

try {
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::P) {
                Switch-Platform
                Draw-Dashboard
            }
        }
        Start-Sleep -Milliseconds 100
    }
} finally {
    Stop-AllChildren
}
