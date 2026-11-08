---
name: Obsidian Kinetic
colors:
  surface: '#12131a'
  surface-dim: '#12131a'
  surface-bright: '#383941'
  surface-container-lowest: '#0d0e15'
  surface-container-low: '#1a1b22'
  surface-container: '#1e1f26'
  surface-container-high: '#292931'
  surface-container-highest: '#33343c'
  on-surface: '#e3e1ec'
  on-surface-variant: '#d1c6ab'
  inverse-surface: '#e3e1ec'
  inverse-on-surface: '#2f3038'
  outline: '#9a9078'
  outline-variant: '#4d4632'
  surface-tint: '#eec200'
  primary: '#ffecb9'
  on-primary: '#3c2f00'
  primary-container: '#facc15'
  on-primary-container: '#6c5700'
  inverse-primary: '#735c00'
  secondary: '#ffb95f'
  on-secondary: '#472a00'
  secondary-container: '#ee9800'
  on-secondary-container: '#5b3800'
  tertiary: '#ffebc4'
  on-tertiary: '#3f2e00'
  tertiary-container: '#ffc93e'
  on-tertiary-container: '#715500'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffe083'
  primary-fixed-dim: '#eec200'
  on-primary-fixed: '#231b00'
  on-primary-fixed-variant: '#574500'
  secondary-fixed: '#ffddb8'
  secondary-fixed-dim: '#ffb95f'
  on-secondary-fixed: '#2a1700'
  on-secondary-fixed-variant: '#653e00'
  tertiary-fixed: '#ffdf9a'
  tertiary-fixed-dim: '#f7be1d'
  on-tertiary-fixed: '#251a00'
  on-tertiary-fixed-variant: '#5a4300'
  background: '#12131a'
  on-background: '#e3e1ec'
  surface-variant: '#33343c'
typography:
  display-hero:
    fontFamily: Bricolage Grotesque
    fontSize: 48px
    fontWeight: '800'
    lineHeight: 52px
    letterSpacing: -0.04em
  display-hero-mobile:
    fontFamily: Bricolage Grotesque
    fontSize: 38px
    fontWeight: '800'
    lineHeight: 42px
    letterSpacing: -0.035em
  headline-lg:
    fontFamily: Bricolage Grotesque
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.03em
  headline-md:
    fontFamily: Bricolage Grotesque
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 28px
    letterSpacing: -0.025em
  headline-sm:
    fontFamily: Bricolage Grotesque
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.02em
  body-lg:
    fontFamily: Bricolage Grotesque
    fontSize: 17px
    fontWeight: '500'
    lineHeight: 22px
    letterSpacing: -0.01em
  body-md:
    fontFamily: Bricolage Grotesque
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: -0.005em
  body-sm:
    fontFamily: Bricolage Grotesque
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: 0em
  telemetry-lg:
    fontFamily: JetBrains Mono
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.03em
  telemetry-md:
    fontFamily: JetBrains Mono
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: -0.01em
  telemetry-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-caps:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.08em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  gutter: 0.75rem
  gutter-sm: 0.5rem
  margin: 1rem
  margin-safe: 1.25rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.5rem
---

## Brand & Style

This design system is engineered for zero-connectivity peer-to-peer monetary infrastructure on iOS. It communicates extreme cryptographic reliability, immediate finality, and hardware-grade precision. 

The aesthetic synthesizes AMOLED Minimalism with tactile iOS Liquid Glass:
- **True Black Substrate:** Canvas uses pitch `#000000` to maximize contrast, battery conservation, and bezel-free edge immersion on OLED displays.
- **Electric Telemetry:** Kinetic Amber/Yellow highlights cut through obsidian depth, transforming offline Bluetooth/NFC mesh interactions into vivid, reassuring feedback loops.
- **No Decorative Overhead:** Zero filler copy, zero purely decorative illustrations. Every pixel renders a transaction state, a cryptographic proof, or a mesh proximity vector.

## Colors

The palette establishes an absolute contrast ratio between deep obsidian structural tiers and luminous energetic accents.

### Palette Hierarchy
- **Canvas Base:** Pitch Black (`#000000`) for edge-to-edge system immersion.
- **Surface Tiers:** Obsidian Layer 1 (`#080808`), Surface Card (`#111111`), Elevated Floating (`#161616`).
- **Primary Accent (`#FACC15`):** Hyper-saturated luminous yellow for active connection pings, confirmed payment states, primary CTAs, and offline broadcast waves.
- **Secondary Accent (`#F59E0B`):** Warm amber used for mesh routing states, pending proofs, and warning-level telemetry.
- **Tertiary Accent (`#EAB308`):** Deep golden amber reserved for interactive focus rings and active toggle fills.
- **Hairline Dividers & Glass Edges:** White at 8% opacity (`rgba(255, 255, 255, 0.08)`) and active amber glow strokes (`rgba(250, 204, 21, 0.25)`).
- **Text & Telemetry:** Pure White (`#FFFFFF`) for primary figures and headings; Slate Steel (`#A1A1AA`) for secondary metadata; Muted Zinc (`#71717A`) for inactive timestamps and network latency tags.

