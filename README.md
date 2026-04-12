# Island Defence

Island Defence is a Godot 4.6 top-down combat prototype built around a single playable scene. The main scene is `scenes/world.tscn`, which instances the player, the castle base, and a bomb enemy.

## Requirements

- Godot 4.6 or newer
- A local Godot executable available as `godot4`, or another executable name you substitute in the commands below

## Run

From the repository root:

```powershell
godot4 --path .
```

To open the project in the editor:

```powershell
godot4 --path . --editor
```

To run a fast headless parse/import check:

```powershell
godot4 --headless --path . --quit
```

## Controls

- `WASD`: move the player
- Left click: attack
- Right click: defend

## Gameplay Loop

- The player moves around the map as a `CharacterBody2D` and uses `script/character/player.gd`.
- Left click triggers `attack_1`; pressing attack again during the first swing queues `attack_2`.
- Right click holds the defend state, which locks movement while the defend animation is active.
- `scenes/enemies/bomb_enemy.tscn` spawns an enemy that seeks the node in the `base` group.
- `scenes/building/castle.tscn` provides the base health bar, and `script/buildings/castle.gd` exposes the health and bar-color update logic used when the base takes damage.
- `scenes/other/damage_text.tscn` shows floating damage numbers, driven by `script/other/damage_text.gd`.

## Project Structure

- `scenes/world.tscn`: main scene and gameplay setup
- `scenes/character/`: player scene
- `scenes/building/`: castle/base scene
- `scenes/enemies/`: enemy scene(s)
- `scenes/other/`: shared utility scenes such as damage text
- `script/character/`: player logic
- `script/buildings/`: base logic
- `script/enemies/`: enemy logic
- `script/other/`: utility logic
- `assets/`: imported sprites and tiles from the Tiny Swords packs

## Notes

- The project currently has no automated test suite.
- For manual smoke testing, use `scenes/world.tscn` and verify movement, attack chaining, defend locking, enemy pathing, and damage text spawning. If you wire enemy-to-base damage in your local branch, also verify the castle health bar updates correctly.
