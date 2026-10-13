# 📱 UPI OFFLINE MESH — 3:4 Cinematic Portrait Teaser

A browser-rendered **3:4 portrait aspect ratio (1440 × 1920)** product teaser animation for **UPI Offline Mesh**, engineered specifically for Instagram feed posts, LinkedIn, and mobile event promotions.

---

## 📐 Format & Composition

- **Aspect Ratio**: **3:4 Portrait**
- **Master Resolution**: `1440 × 1920` (HiDPI Canvas 2D)
- **Social Export Preset**: `1080 × 1440` (Instagram / LinkedIn optimized)
- **Duration**: **24.0 seconds** (Deterministic frame-accurate timeline)
- **Safe Area**: All critical headlines, device mockups, UI cards, and CTA buttons are composed within a centered vertical safe area.

---

## 🎨 Visual Identity

- **Canvas Palette**: Matte black background (`#050505`) with deep obsidian surfaces (`#080A0D` / `#0C0E12`).
- **Dominant Accent**: Signal Yellow (`#FFD400`) as the sole dominant accent.
- **Supporting Text**: Off-white (`#F5F5F5`) and muted technical slate (`#8E929E`, `#94A3B8`).
- **Typography**: `Bricolage Grotesque`, `Space Grotesk`, `Inter`, and `JetBrains Mono`.
- **Aesthetic Guardrails**: Strict avoidance of neon cyberpunk, blue/purple flares, rainbow gradients, or cluttered HUDs. Black dominates the composition; yellow guides viewer attention.

---

## 🎬 6-Scene Cinematic Storyboard

| Scene | Timecode | Headline | Visual Choreography |
| :--- | :--- | :--- | :--- |
| **1. The Hook** | `00:00 – 00:03.2` | **WHAT IF CONNECTIVITY DISAPPEARED?** | A premium smartphone chassis emerges from obsidian darkness. 4 cellular bars drain to zero; red `NO SERVICE • OFFLINE` alert triggers; razor-thin yellow pulse travels down the glass. |
| **2. The Concept** | `00:03.2 – 00:07.2` | **PAYMENTS THAT KEEP MOVING.** | A minimal payment packet (`₹10.00`) is signed locally on Alice's phone. Detaches and glides along a vertical yellow laser track toward Bob's phone with zero cellular connectivity. |
| **3. The Mesh** *(Highlight)* | `00:07.2 – 00:12.2` | **PEER-TO-PEER. MESH-POWERED. OFFLINE-FIRST.** | Full vertical topology expands (`Alice → Carol → Relay → Bridge`). Primary link to an unstable node fails and dissolves into particles; mesh immediately self-heals as the packet hops down intermediate nodes with decrementing TTL (`5 → 4 → 3`). |
| **4. Trust & Resilience** | `00:12.2 – 00:16.2` | **SIGNED. ENCRYPTED. DESIGNED FOR RESILIENCE.** | Precision rotating cryptographic dials (`360°`), scrolling SHA-256 hexadecimal rings, RSASSA-PSS digital signature verification lock, and hybrid `RSA-OAEP + AES-256-GCM` envelope encryption. |
| **5. The Future** | `00:16.2 – 00:20.0` | **BUILT FOR A WORLD THAT DOESN'T ALWAYS CONNECT.** | Ingestion at edge bridge gateway. Pending records converge into an immaculate double-entry ledger card (`Alice -₹10.00`, `Bob +₹10.00`) snapping to `SETTLED`. |
| **6. Brand Reveal** | `00:20.0 – 00:24.0` | **UPI OFFLINE MESH**<br/>`PAYMENTS THAT KEEP MOVING.`<br/>**[ COMING SOON ]** | Pure black blackout. A single yellow line draws vertically, branches into a minimalist mesh glyph, resolving into the monumental title card, yellow tagline, and glowing `COMING SOON` button. |

---

## 🚀 How to Run Locally

The preview server is running at:
```
http://localhost:8765
```

Or start manually with any static server:
```bash
cd teaser-animation
python3 -m http.server 8765
```

### Interactive Controls:
- **Play / Pause**: Click `PLAY` or press `Space`
- **Timeline Scrubbing**: Drag the yellow slider or use `←` / `→` arrow keys
- **Audio Toggle**: Click `SOUND: ON / OFF` or press `M`
- **Fullscreen**: Click `⛶` or press `F`
- **Preset Selector**: Choose between `1440×1920 (Master)` and `1080×1440 (Social / IG)`
- **Record Video**: Click `● RECORD` to automatically capture the full 24-second sequence at 60 FPS into a downloadable WebM file.

---

## 🎥 Converting to Social-Media MP4 (FFmpeg)

To convert the recorded WebM file to high-compatibility MP4 for Instagram and LinkedIn:

```bash
ffmpeg -i upi-offline-mesh-teaser-3x4-1080x1440-social.webm \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  upi-offline-mesh-teaser-instagram.mp4
```

---

## 🛡️ Product Accuracy & Isolation

- **Zero modifications** to Spring Boot backend (`src/`), H2 database, device keys, or iOS app (`ios/`).
- **Authentic Framing**: Communicates the broader architectural vision (local signing, multi-hop mesh store-and-forward, deferred atomic settlement) without implying that unfinished offline hardware transport is already operational in production.
