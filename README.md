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
| I / Tab | Open or close the inventory |
| F5 | Save now |
| F9 (twice) | Erase your save and start over |

## Inventory

Press **I** or **Tab** to open your inventory. Drag items between slots, or
right-click an item to equip or unequip it.

- **Armor slots:** Head, Chest, Hands, Legs, Feet
- **Accessory slots:** Amulet, two Rings, Charm
- **Bag:** 24 slots; things like apples and stones stack

Worn items show on your character and add up to your stats. Speed and jump
bonuses already work. Armor is counted, but there's nothing to fight yet. A new
game starts with a starter kit. To add your own items, edit `scripts/items.gd`.

## Saving

The game saves automatically every 30 seconds and when you close the window,
and picks up where you left off next time. It remembers where you are, which
way you're looking, the time of day, which world you're in and your inventory.

The save file is at `%APPDATA%\Godot\app_userdata\Nelbrenn\savegame.json`.

## Project layout

| File | What it does |
| --- | --- |
| `scenes/main.tscn` | The main scene the game starts in |
| `scripts/main.gd` | Sets up controls, sky, sun, world and player, and handles saving. Change `world_seed` for a new world (then press F9 twice in-game, since a save keeps its own world) |
| `scripts/world.gd` | Terrain generation, chunk streaming, trees, rocks and water |
| `scripts/player.gd` | Player movement, swimming and the third-person camera |
| `scripts/day_night.gd` | Sun movement and sky colours over the day |
| `scripts/items.gd` | The list of every item and its stats |
| `scripts/inventory.gd` | Inventory slots, equipping, stacking and stats |
| `scripts/inventory_ui.gd` | The inventory screen |
| `scripts/inventory_slot.gd` | One slot in the inventory screen: icons and drag-and-drop |
| `scripts/save_game.gd` | Reading and writing the save file |
| `scripts/low_poly.gd` | Helpers for building flat-shaded low-poly meshes |
