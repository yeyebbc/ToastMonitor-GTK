---
name: ToastMonitor-GTK
description: Native GNOME usage monitoring with faithful ToastMonitor reference composition.
colors:
  source-codex: "#7d9bff"
  source-claude: "#d16e2b"
  source-omp: "#52adc4"
  source-hermes: "#b052db"
  source-opencode: "#30b85e"
  source-other: "#5e6efd"
  shell-source-claude: "#d47745"
  shell-source-omp: "#54adbf"
  shell-source-hermes: "#b34fdb"
  shell-source-opencode: "#35b963"
  shell-source-dsh: "#6674fd"
  activity-warm: "rgb(82%, 43%, 25%)"
typography:
  stat-value:
    fontSize: "2em"
    fontWeight: 700
    fontFeature: "tnum"
  heading:
    fontSize: "1.1em"
    fontWeight: 700
  preferences-heading:
    fontSize: "1.05em"
    fontWeight: 700
  body:
    fontSize: "1em"
    fontWeight: 400
  value:
    fontWeight: 600
    fontFeature: "tnum"
  table-heading:
    fontSize: "0.95em"
  shell-title:
    fontSize: "1.15em"
    fontWeight: 700
  shell-total:
    fontSize: "2.6em"
    fontWeight: 700
  shell-heading:
    fontSize: "1em"
    fontWeight: 600
  shell-secondary:
    fontSize: "0.9em"
    fontWeight: 400
rounded:
  quota: "2px"
  source-track: "3px"
  segment-button: "5px"
  shell-segment-button: "6px"
  segments: "7px"
  settings-tab: "8px"
  session-icon: "9px"
  card: "12px"
  round: "99px"
spacing:
  inset-2: "2px"
  gap-4: "4px"
  gap-6: "6px"
  gap-8: "8px"
  gap-10: "10px"
  gap-12: "12px"
  gap-14: "14px"
  gap-16: "16px"
  card-inset: "18px"
  page-inset: "20px"
  settings-inset: "24px"
  preferences-gap: "28px"
components:
  button-native:
    typography: "{typography.body}"
  segments:
    rounded: "{rounded.segments}"
    padding: "{spacing.inset-2}"
  segment-button:
    rounded: "{rounded.segment-button}"
    padding: "5px 12px"
  settings-tab:
    rounded: "{rounded.settings-tab}"
    padding: "0"
    width: "104px"
    height: "76px"
  card:
    rounded: "{rounded.card}"
    padding: "{spacing.card-inset}"
  stat-card:
    rounded: "{rounded.card}"
    padding: "{spacing.gap-16}"
    typography: "{typography.stat-value}"
  session-icon:
    rounded: "{rounded.session-icon}"
    padding: "9px"
  source-dot:
    rounded: "{rounded.round}"
    size: "7px"
  shell-section:
    rounded: "{rounded.card}"
    padding: "{spacing.gap-12}"
  shell-quota:
    backgroundColor: "{colors.source-codex}"
    rounded: "{rounded.quota}"
    height: "4px"
---

# Design System: ToastMonitor-GTK

## Overview

**Creative North Star: "Native GNOME reference fidelity"**

ToastMonitor-GTK presents local AI usage as a compact, orderly desktop utility. The user-selected ToastMonitor reference images establish its visual language: prominent numeric summaries, aligned breakdowns, rounded groups, and restrained supporting text. GTK4/libadwaita and GNOME Shell supply the font, theme, window controls, widgets, and interaction states.

Preserve the reference hierarchy while expressing it through the existing Linux capabilities. Clear labels carry the distinction between recorded spend, estimated API value, fixed subscriptions, balances, and quotas. [README.md](README.md) records the Dashboard and Settings section hierarchy; [the panel guide](docs/gnome-extension.md) describes the popup. [PRODUCT.md](PRODUCT.md) remains the authority for capability and accounting truth.

**Key Characteristics:**

- Native GNOME typography, theme roles, symbolic icons, and controls.
- Spacious page gutters with compact, aligned information inside rounded groups.
- Large numeric summaries, tabular values, and quieter explanatory text.
- Labeled chart colors shared by each series' marks, legend, and detail rows.
- Explicit availability, freshness, refresh, and error feedback.

This is an extracted system, not a web implementation. Frontmatter contains the actual fixed chart colors, relative text roles, geometry, and spacing. Local Impeccable metadata in `.impeccable/design.json` records GTK theme symbols, renderer-specific color values, opacity, and native component examples; that directory is excluded from version control. The reviewed screenshots use synthetic fixtures; their amounts, account names, timestamps, and session titles are not product content.

## Colors

The desktop owns surface and text colors; the fixed palette identifies data series.

### Primary

