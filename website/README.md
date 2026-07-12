# Joustra Builds — website

One Next.js app, three brands:

| Route         | Brand            | What it is                                          |
| ------------- | ---------------- | --------------------------------------------------- |
| `/`           | Joustra Builds   | Main site: about, projects, links to the sub-brands |
| `/simulators` | Joustra SimWorks | Sim racing rigs + configurator with ±15% estimate   |
| `/catio`      | Joustra Catios   | Catio enclosures + dimension-based estimator        |

## Run locally

```bash
cd website
npm install
npm run dev     # http://localhost:3000
```

## Updating prices (the important part)

All pricing lives in two editable files — no code changes needed:

- **`data/sim-pricing.ts`** — every sim product with its supplier and USD
  price (researched July 2026). Change a `price`, add/remove option lines,
  update `asOf`. The configurator recalculates automatically.
- **`data/catio-pricing.ts`** — the catio cost model. **All rates are
  placeholders** — replace `baseFee`, per-sq-ft mesh/roof rates, `perBend`
  and `perDoor` with your real numbers.

Contact email and business info live in **`data/site-config.ts`**.

Every estimate is displayed as a ±15% range (`PRICE_TOLERANCE` in
`data/sim-pricing.ts`).

## Deploy

Standard Next.js app — deploys as-is to Vercel (recommended), Netlify, or any
Node host (`npm run build && npm start`).
