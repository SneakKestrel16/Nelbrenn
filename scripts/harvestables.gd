extends RefCounted
## Everything in the world you can chop, mine or pick. To add a new kind,
## add an entry here, give it a mesh in world.gd (_build_prop_meshes) and
## decide where it grows (_build_props / _build_ores).
##
## "hits":     how many hits it takes to break.
## "per_hit":  items you get from every hit.
## "on_break": extra items when it breaks.
##             An amount is a number, or [min, max] for a random amount.
## "regrow":   seconds until it grows back after breaking.
## "sound":    "chop", "mine" or "pick".
## "chips":    colour of the bits that fly off when hit.

const KINDS := {
	"oak": {
		"name": "Oak Tree", "action": "Chop", "hits": 5, "sound": "chop",
		"per_hit": {"wood": 1}, "on_break": {"wood": [2, 3], "apple": [0, 2]},
		"regrow": 600, "chips": Color(0.62, 0.45, 0.27),
	},
	"pine": {
		"name": "Pine Tree", "action": "Chop", "hits": 4, "sound": "chop",
		"per_hit": {"wood": 1}, "on_break": {"wood": [2, 3]},
		"regrow": 600, "chips": Color(0.62, 0.45, 0.27),
	},
	"rock": {
		"name": "Rock", "action": "Mine", "hits": 3, "sound": "mine",
		"per_hit": {"stone": 1}, "on_break": {"stone": [1, 2]},
		"regrow": 900, "chips": Color(0.55, 0.53, 0.50),
	},
	"coal": {
		"name": "Coal Deposit", "action": "Mine", "hits": 4, "sound": "mine",
		"per_hit": {"coal": 1}, "on_break": {"coal": [1, 2], "stone": [1, 2]},
		"regrow": 1200, "chips": Color(0.15, 0.15, 0.16),
	},
	"copper": {
		"name": "Copper Deposit", "action": "Mine", "hits": 5, "sound": "mine",
		"per_hit": {"copper_ore": 1}, "on_break": {"copper_ore": [1, 2], "stone": [1, 2]},
		"regrow": 1200, "chips": Color(0.80, 0.48, 0.25),
	},
	"iron": {
		"name": "Iron Deposit", "action": "Mine", "hits": 6, "sound": "mine",
		"per_hit": {"iron_ore": 1}, "on_break": {"iron_ore": [1, 2], "stone": [1, 2]},
		"regrow": 1500, "chips": Color(0.72, 0.52, 0.42),
	},
	"gold": {
		"name": "Gold Deposit", "action": "Mine", "hits": 7, "sound": "mine",
		"per_hit": {"gold_ore": 1}, "on_break": {"gold_ore": [0, 1], "stone": [1, 2]},
		"regrow": 2400, "chips": Color(0.95, 0.78, 0.25),
	},
	"crystal": {
		"name": "Crystal Cluster", "action": "Mine", "hits": 5, "sound": "mine",
		"per_hit": {}, "on_break": {"crystal": [1, 3]},
		"regrow": 3000, "chips": Color(0.55, 0.85, 0.95),
	},
	"berry_bush": {
		"name": "Berry Bush", "action": "Pick", "hits": 1, "sound": "pick",
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


## Rolls the random amounts in a drop table: {"wood": [2, 3]} -> {"wood": 2}.
static func roll(table: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result := {}
	for id in table:
		var amount = table[id]
		var n: int = rng.randi_range(amount[0], amount[1]) if amount is Array else int(amount)
		if n > 0:
			result[id] = n
	return result
