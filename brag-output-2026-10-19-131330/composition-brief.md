# Hyperframes Composition Brief: MeshPay / UPI Offline Mesh

## Objective
Create a short cinematic brag video for MeshPay — an offline, peer-to-peer, cryptographically dual-signed UPI payment system that works without internet.

## Output
- Composition directory: brag-output-2026-10-19-131330/composition/
- Rendered video: brag-output-2026-10-19-131330/brag.mp4
- Format: landscape — 1920x1080
- Duration: 20 seconds

## Source Material
- Project root: /Users/munshijarjisalam/Documents/Projects/upimesh/
- Primary files read: README.md, ios_ui/liquid_mesh_upi/DESIGN.md, docs/assets/
- Product name: MeshPay / UPI Offline Mesh
- Tagline / strongest claim: "Decentralized, Peer-to-Peer Offline Payment Routing with Dual Cryptographic Signatures"
- Key UI moment to recreate: Mesh Radar with pulsing azure rings and peer node discovery; Mac Companion SETTLED status transition
- Copy that must appear verbatim:
  - "No internet."
  - "Paid."
  - "SETTLED"
  - "Debits ₹430.00 = Credits ₹430.00"
  - "399 tests · 0 failures"
  - "Physical iPhone 14 + MacBook Pro"
  - "Payment ID: dd3bd00c-646a-4d8d-..."
  - "Decentralized. Offline. Verified."

## Creative Direction
- Tone preset: cinematic
- Creative direction: "quiet systems-level revelation — the grid goes dark, money still moves"
- Interpretation: Wide staging, long holds on key numbers, dramatic text reveals, restrained pacing. The project's real numbers carry emotional weight — no invented hype copy.
- Angle: The internet fails. A cryptographically signed packet travels 0.4m through the air over AWDL. The ledger balances to the rupee. The escrow clears to ₹0.00. This video proves it.
- Hook: "No internet." slams in. Then "Paid." in mint (#4ADE80) slams with weight. Mesh Radar pulses into existence behind them.
- Outro: MeshPay wordmark + "Decentralized. Offline. Verified." Deep bell rings. Music fades.
- Avoid:
  - Generic SaaS language ("streamline your workflow")
  - Abstract filler motion that could belong to any video
  - Unrelated visual redesign — stay in the obsidian/mint/azure palette

## Visual Identity
- Background: #080A0D (Void Canvas from DESIGN.md)
- Text: #E2E2E6 (on-surface)
- Accent mint: #4ADE80 (cryptographic clearance, verified states, fund transfer)
- Accent azure: #38BDF8 (mesh beaconing, peer discovery, AWDL/BLE)
- Accent amber: #FBBF24 (pending/unsynced state)
- Display font: Manrope 700 (Google Fonts)
- Mono font: JetBrains Mono 500 (balances, UUIDs, ledger lines)
- Visual references from the project:
  - Mesh Radar: concentric luminous rings pulsing on obsidian canvas, peer nodes as glowing dots (mint = trusted, azure = broadcasting)
  - Mac Companion status badges: RECEIVED · NOT SETTLED (amber) → SETTLED (mint)
  - iOS glassmorphism cards: rgba(255,255,255,0.08) fill, backdrop-blur 40px, specular rim border rgba(255,255,255,0.18)
  - Floating pill tab bar, liquid glass capsule styling
  - JetBrains Mono for all ₹ amounts, UUIDs, and ledger numbers

## Storyboard
Use brag-output-2026-10-19-131330/brag-plan.md as the creative contract.

Scene summary:
1. Hook — 3s — "No internet." then "Paid." (mint) slam in on obsidian canvas; radar begins pulsing behind
2. Peer Discovery — 5s — Full-screen Mesh Radar; azure rings pulse; "Bob · MacBook" node floats up with mint glow; transfer arc → 100%; RECEIVED badge appears
3. Settlement — 5s — Inbox row RECEIVED→SETTLED; escrow ticks ₹100→₹0; "Debits ₹430.00 = Credits ₹430.00" types out; SETTLED in mint at beat 13.11s
4. Proof Block — 4s — Glassmorphism card: 3 lines reveal on beat grid (399 tests, physical hardware, payment ID); hold all 3 through end
5. Logo Outro — 3s — MeshPay wordmark + tagline; mint glow ring pulse; music fades; deep bell rings

## Audio
- Audio role: cinematic support — sparse, weighty, restrained
- Audio arc: near-silent → bed builds through peer discovery → locks the SETTLED strong beat → bell rings into fading bed → silence
- Music: assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3
- Music treatment: fade in at 0.0s, volume 0.30; hold through Scene 4; fade 18.5s → 0.0 by 20.0s; deep bell rings over fading bed at 17.4s
- Music cue guidance: bundled preset JSON available; strong cue locks: 8.74s (peer discovery arc complete), 13.11s (SETTLED reveal), 17.47s (logo fade-in); beat-grid for Scene 4 lines: 13.64s, 14.20s, 14.73s
- Audio-reactive treatment: subtle; use music RMS/bass to breathe the Mesh Radar ring glow and logo glow presence. No waveform/EQ visuals.
- Audio-coupled moments:
  - Scene 1 "Paid." slam → impact/impactSoft_medium_001.ogg at ~2.1s
  - Scene 2 peer node float-up → interface/drop_001.ogg at ~5.2s
  - Scene 3 SETTLED text → impact/impactBell_heavy_000.ogg beat-locked to 13.1s, volume 0.80
  - Scene 4 each proof line → interface/drop_001.ogg at 0.40 volume (3 cues)
  - Scene 5 logo reveal → impact/impactBell_heavy_003.ogg at 17.4s, volume 0.75
- SFX selection guidance: prefer low/medium HF risk; impactSoft_medium family for transitions; impactBell for major payoffs; interface/drop for soft reveals; interface/click_003 for any typing (low HF risk, low volume)
- SFX analysis guidance: see assets/sfx/sfx-analysis.md (or sfx-analysis.json) for per-file HF risk ratings
- Exact SFX choice: Hyperframes should finalize filenames, timestamps, density, and volume after the animation is implemented
- Audio files: copy chosen music and SFX into brag-output-2026-10-19-131330/composition/assets/

## Hyperframes Instructions
Load hyperframes-core, hyperframes-animation, hyperframes-creative, hyperframes-keyframes, and hyperframes-cli. /brag is its own workflow — do not enter the hyperframes entry-point intent interview or route into its generic promo/launch-video workflow.

Requirements:
- Show at least one real UI element from the source project (Mesh Radar visualization, Mac Companion SETTLED status, iOS glassmorphism card)
- Keep all text readable: short labels ≥0.8s settled; sentences ≥0.3s per word; "No internet." and "Paid." each hold ≥0.8s settled
- Keep the video within 20 seconds total
- Include the vol-12 music bed and the 4-5 SFX cues listed above
- Beat-lock SETTLED reveal to 13.11s, logo to 17.47s, peer discovery arc to 8.74s (±0.15s)
- Beat-grid Scene 4 proof lines to 13.64s, 14.20s, 14.73s (±0.10s); hold all 3 through 16.8s
- Use audio-reactive treatment: RMS/bass breathes the Mesh Radar ring glow and logo glow (subtle, not waveform/EQ)
- Run npx hyperframes check before render; fix all errors
- Render to ../brag.mp4 (relative to composition dir)
