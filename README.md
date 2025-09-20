# LunchBarApp

Lightweight macOS menu bar app for checking your Nutrislice lunch menu without opening a browser. The app stays idle until you click the fork/knife icon (or press the global shortcut), fetches the latest menu for the selected day, and lets you browse previous/next days.

## Features
- Menu bar resident widget – no dock icon, minimal resource usage.
- Global shortcut (`⌘⇧L`) to open/close the popover instantly.
- Smooth day navigation with cached layout (no window jumps).
- Graceful handling of items without images.
- Environment-based configuration so you can point to any Nutrislice-supported school without editing code.
- Polished Finder/Spotlight icon for easier discovery.

## Requirements
- macOS 13 Ventura or newer (Apple Silicon).
- Xcode 15+ or matching Command Line Tools for SwiftUI builds.

## Setup
1. Clone or download the repository:
   ```bash
   git clone https://github.com/<your-user>/LunchBarApp.git
   cd LunchBarApp
   ```
2. Create a configuration by copying `.env.example` to wherever you prefer:
   ```bash
   cp .env.example .env  # or ~/.lunchbar.env
   ```
   Then edit the file and supply your district details:
   ```env
   NUTRISLICE_ORIGIN="https://district.api.nutrislice.com"
   NUTRISLICE_SCHOOL_SLUG="high-school"
   NUTRISLICE_MENU_TYPE="lunch"
   ```
   > You can also skip the file and export the same variables in your shell before launching the app.
   > The installer copies `.env` into `~/Library/Application Support/LunchBarApp/config.env`, which the bundled app reads automatically.
3. Build a release binary:
   ```bash
   swift build -c release
   ```
4. Launch the menu bar app:
   ```bash
   .build/release/LunchBarApp &
   ```
   (or double-click the `.app` bundle described below.)

The first launch asks for network permission. Afterwards the app lives in the menu bar and responds to `⌘⇧L`.

## Install the App Bundle
Run the helper script to build, assemble a `.app`, and copy it into `~/Applications` for easy launching via Spotlight/Finder:
```bash
scripts/install.sh
```
If a `.env` file is present in the project root it will be synced to
`~/Library/Application Support/LunchBarApp/config.env`. You can then drag
the app to the Dock or assign macOS shortcuts as usual.

## Packaging for a Release
To publish a binary for a GitHub release:
```bash
scripts/package.sh
```
That produces `dist/LunchBarApp-macos-arm64.zip` ready for upload.

## Customising for Other Schools
If your district uses Nutrislice you can locate the required slugs by opening the Nutrislice URL in a browser:
```
https://<district>.nutrislice.com/menu/<school-slug>/<menu-type>/<YYYY-MM-DD>
```
- `NUTRISLICE_ORIGIN` is typically `https://<district>.api.nutrislice.com`.
- `NUTRISLICE_SCHOOL_SLUG` is the `<school-slug>` segment.
- `NUTRISLICE_MENU_TYPE` is the menu type (e.g. `lunch`, `breakfast`).


## Development Notes
- Global shortcut uses `⌘⇧L` via Carbon’s hotkey API. Adjust the key in `Sources/HotKeyManager.swift` if needed.
- Default popover size is fixed (280×240) to avoid macOS reposition glitches; tweak in `LunchMenuView`.
- Images fetch lazily with `AsyncImage`, showing a fork/knife placeholder when missing.

## License
MIT
