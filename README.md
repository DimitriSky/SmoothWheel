# SmoothWheel

Smooth mouse-wheel scrolling for macOS. A native menu bar app with adjustable speed and inertia.

- Vertical and horizontal scrolling
- Per-app exclusions
- Optional reverse scrolling
- Pause and launch at login
- Preserves native trackpad scrolling

## Build

Requires macOS 13+ and Xcode or Command Line Tools with Swift 5.9+.

From the repository root:

```sh
bash scripts/build-app.sh
open dist/SmoothWheel.app
```

## Usage

1. Enable **SmoothWheel** in **System Settings → Privacy & Security → Accessibility**.
2. Use the mouse icon in the menu bar to adjust speed, inertia, and app exclusions.

## Tests

```sh
swift test
```
