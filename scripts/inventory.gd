extends Node
## The player's items: a bag of BAG_SIZE slots plus equipment slots for
## armor and accessories.
##
## A slot is referred to by a "ref": an int for a bag slot (0 to BAG_SIZE - 1)
## or a String for an equipment slot ("head", "ring_1", ...).
## Each filled slot holds {"id": item id, "count": how many}; empty slots hold null.

signal changed

const Items := preload("res://scripts/items.gd")

const BAG_SIZE := 24
const ARMOR_SLOTS: Array[String] = ["head", "chest", "hands", "legs", "feet"]
const ACCESSORY_SLOTS: Array[String] = ["neck", "ring_1", "ring_2", "charm"]
const SLOT_LABELS := {
	"head": "Head", "chest": "Chest", "hands": "Hands", "legs": "Legs", "feet": "Feet",
	"neck": "Amulet", "ring_1": "Ring", "ring_2": "Ring", "charm": "Charm",
}

var bag: Array = []
var equipment := {}


func _init() -> void:
	clear()


func clear() -> void:
	bag.clear()
	bag.resize(BAG_SIZE)
	equipment.clear()
	for slot in ARMOR_SLOTS + ACCESSORY_SLOTS:
		equipment[slot] = null


func get_slot(ref) -> Variant:
	return bag[ref] if ref is int else equipment.get(ref)


## Which kind of item an equipment slot takes ("ring_1" and "ring_2" both take "ring").
static func slot_type(ref) -> String:
	return "" if ref is int else String(ref).trim_suffix("_1").trim_suffix("_2")


## Whether `entry` is allowed to sit in slot `ref`.
func can_hold(ref, entry) -> bool:
	if entry == null or ref is int:
		return true
	return Items.get_info(entry["id"]).get("slot", "") == slot_type(ref) and entry["count"] == 1


func can_move(from, to) -> bool:
	if _same_ref(from, to) or get_slot(from) == null:
		return false
	return _can_stack(from, to) or (can_hold(to, get_slot(from)) and can_hold(from, get_slot(to)))


## Moves the item at `from` to `to`, stacking or swapping with what's there.
func move(from, to) -> bool:
	if not can_move(from, to):
		return false
	var a: Dictionary = get_slot(from)
	var b = get_slot(to)
	if _can_stack(from, to):
		var moved := mini(a["count"], Items.max_stack(a["id"]) - b["count"])
		b["count"] += moved
		a["count"] -= moved
		_set_slot(from, a if a["count"] > 0 else null)
	else:
		_set_slot(to, a)
		_set_slot(from, b)
	changed.emit()
	return true


## Right-click: equip an item from the bag, or put an equipped item back in the bag.
func quick_move(ref) -> bool:
	var entry = get_slot(ref)
	if entry == null:
		return false
	if not ref is int:
		var free := bag.find(null)
		return free != -1 and move(ref, free)
	var wanted: String = Items.get_info(entry["id"]).get("slot", "")
	if wanted == "":
		return false
	var targets: Array = [wanted] if equipment.has(wanted) else [wanted + "_1", wanted + "_2"]
	for target in targets:  # Prefer an empty slot, otherwise swap with the first.
		if equipment[target] == null:
			return move(ref, target)
	return move(ref, targets[0])


## Puts items in the bag, filling existing stacks first. Returns how many didn't fit.
func add_item(id: String, count := 1) -> int:
	if not Items.exists(id):
		push_warning("Unknown item: %s" % id)
		return count
	var limit := Items.max_stack(id)
	for i in BAG_SIZE:
		if count > 0 and bag[i] != null and bag[i]["id"] == id and bag[i]["count"] < limit:
			var added := mini(count, limit - bag[i]["count"])
			bag[i]["count"] += added
			count -= added
	for i in BAG_SIZE:
		if count > 0 and bag[i] == null:
			var added := mini(count, limit)
			bag[i] = {"id": id, "count": added}
			count -= added
	changed.emit()
	return count


## How many more of `id` fit in the bag.
func room_for(id: String) -> int:
	var limit := Items.max_stack(id)
	var room := 0
	for entry in bag:
		if entry == null:
			room += limit
		elif entry["id"] == id:
			room += limit - entry["count"]
	return room


func equip_new(id: String) -> void:
	var slot: String = Items.get_info(id).get("slot", "")
	var target := slot if equipment.has(slot) else slot + "_1"
	if equipment.has(target) and equipment[target] == null:
		equipment[target] = {"id": id, "count": 1}
		changed.emit()
	else:
		add_item(id)


## Totals of all worn items: armor points, speed and jump bonus in percent.
func get_stats() -> Dictionary:
	var stats := {"armor": 0, "speed": 0, "jump": 0}
	for entry in equipment.values():
		if entry != null:
			var info := Items.get_info(entry["id"])
			for stat in stats:
				stats[stat] += int(info.get(stat, 0))
	return stats


## The colour of the item worn in `slot`, or null if nothing is worn there.
func worn_color(slot: String) -> Variant:
	var entry = equipment.get(slot)
	return null if entry == null else Items.get_info(entry["id"]).get("color")


func give_starter_items() -> void:
	clear()
	equip_new("leather_tunic")
	equip_new("leather_boots")
	for id in ["leather_cap", "iron_helm", "chainmail", "leather_gloves", "leather_trousers",
			"swift_boots", "amber_amulet", "silver_ring", "ruby_ring", "feather_charm"]:
		add_item(id)
	add_item("apple", 5)
	add_item("stone", 12)


func get_save_data() -> Dictionary:
	return {"bag": bag.duplicate(true), "equipment": equipment.duplicate(true)}


func apply_save_data(data: Dictionary) -> void:
	clear()
	var saved_bag: Array = data.get("bag", [])
	for i in mini(saved_bag.size(), BAG_SIZE):
		bag[i] = _load_entry(saved_bag[i])
	var saved_equipment: Dictionary = data.get("equipment", {})
	for slot in equipment:
		var entry = _load_entry(saved_equipment.get(slot))
		equipment[slot] = entry if can_hold(slot, entry) else null
		if entry != null and equipment[slot] == null:
			add_item(entry["id"], entry["count"])
	changed.emit()


## Turns a saved slot back into an entry, skipping items that no longer exist.
func _load_entry(saved) -> Variant:
	if not saved is Dictionary or not Items.exists(String(saved.get("id", ""))):
		return null
	return {"id": String(saved["id"]), "count": maxi(1, int(saved.get("count", 1)))}


func _set_slot(ref, entry) -> void:
	if ref is int:
		bag[ref] = entry
	else:
		equipment[ref] = entry


func _can_stack(from, to) -> bool:
	var a = get_slot(from)
	var b = get_slot(to)
	return (to is int and a != null and b != null and a["id"] == b["id"]
			and b["count"] < Items.max_stack(b["id"]))


static func _same_ref(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b
