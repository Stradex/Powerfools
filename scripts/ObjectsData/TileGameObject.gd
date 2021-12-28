class_name TileGameObject
extends Object

const ROCK_OWNER_ID: int = -3 #if owner == -3, then it is a rock and no player/bot should be allowed to move troops or build or anything here


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
const MAX_ITERATIONS_ALLOWED: int = 15000 #max iterations allowed
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
	upcomingTroops = [], #array with all the upcoming troops. DATA: turns to wait, owner, troop_id and amount
	type_of_rock = -1,
	tribe_owner = -1, #in case this tile is owned by a tribal society, this holds he ID of the tribal society who owns it (to get the name)
}

var alphabet: Array = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "N", "Ñ", "O", "P", "Q", "R", "S", "T", "V", "W", "X", "Y", "Z"]

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

func cell_has_building(cell: Vector2) -> bool:
	return tiles_data[cell.x][cell.y].building_id != -1

func get_all_tile_coords() -> Dictionary:
	var tile_coords: Array = []
	for x in range(tile_size.x):
		tile_coords.append([])
		for y in range(tile_size.y):
			tile_coords[x].append(str(alphabet[x] + str(y+1)))
	return {coords_size = tile_size, coords = tile_coords }

func cell_has_better_building_than(cellA: Vector2, cellB: Vector2) -> bool:
	var cell_a_data: Dictionary = tiles_data[cellA.x][cellA.y]
	var cell_b_data: Dictionary = tiles_data[cellB.x][cellB.y]
	if cell_a_data.building_id == -1:
		return false
	if cell_b_data.building_id == -1:
		return true
	return building_types_obj.getByID(cell_a_data.building_id).buy_prize > building_types_obj.getByID(cell_b_data.building_id).buy_prize

func is_capital(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].tile_id == tile_types_obj.getIDByName("capital")

func is_tile_owned_by_tribal_society(tile_pos: Vector2) -> bool:
	if !is_tile_walkeable(tile_pos):
		return false
	return tiles_data[tile_pos.x][tile_pos.y].owner == -1

func player_has_troops_in_cell(tile_pos: Vector2, playerNumber: int) -> bool:
	for troop in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troop.owner == playerNumber:
			return true
	return false

func get_all_capitals() -> Array:
	var capitals_cells: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].tile_id == tile_types_obj.getIDByName("capital"):
				capitals_cells.append(Vector2(x, y))
	return capitals_cells

func is_tile_walkeable(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner != ROCK_OWNER_ID

func is_owned_by_any_player(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner >= 0

func belongs_to_player(tile_pos: Vector2, playerNumber: int) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner == playerNumber

func belongs_to_allies(tile_pos: Vector2, playerNumber: int) -> bool:
	return Game.are_player_allies(tiles_data[tile_pos.x][tile_pos.y].owner, playerNumber)

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
	var neighbors: Array = get_walkeable_neighbors(cell)
	for neighbor in neighbors:
		if tiles_data[neighbor.x][neighbor.y].owner != -1:
			return true 
	return false

func is_next_to_player_territory(cell: Vector2, playerNumber: int) -> bool:
	var neighbors: Array = get_walkeable_neighbors(cell)
	for neighbor in neighbors:
		if tiles_data[neighbor.x][neighbor.y].owner == playerNumber:
			return true 
	return false

func is_next_to_allies_territory(cell: Vector2, playerNumber: int) -> bool:
	var neighbors: Array = get_walkeable_neighbors(cell)
	for neighbor in neighbors:
		if Game.are_player_allies(tiles_data[neighbor.x][neighbor.y].owner, playerNumber):
			return true 
	return false

func is_next_to_allies_territory_with_own_troops(cell: Vector2, playerNumber: int) -> bool:
	var neighbors: Array = get_walkeable_neighbors(cell)
	for neighbor in neighbors:
		if Game.are_player_allies(tiles_data[neighbor.x][neighbor.y].owner, playerNumber) and player_has_troops_in_cell(neighbor, playerNumber):
			return true 
	return false

func is_next_to_player_enemy_territory(cell: Vector2, playerNumber: int) -> bool:
	var neighbors: Array = get_walkeable_neighbors(cell)
	for neighbor in neighbors:
		if tiles_data[neighbor.x][neighbor.y].owner != playerNumber and tiles_data[neighbor.x][neighbor.y].owner != -1 and !Game.are_player_allies(playerNumber, tiles_data[neighbor.x][neighbor.y].owner):
			return true 
	return false

func is_next_to_enemy_territory(cell: Vector2, playerNumber: int) -> bool:
	var neighbors: Array = get_walkeable_neighbors(cell)
	for neighbor in neighbors:
		if tiles_data[neighbor.x][neighbor.y].owner != playerNumber and !Game.are_player_allies(playerNumber, tiles_data[neighbor.x][neighbor.y].owner):
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
	var players_in_cell: Array = get_players_in_cell(tile_pos)
	for playerA in players_in_cell:
		for playerB in players_in_cell:
			if !Game.are_player_allies(playerA, playerB):
				return true
	return false

func get_strongest_player_in_cell(tile_pos: Vector2) -> int:
	var players_in_cell: Array = get_players_in_cell(tile_pos)
	var strongest_player: int = -1
	for player in players_in_cell:
		if strongest_player == -1:
			strongest_player = player
			continue
		if get_strength(tile_pos, player) > get_strength(tile_pos, strongest_player):
			strongest_player = player
		
	return strongest_player


func is_player_being_attacked(playerNumber: int) -> bool:
	return get_cells_invaded_by_enemies(playerNumber).size() > 0

func is_player_having_battles(playerNumber: int) -> bool:
	return get_cells_in_battle_with_enemies(playerNumber).size() > 0

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

func get_name(tile_pos: Vector2) -> String:
	return tiles_data[tile_pos.x][tile_pos.y].name

func get_amount_of_buildings(building_id: int, playerNumber: int) -> int:
	var count: int = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber and tiles_data[x][y].building_id == building_id:
				count+=1
	return count

func get_owner(cell: Vector2) -> int:
	return tiles_data[cell.x][cell.y].owner

func get_all_buildings(playerNumber: int) -> Array:
	var cells_with_builidngs: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber and tiles_data[x][y].building_id != -1:
				cells_with_builidngs.append(Vector2(x, y))
	return cells_with_builidngs

func get_count_of_all_buildings_player_have(playerNumber: int) -> int:
	return get_all_buildings(playerNumber).size()

func get_all_walkeable_tiles() -> Array:
	var walkeable_cells: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if is_tile_walkeable(Vector2(x, y)):
				walkeable_cells.append(Vector2(x, y))
	return walkeable_cells

func get_total_gold_gain_and_losses(playerNumber: int) -> float:
	var goldGains: float = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			goldGains += get_cell_gold_gain_and_losses(Vector2(x, y), playerNumber)
	goldGains-= get_all_war_costs(playerNumber)
	goldGains-= get_all_travel_costs(playerNumber)
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

func get_all_civilians_count(playerNumber: int) -> int:
	var player_cells: Array = get_all_player_tiles(playerNumber)
	var civilians_count: int = 0
	for cell in player_cells:
		civilians_count+= get_civilian_count(cell, playerNumber)
	return civilians_count

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

func get_all_free_cells() -> Array:
	var free_cells: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == -1: #cells not owned by any player (maybe tribal)
				free_cells.append(Vector2(x, y))
	return free_cells

func get_all_tiles_from_player_and_allies(playerNumber: int) -> Array:
	var allies_cells: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if !Game.are_player_allies(tiles_data[x][y].owner, playerNumber):
				continue			
			allies_cells.append(Vector2(x, y))
	return allies_cells

func get_all_player_tiles(playerNumber: int) -> Array:
	var player_cells: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber:
				player_cells.append(Vector2(x, y))
	return player_cells

func get_amount_of_player_tiles(playerNumber: int) -> int:
	return get_all_player_tiles(playerNumber).size()

func get_all_tiles_with_warriors_from_player(player_number: int, minimum_amount: int = 0) -> Array:
	var player_and_allies_cells: Array = get_all_tiles_from_player_and_allies(player_number) # fix: added allies territories also because sometimes bots got stuck at allies territories
	var troops_cells: Array = []
	for cell in player_and_allies_cells:
		if get_warriors_count(cell, player_number) > minimum_amount:
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

func get_own_troops_damage(tilePos: Vector2, playerNumber: int, only_warriors: bool = false) -> float:
	var allies_total_damage: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.amount <= 0:
			continue
		if only_warriors and !troop_types_obj.getByID(troopDict.troop_id).is_warrior:
			continue
		var averageTroopDamage: float = (troop_types_obj.getByID(troopDict.troop_id).damage.x + troop_types_obj.getByID(troopDict.troop_id).damage.y)/2.0
		allies_total_damage += troopDict.amount*averageTroopDamage
	return allies_total_damage

func get_own_troops_health(tilePos: Vector2, playerNumber: int, only_warriors: bool = false) -> float:
	var allies_total_health: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if troopDict.amount <= 0:
			continue
		if only_warriors and !troop_types_obj.getByID(troopDict.troop_id).is_warrior:
			continue
		var troopHealth: float = troop_types_obj.getByID(troopDict.troop_id).health
		allies_total_health += troopDict.amount*troopHealth
	return allies_total_health

func get_enemies_troops_damage(tilePos: Vector2, playerNumber: int) -> float:
	var enemies_total_damage: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner == playerNumber:
			continue
		if Game.are_player_allies(playerNumber, troopDict.owner):
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
		if Game.are_player_allies(playerNumber, troopDict.owner):
			continue
		if troopDict.amount <= 0:
			continue
		var troopHealth: float = troop_types_obj.getByID(troopDict.troop_id).health
		enemies_total_health += troopDict.amount*troopHealth
	return enemies_total_health

func get_enemies_upcoming_troops_health(tilePos: Vector2, playerNumber: int) -> float:
	var upcoming_total_health: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].upcomingTroops:
		if troopDict.owner == playerNumber:
			continue
		if Game.are_player_allies(playerNumber, troopDict.owner):
			continue
		if troopDict.amount <= 0:
			continue
		var troopHealth: float = troop_types_obj.getByID(troopDict.troop_id).health
		upcoming_total_health += troopDict.amount*troopHealth
	return upcoming_total_health

func get_enemies_upcoming_troops_damage(tilePos: Vector2, playerNumber: int) -> float:
	var upcoming_total_damage: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].upcomingTroops:
		if troopDict.owner == playerNumber:
			continue
		if Game.are_player_allies(playerNumber, troopDict.owner):
			continue
		if troopDict.amount <= 0:
			continue
		var averageTroopDamage: float = (troop_types_obj.getByID(troopDict.troop_id).damage.x + troop_types_obj.getByID(troopDict.troop_id).damage.y)/2.0
		upcoming_total_damage += troopDict.amount*averageTroopDamage
	return upcoming_total_damage

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

