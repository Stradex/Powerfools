class_name WorldGameNode
extends Node2D

#TODO: 
#	1) Prepare the player/civilization data object where all the data should be stored
#	2) Prepare the tile/cell data object (data that should be stored in the tile)
#	3) Prepare the object data for different troops (recruits, soldiers and Elite)

const MIN_ACTIONS_PER_TURN: int = 3
const MAX_DEPLOYEMENTS_PER_TILE: int = 1
const MININUM_TROOPS_TO_FIGHT: int = 5
const EXTRA_CIVILIANS_TO_GAIN_CONQUER: int = 500

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
onready var id_tile_battle: int = $ConstructionTiles.tile_set.find_tile_by_name('battle_in_progress')
onready var id_not_owned_tile: int = $OwnedTiles.tile_set.find_tile_by_name('tile_not_owned')
onready var tile_map_size: Vector2 = Vector2(round(Game.SCREEN_WIDTH/Game.TILE_SIZE), round(Game.SCREEN_HEIGHT/Game.TILE_SIZE))

onready var current_game_status: int = -1
onready var current_player_turn: int = -1
var time_offset: float = 0.0
var player_in_menu: bool = false
var player_can_interact: bool = true
var actions_available: int = MIN_ACTIONS_PER_TURN
var rng: RandomNumberGenerator = RandomNumberGenerator.new();

var interactTileSelected: Vector2 = Vector2(-1, -1)
var nextInteractTileSelected: Vector2 = Vector2(-1, -1)

onready var tween: Tween

var actionTileToDo: Dictionary = {
	goldToSend = 0,
	currentTroopId=0,
	troopsToMove = []
}

var current_tile_selected: Vector2 = Vector2.ZERO

###################################################
# GODOT _READY, _PROCESS & FUNDAMENTAL FUNCTIONS
###################################################

func _ready():
	tween = Tween.new(); #useful to avoid having to add it manually in each map
	add_child(tween);
	$UI.init_gui(self)
	if Game.tilesObj:
		Game.tilesObj.clear()
	Game.tilesObj = TileGameObject.new(tile_map_size, Game.tileTypes.getIDByName('vacio'), Game.tileTypes, Game.troopTypes, Game.buildingTypes)
	change_game_status(Game.STATUS.PRE_GAME)
	move_to_next_player_turn()

func _process(delta):
	var player_was_in_menu: bool = player_in_menu
	player_in_menu = is_player_menu_open()
	if player_was_in_menu != player_in_menu: #little delay to avoid player spaming actions and also bugs
		player_can_interact = false
		tween.interpolate_callback(self, 0.25, "allow_player_interact")
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
		$UI/HUD/GameInfo/HBoxContainer/ActionsLeftText.text = str(actions_available)
		$UI/HUD/PreGameInfo/HBoxContainer/PointsLeftText.text = str(Game.playersData[current_player_turn].selectLeft)

func _input(event):
	if Input.is_action_just_pressed("toggle_tile_info"):
		$UI/HUD/TileInfo.visible = !$UI/HUD/TileInfo.visible 
	if Input.is_action_just_pressed("toggle_civ_info"):
		$UI/HUD/CivilizationInfo.visible = !$UI/HUD/CivilizationInfo.visible
		
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


###################################
#	GAME LOGIC
###################################

func game_interact():
	if interactTileSelected == current_tile_selected or nextInteractTileSelected == current_tile_selected:
		return
	
	
	if interactTileSelected == Vector2(-1, -1) or (interactTileSelected != Vector2(-1, -1) and nextInteractTileSelected != Vector2(-1, -1)):
		if !Game.tilesObj.belongs_to_player(current_tile_selected, current_player_turn):
			interactTileSelected = Vector2(-1, -1)
		else:
			interactTileSelected = current_tile_selected
		nextInteractTileSelected = Vector2(-1, -1)
	elif nextInteractTileSelected == Vector2(-1, -1):
		if Game.tilesObj.is_next_to_tile(interactTileSelected, current_tile_selected):
			nextInteractTileSelected = current_tile_selected
			popup_tiles_actions()
		else:
			interactTileSelected = Vector2(-1, -1)

