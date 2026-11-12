# Rutgers source, verified November 10, 2026

Rutgers New Brunswick's [Dining homepage](https://food.rutgers.edu/) now links **all four dining locations to Nutrislice**. Following the public redirects reached `rutgers.nutrislice.com` for Busch Dining Hall, Livingston Dining Commons, Neilson Dining Hall and The Atrium. The public Rutgers schools endpoint lists those same four locations and their current meal names. No additional New Brunswick locations appeared in that catalog. The app's Rutgers current-menu option loads it dynamically.

The older [FoodPro portal](https://menuportal23.dining.rutgers.edu/foodpronet/pickmenu.aspx?sName=Rutgers+University+Dining&locationNum=04&locationName=Busch+Dining+Hall&naFlag=1) still serves menus. Confirmed IDs: **03 Livingston, 04 Busch, 05 Neilson**. The old Atrium shortcut redirects to Nutrislice; no Atrium FoodPro ID was verified. The app offers the three confirmed FoodPro halls and The Atrium through Rutgers' current catalog, without guessing an ID.

## Access, dates, meals and stations

`https://menuportal23.dining.rutgers.edu/robots.txt` returned **404**. The FoodPro footer links no scraping terms; [Dining policies](https://food.rutgers.edu/policies) describes operations rather than machine access or an API license. Only public unauthenticated requests were used. The `/foodpronet/` directory returned 403 and was not pursued. Public `picklocation.aspx` and `default.aspx` returned 500 and supplied no catalog.

Menu GETs use `pickmenu.aspx`, `sName`, `locationNum`, `locationName`, `dtdate=M/D/YYYY`, and `activeMeal`. Observed meal links: **Breakfast, Lunch, Dinner, Late Knight**. Takeout also appears as a station within meals. The form action confirms the actual meal; unknown meals can silently fall back to breakfast, so a mismatch is rejected.

The date dropdown advertised **November 10–16**, seven days at observation time. This is an observed window, not a promise. November 26 returned populated HTML even though Rutgers says dining is closed then. The parser requires the requested date to be in the dropdown before showing any items.

Stations are `<h3>` elements inside `.menuBox`, followed by item `<fieldset>` blocks. They become LunchKit sections. Each item carries a `recipe*portion*station` form token; labels use `RecNumAndPort=recipe*portion`. Portions include fractions, and recipes repeat across stations.

## Nutrition report and labels

The pages are server-rendered HTML. No menu/nutrition JSON endpoint was found in their scripts. The public “Create Nutrition Report” form posts repeated `recipe` and `QTY=1` fields to `nutRpt.aspx`, with hall, date and meal parameters. It returns **individual recipe nutrients plus meal totals**. LunchBar parses individual rows only.

The exact three-part form token is required. Sending just recipe and portion returns HTTP 200 with truncated recipe IDs. A live check caught this and the request test now checks the station suffix.

Report fields include protein, calories, total/saturated/trans fat, carbohydrate, fiber, sugars/added sugars, sodium, cholesterol, calcium and iron. Dashes mean unavailable, not zero. Reports omit ingredients and allergens. `label.aspx` contains those, serving size, calories and nutrients, plus Rutgers' accuracy and cross-contact disclaimer. The recorded eggs label says **4 OZ, 141 cal, 11.1 g protein**, with Milk, Eggs and Soybeans. Malformed markup can put ingredient/allergen paragraphs outside the nutrition container after HTML repair; explicit prefixes identify them.

Reports use serial batches of at most 100 distinct recipe/portion identifiers. Labels load on expansion, or in ranking order when avoided allergens require checking top candidates. Unchecked labels cannot enter Top protein when an avoided allergen is selected. That can require more than five labels if candidates are excluded.

## Fragility and request policy

**This is HTML, not an API contract.** Hostnames, selectors, fields, tokens and meal names can change without notice. SwiftSoup tolerates malformed markup and entities; required fields and returned recipe IDs are validated. Changed/error pages fail instead of quietly becoming a closed day.

Menus cache per provider/hall/meal/date for one hour, with stale fallback. Nutrition caches by recipe **and portion** for 30 days. FoodPro requests share a serial queue, 350 ms spacing, and an honest LunchBar/repository User-Agent. HTTP/network failures back off exponentially from 30 seconds, respecting numeric Retry-After up to an hour. There is no automatic retry timer or FoodPro background notification fetch.

Fixtures and their public URLs are in `Tests/LunchKitTests/Fixtures/Rutgers/provenance.json`; `scripts/record-rutgers.py` reproduces the serial capture. The empty fixture preserves the misleading out-of-window response so its rejection stays tested. Live request counts and hand-checked rankings are recorded under `docs/verification`.

## Integration pitfall caught live

Repeated report selections initially returned the previous report's recipe IDs despite a changed POST body. The client rejects those mismatches. A dedicated stateless session with Foundation HTTP caching disabled fixed the live switching matrix; the app-level caches remain authoritative. Cookie-enabled and cookie-free public form checks both worked independently, so the portal does not require a session. Requests also explicitly disable cookie handling and local HTTP-cache reuse. Tests assert those request policies.

After midnight the final live matrix uses November 11 and 12. The November 10 fixtures remain a reproducible historical parser baseline.
