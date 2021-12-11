class_name TileGameObject
extends Object

const N: int = 1
const NE: int = 2
const E: int = 4
const SE: int = 8
const S: int = 16
const SW: int = 32
const W: int = 64
const NW: int = 128
const ALL_DIR: int = N | NE | E | SE | S | SW | W | NW # All 8 directions
const DIAG_DIR: int = NE | SE | SW | NW # Diagonal directions only
const HOR_AND_VER_DIR: int = ALL_DIR - DIAG_DIR # Horizontal and vertical directions
const DIRS: Dictionary = { # The keys are vectors 2D, which is awesome and handy
	Vector2(0, -1): N,
	Vector2(1, -1): NE,
	Vector2(1, 0): E,
	Vector2(1, 1): SE,
	Vector2(0, 1): S,
	Vector2(-1, 1): SW,
	Vector2(-1, 0): W,
	Vector2(-1, -1): NW
};

var default_tile: Dictionary = {
	owner = -1,
	name = "untitled",
	turns_to_improve_left = 0, #if > 0, it is upgrading
	tile_id = -1,
	gold = 0,
	turns_to_build = 0, # if > 0, it is building
	building_id = -1, #a tile can only hold one building, so choose carefully!
	troops = [],
	upcomingTroops = [] #array with all the upcoming troops. DATA: turns to wait, owner, troop_id and amount
}

var saved_tiles_data: Array = []
var old_tiles_data: Array = []
var tiles_data: Array = []
var tile_types_obj = null
var troop_types_obj = null
var building_types_obj = null
var tile_size : Vector2 = Vector2.ZERO

func _init(init_tile_size: Vector2, default_tile_id: int, init_tile_types_obj, init_troop_types_obj, init_building_types_obj):
	tile_size = init_tile_size
	tile_types_obj = init_tile_types_obj
	troop_types_obj = init_troop_types_obj
	building_types_obj = init_building_types_obj
	tiles_data = []
	old_tiles_data = []
	default_tile.tile_id = default_tile_id
	for x in range(tile_size.x):
		tiles_data.append([])
		for y in range(tile_size.y):
			tiles_data[x].append(default_tile.duplicate(true))
	
	old_tiles_data = tiles_data.duplicate(true)
################
#	BOOLEANS   #
################

func is_owned_by_player(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner >= 0

func belongs_to_player(tile_pos: Vector2, playerNumber: int) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner == playerNumber

func compare_tile_type_name(tile_pos: Vector2, tile_tyle_name: String) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].tile_id == tile_types_obj.getIDByName(tile_tyle_name)

func is_producing_gold(tile_pos: Vector2,  playerNumber: int) -> bool:
	var civilianCountInTile: int = get_civilian_count(tile_pos, playerNumber)
	var tileTypeDict: Dictionary = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	return civilianCountInTile >= tileTypeDict.min_civil_to_produce_gold && civilianCountInTile <= tileTypeDict.max_civil_to_produce_gold

func has_minimum_civilization(tile_pos: Vector2,  playerNumber: int) -> bool:
	var civilianCountInTile: int = get_civilian_count(tile_pos, playerNumber)
	var tileTypeDict: Dictionary = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	return civilianCountInTile >= tileTypeDict.min_civil_to_produce_gold

func has_troops_or_citizen(tile_pos: Vector2,  playerNumber: int) -> bool:
	var allEntitiesCountInTile: int = get_civilian_count(tile_pos, playerNumber) + get_troops_count(tile_pos, playerNumber)
	return allEntitiesCountInTile > 0

func is_a_valid_tile(cell: Vector2) -> bool:
	if cell.x < 0 or cell.y < 0:
		return false
	if cell.x >= tile_size.x or cell.y >= tile_size.y:
		return false
	return true

func is_next_to_tile(cell: Vector2, to_compare_cell: Vector2) -> bool:
	var neighbors: Array = get_neighbors(cell)
	for v in neighbors:
		if to_compare_cell == v:
			return true
	return false

func is_next_to_any_player_territory(cell: Vector2) -> bool:
	var neighbors: Array = get_neighbors(cell)
	for neighbor in neighbors:
		if tiles_data[neighbor.x][neighbor.y].owner != -1:
			return true 
	return false

