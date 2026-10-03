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
| 1–8 / mouse wheel | Pick a hotbar slot (the item goes in your hand) |
| E / left click (hold) | Chop, mine or pick what's in front of you |
| F / right click | Eat the food in your hand, or build the bench in your hand |
| E / left click (at a bench) | Open the crafting menu |
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
- **Hotbar:** 8 slots, also shown along the bottom of the screen. Press
  1–8 or scroll the mouse wheel to pick one; that item is held in your hand.
  Right-click an item in the bag to put it on the hotbar (or back).

## Tools, food and hunger

A new world starts with a **stone axe**, a **stone pickaxe**, some apples and
a **crafting bench** on the hotbar (older worlds get anything they're missing
from that list added once).

- **Axes** chop trees faster, **pickaxes** break rocks faster. You get the
  same amount of loot, just in fewer swings. Iron tools (crafted) are even faster.
- **Ore deposits and crystals need a pickaxe** in your hand. Trees, rocks
  and bushes can also be gathered with bare hands, just slowly.
- **Hunger** (the orange bar) slowly runs down, twice as fast while
  sprinting. Hold food on the hotbar and press **F** or right-click to eat
  (apple +20, berries +8).
- **Health** (the red bar) comes back on its own while you're at least half
  full. If hunger runs out, health drains, and at zero you faint and wake up
  at the world's starting point. You keep all your items.

Worn items show on your character and add up to your stats. Speed and jump
bonuses already work. Armor is counted, but there's nothing to fight yet. A new
world starts with a starter kit. To add your own items, edit `scripts/items.gd`.

## Gathering resources

Walk up to a tree, rock, ore deposit or berry bush and hold **E** (or the left
mouse button). A label shows what you're aiming at and how close it is to
breaking. Every hit gives you something, with a bonus when it breaks.
Bottom right lists what you picked up.

| Find it | What it looks like | You get |
| --- | --- | --- |
| Oak / pine trees | Everywhere on dry land | Wood (oaks sometimes drop apples) |
| Rocks | Grey boulders | Stone |
| Coal | Boulder with black lumps, anywhere | Coal, stone |
| Copper | Orange lumps, lowlands and hills | Copper ore, stone |
| Iron | Rusty lumps, more common on hills | Iron ore, stone |
| Gold | Yellow lumps, high in the mountains only | Gold ore, stone |
| Crystals | Pale blue spikes near the snowy peaks | Crystal |
| Berry bushes | Small bushes with red berries, near forests | Berries |

Ore deposits come in clusters, and there are more the higher you climb.
Harvested things grow back after 5–50 minutes (even while the game is
closed). To change what drops, how many hits things take or how fast they
regrow, edit `scripts/harvestables.gd`.

## Crafting

**By hand:** the inventory screen (I / Tab) has a small **Crafting** list
for the basics: a Crafting Bench, Stone Axe, Stone Pickaxe and Fruit Salad.
Each shows what it needs (green when you have it) and a **Craft** button.

**At a crafting bench:** everything else (iron tools, smelting, armor and
accessories) needs a **crafting bench**. Put the bench on your hotbar,
pick it, and right-click (or press F) to build it in front of you. Walk up to
it and press **E** or click to open the crafting menu: pick a recipe on the
left, see what it needs and what you have, and press **Craft**. **Pick Up
Bench** puts it back in your bag so you can build it somewhere else. A bench
can make more benches.

| Group | Recipes |
| --- | --- |
| Building | Crafting Bench (8 wood, 4 stone) |
| Tools | Stone Axe / Pickaxe (3 wood, 3 stone), Iron Axe / Pickaxe (2 wood, 3 iron bars) |
| Smelting | Copper, Iron and Gold Bars (2 ore + 1 coal each) |
| Armor & accessories | Copper Helm, Iron Helm, Chainmail, Gold Ring, Crystal Charm |
| Food | Fruit Salad (2 apples, 4 berries; very filling) |

Benches you build are saved with the world. To add or change recipes, edit
`scripts/recipes.gd` (give a recipe `"hand": true` to make it craftable from
the inventory too).

## Saving

Every world has its own save. The game saves automatically every 30 seconds,
when you quit through the pause menu, and when you close the window. It
remembers where you are, which way you're looking, the time of day, your
inventory and hotbar, your health and hunger, and what you've harvested that
hasn't grown back yet.

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
| `scripts/world.gd` | Terrain shape and colours, chunk streaming, trees, rocks, ores, bushes, water and built benches |
| `scripts/harvestables.gd` | What every tree, rock and ore drops, how many hits it takes, regrow times |
| `scripts/gathering.gd` | Chopping and mining: aiming, tools, the on-screen prompt, pickups and sounds |
| `scripts/hud.gd` | Hotbar and health / food bars on screen; picking slots, eating and building |
| `scripts/recipes.gd` | Every crafting recipe |
| `scripts/crafting_ui.gd` | The crafting bench menu |
| `scripts/vitals.gd` | Health and hunger, eating, and fainting |
| `scripts/player.gd` | Player movement, swimming and the third-person camera |
| `scripts/day_night.gd` | Sun movement and sky colours over the day |
| `scripts/ambience.gd` | Wind sound, made in code, louder up high |
| `scripts/items.gd` | The list of every item and its stats |
| `scripts/inventory.gd` | Inventory and hotbar slots, equipping, stacking and stats |
| `scripts/inventory_ui.gd` | The inventory screen |
| `scripts/inventory_slot.gd` | One slot in the inventory screen: icons and drag-and-drop |
| `scripts/save_game.gd` | Reading, writing, listing and deleting world saves |
| `export_presets.cfg` | Export settings for the browser and Windows builds |
| `.github/workflows/publish.yml` | Builds and publishes the game on every push |
| `scripts/low_poly.gd` | Helpers for building flat-shaded low-poly meshes |
