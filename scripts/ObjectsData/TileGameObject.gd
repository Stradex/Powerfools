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
var previous_action_tiles_data: Array = []
var old_tiles_data: Array = []
var tiles_data: Array = []
var tile_types_obj = null
var troop_types_obj = null
var building_types_obj = null
var tile_size : Vector2 = Vector2.ZERO
var rng: RandomNumberGenerator

func _init(init_tile_size: Vector2, default_tile_id: int, init_tile_types_obj, init_troop_types_obj, init_building_types_obj, init_rng):
	rng = init_rng
	tile_size = init_tile_size
	tile_types_obj = init_tile_types_obj
	troop_types_obj = init_troop_types_obj
	building_types_obj = init_building_types_obj
	tiles_data = []
	previous_action_tiles_data = []
	old_tiles_data = []
	default_tile.tile_id = default_tile_id
	for x in range(tile_size.x):
		tiles_data.append([])
		for y in range(tile_size.y):
			tiles_data[x].append(default_tile.duplicate(true))
	
	previous_action_tiles_data = tiles_data.duplicate(true)
	old_tiles_data = tiles_data.duplicate(true)
################
#	BOOLEANS   #
################

func player_has_troops_in_cell(tile_pos: Vector2, playerNumber: int) -> bool:
	for troop in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troop.owner == playerNumber:
			return true
	return false

func is_owned_by_player(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner >= 0

func belongs_to_player(tile_pos: Vector2, playerNumber: int) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner == playerNumber

func compare_tile_type_name(tile_pos: Vector2, tile_tyle_name: String) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].tile_id == tile_types_obj.getIDByName(tile_tyle_name)

func is_producing_gold(tile_pos: Vector2,  playerNumber: int) -> bool:
	var civilianCountInTile: int = get_civilian_count(tile_pos, playerNumber)
	var tileTypeDict: Dictionary = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	return civilianCountInTile >= tileTypeDict.min_civil_to_produce_gold and civilianCountInTile <= tileTypeDict.max_civil_to_produce_gold and tileTypeDict.gold_to_produce > 0

func has_minimum_civilization(tile_pos: Vector2,  playerNumber: int) -> bool:
	var civilianCountInTile: int = get_civilian_count(tile_pos, playerNumber)
	var tileTypeDict: Dictionary = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	return civilianCountInTile >= tileTypeDict.min_civil_to_produce_gold

func has_troops_or_citizen(tile_pos: Vector2,  playerNumber: int) -> bool:
	var allEntitiesCountInTile: int = get_civilian_count(tile_pos, playerNumber) + get_warriors_count(tile_pos, playerNumber)
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

func get_all_buildings(playerNumber: int) -> Array:
	var cells_with_builidngs: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber and tiles_data[x][y].building_id != -1:
				cells_with_builidngs.append(Vector2(x, y))
	return cells_with_builidngs

func can_be_upgraded(tile_pos: Vector2, playerNumber: int) -> bool:
	if tiles_data[tile_pos.x][tile_pos.y].owner != playerNumber:
		return false
	if is_upgrading(tile_pos):
		return false
	var tileTypeDict = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	if get_total_gold(playerNumber) < tileTypeDict.improve_prize:
		return false
	
	return tile_types_obj.canBeUpgraded(tiles_data[tile_pos.x][tile_pos.y].tile_id)

func gold_needed_to_upgrade(tile_pos: Vector2) -> float:
	var tileTypeDict = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	return tileTypeDict.improve_prize

func is_cell_in_battle(tile_pos: Vector2) -> bool:
	return get_number_of_players_in_cell(tile_pos) > 1

func can_buy_building_at_cell(tile_pos: Vector2, buildTypeId: int, goldAvailable: int, playerNumber: int):
	if tiles_data[tile_pos.x][tile_pos.y].building_id == buildTypeId:
		return false
	var currentBuildingTypeSelected = building_types_obj.getByID(buildTypeId)
	if goldAvailable < currentBuildingTypeSelected.buy_prize:
		return false
	if currentBuildingTypeSelected.max_amount > 0 and get_amount_of_buildings(buildTypeId, playerNumber) >= currentBuildingTypeSelected.max_amount:
		return false
	return true

