extends Node2D

#TODO: 
#	1) Prepare the player/civilization data object where all the data should be stored
#	2) Prepare the tile/cell data object (data that should be stored in the tile)
#	3) Prepare the object data for different troops (recruits, soldiers and Elite)

const MINIMUM_CIVILIAN_ICON_COUNT: int = 50 
const MINIMUM_TROOPS_ICON_COUNT: int = 10

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

onready var tile_map_size: Vector2 = Vector2(round(Game.SCREEN_WIDTH/Game.TILE_SIZE), round(Game.SCREEN_HEIGHT/Game.TILE_SIZE))

onready var current_game_status: int = -1
onready var current_player_turn: int = -1
var time_offset: float = 0.0
var player_in_menu: bool = false
var player_can_interact: bool = true
var tiles_data = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new();

var interactTileSelected: Vector2 = Vector2(-1, -1)
var nextInteractTileSelected: Vector2 = Vector2(-1, -1)

onready var tween: Tween

onready var default_tile: Dictionary = {
	owner = -1,
	name = "untitled",
	turns_to_improve_left = 0, #if > 0, it is upgrading
	tile_id = Game.tileTypes.getIDByName("vacio"),
	gold = 0,
	turns_to_build = 0, # if > 0, it is building
	building_id = -1, #a tile can only hold one building, so choose carefully!
	troops = [],
	upcomingTroops = [] #array with all the upcoming troops. DATA: turns to wait, owner, troop_id and amount
}

var actionTileToDo: Dictionary = {
	goldToSend = 0,
	currentTroopId=0,
	troopsToMove = []
}

var turnActionsToDo: Dictionary = {
	goldToAdd = 0
}

var current_tile_selected: Vector2 = Vector2.ZERO

###################################################
#	GODOT _READY, _PROCESS & FUNDAMENTAL FUNCTIONS
###################################################

func _ready():
	tween = Tween.new(); #useful to avoid having to add it manually in each map
	add_child(tween);
	init_menu_graphics()
	init_button_signals()
	init_tile_data()
	change_game_status(Game.STATUS.PRE_GAME)
	move_to_next_player_turn()

func _process(delta):
	var player_was_in_menu: bool = player_in_menu
	player_in_menu = is_player_menu_open()
	if player_was_in_menu != player_in_menu: #little delay to avoid player spaming actions and also bugs
		player_can_interact = false
		tween.interpolate_callback(self, 0.25, "allow_player_interact");
		tween.start()

	if player_in_menu or !player_can_interact:
		return
	update_selection_tiles()
	time_offset+=delta
	if (time_offset > 1.0/Game.GAME_FPS):
		time_offset = 0.0
		game_on()
		update_building_tiles()
		gui_update_tile_info(current_tile_selected)
		gui_update_civilization_info(current_player_turn)
		$PreGameInfo/HBoxContainer/PointsLeftText.text = str(Game.playersData[current_player_turn].selectLeft)

func is_player_menu_open() -> bool:
	return $ActionsMenu/ExtrasMenu.visible or $ActionsMenu/InGameTileActions.visible or $ActionsMenu/TilesActions.visible or $ActionsMenu/BuildingsMenu.visible

func _input(event):
	if Input.is_action_just_pressed("toggle_tile_info"):
		$TileInfo.visible = !$TileInfo.visible 
	if Input.is_action_just_pressed("toggle_civ_info"):
		$CivilizationInfo.visible = !$CivilizationInfo.visible
		
	if player_in_menu or !player_can_interact:
		return
		
	if Input.is_action_just_pressed("show_info"):
		match current_game_status:
			Game.STATUS.PRE_GAME:
				pass
			Game.STATUS.GAME_STARTED:
				game_tile_show_info()
	if Input.is_action_just_pressed("interact"):
		match current_game_status:
			Game.STATUS.PRE_GAME:
				pre_game_interact()
			Game.STATUS.GAME_STARTED:
				game_interact()

func allow_player_interact():
	player_can_interact = true

###################################
#	INIT FUNCTIONS
###################################

func init_tile_data() -> void: 
	tiles_data = []
	for x in range(tile_map_size.x):
		tiles_data.append([])
		for y in range(tile_map_size.y):
			tiles_data[x].append(default_tile.duplicate(true))

