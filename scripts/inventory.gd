extends Node
## The player's items: a bag of BAG_SIZE slots, a hotbar of HOTBAR_SIZE slots
## (the item picked there is the one in your hand), plus equipment slots for
## armor and accessories.
##
## A slot is referred to by a "ref": an int for a bag slot (0 to BAG_SIZE - 1),
## "hotbar_0" to "hotbar_7" for the hotbar, or the name of an equipment slot
## ("head", "ring_1", ...).
## Each filled slot holds {"id": item id, "count": how many}; empty slots hold null.

signal changed

const Items := preload("res://scripts/items.gd")

const BAG_SIZE := 24
const HOTBAR_SIZE := 8
const ARMOR_SLOTS: Array[String] = ["head", "chest", "hands", "legs", "feet"]
const ACCESSORY_SLOTS: Array[String] = ["neck", "ring_1", "ring_2", "charm"]
const SLOT_LABELS := {
	"head": "Head", "chest": "Chest", "hands": "Hands", "legs": "Legs", "feet": "Feet",
	"neck": "Amulet", "ring_1": "Ring", "ring_2": "Ring", "charm": "Charm",
}
## Put on the hotbar of every new world. Older worlds get any they never
## received when they're loaded (that's what `received` remembers).
const STARTER_GIFTS: Array[String] = ["stone_axe", "stone_pickaxe", "crafting_bench"]

var bag: Array = []
var hotbar: Array = []
var equipment := {}
var received: Array = []
## The hotbar slot in your hand (0 to HOTBAR_SIZE - 1).
var selected := 0


func _init() -> void:
	clear()


func clear() -> void:
	bag.clear()
	bag.resize(BAG_SIZE)
	hotbar.clear()
	hotbar.resize(HOTBAR_SIZE)
	selected = 0
	received.clear()
	equipment.clear()
	for slot in ARMOR_SLOTS + ACCESSORY_SLOTS:
		equipment[slot] = null


static func hotbar_ref(index: int) -> String:
	return "hotbar_%d" % index


static func is_hotbar(ref) -> bool:
	return ref is String and ref.begins_with("hotbar_")


## Bag and hotbar slots take any item; equipment slots only take what's worn there.
static func is_storage(ref) -> bool:
	return ref is int or is_hotbar(ref)


func get_slot(ref) -> Variant:
	if ref is int:
		return bag[ref]
	if is_hotbar(ref):
		return hotbar[int(ref.trim_prefix("hotbar_"))]
	return equipment.get(ref)


## Which kind of item an equipment slot takes ("ring_1" and "ring_2" both take "ring").
static func slot_type(ref) -> String:
	return "" if is_storage(ref) else String(ref).trim_suffix("_1").trim_suffix("_2")


## Whether `entry` is allowed to sit in slot `ref`.
func can_hold(ref, entry) -> bool:
	if entry == null or is_storage(ref):
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


## Right-click: equip an item from the bag (or put tools and food on the
## hotbar), or put an equipped or hotbar item back in the bag.
func quick_move(ref) -> bool:
	var entry = get_slot(ref)
	if entry == null:
		return false
	if not ref is int:
		var free := bag.find(null)
		return free != -1 and move(ref, free)
	var wanted: String = Items.get_info(entry["id"]).get("slot", "")
	if wanted == "":
		for i in HOTBAR_SIZE:  # Top up a matching stack first, then an empty slot.
			if _can_stack(ref, hotbar_ref(i)):
				return move(ref, hotbar_ref(i))
		var empty := hotbar.find(null)
		return empty != -1 and move(ref, hotbar_ref(empty))
	var targets: Array = [wanted] if equipment.has(wanted) else [wanted + "_1", wanted + "_2"]
	for target in targets:  # Prefer an empty slot, otherwise swap with the first.
		if equipment[target] == null:
			return move(ref, target)
	return move(ref, targets[0])


## Puts items away: first onto matching stacks (hotbar, then bag), then into
## empty bag slots, then empty hotbar slots. Returns how many didn't fit.
func add_item(id: String, count := 1) -> int:
	if not Items.exists(id):
		push_warning("Unknown item: %s" % id)
		return count
	var limit := Items.max_stack(id)
	for list in [hotbar, bag]:
		for i in list.size():
			if count > 0 and list[i] != null and list[i]["id"] == id and list[i]["count"] < limit:
				var added := mini(count, limit - list[i]["count"])
				list[i]["count"] += added
				count -= added
	for list in [bag, hotbar]:
		for i in list.size():
			if count > 0 and list[i] == null:
				var added := mini(count, limit)
				list[i] = {"id": id, "count": added}
				count -= added
	changed.emit()
	return count


## How many more of `id` fit in the bag and hotbar.
func room_for(id: String) -> int:
	var limit := Items.max_stack(id)
	var room := 0
	for entry in hotbar + bag:
		if entry == null:
			room += limit
		elif entry["id"] == id:
			room += limit - entry["count"]
	return room


