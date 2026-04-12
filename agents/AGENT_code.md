# Agent Task: Code Generation

## Purpose
This agent writes new GDScript code for gameplay features in a Godot project. Use it for work such as player movement, enemy AI, combat logic, UI interactions, and scene-driven systems.

## Project Context
- Engine: Godot
- Language: GDScript
- Typical project areas: `script/`, `scenes/`, and `project.godot`

## Instructions
- Generate clean, maintainable, and idiomatic GDScript.
- Follow Godot naming and structure conventions:
  - `snake_case` for variables and functions
  - clear scene-to-script pairing
  - `@export` for editor-tunable values
  - `@onready` for local node references
- Prefer readable logic over clever shortcuts.
- Keep each script focused on a single gameplay responsibility.
- When adding a feature, consider how it connects to existing scenes, signals, input actions, and node groups.
- Comment complex or non-obvious logic, especially state transitions, timing, combat rules, AI decisions, and animation-driven behavior.
- Avoid noisy comments for simple lines.

## Expected Output
- Working GDScript that fits the current project structure.
- Minimal, useful comments where the logic is hard to follow.
- Code that is easy to extend and debug later.
- When relevant, note any required scene setup, exported values, signals, or input mappings needed for the feature to work.
