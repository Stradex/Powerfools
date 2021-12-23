extends Node2D

onready var id_tile_non_selected: int = $SelectionTiles.tile_set.find_tile_by_name('off')
onready var id_tile_selected: int = $SelectionTiles.tile_set.find_tile_by_name('tile_hover')
onready var id_tile_not_allowed: int = $SelectionTiles.tile_set.find_tile_by_name('tile_not_allowed')
onready var id_tile_action_begin: int = $SelectionTiles.tile_set.find_tile_by_name('tile_action_begin')
onready var id_tile_action_end: int = $SelectionTiles.tile_set.find_tile_by_name('tile_action_end')
onready var id_tile_upgrading: int = $ConstructionTiles.tile_set.find_tile_by_name('tile_upgrading')
onready var id_tile_building_in_progress: int = $BuildingTypesTiles.tile_set.find_tile_by_name('building_in_progress')
onready var id_tile_civilians: int = $CivilianTiles.tile_set.find_tile_by_name('civilians')
onready var id_tile_overpopulation: int = $CivilianTiles.tile_set.find_tile_by_name('civilians_overpopulation')
onready var id_tile_underpopulation: int = $CivilianTiles.tile_set.find_tile_by_name('civilians_underpopulation')
onready var id_tile_troops: int = $TroopsTiles.tile_set.find_tile_by_name('military_troops')
onready var id_tile_deploying_troops: int = $TroopsTiles.tile_set.find_tile_by_name('military_troops_wip')
onready var id_tile_battle: int = $ConstructionTiles.tile_set.find_tile_by_name('battle_in_progress')
onready var id_not_owned_tile: int = $OwnedTiles.tile_set.find_tile_by_name('tile_not_owned')
onready var id_not_visible_tile: int = $VisibilityTiles.tile_set.find_tile_by_name('tile_invisible')
onready var id_rock_tile: int = $BuildingsTiles.tile_set.find_tile_by_name('tile_rock3')
onready var id_debug_tile: int = $DebugTiles.tile_set.find_tile_by_name('tile_path_debug')
onready var id_enemy_player_tile: int = $OwnedTiles.tile_set.find_tile_by_name('tile_player_enemy')
onready var id_ally_player_tile: int = $OwnedTiles.tile_set.find_tile_by_name('tile_ally')

onready var id_rock_types: Array = [
	$BuildingsTiles.tile_set.find_tile_by_name('tile_rock1'),
	$BuildingsTiles.tile_set.find_tile_by_name('tile_rock2'),
	$BuildingsTiles.tile_set.find_tile_by_name('tile_rock3'),
	$BuildingsTiles.tile_set.find_tile_by_name('tile_rock4')
]

const MINIMUM_CIVILIAN_ICON_COUNT: int = 50 
const MINIMUM_TROOPS_ICON_COUNT: int = 10

func update_building_tiles() -> void:
	
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer() or Game.is_current_player_a_bot():
		player_mask = Game.get_local_player_number()

	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			var tile_cell_data: Dictionary = Game.tilesObj.get_cell(Vector2(x, y))
			var tileImgToSet
			if tile_cell_data.owner == Game.tilesObj.ROCK_OWNER_ID:
				tileImgToSet = id_rock_types[tile_cell_data.type_of_rock]
				#tileImgToSet = id_rock_tile
			else:
				tileImgToSet = $BuildingsTiles.tile_set.find_tile_by_name(Game.tileTypes.getImg(tile_cell_data.tile_id))
				
			var buildingImgToSet = -1
			if Game.tilesObj.is_cell_in_battle(Vector2(x, y)):
				$ConstructionTiles.set_cellv(Vector2(x, y), id_tile_battle)
			elif tile_cell_data.owner == player_mask and Game.tilesObj.is_upgrading(Vector2(x, y)):
				$ConstructionTiles.set_cellv(Vector2(x, y), id_tile_upgrading)
			else:
				$ConstructionTiles.set_cellv(Vector2(x, y), -1)
			
			if tile_cell_data.owner == player_mask and Game.tilesObj.is_building(Vector2(x, y)):
				$BuildingTypesTiles.set_cellv(Vector2(x, y), id_tile_building_in_progress)
			elif tile_cell_data.owner == player_mask and tile_cell_data.building_id >= 0:
				buildingImgToSet = $BuildingTypesTiles.tile_set.find_tile_by_name(Game.buildingTypes.getImg(tile_cell_data.building_id))
				$BuildingTypesTiles.set_cellv(Vector2(x, y), buildingImgToSet)
			else:
				$BuildingTypesTiles.set_cellv(Vector2(x, y), -1)
			
			if  Game.tilesObj.belongs_to_player(Vector2(x, y), player_mask):
				$OwnedTiles.set_cellv(Vector2(x, y), -1)
			elif tile_cell_data.owner >= 0 and !Game.are_player_allies(tile_cell_data.owner, player_mask):
				$OwnedTiles.set_cellv(Vector2(x, y), id_enemy_player_tile)
			elif tile_cell_data.owner >= 0 and Game.are_player_allies(tile_cell_data.owner, player_mask):
				$OwnedTiles.set_cellv(Vector2(x, y), id_ally_player_tile)
			else:
				$OwnedTiles.set_cellv(Vector2(x, y), id_not_owned_tile)
			
			$CivilianTiles.set_cellv(Vector2(x, y), get_civilians_tile_id(Vector2(x, y), player_mask))
			$BuildingsTiles.set_cellv(Vector2(x, y), tileImgToSet)
			if Game.are_player_allies(tile_cell_data.owner, player_mask):
				$TroopsTiles.set_cellv(Vector2(x, y), get_troops_tile_id(Vector2(x, y), player_mask))
			else:
				$TroopsTiles.set_cellv(Vector2(x, y), -1)

