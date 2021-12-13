class_name BuildingTypesObject
extends Object

const BUILDINGS_FILES_NAME: String = "buildings.json"

var BuildingTypes: Array

var InvalidBuilding: Dictionary = {
	name = "invalid",
	buy_prize = 0,
	sell_prize = 0,
	deploy_prize = 0,
	turns_to_build = 0,
	id_troop_generate = -1,
	building_img='no_building',
	turns_to_deploy_troops = 0,
	deploy_amount = 0,
	max_amount = 0 #if zero, you can have unlimited amount of this
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

func getImg(buildingID: int) -> String:
	return getByID(buildingID).building_img

func getByID(buildingID: int) -> Dictionary:
	var i: int = 0
	for buildDict in BuildingTypes:
		if i == buildingID:
			return buildDict
		i+=1
	return InvalidBuilding

func getList() -> Array:
	return BuildingTypes.duplicate(true) #gives a copy so no one can fuck up the original list

func load_from_file(folder: String, fileSystemObj: Object, troops_types_obj: Object) -> void:
	var troopsImportedData: Dictionary = fileSystemObj.get_data_from_json(folder + "/" + BUILDINGS_FILES_NAME)
	assert(troopsImportedData.has('buildings'))
	for troopDict in troopsImportedData['buildings']:
		add({
			name = troopDict["name"],
			buy_prize = troopDict["buy_prize"],
			sell_prize = troopDict["sell_prize"],
			deploy_prize = troopDict["deploy_prize"],
			turns_to_build = troopDict["turns_to_build"],
			id_troop_generate = troops_types_obj.getIDByName(troopDict["troop_to_generate"]),
			building_img = troopDict["building_img"],
			turns_to_deploy_troops = troopDict["turns_to_deploy_troops"], 
			deploy_amount= troopDict["deploy_amount"],
			max_amount= troopDict["max_amount"] 
		})
