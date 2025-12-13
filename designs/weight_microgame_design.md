# Microgame Design Document  
## **Project:** Emotional Playground  
## **Microgame:** **Weight**  
### *An AI‑friendly specification for implementation in LÖVE (Love2D)*

---

# 🎯 Overview

**Weight** is a microgame exploring the experiential texture of **burden** through layered interactive mechanics.  
The player navigates a small 2D top-down space while systemic forces gradually impose:

- friction  
- perceptual narrowing  
- cognitive interference  
- erosion of freedom  
- accumulation of “shadows” (symbolic burdens)

There is **no explicit score or goal**. The emotional arc emerges from interacting with the system.

This document is structured for collaboration with AI coding agents (Claude Code, Cursor, etc.).  
It includes clear sections, implementation notes, and modular behavior lists.

---

# 🧱 Core Loop Summary

1. Player moves freely in a top‑down 2D space.  
2. Invisible “burden level” increases via:
   - contact with shadow entities  
   - time spent  
   - overexertion  
3. Burden level triggers progressive modifiers:
   - slower movement  
   - input viscosity (micro‑lag)  
   - world dimming & shrinking field of view  
   - shadow followers becoming harder to remove  
   - intrusive text messages  
4. Player may attempt to “lighten load” at cleansing zones.  
5. Some burdens detach, others resist, and one becomes permanent.  
6. Game ends when the player returns to center and stays still.

---

# 🧩 System Architecture

The microgame should subclass `MicroGameBase`:

```
Weight = MicroGameBase:new(metadata)
```

### **Primary Systems**
- Player movement controller  
- Burden accumulator  
- Shadow entity manager  
- Input viscosity modifier  
- Visual vignette / dimming system  
- Intrusive text system  
- World degradation (optional V1.0: locked tiles)  
- Burden release logic  

Each system should be implemented as self-contained update/utility functions so an AI agent can evolve them individually.

---

# 🧪 Gameplay Space & World Layout

### Suggested layout (simple for AI generation):

```
+---------------------------+
|           ????            |
|     S           S         |
|                           |
|       C     P     C       |
|                           |
|     S           S         |
|           ????            |
+---------------------------+
```

Legend:  
- `P` = player start (center)  
- `S` = shadow spawn points  
- `C` = cleansing zones (attempt burden release)  
- `????` = areas that dim more quickly  

AI can generate a 2D table or direct coordinate placements.

---

# ⚖️ Burden Level

```
burden = 0.0 -- (0.0 to 1.0)
```

### Burden increases by:
- +0.01/sec baseline  
- +0.05 on shadow touch  
- +0.03 per second while moving continuously  
- +0.1 when sprinting (optional feature)  
- +random small increments (emotional realism)

### Burden decreases by:
- -0.05 on successful cleansing  
- -0.02 on resting still for > 2 seconds  
- never below 0  

### Burden caps:
- Soft cap at 1.0  
- Can “overflow” to 1.2 internally, but UI clamps — used for spikes.

---

# 👤 Player Mechanics

### Base state:
```
speed = 120
```

### Modified by burden:
```
effectiveSpeed = speed * (1 - burden^2 * 0.7)
```

Non-linear = more realistic emotional curve.

### Input viscosity:
When burden > 0.3:
- Add 20–80ms randomized movement lag  
- Add velocity overshoot when stopping  

When burden > 0.7:
- 5–10% of input frames are ignored  
- Occasional “sticky direction” (keeps walking briefly)

All effects should be gentle, not comedic.

---

# 👥 Shadow Mechanics

Shadows float around and latch onto player:

```
shadow.state = "free" | "following" | "attached"
```

### Behaviors:
- Free shadows wander with slow noise movement.  
- When near player → become **following**.  
- On contact → become **attached** and increase burden.  
- Attached shadows circle around the player at varying radii.

### Detachment:
Only possible at cleansing zones.  
But:
- 70% chance to detach  
- 20% chance to partially detach (visual half-opacity)  
- 10% chance become **permanent shadow**

Permanent shadow = symbolic irreducible burden.

---

# 🎨 Visual Burden Effects

### 1. **Vignette Dimming**
Use a screen‑space darkening overlay:

```
alpha = 0.2 + burden * 0.6
```

### 2. **Field-of-View Shrink**
Draw full scene, then overlay black with a circular hole:

```
radius = lerp(300, 120, burden)
```

### 3. **Avatar Deformation**
Player sprite scales non-uniformly:

```
sx = 1 - burden * 0.2
sy = 1 + burden * 0.25
rotation = sin(time * 2) * burden * 0.05
```

### 4. **Screen Distortion**
Optional for later versions (shader-based).

---

# 📜 Intrusive Text System

Messages appear semi-randomly when burden > 0.4:

Examples:
- “Maybe go back.”  
- “This is too much.”  
- “Are you sure?”  
- “Not again.”  
- “Slow down…”  

Implementation:

```
if burden > threshold and random chance fires:
    activeMessage = pickRandom(messageList)
    fade for 1.5s
```

Messages should never overlap; reuse same draw layer for simplicity.

---

# 🌫️ World Degradation (Optional V1)

Tiles become blocked when burden > 0.6.  
Implement as a small set of coordinates the player cannot walk through.

Later versions may visually crack or darken tiles.

---

# 🧘 End Condition

When the player:

1. Returns to the center tile  
2. Stands still for 3 seconds  
3. Burden level stabilizes (no spikes)

Then fade in:

```
"Some burdens lift. 
 Some lighten. 
 Some become part of you."
```

Fade out → return to microgame menu.

---

# 📦 Data Structures (AI-agent friendly)

### Player
```
player = {
  x, y,
  baseSpeed,
  burdenSpeed,
  lastMoveTime,
  spriteState
}
```

### Shadows
```
shadows = {
  {x, y, state, angle, distance},
  ...
}
```

### Burden
```
burden = {
  value,
  rateBase,
  rateMovement,
  rateShadow,
  intrusionTimer
}
```

### Messages
```
messages = {
  list = {...},
  active = nil,
  alpha = 0,
  timer = 0
}
```

---

# 🧭 Implementation Order (Recommended for AI)

1. Player movement  
2. Burden accumulation  
3. Shadow behavior  
4. Visual dimming  
5. Input viscosity  
6. Intrusive messages  
7. Avatar deformation  
8. Cleansing zones & detachment logic  
9. End state  

---

# ✔ Ready for Coding

This spec is written to be directly translated into a `init.lua` microgame module and plugged into your existing LÖVE project architecture.

If you need:
- A **downloadable zip**
- A **ready-made Lua implementation**
- Integration into your repo structure  

Just ask!