func get_neighbors_from_array(cell: Vector2, cell_array: Array, bitmask: int = ALL_DIR, mult: int = 1) -> Array:
	var neighbors: Array = []
	for n in DIRS.keys():
		if (bitmask & DIRS[n]) && cell_array.find(cell+n*mult) != -1:
			neighbors.append(cell+n*mult)
	return neighbors

func get_neighbors(cell: Vector2, bitmask: int = ALL_DIR, mult: int = 1) -> Array:
	var neighbors: Array = []
	for n in DIRS.keys():
		if (bitmask & DIRS[n]) && is_a_valid_tile(cell+n*mult):
			neighbors.append(cell+n*mult)
	return neighbors

func get_walkeable_neighbors(cell: Vector2, bitmask: int = ALL_DIR, mult: int = 1) -> Array:
	var neighbors: Array = []
	for n in DIRS.keys():
		if (bitmask & DIRS[n]) && is_a_valid_tile(cell+n*mult) && is_tile_walkeable(cell+n*mult):
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

func get_troops_clean(tile_pos: Vector2) -> Array:
	var cleaned_array: Array = []
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troopDict.amount <= 0:
			continue
		cleaned_array.append(troopDict.duplicate(true))
	return cleaned_array

func get_cell(tile_pos: Vector2, read_only: bool = false) -> Dictionary:
	if read_only:
		return tiles_data[tile_pos.x][tile_pos.y].duplicate(true)
	return tiles_data[tile_pos.x][tile_pos.y]

func get_all(read_only: bool = false) -> Array:
	if read_only:
		return tiles_data.duplicate(true)
	return tiles_data

func get_amount_of_cells() -> int:
	return int(round(tile_size.x*tile_size.y))

func set_all(new_tiles_data: Array, new_tile_size: Vector2) -> void:
	clear()
	tiles_data = new_tiles_data.duplicate(true)
	tile_size = new_tile_size

func get_cell_gold(cell: Vector2) -> float:
	return tiles_data[cell.x][cell.y].gold

func get_tile_type_dict(tile_pos: Vector2) -> Dictionary:
	return tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)

func get_all_travel_costs(playerNumber: int) -> float:
	var travel_costs: float = 0
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if tiles_data[x][y].owner == playerNumber or is_cell_in_battle(Vector2(x, y)): #Only being in not owned ally or neutral territory cost travel
				continue
			for troopDict in tiles_data[x][y].troops:
				if troopDict.amount <= 0:
					continue
				if troopDict.owner == playerNumber:
					travel_costs+= troop_types_obj.getByID(troopDict.troop_id).moving_cost_per_turn*troopDict.amount/1000.0
	return travel_costs


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

func get_players_in_cell(tile_pos: Vector2) -> Array:
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
	return playersInTileArray

func get_number_of_players_in_cell(tile_pos: Vector2) -> int:
	return get_players_in_cell(tile_pos).size()

func get_cell_owner(tile_pos: Vector2) -> int:
	return tiles_data[tile_pos.x][tile_pos.y].owner

################
#	SETTERS    #
################

func set_name(tile_pos: Vector2, name: String) -> void:
	tiles_data[tile_pos.x][tile_pos.y].name = name

func set_cell_gold(tile_pos: Vector2, gold: float):
	tiles_data[tile_pos.x][tile_pos.y].gold = gold

func set_troops(tile_pos: Vector2, troops_array: Array) -> void:
	tiles_data[tile_pos.x][tile_pos.y].troops.clear()
	tiles_data[tile_pos.x][tile_pos.y].troops = troops_array.duplicate(true)

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

func remove_troops_from_player(tile_pos: Vector2, player_number: int) -> void:
	var indexes_to_remove: Array = []
	var troops_data: Array = tiles_data[tile_pos.x][tile_pos.y].troops
	var removing_completed: bool = false
	while !removing_completed:
		removing_completed = true
		for i in range(troops_data.size()):
			if troops_data[i].owner == player_number:
				tiles_data[tile_pos.x][tile_pos.y].troops.remove(i)
				removing_completed = false
				break

func add_troops(tile_pos: Vector2, add_troops: Dictionary) -> void:
	for i in range(tiles_data[tile_pos.x][tile_pos.y].troops.size()):
		if tiles_data[tile_pos.x][tile_pos.y].troops[i].owner == add_troops.owner and tiles_data[tile_pos.x][tile_pos.y].troops[i].troop_id == add_troops.troop_id:
			tiles_data[tile_pos.x][tile_pos.y].troops[i].amount += add_troops.amount
			return
	tiles_data[tile_pos.x][tile_pos.y].troops.append(add_troops)

