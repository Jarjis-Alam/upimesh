---
name: Liquid Mesh UPI
colors:
  surface: '#111317'
  surface-dim: '#111317'
  surface-bright: '#37393d'
  surface-container-lowest: '#0c0e11'
  surface-container-low: '#1a1c1f'
  surface-container: '#1e2023'
  surface-container-high: '#282a2d'
  surface-container-highest: '#333538'
  on-surface: '#e2e2e6'
  on-surface-variant: '#bccabb'
  inverse-surface: '#e2e2e6'
  inverse-on-surface: '#2f3034'
  outline: '#869486'
  outline-variant: '#3d4a3e'
  surface-tint: '#4de082'
  primary: '#6bfb9a'
  on-primary: '#003919'
  primary-container: '#4ade80'
  on-primary-container: '#005e2d'
  inverse-primary: '#006d36'
  secondary: '#7bd0ff'
  on-secondary: '#00354a'
  secondary-container: '#00a6e0'
  on-secondary-container: '#00374d'
  tertiary: '#a9eedb'
  on-tertiary: '#00382e'
  tertiary-container: '#8dd1bf'
  on-tertiary-container: '#0f5b4d'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#6dfe9c'
  primary-fixed-dim: '#4de082'
  on-primary-fixed: '#00210c'
  on-primary-fixed-variant: '#005227'
  secondary-fixed: '#c4e7ff'
  secondary-fixed-dim: '#7bd0ff'
  on-secondary-fixed: '#001e2c'
  on-secondary-fixed-variant: '#004c69'
  tertiary-fixed: '#abf0dd'
  tertiary-fixed-dim: '#90d4c2'
  on-tertiary-fixed: '#00201a'
  on-tertiary-fixed-variant: '#005144'
  background: '#111317'
  on-background: '#e2e2e6'
  surface-variant: '#333538'
typography:
  display-hero:
    fontFamily: Manrope
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.03em
  display-hero-mobile:
    fontFamily: Manrope
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.025em
  headline-lg:
    fontFamily: Manrope
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Manrope
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.015em
  headline-sm:
    fontFamily: Manrope
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Manrope
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.01em
  body-md:
    fontFamily: Manrope
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 22px
    letterSpacing: 0em
  body-sm:
    fontFamily: Manrope
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: 0em
  label-numeric:
    fontFamily: JetBrains Mono
    fontSize: 15px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: -0.02em
  label-caps:
    fontFamily: Manrope
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.08em
  caption:
    fontFamily: Manrope
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.01em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1.25rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

### Personality & Direction
This design system expresses a luxury, tactile, and future-forward interface tailored for an offline peer-to-peer mesh payment application on iOS. It pairs deep obsidian tones with liquid glass surfaces, optical refraction, and luminous chromatic indicators. The system evokes sovereign security, frictionless financial exchange, and technological precision.

### Aesthetics
- **Materiality:** Fluid, layered glassmorphism with high-refraction specular highlights and translucent frosted layers.
- **Lighting Paradigm:** Directional illumination from the top-left edge simulating dynamic ambient refractions over fluid squircle vessels.
- **Chromatics:** Deep obsidian field surfaces punctured by radiant mint-emerald state verifications and electric azure mesh network beacons.

## Colors

The palette relies on a pitch-black substrate overlaid with tiered frosted materials and vibrant spectral accents indicating offline radio states, mesh hops, and transaction authentications.

### Surface System
- **Void Canvas:** `#080A0D` — Base screen background under glass layers.
- **Elevated Canvas:** `#0D1117` — Deep obsidian under-paneling and drawer depths.
- **Liquid Glass Primary:** `rgba(255, 255, 255, 0.08)` backdrop with `backdrop-filter: blur(40px) saturate(190%)`.
- **Liquid Glass Dark:** `rgba(20, 24, 30, 0.65)` for contrast-retaining containers and sensitive card shields.
- **Glass Specular Stroke:** `rgba(255, 255, 255, 0.18)` on upper-left edges cascading down to `rgba(255, 255, 255, 0.04)`.

### Chromatic Accents
- **Mint Vitality (`#4ADE80`):** Cryptographic clearance, funds transferred, authenticated mesh signature.
- **Electric Azure (`#38BDF8`):** Offline mesh beaconing, peer discovery, low-energy Bluetooth/Wi-Fi Direct handshake.
- **Patina Emerald (`#72B5A4`):** Secondary verification, passive connection, ledger syncing states.
- **Warning / Unsynced (`#FBBF24`):** Delayed peer broadcast, pending consensus proof.
- **Critical Alert (`#FB7185`):** Signal drop, handshake rejected, insufficient offline reserve.

## Typography

The type system blends contemporary Apple Human Interface guidelines with the structural clarity of neo-grotesque forms.

- **Primary Display & Body (`Manrope`):** Delivers clean optical rhythm, high legibility on high-DPI OLED panels, and geometric stability.
- **Technical & Numeric Readouts (`JetBrains Mono`):** Applied to UPI reference tokens, encrypted payload hashes, mesh hop identifiers, and numerical transaction breakdowns.
- **Currency Readouts:** Currency symbols match the weight of the following numerical glyph, scaled dynamically to prevent visual overflow in offline balance chips.

