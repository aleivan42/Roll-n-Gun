extends RigidBody3D

var BasicFPSPlayerScene : PackedScene = preload("basic_player_head.tscn")
var addedHead = false

func _enter_tree():
	if find_child("Head"):
		addedHead = true
	
	if Engine.is_editor_hint() && !addedHead:
		var s = BasicFPSPlayerScene.instantiate()
		add_child(s)
		s.owner = get_tree().edited_scene_root
		addedHead = true

## PLAYER MOVEMENT SCRIPT WITH PHYSICS ##

@export_category("Mouse Capture")
@export var CAPTURE_ON_START := true

@export_category("Movement")
@export_subgroup("Settings")
@export var MOVE_FORCE := 10.0
@export var AIR_CONTROL_FACTOR := 0.3
@export var JUMP_FORCE := 10.0
@export var MAX_SPEED := 8.0
@export var BRAKE_FORCE := 5.0
@export_subgroup("Torque")
@export var TORQUE_FORCE := 2.0
@export var TORQUE_DAMPING := 0.8
@export var MAX_ANGULAR_SPEED := 3.0
@export_subgroup("Head Bob")
@export var HEAD_BOB := true
@export var HEAD_BOB_FREQUENCY := 0.3
@export var HEAD_BOB_AMPLITUDE := 0.01
@export_subgroup("Clamp Head Rotation")
@export var CLAMP_HEAD_ROTATION := true
@export var CLAMP_HEAD_ROTATION_MIN := -90.0
@export var CLAMP_HEAD_ROTATION_MAX := 90.0
@export_subgroup("Dash")
@export var DASH_FORCE := 30.0
@export var DASH_COOLDOWN := 1.0

@export_category("Physics Settings")
@export var MASS := 2.0
@export var FRICTION := 0.5
@export var BOUNCINESS := 0.3
@export var LINEAR_DAMP := 0.1
@export var ANGULAR_DAMP := 0.1

@export_category("Key Binds")
@export_subgroup("Mouse")
@export var MOUSE_ACCEL := true
@export var KEY_BIND_MOUSE_SENS := 0.005
@export var KEY_BIND_MOUSE_ACCEL := 50
@export_subgroup("Movement")
@export var KEY_BIND_UP := "ui_up"
@export var KEY_BIND_LEFT := "ui_left"
@export var KEY_BIND_RIGHT := "ui_right"
@export var KEY_BIND_DOWN := "ui_down"
@export var KEY_BIND_JUMP := "ui_accept"
@export var KEY_BIND_BRAKE := "ui_cancel"

var rotation_target_player : float
var rotation_target_head : float
var head_start_pos : Vector3
var tick = 0
var is_on_ground := false
var ground_check_ray : RayCast3D
var dash_ready := true
var bullet = load("res://Scenes/bullet.tscn")
var instance
@onready var gun_anim = $Head/blaster/AnimationPlayer
@onready var gun_barrel = $Head/blaster/RayCast3D


func _ready():
	if Engine.is_editor_hint():
		return
	
	# Physics properties
	mass = MASS
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = FRICTION
	physics_material_override.bounce = BOUNCINESS
	linear_damp = LINEAR_DAMP
	angular_damp = ANGULAR_DAMP
	
	# Create ground check ray
	ground_check_ray = RayCast3D.new()
	ground_check_ray.enabled = true
	ground_check_ray.collide_with_areas = true
	ground_check_ray.collide_with_bodies = true
	ground_check_ray.target_position = Vector3(0, -0.6, 0)
	add_child(ground_check_ray)
	
	# Capture mouse if set to true
	if CAPTURE_ON_START:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	head_start_pos = $Head.position

func _physics_process(delta):
	if Engine.is_editor_hint():
		return
	
	# Update ground check
	is_on_ground = ground_check_ray.is_colliding()
	
	# Increment player tick
	tick += 1
	
	# Handle movement
	handle_movement(delta)
	
	# Handle rotation
	rotate_player(delta)
	
	# Dash input
	if Input.is_action_just_pressed("dash") and dash_ready:
		perform_dash()
	
	# Head bob
	if HEAD_BOB:
		if linear_velocity.length() > 0.5 and is_on_ground:
			head_bob_motion()
		reset_head_bob(delta)
	
	# Limit maximum speed
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.normalized() * MAX_SPEED
	
	# Limit angular velocity
	if angular_velocity.length() > MAX_ANGULAR_SPEED:
		angular_velocity = angular_velocity.normalized() * MAX_ANGULAR_SPEED
	
	# Apply torque damping
	angular_velocity *= TORQUE_DAMPING