func init_button_signals():
	$ActionsMenu/InGameTileActions/VBoxContainer/Reclutar.connect("pressed", self, "gui_recruit_troops")
	$ActionsMenu/BuildingsMenu/VBoxContainer/Comprar.connect("pressed", self, "gui_buy_building")
	$ActionsMenu/BuildingsMenu/VBoxContainer/Cancelar.connect("pressed", self, "gui_exit_build_window")
	$ActionsMenu/InGameTileActions/VBoxContainer/Construir.connect("pressed", self, "gui_open_build_window")
	$ActionsMenu/InGameTileActions/VBoxContainer/VenderTile.connect("pressed", self, "gui_vender_tile")
	$ActionsMenu/InGameTileActions/VBoxContainer/UrbanizarTile.connect("pressed", self, "gui_urbanizar_tile")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.connect("text_changed", self, "gold_to_move_text_changed")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.connect("text_changed", self, "troops_to_move_text_changed")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.connect("item_selected", self, "update_troops_move_data")
	$GameInfo/HBoxContainer3/FinishTurn.connect("pressed", self, "btn_finish_turn")
	$ActionsMenu/ExtrasMenu/VBoxContainer/Cancelar.connect("pressed", self, "hide_extras_menu")
	$ActionsMenu/ExtrasMenu/VBoxContainer/ObtenerTalentos.connect("pressed", self, "give_extra_gold")
	$ActionsMenu/ExtrasMenu/VBoxContainer/ObtenerTropas.connect("pressed", self, "add_extra_troops")
	$ActionsMenu/InGameTileActions/VBoxContainer/Cancelar.connect("pressed", self, "hide_ingame_actions")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer/Cancelar.connect("pressed", self, "hide_tiles_actions")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer/Aceptar.connect("pressed", self, "accept_tiles_actions")

###################################
#	GAME LOGIC
###################################

func game_interact():
	if interactTileSelected == current_tile_selected or nextInteractTileSelected == current_tile_selected:
		return
	
	if interactTileSelected == Vector2(-1, -1) or (interactTileSelected != Vector2(-1, -1) and nextInteractTileSelected != Vector2(-1, -1)):
		if tiles_data[current_tile_selected.x][current_tile_selected.y].owner != current_player_turn:
			interactTileSelected = Vector2(-1, -1)
		else:
			interactTileSelected = current_tile_selected
		nextInteractTileSelected = Vector2(-1, -1)
	elif nextInteractTileSelected == Vector2(-1, -1):
		nextInteractTileSelected = current_tile_selected
		popup_tiles_actions()

func pre_game_interact():
	if is_tile_owned_by_player(current_tile_selected):
		if tiles_data[current_tile_selected.x][current_tile_selected.y].owner == current_player_turn:
			$ActionsMenu/ExtrasMenu.visible = true
		return
	if !player_has_capital(current_player_turn):
		give_player_capital(current_player_turn, current_tile_selected)
	elif Game.playersData[current_player_turn].selectLeft > 0 :
		give_player_rural(current_player_turn, current_tile_selected)
		Game.playersData[current_player_turn].selectLeft-=1
	
	if Game.playersData[current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()

func change_game_status(new_status: int) -> void:
	current_game_status = new_status
	match new_status:
		Game.STATUS.PRE_GAME:
			$GameInfo.visible = false
			$PreGameInfo.visible = true
		Game.STATUS.GAME_STARTED:
			$PreGameInfo.visible = false
			$GameInfo.visible = true
	print("Game Status changed to value: " + str(new_status))

func game_on() -> void:
	match current_game_status:
		Game.STATUS.PRE_GAME:
			pre_game()
		Game.STATUS.GAME_STARTED:
			pass

func pre_game() -> void:
	for i in range(Game.playersData.size()):
		if !Game.playersData[i].alive:
			continue
		if !player_has_capital(i) or Game.playersData[i].selectLeft > 0:
			return
	
	change_game_status(Game.STATUS.GAME_STARTED)

func move_to_next_player_turn() -> void: 
	if current_game_status == Game.STATUS.GAME_STARTED:
		process_turn_end(current_player_turn)
	for i in range(Game.playersData.size()):
		if i != current_player_turn and Game.playersData[i].alive:
			current_player_turn = i
			print("Player " + str(i) + " turn")
			return
		i+=1

func process_turn_end(playerNumber: int) -> void:
	update_gold_stats(playerNumber)
	process_tiles_turn_end(playerNumber)

func process_tiles_turn_end(playerNumber: int) -> void:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			process_tile_upgrade(Vector2(x, y), playerNumber)
			process_tile_builings(Vector2(x, y), playerNumber)
			process_tile_recruitments(Vector2(x, y), playerNumber)

func process_tile_recruitments(tile_pos: Vector2, playerNumber: int) -> void:
	var upcomingTroopsArray: Array = tiles_data[tile_pos.x][tile_pos.y].upcomingTroops
	var troopsToAddDict: Dictionary = {
		owner = playerNumber,
		troop_id = -1,
		amount = -1
	}
	var restartLoop: bool = true
	while restartLoop:
		restartLoop = false
		upcomingTroopsArray = tiles_data[tile_pos.x][tile_pos.y].upcomingTroops #just in case I guess
		for i in range(upcomingTroopsArray.size()):
			if upcomingTroopsArray[i].owner != playerNumber:
				continue
			upcomingTroopsArray[i].turns_left-=1
			if upcomingTroopsArray[i].turns_left <= 0:
				troopsToAddDict.troop_id = upcomingTroopsArray[i].troop_id
				troopsToAddDict.amount = upcomingTroopsArray[i].amount
				add_troops_to_tile(tile_pos, troopsToAddDict.duplicate())
				tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.remove(i)
				restartLoop = true # restart the loop as long as there are troops to remove
				break

func process_tile_builings(tile_pos: Vector2, playerNumber: int) -> void:
	if tiles_data[tile_pos.x][tile_pos.y].owner != playerNumber:
		return
	if !is_tile_building(tile_pos):
		return
	tiles_data[tile_pos.x][tile_pos.y].turns_to_build -= 1

func process_tile_upgrade(tile_pos: Vector2, playerNumber: int) -> void:
	if tiles_data[tile_pos.x][tile_pos.y].owner != playerNumber:
		return
	if !is_tile_upgrading(tile_pos):
		return
	tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left -= 1
	if tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left <= 0: #upgrade tile
		upgrade_tile(tile_pos, playerNumber)

func upgrade_tile(tile_pos: Vector2, playerNumber: int) -> void:
	tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left = 0
	
	var extra_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = Game.tileTypes.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id).min_civil_to_produce_gold
	}
	
	var nextStageTileTypeId: int = Game.tileTypes.getNextStageID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	tiles_data[tile_pos.x][tile_pos.y].tile_id = nextStageTileTypeId
	add_troops_to_tile(tile_pos, extra_population)
	
