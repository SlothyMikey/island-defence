# Repository Guidelines

## Project Structure & Module Organization
`project.godot` defines this Godot 4.6 project and starts at `scenes/world.tscn`. Keep gameplay scenes under `scenes/`, grouped by feature: `character/`, `building/`, `enemies/`, and `other/`. Mirror that structure in `script/` so scene logic stays easy to find, for example `scenes/enemies/bomb_enemy.tscn` and `script/enemies/bomb_enemy.gd`. Store art, spritesheets, and import metadata in `assets/`. Treat `.godot/` as generated editor state; it is ignored and should not be committed.

## Build, Test, and Development Commands
Use the Godot executable installed on your machine; examples below assume it is available as `godot4`.

```powershell
godot4 --path .
godot4 --path . --editor
godot4 --headless --path . --quit
```

`godot4 --path .` runs the game from the repo root. `godot4 --path . --editor` opens the project in the editor. `godot4 --headless --path . --quit` is a fast parse/import check before pushing changes.

## Coding Style & Naming Conventions
Follow Godot GDScript conventions already used here: tabs for indentation, `snake_case` for variables and functions, and `lower_snake_case` file names such as `player.gd` and `damage_text.gd`. Keep one primary behavior per scene/script pair. Prefer `@export` and `@onready` for editor wiring instead of hard-coded node lookups outside the local scene tree.

## Testing Guidelines
There is no automated test suite or `tests/` directory yet. For now, do focused manual smoke tests in `scenes/world.tscn`: player movement with `WASD`, left-click attack chaining, right-click defend, enemy pathing to the base, castle health bar updates, and damage text spawning. If you add automated tests later, place them in a top-level `tests/` folder and document the runner in this file.

## Commit & Pull Request Guidelines
This checkout does not include Git history, so no repository-specific commit format can be inferred. Use short imperative subjects with a clear scope, for example `player: lock movement during defend` or `enemy: spawn damage text at marker`. PRs should describe the gameplay change, list manual verification steps, and include screenshots or short clips for scene, animation, or UI updates.

## Configuration Notes
Prefer editing `project.godot` and `.tscn` files through the Godot editor when possible to avoid noisy diffs. Keep line endings normalized to LF as defined in `.gitattributes`.
