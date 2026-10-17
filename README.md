# pool

100 editions. Each is ten seconds of one person's touch, stored on Ethereum and replayed in a pool of light: **#1, then #2 a second later, and so on to #100**, then around again. Never more than ten in the water at once. Free to mint (collectors pay their own gas), one per wallet.

- **`/input/`** — the phone. A black-and-white lattice your hand disturbs. Tap **record your 10 seconds**, touch, review (replay / again), then **mint**.
- **`/pool/`** — the wall. A deep white-tiled pool seen from above, with lane lines, a grid of ceiling lamps mirrored on the surface, and "POOL BY LAMPWRECKED" on the far wall. Ripples slosh off the walls; ~260,000 plankton light up only where the water is disturbed. Every screen is synced to the clock, so they all show the same moment. `/pool/?token=12` shows the pool with #12 glowing brighter (this is each token's animation).
- **`contracts/Pool.sol`** — the contract. Gestures are stored fully on-chain. Each token's image is an on-chain SVG trace of its gesture.
- **`config.js`** — the one place you paste the contract address.

Before a contract is set, everything runs in **demo mode**: the wall plays 100 invented editions, and the input page lets you record and preview but not mint.

---

## Deploying (all in the browser, works on iPad)

**Test on Sepolia first.** It's the free practice network. Get free test ETH from a Sepolia faucet.

### 1. Compile and deploy in Remix
1. Go to **remix.ethereum.org**. Create a file `Pool.sol` and paste in `contracts/Pool.sol`.
2. **Solidity compiler** tab: version **0.8.24** or newer, turn **optimization on (200)**, click **Compile**. Remix fetches the OpenZeppelin imports automatically.
3. **Deploy** tab: Environment **Injected Provider – MetaMask**, with MetaMask on **Sepolia** first. Pick `Pool` and click **Deploy**. Approve in MetaMask.
4. Copy the deployed contract address.

### 2. Point the site at it
In `config.js`, paste the address into `contract: ''`. For the Sepolia test, also set `chainId: 11155111`; for the real thing, `chainId: 1`.

### 3. Set up the contract (Remix → Deployed Contracts, expand Pool)
- `setAnimationBase` → `https://lampwrecked.github.io/pool/pool/` (or your custom domain + `/pool/`)
- `setRoyalty` (optional) → your wallet, `500` = 5%
- `setMintOpen` → `true` when you're ready

### 4. Test it
Open `/input/` inside MetaMask's browser on your phone, record, mint. Check `/pool/` picks it up (within 30 seconds) and the token looks right on OpenSea's testnet site.

### 5. Mainnet
Repeat steps 1–3 with MetaMask on **Ethereum mainnet**, put the new address in `config.js` with `chainId: 1`. When the animation link is final, call `freezeMetadata` (permanent).

### Costs (Oct 2026, ~0.07 gwei, ETH ≈ $2,450)
- Deploying: roughly a dollar.
- Each mint: a typical gesture is under 1 KB, about **$0.05** of gas; the heaviest possible (five fingers for ten seconds, ~3.8 KB) is about $0.20. Gas prices change; check before launch.

---

## In the gallery
- **80" Samsung:** open `/pool/`, press **f** (or double-click) for full screen. If the TV's browser stutters, use a laptop or mini PC over HDMI. `?q=low` is a lighter fallback; `?ui=0` hides the QR code.
- **QR code** on the wall points to `/input/`. Phones need a wallet to mint: the page offers **open in MetaMask / Coinbase Wallet** buttons, which reopen it inside the wallet's browser.

## What the contract enforces
- 100 max · one per wallet · free · minting only while open.
- Gesture data must be well-formed: 10 seconds max, ≤ 40 movements, ≤ 5 fingers each, ≤ 6 KB.

## Gestures and what they do in the water
| Gesture | Water |
|---|---|
| Tap | a ring pulse |
| Double tap | two rings, the second wider |
| Hold | a slow welling upwelling that grows the longer it's held |
| Drag | a current along the path |
| Flick | a fast jet |
| Swirl | the path, then a vortex spinning the way you drew |
| Pinch / spread | water sucked in / pushed out |
| Rotate (two fingers) | a large eddy |
| Two-finger drag | twin parallel currents |
| Three+ fingers | a scatter of small pulses and currents |

## Tuning the water
Near the top of `pool/index.html`, the `P` block has plain settings:
- **Plankton:** `threshold`, `gain`, `plankton` (brightness), `lightDecay` (afterglow), `recover` / `deplete` (how fast water tires and recovers), `particles` (count = this squared)
- **Water:** `curl`, `waveForce`, `waveDamp` (closer to 1 = sloshes longer), `waveSpeed`, `slope`
- **Room:** `margin` (deck width), `depth` (smaller = deeper), `lampCount`, `lamps`, `bloom`
