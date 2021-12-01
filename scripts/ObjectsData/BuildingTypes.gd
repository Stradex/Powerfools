class_name BuildingTypesObject
extends Object

var BuildingTypes: Array

var InvalidBuilding: Dictionary = {
	name = "invalid",
	buy_prize = 0,
	sell_prize = 0,
	deploy_prize = 0,
	turns_to_build = 0,
	id_troop_generate = -1,
	turns_to_deploy_troops = 0
}

func _init():
	pass

func clearList() -> void:
	BuildingTypes.clear()

func add(buildingDict: Dictionary):
	BuildingTypes.append(buildingDict)

func getByName(buildingName: String) -> Dictionary:
	for buildDict in BuildingTypes:
		if buildDict.name.to_lower() == buildingName.to_lower():
			return buildDict
	return InvalidBuilding

func getIDByName(buildingName: String) -> int:
	var i: int = 0
	for buildDict in BuildingTypes:
		if buildDict.name.to_lower() == buildingName.to_lower():
			return i
		i+=1
	return -1

func getByID(buildingID: int) -> Dictionary:
	var i: int = 0
	for buildDict in BuildingTypes:
		if i == buildingID:
			return buildDict
		i+=1
	return InvalidBuilding
