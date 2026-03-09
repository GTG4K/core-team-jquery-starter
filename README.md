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

The script itself is installed to a fixed location (`C:\tools\coreboot\coreboot.ps1`) so it won't be affected if you move or delete the original download.

## Installation

### Run the install-coreboot.cmd file

Double-click `install-coreboot.cmd`. This will:

1. Copy the script to `C:\tools\coreboot\`
2. Register the `coreboot` command in your PowerShell profile

Restart your terminal after installing.

## Usage

```powershell
coreboot <project> <platform> [rootpath]
```

| Argument   | Required | Description                                      |
| ---------- | -------- | ------------------------------------------------ |
| `project`  | Yes      | Project folder name (e.g. `goldenbet`, `donbet`) |
| `platform` | Yes      | `pc` or `mobile`                                 |
| `rootpath` | No       | Override the root folder (defaults to Documents) |

### Examples

```powershell
# Standard usage
coreboot goldenbet pc
coreboot donbet mobile

# Projects in a custom folder
coreboot goldenbet pc -RootPath "D:\Projects"
```