func pre_game_interact():
	if Game.tilesObj.is_owned_by_player(current_tile_selected):
		if Game.tilesObj.belongs_to_player(current_tile_selected, current_player_turn):
			$UI/ActionsMenu/ExtrasMenu.visible = true
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
			$UI/HUD/GameInfo.visible = false
			$UI/HUD/PreGameInfo.visible = true
		Game.STATUS.GAME_STARTED:
			$UI/HUD/PreGameInfo.visible = false
			$UI/HUD/GameInfo.visible = true
			process_unused_tiles()
	print("Game Status changed to value: " + str(new_status))

func process_unused_tiles() -> void:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if !Game.tilesObj.is_owned_by_player(Vector2(x, y)):
				add_tribal_society_to_tile(Vector2(x, y))

func add_tribal_society_to_tile(cell: Vector2) -> void:
	Game.tilesObj.set_cell_gold(cell, round(rand_range(5.0, 20.0)))
	var troopsToAdd: Dictionary = {
		owner = -1,
		troop_id = Game.troopTypes.getIDByName("recluta"),
		amount = int(rand_range(250.0, 2000.0))
	}
	var civiliansToAdd: Dictionary = {
		owner = -1,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = int(rand_range(500.0, 5000.0))
	}
	Game.tilesObj.add_troops(cell, troopsToAdd)
	Game.tilesObj.add_troops(cell, civiliansToAdd)

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
			update_actions_available()
			print("Player " + str(i) + " turn")
			return
		i+=1

	update_actions_available()

func update_actions_available() -> void:
	if current_game_status == Game.STATUS.GAME_STARTED:
		actions_available = int(round(Game.tilesObj.number_of_productive_territories(current_player_turn)/3.0 + 0.5))
		if actions_available < MIN_ACTIONS_PER_TURN:
			actions_available = MIN_ACTIONS_PER_TURN

func process_turn_end(playerNumber: int) -> void:
	update_gold_stats(playerNumber)
	process_tiles_turn_end(playerNumber)
	if did_player_lost(playerNumber):
		destroy_player(playerNumber)

func process_tiles_turn_end(playerNumber: int) -> void:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			process_tile_upgrade(Vector2(x, y), playerNumber)
			process_tile_builings(Vector2(x, y), playerNumber)
			process_tile_recruitments(Vector2(x, y), playerNumber)
			process_tile_battles(Vector2(x, y))
			update_tile_owner(Vector2(x, y))


func update_tile_owner(cell: Vector2) -> void:
	var playersInTile: int = Game.tilesObj.number_of_players_in_cell(cell)
	if playersInTile > 1:
		return 
	var tile_cell_troops = Game.tilesObj.get_troops(cell)
	for troopDict in tile_cell_troops:
		if troopDict.amount <= 0:
			continue
		Game.tilesObj.set_cell_owner(cell, troopDict.owner)
		break

