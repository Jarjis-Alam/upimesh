# Brag Plan: MeshPay / UPI Offline Mesh

## What is this app?
MeshPay sends legally-structured, cryptographically dual-signed UPI payments between real iPhones and Macs over Bluetooth and AWDL — with zero internet — and it actually worked on physical hardware for ₹100 INR.

## The angle
The internet goes down. The UPI network goes dark. Alice taps "Pay". A signed packet travels through the air to Bob's Mac. The ledger balances to the rupee. The escrow clears to ₹0.00.
This is the video that proves it.

## Hook (first 2-3 seconds)
Black screen. Two words slam in sequentially: "No internet." — then "Paid." The Mesh Radar pulses into existence behind them, mint rings expanding outward.

## Key moments (the middle)
- Phase 1 — Issue Allowance: iPhone 14 UI card shows Alice's balance (₹5,000), taps "Issue Allowance ₹100". Bank signs a voucher. Status badge: ACTIVE.
- Phase 2 — Peer Discovery + Transfer: Mesh Radar lights up — electric azure rings pulse, peer node "Bob (MacBook)" floats up with mint glow. Packet Transfer arc sweeps to 100%. Status badge: RECEIVED — NOT SETTLED.
- Phase 3 — Settlement: Mac Companion inbox row transitions. Escrow counter ticks ₹100.00 → ₹0.00. Big centered text: SETTLED. Ledger: Debits = Credits = ₹430.00.

## Outro / punchline
Logo: MeshPay in Manrope 700. Tagline: "Decentralized. Offline. Verified." Deep bell rings. Fade.

## User flow worth showing
1. Entry: Alice issues allowance on iPhone → bank RSA-PSS signs a voucher
2. Key action: Mesh Radar discovers Bob's Mac → AWDL/BLE packet transfer completes
3. Result: Bridge settles → escrow clears → ledger BALANCED (₹430.00 = ₹430.00)

## Tone
- Preset: cinematic
- Creative direction: "quiet systems-level revelation — the grid goes dark, money still moves"
- Interpretation: Wide staging, long holds on key numbers, dramatic text reveals, restrained pacing. The project's actual numbers do the work — no hype copy needed.

## Format: landscape — 1920x1080
## Duration: 20 seconds

## Visual identity (from the project)
- Background: #080A0D (Void Canvas)
- Accent mint: #4ADE80 (Mint Vitality — cryptographic clearance, fund transfer)
- Accent azure: #38BDF8 (Electric Azure — mesh beaconing, peer discovery)
- Text: #E2E2E6 (on-surface)
- Display font: Manrope 700
- Body / mono readouts: JetBrains Mono 500
- Strongest visual element: Mesh Radar — concentric luminous rings on obsidian, peer nodes as glowing dots

## Share copy (draft)
Built offline UPI payments that actually work — dual crypto signatures, P2P AWDL/BLE, zero internet. ₹100 settled on physical iPhone 14 → MacBook. Double-entry ledger: BALANCED.

## Audio direction
- Role: cinematic support — sparse, weighty, lets the numbers breathe
- Music: happy-beats-business-moves-vol-12-by-ende-dot-app.mp3 (steady and clean; best for cinematic)
- Music treatment: fade in at 0.0s, volume 0.30, fade to 0.0 over last 2s
- Music cue guidance: bundled preset at assets/music/cues/vol-12.music-cues.json; beat-lock peer discovery reveal to 8.74s (strong_beat), SETTLED reveal to 13.11s (strong_beat), logo to 17.47s (strong_beat)
- Audio-reactive treatment: subtle; music RMS/bass breathes the radar ring glow and escrow counter presence. No waveform/EQ visuals.
- SFX posture: sparse — 3-4 cues only; cinematic restraint
- Audio-coupled moments: hook "Paid." slam → impact/impactSoft_medium_001.ogg; peer node pop-up → interface/drop_001.ogg; SETTLED text → impact/impactBell_heavy_000.ogg (beat-locked 13.11s); logo → impact/impactBell_heavy_003.ogg at 17.47s
- Restraint rule: no dense SFX sequences; every sound should feel inevitable

## Music cue guidance
- Track: happy-beats-business-moves-vol-12-by-ende-dot-app.mp3, ~109.96 BPM (~0.545s/beat)
- Strong cue locks:
  - Scene 2 peer discovery: beat-lock to 8.74s
  - Scene 3 SETTLED: beat-lock to 13.11s
  - Scene 5 logo: beat-lock to 17.47s
- Beat-grid for Scene 4 proof lines: 13.64s, 14.20s, 14.73s
- Restraint: cinematic tone — lock only the 3 above