func get_civilians_tile_id(tile_pos: Vector2, playerNumber: int) -> int:
	var civilianCountInTile: int = Game.tilesObj.get_civilian_count(tile_pos, playerNumber)
	var tileTypeDict: Dictionary = Game.tilesObj.get_tile_type_dict(tile_pos)
	if civilianCountInTile < MINIMUM_CIVILIAN_ICON_COUNT:
		return -1
	elif civilianCountInTile >= MINIMUM_CIVILIAN_ICON_COUNT and civilianCountInTile < tileTypeDict.min_civil_to_produce_gold:
		return id_tile_underpopulation
	elif civilianCountInTile >= tileTypeDict.min_civil_to_produce_gold && civilianCountInTile <= tileTypeDict.max_civil_to_produce_gold:
		return id_tile_civilians

	return id_tile_overpopulation

func get_troops_tile_id(tile_pos: Vector2, playerNumber: int) -> int:
	var troopsCountInTile: int = Game.tilesObj.get_warriors_count(tile_pos, playerNumber)
	var upcoming_troops_data: Array = Game.tilesObj.get_upcoming_troops(tile_pos)
	if upcoming_troops_data.size() > 0 and Game.tilesObj.get_owner(tile_pos) == playerNumber:
		return id_tile_deploying_troops
	elif troopsCountInTile > MINIMUM_TROOPS_ICON_COUNT:
		return id_tile_troops
	return -1

func update_selection_tiles() -> void:
	
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer() or Game.is_current_player_a_bot():
		player_mask = Game.get_local_player_number()
	var mouse_pos: Vector2 = get_global_mouse_position()
	mouse_pos -= self.position
	mouse_pos /= self.scale
	var tile_selected: Vector2 = $SelectionTiles.world_to_map(mouse_pos)
	if Game.current_tile_selected == tile_selected:
		return
	
	if tile_selected.x >= Game.tile_map_size.x or tile_selected.x < 0 or tile_selected.y >= Game.tile_map_size.y or tile_selected.y < 0:
		return

	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			if Game.interactTileSelected == Vector2(x, y):
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_action_begin)
			elif Game.nextInteractTileSelected == Vector2(x, y):
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_action_end)
			elif Vector2(x, y) == tile_selected:
				$SelectionTiles.set_cellv(Vector2(x, y), get_tile_selected_img_id(Vector2(x, y), player_mask))
			else:
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_non_selected)
	Game.current_tile_selected = tile_selected

func get_tile_selected_img_id(tile_pos: Vector2, playerNumber: int) -> int:
	if Game.current_game_status == Game.STATUS.GAME_STARTED:
		if Game.interactTileSelected != Vector2(-1, -1) and Game.nextInteractTileSelected == Vector2(-1, -1):
			if Game.tilesObj.is_next_to_tile(Game.interactTileSelected, tile_pos):
				return id_tile_selected
			else:
				return id_tile_not_allowed
		elif !Game.tilesObj.belongs_to_player(tile_pos, playerNumber):
			return id_tile_not_allowed
	return id_tile_selected

func update_visibility_tiles() -> void:
	
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer() or Game.is_current_player_a_bot():
		player_mask = Game.get_local_player_number()
		
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			$VisibilityTiles.set_cellv(Vector2(x, y), get_visibility_tile_img(Vector2(x, y)))

func get_visibility_tile_img(tile_pos: Vector2) -> int:
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer() or Game.is_current_player_a_bot():
		player_mask = Game.get_local_player_number()
		
	if Game.DEBUG_MODE or tile_should_be_visible(tile_pos, player_mask):
		return -1
	return id_not_visible_tile

func tile_should_be_visible(tile_pos: Vector2, playerNumber: int) -> bool:
	var tile_cell_data: Dictionary = Game.tilesObj.get_cell(tile_pos)
	if tile_cell_data.owner == playerNumber:
		return true
	if Game.tilesObj.is_next_to_player_territory(tile_pos, playerNumber):
		return true
	if Game.tilesObj.belongs_to_allies(tile_pos, playerNumber):
		return true
	if Game.tilesObj.is_next_to_allies_territory_with_own_troops(tile_pos, playerNumber):
		return true
	return Game.tilesObj.has_troops_or_citizen(tile_pos, playerNumber)

func debug_tile_path(tile_path: Array) -> void:
	if !Game.DEBUG_MODE:
		return
	$DebugTiles.clear()
	for cell in tile_path:
		$DebugTiles.set_cellv(cell, id_debug_tile)