func process_tile_battles(tile_pos: Vector2) -> void:
	if !Game.tilesObj.is_cell_in_battle(tile_pos):
		return
	var damageMultiplier: float = rand_range(0.25, 1.0) #some battles can last more than others
	#Step 1: calculate Damage to do by each army
	var damageToDoArray: Array = []
	var civiliansKilledBy: Array = []
	var tile_cell_troops = Game.tilesObj.get_troops(tile_pos)
	for troopDict in tile_cell_troops:
		var existsInArray: bool = false
		var damageToApply: float = Game.troopTypes.calculateTroopDamage(troopDict.troop_id)*troopDict.amount*damageMultiplier
		for damageToDo in damageToDoArray:
			if damageToDo.owner == troopDict.owner:
				damageToDo.amount += damageToApply
				existsInArray = true
		if !existsInArray:
			damageToDoArray.append({owner = troopDict.owner, amount = damageToApply})
	
	#Step2: Apply damage to other armies
	for damageToDo in damageToDoArray:
		#Calculate how much damage to apply to each troop
		var enemiesWarriorStrength: Array
		var enemiesTotalStrength: float = 0.0
		for troopDict in tile_cell_troops:
			if damageToDo.owner == troopDict.owner:
				continue
			if troopDict.amount <= 0:
				continue
			var troopStrength: float = Game.tilesObj.get_troop_cell_strength(tile_pos, troopDict.owner, troopDict.troop_id)
			enemiesWarriorStrength.append(troopStrength)
			enemiesTotalStrength += troopStrength
		
		#apply the damage now to enemy troops
		var initial_damage_to_do: float = damageToDo.amount
		var i: int = 0
		for troopDict in tile_cell_troops:
			if damageToDo.owner == troopDict.owner:
				continue
			if troopDict.amount <= 0:
				continue

			var individualTroopHealth: float = Game.troopTypes.getByID(troopDict.troop_id).health
			var percentOfDamageToApply: float = float(enemiesWarriorStrength[i]/enemiesTotalStrength)
			var damageToApplyToThisTroop: float = initial_damage_to_do*percentOfDamageToApply
			var troopsToKill: int = round(damageToApplyToThisTroop/individualTroopHealth)
			Game.tilesObj.set_troops_amount_in_cell(tile_pos, troopDict.owner, troopDict.troop_id, troopDict.amount-troopsToKill)
			
			if !Game.troopTypes.getByID(troopDict.troop_id).is_warrior: #adding to the Civilians Killed array for future slaves in case of battle is finished this round
				var addToArray: bool = true
				for civiliansKilledDictionary in civiliansKilledBy:
					if civiliansKilledDictionary.attacker == damageToDo.owner:
						addToArray = false
						civiliansKilledDictionary.amount += troopsToKill
				if addToArray:
					civiliansKilledBy.append({attacker = damageToDo.owner, amount = troopsToKill})
				
			if troopDict.amount < MININUM_TROOPS_TO_FIGHT: #avoid problems
				troopDict.amount = 0
			i+=1
	#Step4: Check if battle is over
	if !Game.tilesObj.is_cell_in_battle(tile_pos):
		var playerWhoWonId: int = -1
		for troopDict in tile_cell_troops:
			if troopDict.amount <= 0:
				continue
			playerWhoWonId = troopDict.owner
			
		var slaves_to_gain: int = 0
		for civiliansKilledDictionary in civiliansKilledBy:
			if civiliansKilledDictionary.attacker == playerWhoWonId:
				slaves_to_gain = int(rand_range(civiliansKilledDictionary.amount*0.25, civiliansKilledDictionary.amount*0.75))
				break
				
		var extra_population: Dictionary = {
			owner = playerWhoWonId,
			troop_id = Game.troopTypes.getIDByName("civil"),
			amount = EXTRA_CIVILIANS_TO_GAIN_CONQUER+slaves_to_gain
		}
		Game.tilesObj.set_cell_owner(tile_pos, playerWhoWonId)
		Game.tilesObj.add_troops(tile_pos, extra_population)


func process_tile_recruitments(tile_pos: Vector2, playerNumber: int) -> void:
	var upcomingTroopsArray: Array = Game.tilesObj.get_upcoming_troops(tile_pos)
	var troopsToAddDict: Dictionary = {
		owner = playerNumber,
		troop_id = -1,
		amount = -1
	}
	var restartLoop: bool = true
	while restartLoop:
		restartLoop = false
		upcomingTroopsArray = Game.tilesObj.get_upcoming_troops(tile_pos) #just in case I guess
		for i in range(upcomingTroopsArray.size()):
			if upcomingTroopsArray[i].owner != playerNumber:
				continue
			upcomingTroopsArray[i].turns_left-=1
			if upcomingTroopsArray[i].turns_left <= 0:
				troopsToAddDict.troop_id = upcomingTroopsArray[i].troop_id
				troopsToAddDict.amount = upcomingTroopsArray[i].amount
				Game.tilesObj.add_troops(tile_pos, troopsToAddDict.duplicate())
				Game.tilesObj.remove_upcoming_troops_index(tile_pos, i)
				restartLoop = true # restart the loop as long as there are troops to remove
				break

func process_tile_builings(tile_pos: Vector2, playerNumber: int) -> void:
	if !Game.tilesObj.belongs_to_player(tile_pos, playerNumber):
		return
	if !Game.tilesObj.is_building(tile_pos):
		return
	Game.tilesObj.decrease_turns_to_build(tile_pos)

