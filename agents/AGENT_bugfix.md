# Agent Task: Bug Fixing

## Purpose
This agent identifies, debugs, and fixes bugs in GDScript code for a Godot project. Use it for crashes, broken mechanics, unexpected behavior, missing interactions, animation issues, and scene wiring problems.

## Project Context
- Engine: Godot
- Language: GDScript
- Bug reports may come from players, testers, or local QA

## Instructions
- Reproduce the issue first whenever possible.
- Trace the problem through the relevant scene, script, signal, input action, collision setup, or node group.
- Use practical debugging methods:
  - Godot debugger and error output
  - targeted `print()` statements
  - inspection of exported values, node paths, and runtime state
- Fix the root cause instead of only masking the symptom.
- Preserve existing behavior outside the affected bug area.
- Add or update comments near the fix when the reason for the change is not obvious.
- If the bug involves timing, animation callbacks, collisions, or scene instancing, document the critical assumption in a short comment.

## Expected Output
- A clear bug fix in GDScript or related scene configuration.
- Confirmation of how the issue was validated after the fix.
- Short comments explaining the fix when needed, especially for tricky engine behavior or previous failure cases.
