class_name TribalSocietyObject
extends Object

var TribesTypes: Array = []
const TRIBES_FILES_NAME: String = "tribes_settings.json"

var InvalidTile: Dictionary = {
	name = "invalid",
	min_gold = 0, #leave it blank if this tile cannot be improved
	max_gold = 0,
	troops = [] # -> Data: troop_name, min_amount, max_amount
}

func _init():
	TribesTypes.clear()
	
func add(tileDict: Dictionary):
	TribesTypes.append(tileDict)

func clearList() -> void:
	for tribe in TribesTypes:
		tribe.troops.clear()
	TribesTypes.clear()

func getList(read_only: bool = false) -> Array:
	if read_only:
		return TribesTypes.duplicate(true)
	return TribesTypes

func getCount() -> int:
	return TribesTypes.size()

func getName(tribeID: int) -> String:
	var i: int = 0
	for troopDict in TribesTypes:
		if i == tribeID:
			return troopDict.name
		i+=1
	return "error"

func getByID(tribeID: int) -> Dictionary:
	var i: int = 0
	for tileDict in TribesTypes:
		if i == tribeID:
			return tileDict
		i+=1
	return InvalidTile

func load_from_file(folder: String, fileSystemObj: Object) -> bool:
	if !fileSystemObj.file_exists(folder + "/" + TRIBES_FILES_NAME):
		return false
	var tribesImportedData: Dictionary = fileSystemObj.get_data_from_json(folder + "/" + TRIBES_FILES_NAME)
	assert(tribesImportedData.has('tribes_types'))
	for troopDict in tribesImportedData['tribes_types']:
		add({
			name = troopDict["name"],
			min_gold = troopDict["min_gold"],
			max_gold = troopDict["max_gold"],
			troops = troopDict["troops"].duplicate(true)
		})
	return true