func process_tile_upgrade(tile_pos: Vector2, playerNumber: int) -> void:
	if !Game.tilesObj.belongs_to_player(tile_pos, playerNumber):
		return
	if !Game.tilesObj.is_upgrading(tile_pos):
		return
	Game.tilesObj.decrease_turns_to_improve(tile_pos)
	if Game.tilesObj.get_turns_to_improve(tile_pos) <= 0: #upgrade tile
		Game.tilesObj.upgrade_cell(tile_pos, playerNumber)

func update_gold_stats(playerNumber: int) -> void:
	var positiveBalanceTerritories: Array = []
	var negativeBalanceTerritories: Array = []
	var totalAmountOfGold: int = 0
	#Step 1, update all gold in all the tiles
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if Game.tilesObj.belongs_to_player(Vector2(x, y), playerNumber):
				update_gold_stats_in_tile(Vector2(x, y), playerNumber)
				var cellGold: float = Game.tilesObj.get_cell_gold(Vector2(x, y))
				totalAmountOfGold+= cellGold
				if cellGold > 0.0:
					positiveBalanceTerritories.append(Vector2(x, y))
				elif cellGold < 0.0:
					negativeBalanceTerritories.append(Vector2(x, y))

	if totalAmountOfGold < 0:
		if positiveBalanceTerritories.size() <= 0 or totalAmountOfGold < -10:
			destroy_player(playerNumber)
			return
		#first, remove the capital
		
		var capitalVec2Coords: Vector2 = Game.tilesObj.get_player_capital_vec2(playerNumber)
		var capitalId: int = -1
		for i in range(positiveBalanceTerritories.size()):
			if positiveBalanceTerritories[i] == capitalVec2Coords:
				capitalId = i
		if capitalId != -1:
			positiveBalanceTerritories.remove(capitalId)
		if positiveBalanceTerritories.size() <= 0:
			destroy_player(playerNumber)
			return
		Game.tilesObj.add_cell_gold(capitalVec2Coords, 10.0)
		var rndCellToSell: int = rng.randi_range(0, positiveBalanceTerritories.size() -1)
		Game.tilesObj.clear_cell(positiveBalanceTerritories[rndCellToSell])
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
			var gold_available: float = Game.tilesObj.get_cell_gold(positiveBalanceTerritories[j])
			var gold_debt: float = Game.tilesObj.get_cell_gold(negativeBalanceTerritories[i])
			if gold_available <= 0:
				continue
			if gold_debt + gold_available >= 0:
				Game.tilesObj.add_cell_gold(positiveBalanceTerritories[j], gold_debt)
				Game.tilesObj.set_cell_gold(negativeBalanceTerritories[i], 0.0)
			else:
				Game.tilesObj.add_cell_gold(negativeBalanceTerritories[i], gold_available)
				Game.tilesObj.set_cell_gold(positiveBalanceTerritories[j], 0.0)

func update_gold_stats_in_tile(tile_pos: Vector2, playerNumber: int) ->  void:
	Game.tilesObj.add_cell_gold(tile_pos, Game.tilesObj.get_gold_gain_and_losses(tile_pos, playerNumber))

###################################
#	BOOLEANS FUNCTIONS
###################################

func is_player_menu_open() -> bool:
	return $UI.is_a_menu_open()

func did_player_lost(playerNumber: int) -> bool:
	return !player_has_capital(playerNumber)

func player_has_capital(playerNumber: int) -> bool:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if Game.tilesObj.belongs_to_player(Vector2(x, y), playerNumber) and Game.tilesObj.compare_tile_type_name(Vector2(x, y), "capital"):
				return true
	return false

func is_recruiting_possible(tile_pos: Vector2, playerNumber: int) -> bool:
	var tile_cell_data: Dictionary = Game.tilesObj.get_cell(tile_pos)
	if tile_cell_data.building_id == -1:
		return false
	if tile_cell_data.turns_to_build > 0:
		return false
	var currentBuildingType = Game.buildingTypes.getByID(tile_cell_data.building_id)
	if currentBuildingType.deploy_prize > Game.tilesObj.get_total_gold(playerNumber):
		return false
	if tile_cell_data.upcomingTroops.size() >= MAX_DEPLOYEMENTS_PER_TILE: 
		return false
	return true

