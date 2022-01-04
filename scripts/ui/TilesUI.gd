extends Node2D

var id_tile_non_selected: int = -1
var id_tile_hover: int = -1
var id_tile_hover_not_allowed: int = -1
var id_tile_action_begin: int = -1
var id_tile_action_end: int = -1
var id_tile_upgrading: int = -1
var id_tile_building_in_progress: int = -1
var id_tile_civilians: int = -1
var id_tile_overpopulation: int = -1
var id_tile_underpopulation: int = -1
var id_tile_own_troops: int = -1
var id_tile_ally_troops: int = -1
var id_tile_enemy_troops: int = -1
var id_tile_deploying_troops: int = -1
var id_tile_battle: int = -1
var id_owned_tile: int = -1
var id_not_owned_tile: int = -1
var id_not_visible_tile: int = -1
onready var id_debug_tile: int = $DebugTiles.tile_set.find_tile_by_name('tile_path_debug')
var id_enemy_player_tile: int = -1
var id_ally_player_tile: int = -1
onready var id_selling_tile: int = $FuncTiles.tile_set.find_tile_by_name('tile_selling')

var id_rock_types: Array = []

const MINIMUM_CIVILIAN_ICON_COUNT: int = 50 
const MINIMUM_TROOPS_ICON_COUNT: int = 100

func _ready():
	var base_building_types_tiles_folder: String = Game.GAME_DEFAULT_MOD + "/graphics/buildings"
	var base_terrain_types_tiles_folder: String = Game.GAME_DEFAULT_MOD + "/graphics/tiles"
	var base_func_tiles_files_folder: String = Game.GAME_DEFAULT_MOD + "/graphics/functiles"
	var base_troop_tiles_files_folder: String = Game.GAME_DEFAULT_MOD + "/graphics/troops"
	var building_types_tiles_folder: String = Game.current_mod + "/graphics/buildings"
	var terrain_types_tiles_folder: String = Game.current_mod + "/graphics/tiles"
	var func_tiles_files_folder: String = Game.current_mod + "/graphics/functiles"
	var troop_tiles_files_folder: String = Game.current_mod + "/graphics/troops"
	
	var new_func_tiles: TileSet = Game.TileSetImporter.make_tileset_from_folder(func_tiles_files_folder)
	var new_buildings_tiles: TileSet = Game.TileSetImporter.make_tileset_from_folder(terrain_types_tiles_folder)
	var new_buildings_types_tiles: TileSet = Game.TileSetImporter.make_tileset_from_folder(building_types_tiles_folder)
	var new_troops_tiles: TileSet = Game.TileSetImporter.make_tileset_from_folder(troop_tiles_files_folder)
	if Game.current_mod.to_lower() != Game.GAME_DEFAULT_MOD.to_lower(): #loading a MOD
		Game.TileSetImporter.append_to_tileset_from_folder(base_terrain_types_tiles_folder, new_buildings_tiles)
		Game.TileSetImporter.append_to_tileset_from_folder(base_building_types_tiles_folder, new_buildings_types_tiles)
		Game.TileSetImporter.append_to_tileset_from_folder(base_func_tiles_files_folder, new_func_tiles)
		Game.TileSetImporter.append_to_tileset_from_folder(base_troop_tiles_files_folder, new_troops_tiles)
	
	$BuildingsTiles.init_tile_data_array(Game.tile_map_size)
	$BuildingsTilesOverlay.init_tile_data_array(Game.tile_map_size)
	$BuildingTypesTiles.init_tile_data_array(Game.tile_map_size)
	$BuildingTypesTilesOverlay.init_tile_data_array(Game.tile_map_size)
	$OwnedTiles.init_tile_data_array(Game.tile_map_size)
	
	$BuildingsTiles.tile_set = new_buildings_tiles
	$BuildingsTilesOverlay.tile_set = new_buildings_tiles
	$BuildingTypesTiles.tile_set = new_buildings_types_tiles
	$BuildingTypesTilesOverlay.tile_set = new_buildings_types_tiles
	$OwnedTiles.tile_set = new_func_tiles
	$SelectionTiles.tile_set = new_func_tiles
	$ConstructionTiles.tile_set = new_func_tiles
	$CivilianTiles.tile_set = new_func_tiles
	$TroopsTiles.tile_set = new_troops_tiles
	
	id_not_visible_tile = $BuildingsTiles.tile_set.find_tile_by_name(Game.functiles_dict.noinfo_tile)
	id_owned_tile = $OwnedTiles.tile_set.find_tile_by_name(Game.functiles_dict.owned_border)
	id_not_owned_tile = $OwnedTiles.tile_set.find_tile_by_name(Game.functiles_dict.not_owned_border)
	id_ally_player_tile = $OwnedTiles.tile_set.find_tile_by_name(Game.functiles_dict.allies_border)
	id_enemy_player_tile = $OwnedTiles.tile_set.find_tile_by_name(Game.functiles_dict.enemies_border)
	id_tile_hover = $SelectionTiles.tile_set.find_tile_by_name(Game.functiles_dict.tile_hover)
	id_tile_hover_not_allowed = $SelectionTiles.tile_set.find_tile_by_name(Game.functiles_dict.tile_hover_not_allowed)
	id_tile_action_begin = $SelectionTiles.tile_set.find_tile_by_name(Game.functiles_dict.action_start_tile)
	id_tile_action_end = $SelectionTiles.tile_set.find_tile_by_name(Game.functiles_dict.action_end_tile)
	id_tile_non_selected = $SelectionTiles.tile_set.find_tile_by_name(Game.functiles_dict.tile_not_selected)
	id_tile_upgrading = $ConstructionTiles.tile_set.find_tile_by_name(Game.functiles_dict.tile_upgrading)
	id_tile_battle = $ConstructionTiles.tile_set.find_tile_by_name(Game.functiles_dict.tile_battle)
	id_tile_civilians = $CivilianTiles.tile_set.find_tile_by_name(Game.functiles_dict.civilian)
	id_tile_overpopulation = $CivilianTiles.tile_set.find_tile_by_name(Game.functiles_dict.civilian_overpopulation)
	id_tile_underpopulation = $CivilianTiles.tile_set.find_tile_by_name(Game.functiles_dict.civilian_underpopulation)
	id_tile_building_in_progress = $BuildingTypesTiles.tile_set.find_tile_by_name('building_in_progress')
	id_tile_own_troops = $TroopsTiles.tile_set.find_tile_by_name("own_troops")
	id_tile_ally_troops = $TroopsTiles.tile_set.find_tile_by_name("ally_troops")
	id_tile_enemy_troops = $TroopsTiles.tile_set.find_tile_by_name("enemy_troops")
	id_tile_deploying_troops = $TroopsTiles.tile_set.find_tile_by_name("troop_wip")
	id_rock_types.clear()
	id_rock_types = [
		$BuildingsTiles.tile_set.find_tile_by_name('_auto1_mountains'),
		$BuildingsTiles.tile_set.find_tile_by_name('_auto1_mountains'),
		$BuildingsTiles.tile_set.find_tile_by_name('_auto1_mountains'),
		$BuildingsTiles.tile_set.find_tile_by_name('_auto1_mountains')
	]


