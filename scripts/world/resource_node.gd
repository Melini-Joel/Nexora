class_name ResourceNode
extends StaticBody3D
## Recurso recolectable (árbol, roca...). El servidor lleva la cuenta de golpes
## y avisa a todos cuando se agota o reaparece.

var resource_type := "wood"
var display_name := "árbol"
var action_name := "Talar"
var preferred_tool := "hatchet"  ## Herramienta que rinde más con este recurso ("" = a mano).
var base_yield := 2  ## Cuánto da cada golpe a mano.
var max_hits := 5
var hits_left := 5
var depleted := false
var visual: Node3D


func setup(type: String, p_display_name: String, p_action_name: String, hits: int, tool: String) -> void:
	resource_type = type
	preferred_tool = tool
	display_name = p_display_name
	action_name = p_action_name
	max_hits = hits
	hits_left = hits


func get_interact_text() -> String:
	return "%s %s" % [action_name, display_name]


func set_depleted(value: bool) -> void:
	depleted = value
	visible = not value
	collision_layer = 0 if value else 1
	if not value:
		hits_left = max_hits
		if visual:
			var base_scale := visual.scale
			visual.scale = base_scale * 0.2
			create_tween().tween_property(visual, "scale", base_scale, 0.6) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_hit() -> void:
	if visual == null:
		return
	var tween := create_tween()
	tween.tween_property(visual, "rotation:z", 0.07, 0.05)
	tween.tween_property(visual, "rotation:z", -0.05, 0.07)
	tween.tween_property(visual, "rotation:z", 0.0, 0.08)
