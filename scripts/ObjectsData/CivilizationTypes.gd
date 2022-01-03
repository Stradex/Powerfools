class_name CivilizationTypesObject
extends Object

const CIVILIZATIONS_FILES_NAME: String = "civilizations.json"

var CivilizationTypes: Array

var InvalidCivilizationType: Dictionary = {
	default_name = "_default"
}

func _init():
	pass

func clearList() -> void:
	CivilizationTypes.clear()

func add(civDict: Dictionary):
	CivilizationTypes.append(civDict)

func getByName(civilizationName: String) -> Dictionary:
	for civDict in CivilizationTypes:
		if civDict.default_name.to_lower() == civilizationName.to_lower():
			return civDict
	return InvalidCivilizationType

func getIDByName(civilizationName: String) -> int:
	var i: int = 0
	for civDict in CivilizationTypes:
		if civDict.default_name.to_lower() == civilizationName.to_lower():
			return i
		i+=1
	return -1

func getByID(civID: int) -> Dictionary:
	var i: int = 0
	for civDict in CivilizationTypes:
		if i == civID:
			return civDict
		i+=1
	return InvalidCivilizationType

func getList() -> Array:
	return CivilizationTypes.duplicate(true) #gives a copy so no one can fuck up the original list

func load_from_file(folder: String, fileSystemObj: Object) -> bool:
	if !fileSystemObj.file_exists(folder + "/" + CIVILIZATIONS_FILES_NAME):
		return false
	var civImportedData: Dictionary = fileSystemObj.get_data_from_json(folder + "/" + CIVILIZATIONS_FILES_NAME)
	assert(civImportedData.has('civilizations'))
	for civDict in civImportedData['civilizations']:
		add({
			default_name = civDict["default_name"]
		})
	return true
