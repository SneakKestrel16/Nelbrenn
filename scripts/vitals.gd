extends Node
## Health and hunger. Hunger slowly runs down (faster while sprinting); eat
## food from the hotbar to fill it up. While you're well fed your health
## comes back by itself; if you starve it drains away, and at zero you
## faint and wake up back at the world's starting point (keeping your items).

signal damaged(amount: float)
signal fainted

const Items := preload("res://scripts/items.gd")

const MAX := 100.0
const HUNGER_SECONDS := 900.0  ## Full to empty in 15 minutes of walking.
const SPRINT_HUNGER := 2.0     ## Sprinting makes you this many times hungrier.
const REGEN_PER_SECOND := 1.0  ## Health back per second while hunger is above half.
const STARVE_PER_SECOND := 1.5 ## Health lost per second while hunger is empty.

var player  # player.gd
var world  # world.gd
var game  # game.gd, for messages

var health := MAX
var hunger := MAX

var _warned := ""  # The last hunger warning shown, so it isn't repeated.


func _process(delta: float) -> void:
	var rate := MAX / HUNGER_SECONDS
	if player.controls_enabled and Input.is_action_pressed("sprint") and Vector2(player.velocity.x, player.velocity.z).length() > 1.0:
		rate *= SPRINT_HUNGER
	hunger = maxf(hunger - rate * delta, 0.0)

	if hunger <= 0.0:
		hurt(STARVE_PER_SECOND * delta)
	elif hunger >= MAX * 0.5:
		health = minf(health + REGEN_PER_SECOND * delta, MAX)

	if hunger <= 0.0 and _warned != "starving":
		_warned = "starving"
		game.show_message("You're starving! Eat something before you faint.")
	elif hunger > 0.0 and hunger < 25.0 and _warned == "":
		_warned = "hungry"
		game.show_message("You're getting hungry. Eat something from your hotbar.")
	elif hunger >= 30.0:
		_warned = ""


## Eats one `id` if it's food and you're hungry. Returns true if it was eaten.
func eat(id: String) -> bool:
	var food := float(Items.get_info(id).get("food", 0))
	if food <= 0.0:
		return false
	if hunger >= MAX - 1.0:
		game.show_message("You're full.")
		return false
	hunger = minf(hunger + food, MAX)
	health = minf(health + food * 0.25, MAX)
	return true


## Takes `amount` health. `cause` names what did it ("" means hunger).
func hurt(amount: float, cause := "") -> void:
	health -= amount
	damaged.emit(amount)
	if health <= 0.0:
		_faint(cause)


func _faint(cause: String) -> void:
	health = MAX
	hunger = maxf(hunger, MAX * 0.5)
	player.global_position = world.find_spawn_point()
	player.velocity = Vector3.ZERO
	world.generate_around(player.global_position, true)  # Ground to land on.
	if cause == "":
		game.show_message("You fainted from hunger... and woke up back where you started.")
	else:
		game.show_message("You were killed by %s... and woke up back where you started." % cause)
	fainted.emit()


func get_save_data() -> Dictionary:
	return {"health": health, "hunger": hunger}


func apply_save_data(data: Dictionary) -> void:
	health = clampf(float(data.get("health", MAX)), 1.0, MAX)
	hunger = clampf(float(data.get("hunger", MAX)), 0.0, MAX)
