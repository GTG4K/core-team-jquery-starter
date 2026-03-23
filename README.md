# coreboot

Dev environment bootstrapper for our core team. One command spins up all four services, and you can hot-switch between PC and Mobile without restarting.

## What it does

1. **Gulp** - pulls latest code, installs dependencies, runs the build
2. **Core** - pulls latest code, copies dist to the project
3. **API Proxy** - starts the local proxy server
4. **BrowserSync** - serves the built site at `http://localhost:3002/html` with live reload

The script waits up to 15 seconds for the initial Gulp build to produce output before launching the remaining services, so BrowserSync doesn't open to a blank page.

On first run (no `dist/` folder detected), the script automatically runs `npm install` in the platform directory before starting services.

## Interactive Dashboard

Once all services are running, coreboot displays a live dashboard with a platform toggle:

```
  ────────────────────────────────────────────────────────────
  coreboot  -  myproject (PC)
  ────────────────────────────────────────────────────────────

  ▶  Gulp Build        pull + compile (PC)
  ▶  Core Copydist     pull + copydist myproject
  ▶  API Proxy         proxying to myproject.com
  ▶  BrowserSync       http://localhost:3002/html (live-reload)

  ────────────────────────────────────────────────────────────
  Platform:   PC    Mobile
  Press [P] to switch platform   Ctrl+C to stop all
  ────────────────────────────────────────────────────────────
```

| Key        | Action                                                                                         |
| ---------- | ---------------------------------------------------------------------------------------------- |
| `P`        | Toggle between PC and Mobile. Stops Gulp, Core, and BrowserSync, restarts them for the new platform. API Proxy stays running. |
| `Ctrl+C`   | Gracefully stops all four services and exits.                                                  |

The active platform is highlighted in the toggle. Switching takes about 1-2 seconds — the old platform-specific processes are killed and new ones are spawned with the correct paths.

## Prerequisites

