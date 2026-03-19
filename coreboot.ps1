param(
    [Parameter(Position=0)]
    [string]$ProjectName,

    [Parameter(Position=1)]
    [ValidateSet("pc", "mobile", IgnoreCase=$true)]
    [string]$Platform,

    [string]$RootPath,

    [string]$ApiProxy,

    [switch]$Install
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
    Write-Host "  Usage:  coreboot <project> <pc|mobile> [-RootPath `"path`"] [-ApiProxy `"domain.tld`"]" -ForegroundColor Cyan
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
$PlatformFolder = if ($Platform.ToLower() -eq "pc") { "PC" } else { "Mobile" }
$ProjectPath = Join-Path $DocsRoot $ProjectName
$PlatformPath = Join-Path $ProjectPath $PlatformFolder
$DistPath = Join-Path $PlatformPath "dist"
$ApiProxyPath = Join-Path $DocsRoot "api-proxy"
$CorePath = Join-Path $DocsRoot "core"

if (-not (Test-Path $ProjectPath)) {
    Write-Host "Project not found: $ProjectPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $PlatformPath)) {
    Write-Host "Platform folder not found: $PlatformPath" -ForegroundColor Red
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
if (-not (Test-Path $DistPath)) {
    New-Item -ItemType Directory -Path $DistPath -Force | Out-Null
}

$CopyDistArgs = if ($Platform.ToLower() -eq "pc") { $ProjectName } else { "$ProjectName mobile" }

Write-Host ""
Write-Host "  Starting dev environment" -ForegroundColor Cyan
Write-Host "  Project:  $ProjectName" -ForegroundColor White
Write-Host "  Platform: $PlatformFolder" -ForegroundColor White
Write-Host "  Root:     $DocsRoot" -ForegroundColor White
Write-Host "  Proxy:    $ResolvedProxy" -ForegroundColor White
Write-Host ""
Write-Host "  [1] GULP RUN     -> git pull && npm i && gulp run ($PlatformPath)" -ForegroundColor Cyan
Write-Host "  [2] CORE         -> git pull && npm run copydist $CopyDistArgs" -ForegroundColor Green
Write-Host "  [3] API-PROXY    -> npm run start -- --host $ResolvedProxy" -ForegroundColor DarkYellow
Write-Host "  [4] BROWSERSYNC  -> browser-sync in $PlatformFolder\dist (http://localhost:3002/html)" -ForegroundColor Magenta
Write-Host ""

# Step 1: GULP RUN - needs to build dist first
Start-Process wt -ArgumentList "--title `"GULP RUN $ProjectName`" --tabColor `"#0097A7`" --suppressApplicationTitle -d `"$PlatformPath`" cmd /k `"git pull & npm i & gulp run`""

$waitSeconds = 15
$HtmlPath = Join-Path $DistPath "html"
Write-Host ""

$elapsed = 0
$spinner = @("|", "/", "-", "\")
$found = $false

while ($elapsed -lt $waitSeconds) {
    $frame = $spinner[$elapsed % 4]
    $bar = "[" + ("=" * $elapsed) + (" " * ($waitSeconds - $elapsed)) + "]"
    $status = if ($found) { "starting app..." } else { "waiting for index.html..." }
    Write-Host ("`r  $frame $bar $elapsed/${waitSeconds}s  $status  ") -NoNewline -ForegroundColor $(if ($found) { "Yellow" } else { "DarkCyan" })

    if (-not $found -and (Test-Path (Join-Path $HtmlPath "index.html"))) {
        $found = $true
    }

    Start-Sleep -Seconds 1
    $elapsed++
}

$finalStatus = if ($found) { "Build ready." } else { "dist/html not found yet - BrowserSync will reload once files appear." }
$finalColor = if ($found) { "Yellow" } else { "Yellow" }
Write-Host ("`r  $(' ' * 60)") -NoNewline
Write-Host "`r  $finalStatus" -ForegroundColor $finalColor
Write-Host ""

# Step 2: CORE - copy dist
Start-Process wt -ArgumentList "-w 0 new-tab --title `"CORE`" --tabColor `"#2E7D32`" --suppressApplicationTitle -d `"$CorePath`" cmd /k `"git pull & npm run copydist $CopyDistArgs`""
Start-Sleep -Milliseconds 1500

# Step 3: API-PROXY
Start-Process wt -ArgumentList "-w 0 new-tab --title `"API-PROXY`" --tabColor `"#D4820A`" --suppressApplicationTitle -d `"$ApiProxyPath`" cmd /k npm run start -- --host $ResolvedProxy"
Start-Sleep -Milliseconds 1000

# Step 4: BROWSERSYNC - launched last so dist is populated
Start-Process wt -ArgumentList "-w 0 new-tab --title `"BROWSERSYNC`" --tabColor `"#7B1FA2`" --suppressApplicationTitle -d `"$DistPath`" cmd /k browser-sync start --server --port 3002 --startPath /html --files **/*.*"

Write-Host "  All 4 tabs launched in Windows Terminal!" -ForegroundColor Green
Write-Host ""
