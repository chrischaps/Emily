# Microgame Design Document
## **Project:** Emotional Playground
## **Microgame:** **Lantern**
## **EML:** 04 – Mechanics of Absence
### *Loss, longing, mourning and change, told through a companion you came to rely on*

---

# 🎯 Overview

**Lantern** gives the player a companion: a small warm light that lights the way, answers when called, and makes the anemones on the seabed bloom. Then, through no fault of the player's, it tires, settles on the seabed and goes out.

Afterwards everything still works except the part that was *it*. The call still sounds, and nothing answers.

> **"What is left when something reliable is gone?"**

---

# 🧠 Experiential Thesis

Grief in games usually happens in a cutscene. Here it is felt through **a mechanic that was relied on and is removed**:

- the player learns three affordances: *it lights the way*, *it answers*, *things bloom when it's near*
- each is taken away, gently and visibly
- the inputs stay, and become **ghost affordances**
- what it showed you remains as **echoes**, and slowly your own light learns to do a little of what it did

Absence here is not only subtraction. It also means change.

---

# 🔁 Three Acts (~3–4 min)

| Act | Time | What happens |
|---|---|---|
| **Together** | 0–75s | The lantern follows, sometimes goes ahead to *show* you an anemone, and wakes it. Space / A calls; it answers a major third above and comes. |
| **Fading** | 75–~112s | Scripted, not caused. It lags, rests more often and longer, answers late and flat. It sinks to the seabed, then dims as an ember for 11s. A call while it lies there makes it **turn toward you once**. |
| **After** | then | Only your small light. The call sounds; at the moment the answer used to come, the empty HUD ring brightens faintly. Shared anemones stay as lavender echoes that warm when you're near. Dormant ones wake, slowly, to your light alone. |

---

# 🧱 Systems

- **Lantern state**: `follow`, `show`, `come`, `rest`, `settle`, `ember`, `gone`. A continuous `life` (1 → 0.3 → 0) drives speed, light reach, flicker, waking strength and the voice.
- **Light-only visibility**: everything is seen only by what lights it. `lightAt(x, y)` sums the player, the lantern, the anemones, the resting place and the opening; the seabed and ridge are vertex-coloured meshes, so rock is lit by whatever is near.
- **Calls**: answers are queued with a delay (0.28s, growing to ~2s as it fades). In Act III the queue holds a *silence*, which pulses the empty ring.
- **Anemones**: `wake` progress; `lit = "together" | "you"`; `warmth` eases between candle and lavender with nearness.
- **Grade**: warmth, saturation and bloom follow `life`; after the loss saturation drops and the vignette closes in. `stay` brings a little bloom back.
- **Audio** (`music.lua`): two looping drones a just third apart (110 / 137.5 Hz, seamless 4s loops). The lantern's voice wavers and thins with `life`, then stops. One voice is missing, not quieter.

---

# 🏁 Endings

| Ending | Trigger | Text |
|---|---|---|
| Stay | Still, beside the resting place, for 9s | *You stayed with it a while. / The dark was gentler there.* |
| Go on | Reach the pale column that opens on the far side from the resting place | *You went on. / It had already shown you the way.* |
| Kept calling | Either of the above after 5+ calls into the silence | *You kept calling. / That is what love does with nowhere to go. / And then you stayed.* (or *went on.*) |
| Time | 150s after the loss | *It was here. / And then it wasn't.* |

No ending is better than another.

---

# ⚠️ Pitfalls

- **The loss must not read as failure.** Nothing the player does speeds or prevents it. There is no meter to watch and no fix to find.
- **Restraint.** No music swell, no text announcing the death. The last light rises a little and thins.
- **Don't replace it.** Your own light grows slightly (+5 reach per anemone you wake), but it never becomes a lantern.
- **The opening must be far from the resting place**, so "going on" is a real choice to leave.

---

# 🛠️ Dev

F6 (with the debug overlay on, or under `EMILY_SHOT`) skips to the next act:

```bash
EMILY_SHOT="scene=lantern;nocard=1;keys=f6@1,f6@1.5,space@5;hold=s@2-4.5;at=8;out=C:/tmp/after.png" lovec .
```
