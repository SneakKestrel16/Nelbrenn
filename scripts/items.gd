extends RefCounted
## Every item in the game. To add a new item, add an entry to ITEMS.
##
## "slot" is where the item can be worn:
##   armor:       head, chest, hands, legs, feet
##   accessories: neck, ring, charm
##   ""           only goes in the bag (materials, food...)
## Optional stats: "armor" (points), "speed" and "jump" (percent bonus).
## "max_stack" is how many fit in one bag slot (default 1).
## "icon" picks the drawn icon shape (defaults to the slot).
## Tools: "tool" is "axe" or "pickaxe", "power" is how much each hit does
## (your bare hands do 1). Food: "food" is how much hunger eating it fills.

const ITEMS := {
	# --- Tools ---
	"stone_axe": {
		"name": "Stone Axe", "slot": "", "icon": "axe", "color": Color(0.60, 0.60, 0.58),
		"tool": "axe", "power": 2, "description": "Chops trees twice as fast as your hands.",
	},
	"stone_pickaxe": {
		"name": "Stone Pickaxe", "slot": "", "icon": "pickaxe", "color": Color(0.60, 0.60, 0.58),
		"tool": "pickaxe", "power": 2, "description": "Mines rocks and ore. You need a pickaxe for ore.",
	},
	"iron_axe": {
		"name": "Iron Axe", "slot": "", "icon": "axe", "color": Color(0.78, 0.80, 0.84),
		"tool": "axe", "power": 3, "description": "A sharp iron blade. Trees don't stand a chance.",
	},
	"iron_pickaxe": {
		"name": "Iron Pickaxe", "slot": "", "icon": "pickaxe", "color": Color(0.78, 0.80, 0.84),
		"tool": "pickaxe", "power": 3, "description": "Bites through stone and ore.",
	},
	# --- Armor ---
	"leather_cap": {
		"name": "Leather Cap", "slot": "head", "color": Color(0.55, 0.36, 0.20),
		"armor": 1, "description": "A simple cap of stitched leather.",
	},
	"iron_helm": {
		"name": "Iron Helm", "slot": "head", "color": Color(0.62, 0.64, 0.68),
		"armor": 3, "description": "Heavy, but it keeps your head in one piece.",
	},
	"leather_tunic": {
		"name": "Leather Tunic", "slot": "chest", "color": Color(0.50, 0.33, 0.18),
		"armor": 2, "description": "Sturdy traveller's clothing.",
	},
	"chainmail": {
		"name": "Chainmail", "slot": "chest", "color": Color(0.58, 0.60, 0.64),
		"armor": 5, "speed": -5, "description": "Strong protection, a little heavy.",
	},
	"leather_gloves": {
		"name": "Leather Gloves", "slot": "hands", "color": Color(0.45, 0.30, 0.17),
		"armor": 1, "description": "Keeps the splinters out.",
	},
	"leather_trousers": {
		"name": "Leather Trousers", "slot": "legs", "color": Color(0.40, 0.27, 0.16),
		"armor": 2, "description": "Tough trousers for rough country.",
	},
	"leather_boots": {
		"name": "Leather Boots", "slot": "feet", "color": Color(0.35, 0.22, 0.12),
		"armor": 1, "description": "Well worn and comfortable.",
	},
	"swift_boots": {
		"name": "Boots of Swiftness", "slot": "feet", "color": Color(0.20, 0.55, 0.75),
		"armor": 1, "speed": 15, "description": "Light as air. You move faster.",
	},
	# --- Accessories ---
	"amber_amulet": {
		"name": "Amber Amulet", "slot": "neck", "color": Color(0.95, 0.65, 0.15),
		"armor": 1, "description": "Warm to the touch.",
	},
	"silver_ring": {
		"name": "Silver Ring", "slot": "ring", "color": Color(0.80, 0.82, 0.88),
		"armor": 1, "description": "A plain silver band.",
	},
	"ruby_ring": {
		"name": "Ruby Ring", "slot": "ring", "color": Color(0.85, 0.15, 0.20),
		"speed": 5, "description": "The stone glows faintly when you run.",
	},
	"feather_charm": {
		"name": "Feather Charm", "slot": "charm", "color": Color(0.90, 0.92, 0.95),
		"jump": 30, "description": "You feel lighter. You jump higher.",
	},
	# --- Bag-only items ---
	"apple": {
		"name": "Apple", "slot": "", "icon": "round", "color": Color(0.85, 0.20, 0.15),
		"max_stack": 20, "food": 20, "description": "Crunchy and sweet.",
	},
	"berries": {
		"name": "Berries", "slot": "", "icon": "berries", "color": Color(0.80, 0.12, 0.22),
		"max_stack": 30, "food": 8, "description": "Picked from a berry bush.",
	},
	# --- Materials (gathered in the world) ---
	"wood": {
		"name": "Wood", "slot": "", "icon": "log", "color": Color(0.58, 0.40, 0.22),
		"max_stack": 50, "description": "Chopped from trees.",
	},
	"stone": {
		"name": "Stone", "slot": "", "icon": "rock", "color": Color(0.55, 0.55, 0.55),
		"max_stack": 50, "description": "Mined from rocks. Could be useful for building one day.",
	},
	"coal": {
		"name": "Coal", "slot": "", "icon": "lump", "color": Color(0.16, 0.16, 0.18),
		"max_stack": 50, "description": "Burns hot. Found in dark-speckled boulders.",
	},
	"copper_ore": {
		"name": "Copper Ore", "slot": "", "icon": "ore", "color": Color(0.85, 0.50, 0.25),
		"max_stack": 50, "description": "Orange-flecked rock from the lowlands and hills.",
	},
	"iron_ore": {
		"name": "Iron Ore", "slot": "", "icon": "ore", "color": Color(0.78, 0.52, 0.42),
		"max_stack": 50, "description": "Rusty-looking rock, common in the hills.",
	},
	"gold_ore": {
		"name": "Gold Ore", "slot": "", "icon": "ore", "color": Color(1.0, 0.82, 0.25),
		"max_stack": 50, "description": "Glittering rock from high in the mountains.",
	},
	"crystal": {
		"name": "Crystal", "slot": "", "icon": "gem", "color": Color(0.55, 0.85, 0.95),
		"max_stack": 30, "description": "A clear crystal from the snowy peaks.",
	},
}


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func get_info(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func max_stack(id: String) -> int:
	return int(get_info(id).get("max_stack", 1))


## Text shown when hovering an item: name, stats and description.
static func describe(id: String) -> String:
	var info := get_info(id)
	if info.is_empty():
		return ""
	var lines: Array[String] = [info["name"]]
	if info.get("armor", 0) != 0:
		lines.append("Armor %+d" % info["armor"])
	if info.get("speed", 0) != 0:
		lines.append("Speed %+d%%" % info["speed"])
	if info.get("jump", 0) != 0:
		lines.append("Jump %+d%%" % info["jump"])
	if info.has("tool"):
		lines.append("%s power %d" % [String(info["tool"]).capitalize(), info.get("power", 1)])
	if info.get("food", 0) != 0:
		lines.append("Food +%d (hold it on the hotbar and right-click to eat)" % info["food"])
	if info.get("description", "") != "":
		lines.append(info["description"])
	return "\n".join(lines)