func update_gold_stats(playerNumber: int) -> void:
	var positiveBalanceTerritories: Array = []
	var negativeBalanceTerritories: Array = []
	var totalAmountOfGold: int = 0
	#Step 1, update all gold in all the tiles
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber:
				update_gold_stats_in_tile(Vector2(x, y), playerNumber)
				totalAmountOfGold+=tiles_data[x][y].gold
				if tiles_data[x][y].gold > 0.0:
					positiveBalanceTerritories.append(Vector2(x, y))
				elif tiles_data[x][y].gold < 0.0:
					negativeBalanceTerritories.append(Vector2(x, y))

	if totalAmountOfGold < 0:
		if positiveBalanceTerritories.size() <= 0 or totalAmountOfGold < -10:
			destroy_player(playerNumber)
			return
		#first, remove the capital
		
		var capitalVec2Coords: Vector2 = get_player_capital_vec2(playerNumber)
		var capitalId: int = -1
		for i in range(positiveBalanceTerritories.size()):
			if positiveBalanceTerritories[i] == capitalVec2Coords:
				capitalId = i
		if capitalId != -1:
			positiveBalanceTerritories.remove(capitalId)
		if positiveBalanceTerritories.size() <= 0:
			destroy_player(playerNumber)
			return
		tiles_data[capitalVec2Coords.x][capitalVec2Coords.y].gold += 10.0
		var rndCellToSell: int = rng.randi_range(0, positiveBalanceTerritories.size() -1)
		clear_tile(positiveBalanceTerritories[rndCellToSell])
		positiveBalanceTerritories.remove(rndCellToSell)
		print("PLAYER " + str(playerNumber) + " SOLD A TERRITORY TO AVOID BANKRUNPCY!")
		
	#Step 2, distribute gold to make sure there are no territorie with negative gold.
	var nX: int
	var nY: int
	var pX: int
	var pY: int 
	for i in range(negativeBalanceTerritories.size()):
		nX = negativeBalanceTerritories[i].x
		nY = negativeBalanceTerritories[i].y
		for j in range(positiveBalanceTerritories.size()):
			pX = positiveBalanceTerritories[j].x
			pY = positiveBalanceTerritories[j].y
			if tiles_data[pX][pY].gold <= 0:
				continue
			if tiles_data[nX][nY].gold + tiles_data[pX][pY].gold >= 0:
				tiles_data[pX][pY].gold += tiles_data[nX][nY].gold
				tiles_data[nX][nY].gold = 0
			else:
				tiles_data[nX][nY].gold += tiles_data[pX][pY].gold
				tiles_data[pX][pY].gold = 0

func update_gold_stats_in_tile(tile_pos: Vector2, playerNumber: int) ->  void:
	tiles_data[tile_pos.x][tile_pos.y].gold += get_tile_gold_gain_and_losses(tile_pos, playerNumber)

###################################
#	BOOLEANS FUNCTIONS
###################################

func player_has_capital(playerNumber: int) -> bool:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber and tiles_data[x][y].tile_id == Game.tileTypes.getIDByName("capital"):
				return true
	return false