###################################
#	DRAWING & GRAPHICS TILES
###################################

func update_building_tiles() -> void:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			var tile_cell_data: Dictionary = Game.tilesObj.get_cell(Vector2(x, y))
			var tileImgToSet = $BuildingsTiles.tile_set.find_tile_by_name(Game.tileTypes.getImg(tile_cell_data.tile_id))
			var buildingImgToSet = -1
			if Game.tilesObj.is_cell_in_battle(Vector2(x, y)):
				$ConstructionTiles.set_cellv(Vector2(x, y), id_tile_battle)
			elif Game.tilesObj.is_upgrading(Vector2(x, y)):
				$ConstructionTiles.set_cellv(Vector2(x, y), id_tile_upgrading)
			else:
				$ConstructionTiles.set_cellv(Vector2(x, y), -1)
			
			if Game.tilesObj.is_building(Vector2(x, y)):
				$BuildingTypesTiles.set_cellv(Vector2(x, y), id_tile_building_in_progress)
			elif tile_cell_data.building_id >= 0:
				buildingImgToSet = $BuildingTypesTiles.tile_set.find_tile_by_name(Game.buildingTypes.getImg(tile_cell_data.building_id))
				$BuildingTypesTiles.set_cellv(Vector2(x, y), buildingImgToSet)
			else:
				$BuildingTypesTiles.set_cellv(Vector2(x, y), -1)
			
			if  Game.tilesObj.belongs_to_player(Vector2(x, y), current_player_turn):
				$OwnedTiles.set_cellv(Vector2(x, y), -1)
			else:
				$OwnedTiles.set_cellv(Vector2(x, y), id_not_owned_tile)
			
			$CivilianTiles.set_cellv(Vector2(x, y), get_civilians_tile_id(Vector2(x, y), current_player_turn))
			$BuildingsTiles.set_cellv(Vector2(x, y), tileImgToSet)
			$TroopsTiles.set_cellv(Vector2(x, y), get_troops_tile_id(Vector2(x, y), current_player_turn))

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
	var troopsCountInTile: int = Game.tilesObj.get_troops_count(tile_pos, playerNumber)
	var upcoming_troops_data: Array = Game.tilesObj.get_upcoming_troops(tile_pos)
	if upcoming_troops_data.size() > 0:
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
		if interactTileSelected != Vector2(-1, -1) and nextInteractTileSelected == Vector2(-1, -1):
			if Game.tilesObj.is_next_to_tile(interactTileSelected, tile_pos):
				return id_tile_selected
			else:
				return id_tile_not_allowed
		elif !Game.tilesObj.belongs_to_player(tile_pos, current_player_turn):
			return id_tile_not_allowed
	return id_tile_selected


###################################
#	GETTERS
###################################

###################################
#	UTIL & STUFF
###################################


func give_player_capital(playerNumber: int, tile_pos: Vector2) ->void:
	var starting_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = 5000
	}
	Game.tilesObj.give_to_a_player(playerNumber, tile_pos, Game.tileTypes.getIDByName("capital"), 0, starting_population)
	Game.tilesObj.set_name(tile_pos, "Capital")

func give_player_rural(playerNumber: int, tile_pos: Vector2) ->void:
	var starting_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = 1000
	}
	Game.tilesObj.give_to_a_player(playerNumber, tile_pos, Game.tileTypes.getIDByName("rural"), 0, starting_population)

func destroy_player(playerNumber: int):
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if Game.tilesObj.belongs_to_player(Vector2(x, y), playerNumber):
				Game.tilesObj.clear_cell(Vector2(x, y))
	Game.playersData[playerNumber].alive = false
	print("PLAYER " + str(playerNumber) + " LOST!")

###################################
#	UI 
###################################

func update_build_menu():
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(current_player_turn)
	$UI/ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.clear()
	var buildingTypesList: Array = Game.buildingTypes.getList() #Gives a copy, not the original list edit is safe
	for i in range(buildingTypesList.size()):
		if getTotalGoldAvailable >= buildingTypesList[i].buy_prize:
			$UI/ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.add_item(buildingTypesList[i].name, i)
	
	update_build_menu_price($UI/ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.selected)

