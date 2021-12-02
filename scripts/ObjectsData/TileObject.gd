class_name TilesTypesObject
extends Object

var TilesTypes: Array

var InvalidTile: Dictionary = {
	name = "invalid",
	next_stage = "none", #leave it blank if this tile cannot be improved
	improve_prize = 0,
	turns_to_improve = 0,
	gold_to_produce = 0, #ammount of gold to produce per turn
	strength_boost = 0, #ammount of extra damage in % that the owner of this tile gets in their troops
	sell_prize = 0, #ammount of gold to receive in case of this sold
	conquer_gain = 0, #ammount of gold to receive in case of conquering this land
	tile_img = 'tile_empty' #image name of the tile (look at tileResources)
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

func getByID(tileTypeID: int) -> Dictionary:
	var i: int = 0
	for tileDict in TilesTypes:
		if i == tileTypeID:
			return tileDict
		i+=1
	return InvalidTile

func getImg(tileTypeID: int) -> String:
	return getByID(tileTypeID).tile_img
