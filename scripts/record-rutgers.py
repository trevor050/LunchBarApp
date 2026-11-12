#!/usr/bin/env python3
"""Record public FoodPro fixtures; deliberately serial, half a second apart."""
import json, pathlib, re, time, urllib.parse, urllib.request
root = pathlib.Path(__file__).resolve().parents[1]
out = root / 'Tests/LunchKitTests/Fixtures/Rutgers'
base = 'https://menuportal23.dining.rutgers.edu/foodpronet/'
records = []
def fetch(name, page, params, body=None):
    url = base + page + '?' + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, data=body, headers={'User-Agent': 'LunchBar/2.0 (+https://github.com/trevor050/LunchBarApp)'})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read(); (out / name).write_bytes(data)
        records.append({'file': name, 'url': url, 'method': req.get_method(), 'status': r.status})
    time.sleep(.5)
    return data.decode('utf-8')
for loc, hall in [('03','Livingston Dining Commons'),('04','Busch Dining Hall'),('05','Neilson Dining Hall')]:
    for meal in ['Lunch','Dinner']:
        fetch(f'{loc}-{meal.lower()}-2026-11-10.html', 'pickmenu.aspx', dict(sName='Rutgers University Dining', locationNum=loc, locationName=hall, dtdate='11/10/2026', activeMeal=meal, naFlag='1'))
fetch('04-empty-2026-11-26.html','pickmenu.aspx',dict(sName='Rutgers University Dining',locationNum='04',locationName='Busch Dining Hall',dtdate='11/26/2026',activeMeal='Lunch',naFlag='1'))
fetch('04-label-eggs.html','label.aspx',dict(locationNum='04',locationName='Busch Dining Hall',dtdate='11/10/2026',RecNumAndPort='061002*4'))
menu=(out/'04-lunch-2026-11-10.html').read_text()
recipes=list(dict.fromkeys(re.findall(r'name="recipe"[^>]+value="([^"]+)"',menu)))
# This is the public form's repeated recipe/QTY fields. No ADDSELECTIONS action.
body=urllib.parse.urlencode([p for r in recipes for p in [('recipe',r),('QTY','1')]]).encode()
fetch('04-lunch-report.html','nutRpt.aspx',dict(locationNum='04',locationName='Busch Dining Hall',dtdate='11/10/2026',mealName='Lunch',sName='Rutgers University Dining'),body)
(out/'provenance.json').write_text(json.dumps({'recorded':'2026-11-10 America/New_York','requests':records},indent=2)+'\n')
print('recorded',len(records),'public pages;',len(recipes),'unique lunch recipes')