---

## Storyboard

### Scene 1 — Hook — 3s (0:00-0:03)
Black void canvas (#080A0D). Two lines slam in one at a time, Manrope 700, centered:
- "No internet." — slides in from left, settles at 1.2s; hold 0.8s
- "Paid." — slams in with impact, #4ADE80 mint color, settles at 2.2s; hold 0.8s
Mesh Radar rings begin pulsing dimly behind the text.
Sequential/interaction: yes — two lines arrive one at a time; "Paid." gets the impact accent
Audio intent: arresting slam on "Paid." — subwoofer weight
Audio-coupled idea: "Paid." lands → impact/impactSoft_medium_001.ogg at ~2.1s
Music: bed fades in from near-silence
Transition mood: dramatic (radar expands) → Scene 2

### Scene 2 — Peer Discovery — 5s (0:03-0:08)
Full-screen Mesh Radar: obsidian canvas, azure rings (#38BDF8) pulsing outward. Peer node "Bob · MacBook" floats up with mint glow ring (#4ADE80).
Top-center JetBrains Mono label: "_upimesh._tcp · AWDL / BLE · 0 internet"
Packet transfer arc sweeps 0% → 100% over ~2s ending with mint checkmark.
Status badge slides in: RECEIVED · NOT SETTLED in amber (#FBBF24)
Sequential/interaction: yes — rings pulse, then peer node floats up, then arc fills, then status badge slides in
Audio intent: live system waking up; anticipatory
Audio-coupled idea: peer node float-up → interface/drop_001.ogg at ~5.2s; arc completion beat-locked to 8.74s
Music: bed building in energy
Transition mood: clean wipe → Scene 3

### Scene 3 — Settlement — 5s (0:08-0:13)
Mac Companion inbox row transitions: RECEIVED · NOT SETTLED (amber) → SETTLED (#4ADE80)
Escrow counter in JetBrains Mono ticks ₹100.00 → ₹0.00 over 1.5s
Ledger line types out: "Debits ₹430.00 = Credits ₹430.00"
Large centered: SETTLED in Manrope 700, #4ADE80, 48px — beat-locked to 13.11s
Sequential/interaction: yes — inbox transitions, counter ticks, ledger types, SETTLED overlays
Audio intent: weight of a completed financial transaction; single resonant bell
Audio-coupled idea: SETTLED lands → impact/impactBell_heavy_000.ogg at 13.0s (beat-locked to 13.11s); ledger typing → interface/click_003.ogg per character at 0.35 volume
Music: strong beat at 13.11s carries the SETTLED moment
Transition mood: crossfade → Scene 4

### Scene 4 — Proof Block — 4s (0:13-0:17)
Dark glassmorphism card, centered. Three lines reveal in JetBrains Mono:
- "399 tests · 0 failures"  — fades up at 13.64s
- "Physical iPhone 14 + MacBook Pro" — fades up at 14.20s
- "Payment ID: dd3bd00c-646a-4d8d-..." — fades up at 14.73s (grounded from README)
Small badge top-right: Apache 2.0 · Open Source
Sequential/interaction: yes — 3 lines one per beat; beat-grid: line 1 at 13.64s, line 2 at 14.20s, line 3 at 14.73s; hold all 3 on screen through 16.8s
Audio intent: quiet, credentialing
Audio-coupled idea: each line fade-up → interface/drop_001.ogg at 0.40 volume, one per line
Music: approaching strong cue at 17.47s
Transition mood: soft crossfade → Scene 5

### Scene 5 — Logo / Outro — 3s (0:17-0:20)
Full obsidian canvas. Center:
- "MeshPay" in Manrope 700, 64px, white #E2E2E6 — fades in at 17.4s (beat-locked to 17.47s)
- Tagline Manrope 400, 20px, mint #4ADE80: "Decentralized. Offline. Verified."
- Thin radial mint glow ring pulses once (audio-reactive peak)
- Music fades 18.5s → 0.0 by 20.0s
Sequential/interaction: none — single composed reveal
Audio intent: deep bell rings; music fades under it
Audio-coupled idea: logo fade-in → impact/impactBell_heavy_003.ogg at 17.4s, volume 0.75
Music: fade out 18.5s → 20.0s; bell rings over fading bed
Transition mood: fade to black

**Music mood for this video:** cinematic, steady, restrained
**Audio summary:** Vol-12 bed fades in under the opening slam, builds through peer discovery, locks the 13.11s strong beat for SETTLED, fades under the logo bell at 17.47s — 3 anchor points, everything else breathes naturally.