func update_build_menu_price(index: int):
	var currentBuildingTypeSelected = Game.buildingTypes.getByID(index)
	$UI/ActionsMenu/BuildingsMenu/VBoxContainer/HBoxContainer/BuilidngPriceText.text = str(currentBuildingTypeSelected.buy_prize)

func check_if_player_can_buy_buildings(playerNumber: int) -> bool:
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(playerNumber)
	var buildingTypesList: Array = Game.buildingTypes.getList()
	for i in range(buildingTypesList.size()):
		if getTotalGoldAvailable >= buildingTypesList[i].buy_prize:
			return true
	return false

func gold_to_move_text_changed():
	var goldAvailable: int = int($UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosDisponibles.text)
	var goldToMove: int = int($UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.text)
	goldToMove = int(clamp(float(goldToMove), 0.0, float(goldAvailable)))
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.text = str(goldToMove)
	actionTileToDo.goldToSend = goldToMove

func troops_to_move_text_changed():
	var troopAvailable: int = int($UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.text)
	var troopsToMove: int = int($UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.text)
	troopsToMove = int(clamp(float(troopsToMove), 0.0, float(troopAvailable)))
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.text = str(troopsToMove)
	for troopInActionTileDict in actionTileToDo.troopsToMove:
		if actionTileToDo.currentTroopId == troopInActionTileDict.troop_id:
			troopInActionTileDict.amountToMove = troopsToMove
			return

func popup_tiles_actions():
	$UI/ActionsMenu/TilesActions.visible = true
	clear_action_tile_to_do()
	update_tiles_actions_data()

func clear_action_tile_to_do():
	actionTileToDo.goldToSend = 0
	actionTileToDo.currentTroopId = -1
	actionTileToDo.troopsToMove.clear()
	var troops_array: Array = Game.tilesObj.get_troops(interactTileSelected)
	for troopDict in troops_array:
		if troopDict.owner != current_player_turn:
			continue
		if actionTileToDo.currentTroopId == -1:
			actionTileToDo.currentTroopId = troopDict.troop_id
		actionTileToDo.troopsToMove.append( { troop_id = troopDict.troop_id, amountToMove = 0})

func update_tiles_actions_data():
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosDisponibles.text = str(Game.tilesObj.get_cell_gold(interactTileSelected))
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.text = str(actionTileToDo.goldToSend)
	
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.clear()
	var troops_array: Array = Game.tilesObj.get_troops(interactTileSelected)
	for troopDict in troops_array:
		if troopDict.owner != current_player_turn:
			continue
		$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.add_item(Game.troopTypes.getByID(troopDict.troop_id).name, troopDict.troop_id)
	update_troops_move_data($UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.selected)

func game_tile_show_info():
	if !Game.tilesObj.belongs_to_player(current_tile_selected, current_player_turn):
		return
	
	var cell_data: Dictionary = Game.tilesObj.get_cell(current_tile_selected)
	
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/VenderTile.visible = Game.tileTypes.canBeSold(cell_data.tile_id)
	#if tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id ==  Game.tileTypes.getIDByName("capital"):
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/UrbanizarTile.visible = Game.tilesObj.can_be_upgraded(current_tile_selected, current_player_turn)
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/Construir.visible = check_if_player_can_buy_buildings(current_player_turn)
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/Reclutar.visible = is_recruiting_possible(current_tile_selected, current_player_turn)
	$UI/ActionsMenu/InGameTileActions.visible = true


func gui_update_civilization_info(playerNumber: int) -> void:
	$UI/HUD/CivilizationInfo/VBoxContainer/HBoxContainer5/CivilizationText.text = str(Game.playersData[playerNumber].civilizationName)
	$UI/HUD/CivilizationInfo/VBoxContainer/HBoxContainer/TotTalentosText.text = str(Game.tilesObj.get_total_gold(playerNumber))
	$UI/HUD/CivilizationInfo/VBoxContainer/HBoxContainer2/StrengthText.text = str(Game.tilesObj.get_total_strength(playerNumber))
	$UI/HUD/CivilizationInfo/VBoxContainer/HBoxContainer6/GainText.text = str(Game.tilesObj.get_total_gold_gain_and_losses(playerNumber))
	$UI/HUD/CivilizationInfo/VBoxContainer/HBoxContainer7/WarCostsText.text = str(Game.tilesObj.get_all_war_costs(playerNumber))

	var civilizationTroopsInfo: Array = Game.tilesObj.get_civ_population_info(playerNumber)
	var populationStr: String = ""
	
	for troopDict in civilizationTroopsInfo:
		populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	
	$UI/HUD/CivilizationInfo/VBoxContainer/HBoxContainer4/TotPopulationText.text = populationStr


