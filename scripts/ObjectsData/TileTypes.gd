class_name TilesTypesObject
extends Object

var TilesTypes: Array
const TILES_FILES_NAME: String = "tiles.json"

var InvalidTile: Dictionary = {
	name = "invalid",
	next_stage = "none", #leave it blank if this tile cannot be improved
	improve_prize = 0,
	turns_to_improve = 0,
	gold_to_produce = 0, #ammount of gold to produce per turn
	strength_boost = 0, #ammount of extra damage in % that the owner of this tile gets in their troops
	sell_prize = 0, #ammount of gold to receive in case of this sold
	conquer_gain = 0, #ammount of gold to receive in case of conquering this land
	tile_img = 'tile_empty', #image name of the tile (look at tileResources)
	min_civil_to_produce_gold = 0, #minimum amount of civilians to produce gold
	max_civil_to_produce_gold = 0, #maximum amount of civilians to produce gold
	extra_actions_to_give = 0.0, #extra actions to give per territory
	tile_imgs = [] #array with 'civ_name' and 'imgs' array of images to use
}

func _init():
	pass

func clearList() -> void:
	TilesTypes.clear()

func add(tileDict: Dictionary):
	TilesTypes.append(tileDict)

func canBeSold(tileTypeID: int) -> bool:
	return getByID(tileTypeID).sell_prize > 0
	
func canBeUpgraded(tileTypeID: int) -> bool:
	return getByID(tileTypeID).next_stage.length() > 1

func getByName(tileTypeName: String) -> Dictionary:
	for tileDict in TilesTypes:
		if tileDict.name.to_lower() == tileTypeName.to_lower():
			return tileDict
	return InvalidTile

func getIDByName(tileTypeName: String) -> int:
	var i: int = 0
	for tileDict in TilesTypes:
		if tileDict.name.to_lower() == tileTypeName.to_lower():
			return i
		i+=1
	return -1

func getNextStageID(tileTypeID: int) -> int:
	var i: int = 0
	for tileDict in TilesTypes:
		if i == tileTypeID:
			return getIDByName(tileDict.next_stage)
		i+=1
	return -1

func getByID(tileTypeID: int) -> Dictionary:
	var i: int = 0
	for tileDict in TilesTypes:
		if i == tileTypeID:
			return tileDict
		i+=1
	return InvalidTile

func getImg(tileTypeID: int, civilization_id: int) -> String:
	var tileDict: Dictionary = getByID(tileTypeID)
	for imgDict in tileDict.tile_imgs:
		if imgDict.civ_id == civilization_id:
			return imgDict.imgs[0] #FIXME: allow variations later
	return tileDict.tile_imgs[0].imgs[0] #_default... I guess?

func getList() -> Array:
	return TilesTypes.duplicate(true) #gives a copy so no one can fuck up the original list

func load_from_file(folder: String, fileSystemObj: Object, civ_types_object) -> bool:
	if !fileSystemObj.file_exists(folder + "/" + TILES_FILES_NAME):
		return false
	var tilesImportedData: Dictionary = fileSystemObj.get_data_from_json(folder + "/" + TILES_FILES_NAME)
	assert(tilesImportedData.has('tiles'))
	for troopDict in tilesImportedData['tiles']:
		var tile_imgs_array: Array = []
		for imgsDict in troopDict["tile_imgs"]:
			tile_imgs_array.append({
				civ_id = civ_types_object.getIDByName(imgsDict["civ_name"]),
				imgs = imgsDict["imgs"]
			})
		add({
			name = troopDict["name"],
			next_stage = troopDict["next_stage"],
			improve_prize = troopDict["improve_prize"],
			turns_to_improve = troopDict["turns_to_improve"],
			gold_to_produce = troopDict["gold_to_produce"],
			sell_prize = troopDict["sell_prize"],
			conquer_gain = troopDict["conquer_gain"],
			tile_img = troopDict["tile_img"],
			min_civil_to_produce_gold = troopDict["min_civil_to_produce_gold"],
			max_civil_to_produce_gold = troopDict["max_civil_to_produce_gold"],
			extra_actions_to_give = troopDict["extra_actions_to_give"],
			tile_imgs = tile_imgs_array.duplicate(true)
		})
	return true
