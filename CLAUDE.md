# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Emily ("Emotional Playground") is a LOVE 2D (Lua) educational game focused on emotional learning through microgames. Each microgame simulates emotional experiences through gameplay mechanics.

## Expressive Mechanics Library (EML)

See `expressive_mechanics_library.md` for the full catalog. Each microgame implements one EML pattern:

| ID | Pattern | Emotions | Core Technique |
|----|---------|----------|----------------|
| EML-01 | Burden | Exhaustion, duty, drudgery | Friction that grows with effort (slowdowns, repetition, decay) |
| EML-02 | Disorientation | Confusion, anxiety, distrust | Input/output mismatch (shifting controls, camera drift) |
| EML-03 | Care | Tenderness, patience, responsibility | Quality of intention over quantity (gentle input, steady presence) |
| EML-04 | Absence | Loss, emptiness, mourning | Removing previously reliable mechanics/companions |
| EML-05 | Intimacy | Closeness, trust, vulnerability | Unlocks through attentive presence or sync |
| EML-06 | Temptation | Impulse, curiosity, internal conflict | Short-term reward vs subtle long-term cost |
| EML-07 | Ambivalence | Moral uncertainty, mixed emotions | All choices simultaneously help and harm |

When creating microgames, reference the EML entry for implementation notes and pitfalls. The `emlId` field in microgame metadata links to these patterns.

## Running the Game

```bash
love .
```

Requires LOVE 2D runtime installed (https://love2d.org/).

## Architecture

**Data Flow:**
```
LOVE Framework → main.lua → game.lua → scene_manager.lua → Current Scene → Microgame
```

**Core Systems (`src/core/`):**
- `game.lua` - Main controller, delegates LOVE callbacks to scene manager
- `scene_manager.lua` - Scene lifecycle; `switchTo` dissolves through darkness, `setScene` cuts. Calls `unload` on the outgoing scene
- `theme.lua` - The visual language: palette, per-EML hues, fonts, `glow`/`blob`/`lightOrb`, easing, and the mood that drives post-processing
- `visual_effects.lua` - Per-game ambient particles, trails and bursts (presets: `burden`, `disorientation`, `intimacy`, `complicity`)
- `microgame_base.lua` - Base class template for all microgames
- `devshot.lua` - Dev-only screenshot harness (see Verifying Visuals)

**Rendering:** every frame draws into a 960x540 float canvas (MSAA, stencil) that `LoveLibs/graphics/postfx.lua` blooms, grades, vignettes and dithers before presenting it letterboxed. Debug overlays draw afterwards via a scene's `drawOverlay`.

**Scene System (`src/ui/`):**
- `menu_scene.lua` - "The Pool": each microgame is a creature of light in its EML hue
- `microgame_scene.lua` - Wraps a microgame with a title card, pause panel and shared ending card
- `settings_scene.lua` - Volume sliders

**Microgames (`src/microgames/`):**
- `registry.lua` - Catalogs all available microgames with metadata
- Each microgame in its own subdirectory with `init.lua`

## Adding a New Microgame

1. Create directory: `src/microgames/<name>/init.lua`
2. Extend `MicroGameBase` using metatable inheritance
3. Implement `create()` factory function returning instance with metadata:
   - `id`, `name`, `emlId`, `emotions` (table), `description`, `duration`
4. Implement lifecycle hooks: `load()`, `update(dt)`, `draw()`, `keypressed(key)`
5. Optional: `getEndingText()` returns the line(s) for the shared ending card (`\n` separates lines). Fade your own scene to black, then set `finished`; don't draw ending text yourself
6. Optional: `cleanup()` stops any audio the game owns; it runs when the player leaves for the menu
7. Register in `src/microgames/registry.lua`

## Patterns

- **OOP via metatables**: Use `__index` for inheritance, `.new()` for construction, `:` for method calls
- **Lifecycle hooks**: All game objects implement optional `load`, `update(dt)`, `draw`, `keypressed`, `mousepressed`
- **Scene transitions**: Call `scene_manager.switchTo(scene, { out = s, inn = s }, ...)` to dissolve to a scene

## Art Direction: Living Light

Feelings are drawn as bioluminescent organisms in deep water. Darkness is the canvas; light is what matters.

| Pattern | Games | Hue (`theme.hues.*`) |
|---|---|---|
| Burden | Carry, Weight | `burden`: ember amber |
| Disorientation | Fog, Fog (Anchors), Fog (Exit) | `disorientation`: sodium-grey cyan |
| Intimacy | Hold | `intimacy`: rose and peach |
| Complicity | Ledger | `complicity`: clinical mint, souring to yellow |
| Shell | Menu, settings | `shell`: moonlight |

- **Light is additive.** Use `theme.glow` / `theme.glowEllipse` for halos. Never stack translucent circles; they band visibly.
- **Darkness uses `theme.darknessAround`** for soft-edged vignettes. The general vignette lives in the grade (`theme.setVignette`).
- **Shapes are alive.** Use `theme.blob` for bodies and `theme.lightOrb` for a complete living light.
- **The grade carries the feeling.** Each game sets its mood from its EML id automatically. Push per-frame changes with `theme.setModifiers({ saturation = ..., bloom_intensity = ... })` and `theme.setDistortion(0..1)`.
- **Type:** Cormorant Garamond (`theme.font("display" | "poem", size)`) for names and words that carry feeling; Nunito (`"ui"`, `"uiBold"`) for everything else. Fonts are cached; never call `love.graphics.newFont` in a draw loop.
- **Gotcha:** postfx draws its canvases with the current colour. `theme.endFrame` resets it to white first; keep that if you touch the pipeline.

## Verifying Visuals

`EMILY_SHOT` drives the game unattended and saves PNGs (see the header of `src/core/devshot.lua`):

```bash
EMILY_SHOT="scene=hold;nocard=1;hold=a@0.5-3;at=2,6;out=C:/tmp/hold.png" lovec .
```

Options: `scene` (menu or a microgame id), `keys`, `hold`, `at`, `ending`/`endtext`, `size=WxH`, `perf=1` (frame times). `record=a-b;dir=...` saves every frame between a and b seconds as numbered PNGs, and `fps=30` steps the clock by exactly 1/fps (alone, it makes probe stills match a recording). `EMILY_DENSITY=2` renders the 960x540 world at twice the pixel density; pair it with `size=1920x1080` for full-resolution stills and films. Inside a draw, reset the transform with `theme.origin()`, never `love.graphics.origin()`, or density captures break. `EMILY_FX=bypass|nomsaa|rgba8` isolates pipeline problems; Shift+F1–F4 toggle bypass, distortion, bloom and grade in game.

## Libraries

`LoveLibs/` is a git subtree of https://github.com/chrischaps/LoveLibs. The `postfx` options `canvasFormat`, `msaa`, `stencil` and `bloom.passes` were added here; push them upstream with `git subtree push --prefix=LoveLibs https://github.com/chrischaps/LoveLibs.git <branch>`.

## Window Configuration

960x540px virtual resolution, resizable and letterboxed (set in `conf.lua`)