The native accent is GTK's `@accent_color`, used for selected Settings tabs and the session icon treatment. It is a theme role rather than a fixed ToastMonitor brand swatch. GNOME Shell controls inherit the active Shell theme independently of the application's Appearance setting.

### Secondary

The `source-*` tokens identify six dashboard series: periwinkle Codex, warm orange Claude, teal Oh My Pi, violet Hermes, green OpenCode, and indigo for the remaining tool. Model series reuse this indexed palette; the current implementation assigns model indices from sorted model names. A model's color is an identifier within the current data set, not a permanent model brand color.

The `shell-source-*` tokens retain the popup's existing source variants; Shell Codex and quota fills use `source-codex`. `activity-warm` encodes activity intensity. Its opacity reflects relative activity, not a separate cost or account status.

The Cairo chart renderer stores its series colors as fractional RGB values. Those small differences from the GTK CSS swatches are preserved in the sidecar's native renderer metadata. Do not infer exact values from screenshot sampling or silently replace either source palette.

### Neutral

| Native role | Authority | Use |
| --- | --- | --- |
| Window background | `@window_bg_color` | GTK window material |
| Content surface | `@view_bg_color` | Dashboard cards and selected segmented controls |
| Foreground | `@window_fg_color` / widget foreground | Text, subtle segment material, axes, chart guides, empty cells |
| Shell material and foreground | Active `St.ThemeNode` / native `button` class | Popup, native controls, labels, and icon foreground |

Secondary GTK text and table headings use foreground opacity; Shell secondary labels derive their color from the theme and lower actor opacity. Shell sections and tracks use the existing translucent neutral overlays, recorded in the sidecar. No fixed light or dark surface palette is imposed.

**The Native Material Rule.** Resolve surfaces, text, accent, and control states through the desktop theme; fixed source colors identify data.

**The Series Identity Rule.** Pass the same series index to its chart, legend dot, breakdown row, and share bar, and retain a readable text label.

## Typography

**Display Font:** the GNOME-configured UI font, inherited by GTK and Shell.

**Body Font:** the same native UI font; no application font-family override.

**Label/Mono Font:** numeric values request tabular figures through `tnum`; this is not a separate monospace font.

The hierarchy uses relative sizes and native text measurement, so desktop font and text scaling remain effective. The frontmatter defines the observed size and weight overrides; unspecified line height, letter spacing, and baseline font size stay under toolkit control.

- **Stat value:** the largest dashboard number, paired with a regular, quieter label.
- **Heading / preferences heading:** card and preferences-group hierarchy.
- **Body / value:** regular descriptions with semibold numeric or session values.
- **Table heading:** a slightly smaller, quieter label above aligned data columns.
- **Shell title / total:** compact popup identity and a dominant token total.
- **Shell heading / secondary:** section and row labels with quieter details and freshness messages.

**The Desktop Type Rule.** Keep typography relative and inherited; let text wrap or content scroll when desktop text grows.

## Layout

Use a vertical content stack inside a native scroll view. The reusable dashboard page gutter is `page-inset`; section separation is `gap-16`. Dashboard stat cards use `gap-12` between equal-width columns, `gap-16` internal padding, and `gap-6` between label and value. Breakdown and chart cards use `card-inset`; their painted surface contains the padding rather than leaving an unpainted margin inside the card boundary.

Settings uses `settings-inset` around a content column with an implemented maximum width of 800 logical pixels. Preferences groups have `preferences-gap` separation. Tab buttons share equal highlight rectangles with a minimum size of 104 × 76 logical pixels and `gap-8` between buttons; their contents stay vertically centered. The navigation scrolls horizontally if its measured content exceeds the available width. Native rows and controls retain their toolkit sizing.

Collection-based layouts use native `FlowBox`: plan cards allow one to three columns, with a minimum card width of 270 logical pixels and `gap-12` between cards; chart legends allow one to eight items per row. These are measured native layouts, not CSS media-query breakpoints. The existing dashboard statistics and Analysis control row remain horizontal groups. The narrow capture demonstrates the current desktop layout at its captured width; it does not establish a phone layout or support at arbitrarily small widths.

The Shell popup bounds its width and scrollable content height against the primary monitor and scale factor. Its title, period controls, notice, and footer sit outside the scrolling content. The exact sizing formulas belong to the sidecar and the native surface brief. Long account titles and details wrap, while numeric values remain aligned.

**The Gutter Rule.** Keep outer page padding distinct from card padding and native box spacing; preserve the continuous painted card surface.

## Elevation & Depth

