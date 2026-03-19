# coreboot

Dev environment bootstrapped for our core team

## What it does

1. **Gulp** - pulls latest code, installs dependencies, runs the build
2. **Core** - pulls latest code, copies dist to the project
3. **API Proxy** - starts the local proxy server
4. **BrowserSync** - serves the built site at `http://localhost:3002/html` with live reload

The script waits 15seconds for gulp to finish building before launching the rest, so BrowserSync doesn't open to a blank page.

## Prerequisites

- [Windows Terminal](https://aka.ms/terminal) installed
- [Node.js](https://nodejs.org/) and npm on PATH
- [Git](https://git-scm.com/) on PATH
- Global npm packages: `gulp-cli`, `browser-sync`

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

### Run the install-coreboot.cmd file

Double-click `install-coreboot.cmd`. This will:

1. Copy the script to `%LOCALAPPDATA%\coreboot\`
2. Create a `coreboot.cmd` wrapper in the same folder
3. Add the folder to your user PATH

No PowerShell profile changes are needed — works with Symantec/endpoint protection policies.

Restart your terminal after installing.

## Usage

```powershell
coreboot <project> <platform> [-RootPath "path"] [-ApiProxy "domain.tld"]
```

| Argument    | Required | Description                                                       |
| ----------- | -------- | ----------------------------------------------------------------- |
| `project`   | Yes      | Project folder name (e.g. `goldenbet`, `donbet-co`)               |
| `platform`  | Yes      | `pc` or `mobile`                                                  |
| `-RootPath` | No       | Override the root folder (defaults to Documents). Saved globally. |
| `-ApiProxy` | No       | Custom api-proxy host (e.g. `donbet.co`). Saved per project.      |

When `-RootPath` is provided, the value is saved to `%LOCALAPPDATA%\coreboot\rootpath-map.json` so future runs will reuse it automatically. If omitted and no saved path exists, the default Documents folder is used.

When `-ApiProxy` is provided, the value is saved to `%LOCALAPPDATA%\coreboot\proxy-map.json` so future runs of the same project will reuse it automatically. If omitted and no saved mapping exists, the default `<project>.com` is used.

### Examples

```powershell
# Standard usage (api-proxy uses goldenbet.com)
coreboot goldenbet pc

# Custom api-proxy (saves donbet-co -> donbet.co for future runs)
coreboot donbet-co mobile -ApiProxy "donbet.co"

# Next time, no need to pass -ApiProxy again
coreboot donbet-co mobile

# Set a custom root folder (saved for future runs)
coreboot goldenbet pc -RootPath "$HOME\Desktop\Projects"

# Next time, no need to pass -RootPath again
coreboot goldenbet pc
```
