# pool — handoff for Claude Code

*Compiled 2026-10-29 from the GitHub repo, the local backup, and past sessions. Nothing in this doc was verified on-chain: no contract is deployed yet.*

## What it is

**pool by Lampwrecked** is an on-chain generative artwork of 100 editions on Ethereum. Each edition holds 10 seconds of one person's touch (a gesture recorded on a phone). The wall replays the gestures, in mint order, as currents, ripples and bioluminescent plankton in a WebGL swimming pool (tiled walls, lane lines, caustics, a 40-lamp ceiling, "POOL BY LAMPWRECKED" spelled in tiles).

- Minting is free (the collector pays gas), with one mint per wallet and 100 max.
- The holder of a token can **rewrite** its gesture for exactly 0.01 ETH. The token keeps its number and its place in the order.
- **Fully on-chain:** the contract stores the gestures plus gzipped copies of the pool page and the mint page. `tokenURI` builds a self-contained HTML page for each token.
- **Seal:** when minting ends, the owner calls `sealPool(to)`. That closes minting for good and mints one more token, the **pool token** (the whole work, live). It is always the token after the last gesture (#101 if all 100 are minted).
- It's for a gallery: an 80" Samsung shows `/pool/` with a QR code that points to `/input/`.

## Where things are

| | |
|---|---|
| Repo | https://github.com/lampwrecked/pool (public, `main`, HTML) |
| Hosting | GitHub Pages, from `main` / root → https://lampwrecked.github.io/pool/ |
| Local copy | `C:\Users\lampw\github-backup\pool` is a **stale** backup from 2026-10-21 that is missing the last two commits. Clone fresh before working. |
| Where it was built | Claude Code on the web: `https://claude.ai/code/session_01PAUyu9bdzdcdQ7MDyY5LoG` (linked from the commit trailers). None of the local desktop sessions worked on it. |

```bash
gh repo clone lampwrecked/pool
```

## Repo layout

| Path | Role |
|---|---|
| `index.html` | Landing page with two links: input / pool |
| `config.js` | `window.POOL_CONFIG`: `contract` (the engine address), `collection` (the Transient collection), `chainId` (1 or 11155111), public RPC lists. **`contract` is empty, which puts the site in demo mode.** |
| `lib.js` | Gesture codec (`encode`/`decode`, binary v1 format) and hand-written ABI encoders and function selectors (`SEL`), plus read-only RPC with fallback. No libraries. |
| `pool/index.html` (~50 KB) | The wall: WebGL fluid, light and wave simulation. The `P` tuning block is near line 55. Scheduling (`SLOT = 2000`) is near line 804. Demo synth gestures are near line 836. |
| `input/index.html` (~24 KB) | Mint page: record 10 s → locked replay → re-record or mint. Holders also get "rewrite #n · 0.01 ETH". Has deep-link buttons for MetaMask and Coinbase Wallet. |
| `admin/index.html` | Owner console with steps 0–5: link the collection (grant minter role, set renderer) → upload pool and mint page → open or close minting and rewrites → withdraw → seal → freeze files. |
| `contracts/PoolEngine.sol` | **The recommended route.** It's the minter and renderer for a Transient Labs ERC721TL collection, calling `externalMint`. Has `sealPool` and the pool token. |
| `contracts/Pool.sol` | Standalone alternative: its own ERC721 + ERC2981, with no pool token. |
| `onchain/*.html.gz` | Build outputs that get uploaded into the contract. |
| `tools/build.py` | Inlines `lib.js`, drops `config.js`, and gzips into `onchain/`. Checks that the placeholders `/*POOL_DATA*/null` and `/*POOL_CONFIG*/null` each appear exactly once. |

## Key mechanics and invariants

- **Gesture limits** (enforced in `lib.js` and in the contract's `_validate`): 10 000 ms max, ≤ 40 strokes, ≤ 5 fingers per stroke, ≤ 6144 bytes. Coordinates are 0..1000, and the aspect ratio is stored ×1000. Format: version byte `1`, then u16 aspect, then the stroke count. Each stroke has a type (0–9) and a finger count. Each finger has a point count and an absolute first point, then deltas (time delta ≤ 255 ms; longer gaps get split).
- **Stroke types → water:** tap → ring; double tap → two rings; hold → upwelling; drag → current; flick → jet; swirl → vortex; pinch/spread → sink/source; two-finger rotate → eddy; two-finger drag → twin currents; three or more fingers → scatter.
- **Playback (current, after commit `3b82423`):** a new edition every **2 s**, with **at most 5** in the water at once. A full set gives a 200 s cycle. With fewer than 100 editions they repeat in order. Playback is clock-synced (`Date.now`), so every screen shows the same moment. A single token's page (`SOLO`) plays only its own gesture, every 10 s.
- **Gestures are stored** with SSTORE2-style pointer contracts (`_store`/`_load`). Files are chunked per slot (`FILE_POOL = 0`, `FILE_MINT = 1`) until `freezeFiles()`.
- **The engine enforces:** minting only while open and never after seal; `hasMinted` per wallet; rewrites only by the current holder, exactly 0.01 ETH, while rewrites are open; seal is owner-only, happens once, and needs at least one gesture; the pool token can't be rewritten.
- **Token numbers must match the pool order,** so nothing else may ever be minted into the Transient collection.
- **Compiling:** Solidity 0.8.24, optimizer 200, **viaIR on** (it fails with "Stack too deep" otherwise). The engine comes to ~16 KB, under the 24 KB limit.

## Status (as of last commit, 2026-10-25)

Done:
- The wall, the mint page and the admin page all work in demo mode.
- Both contracts are written. Seal and pool token are implemented.
- The `onchain/` gz files were rebuilt in the last commit.

**Not done:**
1. Nothing has been deployed. `config.js` has empty `contract` and `collection` and `chainId: 1`.
2. The full Sepolia rehearsal hasn't been run (README §5): mint from a phone, rewrite, seal, then check that the pool token renders on Transient and testnets.opensea.io.
3. It hasn't gone to mainnet, and files haven't been frozen.

## Known loose ends

- After a rewrite, marketplaces may show the old gesture until someone refreshes the metadata. Through Transient, the engine can't emit ERC-4906 for the collection (the standalone `Pool.sol` can).
- The pool token is the heaviest `tokenURI` because it builds the whole pool on the spot. Rendering it on marketplaces is the main thing to check on Sepolia.
- Cost estimates in the README assume Oct 2026 gas (~0.07 gwei, ETH ≈ $2,450). Re-check them before launch.

## Working rules for the next session

- After any edit to `pool/index.html` or `input/index.html`, run `python3 tools/build.py` and commit the regenerated `onchain/*.gz`. The on-chain copy only changes when the owner re-uploads from `/admin/`, and only before freezing.
- Keep `lib.js` limits, `_validate` in **both** contracts, and the descriptions in both contracts in sync.
- If you change a function signature, update the hard-coded selectors in `lib.js` `SEL`.
- The user deploys through Remix and MetaMask in the browser (often on an iPad). Keep the steps browser-only, with no Hardhat or Foundry required.
- Test on Sepolia (`chainId: 11155111`) before mainnet. Pages auto-deploy from `main`, so a push is live.
- The user's earlier commits are authored by Claude with a `Claude-Session:` trailer. Keep the `Co-Authored-By` line.