################
#	GETTERS    #
################

func get_owner(cell: Vector2) -> int:
	return tiles_data[cell.x][cell.y].owner

func get_total_gold_gain_and_losses(playerNumber: int) -> float:
	var goldGains: float = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			goldGains += get_cell_gold_gain_and_losses(Vector2(x, y), playerNumber)
	goldGains-= get_all_war_costs(playerNumber)
	return goldGains 

func get_cell_gold_gain_and_losses(tile_pos: Vector2, playerNumber: int) -> float:
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

func get_all_warriors_count(playerNumber: int) -> int:
	var cells_with_warriors: Array = get_all_tiles_with_warriors_from_player(playerNumber)
	var warriors_count: int = 0
	for cell in cells_with_warriors:
		warriors_count+= get_warriors_count(cell, playerNumber)
	return warriors_count
func get_warriors_count(tile_pos: Vector2, playerNumber: int) -> int:
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

func get_all_player_tiles(playerNumber: int) -> Array:
	var player_cells: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber:
				player_cells.append(Vector2(x, y))
	return player_cells

func get_all_tiles_with_warriors_from_player(player_number: int) -> Array:
	var player_cells: Array = get_all_player_tiles(player_number)
	var troops_cells: Array = []
	for cell in player_cells:
		if get_warriors_count(cell, player_number) > 0:
			troops_cells.append(cell)
	return troops_cells

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

func get_cells_in_battle() -> Array:
	var cells_in_battle: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if is_cell_in_battle(Vector2(x, y)):
				cells_in_battle.append(Vector2(x, y))
	return cells_in_battle

func get_cells_in_battle_with_enemies(playerNumber: int) -> Array:
	var cells_in_battle: Array = get_cells_in_battle()
	var cells_in_battle_with_enemies: Array = []
	for cell in cells_in_battle:
		if player_has_troops_in_cell(cell, playerNumber):
			cells_in_battle_with_enemies.append(cell)
	return cells_in_battle_with_enemies

func get_cells_invaded_by_enemies(playerNumber: int) -> Array:
	var cells_in_battle: Array = get_cells_in_battle()
	var cells_invaded_by_enemies: Array = []
	for cell in cells_in_battle:
		if belongs_to_player(cell, playerNumber):
			cells_invaded_by_enemies.append(cell)
	return cells_invaded_by_enemies

func is_player_being_attacked(playerNumber: int) -> bool:
	return get_cells_invaded_by_enemies(playerNumber).size() > 0

func is_player_having_battles(playerNumber: int) -> bool:
	return get_cells_in_battle_with_enemies(playerNumber).size() > 0

func get_own_troops_damage(tilePos: Vector2, playerNumber: int) -> float:
	var allies_total_damage: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.amount <= 0:
			continue
		var averageTroopDamage: float = (troop_types_obj.getByID(troopDict.troop_id).damage.x + troop_types_obj.getByID(troopDict.troop_id).damage.y)/2.0
		allies_total_damage += troopDict.amount*averageTroopDamage
	return allies_total_damage

func get_own_troops_health(tilePos: Vector2, playerNumber: int) -> float:
	var allies_total_health: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.amount <= 0:
			continue
		var troopHealth: float = troop_types_obj.getByID(troopDict.troop_id).health
		allies_total_health += troopDict.amount*troopHealth
	return allies_total_health

func get_enemies_troops_damage(tilePos: Vector2, playerNumber: int) -> float:
	var enemies_total_damage: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner == playerNumber:
			continue
		if troopDict.amount <= 0:
			continue
		var averageTroopDamage: float = (troop_types_obj.getByID(troopDict.troop_id).damage.x + troop_types_obj.getByID(troopDict.troop_id).damage.y)/2.0
		enemies_total_damage += troopDict.amount*averageTroopDamage
	return enemies_total_damage

func get_enemies_troops_health(tilePos: Vector2, playerNumber: int) -> float:
	var enemies_total_health: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner == playerNumber:
			continue
		if troopDict.amount <= 0:
			continue
		var troopHealth: float = troop_types_obj.getByID(troopDict.troop_id).health
		enemies_total_health += troopDict.amount*troopHealth
	return enemies_total_health