func is_next_to_player_territory(cell: Vector2, playerNumber: int) -> bool:
	var neighbors: Array = get_neighbors(cell)
	for neighbor in neighbors:
		if tiles_data[neighbor.x][neighbor.y].owner == playerNumber:
			return true 
	return false

func is_next_to_enemy_territory(cell: Vector2, playerNumber: int) -> bool:
	var neighbors: Array = get_neighbors(cell)
	for neighbor in neighbors:
		if tiles_data[neighbor.x][neighbor.y].owner != playerNumber and tiles_data[neighbor.x][neighbor.y].owner != -1:
			return true 
	return false
	
func is_upgrading(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left > 0

func is_building(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].turns_to_build > 0

func can_be_upgraded(tile_pos: Vector2, playerNumber: int) -> bool:
	if tiles_data[tile_pos.x][tile_pos.y].owner != playerNumber:
		return false
	if is_upgrading(tile_pos):
		return false
	var tileTypeDict = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	if get_total_gold(playerNumber) < tileTypeDict.improve_prize:
		return false
	
	return tile_types_obj.canBeUpgraded(tiles_data[tile_pos.x][tile_pos.y].tile_id)

func is_cell_in_battle(tile_pos: Vector2) -> bool:
	return get_number_of_players_in_cell(tile_pos) > 1

################
#	GETTERS    #
################

func get_total_gold_gain_and_losses(playerNumber: int) -> float:
	var goldGains: float = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			goldGains += get_gold_gain_and_losses(Vector2(x, y), playerNumber)
	
	return goldGains

func get_gold_gain_and_losses(tile_pos: Vector2, playerNumber: int) -> float:
	if tiles_data[tile_pos.x][tile_pos.y].owner != playerNumber: #fixme: calculate battle stuff here later
		return 0.0
	var goldGains: float = 0
	if is_producing_gold(tile_pos, playerNumber):
		goldGains += float(tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id).gold_to_produce)
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		goldGains -= float(troop_types_obj.getByID(troopDict.troop_id).idle_cost_per_turn*troopDict.amount)/1000.0
	return goldGains

func get_troops_count(tile_pos: Vector2, playerNumber: int) -> int:
	var tropsCount: int = 0
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troop_types_obj.getByID(troopDict.troop_id).is_warrior:
			tropsCount+=troopDict.amount

	return tropsCount

func get_civilian_count(tile_pos: Vector2, playerNumber: int) -> int:
	var civilianCount: int = 0
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if !troop_types_obj.getByID(troopDict.troop_id).is_warrior:
			civilianCount+=troopDict.amount

	return civilianCount

func get_player_capital_vec2(playerNumber: int) -> Vector2:
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber and tiles_data[x][y].tile_id == tile_types_obj.getIDByName("capital"):
				return Vector2(x, y)
	return Vector2(-1, -1)

func get_player_tiles_count(playerNumber: int) -> int:
	var count: int = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber:
				count+=1
	return count

func get_total_gold(playerNumber: int) -> float:
	var totalGold: float = 0.0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber:
				totalGold += tiles_data[x][y].gold
	return floor(totalGold)

func get_troop_cell_strength(tilePos: Vector2, playerNumber: int, troop_id: int) -> float:
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.troop_id != troop_id:
			continue
		if troopDict.amount <= 0:
			continue
		var troopHealth: float = troop_types_obj.getByID(troopDict.troop_id).health
		var averageTroopDamage: float = (troop_types_obj.getByID(troopDict.troop_id).damage.x + troop_types_obj.getByID(troopDict.troop_id).damage.y)/2.0
		return (averageTroopDamage*troopDict.amount*troopHealth/200.0)
	return 0.0

func get_strength(tilePos: Vector2, playerNumber: int) -> float:
	var totalStrength: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.amount <= 0:
			continue
		totalStrength += get_troop_cell_strength(tilePos, playerNumber, troopDict.troop_id)

	return round(totalStrength)

func get_total_strength(playerNumber: int) -> float:
	var totalStrength: float = 0.0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			totalStrength+= get_strength(Vector2(x, y), playerNumber)
	
	return totalStrength

func get_civ_population_info(playerNumber: int) -> Array:
	var troopsInfo: Array = []
	var troopExists: bool = false
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			for troopDict in tiles_data[x][y].troops:
				if troopDict.owner != playerNumber:
					continue
				troopExists = false
				for returnTroop in troopsInfo:
					if returnTroop.troop_id == troopDict.troop_id:
						returnTroop.amount += troopDict.amount
						troopExists = true
				if !troopExists:
					troopsInfo.append({troop_id = troopDict.troop_id, amount = troopDict.amount})
	return troopsInfo