func is_tile_owned_by_player(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner >= 0
	
func tile_is_producing_gold(tile_pos: Vector2,  playerNumber: int) -> bool:
	var civilianCountInTile: int = get_tile_civilian_count(tile_pos, playerNumber)
	var tileTypeDict: Dictionary = Game.tileTypes.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	return civilianCountInTile >= tileTypeDict.min_civil_to_produce_gold && civilianCountInTile <= tileTypeDict.max_civil_to_produce_gold

func is_recruiting_possible(tile_pos: Vector2, playerNumber: int) -> bool:
	if tiles_data[tile_pos.x][tile_pos.y].building_id == -1:
		return false
	if tiles_data[tile_pos.x][tile_pos.y].turns_to_build > 0:
		return false

	var currentBuildingType = Game.buildingTypes.getByID(tiles_data[tile_pos.x][tile_pos.y].building_id)
	if currentBuildingType.deploy_prize > get_total_gold(playerNumber):
		return false
	return true

###################################
#	DRAWING & GRAPHICS TILES
###################################

func update_building_tiles() -> void:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			var tileImgToSet = $BuildingsTiles.tile_set.find_tile_by_name(Game.tileTypes.getImg(tiles_data[x][y].tile_id))
			var buildingImgToSet = -1
			if is_tile_upgrading(Vector2(x, y)):
				$ConstructionTiles.set_cellv(Vector2(x, y), id_tile_upgrading)
			else:
				$ConstructionTiles.set_cellv(Vector2(x, y), -1)
			
			if is_tile_building(Vector2(x, y)):
				$BuildingTypesTiles.set_cellv(Vector2(x, y), id_tile_building_in_progress)
			elif tiles_data[x][y].building_id >= 0:
				buildingImgToSet = $BuildingTypesTiles.tile_set.find_tile_by_name(Game.buildingTypes.getImg(tiles_data[x][y].building_id))
				$BuildingTypesTiles.set_cellv(Vector2(x, y), buildingImgToSet)
			else:
				$BuildingTypesTiles.set_cellv(Vector2(x, y), -1)
			
			$CivilianTiles.set_cellv(Vector2(x, y), get_civilians_tile_id(Vector2(x, y), current_player_turn))
			$BuildingsTiles.set_cellv(Vector2(x, y), tileImgToSet)
			$TroopsTiles.set_cellv(Vector2(x, y), get_troops_tile_id(Vector2(x, y), current_player_turn))

func get_civilians_tile_id(tile_pos: Vector2, playerNumber: int) -> int:
	var civilianCountInTile: int = get_tile_civilian_count(tile_pos, playerNumber)
	var tileTypeDict: Dictionary = Game.tileTypes.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	if civilianCountInTile < MINIMUM_CIVILIAN_ICON_COUNT:
		return -1
	elif civilianCountInTile >= MINIMUM_CIVILIAN_ICON_COUNT and civilianCountInTile < tileTypeDict.min_civil_to_produce_gold:
		return id_tile_underpopulation
	elif civilianCountInTile >= tileTypeDict.min_civil_to_produce_gold && civilianCountInTile <= tileTypeDict.max_civil_to_produce_gold:
		return id_tile_civilians

	return id_tile_overpopulation

func get_troops_tile_id(tile_pos: Vector2, playerNumber: int) -> int:
	var troopsCountInTile: int = get_tile_troops_count(tile_pos, playerNumber)
	if tiles_data[tile_pos.x][tile_pos.y].upcomingTroops.size() > 0:
		return id_tile_deploying_troops
	elif troopsCountInTile > MINIMUM_TROOPS_ICON_COUNT:
		return id_tile_troops
	return -1

func update_selection_tiles() -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var tile_selected: Vector2 = $SelectionTiles.world_to_map(mouse_pos)
	if current_tile_selected == tile_selected:
		return
	
	if tile_selected.x >= tile_map_size.x or tile_selected.x < 0 or tile_selected.y >= tile_map_size.y or tile_selected.y < 0:
		return

	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if interactTileSelected == Vector2(x, y):
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_action_begin)
			elif nextInteractTileSelected == Vector2(x, y):
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_action_end)
			elif Vector2(x, y) == tile_selected:
				$SelectionTiles.set_cellv(Vector2(x, y), get_tile_selected_img_id(Vector2(x, y)))
			else:
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_non_selected)
	current_tile_selected = tile_selected

func get_tile_selected_img_id(tile_pos: Vector2) -> int:
	if current_game_status == Game.STATUS.GAME_STARTED:
		if tiles_data[tile_pos.x][tile_pos.y].owner != current_player_turn:
			return id_tile_not_allowed
	return id_tile_selected


###################################
#	GETTERS
###################################

func get_total_gold_gain_and_losses(playerNumber: int) -> float:
	var goldGains: float = 0
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			goldGains += get_tile_gold_gain_and_losses(Vector2(x, y), playerNumber)
	
	return goldGains

