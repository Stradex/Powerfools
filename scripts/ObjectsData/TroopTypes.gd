class_name TroopTypesObject
extends Object

const TROOPS_FILES_NAME: String = "troops.json"

var TroopsTypes: Array

var InvalidTroop: Dictionary = {
	name = "invalid",
	is_warrior = false, #if the troop should fight at all or not in normal circunstances
	cost_to_make = 0, #only used in case it does not require building to be deployed
	damage = Vector2.ZERO, #minimum and maximum damage to do by this troop
	idle_cost_per_turn = 0, #cost of this troop per turn while doing nothing (cost per 1000 troops)
	moving_cost_per_turn = 0, #cost of this troop per turn while traveling (cost per 1000 troops)
	battle_cost_per_turn = 0, #cost of this troop per turn while fighting (cost per 1000 troops)
	health= 0 # health of this troop
}

func _init():
	pass

func clearList() -> void:
	TroopsTypes.clear()

func add(troopDict: Dictionary):
	TroopsTypes.append(troopDict)

func getByName(troopName: String) -> Dictionary:
	for troopDict in TroopsTypes:
		if troopDict.name.to_lower() == troopName.to_lower():
			return troopDict
	return InvalidTroop

func getIDByName(troopName: String) -> int:
	var i: int = 0
	for troopDict in TroopsTypes:
		if troopDict.name.to_lower() == troopName.to_lower():
			return i
		i+=1
	return -1

func getName(troopID: int) -> String:
	var i: int = 0
	for troopDict in TroopsTypes:
		if i == troopID:
			return troopDict.name
		i+=1
	return "error"

func calculateTroopDamage(troopID: int) -> float:
	var i: int = 0
	for troopDict in TroopsTypes:
		if i == troopID:
			return Game.rng.randf_range(troopDict.damage.x, troopDict.damage.y)
		i+=1
	return 0.0

func amountNeededToDefend(troopID: int, enemy_health: float, enemy_damage: float) -> int:
	var average_troop_damage: float = float((TroopsTypes[troopID].damage.x + TroopsTypes[troopID].damage.y)/2.0)
	var average_troop_health: float = float(TroopsTypes[troopID].health)
	return int(round((enemy_health + enemy_damage)/(average_troop_damage+average_troop_health)))

func getAverageDamage(troopID: int) -> float:
	var i: int = 0
	for troopDict in TroopsTypes:
		if i == troopID:
			return (troopDict.damage.x + troopDict.damage.y)/2.0
		i+=1
	return 0.0
func getByID(troopID: int) -> Dictionary:
	var i: int = 0
	for troopDict in TroopsTypes:
		if i == troopID:
			return troopDict
		i+=1
	return InvalidTroop

func getList() -> Array:
	return TroopsTypes.duplicate(true) #gives a copy so no one can fuck up the original list

func load_from_file(folder: String, fileSystemObj: Object) -> bool:
	if !fileSystemObj.file_exists(folder + "/" + TROOPS_FILES_NAME):
		return false
	var troopsImportedData: Dictionary = fileSystemObj.get_data_from_json(folder + "/" + TROOPS_FILES_NAME)
	assert(troopsImportedData.has('troops'))
	for troopDict in troopsImportedData['troops']:
		add({
			name = troopDict["name"],
			is_warrior = troopDict["is_warrior"],
			cost_to_make = troopDict["cost_to_make"],
			damage = Vector2(troopDict["damage_min"], troopDict["damage_max"]),
			idle_cost_per_turn = troopDict["idle_cost_per_turn"],
			moving_cost_per_turn = troopDict["moving_cost_per_turn"],
			battle_cost_per_turn = troopDict["battle_cost_per_turn"], 
			health= troopDict["health"] 
		})
	return true
