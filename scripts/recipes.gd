extends RefCounted
## Everything you can make at a crafting bench. To add a recipe, add an
## entry: "id" is the item made (from items.gd), "count" how many (default 1),
## "needs" the items used up, and "group" the heading it's listed under.

const RECIPES := [
	{"id": "crafting_bench", "group": "Building", "needs": {"wood": 8, "stone": 4}},

	{"id": "stone_axe", "group": "Tools", "needs": {"wood": 3, "stone": 3}},
	{"id": "stone_pickaxe", "group": "Tools", "needs": {"wood": 3, "stone": 3}},
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

	{"id": "fruit_salad", "group": "Food", "needs": {"apple": 2, "berries": 4}},
]