func get_number_of_productive_territories(playerNumber: int) -> int:
	var productiveTerritoriesCount: int = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber && has_minimum_civilization(Vector2(x, y), playerNumber):
				productiveTerritoriesCount+=1
	return productiveTerritoriesCount

func get_neighbors(cell: Vector2, bitmask: int = ALL_DIR, mult: int = 1) -> Array:
	var neighbors: Array = []
	for n in DIRS.keys():
		if (bitmask & DIRS[n]) && is_a_valid_tile(cell+n*mult):
			neighbors.append(cell+n*mult)
	return neighbors

func decrease_turns_to_improve(tile_pos: Vector2) -> void:
	tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left -= 1

func get_turns_to_improve(tile_pos: Vector2) -> int:
	return tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left

func get_turns_to_build(tile_pos: Vector2) -> int:
	return tiles_data[tile_pos.x][tile_pos.y].turns_to_build

func decrease_turns_to_build(tile_pos: Vector2) -> void:
	tiles_data[tile_pos.x][tile_pos.y].turns_to_build -= 1

func get_upcoming_troops(tile_pos: Vector2, read_only: bool = false) -> Array:
	if read_only:
		return tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.duplicate(true)
	return tiles_data[tile_pos.x][tile_pos.y].upcomingTroops

func get_size() -> Vector2:
	return tile_size

func get_troops(tile_pos: Vector2, read_only: bool = false) -> Array:
	if read_only:
		return tiles_data[tile_pos.x][tile_pos.y].troops.duplicate(true)
	return tiles_data[tile_pos.x][tile_pos.y].troops

func get_cell(tile_pos: Vector2, read_only: bool = false) -> Dictionary:
	if read_only:
		return tiles_data[tile_pos.x][tile_pos.y].duplicate(true)
	return tiles_data[tile_pos.x][tile_pos.y]

func get_all(read_only: bool = false) -> Array:
	if read_only:
		return tiles_data.duplicate(true)
	return tiles_data

func get_cell_gold(cell: Vector2) -> float:
	return tiles_data[cell.x][cell.y].gold

func get_tile_type_dict(tile_pos: Vector2) -> Dictionary:
	return tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)

func get_all_war_costs(playerNumber: int) -> float:
	var war_costs: float = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber: #Only invasions cost money
				continue
			if is_cell_in_battle(Vector2(x, y)):
				for troopDict in tiles_data[x][y].troops:
					if troopDict.amount <= 0:
						continue
					if troopDict.owner == playerNumber:
						war_costs+= troop_types_obj.getByID(troopDict.troop_id).battle_cost_per_turn*troopDict.amount/1000.0
	return war_costs

func get_number_of_players_in_cell(tile_pos: Vector2) -> int:
	var playersInTileArray: Array = []
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troopDict.amount <= 0:
			continue
		var newPlayerInTile: bool = true
		for playerNumber in playersInTileArray:
			if playerNumber == troopDict.owner:
				newPlayerInTile = false
				break
		if newPlayerInTile:
			playersInTileArray.append(troopDict.owner)
	return playersInTileArray.size()

################
#	SETTERS    #
################

func set_name(tile_pos: Vector2, name: String) -> void:
	tiles_data[tile_pos.x][tile_pos.y].name = name

func set_cell_gold(tile_pos: Vector2, gold: float):
	tiles_data[tile_pos.x][tile_pos.y].gold = gold

func set_troops_amount_in_cell(tile_pos: Vector2, troops_owner: int, troop_id: int, amount: int):
	for troopDict in get_troops(tile_pos):
		if troopDict.owner == troops_owner and troopDict.troop_id == troop_id:
			troopDict.amount = amount
			break
func set_cell_owner(tile_pos: Vector2, playerNumber: int) -> void:
	tiles_data[tile_pos.x][tile_pos.y].owner = playerNumber

##################
#	UTIL & TOOLS #
##################

func delete_cell(tile_pos: Vector2):
	tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.clear()
	tiles_data[tile_pos.x][tile_pos.y].troops.clear()
	tiles_data[tile_pos.x][tile_pos.y] = null

