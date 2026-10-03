extends RefCounted
## Everything you can craft. To add a recipe, add an entry: "id" is the item
## made (from items.gd), "count" how many (default 1), "needs" the items used
## up, and "group" the heading it's listed under.
##
## Every recipe can be made at a crafting bench. Ones with "hand": true can
## also be made anywhere from the inventory screen (I / Tab), so you can
## always get started.

const Items := preload("res://scripts/items.gd")

const RECIPES := [
	{"id": "crafting_bench", "group": "Building", "hand": true, "needs": {"wood": 8, "stone": 4}},

	{"id": "stone_axe", "group": "Tools", "hand": true, "needs": {"wood": 3, "stone": 3}},
	{"id": "stone_pickaxe", "group": "Tools", "hand": true, "needs": {"wood": 3, "stone": 3}},
	{"id": "iron_axe", "group": "Tools", "needs": {"wood": 2, "iron_bar": 3}},
	{"id": "iron_pickaxe", "group": "Tools", "needs": {"wood": 2, "iron_bar": 3}},

	{"id": "copper_bar", "group": "Smelting", "needs": {"copper_ore": 2, "coal": 1}},
	{"id": "iron_bar", "group": "Smelting", "needs": {"iron_ore": 2, "coal": 1}},
	{"id": "gold_bar", "group": "Smelting", "needs": {"gold_ore": 2, "coal": 1}},

	{"id": "copper_helm", "group": "Armor & accessories", "needs": {"copper_bar": 4}},
	{"id": "iron_helm", "group": "Armor & accessories", "needs": {"iron_bar": 5}},
	{"id": "chainmail", "group": "Armor & accessories", "needs": {"iron_bar": 8}},
	{"id": "gold_ring", "group": "Armor & accessories", "needs": {"gold_bar": 2}},
	{"id": "crystal_charm", "group": "Armor & accessories", "needs": {"crystal": 3, "gold_bar": 1}},

	{"id": "fruit_salad", "group": "Food", "hand": true, "needs": {"apple": 2, "berries": 4}},
]


## The recipes you can make from the inventory screen, without a bench.
static func hand_recipes() -> Array:
	return RECIPES.filter(func(r): return r.get("hand", false))


static func can_craft(recipe: Dictionary, inventory) -> bool:
	for id in recipe["needs"]:
		if inventory.count_of(id) < recipe["needs"][id]:
			return false
	return true


## Uses up the ingredients and adds the result. Returns "" if it worked, or
## the reason it didn't (nothing is used up then).
static func craft(recipe: Dictionary, inventory) -> String:
	if not can_craft(recipe, inventory):
		return "You don't have everything for that."
	var before: Dictionary = inventory.get_save_data()
	for id in recipe["needs"]:
		inventory.remove_item(id, recipe["needs"][id])
	if inventory.add_item(recipe["id"], recipe.get("count", 1)) > 0:
		inventory.apply_save_data(before)  # Undo: there was no room for it.
		return "No room in your bag for that."
	return ""


## "3 Wood, 3 Stone"
static func needs_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	for id in recipe["needs"]:
		parts.append("%d %s" % [recipe["needs"][id], Items.get_info(id)["name"]])
	return ", ".join(parts)