Dashboard grouping relies on tonal layering and rounded surfaces. Dashboard cards add no custom shadow or border. Native preferences groups, buttons, dialogs, the header bar, and the Shell popup keep the toolkit or desktop theme's own depth and focus treatments. The selected GTK segment adds one small native CSS shadow, recorded exactly in the sidecar. Avoid adding a separate application-wide elevation system.

## Shapes

The recurring card silhouette uses `rounded.card`. Segmented controls have a softly rounded outer track with smaller rounded buttons; Settings tabs use a slightly larger selection tile around a symbolic icon and label. Session icons sit in a rounded accent-tinted square. Data dots are round, and quota tracks are thin with gently rounded ends.

The frontmatter captures the implemented geometry. Unspecified native button, entry, preferences-group, dialog, and window shapes remain toolkit-owned. Chart bars and activity cells retain the Cairo renderer's rectangular geometry.

## Components

### Buttons

Use native `Button`, icon buttons, and `Menu` for actions. Standard and flat variants retain GTK hover, focus, pressed, insensitive, and keyboard behavior. Icon-only actions need a tooltip or accessible name describing the action. GNOME Shell actions use focusable native `St.Button` actors with the Shell `button` class. The footer's dashboard action stays visible when popup content scrolls.

### Segmented controls and navigation

`NativeSegments` uses grouped `ToggleButton` widgets with a single selected option. Its track derives material from the window foreground; the selected option uses the native view surface and the small selection shadow. Keep selection represented by the widget state, not only custom color. Settings uses grouped icon-and-label toggles; the selected tab takes the native accent and subtle foreground-derived material. Shell period controls use their real checked state and the existing neutral overlay.

### Cards / Containers

`cardSurface()` wraps padded content in a styled native `Bin`. Statistics, breakdowns, charts, account plans, and sessions share the rounded surface language. Stat cards emphasize one value; breakdown cards combine a proportional source track with labeled rows. Shell sections use the same recurring shape with translucent neutral material and tighter padding.

### Inputs / Fields

Use libadwaita `EntryRow`, `PasswordEntryRow`, `SwitchRow`, `ActionRow`, and `ExpanderRow` inside `PreferencesGroup`. Preserve native focus, masking, validation affordances, expansion, and disabled behavior. Place the related action in the row suffix or directly after the group, as in the current native implementation. Destructive restore uses a native confirmation dialog with a destructive response.

### Charts and detail rows

`NativeChart` is a GTK drawing area painted by Cairo with native Pango labels. Every chart supplies a text summary as both tooltip and accessibility label; Analysis also provides a readable Details table. Legends wrap through `FlowBox`. Detail rows align name, tokens, calls, estimated cost, and token share; the share bar and dot receive the same series index as the chart. Share remains token share even when the chart displays estimated cost.

Activity intensity uses warm color with variable opacity and theme-foreground empty cells. Keep date and amount axes, source names, percentages, and the Less/More legend where the implemented chart provides them; color alone does not identify a series.

### Account / quota rows

Keep the account title, value, freshness or error detail, and optional quota bar together. Clamp fractions for display and label whether quota is used or remaining. Balance, provider spend, quota, and fixed subscription rows retain their distinct labels. A failed refresh keeps last-known data and its status visible; an unavailable value is shown explicitly rather than fabricated as zero.

### Status and notices

The GTK runtime notice wraps selectable text and offers a native Dismiss action. Collection completion uses the existing native toast. The popup refresh notice sits outside the scrolling region, above the fixed footer. During refresh, the control is inactive and the notice remains through the implemented refresh window; a failed request leaves its error visible across snapshot updates and timeout until a retry or owner-state change resets it. This feedback reports the action state, not a guarantee that every account succeeded.

## Do's and Don'ts

### Do:

- **Do** inherit GNOME font, theme, window controls, symbolic icon foreground, and native widget behavior.
- **Do** reuse the extracted page gutter, card surface, relative typography, and native grouped rows.
- **Do** pair series color with a readable label and pass its index consistently to charts, dots, and share bars.
- **Do** keep recorded spend, estimated API value, subscriptions, balances, and quotas visibly distinct.
- **Do** preserve wrapping, scrolling, focus, availability, freshness, and action feedback at enlarged text sizes.
- **Do** use the original references for composition and the reviewed native captures for implemented geometry and states.

### Don't:

- **Don't** replace theme symbols with sampled light or dark screenshot colors.
- **Don't** import macOS window controls, font selection, update UI, or unsupported account capabilities into the Linux interface.
- **Don't** present synthetic capture content as real product data or a customer claim.
- **Don't** turn estimated API value into a bill or combine unrelated money and quota measures into an unexplained total.
- **Don't** clear last-known account data or persistent popup errors merely because another snapshot arrives.
- **Don't** treat illustrative web previews as authoritative GTK or Shell implementation code.
