extends CharacterBody2D

# Player controller for movement, defend, and the two-step attack combo.
@export var speed: float = 320.0
@export var attack_damage: int = 25

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D

var is_attacking := false
var facing_right := true
var combo_step := 0
var attack_queued := false
var is_defending := false

func _ready() -> void:
	attack_shape.disabled = true
	# End attacks and advance the combo from the animation system.
	animated_sprite.animation_finished.connect(_on_animation_finished)

func _physics_process(_delta: float) -> void:
	if Input.is_action_pressed("defend") and not is_attacking:
		start_defend()
	else:
		stop_defend()
		
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		# Queue the second swing if attack is pressed during attack_1.
		if Input.is_action_just_pressed("attack") and combo_step == 1:
			attack_queued = true
		return

	if is_defending:
		velocity = Vector2.ZERO
		move_and_slide()
		# Do not let movement overwrite the defend animation.
		return

	handle_movement()

	if Input.is_action_just_pressed("attack"):
		start_attack_1()

	move_and_slide()
	
# Start the defense animation
func start_defend() -> void:
	is_defending = true
	animated_sprite.play("defend")

# Stop the defense animation
func stop_defend() -> void:
	if is_defending:
		is_defending = false
		animated_sprite.play("idle")

func handle_movement() -> void:
	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	input_vector = input_vector.normalized()

	velocity = input_vector * speed

	if input_vector != Vector2.ZERO:
		if input_vector.x > 0:
			facing_right = true
			animated_sprite.flip_h = false
		elif input_vector.x < 0:
			facing_right = false
			animated_sprite.flip_h = true

		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

func start_attack_1() -> void:
	is_attacking = true
	combo_step = 1
	attack_queued = false
	animated_sprite.play("attack_1")
	perform_attack_hit()

func start_attack_2() -> void:
	is_attacking = true
	combo_step = 2
	attack_queued = false
	animated_sprite.play("attack_2")
	perform_attack_hit()

func perform_attack_hit() -> void:
	# Enable the hitbox after the current frame so physics overlap data updates cleanly.
	attack_shape.set_deferred("disabled", false)

	if facing_right:
		attack_area.position.x = 12
	else:
		attack_area.position.x = -12

	# Wait two physics frames so the overlap query sees the newly enabled hitbox.
	await get_tree().physics_frame
	await get_tree().physics_frame

	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(attack_damage)

	# Disable the hitbox again after resolving the swing.
	attack_shape.set_deferred("disabled", true)

func _on_animation_finished() -> void:
	if animated_sprite.animation == "attack_1":
		if attack_queued:
			start_attack_2()
		else:
			is_attacking = false
			combo_step = 0
	elif animated_sprite.animation == "attack_2":
		is_attacking = false
		combo_step = 0
