# Portly

https://github.com/user-attachments/assets/dd41fca5-b6ad-43c5-bbcf-1236241b7b6a

A macOS menu bar widget that shows every dev server you've started with a package manager — `bun`, `npm`, `pnpm` or `yarn` running a `dev`, `start`, `serve`, `preview` or `develop` script (or variants like `dev:api`) — with the ports it listens on, the project folder, the script and uptime. Open one in the browser, Finder or your terminal, or stop it.

Requires macOS 14 (Sonoma) or later.

## Install

```sh
brew install --cask code7551/portly/portly
open -a Portly
```

After the first launch it starts at login (turn that off in its ⋯ menu). The cask also links a `portly` command.

To uninstall:

```sh
portly --remove-login-item
brew uninstall --cask code7551/portly/portly
```

## Use

| Key | Action |
| --- | --- |
| ⌃⌥B (global) | open / close Portly |
| ↑ ↓ | select |
| click a row, ↩ or → | slide to the server's page: ports, path, command, uptime; open the site (↩), the folder in Finder (F) or your terminal (T), or Stop Server |
| ‹ Back, esc or ← | back to the list |
| click the port badge | open `http://localhost:<port>` directly |
| ⌘R / ⌘Q / esc | refresh / quit / close |

Stopping has no shortcut on purpose: it's the Stop Server button on a server's page (or "Stop All…" in the ⋯ menu, or right-click → Stop Server…), always followed by a confirmation. Stopping sends SIGTERM to the whole process tree (the package manager and the next/vite/node processes under it), then SIGKILL to anything still alive after 3 s.

The panel is placed under the icon's position rather than attached to it, so it opens in the right place even with an auto-hiding menu bar or from a full-screen space.

## CLI

```sh
portly --list            # what Portly sees: pid, ports, folder, script, path
portly --kill <pid>      # stop one server's process tree
portly --toggle          # open / close the panel (for other launchers)
portly --remove-login-item
```

## Build from source

```sh
./build.sh install   # build for this Mac, copy to /Applications, relaunch
./build.sh dist      # universal zip + sha256 for a release
```

No Xcode project — just `swiftc` (Xcode or the Command Line Tools).

Releasing: bump `VERSION`, run `./build.sh dist`, tag `v<version>`, attach `build/Portly-<version>.zip` to a GitHub release, and put the printed sha256 and version in `Casks/portly.rb`.
