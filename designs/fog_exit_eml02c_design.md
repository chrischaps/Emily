# Microgame Design Document  
## **Project:** Emotional Playground  
## **Microgame:** **Fog (Exit)**  
## **EML:** 02c – Disorientation with Concrete, Game‑Like Goals  
### *An AI‑friendly design spec exploring Kafkaesque disorientation through explicit objectives*

---

# 🎯 Overview

**Fog (Exit)** is a variant of *Fog* that deliberately introduces a **clear, videogame‑legible objective**:

> **Reach the exit.**

Unlike traditional goal‑based games, difficulty does not come from enemies, puzzles, or player skill alone.  
Instead, the antagonistic force is **disorientation itself** — perceptual drift, rule instability, and systemic pushback.

This design intentionally allows *gamey tropes* (UI, chimes, counters, success feedback) to coexist — and clash — with an unstable world, using contrast as an expressive tool.

---

# 🧠 Experiential Thesis

This microgame explores the tension between:

- **Clear intention** (“I know what I’m supposed to do”)
- **Player competence** (“I can execute this mechanically”)
- **Systemic resistance** (“The system does not reliably acknowledge correctness”)

The player is not confused about the *goal*.  
They become uncertain about whether **doing the right thing is sufficient**.

This mirrors:
- internal cognitive struggle (anxiety, dissociation, executive dysfunction)
- institutional struggle (Kafka, bureaucracy, procedural absurdity)
- videogame literacy being turned against the player’s expectations

---

# 🔁 Core Loop Summary

1. Player is shown an exit and instructed to reach it.
2. Early interactions behave as expected.
3. Disorientation systems activate gradually.
4. Exit interactions remain *legible* but become unreliable in nuanced ways.
5. Player oscillates between confidence and doubt.
6. The goal remains visible and concrete throughout.
7. The game ends when the player reaches the exit *without certainty* or stops trying to resolve the ambiguity.

---

# 🧱 System Architecture

Subclass `MicroGameBase`:

```
FogExit = MicroGameBase:new(metadata)
```

### Primary Systems
- Player movement (competence‑based, mostly stable)
- Disorientation accumulator
- Exit validation system (new)
- Gamey UI feedback layer
- Input distortion & camera drift (inherited)
- Rule explanation vs rule execution divergence
- End‑state evaluator

All systems should be **internally consistent**, even when outcomes are ambiguous.

---

# 🗺️ Gameplay Space

A simple, readable layout emphasizing clarity:

```
+-------------------------+
|                         |
|      ▢           ▢      |
|                         |
|   P                 E   |
|                         |
|      ▢           ▢      |
|                         |
+-------------------------+
```

Legend:
- `P` = player start
- `E` = exit
- `▢` = inert landmarks

The space should be easy to navigate *mechanically*.

---

# 🏁 The Exit (Core Goal Object)

The exit is:
- clearly marked
- visually distinct
- reinforced by UI cues

Examples:
- glowing tile
- animated arrow
- text label (“EXIT”)

The player should never doubt *where* the exit is.

---

# ⚖️ Exit Validation System (Critical Design Element)

Rather than the exit being broken or random, it operates under **rules that are internally consistent but not fully visible**.

### Validation Inputs (examples):
- approach angle
- movement speed on approach
- recent control remaps
- player hesitation or overshoot
- disorientation level
- time since last exit attempt

### Validation Output:
```
exitResult = "accept" | "reject" | "partial"
```

---

## 🟢 Early Phase (Trust)

- Exit accepts interaction reliably.
- Player receives:
  - success chime
  - UI confirmation (“Checkpoint Reached” or similar)
- Player builds confidence.

---

## 🟡 Mid Phase (Doubt)

- Exit accepts interaction *conditionally*.
- Same action may:
  - succeed once
  - fail another time
- Failure is *soft*:
  - muted sound
  - delayed feedback
  - ambiguous UI (“Processing…”)

Important:  
**Failure is never silent.**  
The system always responds — just not reassuringly.

---

## 🔴 Late Phase (Procedural Absurdity)

- Exit may:
  - accept but not end the game
  - partially validate (“Almost”)
  - validate only after seemingly incorrect behavior (hesitation, backing away)

Rules do not contradict themselves — they merely depend on hidden state.

This avoids the impression of bugs.

---

# 🎮 Player Competence & Controls

Player controls remain **largely responsive**:

- movement accuracy still matters
- overshooting the exit can prevent validation
- careful alignment improves chances

This preserves:
- a sense of agency
- a feeling that *you are not incompetent*

Disorientation interferes with *interpretation*, not execution.

---

# 🎨 Gamey UI Feedback (Intentional Contrast)

The game uses deliberately videogame‑y elements:

- coin counter (worthless)
- progress bar that fills inconsistently
- success/failure chimes
- achievement‑style popups (“EXIT ATTEMPTED”)

These elements:
- appear authoritative
- contradict lived experience
- reinforce the sense of bureaucratic opacity

---

# 🧭 Disorientation Systems (Inherited & Tuned)

From EML‑02:
- input latency variance
- subtle directional remapping
- camera drift
- inconsistent collision response

In *Fog (Exit)* these systems:
- never fully prevent reaching the exit
- interfere with **confidence**, not **possibility**

---

# 🧘 Player Interpretation Loop

Over time, the player cycles through:

1. “I did it wrong.”
2. “The timing was off.”
3. “Maybe it wants something specific.”
4. “I don’t know what it wants.”
5. “I reached the exit.”

This internal dialogue is the core experience.

---

# 🧩 End Conditions (Non‑Binary)

The game can end in multiple acceptable states:

### Ending A — Ambiguous Success
- Exit validates
- Game ends without strong confirmation
- Text:
```
You reached the exit.
Whether it counted is unclear.
```

### Ending B — Exhaustion
- Player stands at exit repeatedly
- Disorientation remains high
- Player stops moving
- Text:
```
You did everything you were asked.
The system did not clarify.
```

### Ending C — Quiet Acceptance
- Player reaches exit once more
- No chime
- Fade out
- Text:
```
The exit was always there.
```

No ending is labeled as “correct”.

---

# 📦 Data Structures (AI‑Friendly)

### Exit
```
exit = {
  x, y,
  radius,
  validationState,
  lastAttemptTime
}
```

### Validation Context
```
exitContext = {
  approachSpeed,
  angle,
  hesitationTime,
  disorientationLevel
}
```

### UI Feedback
```
ui = {
  coins,
  messages,
  progressBarState
}
```

---

# 🛠️ Recommended Implementation Order

1. Base Fog movement + disorientation
2. Exit detection & interaction
3. Exit validation logic
4. Gamey UI feedback layer
5. Ambiguous response tuning
6. End‑state detection & text

---

# ✔ Design Intent Summary

This microgame embraces:
- **Concrete goals**
- **Videogame tropes**
- **Player competence**
- **Systemic antagonism**

Disorientation is not the absence of rules —  
it is the presence of rules that refuse to fully reveal themselves.

---

*EML‑02c: Disorientation through Goal Antagonism*  
