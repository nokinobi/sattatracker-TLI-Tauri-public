# TLI-Sattatracker (nokinobi fork)

A fork of [sattatrapy/sattatracker-TLI-Tauri-public](https://github.com/sattatrapy/sattatracker-TLI-Tauri-public), the transparent overlay that tracks loot, expenses and profit per map in Torchlight Infinite. Each release of this fork is the original project's latest version plus a selection of extra features.

## Download

Get the installer from the [releases](https://github.com/nokinobi/sattatracker-TLI-Tauri-public/releases). Use the `-setup.exe` (setup wizard) or the `.msi`. The installer is not code-signed, so Windows SmartScreen shows a warning, and the app asks for administrator rights when it starts.

Releases marked **Pre-release** are development builds; the others are ready versions. Each release has notes in [`docs/release/versions/`](../docs/release/versions/), and the [release process](../docs/release/RELEASING.md#versions) explains the version numbers.

This fork uses the original app ID, so installing it replaces the original tracker and keeps its settings.

## Features added in this release

<!-- features:start -->
- [Compact Window](../docs/features/compact-window.md) - One small, click-through window with profit per hour, the current map's profit and timer, and the map's loot.
<!-- features:end -->

Everything else, such as setup, hotkeys, prices and assets, works as described in the original project's [README](../README.md).

## For contributors

- [How releases are built](../docs/release/RELEASING.md): branches, picking features for a release, syncing with the original project.
- Feature specs live in [`docs/features/`](../docs/features/) on each feature branch.

## Credits and license

Original project by [sattatrapy](https://github.com/sattatrapy), MIT License. This fork keeps the same [license](../LICENSE).