func append_upcoming_troops(tile_pos: Vector2, troopDict: Dictionary) -> void:
	tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.append(troopDict)

func gold_needed_to_upgrade(tile_pos: Vector2) -> float:
	var tileTypeDict = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	return tileTypeDict.improve_prize

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
	var gold_multiplier: float = 1.0
	if Game.is_player_a_bot(playerNumber):
		gold_multiplier = Game.get_bot_gains_multiplier(playerNumber)
	var gold_to_give: float = get_cell_gold_gain_and_losses(tile_pos, playerNumber)
	if gold_to_give >=0:
		gold_to_give*=gold_multiplier
	add_cell_gold(tile_pos, gold_to_give)

func queue_upgrade_cell(cell: Vector2) -> void:
	var tileTypeData = Game.tileTypes.getByID(tiles_data[cell.x][cell.y].tile_id)
	tiles_data[cell.x][cell.y].gold -= tileTypeData.improve_prize
	tiles_data[cell.x][cell.y].turns_to_improve_left = tileTypeData.turns_to_improve

func finish_upgrade_cell(tile_pos: Vector2, playerNumber: int) -> void:
	tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left = 0
	var extra_population: Dictionary = {
		owner = playerNumber,
		troop_id = troop_types_obj.getIDByName("civil"),
		amount = tile_types_obj.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id).min_civil_to_produce_gold
	}
	var nextStageTileTypeId: int = tile_types_obj.getNextStageID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	if extra_population.amount < tile_types_obj.getByID(nextStageTileTypeId).min_civil_to_produce_gold:
		extra_population.amount = tile_types_obj.getByID(nextStageTileTypeId).min_civil_to_produce_gold
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

func get_sync_data(playerNumber: int = -1, force: bool = false) -> Array: #if playerNumber != -1 then only sync ties from that player, useful for secure changes
	var cellsToSync: Array = []
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if playerNumber != -1 and tiles_data[x][y].owner != playerNumber:
				continue
			if tiles_data[x][y].owner == -1 and !is_next_to_any_player_territory(Vector2(x, y)):
				continue
			if old_tiles_data.size() <= x or old_tiles_data[x].size() <= y:
				continue
			if force or !Game.Util.dicts_are_equal(tiles_data[x][y], old_tiles_data[x][y]):
				cellsToSync.append({ cell_pos = Vector2(x, y), cell_data = tiles_data[x][y].duplicate( true ) })
	#print( "get_sync_data: " + str(cellsToSync.size()) )
	
	if !force: #do not do this in case this was a forced sync!
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
	#print( "get_sync_neighbors: " + str(cellsToSync.size()) )
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

func ai_get_cell_available_allowed_percent_troops_attack(cell_pos: Vector2, cell_to_attack: Vector2, player_number: int) -> float:
	var available_force: float = get_own_troops_health(cell_pos, player_number) + get_own_troops_damage(cell_pos, player_number)
	if available_force <= 0.0:
		return 0.0
	var percent_allowed_to_move: float = ai_get_cell_available_force_to_attack(cell_pos, cell_to_attack, player_number)/available_force
	if percent_allowed_to_move < 0.0:
		percent_allowed_to_move = 0.0
	return percent_allowed_to_move

func ai_get_cell_available_force(cell_pos: Vector2, player_number: int) -> float:
	var available_health: float = get_own_troops_health(cell_pos, player_number, true)
	var available_damage: float = get_own_troops_damage(cell_pos, player_number, true)
	var enemies_close_force: Dictionary = ai_get_enemies_strength_close_to(cell_pos, player_number)

	if Game.is_player_a_bot(player_number) and is_capital(cell_pos): #Extra force to protect owns capital
		var minimum_recruits_force_at_capital: float = float(Game.get_bot_minimum_capital_troops(player_number))
		var minimum_health_to_defend: float = float(troop_types_obj.getByID(troop_types_obj.getIDByName("recluta")).health)*minimum_recruits_force_at_capital
		var minimum_damage_to_defend: float = troop_types_obj.getAverageDamage(troop_types_obj.getIDByName("recluta"))*minimum_recruits_force_at_capital
		available_health-=minimum_health_to_defend
		available_damage-=minimum_damage_to_defend
	else:
		var upcoming_enemies_force: Dictionary = ai_get_upcoming_enemies_strength_at(cell_pos, player_number)
		#Fix: help bots to avoid leaving cells unprotected when an upcoming troop is going to spawn.
		enemies_close_force.damage+=upcoming_enemies_force.damage
		enemies_close_force.health+=upcoming_enemies_force.health

	available_health-=enemies_close_force.health
	available_damage-=enemies_close_force.damage
		
	return available_health+available_damage

func ai_get_cell_available_force_to_attack(cell_pos: Vector2, cell_to_attack: Vector2, player_number: int) -> float:
	var available_health: float = get_own_troops_health(cell_pos, player_number, true)
	var available_damage: float = get_own_troops_damage(cell_pos, player_number, true)
	var enemies_close_force: Dictionary = ai_get_enemies_strength_close_to(cell_pos, player_number, [cell_to_attack])

	if Game.is_player_a_bot(player_number) and is_capital(cell_pos): #Extra force to protect owns capital
		var minimum_recruits_force_at_capital: float = float(Game.get_bot_minimum_capital_troops(player_number))
		var minimum_health_to_defend: float = float(troop_types_obj.getByID(troop_types_obj.getIDByName("recluta")).health)*minimum_recruits_force_at_capital
		var minimum_damage_to_defend: float = troop_types_obj.getAverageDamage(troop_types_obj.getIDByName("recluta"))*minimum_recruits_force_at_capital
		available_health-=minimum_health_to_defend
		available_damage-=minimum_damage_to_defend
	else:
		var upcoming_enemies_force: Dictionary = ai_get_upcoming_enemies_strength_at(cell_pos, player_number)
		#Fix: help bots to avoid leaving cells unprotected when an upcoming troop is going to spawn.
		enemies_close_force.damage+=upcoming_enemies_force.damage
		enemies_close_force.health+=upcoming_enemies_force.health

	if !is_capital(cell_to_attack): # in case of enemy cell being capital it doesn't matter at all the force as long as you can take it down.
		available_health-=enemies_close_force.health
		available_damage-=enemies_close_force.damage

	return available_health+available_damage

func ai_get_cell_force(cell_pos: Vector2, player_number: int) -> float:
	var troops_health: float = get_own_troops_health(cell_pos, player_number)
	var troops_damage: float = get_own_troops_damage(cell_pos, player_number)
	return troops_health+troops_damage

func ai_get_cell_enemy_force(cell_pos: Vector2, player_number: int) -> float:
	var enemy_health: float = get_enemies_troops_health(cell_pos, player_number)
	var enemy_damage: float = get_enemies_troops_damage(cell_pos, player_number)
	return enemy_health+enemy_damage

func ai_can_conquer_enemy_pos(own_cell_pos: Vector2, enemy_cell_pos: Vector2, player_number: int, enemy_force_multiplier: float = 1.0) -> bool:
	return ai_get_cell_available_force_to_attack(own_cell_pos, enemy_cell_pos, player_number) > ai_get_cell_enemy_force(enemy_cell_pos, player_number)*1.15*enemy_force_multiplier #try to overcome enemy by a 10% as minimum

