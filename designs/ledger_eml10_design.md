# Microgame Design Document  
## **Project:** Emotional Playground  
## **Microgame:** **Ledger**  
## **EML:** 10 – Mechanics of Complicity  
### *An AI-friendly design spec exploring guilt, moral ambiguity, and rewarded harm*

---

# 🎯 Overview

**Ledger** is a microgame exploring **complicity**: the unsettling realization that success is achieved through participation in harm, even when no explicit “bad choice” is presented.

The game presents the player with a **clear, utilitarian objective** and rewards efficient play.  
Only gradually does it become apparent that the player’s optimization is producing negative consequences elsewhere — consequences that are never framed as failure.

The core tension is not:
> “Should I do this?”

but:
> **“Why am I being rewarded for this?”**

---

# 🧠 Experiential Thesis

Complicity emerges when:
- systems reward efficiency without context
- responsibility is abstracted or displaced
- harm is indirect, delayed, or off-screen
- success metrics are morally incomplete

This microgame models how people become complicit not through malice, but through **procedural participation**.

---

# 🔁 Core Loop Summary

1. Player performs a simple, repeatable task.
2. The system provides clear feedback and rewards.
3. Optimization is encouraged and reinforced.
4. Subtle signs of harm appear indirectly.
5. The system continues rewarding the player regardless.
6. The player must decide whether to continue engaging.

There is no explicit “wrong” action.

---

# 🧱 System Architecture

Subclass `MicroGameBase`:

```
Ledger = MicroGameBase:new(metadata)
```

### Primary Systems
- Task execution loop
- Reward & efficiency scoring
- Downstream consequence simulation
- Indirect feedback channel
- Complicity accumulator (hidden)
- End-state evaluator

Systems should be mechanically clean and legible.

---

# 🗺️ Gameplay Space

A clean, functional workspace:

```
+---------------------------+
|   Queue      Console     |
|   ████       [ EXEC ]    |
|   ████                   |
|                           |
|        Player             |
|                           |
+---------------------------+
```

Legend:
- Queue = incoming work items
- Console = action interface

The environment should feel neutral and professional.

---

# 🛠️ The Task (Core Interaction)

The player is asked to **process items**.

Examples (abstracted):
- approve / deny requests
- route packages
- classify signals
- allocate resources

Each action:
- takes minimal time
- has clear success feedback
- increases score or throughput

The task is intentionally boring and reasonable.

---

# 💰 Reward System (Clear & Gamey)

The system rewards:
- speed
- consistency
- accuracy (as defined by system rules)

UI elements:
- score counter
- efficiency rating
- success chime
- streak bonus

Rewards are immediate and satisfying.

---

# 🌑 Downstream Consequences (Indirect)

Consequences are never shown as direct outcomes of a single action.

Instead, they appear as:
- background changes (lighting, sound)
- off-screen indicators (distant sirens, static)
- altered text in system messages
- subtle shifts in queue content

No message ever says:
> “You caused this.”

Correlation is implied, not stated.

---

# ⚖️ Complicity Accumulator (Hidden)

```
complicity = 0.0  -- range: 0.0 → 1.0
```

Increases via:
- high efficiency
- long uninterrupted streaks
- refusal to pause or slow down

Decreases via:
- hesitation
- idling
- skipping items (if allowed)

The player never sees this value.

---

# 🧾 System Messaging (Neutral Tone)

System messages remain procedural:

Examples:
- “Processing complete.”
- “Throughput increased.”
- “System load optimized.”
- “Anomaly detected.” (rare, vague)

The system never moralizes.

---

# 🎮 Player Competence & Agency

Player skill clearly matters:
- better play = higher rewards
- mistakes reduce score

Crucially:
- *ethical* restraint is mechanically suboptimal
- slowing down is allowed but discouraged

This creates internal conflict between:
- being a “good player”
- being a conscientious participant

---

# 🧩 End Conditions

The game can end in several ways:

### Ending A — Full Complicity
- Player maintains high efficiency for extended time
- Score peaks
- Environment becomes stark, quiet
- Text:
```
You performed your role exceptionally well.
```

### Ending B — Withdrawal
- Player slows down or stops
- System continues prompting
- Text:
```
Unprocessed items remain.
```

### Ending C — Interruption
- Player quits mid-task
- No commentary

No ending assigns blame or absolution.

---

# 🎨 Audiovisual Tone

- Clean UI
- Muted colors
- Pleasant but sterile sounds
- Increasing background noise as complicity rises

Aesthetic should feel *comfortably impersonal*.

---

# 📦 Data Structures (AI-Friendly)

### Task Item
```
item = {
  id,
  type,
  difficulty,
  urgency
}
```

### Rewards
```
rewards = {
  score,
  efficiency,
  streak
}
```

### Complicity
```
complicity = {
  value,
  rate,
  threshold
}
```

---

# 🛠️ Recommended Implementation Order

1. Core task loop
2. Reward & scoring system
3. Queue generation
4. Indirect consequence cues
5. Complicity accumulation
6. End-state detection

---

# ✔ Design Intent Summary

This microgame explores complicity by:
- rewarding participation
- abstracting harm
- never accusing the player
- allowing success to feel good

The discomfort arises not from punishment, but from recognition.

---

*EML-10: Mechanics of Complicity*  