func update_building_tiles() -> void:
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer() or Game.is_current_player_a_bot():
		player_mask = Game.get_local_player_number()

	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			var tile_cell_data: Dictionary = Game.tilesObj.get_cell(Vector2(x, y))
			var tileImgToSet=-1
			var tileImgOverlayToSet=-1
			var owner_civ_id: int = -1
			if tile_cell_data.owner >= 0:
				owner_civ_id = Game.playersData[tile_cell_data.owner].civilization_id
				
			if !tile_should_be_visible(Vector2(x, y), player_mask) and !Game.DEBUG_MODE:
				tileImgToSet = id_not_visible_tile
			elif tile_cell_data.owner == Game.tilesObj.ROCK_OWNER_ID:
				tileImgToSet = id_rock_types[tile_cell_data.type_of_rock]
			else:
				tileImgToSet = $BuildingsTiles.tile_set.find_tile_by_name(Game.tileTypes.getImg(tile_cell_data.tile_id, owner_civ_id))
			
			if tileImgToSet != -1:
				var overlay_tile_name: String = $BuildingsTiles.tile_set.tile_get_name(tileImgToSet) + "_overlay"
				tileImgOverlayToSet = $BuildingsTilesOverlay.tile_set.find_tile_by_name(overlay_tile_name)
			
			var buildingImgToSet = -1
			if !tile_should_be_visible(Vector2(x, y), player_mask) and !Game.DEBUG_MODE:
				$ConstructionTiles.set_cellv(Vector2(x, y), -1)
			elif Game.tilesObj.is_cell_in_battle(Vector2(x, y)):
				$ConstructionTiles.set_cellv(Vector2(x, y), id_tile_battle)
			elif (Game.are_player_allies(player_mask, tile_cell_data.owner) or Game.DEBUG_MODE) and Game.tilesObj.is_upgrading(Vector2(x, y)):
				$ConstructionTiles.set_cellv(Vector2(x, y), id_tile_upgrading)
			else:
				$ConstructionTiles.set_cellv(Vector2(x, y), -1)
			
			if !tile_should_be_visible(Vector2(x, y), player_mask) and !Game.DEBUG_MODE:
				$BuildingTypesTiles.set_cellv_optimized(Vector2(x, y), -1)
			elif (Game.are_player_allies(player_mask, tile_cell_data.owner) or Game.DEBUG_MODE) and Game.tilesObj.is_building(Vector2(x, y)):
				$BuildingTypesTiles.set_cellv_optimized(Vector2(x, y), id_tile_building_in_progress)
			elif (Game.are_player_allies(player_mask, tile_cell_data.owner) or Game.DEBUG_MODE) and tile_cell_data.building_id >= 0:
				buildingImgToSet = $BuildingTypesTiles.tile_set.find_tile_by_name(Game.buildingTypes.getImg(tile_cell_data.building_id))
				$BuildingTypesTiles.set_cellv_optimized(Vector2(x, y), buildingImgToSet)
			else:
				$BuildingTypesTiles.set_cellv(Vector2(x, y), -1)
			
			if !tile_should_be_visible(Vector2(x, y), player_mask) and !Game.DEBUG_MODE:
				$OwnedTiles.set_cellv_optimized(Vector2(x, y), -1)
			elif Game.tilesObj.belongs_to_player(Vector2(x, y), player_mask):
				$OwnedTiles.set_cellv_optimized(Vector2(x, y), id_owned_tile)
			elif tile_cell_data.owner >= 0 and !Game.are_player_allies(tile_cell_data.owner, player_mask):
				$OwnedTiles.set_cellv_optimized(Vector2(x, y), id_enemy_player_tile)
			elif tile_cell_data.owner >= 0 and Game.are_player_allies(tile_cell_data.owner, player_mask):
				$OwnedTiles.set_cellv_optimized(Vector2(x, y), id_ally_player_tile)
			else:
				$OwnedTiles.set_cellv_optimized(Vector2(x, y), id_not_owned_tile)
			
			$CivilianTiles.set_cellv(Vector2(x, y), get_civilians_tile_id(Vector2(x, y), player_mask))
			$BuildingsTiles.set_cellv_optimized(Vector2(x, y), tileImgToSet)
			$BuildingsTilesOverlay.set_cellv_optimized(Vector2(x, y), tileImgOverlayToSet)
			$TroopsTiles.set_cellv(Vector2(x, y), get_troops_tile_id(Vector2(x, y), player_mask))
			
			if (tile_cell_data.owner == player_mask or Game.DEBUG_MODE) and tile_cell_data.turns_to_sell > 0:
				$FuncTiles.set_cellv(Vector2(x, y), id_selling_tile)
			else:
				$FuncTiles.set_cellv(Vector2(x, y), -1)

