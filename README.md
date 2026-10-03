# Nelbrenn

Tis nelbrenn — a low-poly open world made with [Godot 4.7](https://godotengine.org).

The world is generated from noise and streams in around you as you explore:
rolling grassland, forests, beaches, lakes and snowy mountains, with a full
day/night cycle.

## Playing

1. Open Godot, click **Import**, and pick this folder's `project.godot`.
2. Press **F5** (or the ▶ button) to play.

| Key | Action |
| --- | --- |
| W A S D / arrows | Move |
| Mouse | Look around |
| Shift | Sprint |
| Space | Jump / swim up |
| Esc | Free the mouse (click to capture it again) |

## Project layout

| File | What it does |
| --- | --- |
| `scenes/main.tscn` | The main scene the game starts in |
| `scripts/main.gd` | Sets up controls, sky, sun, world and player. Change `world_seed` for a new world |
| `scripts/world.gd` | Terrain generation, chunk streaming, trees, rocks and water |
| `scripts/player.gd` | Player movement, swimming and the third-person camera |
| `scripts/day_night.gd` | Sun movement and sky colours over the day |
| `scripts/low_poly.gd` | Helpers for building flat-shaded low-poly meshes |
