# TorqueDen — Brand & Theme Guide

> A social community app for car enthusiasts — builds, mods, specs, parts and advice.
> This is the brand and visual-theme reference for building the app. Drop it into your repo
> (e.g. as `BRAND.md`) and point Claude Code at it when generating UI.

---

## 1. Brand at a glance

- **Name:** TorqueDen — one word, camelCase (capital `T`, capital `D`). Never all-caps.
- **What it is:** the digital garage-clubhouse for car people — show your build, log your mods, swap specs and advice, find your crew.
- **Concept:** a *den* is where your stuff lives and your people gather. TorqueDen = engine and power ("Torque") meeting warmth and belonging ("Den"). Not another sterile feed — a place with character.
- **Primary tagline:** *Where the build lives.*
- **Alternates:** *Pull up. Show your build.* · *For everyone who can't leave it stock.* · *Your garage. Your crew.*

---

## 2. Personality & voice

**Personality:** Knowledgeable but never gatekeeping. As welcoming to a first-time modder as to a seasoned builder. Garage grit over clean lines — real, warm, a little dry.

**Voice principles**
- Plain-spoken, enthusiast-to-enthusiast. No jargon for jargon's sake; explain it when it helps.
- Encouraging of builds at every level — a stock daily and a full restomod both belong.
- Confident and warm, never corporate or hype-y.

**Do / Don't**

| Do | Don't |
|----|-------|
| "Show us the build." | "Leverage our platform to showcase your vehicle." |
| "Nice work — what's next on it?" | Rank or gatekeep people by spend |
| "Stage 2 and climbing." | Overpromise or lean on hype-speak |

**Microcopy examples**
- Empty garage: "Your garage is empty. Add your first build."
- Post action: "Post an update"
- Follow states: "Follow" / "Following"
- Reaction: the "like" is a flame — *tap to give it a flame*

---

## 3. Logo

**Mark:** a rev gauge living inside a house — a pitched-roof "den" silhouette containing a tachometer, needle sweeping up into an ember redline. Meaning: *revs, at home.*

**Wordmark:** `TorqueDen` set in Archivo (heavy). "Torque" in Cream, "Den" in Ember.

**Usage**
- Primary lockup sits on dark (Carbon) backgrounds.
- Clear space: keep at least the height of the roof apex clear around the mark.
- App icon: the mark alone on Carbon.
- Don't: recolour the ember, stretch the mark, add gradients/shadows, or set the wordmark in all-caps.

**Mark SVG** (Cream + Ember, for dark backgrounds):

```svg
<svg width="96" height="96" viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="TorqueDen logo mark">
  <polygon points="30,92 30,50 60,26 90,50 90,92" fill="#1C2026" stroke="#F3ECE1" stroke-width="3" stroke-linejoin="round"/>
  <circle cx="60" cy="68" r="19" fill="none" stroke="#454B55" stroke-width="2"/>
  <line x1="73" y1="60.5" x2="76.5" y2="58.5" stroke="#FF6A2B" stroke-width="2.4" stroke-linecap="round"/>
  <line x1="69.6" y1="56.5" x2="72.2" y2="53.5" stroke="#FF6A2B" stroke-width="2.4" stroke-linecap="round"/>
  <line x1="65.1" y1="53.9" x2="66.5" y2="50.2" stroke="#FF6A2B" stroke-width="2.4" stroke-linecap="round"/>
  <line x1="60" y1="68" x2="72.3" y2="54.8" stroke="#FF6A2B" stroke-width="3" stroke-linecap="round"/>
  <circle cx="60" cy="68" r="3.6" fill="#FF6A2B"/>
</svg>
```

For light backgrounds: swap the Cream stroke (`#F3ECE1`) to Carbon (`#15171B`) and lighten the house fill.

---

## 4. Colour

Dark-mode-first. The app canvas is dark; **Ember is the single hot accent** — use it sparingly for CTAs, emphasis and "active" states. Overusing it kills the spark.

**Brand palette**

| Token | Hex | Use |
|-------|-----|-----|
| Carbon | `#15171B` | App background / ink |
| Graphite | `#1C2026` | Card surface |
| Graphite raised | `#23272E` | Elevated wells (media, inputs) |
| Hairline | `#2C313A` | Borders / dividers |
| Ember | `#FF6A2B` | Primary accent, CTAs, active, "flame" |
| Ember hover | `#F2581C` | Accent hover / pressed |
| Steel | `#7C8B99` | Secondary accent, inactive |
| Cream | `#F3ECE1` | Primary text, light marks |
| Text secondary | `#9AA3AD` | Secondary text |
| Text muted | `#8A929C` | Muted text / labels |
| On-ember | `#2A0F04` | Text + icons on ember fills |

