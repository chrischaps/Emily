# Microgame Design Document  
## **Project:** Emotional Playground  
## **Microgame:** **Fog (Anchors)**  
## **EML:** 02b – Disorientation with Unreliable Goals  
### *An AI-friendly design spec for a goal-oriented disorientation variant*

---

# 🎯 Overview

**Fog (Anchors)** is a variant of the original *Fog* microgame that introduces a **goal-shaped attractor** without collapsing the experience into a solvable objective.

The player is given a *reasonable human goal*:

> **Find stable reference points to orient yourself.**

Over time, this goal becomes unreliable, incomplete, and emotionally ambiguous.

The game explores not just disorientation of **controls and perception**, but disorientation of **purpose**.

---

# 🧠 Experiential Thesis

When people feel disoriented, they do not stop seeking meaning.  
They seek **anchors**.

This microgame models:
- the instinct to orient oneself  
- the relief of temporary grounding  
- the anxiety when anchors stop working  
- the eventual realization that orientation may not be fully recoverable  

The goal remains present even as its usefulness erodes.

---

# 🔁 Core Loop Summary

1. Player explores a small, readable space.
2. Distortion systems gradually activate (as in Fog / EML-02).
3. Player discovers **Anchors** — landmarks that briefly stabilize the world.
4. Player begins seeking anchors intentionally.
5. As disorientation increases:
   - anchors become unreliable
   - some stabilize incorrectly
   - some increase disorientation
6. Player continues seeking anchors despite diminishing returns.
7. Game ends when the player stops seeking external confirmation.

---

# 🧱 System Architecture

The microgame subclasses `MicroGameBase`:

```
FogAnchors = MicroGameBase:new(metadata)
```

### Primary Systems
- Player movement
- Disorientation accumulator
- Anchor system (new)
- Input distortion
- Camera drift
- Feedback ambiguity
- Goal erosion logic
- End-condition monitor

Each system should be modular and independently adjustable.

---

# 🗺️ Gameplay Space

A simple, symmetrical space to encourage false confidence:

```
+---------------------------+
|           A       A       |
|                           |
|      ▢           ▢        |
|                           |
|            P              |
|                           |
|      ▢           ▢        |
|                           |
|           A       A       |
+---------------------------+
```

Legend:
- `P` = player start
- `A` = anchor points
- `▢` = inert landmarks (never stabilize)

Symmetry is intentional: it makes misorientation more plausible.

---

# 🌫️ Disorientation State

```
disorientation = 0.0  -- range: 0.0 → 1.0
```

Hidden from the player.

### Increases via:
- baseline time (+0.004/sec)
- rapid direction changes
- backtracking
- collisions
- failed anchor interactions
- random micro-spikes

### Decreases via:
- brief stabilization near anchors
- standing still
- slow, uninterrupted movement

---

# ⚓ Anchor System (Core Addition)

Anchors are **goal objects** that promise orientation.

### Anchor States
```
anchor.state = "stable" | "degraded" | "corrupted"
```

#### Stable (early game)
- Recenters camera
- Removes input remapping
- Reduces disorientation temporarily

#### Degraded (mid game)
- Partial stabilization
- One distortion remains active
- Effect duration reduced

#### Corrupted (late game)
- Stabilizes the *wrong* axis
- Recenters camera incorrectly
- Slightly increases disorientation
- Feels like betrayal, not danger

Anchor state transitions are global and tied to disorientation level, not individual anchors.

---

# 🎮 Player–Anchor Interaction

When player enters anchor radius:

```
if anchor.state == "stable":
    stabilize()
elif anchor.state == "degraded":
    partially_stabilize()
elif anchor.state == "corrupted":
    destabilize_subtly()
```

Anchors never explain their behavior.

The player infers meaning through repeated interaction.

---

# 🔁 Goal Erosion Logic

The **goal never disappears**.

Instead:
- Fewer anchors work
- Effects weaken
- Outcomes become inconsistent

Player behavior shifts from:
> “Find anchors to orient myself”

to:
> “Maybe this one will work”

This erosion is the emotional center of the variant.

---

# 📷 Distortion Systems (Inherited from Fog)

All original Fog systems apply:
- input latency variance
- directional remapping
- camera drift
- inconsistent collision feedback
- rule instability events

Anchors temporarily suppress these — until they don’t.

---

# 🪞 Inert Landmarks (False Confidence)

Non-anchor landmarks:
- never stabilize
- never move
- appear visually trustworthy

Players often misattribute anchor-like power to them early on.

This reinforces uncertainty.

---

# 🧘 Grounding vs Anchors

Standing still still reduces disorientation.

Design tension:
- **Anchors** offer fast but unreliable relief.
- **Stillness** offers slow but dependable relief.

Players choose between:
- seeking external certainty
- practicing internal grounding

Neither fully resolves disorientation.

---

# 🧩 End Condition

The game ends when:

1. Disorientation is high (>0.7)
2. Player approaches anchors repeatedly without improvement
3. Player stands still for 4 seconds **without seeking an anchor**

Fade in text:

```
You stop looking for something to confirm where you are.
Nothing resolves.
But nothing collapses.
```

Fade out → return to menu.

---

# 📦 Data Structures (AI-Friendly)

### Anchors
```
anchors = {
  {x, y, state, radius},
  ...
}
```

### Disorientation
```
disorientation = {
  value,
  baselineRate,
  spikeRate
}
```

### Goal State
```
goal = {
  active = true,
  effectiveness = lerp(1.0, 0.0, disorientation)
}
```

---

# 🛠️ Recommended Implementation Order

1. Base Fog movement + distortion
2. Disorientation accumulator
3. Anchor entities
4. Anchor stabilization effects
5. Anchor degradation logic
6. Goal erosion tuning
7. End-condition detection

---

# ✔ Design Intent Summary

This variant adds:
- **Purpose without resolution**
- **Goals that decay instead of completing**
- **Human-aligned motivation**
- **A richer emotional arc**

The player is not meant to *win*.

They are meant to recognize when seeking certainty stops helping.

---

*EML-02b: Disorientation with Unreliable Anchors*  
