# Nelbrenn

Tis nelbrenn — a low-poly open world made with [Godot 4.7](https://godotengine.org).

The world is generated from noise and streams in around you as you explore:
rolling grassland, forests, beaches, lakes and snowy mountains, with a full
day/night cycle. The ground is smooth-shaded with soft blends between sand,
grass, forest floor, rock and snow; trees and rocks keep the low-poly style.

## Play it

- **In your browser:** https://sneakkestrel16.github.io/Nelbrenn/
  (always the newest version, nothing to install; saves stay in that browser)
- **Windows download:** https://github.com/SneakKestrel16/Nelbrenn/releases/latest/download/Nelbrenn-windows.zip
  (unzip and run `Nelbrenn.exe`; the main menu shows an "Update available"
  button when a newer version is out. Windows may warn about an unknown
  publisher: click **More info → Run anyway**.)

Every push to `main` builds and publishes both automatically
(`.github/workflows/publish.yml`). The build number is shown in the bottom
right of the main menu.

## Playing from the source

1. Open Godot, click **Import**, and pick this folder's `project.godot`.
2. Press **F5** (or the ▶ button) to play.

The game opens on the **main menu**:

- **Continue** jumps back into the world you played last.
- **Worlds** lists your saved worlds. Play or delete them, or **Create New
  World**. Give it a name and, if you like, a seed. Leave the seed empty for
  a random world. The same seed always makes the same world, and words work
  as seeds too.
- **Settings** and **Quit**.

| Key (default) | Action |
| --- | --- |
| W A S D / arrows | Move |
| Mouse | Look around |
| Shift | Sprint |
| Space | Jump / swim up |
| I / Tab | Open or close the inventory |
| F5 | Quick save |
| Esc | Pause menu (resume, settings, save, quit) |

All keys except Esc can be changed in **Settings → Controls**.

## Settings

Open them from the main menu or the pause menu. Changes apply straight away
and are remembered.

- **Graphics:** fullscreen, VSync, frame rate limit, render scale,
  anti-aliasing, shadows, view distance, field of view
- **Audio:** master, music, effects and ambience volume (the wind you hear
  outdoors is ambience; there's no music yet)
- **Controls:** mouse sensitivity, invert mouse Y, and key bindings (two keys
  per action; click a box and press a key, right-click to clear)

## Inventory

Press **I** or **Tab** to open your inventory. Drag items between slots, or
right-click an item to equip or unequip it.

- **Armor slots:** Head, Chest, Hands, Legs, Feet
- **Accessory slots:** Amulet, two Rings, Charm
- **Bag:** 24 slots; things like apples and stones stack

Worn items show on your character and add up to your stats. Speed and jump
bonuses already work. Armor is counted, but there's nothing to fight yet. A new
world starts with a starter kit. To add your own items, edit `scripts/items.gd`.

## Saving

Every world has its own save. The game saves automatically every 30 seconds,
when you quit through the pause menu, and when you close the window. It
remembers where you are, which way you're looking, the time of day and your
inventory.

Saves live in `%APPDATA%\Godot\app_userdata\Nelbrenn\worlds\` (one `.json`
file per world) and settings in `settings.cfg` next to that folder. A save
from before multiple worlds existed is moved in automatically as
"My First World".

## Project layout

| File | What it does |
| --- | --- |
| `scenes/main_menu.tscn` | The scene the game starts in |
| `scenes/game.tscn` | The game itself, loaded when you pick a world |
| `scripts/main_menu.gd` | Main menu: world list, creating worlds, the spinning background world |
| `scripts/game.gd` | Sets up sky, sun, world, player, inventory and menus for a world, and saves it |
| `scripts/pause_menu.gd` | The pause menu |
| `scripts/settings.gd` | All settings and key bindings (an autoload, so every script can use `Settings`) |
| `scripts/settings_menu.gd` | The settings screen, shared by the main and pause menus |
| `scripts/ui.gd` | Shared menu look (colours, buttons, panels) |
| `scripts/world.gd` | Terrain shape and colours, chunk streaming, trees, rocks and water |
| `scripts/player.gd` | Player movement, swimming and the third-person camera |
| `scripts/day_night.gd` | Sun movement and sky colours over the day |
| `scripts/ambience.gd` | Wind sound, made in code, louder up high |
| `scripts/items.gd` | The list of every item and its stats |
| `scripts/inventory.gd` | Inventory slots, equipping, stacking and stats |
| `scripts/inventory_ui.gd` | The inventory screen |
| `scripts/inventory_slot.gd` | One slot in the inventory screen: icons and drag-and-drop |
| `scripts/save_game.gd` | Reading, writing, listing and deleting world saves |
| `export_presets.cfg` | Export settings for the browser and Windows builds |
| `.github/workflows/publish.yml` | Builds and publishes the game on every push |
| `scripts/low_poly.gd` | Helpers for building flat-shaded low-poly meshes |