func clear_cell(tile_pos: Vector2):
	tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.clear()
	tiles_data[tile_pos.x][tile_pos.y].troops.clear()
	tiles_data[tile_pos.x][tile_pos.y] = default_tile.duplicate(true)

func clear():
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			delete_cell(Vector2(x, y))
	tiles_data.clear()
	tile_size = Vector2.ZERO

func remove_upcoming_troops_index(tile_pos: Vector2, index: int) -> bool:
	if index < 0 or index >= tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.size():
		return false
	tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.remove(index)
	return true

func remove_troops_index(tile_pos: Vector2, index: int) -> bool:
	if index < 0 or index >= tiles_data[tile_pos.x][tile_pos.y].troops.size():
		return false
	tiles_data[tile_pos.x][tile_pos.y].troops.remove(index)
	return true

func add_troops(tile_pos: Vector2, add_troops: Dictionary) -> void:
	for i in range(tiles_data[tile_pos.x][tile_pos.y].troops.size()):
		if tiles_data[tile_pos.x][tile_pos.y].troops[i].owner == add_troops.owner and tiles_data[tile_pos.x][tile_pos.y].troops[i].troop_id == add_troops.troop_id:
			tiles_data[tile_pos.x][tile_pos.y].troops[i].amount += add_troops.amount
			return
	tiles_data[tile_pos.x][tile_pos.y].troops.append(add_troops)

func append_upcoming_troops(tile_pos: Vector2, troopDict: Dictionary) -> void:
	tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.append(troopDict)

###########################
# SHORTHANDS & GAME LOGIC #
###########################

func add_cell_gold(cell: Vector2, add_gold: float) -> void:
	 tiles_data[cell.x][cell.y].gold += add_gold

func take_cell_gold(cell: Vector2, take_gold: float) -> void:
	 tiles_data[cell.x][cell.y].gold -= take_gold

func give_to_a_player(playerNumber: int, tile_pos: Vector2, tile_type_id: int, add_gold: int, add_troops: Dictionary) -> void:
	tiles_data[tile_pos.x][tile_pos.y].owner = playerNumber
	tiles_data[tile_pos.x][tile_pos.y].gold += add_gold
	tiles_data[tile_pos.x][tile_pos.y].tile_id = tile_type_id
	tiles_data[tile_pos.x][tile_pos.y].name =  "Territorio #" + str(get_player_tiles_count(playerNumber)-1)
	add_troops(tile_pos, add_troops)

func update_gold_stats(tile_pos: Vector2, playerNumber: int) ->  void:
	add_cell_gold(tile_pos, get_gold_gain_and_losses(tile_pos, playerNumber))

func upgrade_tile(cell: Vector2) -> void:
	var tileTypeData = Game.tileTypes.getByID(tiles_data[cell.x][cell.y].tile_id)
	tiles_data[cell.x][cell.y].gold -= tileTypeData.improve_prize
	tiles_data[cell.x][cell.y].turns_to_improve_left = tileTypeData.turns_to_improve

func upgrade_cell(tile_pos: Vector2, playerNumber: int) -> void:
	tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left = 0
	var extra_population: Dictionary = {
		owner = playerNumber,
		troop_id = troop_types_obj.getIDByName("civil"),
		amount = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id).min_civil_to_produce_gold
	}
	var nextStageTileTypeId: int = tile_types_obj.getNextStageID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	tiles_data[tile_pos.x][tile_pos.y].tile_id = nextStageTileTypeId
	add_troops(tile_pos, extra_population)

func buy_building(tile_pos: Vector2, var buildTypeId: int):
	var currentBuildingTypeSelected = building_types_obj.getByID(buildTypeId)
	tiles_data[tile_pos.x][tile_pos.y].gold -= currentBuildingTypeSelected.buy_prize
	tiles_data[tile_pos.x][tile_pos.y].turns_to_build = currentBuildingTypeSelected.turns_to_build
	tiles_data[tile_pos.x][tile_pos.y].building_id = buildTypeId

#################
# NETCODE STUFF #
#################

