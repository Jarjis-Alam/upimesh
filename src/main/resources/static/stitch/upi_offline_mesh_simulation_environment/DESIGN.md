---
name: UPI Offline Mesh Simulation Environment
colors:
  surface: '#121416'
  surface-dim: '#121416'
  surface-bright: '#37393b'
  surface-container-lowest: '#0c0e10'
  surface-container-low: '#1a1c1e'
  surface-container: '#1e2022'
  surface-container-high: '#282a2c'
  surface-container-highest: '#333537'
  on-surface: '#e2e2e5'
  on-surface-variant: '#bfc9c4'
  inverse-surface: '#e2e2e5'
  inverse-on-surface: '#2f3133'
  outline: '#89938f'
  outline-variant: '#3f4946'
  surface-tint: '#90d4c2'
  primary: '#90d4c2'
  on-primary: '#00382e'
  primary-container: '#72b5a4'
  on-primary-container: '#00463b'
  inverse-primary: '#23695b'
  secondary: '#afc9e9'
  on-secondary: '#18324b'
  secondary-container: '#324b65'
  on-secondary-container: '#a1bbda'
  tertiary: '#e6c27e'
  on-tertiary: '#412d00'
  tertiary-container: '#c6a463'
  on-tertiary-container: '#513a01'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#abf0dd'
  primary-fixed-dim: '#90d4c2'
  on-primary-fixed: '#00201a'
  on-primary-fixed-variant: '#005144'
  secondary-fixed: '#d0e4ff'
  secondary-fixed-dim: '#afc9e9'
  on-secondary-fixed: '#001d35'
  on-secondary-fixed-variant: '#304963'
  tertiary-fixed: '#ffdea4'
  tertiary-fixed-dim: '#e6c27e'
  on-tertiary-fixed: '#261900'
  on-tertiary-fixed-variant: '#5b430a'
  background: '#121416'
  on-background: '#e2e2e5'
  surface-variant: '#333537'
typography:
  headline-xl:
    fontFamily: Geist
    fontSize: 2rem
    fontWeight: '600'
    lineHeight: 2.5rem
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Geist
    fontSize: 1.5rem
    fontWeight: '600'
    lineHeight: 2rem
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Geist
    fontSize: 1.25rem
    fontWeight: '500'
    lineHeight: 1.75rem
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Geist
    fontSize: 1rem
    fontWeight: '500'
    lineHeight: 1.5rem
    letterSpacing: 0em
  body-lg:
    fontFamily: Geist
    fontSize: 1rem
    fontWeight: '400'
    lineHeight: 1.5rem
    letterSpacing: 0em
  body-md:
    fontFamily: Geist
    fontSize: 0.875rem
    fontWeight: '400'
    lineHeight: 1.25rem
    letterSpacing: 0em
  body-sm:
    fontFamily: Geist
    fontSize: 0.75rem
    fontWeight: '400'
    lineHeight: 1rem
    letterSpacing: 0.01em
  label-md:
    fontFamily: Geist
    fontSize: 0.8125rem
    fontWeight: '500'
    lineHeight: 1.125rem
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Geist
    fontSize: 0.6875rem
    fontWeight: '500'
    lineHeight: 0.875rem
    letterSpacing: 0.04em
  tabular-numeric-md:
    fontFamily: Geist
    fontSize: 0.875rem
    fontWeight: '500'
    lineHeight: 1.25rem
    letterSpacing: 0em
  tabular-numeric-sm:
    fontFamily: Geist
    fontSize: 0.75rem
    fontWeight: '400'
    lineHeight: 1rem
    letterSpacing: 0em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-compact: 0.5rem
  margin: 1.5rem
  margin-compact: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1.25rem
  space-xl: 1.75rem
---

## Brand & Style

This design system embodies the ethos of mission-critical financial engineering and academic network topology research. It is calibrated for simulated mesh-routed deferred payment settlement—where ledger integrity, cryptographic certainty, and deterministic network graphs take precedence over flashy consumer paradigms.

The visual direction rejects neo-crypto neon glows, heavy glassmorphism, aggressive brutalism, and theatrical telemetry interfaces. Instead, it projects quiet architectural rigor: the visual calm of central banking infrastructure crossed with the clarity of academic computer systems tooling. The emotional response is one of surgical precision, high institutional trust, and unhurried operational clarity. Data density is high but comfortable, favoring structural compartmentalization, subtle tonal contrast, and tabular precision over ornamental flourishes.

