# Rutgers verification

All work ran on this Mac. No other machine was contacted for execution, and no release or tag was created.

- `scripts/test.sh`: **52 tests in 12 suites passed**, including the original 35 tests. New checks cover real FoodPro HTML from three halls/two meals, out-of-window fallback, labels/reports, both ranking modes, exclusions/ties/missing data, saved UserDefaults migration, menu cache isolation, persistent/expired nutrition, backoff, request coalescing, serialized different-label loads, and allergen-gated progressive view-model behavior.
- `scripts/build-app.sh`: arm64 release app built and ad-hoc signature verified. SwiftSoup's MIT notice is bundled in Resources.
- The built app's `--render-snapshots ... --matrix` mode ran real menus for **November 11 and 12**, Livingston/Busch/Neilson, lunch/dinner. All **12 combinations** had populated menus and five ranked choices, and every warm reopen made **0 requests**. It then switched back to Middlesex High; four saved places were retained. See `rutgers-live/live-matrix.json` and its 13 rendered real views. The combined matrix made 27 menu/report calls, sharing recipe nutrition across places and dates.
- The Atrium's current official Nutrislice menu also loaded: 174 items on November 10, with a nonempty protein group. See `rutgers-atrium/`.
- Independent Busch lunch cold/warm measurement: **3 / 0 requests** for 141 items on November 10 (one menu GET and two report POSTs). Milk-avoidance example on November 11: **12 / 0** for menu plus ranking, before manual detail expansion. Cost depends on how many candidate labels must be checked. See `rutgers-requests.json`.
- The five leading Busch lunch choices on November 10 were compared directly with five public label pages. All protein values agreed within the label's one-decimal rounding, and calories matched. URLs and values are in `rutgers-label-check.json`.
- Looked at real offscreen renders for per-serving and lean rankings, the Atrium, settings, a pending report, a filtered/expanded label, and all hall/meal/day matrix states. `--loading` delays the real report transport to hold the actual pending UI state. These are **offscreen renders using the existing snapshot mode**, not a screen recording or a live click-through.

Reproduce the final matrix:

```bash
dist/LunchBar.app/Contents/MacOS/LunchBar --render-snapshots docs/verification/rutgers-live rutgers-foodpro 04 Lunch 2026-11-11 --matrix
```

The popover-based window these runs originally used has since been replaced by an app-positioned panel; see `panel.md` for its verification. The final app is left running from `dist/LunchBar.app`.

## Scope adjustment and limits

Rutgers' current official homepage now directs all four halls to Nutrislice. The app therefore offers both the current Rutgers catalog and the three verified FoodPro IDs. The Atrium is available through the current catalog; no older FoodPro ID was verified or guessed. FoodPro's layout, host, forms and publication window can change without notice. See `../research/rutgers-foodpro.md`.

The ingredient exclusion is a documented station/portion heuristic, not a guarantee about whether an item constitutes an entree. It never hides an item from the full menu, and retains ordinary entree stations, EACH/SLICE servings and portions over 2 OZ. Unpublished allergen information and cross-contact remain limits of the university's data.