func get_tile_gold_gain_and_losses(tile_pos: Vector2, playerNumber: int) -> float:
	if tiles_data[tile_pos.x][tile_pos.y].owner != playerNumber: #fixme: calculate battle stuff here later
		return 0.0
	var goldGains: float = 0
	if tile_is_producing_gold(tile_pos, playerNumber):
		goldGains += float(Game.tileTypes.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id).gold_to_produce)
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		goldGains -= float(Game.troopTypes.getByID(troopDict.troop_id).idle_cost_per_turn*troopDict.amount)/1000.0
	return goldGains

func get_tile_troops_count(tile_pos: Vector2, playerNumber: int) -> int:
	var tropsCount: int = 0
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if Game.troopTypes.getByID(troopDict.troop_id).is_warrior:
			tropsCount+=troopDict.amount

	return tropsCount

func get_tile_civilian_count(tile_pos: Vector2, playerNumber: int) -> int:
	var civilianCount: int = 0
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		if !Game.troopTypes.getByID(troopDict.troop_id).is_warrior:
			civilianCount+=troopDict.amount

	return civilianCount

func get_player_capital_vec2(playerNumber: int) -> Vector2:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber and tiles_data[x][y].tile_id == Game.tileTypes.getIDByName("capital"):
				return Vector2(x, y)
	return Vector2(-1, -1)

func get_player_tiles_count(playerNumber: int) -> int:
	var count: int = 0
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber:
				count+=1
	return count

func get_total_gold(playerNumber: int) -> float:
	var totalGold: float = 0.0
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber:
				totalGold += tiles_data[x][y].gold
	return floor(totalGold)

func get_tile_strength(tilePos: Vector2, playerNumber: int) -> float:
	var totalStrength: float = 0.0
	var totalTroops: int = 0
	var totalHealth: int = 0
	var averageHealth: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		totalHealth += Game.troopTypes.getByID(troopDict.troop_id).health*troopDict.amount
		totalTroops += troopDict.amount
		var averageTroopDamage: float = (Game.troopTypes.getByID(troopDict.troop_id).damage.x + Game.troopTypes.getByID(troopDict.troop_id).damage.y)/2.0
		totalStrength += averageTroopDamage*troopDict.amount

	if totalTroops > 0:
		averageHealth = float(totalHealth) / float(totalTroops)
	return round(totalStrength*averageHealth/200.0)

func get_total_strength(playerNumber: int) -> float:
	var totalStrength: float = 0.0
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			totalStrength+= get_tile_strength(Vector2(x, y), playerNumber)
	
	return totalStrength

func get_civ_population_info(playerNumber: int) -> Array:
	var troopsInfo: Array = []
	var troopExists: bool = false
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
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

###################################
#	UTIL & STUFF
###################################

func is_tile_upgrading(tile_pos: Vector2):
	return tiles_data[tile_pos.x][tile_pos.y].turns_to_improve_left > 0

func is_tile_building(tile_pos: Vector2):
	return tiles_data[tile_pos.x][tile_pos.y].turns_to_build > 0

func can_tile_be_upgraded(tile_pos: Vector2, playerNumber: int):
	if tiles_data[tile_pos.x][tile_pos.y].owner != playerNumber:
		return false
	if is_tile_upgrading(tile_pos):
		return false
	var tileTypeDict = Game.tileTypes.getByID(tiles_data[tile_pos.x][tile_pos.y].tile_id)
	if get_total_gold(playerNumber) < tileTypeDict.improve_prize:
		return false
	
	return Game.tileTypes.canBeUpgraded(tiles_data[tile_pos.x][tile_pos.y].tile_id)

func give_player_a_tile(playerNumber: int, tile_pos: Vector2, tile_type_id: int, add_gold: int, add_troops: Dictionary) -> void:
	tiles_data[tile_pos.x][tile_pos.y].owner = playerNumber
	tiles_data[tile_pos.x][tile_pos.y].gold += add_gold
	tiles_data[tile_pos.x][tile_pos.y].tile_id = tile_type_id
	tiles_data[tile_pos.x][tile_pos.y].name =  "Territorio #" + str(get_player_tiles_count(playerNumber)-1)
	add_troops_to_tile(tile_pos, add_troops)

func add_troops_to_tile(tile_pos: Vector2, add_troops: Dictionary) -> void:
	for i in range(tiles_data[tile_pos.x][tile_pos.y].troops.size()):
		if tiles_data[tile_pos.x][tile_pos.y].troops[i].owner == add_troops.owner and tiles_data[tile_pos.x][tile_pos.y].troops[i].troop_id == add_troops.troop_id:
			tiles_data[tile_pos.x][tile_pos.y].troops[i].amount += add_troops.amount
			return
	tiles_data[tile_pos.x][tile_pos.y].troops.append(add_troops)


func give_player_capital(playerNumber: int, tile_pos: Vector2) ->void:
	var starting_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = 5000
	}
	give_player_a_tile(playerNumber, tile_pos, Game.tileTypes.getIDByName("capital"), 0, starting_population)
	tiles_data[tile_pos.x][tile_pos.y].name = "Capital"

