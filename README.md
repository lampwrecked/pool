# pool

Two sites, one body of water.

- **`/input/`** — the phone. A black-and-white lattice your hand disturbs. Every gesture is saved as numbers only (no text, no IDs) and released into the pool.
- **`/pool/`** — the wall. A dark sea that replays every gesture ever made. It glows only where it's disturbed, like real bioluminescent plankton, and water that's been stirred too much tires and dims for ~20 seconds before it recovers.
- **`worker.js`** — the archive. A Cloudflare Worker that keeps every gesture forever.

It works right away in **demo mode** (no setup): the wall plays invented gestures, and if you open `/input/` in another tab of the *same browser*, your gestures appear on the wall.

---

## Setup (about 10 minutes, all in the browser)

### 1. Make the database
1. Cloudflare dashboard → **Storage & Databases → D1** → **Create database**.
2. Name it `pool`. That's it, the table builds itself later.

### 2. Make the Worker
1. **Workers & Pages → Create → Worker**. Name it `pool-archive`. Deploy the hello-world.
2. Click **Edit code**, delete everything, paste all of `worker.js`, **Deploy**.

### 3. Connect them
1. In the Worker: **Settings → Bindings → Add → D1 database**.
2. Variable name: `DB` (capitals). Database: `pool`. Save/Deploy.
3. Open the Worker's address in a browser. You should see `{"pool":"ok"}`.

### 4. Point both pages at it
Copy the Worker address (like `https://pool-archive.yourname.workers.dev`) and paste it between the quotes on the `const API = '';` line near the top of **both**:
- `pool/index.html`
- `input/index.html`

No slash at the end.

### 5. Publish
Repo `pool` → Settings → Pages → Deploy from branch `main`, folder `/ (root)`. Links:
- wall: `https://lampwrecked.github.io/pool/pool/`
- phone: `https://lampwrecked.github.io/pool/input/` Optional: custom domain `pool.lampwrecked.art` (CNAME in Spaceship → `lampwrecked.github.io`).

The QR code on the wall automatically points to the `/input/` page on whatever domain the wall is on.

---

## On the 80" Samsung
- Open the wall page, press **f** (or double-click) for full screen.
- The TV's own browser may struggle with the fluid. If it stutters, run it from a laptop or mini PC over HDMI. Test this early.
- Add `?q=low` to the address for a lighter version.
- Add `?ui=0` to hide the QR code and counter.

## Testing tricks
- On the wall, press **g** to drop in a test "live" gesture.
- Add `?api=https://…` to either page to try a different archive without editing code.

## Gestures and what they do in the water
| Gesture | Water |
|---|---|
| Tap | a ring pulse |
| Double tap | two rings, the second wider |
| Hold | a slow welling upwelling that grows the longer it's held |
| Drag | a current along the path |
| Flick | a fast jet |
| Swirl | the path, then a vortex left behind spinning the way you drew |
| Pinch / spread | water sucked in / pushed out |
| Rotate (two fingers) | a large eddy |
| Two-finger drag | twin parallel currents |
| Three+ fingers | a scatter of small pulses and currents |

Live gestures land larger and brighter than archived ones so visitors can find their own mark.

## Tuning the sea
Near the top of `pool/index.html`, the `P` block has plain settings: `threshold` (how hard you must stir before it glows), `gain` (brightness), `lightDecay` (afterglow length), `recover` / `deplete` (how quickly water tires and recovers), `curl` (how curly the eddies are), `bloom`.

## Backups
`https://<your-worker>/export?after=0` returns the first 500 gestures; change `after` to the last `id` you got to page through the rest.
