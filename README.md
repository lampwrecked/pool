# pool

100 editions. Each is ten seconds of one person's touch, stored on Ethereum and replayed in a pool of light: **#1, then #2 a second later, and so on to #100**, then around again. Never more than ten in the water at once. Free to mint (collectors pay their own gas), one per wallet. **A token's holder can rewrite its gesture for 0.01 ETH**; it keeps its number and its place in the order.

**Fully on-chain.** The pool itself (compressed) and every gesture live in the contract. Each token's animation is assembled by the contract: the pool plus all gestures, as one self-contained page that unzips itself in the browser. No server, no hosting, no RPC needed to view it. The mint page is stored on-chain too (`mintHTML()`).

- **`/input/`** — the mint page. Record 10 seconds → it replays, locked → **re-record** or **mint**. Holders get **rewrite #n · 0.01 ETH**.
- **`/pool/`** — the wall for the gallery (hosted copy of the same pool; reads gestures live from the chain). `/pool/?token=12` highlights #12.
- **`/admin/`** — for you: upload the pool and mint page into the contract, open/close minting and rewrites, withdraw rewrite fees, freeze.
- **`contracts/PoolEngine.sol`** — the engine for a Transient Labs collection (recommended). `contracts/Pool.sol` — standalone alternative. **`config.js`** — where you paste its address. **`onchain/`** — the compressed files that go into the contract (built by `tools/build.py`).

Before a contract is set, the site runs in **demo mode**.

---

## Deploying through Transient Labs (all in the browser, works on iPad)

The tokens live in a normal **Transient Labs collection** (ERC721TL): your royalties, Story inscriptions, and listing on transient.xyz. A small contract, **`contracts/PoolEngine.sol`**, is that collection's **minter and renderer**: it holds the rules (100, one per wallet, rewrites), the gestures and the pool itself.

**Do the whole thing on Sepolia (free test network) first.** Get test ETH from a Sepolia faucet.

### 1. Make the collection on Transient
Create a new **ERC-721 collection** (the standard creator contract) in Transient Labs' studio. Name it *pool*, set your royalty there. **Use it only for pool**: don't mint anything else into it, because token numbers must match the pool's order. Copy the collection's contract address.

### 2. Deploy the engine in Remix
1. **remix.ethereum.org** → new file `PoolEngine.sol` → paste `contracts/PoolEngine.sol`.
2. **Solidity compiler**: version **0.8.24+**, **optimization on (200)** → **Compile**.
3. **Deploy** tab: Environment **Injected Provider – MetaMask** → contract `PoolEngine` → in the box next to Deploy paste your **collection address** → **Deploy**.
4. Copy the engine's address.

### 3. Point the site at both
In `config.js`: `contract` = the engine address, `collection` = the Transient collection address, `chainId: 11155111` for Sepolia (`1` for mainnet). Commit.

### 4. Set up from /admin/ (in MetaMask's browser, connected as the owner of both)
1. **allow engine to mint** and **use engine as renderer** (two transactions to your collection)
2. **upload pool** and **upload mint page**
3. **preview from chain**
4. **open minting**

### 5. Test, then mainnet
Mint from `/input/` on your phone in MetaMask's browser, try a rewrite, check the tokens on Transient and testnets.opensea.io. Then repeat 1–4 on mainnet with `chainId: 1`. When it's all right: **freeze files forever**.

> **Without Transient:** `contracts/Pool.sol` is a standalone version (its own NFT contract, same features). Deploy it with no constructor input and put its address in `contract`; skip step 0 in /admin/.

### Things to check on Sepolia
- **Marketplace refresh.** The engine can't make the Transient collection announce "metadata changed", so after mints and rewrites, marketplaces may show an older picture until refreshed (OpenSea's *refresh metadata* button, or they re-read on their own schedule). The pool on the wall is always live.
- **Compile size.** If Remix warns the contract is too large, tell Claude.

### Costs (Oct 2026, ~0.07 gwei, ETH ≈ $2,450)
- Transient collection: whatever Transient's studio charges in gas (small) · deploy engine: ~$0.70 · link (2 tx) + upload pool + mint page (~31 KB): ~$1.35
- Each mint: ~$0.05 typical, ~$0.20 for the heaviest gesture
- Each rewrite: 0.01 ETH + the same gas
- Gas changes; check before launch. At 2 gwei, multiply by ~27.

## In the gallery
- **80" Samsung:** open `/pool/`, press **f** (or double-click) for full screen. If the TV's browser stutters, use a laptop or mini PC over HDMI. `?q=low` is a lighter fallback; `?ui=0` hides the QR code.
- **QR code** on the wall points to `/input/`. Phones need a wallet to mint: the page offers **open in MetaMask / Coinbase Wallet** buttons, which reopen it inside the wallet's browser.

## What the contract enforces
- 100 max · one mint per wallet · free · minting only while open.
- Rewrites: only the token's current holder, exactly 0.01 ETH, while rewrites are open.
- Gesture data must be well-formed: 10 seconds max, ≤ 40 movements, ≤ 5 fingers each, ≤ 6 KB.

## After changing the pages
The on-chain copy only changes when you re-upload from /admin/ (before freezing). After editing `pool/` or `input/`, the compressed files need rebuilding (`python3 tools/build.py`). Ask Claude to do it.

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
