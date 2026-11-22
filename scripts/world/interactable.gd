class_name Interactable
extends StaticBody3D
## Objeto del mundo que se usa con E y abre una ventana de diálogo propia
## (por ejemplo el Albatros: reparación y viajes). Ver dialog_ui.gd.

var dialog_id := ""
var interact_text := ""


func get_interact_text() -> String:
	return interact_text