func give_player_rural(playerNumber: int, tile_pos: Vector2) ->void:
	var starting_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = 1000
	}
	give_player_a_tile(playerNumber, tile_pos, Game.tileTypes.getIDByName("rural"), 0, starting_population)

func destroy_player(playerNumber: int):
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber:
				clear_tile(Vector2(x, y))
	Game.playersData[playerNumber].alive = false
	print("PLAYER " + str(playerNumber) + " LOST!")

func clear_tile(tile_pos: Vector2):
	tiles_data[tile_pos.x][tile_pos.y].owner = -1
	tiles_data[tile_pos.x][tile_pos.y].name = "untitled"
	tiles_data[tile_pos.x][tile_pos.y].tile_id = Game.tileTypes.getIDByName("vacio")
	tiles_data[tile_pos.x][tile_pos.y].gold = 0
	tiles_data[tile_pos.x][tile_pos.y].troops.clear()

###################################
#	UI 
###################################

func init_menu_graphics():
	$ActionsMenu/InGameTileActions.visible = false
	$ActionsMenu/ExtrasMenu.visible = false
	$ActionsMenu/TilesActions.visible = false
	$ActionsMenu/BuildingsMenu.visible = false

func update_build_menu():
	var getTotalGoldAvailable: int = get_total_gold(current_player_turn)
	$ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.clear()
	var buildingTypesList: Array = Game.buildingTypes.getList() #Gives a copy, not the original list edit is safe
	for i in range(buildingTypesList.size()):
		if getTotalGoldAvailable >= buildingTypesList[i].buy_prize:
			$ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.add_item(buildingTypesList[i].name, i)
	
	update_build_menu_price($ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.selected)

func update_build_menu_price(index: int):
	var currentBuildingTypeSelected = Game.buildingTypes.getByID(index)
	$ActionsMenu/BuildingsMenu/VBoxContainer/HBoxContainer/BuilidngPriceText.text = str(currentBuildingTypeSelected.buy_prize)

func check_if_player_can_buy_buildings(playerNumber: int) -> bool:
	var getTotalGoldAvailable: int = get_total_gold(playerNumber)
	var buildingTypesList: Array = Game.buildingTypes.getList()
	for i in range(buildingTypesList.size()):
		if getTotalGoldAvailable >= buildingTypesList[i].buy_prize:
			return true
	return false

func gold_to_move_text_changed():
	var goldAvailable: int = int($ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosDisponibles.text)
	var goldToMove: int = int($ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.text)
	goldToMove = int(clamp(float(goldToMove), 0.0, float(goldAvailable)))
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.text = str(goldToMove)
	actionTileToDo.goldToSend = goldToMove

func troops_to_move_text_changed():
	var troopAvailable: int = int($ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.text)
	var troopsToMove: int = int($ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.text)
	troopsToMove = int(clamp(float(troopsToMove), 0.0, float(troopAvailable)))
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.text = str(troopsToMove)
	for troopInActionTileDict in actionTileToDo.troopsToMove:
		if actionTileToDo.currentTroopId == troopInActionTileDict.troop_id:
			troopInActionTileDict.amountToMove = troopsToMove
			return

func popup_tiles_actions():
	$ActionsMenu/TilesActions.visible = true
	clear_action_tile_to_do()
	update_tiles_actions_data()

func clear_action_tile_to_do():
	actionTileToDo.goldToSend = 0
	actionTileToDo.currentTroopId = -1
	actionTileToDo.troopsToMove.clear()
	var startX: int = interactTileSelected.x
	var startY: int = interactTileSelected.y
	for troopDict in tiles_data[startX][startY].troops:
		if troopDict.owner != current_player_turn:
			continue
		if actionTileToDo.currentTroopId == -1:
			actionTileToDo.currentTroopId = troopDict.troop_id
		actionTileToDo.troopsToMove.append( { troop_id = troopDict.troop_id, amountToMove = 0})

func update_tiles_actions_data():
	var startX: int = interactTileSelected.x
	var startY: int = interactTileSelected.y
	var endX: int = nextInteractTileSelected.x
	var endY: int = nextInteractTileSelected.y
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosDisponibles.text = str(tiles_data[startX][startY].gold)
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.text = str(actionTileToDo.goldToSend)
	
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.clear()
	for troopDict in tiles_data[startX][startY].troops:
		if troopDict.owner != current_player_turn:
			continue
		$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.add_item(Game.troopTypes.getByID(troopDict.troop_id).name, troopDict.troop_id)
	update_troops_move_data($ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.selected)