## How many of `id` you're carrying (bag and hotbar).
func count_of(id: String) -> int:
	var n := 0
	for entry in hotbar + bag:
		if entry != null and entry["id"] == id:
			n += entry["count"]
	return n


## Takes `count` of `id` out of the hotbar and bag (bag first). Returns false,
## and takes nothing, if there aren't enough.
func remove_item(id: String, count: int) -> bool:
	if count_of(id) < count:
		return false
	for list in [bag, hotbar]:
		for i in list.size():
			if count > 0 and list[i] != null and list[i]["id"] == id:
				var taken := mini(count, list[i]["count"])
				list[i]["count"] -= taken
				count -= taken
				if list[i]["count"] <= 0:
					list[i] = null
	changed.emit()
	return true


func select(index: int) -> void:
	index = posmod(index, HOTBAR_SIZE)
	if index != selected:
		selected = index
		changed.emit()


## The id of the item in your hand, or "" for an empty hand.
func selected_id() -> String:
	var entry = hotbar[selected]
	return "" if entry == null else entry["id"]


## Uses up one of the item in your hand (eating, for example).
func consume_selected() -> void:
	var entry = hotbar[selected]
	if entry == null:
		return
	entry["count"] -= 1
	if entry["count"] <= 0:
		hotbar[selected] = null
	changed.emit()


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


## A new world's kit. Horror worlds also get a lantern and a campfire.
func give_starter_items(horror := false) -> void:
	clear()
	if horror:
		hotbar[4] = {"id": "lantern", "count": 1}
		hotbar[5] = {"id": "campfire", "count": 1}
	equip_new("leather_tunic")
	equip_new("leather_boots")
	hotbar[0] = {"id": "stone_axe", "count": 1}
	hotbar[1] = {"id": "stone_pickaxe", "count": 1}
	hotbar[2] = {"id": "apple", "count": 5}
	hotbar[3] = {"id": "crafting_bench", "count": 1}
	received = STARTER_GIFTS.duplicate()
	for id in ["leather_cap", "iron_helm", "chainmail", "leather_gloves", "leather_trousers",
			"swift_boots", "amber_amulet", "silver_ring", "ruby_ring", "feather_charm"]:
		add_item(id)
	add_item("stone", 12)


func get_save_data() -> Dictionary:
	return {
		"bag": bag.duplicate(true), "hotbar": hotbar.duplicate(true),
		"equipment": equipment.duplicate(true), "selected": selected,
		"received": received.duplicate(),
	}


func apply_save_data(data: Dictionary) -> void:
	clear()
	var saved_bag: Array = data.get("bag", [])
	for i in mini(saved_bag.size(), BAG_SIZE):
		bag[i] = _load_entry(saved_bag[i])
	var saved_hotbar: Array = data.get("hotbar", [])
	for i in mini(saved_hotbar.size(), HOTBAR_SIZE):
		hotbar[i] = _load_entry(saved_hotbar[i])
	selected = posmod(int(data.get("selected", 0)), HOTBAR_SIZE)
	var saved_equipment: Dictionary = data.get("equipment", {})
	for slot in equipment:
		var entry = _load_entry(saved_equipment.get(slot))
		equipment[slot] = entry if can_hold(slot, entry) else null
		if entry != null and equipment[slot] == null:
			add_item(entry["id"], entry["count"])
	# Saves with a hotbar but no `received` list already got the two tools.
	var default_received: Array = ["stone_axe", "stone_pickaxe"] if data.has("hotbar") else []
	received = Array(data.get("received", default_received)).map(func(id): return String(id))
	_give_missing_gifts()
	changed.emit()


func _give_missing_gifts() -> void:
	for id in STARTER_GIFTS:
		if id in received:
			continue
		received.append(id)
		var empty := hotbar.find(null)
		if empty != -1:
			hotbar[empty] = {"id": id, "count": 1}
		else:
			add_item(id)


## Turns a saved slot back into an entry, skipping items that no longer exist.
func _load_entry(saved) -> Variant:
	if not saved is Dictionary or not Items.exists(String(saved.get("id", ""))):
		return null
	return {"id": String(saved["id"]), "count": maxi(1, int(saved.get("count", 1)))}


func _set_slot(ref, entry) -> void:
	if ref is int:
		bag[ref] = entry
	elif is_hotbar(ref):
		hotbar[int(ref.trim_prefix("hotbar_"))] = entry
	else:
		equipment[ref] = entry


func _can_stack(from, to) -> bool:
	var a = get_slot(from)
	var b = get_slot(to)
	return (is_storage(to) and a != null and b != null and a["id"] == b["id"]
			and b["count"] < Items.max_stack(b["id"]))


static func _same_ref(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b
