---
name: shopping
description: Shopping research for Erik (Stockholm, Sweden). Load whenever Erik asks to find, compare, price-check or re-buy a product ("find the cheapest", "where can I buy", "bulk", "per unit", "Prisjakt", "PriceRunner", "handla", "köpa"), or confirms he bought something. Covers Prisjakt-first research, per-unit math with shipping, the Obsidian notes in ~/obsidian/Life/shop/ai, product screenshots, and the hard rule that agents never buy anything.
---

# Shopping research for Erik

Erik lives in **Stockholm, Sweden**. He wants the cheapest real way to get a
product delivered (or picked up) there, documented so he can buy the exact same
thing again years later, even after the links die.

## Hard rules

- **Research only. Never buy, never add to cart, never start a checkout, never
  create an account, never sign up for a newsletter or club** to see a price.
  Erik decides and buys himself. A purchase needs his explicit OK for that exact
  order, and even then you only document it; he clicks "buy".
- Only the agent's own hidden browser (load **browser-use**): your own tabs,
  closed when done. Never Erik's monitors or browsers. Never submit a login form
  that could trigger a phone prompt (the phone rule in browser-use). Member
  prices you can only see logged in: note them as "member price, not verified".
- Keep the PC light: `curl` for plain HTML/JSON, the agent Chromium for the
  rest. No headless browsers, no scraping loops, no parallel browser fan-out.
- **Never edit Erik's own notes** in `~/obsidian/Life/shop/` (e.g. `kläder.md`,
  `deo.md`, `Apotea.md`). Write only inside `~/obsidian/Life/shop/ai/`. If his
  notes should change (new link, new historik line), propose the exact lines in
  your report.
- Match the product exactly. If Erik names a model, colour, size or variant,
  every candidate must be that model, colour, size and variant. Confirm it from
  his notes, photos (care labels, packaging) or article numbers before pricing.
  A cheaper "similar" product is a separate, clearly marked suggestion at most.

## Research order

1. **Read Erik's notes first** (`~/obsidian/Life/shop/*.md` and
   `~/obsidian/Life/shop/ai/`): he may already have the exact product name,
   article number, links and past prices (historik).
2. **Prisjakt first** (Erik: it is the best way to find things).
   - Search: `https://www.prisjakt.nu/search?query=<terms>`
   - Product page: `https://www.prisjakt.nu/produkt.php?p=<id>`; it lists every
     shop, price, stock and often shipping. Check the variant/size filter.
   - Look at price history on the product page: is today's price a low or a
     spike? Mention it if a sale is likely soon (Black Friday, mellandagsrea).
3. **PriceRunner**: `https://www.pricerunner.se/results?q=<terms>`; product
   pages look like `https://www.pricerunner.se/pl/<cat>-<id>/...-priser`.
   It sometimes has shops Prisjakt lacks.
4. **The shops themselves**, because comparison sites lag and miss campaigns:
   the brand's own Swedish site and its outlet, then the usual Swedish shops
   for the category (clothes: Zalando, Boozt, Ellos, CDON, Amazon.se, Stadium,
   Intersport, Sportamore, Lyko, Bubbleroom, Nelly, Halens, Footway;
   health/beauty: Apotea, Apotek Hjärtat, Kronans, Lyko, Med24; electronics:
   Komplett, Inet, Webhallen, NetOnNet, Elgiganten, Power, Proshop, Dustin).
   Check size/variant stock on the shop page, not just the listing.
5. **Discounts**: current campaigns (3 för 2, "köp 2 spara X"), member/club
   prices, first-order and newsletter codes (note them, don't sign up), student
   discounts, outlet. Search `"<shop> rabattkod"` and check the shop's banner.
   Say which ones you verified on the page and which are only from code sites.

Bulk/large tasks: hand the page-by-page price scraping to a cheap sub-agent
(Codex via `delegate_task`, see the `model-tiers` skill), then **verify the
winning numbers yourself** on the actual pages before reporting.

## Per-unit math

- Compute per unit for every option: `pack price / pieces`.
- Then compute the **cheapest way to reach the quantity Erik wants** (e.g. at
  least 20 pieces): combinations of pack sizes in one shop, with **shipping,
  free-shipping threshold, minimum order and any discount** applied to the
  whole basket. Report total, pieces and per unit including shipping.
- Note returns (free or paid, days), delivery time to Stockholm and pickup
  options (ombud/store in Stockholm) when they differ between top options.
- All prices in SEK including moms. Prices change: always write the date.

## Documentation (Obsidian vault, `~/obsidian/Life/shop/ai/`)

The vault is synced with Syncthing and is not a git repo. Layout:

```
ai/
  README.md            how this workspace works
  purchases.md         confirmed purchases only (historik style)
  candidates/<product>.md   one note per product (all shops in it)
  attachments/         screenshots, YYYY-MM-DD-<shop>-<variant>.png
```

`candidates/<product>.md` (file name: short product slug, e.g.
`bjorn-borg-cotton-stretch-boxer-black.md`) follows Erik's own format:

```markdown
# <exact product name>

- exact name: <as the brand writes it>
- article / product id: <brand article no., colour code, EAN if shown>
- search term: <the full search string that finds it, e.g. "Björn Borg Cotton Stretch Boxer 12-pack svart">
- variant: <colour, size>
- links
	- shop: <brand page>
	- prisjakt: <product page>, search: <prisjakt search URL>
	- pricerunner: <product page>, search: <pricerunner search URL>
- ![[attachments/YYYY-MM-DD-<shop>-<variant>.png]]

## Prices YYYY-MM-DD

| shop | pack | price | per unit | shipping | in stock | link |
| ---- | ---- | ----- | -------- | -------- | -------- | ---- |

## Best way to buy N (YYYY-MM-DD)
<what to buy, total incl. shipping, per unit, why>

## historik
- <price> kr × <qty>, <shop>, YYYY-MM-DD   (only after Erik confirms)
```

Screenshots: take them with `browser_take_screenshot` (viewport, product name
and price visible, cookie banner dismissed) and save into `ai/attachments/`.
Embed with `![[attachments/<file>.png]]`. Take one of the brand product page
and one of every option in the top 3, plus the Prisjakt page.

`purchases.md`: one line per confirmed purchase, newest first, in Erik's
historik style: `- <item>: <price> kr × <qty>, <shop>, YYYY-MM-DD, <link>`.
Write it **only after Erik says he bought it** (with the real price he paid).
Then also add the line to the product note's `historik` and propose the same
line for his own note (e.g. `kläder.md`).

## Report to Erik

Short and ranked:

1. The winner: what to buy (e.g. "2 × 12-pack"), shop, total incl. shipping,
   pieces, per unit, link, and any code to use.
2. Runners-up (2–4 lines) and why they lost.
3. What you could not verify (member prices, stock in his size) and the date.
4. Where the notes are, and the lines you propose for his own notes.

Then stop and let him decide.
