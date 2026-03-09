param(
    [Parameter(Position=0)]
    [string]$ProjectName,

    [Parameter(Position=1)]
    [ValidateSet("pc", "mobile", IgnoreCase=$true)]
    [string]$Platform,

    [Parameter(Position=2)]
    [string]$RootPath,

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
    Write-Host "    coreboot <project> <pc|mobile> [rootpath]" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

if (-not $ProjectName -or -not $Platform) {
    Write-Host ""
    Write-Host "  Usage:  coreboot <project> <pc|mobile> [rootpath]" -ForegroundColor Cyan
    Write-Host "  Install: .\bootstrap.ps1 -Install" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

$DocsRoot = if ($RootPath) { $RootPath } else { [Environment]::GetFolderPath("MyDocuments") }
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
Write-Host ""
Write-Host "  [1] GULP RUN     -> git pull && npm i && gulp run ($PlatformPath)" -ForegroundColor Cyan
Write-Host "  [2] CORE         -> git pull && npm run copydist $CopyDistArgs" -ForegroundColor Green
Write-Host "  [3] API-PROXY    -> npm run start -- --host $ProjectName.com" -ForegroundColor DarkYellow
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
Start-Process wt -ArgumentList "-w 0 new-tab --title `"API-PROXY`" --tabColor `"#D4820A`" --suppressApplicationTitle -d `"$ApiProxyPath`" cmd /k npm run start -- --host $ProjectName.com"
Start-Sleep -Milliseconds 1000

# Step 4: BROWSERSYNC - launched last so dist is populated
Start-Process wt -ArgumentList "-w 0 new-tab --title `"BROWSERSYNC`" --tabColor `"#7B1FA2`" --suppressApplicationTitle -d `"$DistPath`" cmd /k browser-sync start --server --port 3002 --startPath /html --files **/*.*"

Write-Host "  All 4 tabs launched in Windows Terminal!" -ForegroundColor Green
Write-Host ""