func get_troop_cell_damage(tilePos: Vector2, playerNumber: int, troop_id: int) -> float:
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.troop_id != troop_id:
			continue
		if troopDict.amount <= 0:
			continue
		var averageTroopDamage: float = (troop_types_obj.getByID(troopDict.troop_id).damage.x + troop_types_obj.getByID(troopDict.troop_id).damage.y)/2.0
		return troopDict.amount*averageTroopDamage
	return 0.0

func get_troop_cell_health(tilePos: Vector2, playerNumber: int, troop_id: int) -> float:
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.troop_id != troop_id:
			continue
		if troopDict.amount <= 0:
			continue
		var troopHealth: float = troop_types_obj.getByID(troopDict.troop_id).health
		return troopDict.amount*troopHealth
	return 0.0

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
		return ((averageTroopDamage+troopHealth)*troopDict.amount/200.0)
	return 0.0

func get_warriors_strength(tilePos: Vector2, playerNumber: int) -> float:
	var totalStrength: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.amount <= 0:
			continue
		if !troop_types_obj.getByID(troopDict.troop_id).is_warrior:
			continue
		totalStrength += get_troop_cell_strength(tilePos, playerNumber, troopDict.troop_id)

	return round(totalStrength)
	
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

func get_total_warriors_strength(playerNumber: int) -> float:
	var totalStrength: float = 0.0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			totalStrength+= get_warriors_strength(Vector2(x, y), playerNumber)
	
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

func set_all(new_tiles_data: Array, new_tile_size: Vector2) -> void:
	clear()
	tiles_data = new_tiles_data.duplicate(true)
	tile_size = new_tile_size

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

################
#	GETTERS    #
################
func get_name(tile_pos: Vector2) -> String:
	return tiles_data[tile_pos.x][tile_pos.y].name

func get_amount_of_buildings(building_id: int, playerNumber: int) -> int:
	var count: int = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber and tiles_data[x][y].building_id == building_id:
				count+=1
	return count
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
	add_cell_gold(tile_pos, get_cell_gold_gain_and_losses(tile_pos, playerNumber))

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

func save_tiles_data() ->void:
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			previous_action_tiles_data[x][y].troops.clear()
			previous_action_tiles_data[x][y].upcomingTroops.clear()
			previous_action_tiles_data[x][y].clear()
	
	previous_action_tiles_data.clear()
	previous_action_tiles_data = tiles_data.duplicate(true)

func restore_previous_tiles_data() ->void:
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			tiles_data[x][y].troops.clear()
			tiles_data[x][y].upcomingTroops.clear()
			tiles_data[x][y].clear()
	tiles_data.clear()
	tiles_data = previous_action_tiles_data.duplicate(true)
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

func get_sync_data(playerNumber: int = -1) -> Array: #if playerNumber != -1 then only sync ties from that player, useful for secure changes
	var cellsToSync: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if playerNumber != -1 and tiles_data[x][y].owner != playerNumber:
				continue
			if tiles_data[x][y].owner == -1 and !is_next_to_any_player_territory(Vector2(x, y)):
				continue
			if old_tiles_data.size() <= x or old_tiles_data[x].size() <= y:
				continue
			if !dicts_are_equal(tiles_data[x][y], old_tiles_data[x][y]):
				cellsToSync.append({ cell_pos = Vector2(x, y), cell_data = tiles_data[x][y].duplicate( true ) })
	print( "get_sync_data: " + str(cellsToSync.size()) )
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
	print( "get_sync_neighbors: " + str(cellsToSync.size()) )
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

#################
# AI HELP STUFF #
#################

func ai_get_cells_not_being_productive(player_number: int) -> Array:
	var unproductive_territories_array: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == player_number && !is_producing_gold(Vector2(x, y), player_number):
				unproductive_territories_array.append(Vector2(x, y))
	return unproductive_territories_array

