# Codex Pet Energy

Codex Pet Energy is a lightweight macOS menu-bar companion that shows live Codex usage beside the floating Codex Pet.

This is an independent community project and is not affiliated with or endorsed by OpenAI.

Move the pointer over your Pet to reveal a compact Apple-style glass panel with the remaining 5-hour and weekly usage limits. The panel follows the Pet while it is dragged and disappears when the pointer leaves.

## Features

- Live 5-hour and weekly Codex usage percentages
- Per-second reset countdowns
- Native macOS glass material and SF system typography
- Hover-to-show and automatic dismissal
- Smooth Pet drag following across displays and Spaces
- Automatic left/right placement near screen edges
- Click-through overlay that never blocks the Pet or desktop
- Menu-bar controls for refresh, enable/disable, Launch at Login, and quit
- Automatic Launch at Login registration on first run
- Automatic app-server reconnect with periodic usage refresh
- No API key and no direct credential access

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- ChatGPT/Codex desktop app installed and signed in
- Codex Pet enabled and visible

## Install a release

1. Download the latest `Codex-Pet-Energy-*-macos-arm64.zip` from [Releases](../../releases).
2. Unzip it and move **Codex Pet Energy.app** to `/Applications`.
3. Right-click the app and choose **Open** the first time.
4. If macOS blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway**.

The downloadable build is ad-hoc signed. A future notarized build will remove the first-launch Gatekeeper step.

## Build from source

```sh
git clone https://github.com/skyslab-dev/codex-pet-energy.git
cd codex-pet-energy
swift test
./scripts/build-app.sh
open "dist/Codex Pet Energy.app"
```

The build script creates an ad-hoc-signed application at:

```text
dist/Codex Pet Energy.app
```

## How it works

The app launches the local Codex `app-server` process and reads its `account/rateLimits/read` protocol response. It tracks the floating Pet window through macOS window metadata and uses the Pet geometry stored by Codex to place the companion panel.

The menu-bar companion stays dormant when Codex is not running. On first run, it registers for Launch at Login so it is already available whenever Codex and Codex Pet start. Launch at Login can be disabled from the menu-bar controls at any time.

Usage data stays on the Mac. The app does not read `auth.json`, store credentials, send analytics, or contact a separate third-party service.

## Development

Run the test suite:

```sh
swift test
```

Run strict concurrency diagnostics:

```sh
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency
```

The current suite covers usage parsing, limit selection, countdown formatting, screen-edge placement, multi-display coordinate conversion, and Codex Pet state parsing.

## Compatibility note

Codex Pet and `app-server` integration details may change in future desktop releases. The app is designed to fail safely: it hides the overlay, keeps credentials untouched, and reconnects when the local service becomes available again.

## License

MIT — see [LICENSE](LICENSE).
