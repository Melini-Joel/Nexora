class_name Inventory
extends RefCounted
## Inventario por casilleros: 6 de barra rápida (0-5) + 24 de mochila (6-29).
## Lo maneja el servidor; los clientes reciben una copia (Array de casilleros) para dibujarla.
## Cada casillero es {} (vacío) o {"id": String, "count": int}.

const HOTBAR_SIZE := 6
const MAIN_SIZE := 24
const SIZE := HOTBAR_SIZE + MAIN_SIZE
const CAPACITY_KG := 40.0  ## Peso a partir del cual quedás sobrecargado.

var slots: Array = []


func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = {}


static func is_hotbar(index: int) -> bool:
	return index < HOTBAR_SIZE


static func weight_of(slot_array: Array) -> float:
	var total := 0.0
	for slot in slot_array:
		if not slot.is_empty():
			total += ItemDB.weight(slot["id"]) * slot["count"]
	return total


## Capacidad de carga (la mochila grande suma kilos extra).
static func capacity_for(slot_array: Array) -> float:
	var bonus := 0.0
	for slot in slot_array:
		if not slot.is_empty():
			bonus = maxf(bonus, ItemDB.get_item(slot["id"]).get("capacity_bonus", 0.0))
	return CAPACITY_KG + bonus


static func count_in(slot_array: Array, id: String) -> int:
	var total := 0
	for slot in slot_array:
		if slot.get("id", "") == id:
			total += slot["count"]
	return total


## Multiplicador de velocidad según cuánto pesa la mochila (0..1+ de la capacidad).
static func speed_multiplier_for(load_ratio: float) -> float:
	if load_ratio <= 0.4:
		return 1.0
	if load_ratio <= 1.0:
		return lerpf(1.0, 0.55, (load_ratio - 0.4) / 0.6)
	return 0.35  # Sobrecargado.


func is_valid(index: int) -> bool:
	return index >= 0 and index < SIZE


func get_slot(index: int) -> Dictionary:
	return slots[index] if is_valid(index) else {}


func total_weight() -> float:
	return weight_of(slots)


func to_array() -> Array:
	var copy: Array = []
	for slot in slots:
		copy.append(slot.duplicate())
	return copy


func load_from(data: Array) -> void:
	for i in mini(data.size(), SIZE):
		slots[i] = data[i].duplicate()


## Agrega ítems. Devuelve lo que no entró.
func add(id: String, amount: int) -> int:
	if not ItemDB.exists(id) or amount <= 0:
		return amount
	var stack := ItemDB.stack_size(id)
	# 1) Completar pilas existentes.
	for i in SIZE:
		var slot: Dictionary = slots[i]
		if slot.get("id", "") == id and slot["count"] < stack:
			var n := mini(amount, stack - slot["count"])
			slot["count"] += n
			amount -= n
			if amount == 0:
				return 0
	# 2) Casilleros vacíos (las herramientas prefieren la barra rápida).
	for i in _empty_slot_order(id):
		if slots[i].is_empty():
			var n := mini(amount, stack)
			slots[i] = {"id": id, "count": n}
			amount -= n
			if amount == 0:
				return 0
	return amount


func _empty_slot_order(id: String) -> Array:
	var hotbar := range(HOTBAR_SIZE)
	var main := range(HOTBAR_SIZE, SIZE)
	return hotbar + main if ItemDB.tool_type(id) != "" else main + hotbar


## Arrastrar un casillero sobre otro: mueve, junta pilas o intercambia.
func move(from: int, to: int) -> bool:
	if not is_valid(from) or not is_valid(to) or from == to:
		return false
	var a: Dictionary = slots[from]
	var b: Dictionary = slots[to]
	if a.is_empty():
		return false
	if b.is_empty():
		slots[to] = a
		slots[from] = {}
	elif b["id"] == a["id"]:
		var n := mini(a["count"], ItemDB.stack_size(a["id"]) - b["count"])
		if n <= 0:
			return false
		b["count"] += n
		a["count"] -= n
		if a["count"] <= 0:
			slots[from] = {}
	else:
		slots[to] = a
		slots[from] = b
	return true


## Divide una pila a la mitad en el primer casillero libre.
func split(index: int) -> bool:
	var slot := get_slot(index)
	if slot.is_empty() or slot["count"] < 2:
		return false
	for i in range(HOTBAR_SIZE, SIZE) + range(HOTBAR_SIZE):
		if slots[i].is_empty():
			var half: int = slot["count"] / 2
			slot["count"] -= half
			slots[i] = {"id": slot["id"], "count": half}
			return true
	return false


## Shift+Click: pasa el objeto de la barra rápida a la mochila o al revés.
func quick_move(index: int) -> bool:
	var slot := get_slot(index)
	if slot.is_empty():
		return false
	var targets: Array = range(HOTBAR_SIZE, SIZE) if is_hotbar(index) else range(HOTBAR_SIZE)
	var moved := false
	for i in targets:  # Primero juntar con pilas iguales.
		if slots[i].get("id", "") == slot["id"] and move(index, i):
			moved = true
			if slots[index].is_empty():
				return true
	for i in targets:
		if slots[i].is_empty():
			return move(index, i)
	return moved


## Saca todo el contenido de un casillero (para tirarlo al suelo).
func take(index: int) -> Dictionary:
	var slot := get_slot(index)
	if slot.is_empty():
		return {}
	slots[index] = {}
	return slot


func count(id: String) -> int:
	return count_in(slots, id)


func has_items(items: Dictionary) -> bool:
	for id: String in items:
		if count(id) < int(items[id]):
			return false
	return true


## Saca ítems (primero de la mochila, al final de la barra rápida). Devuelve false si no alcanzan.
func remove(id: String, amount: int) -> bool:
	if count(id) < amount:
		return false
	var order: Array = range(SIZE - 1, -1, -1)
	for i in order:
		var slot: Dictionary = slots[i]
		if slot.get("id", "") != id:
			continue
		var n := mini(amount, slot["count"])
		slot["count"] -= n
		amount -= n
		if slot["count"] <= 0:
			slots[i] = {}
		if amount == 0:
			break
	return true


func remove_items(items: Dictionary) -> bool:
	if not has_items(items):
		return false
	for id: String in items:
		remove(id, int(items[id]))
	return true
