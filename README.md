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
| F5 | Save now |
| F9 (twice) | Erase your save and start over |

## Saving

The game saves automatically every 30 seconds and when you close the window,
and picks up where you left off next time. It remembers where you are, which
way you're looking, the time of day and which world you're in.

The save file is at `%APPDATA%\Godot\app_userdata\Nelbrenn\savegame.json`.

## Project layout

| File | What it does |
| --- | --- |
| `scenes/main.tscn` | The main scene the game starts in |
| `scripts/main.gd` | Sets up controls, sky, sun, world and player, and handles saving. Change `world_seed` for a new world (then press F9 twice in-game, since a save keeps its own world) |
| `scripts/world.gd` | Terrain generation, chunk streaming, trees, rocks and water |
| `scripts/player.gd` | Player movement, swimming and the third-person camera |
| `scripts/day_night.gd` | Sun movement and sky colours over the day |
| `scripts/save_game.gd` | Reading and writing the save file |
| `scripts/low_poly.gd` | Helpers for building flat-shaded low-poly meshes |