## Layout & Spacing

### Grid & Composition
- **Mobile Primary Layout:** Single-column fluid architecture anchored with `margin` (`1.25rem` / `20px`) on native viewports to maintain precise ergonomic thumbsweep zones.
- **Rhythm Base:** 4px absolute baseline grid, with internal card groupings separated by `space-sm` (`8px`) or `space-md` (`16px`).
- **Safe Area Insets:** Content yields dynamic padding for iOS Dynamic Island (`54px` top inset) and Home Indicator (`34px` bottom floating clearance).

### Breakpoints & Adaptability
- **Handheld (< 430px):** Single-column stacked stream. Mesh balance hero anchored directly above the primary peer radar view.
- **Foldable / Compact Tablet (431px - 768px):** 2-column asymmetric layout; offline balance and credential ledger on the left, interactive radar and active transaction queue on the right.

## Elevation & Depth

Visual hierarchy does not rely on opaque stacking or drop shadows; it relies on refractive index simulation, frosted layers, and chromatic back-glows.

### Material Stack
1. **Level 0 (Canvas Base):** Solid `#080A0D` with radial gradient ambient light wells (`#38BDF8` at 4% opacity and `#4ADE80` at 3% opacity positioned beneath high-traffic widgets).
2. **Level 1 (Structural Shelves):** Background `rgba(20, 24, 30, 0.65)`, backdrop-blur `24px`, inner specular highlight top: `1px solid rgba(255, 255, 255, 0.12)`.
3. **Level 2 (Interactive Cards & Inputs):** Background `rgba(255, 255, 255, 0.08)`, backdrop-blur `40px`, specular rim border `rgba(255, 255, 255, 0.18)`, ambient shadow `0 20px 40px -15px rgba(0, 0, 0, 0.7)`.
4. **Level 3 (Floating Controls & Navigation):** Full liquid glass capsule. Double-ring border: Outer `rgba(255, 255, 255, 0.15)`, inner glow `inset 0 1px 1px 0 rgba(255, 255, 255, 0.35)`. Ambient colored drop glows emerge upon active state (`0 10px 30px -5px rgba(74, 222, 128, 0.35)`).

## Shapes

The interface embraces Apple squircle geometry, leveraging generous border-radii for fluid visual softness.

- **Primary Cards & Modals:** `rounded-[28px]` or `rounded-3xl` (`24px` to `28px` corner radius) with continuous curvature smoothing.
- **Interactive Controls & Fields:** `rounded-2xl` (`16px`) for form inputs, token tiles, and transaction items.
- **Pill Navigation & State Badges:** Fully rounded (`rounded-full` / `9999px`) to emphasize fluidity, tactile drag operations, and floating ergonomics.

## Components

### Buttons
- **Primary Liquid Action:** Height `56px`, `rounded-full`, fill gradient `linear-gradient(135deg, rgba(74,222,128,0.9), rgba(56,189,248,0.9))`, crisp text in `#080A0D` with font weight `600`. Outer glow: `0 8px 24px -4px rgba(74, 222, 128, 0.4)`.
- **Secondary Glass Action:** Height `56px`, `rounded-full`, background `rgba(255, 255, 255, 0.06)`, border `1px solid rgba(255, 255, 255, 0.18)`, text `#FFFFFF`. Specular top edge highlight.

### Liquid Glass Pill Tab Bar
- **Architecture:** Floating dock detached from viewport bottom by `20px`.
- **Material:** Height `68px`, padding `6px`, background `rgba(20, 24, 30, 0.75)`, `backdrop-blur-2xl`, border `1px solid rgba(255, 255, 255, 0.14)`.
- **Active Indicator:** Smooth sliding pill with background `rgba(255, 255, 255, 0.12)`, dynamic neon mint ambient ring, and subtle chromatic aberration on icon shift.

### Inputs & Keypad
- **UPI PIN Field:** 6 discreet frosted liquid squares (`52px` x `56px`), `rounded-2xl`, background `rgba(255, 255, 255, 0.05)`, border `1px solid rgba(255, 255, 255, 0.12)`. Active entry triggers an internal radial mint glow.
- **Mesh Payee Search:** Integrated search bar with `rgba(255, 255, 255, 0.06)` fill, left-aligned signal radar glyph, and dynamic pulse dot.

### Cards & Ledger Rows
- **Mesh Peer Card:** `rounded-[28px]`, background `rgba(255, 255, 255, 0.08)`, border `1px solid rgba(255, 255, 255, 0.18)`. Displays peer avatar with glowing signal ring, connection hops count, and signal dBm metric in `JetBrains Mono`.
- **Transaction Item:** Clean list item with separator line rendered as an ultra-fine translucent gradient `linear-gradient(90deg, transparent, rgba(255,255,255,0.08), transparent)`.

### Domain-Specific: Mesh Radar Visualizer
- **Interface:** Concentric liquid rings pulsing across the dark canvas. Detected offline nodes float as glowing nodes: mint for trusted contacts, azure for unknown broadcast nodes.