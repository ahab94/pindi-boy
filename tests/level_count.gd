extends SceneTree
func _initialize() -> void:
	print("LEVELS ", load("res://scripts/levels.gd").count())
	quit(0)
