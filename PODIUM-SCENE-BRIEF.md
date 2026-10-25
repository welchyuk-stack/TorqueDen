# TORQUEDEN — "The Shot" Podium Scene · Design Brief

A single hero background image for the **results screen** of TorqueDen's weekly photo
competition, **"The Shot."** Winning car photos, medals, and names are composited over
this image **in the app** — so this brief is for the **empty stage only** (podium + wall
+ floor + lighting + bottles). Do **not** include cars, people, or placeholder photos.

---

## 1. What it's for

TorqueDen is a car-build community app. Each week members enter one photo of their car
into "The Shot." When the week ends, the **Results** tab shows the top three on a podium.
Today that podium is flat coloured boxes — we're replacing it with a **photoreal,
lifelike trophy-presentation scene**, like the winners' podium at a real motorsport event
(reference: Nürburgring 24h press podium), but fully **TORQUEDEN-branded**.

The app then drops each winner's **car photo** onto the top of its step, with a medal and
the car's name — so the finished screen looks like three cars standing on a real podium in
front of a branded sponsor wall.

---

## 2. Deliverable

| Item | Spec |
|------|------|
| Format | **PNG**, RGB, full-bleed (no transparency needed) |
| Aspect ratio | **4:5 portrait** — must be exact |
| Resolution | **1200 × 1500 px** (also export **@2x = 2400 × 3000 px** if easy) |
| Filename | `podium_scene.png` |
| Orientation | Portrait; scene fills the whole frame edge-to-edge |

The image is scaled to the phone's width in-app, so **keep the 4:5 ratio exactly** — the
overlay coordinates in §5 depend on it.

---

## 3. The scene

A **photorealistic 3D-rendered** victory podium in a studio / event setting:

- **Three podium steps**, glossy and solid, viewed from a slight **top-down three-quarter
  angle** so they have real depth and you can see the tops:
  - **Centre = tallest**, with a large **"1"** on its front face
  - **Left = middle height**, large **"2"**
  - **Right = lowest**, large **"3"**
  - Bake the numbers **1 / 2 / 3 into the step faces** (they never change) — printed or
    embossed, clean and legible.
- **Reflective stage floor** — the steps and bottles reflect softly into it (glossy,
  showroom-like, not a mirror).
- **Sponsor wall behind** the podium: a large board **densely tiled with the repeated
  wordmark "TORQUEDEN"** in a neat, even grid — exactly like the sponsor boards behind
  athletes at a press conference / race podium. Vary scale slightly row to row so it reads
  as a real printed backdrop, softly out of focus (depth of field).
- **Champagne / prosecco bottles** lined up along the **base** of the podium, front edge.
- **Stage lighting**: warm spotlights from above pooling on the steps; a subtle glow on
  the wall. Cinematic, premium, celebratory.

---

## 4. Brand & look

- **Accent colour — ember orange `#F26A21`**: use for the spotlights' warmth, a thin
  accent stripe across the **top of the sponsor wall**, and any rim/glow. This replaces the
  green splash seen in typical race podiums.
- **Base / background — charcoal `#101113`** (near-black, slightly warm).
- **Wordmarks / light details — cream `#F4EFE6`**; some TORQUEDEN repeats can be cream,
  others a low-opacity ember, for a layered printed-board feel.
- **Mood**: dark, premium, motorsport, high-contrast, glossy. Think detailing-studio meets
  race podium. Not cartoonish, not flat, not neon.
- **Typography of the baked "TORQUEDEN" text**: bold, condensed, confident sans (Space
  Grotesk / similar). All-caps wordmark. Consistent across the wall.

---

## 5. CRITICAL — keep three areas clear

The app composites each winner's **car photo + medal + name** onto the **top of each
step**. Those three zones must be **empty, unobstructed, and evenly lit** — no bottles, no
wall text creeping in, no props, no dark shadows across them. Just clean space above each
step where a roughly square photo can sit and read clearly.

Approximate zones (fractions of the 1200 × 1500 canvas; origin top-left; x/y = centre of
the zone):

| Step | Centre X | Centre Y | Width | Height |
|------|----------|----------|-------|--------|
| 1st (centre) | 0.50 | 0.32 | 0.30 | 0.22 |
| 2nd (left)   | 0.19 | 0.44 | 0.24 | 0.18 |
| 3rd (right)  | 0.81 | 0.50 | 0.24 | 0.18 |

These follow the step heights (centre highest, left middle, right lowest). They don't need
frames drawn in — just keep them clear and well-lit; the app draws the photo, medal, and
name label there.

---

## 6. Do / Don't

**Do**
- Photoreal 3D render, real materials and reflections
- TORQUEDEN sponsor wall, densely and evenly tiled
- Ember `#F26A21` lighting accents on a charcoal scene
- Champagne bottles at the base
- Numbers 1 / 2 / 3 baked onto the step faces
- Leave the three photo zones clean

**Don't**
- No cars, no people, no driver silhouettes
- No placeholder images or frames in the photo zones
- No green (replace race-podium green with ember)
- No flat/vector/cartoon style — must look rendered and lifelike
- No text other than "TORQUEDEN" (wall) and the numbers 1/2/3 (steps)

---

## 7. One-line prompt (if generating directly)

> Photorealistic 3D render of a motorsport victory podium — three glossy steps (centre
> tallest labelled "1", left "2", right "3") on a dark reflective studio floor, in front of
> a large sponsor wall densely tiled with the repeated word "TORQUEDEN" in a clean grid.
> Warm ember-orange (#F26A21) stage spotlights and a thin orange stripe across the top of
> the wall; charcoal (#101113) and cream (#F4EFE6) palette. A row of champagne bottles along
> the podium base. Cinematic studio lighting, soft depth of field on the back wall, slight
> top-down three-quarter camera angle. No people, no cars — keep the tops of the three steps
> clear and evenly lit. 4:5 portrait, high detail.

---

*When the PNG is ready, drop it in `Car App/assets/` — the app side (pubspec registration,
compositing the car photos/medals/names into the three zones, tap-through to the post
viewer) is already planned and will be wired up then.*
