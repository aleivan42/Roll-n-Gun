extends StaticBody3D  # or Area3D, depending on your setup

var is_hidden := false

# Called when the bullet hits the target
func take_damage(_amount: int) -> void:
	if is_hidden:
		return  # Already hidden, ignore further hits
	
	_hide_target()
	await get_tree().create_timer(3.0).timeout
	_show_target()

# Disable visibility and collision
func _hide_target() -> void:
	is_hidden = true
	visible = false
	collision_layer = 0  # Disable collision
	collision_mask = 0   # Disable collision

# Re-enable visibility and collision after delay
func _show_target() -> void:
	visible = true
	collision_layer = 1  # Restore original layer (adjust as needed)
	collision_mask = 1   # Restore original mask (adjust as needed)
	is_hidden = false