func gui_update_tile_info(tile_pos: Vector2) -> void:
	
	var cell_data: Dictionary = Game.tilesObj.get_cell(tile_pos)

	if current_game_status == Game.STATUS.PRE_GAME:
		$UI/HUD/GameInfo/HBoxContainer2/TurnText.text = "PRE-GAME: " + str(Game.playersData[current_player_turn].civilizationName)
	elif current_game_status == Game.STATUS.GAME_STARTED:
		$UI/HUD/GameInfo/HBoxContainer2/TurnText.text = str(Game.playersData[current_player_turn].civilizationName)
	else:
		$UI/HUD/GameInfo/HBoxContainer2/TurnText.text = "??"

	
	$UI/HUD/TileInfo/VBoxContainer/HBoxContainer5/TileName.text = cell_data.name
	if cell_data.owner == -1:
		$UI/HUD/TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = "No info"
	else:
		$UI/HUD/TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = str(Game.playersData[cell_data.owner].civilizationName)
	$UI/HUD/TileInfo/VBoxContainer/HBoxContainer2/Amount.text = str(floor(cell_data.gold))
	
	$UI/HUD/TileInfo/VBoxContainer/HBoxContainer6/StrengthText.text = str(Game.tilesObj.get_strength(tile_pos, current_player_turn))
	$UI/HUD/TileInfo/VBoxContainer/HBoxContainer7/GainsText.text = str(Game.tilesObj.get_gold_gain_and_losses(tile_pos, current_player_turn))
	
	var populationStr: String = ""
	var isEnemyPopulation: bool = false
	var troops_array: Array = Game.tilesObj.get_troops(tile_pos)
	for troopDict in troops_array:
		if troopDict.amount <= 0:
			continue
		if troopDict.owner == current_player_turn:
			populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
		else:
			isEnemyPopulation = true
	if isEnemyPopulation:
		populationStr += "Enemigos: \n"
		for troopDict in troops_array:
			if troopDict.amount <= 0 or troopDict.owner == current_player_turn: 
				continue
			populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	$UI/HUD/TileInfo/VBoxContainer/HBoxContainer4/PopulationText.text = populationStr


###################################
#	BUTTONS & SIGNALS
###################################

func can_interact_with_menu() -> bool:
	return player_in_menu and player_can_interact

func execute_recruit_troops():
	assert(is_recruiting_possible(current_tile_selected, current_player_turn))
	
	var cell_data: Dictionary = Game.tilesObj.get_cell(current_tile_selected)
	
	var currentBuildingTypeSelected = Game.buildingTypes.getByID(cell_data.building_id)
	
	#step 1: get the types of troops to recruit and the amount
	var idTroopsToRecruit: int = currentBuildingTypeSelected.id_troop_generate
	var ammountOfTroopsToRecruit: int = 0
	
	var upcomingTroopsDict: Dictionary = {
		owner = current_player_turn,
		troop_id= currentBuildingTypeSelected.id_troop_generate,
		amount = currentBuildingTypeSelected.deploy_amount,
		turns_left = currentBuildingTypeSelected.turns_to_deploy_troops
	}
	Game.tilesObj.take_cell_gold(current_tile_selected, currentBuildingTypeSelected.deploy_prize)
	Game.tilesObj.append_upcoming_troops(current_tile_selected, upcomingTroopsDict)
	action_in_turn_executed()
	
func execute_buy_building(var selectedBuildTypeId: int):
	Game.tilesObj.buy_building(current_tile_selected, selectedBuildTypeId)
	action_in_turn_executed()

func execute_open_build_window():
	update_build_menu()

