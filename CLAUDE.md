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
- `scene_manager.lua` - Manages scene transitions and lifecycle delegation
- `microgame_base.lua` - Base class template for all microgames

**Scene System (`src/ui/`):**
- `menu_scene.lua` - Main menu for microgame selection
- `microgame_scene.lua` - Wrapper that manages active microgame instance

**Microgames (`src/microgames/`):**
- `registry.lua` - Catalogs all available microgames with metadata
- Each microgame in its own subdirectory with `init.lua`

## Adding a New Microgame

1. Create directory: `src/microgames/<name>/init.lua`
2. Extend `MicroGameBase` using metatable inheritance
3. Implement `create()` factory function returning instance with metadata:
   - `id`, `name`, `emlId`, `emotions` (table), `description`, `duration`
4. Implement lifecycle hooks: `load()`, `update(dt)`, `draw()`, `keypressed(key)`
5. Register in `src/microgames/registry.lua`

## Patterns

- **OOP via metatables**: Use `__index` for inheritance, `.new()` for construction, `:` for method calls
- **Lifecycle hooks**: All game objects implement optional `load`, `update(dt)`, `draw`, `keypressed`, `mousepressed`
- **Scene transitions**: Call `scene_manager.switchTo(sceneName, args)` to change scenes

## Window Configuration

960x540px, resizable (set in `conf.lua`)