## Typography

The type system blends the characterful, tight-aperture geometry of **Bricolage Grotesque** with the cold, mathematical discipline of **JetBrains Mono**.

### Roles & Execution
- **Display & Currency Amounts:** Bricolage Grotesque at heavy weights (700/800) with compressed negative tracking (`-0.03em` to `-0.04em`) creates an authoritative, modern financial presence.
- **Telemetry & Hashes:** Dynamic cryptographic values, balance amounts, transaction hashes, node IDs, and RSSI signal strengths are strictly set in `JetBrains Mono` to guarantee tabular alignment and avoid optical jitter during dynamic updates.
- **Labels & System Status:** Micro-labels utilize all-caps monospaced treatments with expanded tracking (`0.08em`) for immediate readability at glancing distance in sunlight.

## Layout & Spacing

A mobile-first spatial framework calibrated strictly for iOS single-thumb reachability and high density without optical noise.

### Grid & Canvas Structure
- **Screen Margins:** Fixed `16px` (`margin`) gutters scaling up to `20px` (`margin-safe`) on high-resolution Pro Max viewports. Safe areas directly respect Dynamic Island / notch geometry and bottom home indicator curves.
- **Vertical Rhythm:** Strict 4px/8px modular base increment. Standard component internal padding sits at `12px` (`space-md`) and `16px` (`space-lg`), maximizing data visualization space on 390pt–430pt screen widths.
- **Content Zones:** Dual-zone layout structure:
  - *Interaction Zone (Bottom 45% of viewport):* Houses action triggers, keypad inputs, and floating mesh routing selectors.
  - *Telemetry Zone (Top 55% of viewport):* Holds transaction validation rings, peer proximity radar, and balance status.

## Elevation & Depth

Depth is articulated through pure luminance layering, optical hair-lines, and specular glow, entirely bypassing heavy muddy drop shadows.

### Surface Architecture
- **Layer 0 (Canvas):** Pure `#000000`. Zero elevation.
- **Layer 1 (Card Substrate):** `#080808` with a 1px continuous perimeter border of `rgba(255, 255, 255, 0.08)`.
- **Layer 2 (Floating Action Modules & Modals):** `#111111` or `#161616` equipped with backdrop blur (`backdrop-filter: blur(24px) saturate(180%)`) and an inner highlight line (`inset 0 1px 0 0 rgba(255, 255, 255, 0.12)`).
- **Luminous Radiance (Signal Elevation):** Active nodes, selected transaction pills, and validation triggers cast a localized, diffused amber glow: `box-shadow: 0 0 24px -4px rgba(250, 204, 21, 0.28)`.

## Shapes

The design system relies on ergonomic pill curvature (`roundedness: 3`) across touch targets, paired with controlled squircle continuity for grouping containers.

- **Primary Interactive Elements:** Buttons, search pills, chip filters, and floating navigation operate with pure capsule ends (`9999px` radius).
- **Structural Cards:** Bounded with a high-radius curve (`24px` to `28px`), harmonizing with iOS display corner curvature.
- **Telemetry Indicators:** Sharp circular pins (`50%`) with concentric broadcast ripple rings.

## Components

### Buttons
- **Primary Kinetic Trigger:** Background `#FACC15`, foreground text `#000000` (Bricolage Grotesque Bold). Full capsule shape (`h: 56px`), subtle internal top highlight, active press scale transform (`scale(0.97)` via haptic tap).
- **Secondary Glass Action:** Pitch black fill with 40% opacity, bordered by `1px rgba(255, 255, 255, 0.12)`, text `#FFFFFF`. On active state, shifts to `rgba(250, 204, 21, 0.1)` with amber text.
- **Destructive/Cancel:** Monospaced label, zero border, text `#71717A`.

### Status & Mesh Chips
- Compact pills (`h: 28px`, padding `0 12px`).
- Inactive/Searching: Surface `#111111`, border `rgba(255, 255, 255, 0.08)`, text `#A1A1AA`.
- Mesh Connected: Surface `rgba(250, 204, 21, 0.1)`, border `rgba(250, 204, 21, 0.4)`, text `#FACC15`. Features an animated 6px pulsating amber dot on the leading edge.

### Floating Bottom Navigation
- Suspended liquid capsule floating `20px` above home indicator.
- Background: `#111111` at 85% opacity with 30px backdrop blur and `1px rgba(255, 255, 255, 0.1)` stroke.
- Selected state: Active tab is encapsulated in an internal `#FACC15` solid pill with `#000000` iconography.

### Cards & Peer Mesh List
- Single-pixel bordered surfaces (`#080808` to `#111111`).
- Peer list items feature mono-spaced signal metrics (`-42 dBm`, `HOP: 01`) right-aligned, counterbalanced by bold peer names and avatar halos that flash amber upon packet broadcast.

### Keypad & Inputs
- Numeric Keypad: Borderless circular hit zones (`72px × 72px`), `#FFFFFF` monospaced digits with low-opacity sub-labels.
- Zero traditional text boxes: Inputs are presented as open inline editable values with an amber cursor bar.