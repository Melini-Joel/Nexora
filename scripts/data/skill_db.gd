class_name SkillDB
extends RefCounted
## Habilidades que se mejoran con puntos al subir de nivel (menú de personaje, tecla C).
##
## Experiencia (XP): se gana recolectando, fabricando, construyendo, cazando, derrotando
## sombras, domesticando, abriendo cofres y completando misiones. Cada nivel da 1 punto
## (cada 5 niveles, 2 puntos).

const SKILLS := {
	"vitality": {"name": "Vida", "description": "+15 de vida máxima por nivel.", "max": 10},
	"endurance": {"name": "Energía", "description": "+15 de energía máxima y recuperás un 8% más rápido.", "max": 10},
	"strength": {"name": "Fuerza", "description": "+10% de daño en combate por nivel.", "max": 10},
	"gathering": {"name": "Recolección", "description": "+15% de recursos por golpe.", "max": 10},
	"carry": {"name": "Carga", "description": "+6 kg de capacidad en la mochila.", "max": 10},
	"agility": {"name": "Agilidad", "description": "+4% de velocidad al caminar y correr.", "max": 10},
}

## Experiencia que da cada acción.
const XP := {
	"gather": 2, "craft": 5, "build": 8, "chest": 12, "quest": 120, "tame": 60,
	"kill_animal": 15, "kill_shade": 25, "kill_brute": 70,
}


## Experiencia necesaria para pasar del nivel "level" al siguiente.
static func xp_to_next(level: int) -> int:
	return 100 + (level - 1) * 60


static func points_for_level(level: int) -> int:
	return 2 if level % 5 == 0 else 1


static func empty_progress() -> Dictionary:
	return {"level": 1, "xp": 0, "points": 0, "skills": {}}


static func skill_level(progress: Dictionary, skill: String) -> int:
	return int(progress.get("skills", {}).get(skill, 0))


# --- Efectos de cada habilidad -------------------------------------------------------------

static func max_health(progress: Dictionary) -> float:
	return 100.0 + 15.0 * skill_level(progress, "vitality")


static func max_stamina(progress: Dictionary) -> float:
	return 100.0 + 15.0 * skill_level(progress, "endurance")


static func stamina_regen_multiplier(progress: Dictionary) -> float:
	return 1.0 + 0.08 * skill_level(progress, "endurance")


static func damage_multiplier(progress: Dictionary) -> float:
	return 1.0 + 0.1 * skill_level(progress, "strength")


static func gather_multiplier(progress: Dictionary) -> float:
	return 1.0 + 0.15 * skill_level(progress, "gathering")


static func carry_bonus(progress: Dictionary) -> float:
	return 6.0 * skill_level(progress, "carry")


static func speed_multiplier(progress: Dictionary) -> float:
	return 1.0 + 0.04 * skill_level(progress, "agility")
