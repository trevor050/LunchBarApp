# LunchBar agent notes

Menu bar app (Swift 6 package, macOS 14+) showing any Nutrislice school's menu. Repo name is LunchBarApp; app/product is LunchBar, bundle id `io.github.trevor050.LunchBar`.

## Layout
- `Sources/LunchKit`: no UI. `NutrisliceClient` (public per-district API), `MenuParser` (+ wire DTOs), `MenuCache` (actor, memory + `~/Library/Caches/io.github.trevor050.LunchBar/weeks`), `MenuRepository` (freshness 1h, stale fallback, request coalescing), `LocalDate`, `DayNavigator`, `MenuLink` (district/URL parsing), `Allergens`/`Favorites`.
- `Sources/LunchBar`: AppKit `AppDelegate` (NSStatusItem + NSPopover; not MenuBarExtra because the global hotkey must open it), SwiftUI views, `AppSettings` (UserDefaults, JSON-encoded), `HotKey` (Carbon RegisterEventHotKey), `SystemIntegration` (SMAppService login item, UN notifications), `SnapshotRenderer`.
- `Tests/LunchKitTests`: Swift Testing, fixtures are raw API responses (schools fixture stripped of address/phone).

## Commands
- Tests: `scripts/test.sh` (adds CLT flags: `-F` to CLT Frameworks + `-disable-cross-import-overlays`, because CLT lacks the `_Testing_Foundation` overlay module). Plain `swift test` only works with full Xcode.
- App: `scripts/build-app.sh [--universal] [--version X]` -> `dist/LunchBar.app` + zip, ad-hoc signed. `--universal` needs Xcode (CLT can't multi-arch).
- README images: `.build/debug/LunchBar --render-snapshots <dir> <district> <school> <type> <yyyy-mm-dd> [--steps N] [--offline] [--offline-cold] [--avoid-milk] [--settings]`. Renders real views offscreen with live data; works with a locked screen.
- Release: push `v*` tag -> `.github/workflows/release.yml`. Never push tags without Trevor.

## API facts (verified 2026-11)
- Base `https://{district}.api.nutrislice.com/menu/api/`: `schools/`, `settings/?format=json` (district_name), `weeks/school/{s}/menu-type/{t}/{y}/{m}/{d}/` returns Sun–Sat week.
- Week `start_date` is the first school day (Monday), NOT Sunday. Week start is computed from day dates.
- `menu_items[].id` is usually int but composite smart-recipe entries are strings like `"1,2,3-sr11148-foods"`. Ids are `String` in the model.
- Icons: `food_icons` behavior 1/is_filter = allergens ("Milk", "May contain Soy", "Processed in a facility..."); behavior 2/is_highlight = dietary (Vegan, Vegetarian, Halal). `myplate_icons` = food groups.
- Holidays: text rows with `is_holiday: true` (e.g. "Thanksgiving"). Text rows on food days are connectors ("or"); UI hides notes when there's food.
- Vitamin D key is `mcg_vitamin_d`.
- Unknown district -> DNS failure (`cannotFindHost`) -> `districtNotFound`.
- `sat_enabled`/`sun_enabled` on schools are unreliable (dining halls that serve daily say false), hence the user "Skip weekends" setting.
- District search (`api.nutrislice.com/accounts/api/orgs/lookup/`) requires a reCAPTCHA token. Do not use it; link to lookup.nutrislice.com instead.

## Hazards
- `UNUserNotificationCenter.current()` throws/crashes outside an .app bundle; gate on `isRunningFromAppBundle`.
- Popover size is fixed (`PopoverView.size`) on purpose; resizing re-anchors NSPopover and jumps.
- macOS has no Dynamic Type for 3rd-party apps; text uses `scaledFont(_:)` with the app's Text Size setting.
- Legacy 1.x config (`~/Library/Application Support/LunchBarApp/config.env`, `~/.lunchbar.env`, env vars) is imported once when no source is set.
- Don't build API URLs with `URL.appending(path:)`: trailing-slash handling differs between macOS 15 and 26 SDKs (CI on macos-15 produced `schools//`). `NutrisliceClient` concatenates strings.
- CI is macos-15 / Xcode 16.4 / Swift 6.1, stricter about non-Sendable SDK types (UserNotifications) than local Swift 6.2. Use completion-handler APIs there.