func ai_get_neighbors_by_distance(cell: Vector2, distance: int, mask: int = ALL_DIR) -> Array:
	if distance < 1:
		distance = 1
	var return_array: Array = [cell]
	var array_to_substract: Array = []
	for i in range(distance):
		var data_to_apend: Array = []
		for j in range(return_array.size()):
			if array_to_substract.find(return_array[j]) != -1:
				continue
			var neighbors: Array = get_neighbors(return_array[j], mask)
			for neighbor in neighbors:
				data_to_apend.append(neighbor)
		array_to_substract = return_array.duplicate(true)
		for j in range(data_to_apend.size()):
			if return_array.find(data_to_apend[j]) != -1:
				continue
			return_array.append(data_to_apend[j])
	#Substract to keep only the cells at distance
	for i in range (array_to_substract.size()):
		var index_to_remove: int = return_array.find(array_to_substract[i])
		if index_to_remove >= 0:
			return_array.remove(index_to_remove)
	return return_array

func ai_get_free_cells() -> Array:
	var cells_available: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner != -1 or is_next_to_any_player_territory(Vector2(x, y)):
				continue
			cells_available.append(Vector2(x, y))
	return cells_available

func ai_pick_random_free_cell() -> Vector2:
	var free_cells: Array = ai_get_free_cells()
	return free_cells[rng.randi_range(0, free_cells.size()-1)]

func ai_get_closest_free_cell_to(cell: Vector2) -> Array:
	var distance: int = 1
	var free_neighbors: Array = []
	while free_neighbors.size() <= 0:
		var neighbors: Array = ai_get_neighbors_by_distance(cell, distance)
		for neighbor in neighbors:
			if tiles_data[neighbor.x][neighbor.y].owner == -1:
				free_neighbors.append(neighbor)
		distance+=1

	return free_neighbors

func ai_get_closest_available_to_buy_free_cell_to(cell: Vector2, player_number: int) -> Array:
	var distance: int = 1
	var free_neighbors: Array = []
	while free_neighbors.size() <= 0:
		var neighbors: Array = ai_get_neighbors_by_distance(cell, distance)
		for neighbor in neighbors:
			if tiles_data[neighbor.x][neighbor.y].owner == -1 and !is_next_to_enemy_territory(neighbor, player_number):
				free_neighbors.append(neighbor)
		distance+=1

	return free_neighbors

func ai_get_farthest_player_cell_from(cell: Vector2, player_number: int) -> Array:
	var distance: int = 1
	var farthest_cells: Array = [cell]
	var tmp_farthest_cells: Array = [cell]
	while tmp_farthest_cells.size() > 0:
		farthest_cells = tmp_farthest_cells.duplicate(true)
		tmp_farthest_cells.clear()
		var neighbors: Array = ai_get_neighbors_by_distance(cell, distance)
		for neighbor in neighbors:
			if tiles_data[neighbor.x][neighbor.y].owner == player_number:
				tmp_farthest_cells.append(neighbor)
		distance+=1
	
	return farthest_cells

func ai_get_reachable_enemy_cells(player_number: int) -> Array:
	var player_cells: Array = get_all_player_tiles(player_number)
	var enemy_cells: Array = []
	for cell in player_cells:
		var neighbors: Array = get_neighbors(cell)
		for neighbor in neighbors:
			if tiles_data[neighbor.x][neighbor.y].owner != player_number:
				if enemy_cells.find(neighbor) == -1: #avoid duplicated
					enemy_cells.append(neighbor)
	return enemy_cells

func ai_have_strength_to_conquer(cell_to_conquer: Vector2, player_number: int) -> bool:
	var cell_owner: int = tiles_data[cell_to_conquer.x][cell_to_conquer.y].owner
	var enemy_cell_strength: float = get_strength(cell_to_conquer, cell_owner)
	return get_total_warriors_strength(player_number) > enemy_cell_strength

func ai_get_weakest_enemy_cell(player_number: int) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_enemy_cells(player_number)
	var weakest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if weakest_cell == Vector2(-1, -1):
			weakest_cell = cell
			continue
		var cell_owner: int = tiles_data[cell.x][cell.y].owner
		var weakest_cell_owner: int = tiles_data[weakest_cell.x][weakest_cell.y].owner
		if get_strength(cell, cell_owner) < get_strength(weakest_cell, weakest_cell_owner):
			weakest_cell = cell
			#print(get_strength(cell, cell_owner))
	return weakest_cell

