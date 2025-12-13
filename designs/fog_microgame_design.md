# Microgame Design Document  
## **Project:** Emotional Playground  
## **Microgame:** **Fog**  
### *An AI-friendly specification for implementing EML-02 (Mechanics of Disorientation) in LÖVE*

---

# 🎯 Overview

**Fog** is a microgame exploring **disorientation** as a lived, embodied experience rather than a puzzle to be solved.

The goal is to evoke:
- cognitive fog  
- perceptual unreliability  
- anxiety caused by subtle rule drift  
- distrust of one’s own inputs and expectations  

The game avoids jump scares, explicit failure states, or overt horror.  
Instead, it creates a *slow erosion of certainty*.

This document is structured for direct collaboration with AI coding agents.

---

# 🧠 Core Experiential Thesis

Disorientation is not chaos.

It is the experience of:
- systems *almost* working  
- rules that *mostly* hold  
- perception being *slightly untrustworthy*  

The player should frequently think:
> “Did that just change, or am I imagining it?”

---

# 🔁 Core Loop Summary

1. Player navigates a small top-down space.  
2. Movement, camera, and rules initially feel stable.  
3. Subtle distortions are introduced:
   - directional remapping  
   - input latency variance  
   - camera offset drift  
   - inconsistent feedback  
4. Distortions escalate slowly and unevenly.  
5. Player attempts to re-learn rules that will not fully stabilize.  
6. Game ends when player stops seeking certainty.

---

# 🧱 System Architecture

The microgame should subclass `MicroGameBase`:

```
Fog = MicroGameBase:new(metadata)
```

### **Primary Systems**
- Player movement controller  
- Rule distortion manager  
- Input remapping system  
- Camera drift system  
- Feedback ambiguity generator  
- Stability / uncertainty meter (hidden)  

Each system should be modular and loosely coupled.

---

# 🗺️ Gameplay Space

A simple enclosed space, intentionally readable:

```
+-----------------------+
|                       |
|    ▢     ▢     ▢     |
|                       |
|         P             |
|                       |
|    ▢     ▢     ▢     |
|                       |
+-----------------------+
```

Legend:
- `P` = player start  
- `▢` = landmarks (unchanging geometry)

Landmarks never move — they are anchors of false certainty.

---

# 🌫️ Disorientation State

```
disorientation = 0.0  -- (0.0 to 1.0)
```

This value is never shown to the player.

### Disorientation increases by:
- +0.005/sec baseline  
- +0.02 when player changes direction frequently  
- +0.03 when player backtracks  
- +0.05 when player collides with walls  
- +random micro-spikes (0.005–0.02)

### Disorientation decreases by:
- Standing still briefly (-0.01/sec after 2s)  
- Slow, continuous movement in one direction  

This creates tension between exploration and grounding.

---

# 🎮 Player Movement & Input Distortion

### Base movement:
```
speed = 120
```

### Directional Drift (primary mechanic):

At low disorientation:
- Inputs map correctly.

At moderate disorientation (>0.3):
- One axis may invert briefly (1–2 seconds).
- Diagonal movement may bias toward one axis.

At high disorientation (>0.6):
- Inputs occasionally remap:
  - up → left  
  - right → down  

**Important:**  
Never remap *all* controls at once.

---

# ⏱️ Input Latency Variance

Introduce randomized input delay:

```
delay = lerp(0ms, 120ms, disorientation)
```

- Delay changes frame-to-frame slightly.  
- Player should feel “lag” but never cleanly measure it.

Optional:
- Delay applies more strongly to stopping than starting movement.

---

# 📷 Camera Drift

Camera does not fully center on the player.

```
cameraOffset = noise(time * 0.3) * disorientation * 40
```

Effects:
- Camera lags behind player direction.
- Occasionally recenters suddenly (false reassurance).

---

# 🔊 Feedback Ambiguity

### Visual feedback:
- Collision responses vary slightly.
- Some wall contacts do nothing.

### Audio feedback (optional):
- Footstep sounds occasionally miss or double.

---

# 🧭 Rule Instability Events

At random intervals, briefly alter one rule:

Examples:
- Movement speed increases by 10% for 3 seconds  
- Collision box shrinks slightly  
- Camera zoom changes subtly  

These events are:
- Not announced  
- Not repeated consistently  
- Never explained  

---

# 🧘 Grounding Mechanic (Optional)

Standing still for >2 seconds:
- Slowly reduces disorientation
- Stabilizes camera
- Restores correct input mapping

Relief is temporary.

---

# 🧩 End Condition

The game ends when the player:

1. Stops moving  
2. Disorientation is high (>0.7)  
3. Player remains still for 4 seconds  

Fade in:

```
"You stop trying to orient yourself.
The world does not resolve."
```

Fade out → return to menu.

---

# 📦 Data Structures (AI-Friendly)

### Player
```
player = { x, y, baseSpeed, velocity }
```

### Disorientation
```
disorientation = { value, driftRate, decayRate }
```

### Input Mapping
```
inputMap = { up, down, left, right, timer }
```

### Camera
```
camera = { x, y, offsetX, offsetY }
```

---

# 🛠️ Recommended Implementation Order

1. Stable player movement  
2. Disorientation accumulator  
3. Input latency variance  
4. Directional remapping  
5. Camera drift  
6. Rule instability events  
7. Grounding behavior  
8. End condition  

---

# ✔ Ready for Coding

This document is intended to be directly translated into a `fog/init.lua` microgame module.

Disorientation should feel *unsettling*, not mechanically confusing.