func gui_urbanizar_tile():
	
	var cell_data: Dictionary = Game.tilesObj.get_cell(current_tile_selected)
	
	var tile_type_id: int = cell_data.tile_id
	if  Game.tilesObj.is_upgrading(current_tile_selected):
		print("Already upgrading!")
		return
	var tileTypeData = Game.tileTypes.getByID(tile_type_id)
	assert(Game.tileTypes.canBeUpgraded(tile_type_id))
	if tileTypeData.improve_prize > Game.tilesObj.get_total_gold(current_player_turn):
		print("Not enough money to improve!")
		return
	Game.tilesObj.upgrade_tile(current_tile_selected)
	action_in_turn_executed()
	$UI/ActionsMenu/InGameTileActions.visible = false

func update_troops_move_data( var index: int ):
	actionTileToDo.currentTroopId = $UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.get_item_id(index)
	var startX: int = interactTileSelected.x
	var startY: int = interactTileSelected.y
	var troops_array: Array = Game.tilesObj.get_troops(interactTileSelected)
	
	for troopInActionTileDict in actionTileToDo.troopsToMove:
		if actionTileToDo.currentTroopId == troopInActionTileDict.troop_id:
			$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.text = str(troopInActionTileDict.amountToMove)
			break
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.text = "0"
	for troopDict in troops_array:
		if troopDict.owner != current_player_turn:
			continue
		if troopDict.troop_id == actionTileToDo.currentTroopId:
			$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.text = str(troopDict.amount)
			break

func execute_accept_tiles_actions():
	execute_tile_action()
	action_in_turn_executed()

func action_in_turn_executed():
	if current_game_status != Game.STATUS.GAME_STARTED:
		return
	actions_available-=1
	if actions_available <= 0:
		move_to_next_player_turn()
		
func execute_tile_action():
	var startX: int = interactTileSelected.x
	var startY: int = interactTileSelected.y
	var endX: int = nextInteractTileSelected.x
	var endY: int = nextInteractTileSelected.y
	var troopToAddExists: bool = false
	
	#First, remove gold and troops from the starting cell
	Game.tilesObj.take_cell_gold(interactTileSelected, actionTileToDo.goldToSend)
	var troops_start_array: Array = Game.tilesObj.get_troops(interactTileSelected)
	var troops_end_array: Array = Game.tilesObj.get_troops(nextInteractTileSelected)
	
	for startTroopDict in troops_start_array:
		if startTroopDict.owner != current_player_turn:
			continue
		for toMoveTroopDict in actionTileToDo.troopsToMove:
			if startTroopDict.troop_id == toMoveTroopDict.troop_id:
				startTroopDict.amount -= toMoveTroopDict.amountToMove
	#Second move and add troops for the ending cell
	Game.tilesObj.add_cell_gold(nextInteractTileSelected, actionTileToDo.goldToSend)
	for toMoveTroopDict in actionTileToDo.troopsToMove:
		if toMoveTroopDict.amountToMove <= 0:
			continue
		troopToAddExists = false
		for endTroopDict in troops_end_array:
			if endTroopDict.owner != current_player_turn:
				continue
			if endTroopDict.troop_id == toMoveTroopDict.troop_id:
				endTroopDict.amount += toMoveTroopDict.amountToMove
				troopToAddExists = true
		if !troopToAddExists:
			Game.tilesObj.add_troops(nextInteractTileSelected, {owner = current_player_turn, troop_id = toMoveTroopDict.troop_id, amount = toMoveTroopDict.amountToMove})

func execute_btn_finish_turn():
	if current_game_status == Game.STATUS.GAME_STARTED:
		move_to_next_player_turn()

func execute_give_extra_gold():
	Game.tilesObj.add_cell_gold(current_tile_selected, 10)
	Game.playersData[current_player_turn].selectLeft-=1
	if Game.playersData[current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()

func execute_add_extra_troops():
	var extraRecruits: Dictionary = {
		owner = current_player_turn,
		troop_id = Game.troopTypes.getIDByName("recluta"),
		amount = 1000
	}
	Game.tilesObj.add_troops(current_tile_selected, extraRecruits)
	Game.playersData[current_player_turn].selectLeft-=1
	if Game.playersData[current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()
