extends RefCounted
## Everything in the world you can chop, mine or pick. To add a new kind,
## add an entry here, give it a mesh in world.gd (_build_prop_meshes) and
## decide where it grows (_build_props / _add_ores_and_bushes).
##
## "tool":       "axe" or "pickaxe": holding one makes it go faster (each hit
##               does the tool's power instead of 1).
## "needs_tool": true if you can't gather it at all without that tool.
## "hits":       how much damage it takes to break.
## "per_hit":    items you get for every 1 damage you do.
## "on_break":   extra items when it breaks.
##               An amount is a number, or [min, max] for a random amount.
## "regrow":     seconds until it grows back after breaking.
## "sound":      "chop", "mine" or "pick".
## "chips":      colour of the bits that fly off when hit.

const KINDS := {
	"oak": {
		"name": "Oak Tree", "action": "Chop", "tool": "axe", "hits": 6, "sound": "chop",
		"per_hit": {"wood": 1}, "on_break": {"wood": [1, 2], "apple": [0, 2]},
		"regrow": 600, "chips": Color(0.62, 0.45, 0.27),
	},
	"pine": {
		"name": "Pine Tree", "action": "Chop", "tool": "axe", "hits": 5, "sound": "chop",
		"per_hit": {"wood": 1}, "on_break": {"wood": [1, 2]},
		"regrow": 600, "chips": Color(0.62, 0.45, 0.27),
	},
	"rock": {
		"name": "Rock", "action": "Mine", "tool": "pickaxe", "hits": 4, "sound": "mine",
		"per_hit": {"stone": 1}, "on_break": {"stone": [0, 1]},
		"regrow": 900, "chips": Color(0.55, 0.53, 0.50),
	},
	"coal": {
		"name": "Coal Deposit", "action": "Mine", "tool": "pickaxe", "needs_tool": true, "hits": 6, "sound": "mine",
		"per_hit": {"coal": 1}, "on_break": {"stone": [1, 2]},
		"regrow": 1200, "chips": Color(0.15, 0.15, 0.16),
	},
	"copper": {
		"name": "Copper Deposit", "action": "Mine", "tool": "pickaxe", "needs_tool": true, "hits": 6, "sound": "mine",
		"per_hit": {"copper_ore": 1}, "on_break": {"stone": [1, 2]},
		"regrow": 1200, "chips": Color(0.80, 0.48, 0.25),
	},
	"iron": {
		"name": "Iron Deposit", "action": "Mine", "tool": "pickaxe", "needs_tool": true, "hits": 8, "sound": "mine",
		"per_hit": {"iron_ore": 1}, "on_break": {"stone": [1, 2]},
		"regrow": 1500, "chips": Color(0.72, 0.52, 0.42),
	},
	"gold": {
		"name": "Gold Deposit", "action": "Mine", "tool": "pickaxe", "needs_tool": true, "hits": 8, "sound": "mine",
		"per_hit": {"gold_ore": [0, 1]}, "on_break": {"gold_ore": 1, "stone": [1, 2]},
		"regrow": 2400, "chips": Color(0.95, 0.78, 0.25),
	},
	"crystal": {
		"name": "Crystal Cluster", "action": "Mine", "tool": "pickaxe", "needs_tool": true, "hits": 8, "sound": "mine",
		"per_hit": {}, "on_break": {"crystal": [1, 3]},
		"regrow": 3000, "chips": Color(0.55, 0.85, 0.95),
	},
	"berry_bush": {
		"name": "Berry Bush", "action": "Pick", "tool": "", "hits": 1, "sound": "pick",
		"per_hit": {"berries": [2, 4]}, "on_break": {},
		"regrow": 300, "chips": Color(0.30, 0.55, 0.25),
	},
}


static func get_info(kind: String) -> Dictionary:
	return KINDS.get(kind, {})


## The item a kind is mostly gathered for (used to check there's room in the bag).
static func main_item(kind: String) -> String:
	var info := get_info(kind)
	for table in [info.get("per_hit", {}), info.get("on_break", {})]:
		if not table.is_empty():
			return table.keys()[0]
	return ""


## Rolls the random amounts in a drop table `times` times:
## {"wood": [2, 3]} -> {"wood": 2}. Amounts that come out 0 are left out.
static func roll(table: Dictionary, rng: RandomNumberGenerator, times := 1) -> Dictionary:
	var result := {}
	for id in table:
		var amount = table[id]
		var n := 0
		for i in times:
			n += rng.randi_range(amount[0], amount[1]) if amount is Array else int(amount)
		if n > 0:
			result[id] = n
	return result
