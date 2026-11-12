# LunchBar agent notes

Menu bar app (Swift 6 package, macOS 14+) showing saved Nutrislice schools and Rutgers FoodPro halls. Repo name is LunchBarApp; app/product is LunchBar, bundle id `io.github.trevor050.LunchBar`.

## Layout
- `Sources/LunchKit`: no UI. `MenuProviding` adapters: Nutrislice (weeks) and `RutgersFoodPro` (one day). FoodPro uses SwiftSoup, serial/paced requests, 100-recipe report batches, lazy labels, and a 30-day recipe+portion cache. Read `docs/research/rutgers-foodpro.md` before changing its parser or request policy. `PickGoal` (Top picks: 7 goals, global setting migrated from `proteinRanking`) rules are in `docs/research/top-picks.md`.
- Existing Nutrislice core: `NutrisliceClient` (public per-district API), `MenuParser` (+ wire DTOs), `MenuCache` (actor, memory + `~/Library/Caches/io.github.trevor050.LunchBar/weeks`), `MenuRepository` (freshness 1h, stale fallback, request coalescing), `LocalDate`, `DayNavigator`, `MenuLink` (district/URL parsing), `Allergens`/`Favorites`.
- Display casing: `DisplayText.normalized` (LunchKit) title-cases provider text that arrives all-caps (FoodPro items and stations) and never touches text with any lowercase. The Rutgers parser applies it to `MenuItem.name`/`category` and `MenuSection.title`; the provider's string is kept in `rawName`/`rawTitle` (`providerName`/`providerTitle`) and `id`s/`foodID`s are built from it. Ranking tie-breaks use `providerName`. Gotcha: `stationExpansion` keys in the view use `section.title`, so they changed from "LUNCH TAKEOUT" to "Lunch Takeout" (collapse state for Rutgers stations reset once).
- Settings retain `source` for migration and selection; `savedPlaces` is keyed by provider/district/hall (meal updates replace a place). FoodPro day cache keys must use exact date, not week start.
- `Sources/LunchBar`: AppKit `AppDelegate` (NSStatusItem + `MenuPanelController`; not MenuBarExtra because the global hotkey must open it), SwiftUI views, `AppSettings` (UserDefaults, JSON-encoded), `HotKey` (Carbon RegisterEventHotKey), `SystemIntegration` (SMAppService login item, UN notifications), `SnapshotRenderer`.
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
- Menu window = borderless non-activating `MenuPanel` (MenuPanel.swift), NOT NSPopover (3 rounds of popover resize fixes failed: detaching, cut-off, 507 guard corrections). Do not reintroduce a popover or a position guard.
  - Position: `PanelGeometry.anchor`. x from status button window midX, clamped to visibleFrame. y NEVER from the button: owner's menu bar auto-hides (`_HIHideMenuBar=1`), hidden status window sits above the screen (y=900/932 on a 900pt screen). Top = visibleFrame.maxY if bar shown, else screen.maxY - statusWindow.height (30 on macOS 26; `NSStatusBar.thickness` says a stale 22). While open, only horizontal icon moves / screen changes re-anchor.
  - Height: PanelView reports chrome + ScrollView-content heights via preferences (content inside ScrollView = unconstrained, so window size can't feed back). `hosting.sizingOptions = []` is required. One coalesced resize per run-loop turn, top fixed, 0.18 s animation (none with Reduce Motion). Loading state reuses `model.lastContentHeight` so a day change = 1 resize.
  - Expanded items get a banner only if `ImageStore.isPhoto` (>=320 px); clip art keeps the thumbnail. ImageStore is @Observable so rows update when a photo loads (unobserved state broke the height check once).
  - Focus: panel normally becomes key without activating. Fallback `activate(ignoringOtherApps:)` only inside show(); close() yields activation back to the previous app.
- `--self-test-panel N [--no-animation] [--right-edge]`: real status item + panel; checks top/x fixed, inside visibleFrame, height == clamp(independent offscreen measure `PanelMeasure`), resizes <= content arrivals, monotonic animation frames, plus arrow/Escape/highlight/toggle via NSApp.sendEvent. Uses defaults suite `LunchBarPanelSelfTest` and skips hotkey/notifier (bundle shares the owner's notification center; `checkFavorites` with notifications off calls `removeAll`). It takes key focus and steals the owner's typing: NEVER run it while he uses the Mac (he complained). Prefer PanelGeometryTests + offscreen renders. Run builds/tests serially: fanless 8 GB machine.
- Week cache has `CachedWeek.format` (currently 2). Bump `currentFormat` when parsed menu output changes so old disk copies are refetched.
- macOS has no Dynamic Type for 3rd-party apps; text uses `scaledFont(_:)` with the app's Text Size setting.
- Legacy 1.x config (`~/Library/Application Support/LunchBarApp/config.env`, `~/.lunchbar.env`, env vars) is imported once when no source is set.
- Don't build API URLs with `URL.appending(path:)`: trailing-slash handling differs between macOS 15 and 26 SDKs (CI on macos-15 produced `schools//`). `NutrisliceClient` concatenates strings.
- CI is macos-15 / Xcode 16.4 / Swift 6.1, stricter about non-Sendable SDK types (UserNotifications) than local Swift 6.2. Use completion-handler APIs there.

## Rutgers verification
- Current official Rutgers links now use Nutrislice; all four halls including The Atrium are in its catalog. Verified older FoodPro IDs: 03/04/05 only.
- FoodPro form tokens require recipe*portion*station; nutrition cache identity is recipe*portion. Fractions occur. HTTP 200 does not prove a successful report.
- `--render-snapshots docs/shots rutgers-foodpro 04 Lunch YYYY-MM-DD --matrix` exercises three halls, lunch/dinner, that day/next, warm reopens, then Middlesex. `--goal GOAL`, `--protein-lean`, `--avoid-milk`, `--expand TEXT`, `--settings`, `--text-size large|extraLarge`, `--full` (uncapped height) render other real states. `--high-contrast` uses the HC appearances but SwiftUI takes contrast from the system, so it looks the same; not a real contrast check.
- Nutrition-load generations need checking after every actor hop; stale tasks must not repaint a newly selected source/date.
