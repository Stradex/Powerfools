class_name TroopTypesObject
extends Object

var TroopsTypes: Array

var InvalidTroop: Dictionary = {
	name = "invalid",
	no_building = false, #the troop does not require building to be made
	can_be_bought = false, #if the entity can be bought at all or not
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

func getByID(troopID: int) -> Dictionary:
	var i: int = 0
	for troopDict in TroopsTypes:
		if i == troopID:
			return troopDict
		i+=1
	return InvalidTroop

func getList() -> Array:
	return TroopsTypes.duplicate(true) #gives a copy so no one can fuck up the original list