func ai_cell_is_in_danger(cell_pos: Vector2, player_number: int, cells_to_ignore: Array = []) -> bool:
	var cell_health: float = get_own_troops_health(cell_pos, player_number)
	var cell_damage: float = get_own_troops_damage(cell_pos, player_number)
	var enemies_close_force: Dictionary = ai_get_enemies_strength_close_to(cell_pos, player_number, cells_to_ignore)
	
	if !is_capital(cell_pos):  #This will never happen at own capital
		var upcoming_enemies_force: Dictionary = ai_get_upcoming_enemies_strength_at(cell_pos, player_number)
		#Fix: help bots to avoid leaving cells unprotected when an upcoming troop is going to spawn.
		enemies_close_force.damage+=upcoming_enemies_force.damage
		enemies_close_force.health+=upcoming_enemies_force.health
	
	if Game.is_player_a_bot(player_number) and is_capital(cell_pos): #Extra force to protect owns capital
		var minimum_recruits_force_at_capital: float = float(Game.get_bot_minimum_capital_troops(player_number))
		var minimum_health_to_defend: float = float(troop_types_obj.getByID(troop_types_obj.getIDByName("recluta")).health)*minimum_recruits_force_at_capital
		var minimum_damage_to_defend: float = troop_types_obj.getAverageDamage(troop_types_obj.getIDByName("recluta"))*minimum_recruits_force_at_capital
		enemies_close_force.damage+=minimum_damage_to_defend
		enemies_close_force.health+=minimum_health_to_defend
	
	if enemies_close_force.damage >= cell_damage or enemies_close_force.health >= cell_health: #Capital under danger of attack!
		return true
	return false

func ai_get_outer_territories(player_number: int) -> Array:
	var player_cells: Array = get_all_player_tiles(player_number)
	var border_cells: Array = []
	for cell in player_cells:
		if is_next_to_enemy_territory(cell, player_number):
			border_cells.append(cell)
	return border_cells

func ai_get_inner_territories(player_number: int) -> Array:
	return Game.Util.array_substract(get_all_player_tiles(player_number), ai_get_outer_territories(player_number))

func ai_get_all_ally_cells_in_danger(player_number: int, cells_to_ignore: Array = []) -> Array:
	var cells_in_danger: Array = []
	for i in range(Game.playersData.size()):
		if i == player_number:
			continue
		if !Game.playersData[i].alive:
			continue
		if !Game.are_player_allies(i, player_number):
			continue
		cells_in_danger = Game.Util.array_addition(cells_in_danger, ai_get_all_cells_in_danger(i, cells_to_ignore))
	return cells_in_danger

func ai_get_all_cells_in_danger(player_number: int, cells_to_ignore: Array = []) -> Array:
	var cells_in_danger: Array = []
	var bot_cells: Array = get_all_player_tiles(player_number)
	for cell in bot_cells:
		if ai_cell_is_in_danger(cell, player_number, cells_to_ignore):
			cells_in_danger.append(cell)
	return cells_in_danger

func ai_get_cells_not_in_danger(player_number: int, cells_to_ignore: Array = []) -> Array:
	return Game.Util.array_substract(get_all_player_tiles(player_number), ai_get_all_cells_in_danger(player_number, cells_to_ignore))

func ai_get_cells_available_to_move_troops_towards(player_number: int, pos_to_move: Vector2) -> Array:
	var cells_with_warriors: Array = get_all_tiles_with_warriors_from_player(player_number)
	var cells_in_danger: Array = ai_get_all_cells_in_danger(player_number, [pos_to_move])
	var cells_in_battle: Array = get_cells_in_battle_with_enemies(player_number)
	var cells_avilable_to_move_troops: Array = Game.Util.array_substract(cells_with_warriors, cells_in_danger) #all cells with warriors that are not in danger
	cells_avilable_to_move_troops = Game.Util.array_substract(cells_with_warriors, cells_in_battle) #cells in battle cannot be used
	return cells_avilable_to_move_troops

func ai_get_cells_available_to_conquer_pos(player_number: int, pos_to_attack: Vector2, minimum_amount: int = 0) -> Array:
	var cells_available_to_move_troops_towards: Array = ai_get_cells_available_to_move_troops_towards(player_number, pos_to_attack)
	var cells_that_can_conquer_pos: Array = []
	for cell in cells_available_to_move_troops_towards:
		if get_warriors_count(cell, player_number) >= minimum_amount and ai_can_conquer_enemy_pos(cell, pos_to_attack, player_number):
			cells_that_can_conquer_pos.append(cell)

	return cells_that_can_conquer_pos

func ai_get_strongest_available_cell_in_array(cells_array: Array, player_number: int) -> Vector2:
	#ai_get_cell_available_force_to_attack()
	var max_force_cell: Vector2 = Vector2(-1, -1)
	for cell in cells_array: 
		if max_force_cell == Vector2(-1, -1):
			max_force_cell = cell
			continue
		if ai_get_cell_available_force(cell, player_number) > ai_get_cell_available_force(max_force_cell, player_number):
			max_force_cell = cell
	return max_force_cell


func ai_get_weakest_cell_in_array(cells_array: Array, player_number: int) -> Vector2:
	var weakest_cell: Vector2 = Vector2(-1, -1)
	for cell in cells_array: 
		if weakest_cell == Vector2(-1, -1):
			weakest_cell = cell
			continue
		if ai_get_cell_force(cell, player_number) < ai_get_cell_force(weakest_cell, player_number):
			weakest_cell = cell
	return weakest_cell
	
func ai_order_cells_by_distance_to(cells_array: Array, cell_to_check_distance: Vector2) -> Array: #from closest to farthest
	var cell_return: Array = cells_array.duplicate(true)
	#cell_to_check_distance.distance_squared_to()
	var is_in_order: bool = false
	while !is_in_order:
		is_in_order = true
		for i in range(cell_return.size()-1):
			if cell_return[i+1].distance_squared_to(cell_to_check_distance) < cell_return[i].distance_squared_to(cell_to_check_distance):
				var tmp_cell: Vector2 = cell_return[i]
				cell_return[i] = cell_return[i+1]
				cell_return[i+1] = tmp_cell
				is_in_order = false
				break
	return cell_return

func ai_get_closest_cell_capable_of_conquering(player_number: int, pos_to_attack: Vector2) -> Vector2:
	return ai_get_closest_cell_to_from_array(ai_get_cells_available_to_conquer_pos(player_number, pos_to_attack), pos_to_attack)

func ai_get_strongest_available_force_own_cell(player_number: int) -> Vector2:
	var bot_cells: Array = get_all_player_tiles(player_number)
	var strongest_cell: Vector2 = Vector2(-1, -1)
	for cell in bot_cells:
		var cell_owner: int = tiles_data[cell.x][cell.y].owner
		if cell_owner != player_number:
			continue
		if strongest_cell == Vector2(-1, -1):
			strongest_cell = cell
			continue
		
		if ai_get_cell_available_force(cell, player_number) > ai_get_cell_available_force(strongest_cell, player_number):
			strongest_cell = cell
	return strongest_cell

func ai_get_strongest_own_cell(player_number: int) -> Vector2:
	var bot_cells: Array = get_all_player_tiles(player_number)
	var strongest_cell: Vector2 = Vector2(-1, -1)
	for cell in bot_cells:
		var cell_owner: int = tiles_data[cell.x][cell.y].owner
		if cell_owner != player_number:
			continue
		if strongest_cell == Vector2(-1, -1):
			strongest_cell = cell
			continue
		
		var strongest_cell_owner: int = tiles_data[strongest_cell.x][strongest_cell.y].owner
		if get_strength(cell, cell_owner) > get_strength(strongest_cell, strongest_cell_owner):
			strongest_cell = cell
	return strongest_cell

