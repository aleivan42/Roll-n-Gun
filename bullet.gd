extends Area3D

# Movement
@export var SPEED := 80.0
var hit_something := false

# Nodes
@onready var mesh = $MeshInstance3D
@onready var collision_shape = $CollisionShape3D
@onready var particles = $GPUParticles3D

func _ready() -> void:
	# Initialize
	particles.emitting = false
	particles.local_coords = false  # Critical for world-space positioning
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if hit_something:
		return
	
	var from := global_transform.origin
	var to := from + transform.basis.z * -SPEED * delta
	var space := get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = collision_mask  # Optional: use if you use layers

	var result := space.intersect_ray(query)

	if result:
		global_transform.origin = result.position
		_handle_collision(result.collider)
	else:
		global_transform.origin = to

func _on_body_entered(body: Node) -> void:
	_handle_collision(body)

func _on_area_entered(area: Area3D) -> void:
	_handle_collision(area)

func _handle_collision(collider: Node) -> void:
	if hit_something:
		return
	
	hit_something = true
	mesh.visible = false
	
	# Store exact collision position before any deferred calls
	var collision_pos := global_transform.origin
	
	# Deferred physics modifications
	call_deferred("_deferred_collision_cleanup", collision_pos)
	
	# Apply damage if applicable
	if collider.has_method("take_damage"):
		collider.call_deferred("take_damage", 10)

func _deferred_collision_cleanup(collision_pos: Vector3) -> void:
	# Disable collision safely
	collision_shape.disabled = true
	
	# Position particles at exact collision point
	particles.global_transform.origin = collision_pos
	particles.emitting = true

	# Debug marker using bullet mesh
	_show_debug_hit_point(collision_pos)

	# Wait for particles to finish before deleting
	await get_tree().create_timer(particles.lifetime).timeout
	queue_free()

func _show_debug_hit_point(position: Vector3) -> void:
	var marker := mesh.duplicate() as MeshInstance3D
	marker.visible = true
	marker.global_transform = Transform3D(Basis(), position)
	marker.scale = mesh.scale * 0.5  # Optional: smaller debug marker
	marker.set_name("DebugHitPoint")

	get_tree().current_scene.add_child(marker)

	# Auto-delete after 5 seconds
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 5.0
	timer.timeout.connect(func(): marker.queue_free())
	marker.add_child(timer)
	timer.start()

# Optional: Auto-delete if no collision
func _on_lifetime_timeout() -> void:
	if !hit_something:
		queue_free()