func ai_get_closest_troop_force_pos_to(enemy_cell_pos: Vector2, player_number: int) -> Vector2:
	var cells_with_troops: Array = get_all_tiles_with_warriors_from_player(player_number)
	var cells_to_use: Array = []
	#Remove tiles that are in battle
	for cell in cells_with_troops:
		if !is_cell_in_battle(cell):
			cells_to_use.append(cell)

	if cells_to_use.size() > 0:
		return ai_get_closest_cell_to_from_array(cells_to_use, enemy_cell_pos, player_number)
	return Vector2(-1, -1)

func ai_get_richest_enemy_cell(player_number: int) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_enemy_cells(player_number)
	var richest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if richest_cell == Vector2(-1, -1):
			richest_cell = cell
			continue
		if get_cell_gold(cell) > get_cell_gold(richest_cell):
			richest_cell = cell
			#print(get_strength(cell, cell_owner))
	return richest_cell

func ai_get_closest_cell_to_from_array(array_of_cells: Array, cell_pos: Vector2, player_number: int) -> Vector2:
	var closest_index: int = 0
	for i in range(array_of_cells.size()):
		if cell_pos.distance_squared_to(array_of_cells[i]) < cell_pos.distance_squared_to(array_of_cells[closest_index]):
			closest_index = i
	return array_of_cells[closest_index]
	
func ai_get_path_to_from(start_pos: Vector2, end_pos: Vector2, player_number: int) -> Array:
	# step 1 get neighbors from start_pos, then select the ones closest to end_pos
	var path_completed: bool = false
	var path_array: Array = [start_pos]
	var neighbors: Array = []
	while !path_completed:
		neighbors = get_neighbors(path_array[path_array.size()-1])
		path_array.append(ai_get_closest_cell_to_from_array(neighbors, end_pos, player_number))
		if path_array.find(end_pos) != -1:
			path_completed = true
	return path_array

func ai_move_all_warriors_from_to(start_pos: Vector2, end_pos: Vector2, player_number: int) -> void:
	var startTroopsArray: Array = tiles_data[start_pos.x][start_pos.y].troops
	var endTroopsArray: Array = tiles_data[end_pos.x][end_pos.y].troops
	for troopDict in startTroopsArray:
		if troopDict.owner != player_number:
			continue
		if troopDict.amount <= 0:
			continue
		if !troop_types_obj.getByID(troopDict.troop_id).is_warrior:
			continue
		add_troops(end_pos, {
			owner = player_number,
			troop_id = troopDict.troop_id,
			amount = troopDict.amount
		})
		troopDict.amount = 0

func ai_get_all_cells_without_buildings(playerNumber: int) -> Array:
	var cells_with_builidngs: Array = get_all_buildings(playerNumber)
	var bot_tiles: Array = get_all_player_tiles(playerNumber)
	var cells_without_buildings: Array = []
	
	for cell in cells_with_builidngs:
		var to_remove_index: int = bot_tiles.find(cell)
		if to_remove_index != -1:
			bot_tiles.remove(to_remove_index)
	return bot_tiles

func ai_get_all_cells_available_to_recruit(playerNumber: int) -> Array:
	var cells_with_builidngs: Array = get_all_buildings(playerNumber)
	var cells_that_can_recruit: Array = []
	for cell in cells_with_builidngs:
		if tiles_data[cell.x][cell.y].turns_to_build <= 0 and get_upcoming_troops(cell).size() <= 0:
			cells_that_can_recruit.append(cell)
	return cells_that_can_recruit

func ai_all_cells_being_attacked(playerNumber: int) -> Array:
	var all_player_cells: Array = get_all_player_tiles(playerNumber)
	var cells_in_battle: Array = []
	for cell in all_player_cells:
		if is_cell_in_battle(cell):
			cells_in_battle.append(cell)
	return cells_in_battle

func ai_is_being_attacked(playerNumber: int) -> bool:
	return ai_all_cells_being_attacked(playerNumber).size() > 0