## Colors

The palette is engineered around low-strain, high-legibility dark surfaces tailored for long monitoring sessions and dense protocol inspection.

### Surface Hierarchy
- **Canvas Base (`#151719`)**: Deep charcoal foundation used for main viewports, graph canvases, and primary workspaces.
- **Sunken Surface / Navigation rail (`#111315`)**: Lowest ground plane reserved for global contextual sidebars, terminal shells, and peripheral rails.
- **Surface Level 1 (`#1D2023`)**: Standard card, panel, and ledger container background.
- **Surface Level 2 / Elevated (`#24282C`)**: Raised modals, floating tooltips, active node inspection drawers, and interactive row highlights.

### Structural Lines
- **Border & Rule (`#34383C`)**: Crisp, 1px structural boundaries defining layout cells, ledger headers, and node envelopes. Avoid thick stroke weights.

### Text & Glyphs
- **Primary Text (`#F1F0EB`)**: Warm, non-fatiguing off-white for high-contrast reading of ledger transactions, amounts, and critical headings.
- **Secondary Text (`#A1A5A8`)**: Balanced neutral grey for column metadata, cryptographic timestamps, node addresses, and parameter labels.

### Semantic Tones
- **Primary Accent (`#72B5A4`)**: Restrained muted teal denoting active network routes, verified signatures, and active filters.
- **Secondary Accent (`#819AB8`)**: Slate blue denoting intermediary peer hops, protocol-level state transitions, and baseline metric lines.
- **Success (`#83B99A`)**: Soft sage green indicating final settlement confirmation and quorum consistency.
- **Warning / Deferred (`#D4B16F`)**: Muted ochre signifying deferred batches, retry queues, and mesh partitioning alerts.
- **Error (`#CF827C`)**: Subdued brick red signaling signature mismatch, invalid nonces, and packet drops.

## Typography

Typography prioritizes micro-legibility and vertical rhythm across multi-column balance sheets and topology inspectors.

### Typographic Rules
- **Typeface**: Geist throughout headline, body, and label roles. Its geometric neutral construction balances humanist warmth with engineering exactness.
- **Tabular Figures**: All monetary figures, cryptographic hashes, network latencies, hop counts, and ledger coordinates must enforce `font-variant-numeric: tabular-nums` (CSS `font-feature-settings: "tnum" 1`).
- **Hierarchy & Weight Restraint**: Keep font weights strictly bounded between 400 (regular) and 600 (semi-bold). Never use black or ultra-bold weights. Semantic weight indicates functional state (e.g., active node vs. passive peer), never visual volume.
- **Casing & Metrics**: Technical labels and table column headers utilize sentence case or uppercase with deliberate letter spacing (`letterSpacing: 0.04em`) to establish visual separation without increasing font weight.

## Layout & Spacing

The layout is anchored in a continuous desktop workbench framework designed for high situational awareness across multi-window network telemetry and ledger replay.

### Layout Mechanics
- **Grid Architecture**: 12-column fluid grid paired with fixed-width contextual toolbars. The workbench uses a persistent navigation rail (64px collapsed / 240px expanded) docked against `#111315`, a resizable topology canvas, and a 380px inspector panel on the right.
- **Rhythm & Compaction**: Spacing is tightly controlled on an 8px base rhythm with 4px sub-steps for dense tabular lists. Margins between disparate analytical cards stay fixed at `space-lg` (20px), while internal row paddings compress to `space-xs` and `space-sm` to ensure dozens of deferred mesh transactions are viewable above the fold.
- **Responsive Adaptations**:
  - **Desktop (>= 1280px)**: Three-pane layout: network tree, topology canvas/ledger, and transaction detail inspector concurrently visible.
  - **Tablet / Small Laptop (1024px - 1279px)**: Topology canvas and ledger split into tabbed views; right inspector collapses into an overlay drawer.
  - **Mobile / Compact (< 1024px)**: Single-column linear flow prioritizing pending settlement lists and high-level health indicators. Complex topological graphs switch to linear dependency trees.

## Elevation & Depth

Visual hierarchy is constructed strictly through tonal stratification and structural hairline boundaries. Illusory shadows, drop blurs, and glassmorphic refractions are prohibited.

