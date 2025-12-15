# Microgame Design Document  
## **Project:** Emotional Playground  
## **Microgame:** **Hold**  
## **EML:** 05 – Mechanics of Intimacy  
### *An AI-friendly design spec exploring closeness, trust, and vulnerability through interaction*

---

# 🎯 Overview

**Hold** is a microgame exploring **intimacy** as an interactive state created through *attentive presence, restraint, and mutual responsiveness*.

Unlike games that reward efficiency, speed, or dominance, this experience rewards:
- patience
- sensitivity
- staying with uncertainty
- resisting the urge to optimize

The core question is not *“Can you do this?”* but:

> **“Can you remain present without forcing an outcome?”**

---

# 🧠 Experiential Thesis

Intimacy is not achieved through action alone.

It emerges when:
- two agents adapt to one another
- force breaks the connection
- attention sustains it
- vulnerability introduces risk

This microgame models intimacy as a **fragile, co-regulated state** that exists only while both sides remain attuned.

---

# 🔁 Core Loop Summary

1. Player encounters another entity (“the Other”).
2. Interaction is possible but undefined.
3. Gentle, sustained presence increases closeness.
4. Forceful, impatient, or inconsistent input breaks connection.
5. The player learns intimacy through *negative space*.
6. The game ends when intimacy is either sustained or ruptured.

---

# 🧱 System Architecture

Subclass `MicroGameBase`:

```
Hold = MicroGameBase:new(metadata)
```

### Primary Systems
- Player movement & proximity sensing
- Other-agent responsiveness system
- Intimacy accumulator (bidirectional)
- Fragility / rupture system
- Feedback through subtle audiovisual cues
- End-state evaluator

Systems should privilege *continuous values* over discrete states.

---

# 🗺️ Gameplay Space

A minimal, quiet space with no obstacles:

```
+---------------------+
|                     |
|        O            |
|                     |
|            P        |
|                     |
+---------------------+
```

Legend:
- `P` = player
- `O` = the Other

The emptiness emphasizes relational focus.

---

# 🤝 The Other (Core Relational Agent)

The Other is:
- not an enemy
- not a puzzle
- not controllable

It responds to the player but retains autonomy.

### Behavioral States
```
other.state = "guarded" | "attuning" | "open" | "withdrawn"
```

Transitions are smooth and reversible.

---

# 📏 Proximity & Presence Mechanics

Distance matters, but not in a binary way.

```
intimacyDelta ∝ proximity * stillness * consistency
```

Key factors:
- **Proximity:** being near but not colliding
- **Stillness:** reduced movement velocity
- **Consistency:** similar behavior over time

Moving too fast or erratically decreases intimacy.

---

# ⚖️ Intimacy Accumulator

```
intimacy = 0.0  -- range: 0.0 → 1.0
```

### Increases via:
- staying within an optimal distance band
- minimal input jitter
- mirroring movement subtly
- pauses (doing nothing)

### Decreases via:
- sudden movement
- overshooting proximity
- abrupt withdrawal
- repeated approach–retreat cycles

The player never sees the numeric value.

---

# 🫧 Fragility & Rupture

At higher intimacy:
- the system becomes *more fragile*
- mistakes have larger consequences

This models vulnerability:  
the closer you are, the more there is to lose.

```
ruptureChance ∝ intimacy * forcefulness
```

A rupture causes:
- the Other to withdraw
- audiovisual cues to dim
- intimacy to reset partially or fully

Rupture is not framed as failure — it is part of the experience.

---

# 🎨 Feedback Systems (Subtle, Non-Verbal)

### Visual:
- soft glow between P and O
- gentle pulsing synced over time
- color warmth increasing with intimacy

### Audio:
- low harmonic tone that stabilizes
- dissonance when intimacy drops
- silence during rupture

No explicit UI, text, or meters.

---

# 🎮 Player Competence (Careful Framing)

Player skill matters, but not in the usual way.

Competence here is:
- emotional regulation
- restraint
- sensitivity to feedback

There is no optimal strategy, only attunement.

---

# 🧘 End Conditions

### Ending A — Sustained Intimacy
- Player maintains high intimacy for several seconds
- The Other remains open
- Fade out with text:
```
You stayed.
```

### Ending B — Rupture
- Intimacy breaks and the player does not re-engage
- The Other withdraws fully
- Fade out with text:
```
You reached too quickly.
```

### Ending C — Withdrawal
- Player leaves the space
- Fade out silently

No ending is labeled “success” or “failure.”

---

# 📦 Data Structures (AI-Friendly)

### Player
```
player = {
  x, y,
  velocity,
  lastInputDelta
}
```

### Other
```
other = {
  x, y,
  state,
  responsiveness
}
```

### Intimacy
```
intimacy = {
  value,
  growthRate,
  decayRate,
  fragility
}
```

---

# 🛠️ Recommended Implementation Order

1. Basic movement & proximity detection
2. Other-agent idle & response behavior
3. Intimacy accumulation logic
4. Fragility / rupture tuning
5. Audiovisual feedback
6. End-condition detection

---

# ✔ Design Intent Summary

This microgame treats intimacy as:
- emergent
- fragile
- co-created
- impossible to force

The player does not *take* intimacy.
They participate in it — briefly, imperfectly, or not at all.

---

*EML-05: Mechanics of Intimacy*  