func ai_get_strongest_enemy_cell_in_array(cells_array: Array, player_number: int) -> Vector2:
	#ai_get_cell_available_force_to_attack()
	var max_force_cell: Vector2 = Vector2(-1, -1)
	for cell in cells_array: 
		if max_force_cell == Vector2(-1, -1):
			max_force_cell = cell
			continue
		if ai_get_cell_enemy_force(cell, player_number) > ai_get_cell_enemy_force(max_force_cell, player_number):
			max_force_cell = cell
	return max_force_cell

func ai_get_strongest_enemy_cell_in_path(path_to_follow: Array, player_number: int) -> Vector2:
	var strongest_cell: Vector2 = Vector2(-1, -1)
	for cell in path_to_follow:
		var cell_owner: int = tiles_data[cell.x][cell.y].owner
		if cell_owner == player_number or Game.are_player_allies(player_number, cell_owner):
			continue
		if strongest_cell == Vector2(-1, -1):
			strongest_cell = cell
			continue
		if ai_get_cell_enemy_force(cell, player_number) > ai_get_cell_enemy_force(strongest_cell, player_number):
			strongest_cell = cell
	return strongest_cell
	
func ai_get_neighbor_player_enemies(tile_pos: Vector2, player_number: int) -> Array:
	var neighbors: Array = get_walkeable_neighbors(tile_pos)
	var enemy_cells: Array = []
	for neighbor in neighbors:
		var cell_owner: int = tiles_data[neighbor.x][neighbor.y].owner
		if cell_owner == -1: #ignore tribal societies
			continue
		if cell_owner != player_number and !Game.are_player_allies(player_number, cell_owner):
			enemy_cells.append(neighbor)
	return enemy_cells

func ai_get_upcoming_enemies_strength_at(tile_pos: Vector2, player_number: int) -> Dictionary:
	return { health = get_enemies_upcoming_troops_health(tile_pos, player_number), damage = get_enemies_upcoming_troops_damage(tile_pos, player_number) }

func ai_get_enemies_strength_close_to(tile_pos: Vector2, player_number: int, cells_to_ignore: Array = []) -> Dictionary:
	var neighbors: Array = get_neighbors(tile_pos)
	neighbors.append(tile_pos) #also count enemies in the own territory maybe the tile is in barttle
	var enemies_health: float = 0.0
	var enemies_attack: float = 0.0
	for neighbor in neighbors:
		if tiles_data[neighbor.x][neighbor.y].owner == -1: #ignore tribal societies
			continue
		if cells_to_ignore.find(neighbor) != -1:
			continue
		enemies_health += get_enemies_troops_health(neighbor, player_number)
		enemies_attack += get_enemies_troops_damage(neighbor, player_number)
	return { health = enemies_health, damage = enemies_attack }

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
			var neighbors: Array = get_walkeable_neighbors(return_array[j], mask)
			for neighbor in neighbors:
				data_to_apend.append(neighbor)
		array_to_substract = return_array.duplicate(true)
		for j in range(data_to_apend.size()):
			if return_array.find(data_to_apend[j]) != -1:
				continue
			return_array.append(data_to_apend[j])
	#Substract to keep only the cells at distance
	return_array = Game.Util.array_substract(return_array, array_to_substract)
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

func ai_filter_cell_is_not_owned_by_any_player(cell: Vector2) -> bool:
	return tiles_data[cell.x][cell.y].owner == -1

func ai_filter_cell_is_available_to_buy(cell: Vector2, player_number: int) -> bool:
	return tiles_data[cell.x][cell.y].owner == -1 and !is_next_to_player_enemy_territory(cell, player_number)

func ai_get_closest_cell_to(cell: Vector2, filter_func: String, func_args: Array = [])-> Array: 
	var distance: int = 1
	var free_neighbors: Array = []
	var iterations: int = 0
	var args_to_send: Array = func_args.duplicate(true)
	while free_neighbors.size() <= 0:
		var neighbors: Array = ai_get_neighbors_by_distance(cell, distance)
		for neighbor in neighbors:
			iterations+=1
			args_to_send.push_front(neighbor)
			if callv(filter_func, args_to_send):
				free_neighbors.append(neighbor)
				
			args_to_send.pop_front()
		distance+=1
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_closest_cell_to")
			assert(0)

	return free_neighbors

func ai_get_closest_free_cell_to(cell: Vector2) -> Array:
	return ai_get_closest_cell_to(cell, "ai_filter_cell_is_not_owned_by_any_player")
	
func ai_get_closest_available_to_buy_free_cell_to(cell: Vector2, player_number: int) -> Array:
	return ai_get_closest_cell_to(cell, "ai_filter_cell_is_available_to_buy", [player_number])

func ai_get_farthest_player_cell_from(cell: Vector2, player_number: int) -> Array:
	var distance: int = 1
	var farthest_cells: Array = [cell]
	var tmp_farthest_cells: Array = [cell]
	var iterations: int = 0
	while tmp_farthest_cells.size() > 0:
		farthest_cells = tmp_farthest_cells.duplicate(true)
		tmp_farthest_cells.clear()
		var neighbors: Array = ai_get_neighbors_by_distance(cell, distance)
		for neighbor in neighbors:
			iterations+=1
			if tiles_data[neighbor.x][neighbor.y].owner == player_number:
				tmp_farthest_cells.append(neighbor)
		distance+=1
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_farthest_player_cell_from")
			assert(0)
	
	return farthest_cells

func ai_get_reachable_enemy_cells(player_number: int , use_allies_territories_too: bool = false) -> Array:
	var player_cells: Array = get_all_player_tiles(player_number)
	
	if use_allies_territories_too:
		for i in Game.MAX_PLAYERS:
			if i == player_number:
				continue
			if Game.playersData[i].team == -1:
				continue
			if !Game.playersData[i].alive:
				continue
			if Game.playersData[i].team != Game.playersData[player_number].team:
				continue
			player_cells += Game.Util.array_addition(player_cells, get_all_player_tiles(i))
	
	var enemy_cells: Array = []
	for cell in player_cells:
		var neighbors: Array = get_walkeable_neighbors(cell)
		for neighbor in neighbors:
			if tiles_data[neighbor.x][neighbor.y].owner != player_number and !Game.are_player_allies(player_number, tiles_data[neighbor.x][neighbor.y].owner):
				if enemy_cells.find(neighbor) == -1: #avoid duplicated
					enemy_cells.append(neighbor)
	return enemy_cells

func ai_have_strength_to_conquer(cell_to_conquer: Vector2, player_number: int) -> bool:
	var cell_owner: int = tiles_data[cell_to_conquer.x][cell_to_conquer.y].owner
	
	if cell_owner == player_number or Game.are_player_allies(cell_owner, player_number): #moving along own territory
		return true
	
	var enemy_cell_strength: float = get_strength(cell_to_conquer, cell_owner)
	return get_total_warriors_strength(player_number) > enemy_cell_strength

func ai_get_reachable_player_enemy_cells(player_number: int, use_allies_territories_too: bool = false) -> Array:
	var enemy_cells: Array = ai_get_reachable_enemy_cells(player_number, use_allies_territories_too)
	var enemy_player_cells: Array = []
	for cell in enemy_cells:
		if tiles_data[cell.x][cell.y].owner != -1:
			enemy_player_cells.append(cell)
	return enemy_player_cells

func ai_get_reachable_player_capital(player_number: int, use_allies_territories_too: bool = false) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_player_enemy_cells(player_number, use_allies_territories_too)
	for cell in enemy_cells:
		if is_capital(cell):
			return cell
	return Vector2(-1, -1)

func ai_get_strongest_capable_of_conquer_player_enemy_cell( player_number: int,  use_allies_territories_too: bool = false) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_player_enemy_cells(player_number, use_allies_territories_too)
	var strongest_own_ofensive_cell: Vector2 = ai_get_strongest_available_force_own_cell(player_number)
	var strongest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if strongest_cell == Vector2(-1, -1):
			strongest_cell = cell
			continue
		if !ai_can_conquer_enemy_pos(strongest_own_ofensive_cell, cell, player_number):
			continue
		if ai_get_cell_enemy_force(cell, player_number) > ai_get_cell_enemy_force(strongest_cell, player_number):
			strongest_cell = cell
	return strongest_cell

