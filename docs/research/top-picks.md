# Top picks rules

"Top picks" ranks a large menu by one goal, chosen from the group's heading (or the ⋯ menu when the group is hidden). The choice is global, not per place: it describes the person, not the dining hall. Code: `Sources/LunchKit/PickGoal.swift`.

| Goal | Ranked by | Order | Extra requirement |
| --- | --- | --- | --- |
| High protein | grams of protein | highest first | protein > 0 |
| Lean protein | grams of protein × 100 / calories | highest first | at least 10 g protein, calories > 0 |
| Low calorie | calories | lowest first | meal or side, at least 120 calories |
| Low carb | grams of total carbohydrate | lowest first | meal or side, at least 120 calories |
| High fiber | grams of dietary fiber | highest first | fiber > 0 |
| Low sugar | grams of total sugars | lowest first | meal or side, at least 120 calories |
| Low sodium | milligrams of sodium | lowest first | meal or side, at least 120 calories |

Both providers publish all of these: Nutrislice items carry the full label, and FoodPro's combined report has calories, protein, fat, carbohydrate, fiber, sugars and sodium. On November 11 every goal ranked five items at Busch (FoodPro, 143 items) and the Atrium (Nutrislice, 173 items). Low fat was left out: on these menus it mostly repeated Low calorie. An item without the goal's number is never ranked, and values are never estimated. The 2.x protein setting migrates: grams per serving becomes High protein, per 100 calories becomes Lean protein.

Only published, finite, non-negative values qualify. Ties sort by item name then stable entry ID. Recipe/portion repeats across stations appear once, using that deterministic station choice. Five rows are shown at most. The group appears only when at least eight items can be ranked for the goal and the menu has at least ten items, so it never repeats most of a small menu and is absent, rather than empty, when the goal's data is missing.

**Meal or side** (the low goals only), so the lightest answer is a real dish rather than a condiment or a cup of water: not at a station named Beverage, Drink, Condiment, Topping, Dressing, Sauce, Dessert, Bakery or Sweets; no ingredient word anywhere in the name (oil, crumbles); and the dish's main noun (the last word before " with", " w/", "," or "(") is not a drink, sauce, dressing, spread, topping, snack or dessert word such as milk, juice, dressing, ketchup, butter, cookie or chips. A name that also contains a dish word (sandwich, bowl, chicken, fish, rice and others) counts as a dish, so "Fish and Chips" and "Chicken Sandwich with Ketchup" stay in. This is a word list, so components can still slip through: "Turkey Taco Meat" ranks under Low calorie at Busch.

The ingredient exclusion is deliberately narrow: **a portion of at most 2 OZ**, at a station explicitly named Condiment, Topping, Cook to order, Build your own, Omelet/Omelette, Noodle bar, Salad bar or Cantina sides. Fractions are understood. EACH and SLICE servings, larger ounce portions, unknown serving sizes, ordinary Entrees and Deli stations remain eligible. The rule never removes an item from the full menu. A 6 OZ chicken portion at Toppings, a 1 EACH entree at Cook to order and a 2 OZ entree at Entrees all remain eligible in tests. Station labels and portions can still be wrong, so this is a conservative heuristic, not a classifier of what constitutes a meal.

Selected allergen warnings exclude an item from the top group, including precautionary warnings. FoodPro reports have no allergens, so when an allergen is selected, labels are checked in ranking order until five eligible choices are known. Unknown or failed labels do not qualify. Other items remain in the full menu; loaded allergen warnings appear there, and unverified label details are explicitly marked.

During FoodPro nutrition loading, a quiet pending group appears. New ranking order is deferred while the pointer is in the menu or an item is expanded; existing rows receive updated details without reordering. Newly confirmed allergen conflicts are removed immediately. Leaving the menu applies the current ranking. Nutrition values are never invented for placeholders.