func update_tiles_bit_masks() -> void:
	if $BuildingsTiles.check_if_tile_has_changed():
		$BuildingsTiles.update_bitmask_region(Vector2(0, 0), Game.tile_map_size)
		$BuildingsTiles.update_tile_data_array()
		print("[BuildingsTiles] Tile changed...")
	
	if $OwnedTiles.check_if_tile_has_changed():
		$OwnedTiles.update_bitmask_region(Vector2(0, 0), Game.tile_map_size)
		$OwnedTiles.update_tile_data_array()
		print("[OwnedTiles] Tile changed...")
	
	if $BuildingTypesTiles.check_if_tile_has_changed():
		$BuildingTypesTiles.update_bitmask_region(Vector2(0, 0), Game.tile_map_size)
		$BuildingTypesTiles.update_tile_data_array()
		print("[BuildingTypesTiles] Tile changed...")
	
	if $BuildingTypesTilesOverlay.check_if_tile_has_changed():
		$BuildingTypesTilesOverlay.update_bitmask_region(Vector2(0, 0), Game.tile_map_size)
		$BuildingTypesTilesOverlay.update_tile_data_array()
		print("[BuildingTypesTilesOverlay] Tile changed...")
	
	if $BuildingsTilesOverlay.check_if_tile_has_changed():
		$BuildingsTilesOverlay.update_bitmask_region(Vector2(0, 0), Game.tile_map_size)
		$BuildingsTilesOverlay.update_tile_data_array()
		print("[BuildingsTilesOverlay] Tile changed...")

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
	var enemyTroopsCountInTile: int = Game.tilesObj.get_player_enemies_warriors_count(tile_pos, playerNumber)
	var alliesTroopsCountInTile: int = Game.tilesObj.get_allies_warriors_count(tile_pos, playerNumber)
	if !tile_should_be_visible(tile_pos, playerNumber) and !Game.DEBUG_MODE:
		return -1
	if upcoming_troops_data.size() > 0 and (Game.tilesObj.get_owner(tile_pos) == playerNumber or Game.DEBUG_MODE):
		return id_tile_deploying_troops
	elif troopsCountInTile >= MINIMUM_TROOPS_ICON_COUNT:
		return id_tile_own_troops
	elif alliesTroopsCountInTile >= MINIMUM_TROOPS_ICON_COUNT:
		return id_tile_ally_troops
	elif enemyTroopsCountInTile >= MINIMUM_TROOPS_ICON_COUNT:
		return id_tile_enemy_troops
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
				return id_tile_hover
			else:
				return id_tile_hover_not_allowed
		elif !Game.tilesObj.belongs_to_player(tile_pos, playerNumber):
			return id_tile_hover_not_allowed
	return id_tile_hover

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