func ai_get_strongest_to_ally_capable_of_conquer_player_enemy_cell( player_number: int) -> Vector2:
	var enemy_cells: Array = Game.Util.array_substract(ai_get_reachable_player_enemy_cells(player_number, true), ai_get_reachable_player_enemy_cells(player_number, false))
	var strongest_own_ofensive_cell: Vector2 = ai_get_strongest_available_force_own_cell(player_number)
	var strongest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if strongest_cell == Vector2(-1, -1):
			strongest_cell = cell
			continue
		if !ai_can_conquer_enemy_pos(strongest_own_ofensive_cell, cell, player_number):
			continue
		if ai_get_cell_enemy_force(cell, player_number) > ai_get_cell_enemy_force(strongest_cell, player_number):
			strongest_cell = cell
	return strongest_cell

func ai_get_strongest_player_enemy_cell( player_number: int , use_allies_territories_too: bool = false) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_player_enemy_cells(player_number, use_allies_territories_too)
	var strongest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if strongest_cell == Vector2(-1, -1):
			strongest_cell = cell
			continue
		if ai_get_cell_enemy_force(cell, player_number) > ai_get_cell_enemy_force(strongest_cell, player_number):
			strongest_cell = cell
	return strongest_cell

func ai_get_weakest_player_enemy_cell( player_number: int , use_allies_territories_too: bool = false) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_player_enemy_cells(player_number, use_allies_territories_too)
	var weakest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if weakest_cell == Vector2(-1, -1):
			weakest_cell = cell
			continue
		var cell_owner: int = tiles_data[cell.x][cell.y].owner
		var weakest_cell_owner: int = tiles_data[weakest_cell.x][weakest_cell.y].owner
		if get_strength(cell, cell_owner) < get_strength(weakest_cell, weakest_cell_owner):
			weakest_cell = cell
	return weakest_cell

func ai_get_weakest_enemy_cell(player_number: int, use_allies_territories_too: bool = false) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_enemy_cells(player_number, use_allies_territories_too)
	var weakest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if weakest_cell == Vector2(-1, -1):
			weakest_cell = cell
			continue
		var cell_owner: int = tiles_data[cell.x][cell.y].owner
		var weakest_cell_owner: int = tiles_data[weakest_cell.x][weakest_cell.y].owner
		if get_strength(cell, cell_owner) < get_strength(weakest_cell, weakest_cell_owner):
			weakest_cell = cell
	return weakest_cell

func ai_get_richest_enemy_cell(player_number: int, use_allies_territories_too: bool = false) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_enemy_cells(player_number, use_allies_territories_too)
	var richest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if richest_cell == Vector2(-1, -1):
			richest_cell = cell
			continue
		if get_cell_gold(cell) > get_cell_gold(richest_cell):
			richest_cell = cell
	return richest_cell

func ai_get_closest_to_enemy_cell(player_number: int, pos_to_compare: Vector2, use_allies_territories_too: bool = false) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_enemy_cells(player_number, use_allies_territories_too)
	return ai_get_closest_cell_to_from_array(enemy_cells, pos_to_compare)

func ai_get_closest_to_player_enemy_cell(player_number: int, pos_to_compare: Vector2, use_allies_territories_too: bool = false) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_player_enemy_cells(player_number, use_allies_territories_too)
	return ai_get_closest_cell_to_from_array(enemy_cells, pos_to_compare)

func ai_get_closest_to_capital_enemy_cell(player_number: int,  use_allies_territories_too: bool = false) -> Vector2:
	return ai_get_closest_to_enemy_cell(player_number, get_player_capital_vec2(player_number), use_allies_territories_too)

func ai_get_closest_to_capital_player_enemy_cell(player_number: int,  use_allies_territories_too: bool = false) -> Vector2:
	return ai_get_closest_to_player_enemy_cell(player_number, get_player_capital_vec2(player_number), use_allies_territories_too)

func ai_get_distance_from_capital_to_player_enemy(player_number: int, use_allies_territories_too: bool = false) -> float:
	var player_capital_cell: Vector2 = get_player_capital_vec2(player_number)
	
	var closest_player_to_capital: Vector2 = ai_get_closest_to_capital_player_enemy_cell(player_number, use_allies_territories_too)
	if closest_player_to_capital == Vector2(-1, -1):
		return 9999.0
	return closest_player_to_capital.distance_to(player_capital_cell)

func ai_get_strongest_enemy_cell(player_number: int) -> Vector2:
	var enemy_cells: Array = ai_get_reachable_enemy_cells(player_number)
	var strongest_cell: Vector2 = Vector2(-1, -1)
	for cell in enemy_cells:
		if strongest_cell == Vector2(-1, -1):
			strongest_cell = cell
			continue
		if ai_get_cell_enemy_force(cell, player_number) > ai_get_cell_enemy_force(strongest_cell, player_number):
			strongest_cell = cell
	return strongest_cell

func ai_get_closest_cell_to_from_array(array_of_cells: Array, cell_pos: Vector2) -> Vector2:
	if array_of_cells.size() <= 0:
		return Vector2(-1, -1)
	var closest_index: int = 0
	for i in range(array_of_cells.size()):
		if cell_pos.distance_squared_to(array_of_cells[i]) < cell_pos.distance_squared_to(array_of_cells[closest_index]):
			closest_index = i
	return array_of_cells[closest_index]

func ai_get_all_own_territory_islands(player_number: int) -> Array: #array of arrays
	var island_tiles: Array = []
	var owned_tiles: Array = get_all_player_tiles(player_number)
	if owned_tiles.size() <= 0:
		return []
	var search_complete: bool = false
	var iterations: int = 0
	while !search_complete:
		search_complete = true
		var current_island_tiles: Array =  ai_get_all_own_territory_tiles_recheable_from(owned_tiles[0], player_number)
		if current_island_tiles.size() <= 0:
			break
		island_tiles.append(current_island_tiles)
		for cell in current_island_tiles:
			iterations+=1
			var remove_index: int = owned_tiles.find(cell)
			if remove_index != -1:
				owned_tiles.remove(remove_index)
		if owned_tiles.size() > 0:
			search_complete = false
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_closest_free_cell_to")
			assert(0)
		
	return island_tiles

func ai_get_closest_cells_between_islands(island_a: Array, island_b: Array) -> Dictionary: #dictionary with two vector2
	assert(island_a.size() > 0 and island_b.size() > 0)
	
	var closest_cells: Dictionary = { 
		cellA = Vector2(0, 0),
		cellB = Vector2(999, 999)
	}
	for islandACell in island_a:
		for islandBCell in island_b:
			if closest_cells.cellA.distance_squared_to(closest_cells.cellB) > islandACell.distance_squared_to(islandBCell):
				closest_cells.cellA = islandACell
				closest_cells.cellB = islandBCell
	return closest_cells

func ai_get_islands_with_bridges(islands: Array) -> Array:
	var all_territories: Array = Game.Util.convert_multidimentional_array_into_onedimensional(islands)
	var islands_already_connected: Array = []
	if islands.size() <= 1:
		return all_territories #only one big island, no need for bridges
	for i in range(islands.size()):
		for j in range(islands.size()):
			if i == j:
				continue
			if islands_already_connected.find(Vector2(i, j)) != -1 or islands_already_connected.find(Vector2(j, i)) != -1: #avoid doing extra work for free
				continue
			islands_already_connected.append(Vector2(i, j))
			var closest_cells_between_islands: Dictionary = ai_get_closest_cells_between_islands(islands[i], islands[j])
			var path_to_connect_islands: Array = ai_get_path_to_from(closest_cells_between_islands.cellA, closest_cells_between_islands.cellB)
			for path_cell in path_to_connect_islands:
				if all_territories.find(path_cell) == -1:
					all_territories.append(path_cell)
	return all_territories

 #returns a whole array of cells with bridges in case there are islands (bridges being enemy territories needed to connect the islands)