func game_tile_show_info():
	if tiles_data[current_tile_selected.x][current_tile_selected.y].owner != current_player_turn:
		return
	
	$ActionsMenu/InGameTileActions/VBoxContainer/VenderTile.visible = Game.tileTypes.canBeSold(tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id)
	#if tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id ==  Game.tileTypes.getIDByName("capital"):
	$ActionsMenu/InGameTileActions/VBoxContainer/UrbanizarTile.visible = can_tile_be_upgraded(current_tile_selected, current_player_turn)
	$ActionsMenu/InGameTileActions/VBoxContainer/Construir.visible = check_if_player_can_buy_buildings(current_player_turn)
	$ActionsMenu/InGameTileActions/VBoxContainer/Reclutar.visible = is_recruiting_possible(current_tile_selected, current_player_turn)
	$ActionsMenu/InGameTileActions.visible = true


func gui_update_civilization_info(playerNumber: int) -> void:
	$CivilizationInfo/VBoxContainer/HBoxContainer5/CivilizationText.text = str(Game.playersData[playerNumber].civilizationName)
	$CivilizationInfo/VBoxContainer/HBoxContainer/TotTalentosText.text = str(get_total_gold(playerNumber))
	$CivilizationInfo/VBoxContainer/HBoxContainer2/StrengthText.text = str(get_total_strength(playerNumber))
	$CivilizationInfo/VBoxContainer/HBoxContainer6/GainText.text = str(get_total_gold_gain_and_losses(playerNumber))

	var civilizationTroopsInfo: Array = get_civ_population_info(playerNumber)
	var populationStr: String = ""
	
	for troopDict in civilizationTroopsInfo:
		populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	
	$CivilizationInfo/VBoxContainer/HBoxContainer4/TotPopulationText.text = populationStr


func gui_update_tile_info(tile_pos: Vector2) -> void:

	if current_game_status == Game.STATUS.PRE_GAME:
		$GameInfo/HBoxContainer2/TurnText.text = "PRE-GAME: " + str(Game.playersData[current_player_turn].civilizationName)
	elif current_game_status == Game.STATUS.GAME_STARTED:
		$GameInfo/HBoxContainer2/TurnText.text = str(Game.playersData[current_player_turn].civilizationName)
	else:
		$GameInfo/HBoxContainer2/TurnText.text = "??"

	
	$TileInfo/VBoxContainer/HBoxContainer5/TileName.text = tiles_data[tile_pos.x][tile_pos.y].name
	if tiles_data[tile_pos.x][tile_pos.y].owner == -1:
		$TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = "No info"
	else:
		$TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = str(Game.playersData[tiles_data[tile_pos.x][tile_pos.y].owner].civilizationName)
	$TileInfo/VBoxContainer/HBoxContainer2/Amount.text = str(floor(tiles_data[tile_pos.x][tile_pos.y].gold))
	
	$TileInfo/VBoxContainer/HBoxContainer6/StrengthText.text = str(get_tile_strength(tile_pos, current_player_turn))
	$TileInfo/VBoxContainer/HBoxContainer7/GainsText.text = str(get_tile_gold_gain_and_losses(tile_pos, current_player_turn))
	
	var populationStr: String = ""
	
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	
	$TileInfo/VBoxContainer/HBoxContainer4/PopulationText.text = populationStr

###################################
#	BUTTONS & SIGNALS
###################################

func gui_recruit_troops():

	assert(is_recruiting_possible(current_tile_selected, current_player_turn))
	
	var x: int = current_tile_selected.x
	var y: int = current_tile_selected.y
	var currentBuildingTypeSelected = Game.buildingTypes.getByID(tiles_data[x][y].building_id)
	
	#step 1: get the types of troops to recruit and the amount
	var idTroopsToRecruit: int = currentBuildingTypeSelected.id_troop_generate
	var ammountOfTroopsToRecruit: int = 0
	
	var upcomingTroopsDict: Dictionary = {
		owner = current_player_turn,
		troop_id= currentBuildingTypeSelected.id_troop_generate,
		amount = currentBuildingTypeSelected.deploy_amount,
		turns_left = currentBuildingTypeSelected.turns_to_deploy_troops
	}
	tiles_data[x][y].gold -= currentBuildingTypeSelected.deploy_prize
	tiles_data[x][y].upcomingTroops.append(upcomingTroopsDict)
	$ActionsMenu/InGameTileActions.visible = false
	
func gui_buy_building():
	var selectedBuildTypeId: int = int($ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.selected)
	if selectedBuildTypeId< 0:
		return
	var currentBuildingTypeSelected = Game.buildingTypes.getByID(selectedBuildTypeId)
	tiles_data[current_tile_selected.x][current_tile_selected.y].gold -= currentBuildingTypeSelected.buy_prize
	tiles_data[current_tile_selected.x][current_tile_selected.y].turns_to_build = currentBuildingTypeSelected.turns_to_build
	tiles_data[current_tile_selected.x][current_tile_selected.y].building_id = selectedBuildTypeId
	$ActionsMenu/BuildingsMenu.visible = false