func arrays_contents_are_equal(arrayA: Array, arrayB: Array) -> bool:
	var arrayASize: int = arrayA.size()
	var arrayBSize: int = arrayB.size()
	if arrayASize != arrayBSize:
		return false
	for i in range(arrayASize):
		if typeof(arrayA[i]) != typeof(arrayA[i]):
			return false
		if typeof(arrayA[i]) == TYPE_DICTIONARY:
			if dicts_are_equal(arrayA[i], arrayB[i]):
				continue
			else:
				return false
		if typeof(arrayA[i]) == TYPE_ARRAY:
			if arrays_contents_are_equal(arrayA[i], arrayB[i]):
				continue
			else:
				return false
		if arrayA[i] != arrayB[i]:
			return false
	return true

func dicts_are_equal(dictA: Dictionary, dictB: Dictionary) -> bool:
	for key in dictA:
		if !dictB.has(key):
			return false
		if typeof(dictA[key]) != typeof(dictB[key]):
			return false
		if  typeof(dictA[key]) == TYPE_DICTIONARY:
			if dicts_are_equal(dictA[key], dictB[key]):
				continue
			else:
				return false
		if  typeof(dictA[key]) == TYPE_ARRAY:
			if arrays_contents_are_equal(dictA[key], dictB[key]):
				continue
			else:
				return false
		if dictB[key] != dictA[key]:
			return false
			
	for key in dictB:
		if !dictA.has(key):
			return false
		if typeof(dictA[key]) != typeof(dictB[key]):
			return false
		if  typeof(dictA[key]) == TYPE_DICTIONARY:
			if dicts_are_equal(dictA[key], dictB[key]):
				continue
			else:
				return false
		if  typeof(dictA[key]) == TYPE_ARRAY:
			if arrays_contents_are_equal(dictA[key], dictB[key]):
				continue
			else:
				return false
		if dictB[key] != dictA[key]:
			return false

	return true; #they are totally equal

func set_sync_cell_data(cell: Vector2, cell_data: Dictionary) -> void:
	tiles_data[cell.x][cell.y].troops.clear()
	tiles_data[cell.x][cell.y].upcomingTroops.clear()
	tiles_data[cell.x][cell.y] = cell_data.duplicate(true)

func save_sync_data() -> void:
	saved_tiles_data = tiles_data.duplicate( true )

func recover_sync_data() -> void:
	old_tiles_data = saved_tiles_data.duplicate( true )

func update_sync_data() -> void:
	old_tiles_data = tiles_data.duplicate( true )

func get_sync_data() -> Array: #FIXME: Optimize (try to use delta data changes)
	var cellsToSync: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == -1 and !is_next_to_any_player_territory(Vector2(x, y)):
				continue
			if old_tiles_data.size() <= x or old_tiles_data[x].size() <= y:
				continue
			if !dicts_are_equal(tiles_data[x][y], old_tiles_data[x][y]):
				cellsToSync.append({ cell_pos = Vector2(x, y), cell_data = tiles_data[x][y].duplicate( true ) })
	print( "get_sync_data" + str(cellsToSync.size()) )
	old_tiles_data = tiles_data.duplicate( true )
	
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if old_tiles_data[x][y].owner == -1 and !is_next_to_any_player_territory(Vector2(x, y)):
				old_tiles_data[x][y].owner = -2 #shitty hack to ensure sync in future
	return cellsToSync

func get_sync_neighbors (playerNumber: int) -> Array:
	var cellsToSync: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner != playerNumber and is_next_to_player_territory(Vector2(x, y), playerNumber):
				cellsToSync.append({ cell_pos = Vector2(x, y), cell_data = tiles_data[x][y].duplicate( true ) })
	print( "get_sync_neighbors" + str(cellsToSync.size()) )
	return cellsToSync

func merge_sync_arrays(oldSyncArray: Array, newSyncArray: Array) -> Array:
	for i in range(newSyncArray.size()):
		var exists: bool = false
		for j in range(oldSyncArray.size()):
			if newSyncArray[i].cell_pos == oldSyncArray[j].cell_pos: #already exists, replace for new one
				exists = true
				oldSyncArray[j].clear()
				oldSyncArray[j] = newSyncArray[i].duplicate(true)
				break
		if !exists:
			oldSyncArray.append(newSyncArray[i].duplicate(true))
	
	return oldSyncArray
		
func set_sync_data( dictArray: Array ) -> void:
	for cellData in dictArray:
		var cell: Vector2 = cellData.cell_pos
		var cell_info = cellData.cell_data
		set_sync_cell_data(cell, cell_info)