func ai_get_all_own_territory_with_bridges(player_number: int) -> Array:
	return ai_get_islands_with_bridges(ai_get_all_own_territory_islands(player_number))

func ai_get_all_own_and_allies_territories_with_bridges(player_number: int) -> Array:
	var all_allies_and_own_territories_islands: Array = ai_get_all_own_territory_islands(player_number)
	for i in Game.MAX_PLAYERS:
		if i == player_number:
			continue
		if Game.playersData[i].alive and Game.playersData[i].team != -1 and Game.playersData[i].team == Game.playersData[player_number].team:
			all_allies_and_own_territories_islands = Game.Util.array_addition(all_allies_and_own_territories_islands, ai_get_all_own_territory_islands(i), true)
	
	return ai_get_islands_with_bridges(all_allies_and_own_territories_islands)

func ai_get_all_own_territory_tiles_recheable_from(start_pos: Vector2, player_number: int) -> Array:
	# step 1 get neighbors from start_pos, then select the ones closest to end_pos
	var owned_tiles: Array = get_all_player_tiles(player_number)
	if owned_tiles.find(start_pos) == -1:
		return []
	var territories_recheable: Array = [start_pos]
	var search_complete: bool = false
	var neighbors: Array = []
	var iterations: int = 0
	while !search_complete:
		search_complete = true
		for cell in territories_recheable:
			neighbors.clear()
			neighbors = get_walkeable_neighbors(cell)
			for neighbor in neighbors:
				iterations+=1
				if owned_tiles.find(neighbor) != -1 and territories_recheable.find(neighbor) == -1:
					territories_recheable.append(neighbor)
					search_complete = false
					
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_all_own_territory_tiles_recheable_from")
			assert(0)
	return territories_recheable

func ai_get_attack_path_from_to(start_pos: Vector2, end_pos: Vector2, player_number: int) -> Array:
	var walk_territories: Array = ai_get_all_own_and_allies_territories_with_bridges(player_number)
	var path_to_use: Array = [start_pos]
	var cells_to_ignore: Array = []
	if walk_territories.size() <= 0:
		walk_territories.append(start_pos)
	#Step 1: Update walk territories to include end_pos and make bridges if necessary just in case
	if walk_territories.find(end_pos) == -1: #update walk_territories_path 
		var closest_cells_between_islands: Dictionary = ai_get_closest_cells_between_islands(walk_territories, [end_pos])
		var path_to_connect_islands: Array = ai_get_path_to_from(closest_cells_between_islands.cellA, closest_cells_between_islands.cellB)
		for path_cell in path_to_connect_islands:
			if walk_territories.find(path_cell) == -1:
				walk_territories.append(path_cell)
	
	#Step 2: start walking
	var neighbors: Array = []
	var valid_neighbors: Array = []
	var path_completed: bool = false
	var iterations: int = 0
	while !path_completed:
		neighbors = get_walkeable_neighbors(path_to_use[path_to_use.size()-1])
		valid_neighbors.clear()
		for neighbor in neighbors:
			iterations+=1
			if walk_territories.find(neighbor) != -1 and cells_to_ignore.find(neighbor) == -1 and path_to_use.find(neighbor) == -1:
				valid_neighbors.append(neighbor)
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_closest_free_cell_to")
			assert(0)
				
		if valid_neighbors.size() <= 0: #unable to move, go back
			cells_to_ignore.append(path_to_use[path_to_use.size()-1])
			path_to_use.pop_back() #removes last element
			if path_to_use.size() <= 0: #failed
				print("[ERROR] ai_get_attack_path_from_to failed, using ai_get_path_to_from")
				return ai_get_path_to_from(start_pos, end_pos)
		else:
			path_to_use.append(ai_get_closest_cell_to_from_array(valid_neighbors, end_pos))
		if path_to_use.find(end_pos) != -1:
			path_completed = true
	
	return path_to_use

func ai_get_path_to_from(start_pos: Vector2, end_pos: Vector2) -> Array:
	var walk_territories: Array = get_all_walkeable_tiles()
	var cells_to_ignore: Array = []
	# step 1 get neighbors from start_pos, then select the ones closest to end_pos
	var path_to_use: Array = [start_pos]
	#Step 2: start walking
	var neighbors: Array = []
	var valid_neighbors: Array = []
	var path_completed: bool = false
	var iterations: int = 0
	while !path_completed:
		neighbors = get_walkeable_neighbors(path_to_use[path_to_use.size()-1])
		valid_neighbors.clear()
		for neighbor in neighbors:
			iterations+=1
			if walk_territories.find(neighbor) != -1 and cells_to_ignore.find(neighbor) == -1 and path_to_use.find(neighbor) == -1:
				valid_neighbors.append(neighbor)
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_closest_free_cell_to")
			assert(0)
				
		if valid_neighbors.size() <= 0: #unable to move, go back
			cells_to_ignore.append(path_to_use[path_to_use.size()-1])
			path_to_use.pop_back() #removes last element
			if path_to_use.size() <= 0: #failed
				print("[ERROR] ai_get_path_to_from failed, return null path: " +str(start_pos) + " -> " +str(end_pos))
				return [] #null return equals impossible to achieve path
		else:
			path_to_use.append(ai_get_closest_cell_to_from_array(valid_neighbors, end_pos))
		if path_to_use.find(end_pos) != -1:
			path_completed = true
	
	return path_to_use

# Edit, change this to mak
func ai_move_warriors_from_to(start_pos: Vector2, end_pos: Vector2, player_number: int, percent_to_move: float = 1.0, force_to_move: bool = false) -> bool:
	var allowed_percent_to_move: float = ai_get_cell_available_allowed_percent_troops_attack(start_pos, end_pos, player_number)*0.9 #make it a bit less in order to avoid problems
	if allowed_percent_to_move > percent_to_move:
		allowed_percent_to_move = percent_to_move
		
	if force_to_move: #Move everything
		allowed_percent_to_move = 1.0

	var troops_were_moved: bool = false
	var startTroopsArray: Array = tiles_data[start_pos.x][start_pos.y].troops
	for troopDict in startTroopsArray:
		if troopDict.owner != player_number:
			continue
		if troopDict.amount <= 0:
			continue
		if !troop_types_obj.getByID(troopDict.troop_id).is_warrior:
			continue
		var troops_to_move: int = int(floor(troopDict.amount*allowed_percent_to_move))
		if troops_to_move > troopDict.amount:
			troops_to_move = troopDict.amount
		if troops_to_move > 0:
			troops_were_moved = true
		add_troops(end_pos, {
			owner = player_number,
			troop_id = troopDict.troop_id,
			amount = troops_to_move
		})
		troopDict.amount -= troops_to_move

	return troops_were_moved

func ai_get_all_cells_without_buildings(playerNumber: int) -> Array:
	var cells_with_builidngs: Array = get_all_buildings(playerNumber)
	var bot_tiles: Array = get_all_player_tiles(playerNumber)

	return Game.Util.array_substract(bot_tiles, cells_with_builidngs)

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

#################
# PCG STUFFF    #
#################