func _process(delta):
	if Engine.is_editor_hint():
		return
	
	# Shooting
	if Input.is_action_pressed("shoot"):
		if !gun_anim.is_playing():
			gun_anim.play("Shoot")
			instance = bullet.instantiate()
			instance.position = gun_barrel.global_position
			instance.transform.basis = gun_barrel.global_transform.basis
			get_parent().add_child(instance)
			# Small recoil torque
			apply_torque_impulse(Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)) * 0.5)

func _input(event):
	if Engine.is_editor_hint():
		return
		
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		set_rotation_target(event.relative)

func set_rotation_target(mouse_motion : Vector2):
	rotation_target_player += -mouse_motion.x * KEY_BIND_MOUSE_SENS
	rotation_target_head += -mouse_motion.y * KEY_BIND_MOUSE_SENS
	if CLAMP_HEAD_ROTATION:
		rotation_target_head = clamp(rotation_target_head, deg_to_rad(CLAMP_HEAD_ROTATION_MIN), deg_to_rad(CLAMP_HEAD_ROTATION_MAX))

func rotate_player(delta):
	if MOUSE_ACCEL:
		var new_rot = Quaternion(Vector3.UP, rotation_target_player)
		global_transform.basis = Basis(global_transform.basis.get_rotation_quaternion().slerp(new_rot, KEY_BIND_MOUSE_ACCEL * delta))
		$Head.quaternion = $Head.quaternion.slerp(Quaternion(Vector3.RIGHT, rotation_target_head), KEY_BIND_MOUSE_ACCEL * delta)
	else:
		global_transform.basis = Basis(Quaternion(Vector3.UP, rotation_target_player))
		$Head.quaternion = Quaternion(Vector3.RIGHT, rotation_target_head)

func handle_movement(delta):
	var input_dir = Input.get_vector(KEY_BIND_LEFT, KEY_BIND_RIGHT, KEY_BIND_UP, KEY_BIND_DOWN)
	var direction = (global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply movement force
	if input_dir.length() > 0:
		var force_factor = MOVE_FORCE * (AIR_CONTROL_FACTOR if not is_on_ground else 1.0)
		apply_central_force(direction * force_factor)
		# Add torque based on movement direction
		var torque_dir = Vector3(direction.z, 0, -direction.x) * TORQUE_FORCE
		apply_torque_impulse(torque_dir)
	
	# Braking when no input
	elif is_on_ground:
		var horizontal_vel = Vector3(linear_velocity.x, 0, linear_velocity.z)
		if horizontal_vel.length() > 0.1:
			apply_central_force(-horizontal_vel.normalized() * BRAKE_FORCE)
		else:
			linear_velocity.x = 0
			linear_velocity.z = 0
	
	# Jumping
	if Input.is_action_just_pressed(KEY_BIND_JUMP) and is_on_ground:
		apply_central_impulse(Vector3.UP * JUMP_FORCE)
		# Add random spin when jumping
		apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.2)

func perform_dash():
	var forward: Vector3 = -$Head.global_transform.basis.z.normalized()
	apply_central_impulse(forward * DASH_FORCE)
	dash_ready = false
	var dash_timer := Timer.new()
	dash_timer.wait_time = DASH_COOLDOWN
	dash_timer.one_shot = true
	dash_timer.timeout.connect(func(): dash_ready = true)
	add_child(dash_timer)
	dash_timer.start()

func head_bob_motion():
	var pos = Vector3.ZERO
	pos.y += sin(tick * HEAD_BOB_FREQUENCY) * HEAD_BOB_AMPLITUDE
	pos.x += cos(tick * HEAD_BOB_FREQUENCY/2) * HEAD_BOB_AMPLITUDE * 2
	$Head.position += pos

func reset_head_bob(delta):
	$Head.position = lerp($Head.position, head_start_pos, 2 * (1/HEAD_BOB_FREQUENCY) * delta)