**Functional / status** (kept restrained)

| Token | Hex |
|-------|-----|
| Success | `#4FB477` |
| Warning | `#E8A13A` |
| Danger | `#E5484D` |

**CSS custom properties** — paste into your global stylesheet:

```css
:root {
  /* surfaces */
  --td-bg:          #15171B;
  --td-surface:     #1C2026;
  --td-surface-2:   #23272E;
  --td-border:      #2C313A;
  /* accent */
  --td-ember:       #FF6A2B;
  --td-ember-hover: #F2581C;
  --td-on-ember:    #2A0F04;
  --td-steel:       #7C8B99;
  /* text */
  --td-text:        #F3ECE1;
  --td-text-2:      #9AA3AD;
  --td-text-muted:  #8A929C;
  /* status */
  --td-success:     #4FB477;
  --td-warning:     #E8A13A;
  --td-danger:      #E5484D;
  /* shape */
  --td-radius:      8px;
  --td-radius-card: 12px;
  --td-radius-pill: 999px;
}
```

**Tailwind** — `tailwind.config.js` → `theme.extend`:

```js
colors: {
  carbon:   '#15171B',
  graphite: { DEFAULT: '#1C2026', raised: '#23272E' },
  hairline: '#2C313A',
  ember:    { DEFAULT: '#FF6A2B', hover: '#F2581C', on: '#2A0F04' },
  steel:    '#7C8B99',
  cream:    '#F3ECE1',
},
fontFamily: {
  display: ['Archivo', 'system-ui', 'sans-serif'],
  sans:    ['Inter', 'system-ui', 'sans-serif'],
},
```

---

## 5. Typography

Two families: **Archivo** (display — wordmark, headings, big numbers) and **Inter** (UI / body).

Load:

```html
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@500;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
```

**Scale**

| Role | Font | Weight | Size / line |
|------|------|--------|-------------|
| Display / wordmark | Archivo | 800 | 32–40px / 1.0 · tracking -0.01em |
| H1 | Archivo | 700 | 28px / 1.2 |
| H2 | Archivo | 700 | 22px / 1.25 |
| H3 | Archivo | 600 | 18px / 1.3 |
| Body | Inter | 400 | 16px / 1.6 |
| Small | Inter | 400 | 14px / 1.5 |
| Caption / label | Inter | 500 | 12px / 1.4 |
| Stat value | Inter | 600 | 14–18px |

Headings are sentence case (never Title Case). The wordmark keeps its native casing: `TorqueDen`.

---

## 6. Shape, spacing, elevation

- **Radius:** controls/buttons `8px`, cards `12px`, pills/avatars `999px`.
- **Borders:** 0.5–1px hairline (`--td-border`). Lean on borders, not shadows.
- **Elevation:** flat — no drop shadows, no gradients. Separate layers with surface steps (`bg → surface → surface-2`) and hairlines.
- **Spacing scale:** `4 / 8 / 12 / 16 / 24 / 32` px.

---

## 7. Components

**Buttons**
- Primary: Ember fill, `--td-on-ember` text, radius 8px; hover → `--td-ember-hover`. One primary per view.
- Secondary: transparent, 1px `--td-border`, Cream text; hover lightens surface.
- Ghost/tertiary: text-only, Steel or Cream.

**Build card** — the core unit:
- Surface `--td-surface`, 1px `--td-border`, radius 12px.
- Anatomy: **header** (avatar + handle + location + Follow) → **media well** (`--td-surface-2`) → **title** (e.g. "Mk7 Golf R — Stage 2") → **spec strip** (Power / Mods / Build log) → **footer** (flame count, comments, "View build" in Ember).

**Tags / chips:** pill, 1px `--td-border`, Steel text. For emphasis (e.g. "Stage 2", category), use a subtle ember-tint background with Ember text.

**Stats:** label in `--td-text-muted` (12px), value in Cream (Inter 600).

---

## 8. Iconography & imagery

- **Icons:** outline set (Lucide or Tabler), 1.5–2px stroke, inheriting text colour. Reserve Ember for active/emphasis (e.g. the flame "like"). Common: `car`, `flame`, `message`, `bolt` (power), `settings` (mods), `bookmark`, `map-pin`.
- **Imagery:** real builds shot warm and low-light — night garage, workshop-lamp glow, shallow depth of field. Avoid sterile studio stock. Let Ember be the warm pop against dark surroundings.

---

## 9. Notes for implementation

- Dark-mode-first. A light theme is optional later (invert surfaces, darken text, keep Ember).
- Ember is an accent, not a background — the "single hot spark" is the point.
- Keep the UI flat and content-forward: the builds are the hero, the chrome stays quiet.

---

*TorqueDen — where the build lives.*