### Elevation Principles
- **Tier 0 (Backdrop)**: `#111315` provides the deepest floor, framing global navigation, status strips, and terminal views.
- **Tier 1 (Base Floor)**: `#151719` houses the primary work surface, graph visualization canvas, and background for data tables.
- **Tier 2 (Cards & Panels)**: `#1D2023` cleanly delineates data groupings, node configuration panels, and ledger cards, bound by a 1px border of `#34383C`.
- **Tier 3 (Floating & Overlays)**: `#24282C` represents context menus, hover inspections, and modal sheets. A delicate, highly-diffused ambient shadow (`box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4)`) provides edge separation against underlying tables, accented by a perimeter border of `#34383C`.
- **States & Focus**: Hovering over interactive rows or network nodes shifts the surface upward by one tonal level (`#1D2023` -> `#24282C`) without physical elevation jumps or scale transforms. Focus states utilize a sharp 1px outline of `#72B5A4` offset by 2px of empty space.

## Shapes

The geometry of this design system reflects an engineered instrument. Elements feature crisp, soft radius geometry (`roundedness: 1`), keeping corner curvature subtle and functional rather than friendly or playful.

### Corner Radius Standards
- **Containers & Panels**: Base border radius of `0.25rem` (4px). Structural cards and split views never exceed `0.375rem` (6px).
- **Controls & Form Elements**: Inputs, select buttons, and badges utilize `0.25rem` (4px) corner rounding to maintain a clean, precision-tooled perimeter.
- **Data Nodes**: Mesh vertices in the physical topology map are depicted as geometric primitives: clean 6px rounded squares for intermediate relay nodes, and complete circles only for end-user initiator/recipient wallets.
- **Status Indicators & Pills**: Small tag elements maintain a conservative `0.25rem` radius rather than rounded pills, emphasizing document-grade structure.

## Components

### Buttons & Interactive Controls
- **Primary Button**: Solid fill of `#72B5A4` with `#111315` text, semi-bold weight, 32px height in standard mode, 28px in compact data view. Focus border `#F1F0EB`.
- **Secondary Button**: `#1D2023` background, 1px border `#34383C`, `#F1F0EB` text. Hover shifts background to `#24282C` and border to `#819AB8`.
- **Tertiary / Ghost Button**: Transparent background, `#A1A5A8` text. Hover shifts text to `#F1F0EB` with an ultra-subtle background `#1D2023`.
- **Destructive Action**: `#1D2023` background, 1px border `#CF827C`, text `#CF827C`. Hover shifts background to `#CF827C` with `#111315` text.

### Data Tables & Ledger Grids
- **Header Cells**: 32px height, `#111315` background, `#A1A5A8` label-sm text, uppercase with 0.04em letter-spacing, bottom border 1px `#34383C`.
- **Data Rows**: 36px standard row height (28px dense). Alternating rows do not use zebra striping; separation relies on 1px `#34383C` horizontal lines.
- **Numeric Columns**: Right-aligned, formatted with `tabular-nums`. Deferred amounts display in `#F1F0EB`, batch identifiers and route hashes display in `#A1A5A8`.
- **Hover Row**: Immediate background shift to `#24282C` across the entire row span without easing lag.

### Status Chips & Badges
- **Settled / Verified**: Background `#1D2023`, border 1px `#83B99A`, text `#83B99A`.
- **Deferred / Routing**: Background `#1D2023`, border 1px `#D4B16F`, text `#D4B16F`.
- **Dropped / Failed**: Background `#1D2023`, border 1px `#CF827C`, text `#CF827C`.
- **Hop Count Indicator**: Monospaced-width badge with `#24282C` fill, `#819AB8` text, indicating mesh relay depth (e.g., `3 HOP`).

### Form Inputs & Selectors
- **Text & Numeric Field**: `#111315` background, 1px `#34383C` border, `#F1F0EB` text. Height 32px, padding `0 8px`. Active state transitions border to `#72B5A4` with no drop shadow.
- **Checkboxes & Radios**: 14px square/circle, `#111315` base with 1px `#34383C` stroke. Selected state displays `#72B5A4` fill with `#111315` check mark.

### Network Topology Cards & Nodes
- **Mesh Node Card**: `#1D2023` surface, 1px `#34383C` border. Header features node identifier, battery/power status, and pending queue size.
- **Connection Vectors**: Crisp 1px SVG links in `#34383C` (inactive) or `#72B5A4` (active relay route). No glowing stroke paths; animated dashed segments indicate active batch transmission.