- Windows (PowerShell 5.1+)
- [Node.js](https://nodejs.org/) **v14 or lower** and npm on PATH
- [Git](https://git-scm.com/) on PATH
- Global npm packages: `gulp-cli`, `browser-sync` (auto-installed if missing)

### Expected folder structure

All repos should live under the same root folder (defaults to your Documents folder):

```
Documents/
  api-proxy/
  core/
  <project>/
    PC/
      dev/
      dist/
      gulpfile.js
    Mobile/
      dev/
      dist/
      gulpfile.js
```

The script itself is installed to `%LOCALAPPDATA%\coreboot\` (e.g. `C:\Users\<you>\AppData\Local\coreboot\`) so it won't be affected if you move or delete the original download.

## Installation

Double-click `install-coreboot.cmd`. This will:

1. Copy `coreboot.ps1` to `%LOCALAPPDATA%\coreboot\`
2. Create a `coreboot.cmd` wrapper in the same folder
3. Add the folder to your user PATH

No PowerShell profile changes are needed — works with Symantec/endpoint protection policies.

Restart your terminal after installing.

### What gets saved where

| File                                            | Purpose                                  |
| ----------------------------------------------- | ---------------------------------------- |
| `%LOCALAPPDATA%\coreboot\coreboot.ps1`          | The main script                          |
| `%LOCALAPPDATA%\coreboot\coreboot.cmd`          | CMD wrapper so you can type `coreboot`   |
| `%LOCALAPPDATA%\coreboot\rootpath-map.json`     | Persisted root path setting              |
| `%LOCALAPPDATA%\coreboot\proxy-map.json`        | Persisted API proxy mappings per project |

## Usage

```powershell
coreboot <project> <platform> [-RootPath "path"] [-ApiProxy "domain.tld"]
```

| Argument    | Required | Description                                                       |
| ----------- | -------- | ----------------------------------------------------------------- |
| `project`   | Yes      | Project folder name (e.g. `goldenbet`, `donbet-co`)               |
| `platform`  | Yes      | `pc` or `mobile`                                                  |
| `-RootPath` | No       | Override the root folder (defaults to Documents). Saved globally for future runs. |
| `-ApiProxy` | No       | Custom api-proxy host (e.g. `donbet.co`). Saved per project for future runs.      |

When `-RootPath` is provided, the value is saved to `%LOCALAPPDATA%\coreboot\rootpath-map.json` so future runs will reuse it automatically. If omitted and no saved path exists, the default Documents folder is used.

When `-ApiProxy` is provided, the value is saved to `%LOCALAPPDATA%\coreboot\proxy-map.json` so future runs of the same project will reuse it automatically. If omitted and no saved mapping exists, the default `<project>.com` is used.

### Examples

#### Basic usage

```powershell
# PC project — uses Documents as root, api-proxy defaults to goldenbet.com
coreboot goldenbet pc

# Mobile project
coreboot goldenbet mobile
```

#### Custom root path (`-RootPath`)

```powershell
# First time: set root to Desktop\Projects (saved for all future runs)
coreboot goldenbet pc -RootPath "$HOME\Desktop\Projects"

# Every run after this uses Desktop\Projects automatically — no flag needed
coreboot goldenbet pc
coreboot donbet-co mobile

# Override with a different path (updates the saved value)
coreboot goldenbet pc -RootPath "D:\Work"
```

#### Custom API proxy (`-ApiProxy`)

```powershell
# First time: set proxy for donbet-co (saved per project)
coreboot donbet-co mobile -ApiProxy "donbet.co"

# Every run of donbet-co after this reuses donbet.co — no flag needed
coreboot donbet-co mobile

# Other projects are not affected — goldenbet still defaults to goldenbet.com
coreboot goldenbet pc
```

#### Combining both

```powershell
# Set root path and api-proxy in one go
coreboot donbet-co mobile -RootPath "$HOME\Desktop\Projects" -ApiProxy "donbet.co"

# Future runs need neither flag
coreboot donbet-co mobile
```

#### How saved values work

| Scenario                   | Root path used              | API proxy used                    |
| -------------------------- | --------------------------- | --------------------------------- |
| First run, no flags        | Documents                   | `<project>.com`                   |
| `-RootPath` provided       | The path you gave (saved)   | `<project>.com`                   |
| `-ApiProxy` provided       | Documents                   | The proxy you gave (saved)        |
| Later run, no flags        | Last saved root path        | Last saved proxy for that project |
| `-RootPath` provided again | New path (overwrites saved) | Last saved proxy for that project |

## Switching Platforms at Runtime

You don't need to stop and restart the script to switch between PC and Mobile. While the dashboard is running, press **`P`** to toggle.

What happens under the hood:

1. The three platform-specific services (Gulp, Core copydist, BrowserSync) are killed via `taskkill`
2. Path variables update to point at the other platform folder (`PC/` or `Mobile/`)
3. New Gulp, Core, and BrowserSync processes are spawned with the updated paths
4. The API Proxy stays running — it's platform-independent

Both platform folders (`PC/` and `Mobile/`) must exist under the project directory for switching to work. If the target folder is missing, the switch is cancelled and an error is shown.

## Startup Sequence

1. **Validation** - checks Node version (must be v14 or lower), verifies all required folders exist
2. **Auto-install** - installs `gulp` and `browser-sync` globally if missing; runs `npm install` on first run
3. **Gulp build** - starts Gulp in a separate terminal window; waits up to 15s with a progress bar for `dist/html/index.html` to appear
4. **Core copydist** - starts core's `copydist` in a separate terminal window
5. **API Proxy** - starts the proxy server in a separate terminal window
6. **BrowserSync** - starts live-reload server at `http://localhost:3002/html`
7. **Dashboard** - clears the terminal and shows the interactive dashboard with platform toggle

Pressing `Ctrl+C` at any point gracefully terminates all spawned processes.
