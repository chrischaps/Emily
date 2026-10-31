# Emily

Emily, the Emotional Playground, is a set of small rooms for feeling things. Each microgame takes one pattern from the Expressive Mechanics Library, a catalogue of ways a mechanic can carry an emotion, and builds a short game around it: buckets that slow you down for burden, controls that drift for disorientation, a companion light that goes out for absence. There is nothing to win. Every feeling is drawn as a creature of light in deep water, and each game ends on a single line that names what it made you feel.

**Project page:** [chaps.dev/projects/emily](https://chaps.dev/projects/emily/) has a film of the Pool where you choose a room, clips of Carry, Weight, Fog (Anchors), Hold, Lantern and Ledger, and stills from every game.

![Eight rooms side by side, each in its own light](https://chaps.dev/projects/emily/cover.jpg)

## Running it

Emily runs on [LÖVE](https://love2d.org/) 11. From the repository root:

```bash
love .
```

`EMILY_SHOT` drives the game unattended and saves PNGs; its options are documented at the top of `src/core/devshot.lua`. For example, with `lovec`, the console build of LÖVE on Windows:

```bash
EMILY_SHOT="scene=hold;nocard=1;hold=a@0.5-3;at=2,6;out=C:/tmp/hold.png" lovec .
```

Add `EMILY_DENSITY=2` with `size=1920x1080` for full-resolution captures.

## The rooms

Carry and Weight (burden); Fog, Fog (Anchors) and Fog (Exit) (disorientation); Hold (intimacy); Lantern (absence); and Ledger (complicity).

## How it's built

- `src/core/` - the game controller, a scene manager that dissolves through the dark, the visual theme, ambient effects and the microgame base class
- `src/ui/` - the Pool menu, the scene that wraps each microgame with its title card, pause panel and ending, and settings
- `src/microgames/` - one directory per game, catalogued in `registry.lua`
- `designs/` - the Expressive Mechanics Library and a design document for each game
- Every frame draws into a 960x540 float canvas that `LoveLibs/graphics/postfx.lua` blooms, grades, vignettes and dithers. All music and sound is synthesized at runtime.
- `LoveLibs/` - [LoveLibs](https://github.com/chrischaps/LoveLibs), vendored as a subtree