func gui_exit_build_window():
	$ActionsMenu/ExtrasMenu.visible = true
	$ActionsMenu/BuildingsMenu.visible = false

func gui_open_build_window():
	$ActionsMenu/BuildingsMenu.visible = true
	$ActionsMenu/ExtrasMenu.visible = false
	$ActionsMenu/InGameTileActions.visible = false
	$ActionsMenu/TilesActions.visible = false
	update_build_menu()

func gui_urbanizar_tile():
	var tile_type_id: int = tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id
	if is_tile_upgrading(current_tile_selected):
		print("Already upgrading!")
		return
	var tileTypeData = Game.tileTypes.getByID(tile_type_id)
	assert(Game.tileTypes.canBeUpgraded(tile_type_id))
	if tileTypeData.improve_prize > get_total_gold(current_player_turn):
		print("Not enough money to improve!")
		return
	tiles_data[current_tile_selected.x][current_tile_selected.y].gold -= tileTypeData.improve_prize
	tiles_data[current_tile_selected.x][current_tile_selected.y].turns_to_improve_left = tileTypeData.turns_to_improve
	$ActionsMenu/InGameTileActions.visible = false

func update_troops_move_data( var index: int ):
	actionTileToDo.currentTroopId = index
	var startX: int = interactTileSelected.x
	var startY: int = interactTileSelected.y
	for troopInActionTileDict in actionTileToDo.troopsToMove:
		if actionTileToDo.currentTroopId == troopInActionTileDict.troop_id:
			$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.text = str(troopInActionTileDict.amountToMove)
			break
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.text = "0"
	for troopDict in tiles_data[startX][startY].troops:
		if troopDict.troop_id == index:
			$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.text = str(troopDict.amount)
			break

func hide_tiles_actions():
	if !player_in_menu or !player_can_interact:
		return
	$ActionsMenu/TilesActions.visible = false

func accept_tiles_actions():
	if !player_in_menu or !player_can_interact:
		return
	execute_tile_action()
	$ActionsMenu/TilesActions.visible = false

func execute_tile_action():
	var startX: int = interactTileSelected.x
	var startY: int = interactTileSelected.y
	var endX: int = nextInteractTileSelected.x
	var endY: int = nextInteractTileSelected.y
	var troopToAddExists: bool = false
	
	#First, remove gold and troops from the starting cell
	tiles_data[startX][startY].gold -= actionTileToDo.goldToSend
	for startTroopDict in tiles_data[startX][startY].troops:
		if startTroopDict.owner != current_player_turn:
			continue
		for toMoveTroopDict in actionTileToDo.troopsToMove:
			if startTroopDict.troop_id == toMoveTroopDict.troop_id:
				startTroopDict.amount -= toMoveTroopDict.amountToMove
	#Second move and add troops for the ending cell
	tiles_data[endX][endY].gold += actionTileToDo.goldToSend
	for toMoveTroopDict in actionTileToDo.troopsToMove:
		if toMoveTroopDict.amountToMove <= 0:
			continue
		troopToAddExists = false
		for endTroopDict in tiles_data[endX][endY].troops:
			if endTroopDict.owner != current_player_turn:
				continue
			if endTroopDict.troop_id == toMoveTroopDict.troop_id:
				endTroopDict.amount += toMoveTroopDict.amountToMove
				troopToAddExists = true
		if !troopToAddExists:
			tiles_data[endX][endY].troops.append({owner = current_player_turn, troop_id = toMoveTroopDict.troop_id, amount = toMoveTroopDict.amountToMove})

func hide_ingame_actions():
	if !player_in_menu or !player_can_interact:
		return
	$ActionsMenu/InGameTileActions.visible = false
	
func hide_extras_menu():
	if !player_in_menu or !player_can_interact:
		return
	$ActionsMenu/ExtrasMenu.visible = false

func btn_finish_turn():
	if player_in_menu or !player_can_interact:
		return
	if current_game_status == Game.STATUS.GAME_STARTED:
		move_to_next_player_turn()

func give_extra_gold():
	if !player_in_menu or !player_can_interact:
		return
	tiles_data[current_tile_selected.x][current_tile_selected.y].gold += 10
	$ActionsMenu/ExtrasMenu.visible = false
	Game.playersData[current_player_turn].selectLeft-=1
	if Game.playersData[current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()

func add_extra_troops():
	if !player_in_menu or !player_can_interact:
		return
	var extraRecruits: Dictionary = {
		owner = current_player_turn,
		troop_id = Game.troopTypes.getIDByName("recluta"),
		amount = 1000
	}
	add_troops_to_tile(current_tile_selected, extraRecruits)
	$ActionsMenu/ExtrasMenu.visible = false
	Game.playersData[current_player_turn].selectLeft-=1
	if Game.playersData[current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()