func pcg_get_closest_cells_between_islands(island_a: Array, island_b: Array) -> Dictionary: #dictionary with two vector2
	assert(island_a.size() > 0 and island_b.size() > 0)
	
	var closest_cells: Dictionary = { 
		cellA = Vector2(0, 0),
		cellB = Vector2(999, 999)
	}
	for islandACell in island_a:
		for islandBCell in island_b:
			if closest_cells.cellA.distance_squared_to(closest_cells.cellB) > islandACell.distance_squared_to(islandBCell):
				closest_cells.cellA = islandACell
				closest_cells.cellB = islandBCell
	return closest_cells

func pcg_get_closest_cell_to_from_array(array_of_cells: Array, cell_pos: Vector2) -> Vector2:
	var closest_index: int = 0
	for i in range(array_of_cells.size()):
		if cell_pos.distance_squared_to(array_of_cells[i]) < cell_pos.distance_squared_to(array_of_cells[closest_index]):
			closest_index = i
	return array_of_cells[closest_index]

func pcg_get_path_to_from(start_pos: Vector2, end_pos: Vector2) -> Array:
	# step 1 get neighbors from start_pos, then select the ones closest to end_pos
	var path_completed: bool = false
	var path_array: Array = [start_pos]
	var neighbors: Array = []
	var iterations: int = 0
	while !path_completed:
		neighbors = get_neighbors(path_array[path_array.size()-1])
		path_array.append(pcg_get_closest_cell_to_from_array(neighbors, end_pos))
		if path_array.find(end_pos) != -1:
			path_completed = true
		
		iterations+=1
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_closest_free_cell_to")
			assert(0)
	return path_array

func pcg_make_bridge_to_connect_tiles(array_of_tiles: Array) -> Array:
	var islands: Array = pcg_get_all_islands(array_of_tiles)
	var all_territories: Array = array_of_tiles.duplicate(true)
	var islands_already_connected: Array = []
	if islands.size() <= 1:
		return all_territories #only one big island, no need for bridges
	for i in range(islands.size()):
		for j in range(islands.size()):
			if i == j:
				continue
			if islands_already_connected.find(Vector2(i, j)) != -1 or islands_already_connected.find(Vector2(j, i)) != -1: #avoid doing extra work for free
				continue
			islands_already_connected.append(Vector2(i, j))
			var closest_cells_between_islands: Dictionary = pcg_get_closest_cells_between_islands(islands[i], islands[j])
			var path_to_connect_islands: Array = pcg_get_path_to_from(closest_cells_between_islands.cellA, closest_cells_between_islands.cellB)
			for path_cell in path_to_connect_islands:
				if all_territories.find(path_cell) == -1:
					all_territories.append(path_cell)
	return all_territories

func pcg_get_all_islands(array_of_tiles: Array) -> Array: #array of arrays
	var tiles_to_search: Array = array_of_tiles.duplicate(true)
	var island_tiles: Array = []
	var search_complete: bool = false
	var iterations: int = 0
	while !search_complete:
		search_complete = true
		var current_island_tiles: Array =  pcg_get_all_tiles_recheable_from(tiles_to_search[0], tiles_to_search)
		if current_island_tiles.size() <= 0:
			break
		island_tiles.append(current_island_tiles)
		for cell in current_island_tiles:
			iterations+=1
			var remove_index: int = tiles_to_search.find(cell)
			if remove_index != -1:
				tiles_to_search.remove(remove_index)
		if tiles_to_search.size() > 0:
			search_complete = false
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_closest_free_cell_to")
			assert(0)
		
	return island_tiles

func pcg_get_all_tiles_recheable_from(start_pos: Vector2, array_of_tiles: Array) -> Array:
	# step 1 get neighbors from start_pos, then select the ones closest to end_pos
	if array_of_tiles.find(start_pos) == -1:
		return []
	var territories_recheable: Array = [start_pos]
	var search_complete: bool = false
	var neighbors: Array = []
	var iterations: int = 0
	while !search_complete:
		search_complete = true
		for cell in territories_recheable:
			neighbors.clear()
			neighbors = get_neighbors(cell)
			for neighbor in neighbors:
				iterations+=1
				if array_of_tiles.find(neighbor) != -1 and territories_recheable.find(neighbor) == -1:
					territories_recheable.append(neighbor)
					search_complete = false
					
		if iterations >= MAX_ITERATIONS_ALLOWED:
			print("[CRASH] INFINITE LOOP AT: ai_get_all_own_territory_tiles_recheable_from")
			assert(0)
	return territories_recheable

func pcg_generate_rocks(percent_to_generate: float = 0.125) -> void:
	var all_free_cells: Array = get_all_free_cells() #cells not owned by any player or bot
	var rocks_to_generate: int = round(float(all_free_cells.size())*percent_to_generate)
	var rock_cells: Array = []
	while rocks_to_generate > 0:
		var index_to_use: int = rng.randi_range(0, all_free_cells.size()-1)
		rock_cells.append(all_free_cells[index_to_use])
		#tiles_data[cell.x][cell.y].owner = ROCK_OWNER_ID
		all_free_cells.remove(index_to_use)
		rocks_to_generate-=1
	
	#making sure all capitals are connected
	var all_capitals: Array = get_all_capitals()
	var capital_paths: Array = []
	var tmp_path: Array = []
	for cellA in all_capitals:
		for cellB in all_capitals:
			if cellA == cellB:
				continue
			tmp_path.clear()
			tmp_path = pcg_get_path_to_from(cellA, cellB)
			for cellPath in tmp_path:
				if capital_paths.find(cellPath) == -1:
					capital_paths.append(cellPath)
					
	rock_cells = Game.Util.array_substract(rock_cells, capital_paths)
	
	#removing bad diagonal rocks
	var need_to_clean: bool = true
	while need_to_clean:
		need_to_clean = false
		var remove_index: int = -1
		for i in range(rock_cells.size()):
			var diag_neighbors: Array = get_neighbors_from_array(rock_cells[i], rock_cells, DIAG_DIR)
			if diag_neighbors.size() <= 0:
				continue # no need to do anything, this tile have no diagonal neighbors
			if rock_cells.find(rock_cells[i]+Vector2(1, 1)) != -1 and (rock_cells.find(rock_cells[i]+Vector2(1, 0)) != -1 or rock_cells.find(rock_cells[i]+Vector2(0, 1)) != -1):
					continue
			if rock_cells.find(rock_cells[i]+Vector2(1, -1)) != -1 and (rock_cells.find(rock_cells[i]+Vector2(1, 0)) != -1 or rock_cells.find(rock_cells[i]+Vector2(0, -1)) != -1):
					continue
			if rock_cells.find(rock_cells[i]+Vector2(-1, -1)) != -1 and (rock_cells.find(rock_cells[i]+Vector2(0, -1)) != -1 or rock_cells.find(rock_cells[i]+Vector2(-1, 0)) != -1):
					continue
			if rock_cells.find(rock_cells[i]+Vector2(-1, 1)) != -1 and (rock_cells.find(rock_cells[i]+Vector2(0, 1)) != -1 or rock_cells.find(rock_cells[i]+Vector2(-1, 0)) != -1):
					continue
			remove_index = i
			break
		if remove_index != -1:
			rock_cells.remove(remove_index)
			need_to_clean = true
	
	#update free cells
	all_free_cells = get_all_free_cells() #avoid bug
	all_free_cells = Game.Util.array_substract(all_free_cells, rock_cells)
	all_free_cells = pcg_make_bridge_to_connect_tiles(all_free_cells)
	rock_cells = Game.Util.array_substract(rock_cells, all_free_cells)
	
	#Start adding rocks finally
	for rock_pos in rock_cells:
		tiles_data[rock_pos.x][rock_pos.y].owner = ROCK_OWNER_ID
		tiles_data[rock_pos.x][rock_pos.y].type_of_rock = rng.randi_range(0, 3)
