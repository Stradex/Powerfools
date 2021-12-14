class_name WorldGameNode
extends Node2D

# Tropas se pueden mover maximo 5 casilleros solamente, no más (no estoy seguro todavia)
# Poder quemar tierra
# mapas que se generen solos, montañas ( bloquea )
# Estadisticas batallas ganadas y perdidas, soldados perdidos, etc...
# Facciones: Germanos, Galos, Persas, Esparta, Tebas, Macedonios, Griegos, Romanos, Cartago, Egipto, Escitas 
# Programar bot

const MIN_ACTIONS_PER_TURN: int = 3
const MININUM_TROOPS_TO_FIGHT: int = 5
const EXTRA_CIVILIANS_TO_GAIN_CONQUER: int = 500
const WORLD_GAME_NODE_ID: int = 666 #NODE ID unique
const AUTOSAVE_INTERVAL: float = 600.0 #Every 10 minutes
const PLAYER_DATA_SYNC_INTERVAL: float = 2.0
const BOT_SECS_TO_EXEC_ACTION: float = 2.0 #seconds for a bot to execute each action (not turn but every single action)

var time_offset: float = 0.0
var player_in_menu: bool = false
var player_can_interact: bool = true
var actions_available: int = MIN_ACTIONS_PER_TURN
var rng: RandomNumberGenerator = RandomNumberGenerator.new();
var node_id: int = -1
var undo_available: bool = true

onready var tween: Tween
onready var net_sync_timer: Timer
onready var autosave_timer: Timer
onready var playerdata_sync_timer: Timer
onready var bot_actions_timer: Timer # to emulate that the bot takes time to execute actions
var NetBoop = Game.Boop_Object.new(self);

var saved_player_info: Dictionary = {
	points_to_select_left = 0,
	actions_left = 0
}

var actionTileToDo: Dictionary = {
	goldToSend = 0,
	currentTroopId=0,
	troopsToMove = []
}
enum NET_EVENTS {
	UPDATE_TILE_DATA,
	CLIENT_USE_POINT,
	CLIENT_USE_ACTION,
	CLIENT_TURN_END,
	SERVER_SEND_DELTA_TILES,
	SERVER_UPDATE_GAME_INFO,
	CLIENT_SEND_GAME_INFO,
	SERVER_SEND_PLAYERS_DATA,
	MAX_EVENTS 
}

enum BOT_ACTIONS {
	DEFENSIVE,
	OFFENSIVE,
	GREEDY
}

###################################################
# GODOT _READY, _PROCESS & FUNDAMENTAL FUNCTIONS
###################################################

func _ready():
	tween = Tween.new(); #useful to avoid having to add it manually in each map
	net_sync_timer = Timer.new()
	net_sync_timer.set_wait_time(10.0)
	net_sync_timer.connect("timeout", self, "on_net_sync_timeout")
	playerdata_sync_timer = Timer.new()
	playerdata_sync_timer.set_wait_time(PLAYER_DATA_SYNC_INTERVAL)
	playerdata_sync_timer.connect("timeout", self, "on_playerdata_sync_timeout")
	bot_actions_timer = Timer.new()
	bot_actions_timer.set_wait_time(BOT_SECS_TO_EXEC_ACTION)
	bot_actions_timer.connect("timeout", self, "on_bot_actions_timeout")
	add_child(tween)
	add_child(net_sync_timer)
	add_child(playerdata_sync_timer)
	add_child(bot_actions_timer)
	net_sync_timer.start()
	playerdata_sync_timer.start()
	bot_actions_timer.start()
	
	
	if !Game.Network.is_multiplayer() or Game.Network.is_server():
		autosave_timer = Timer.new()
		autosave_timer.set_wait_time(AUTOSAVE_INTERVAL)
		autosave_timer.connect("timeout", self, "on_autosave_timeout")
		add_child(autosave_timer)
		autosave_timer.start()
		
	$UI.init_gui(self)
	if Game.tilesObj:
		Game.tilesObj.clear()
	Game.tilesObj = TileGameObject.new(Game.tile_map_size, Game.tileTypes.getIDByName('vacio'), Game.tileTypes, Game.troopTypes, Game.buildingTypes, Game.rng)
	if Game.Network.is_multiplayer():
		change_game_status(Game.STATUS.LOBBY_WAIT)
	else:
		change_game_status(Game.STATUS.PRE_GAME)
		start_player_turn(0)
		Game.tilesObj.save_sync_data()
	Game.Network.register_synced_node(self, WORLD_GAME_NODE_ID);

func _process(delta):
	var player_was_in_menu: bool = player_in_menu
	player_in_menu = is_player_menu_open()
	if player_was_in_menu != player_in_menu: #little delay to avoid player spaming actions and also bugs
		player_can_interact = false
		tween.interpolate_callback(self, 0.25, "allow_player_interact")
		tween.start()

	if player_in_menu or !player_can_interact:
		return
	$Tiles.update_selection_tiles()
	time_offset+=delta
	if (time_offset > 1.0/Game.GAME_FPS):
		time_offset = 0.0
		game_on()
		$UI.update_lobby_info()
		$UI.update_server_info()
		$Tiles.update_building_tiles()
		$UI.gui_update_tile_info(Game.current_tile_selected)
		$UI.gui_update_civilization_info()
		$Tiles.update_visibility_tiles()
		if is_local_player_turn():
			$UI.hide_wait_for_player()
		else:
			$UI.show_wait_for_player()
		$UI/HUD/GameInfo/HBoxContainer/ActionsLeftText.text = str(actions_available)
		$UI/HUD/PreGameInfo/HBoxContainer/PointsLeftText.text = str(Game.playersData[Game.current_player_turn].selectLeft)

func _input(event):
	if Input.is_action_just_pressed("toggle_tile_info"):
		$UI/HUD/TileInfo.visible = !$UI/HUD/TileInfo.visible 
	if Input.is_action_just_pressed("toggle_civ_info"):
		$UI/HUD/CivilizationInfo.visible = !$UI/HUD/CivilizationInfo.visible
	

	if player_in_menu or !player_can_interact:
		return
		
	if Input.is_action_just_pressed("show_info"):
		match Game.current_game_status:
			Game.STATUS.PRE_GAME:
				pass
			Game.STATUS.GAME_STARTED:
				game_tile_show_info()

	if !is_local_player_turn():
		return

	if Input.is_action_just_pressed("interact"):
		match Game.current_game_status:
			Game.STATUS.PRE_GAME:
				pre_game_interact()
			Game.STATUS.GAME_STARTED:
				game_interact()
	if Input.is_action_just_pressed("toggle_ingame_menu"):
		$UI.gui_open_ingame_menu_window()	

###################################################
# SAVE & LOAD GAMES SYSTEM
###################################################

func save_game_as(file_name: String):
	if Game.Network.is_client():
		return
	var data_to_save: Dictionary = {
		game_actions_available = actions_available,
		game_current_player_turn = Game.current_player_turn,
		game_current_status = Game.current_game_status,
		game_points_to_select_left = Game.playersData[Game.current_player_turn].selectLeft,
		players_data = Game.playersData.duplicate(true),
		tiles_data = Game.tilesObj.get_all(true),
		tile_size = Game.tilesObj.get_size()
	}
	Game.FileSystem.save_as_json(file_name, data_to_save)

func load_game_from(file_name: String):
	if Game.Network.is_client():
		return
	Game.tilesObj.update_sync_data()
	var data_to_load: Dictionary = Game.FileSystem.load_as_dict(file_name)
	#TODO: Sync player data CORRECTLY, RIGHT NOW IT ONLY WORKS FOR 2 PLAYERS AND NOTHING MORE!
	Game.tilesObj.set_all(data_to_load.tiles_data, data_to_load.tile_size)
	Game.current_player_turn = data_to_load.game_current_player_turn
	Game.playersData[Game.current_player_turn].selectLeft = data_to_load.game_points_to_select_left
	actions_available = data_to_load.game_actions_available
	change_game_status(data_to_load.game_current_status)
	server_send_game_info()
	Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_DELTA_TILES, {dictArray = Game.tilesObj.get_sync_data() })
	Game.tilesObj.save_sync_data()

###################################
#	TIMERS
###################################

func on_autosave_timeout():
	if Game.Network.is_client():
		return
	save_game_as("autosave.json")

func on_net_sync_timeout():
	if Game.Network.is_client():
		return
	server_send_game_info()

func on_playerdata_sync_timeout():
	if Game.Network.is_client():
		return
	Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_PLAYERS_DATA, {playerDataArray = Game.playersData.duplicate(true) }, true) #Unreliable, to avoid overflow of netcode

##################
#	BOT STUFF	 #
##################

func on_bot_actions_timeout():
	if !Game.is_current_player_a_bot():
		return

	match Game.current_game_status:
		Game.STATUS.PRE_GAME:
			bot_process_pre_game(Game.current_player_turn)
		Game.STATUS.GAME_STARTED:
			bot_process_game(Game.current_player_turn)

func bot_process_game(bot_number: int):
	if !Game.is_current_player_a_bot():
		return

	check_bot_plan_status(bot_number)

	if is_bot_plan_empty(bot_number):
		bot_make_new_plan(bot_number)

	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	var type_of_action_to_make: int = bot_get_type_of_action_to_make(bot_number)
	var plan_to_achieve: Dictionary = Game.playersData[bot_number].bot_stats.next_plan
	var action_executed: bool = false
	var bot_is_being_attacked: bool = Game.tilesObj.ai_is_being_attacked(bot_number)
	#var is_bot_being_attacked: bool = Game.tilesObj.is_player_being_attacked(bot_number)
	#var is_bot_having_battles: bool = Game.tilesObj.is_player_having_battles(bot_number)
	
	#attack plan: first group the amount of troops necessary to win close to the enemy pos, then move that whole force to attack
	if bot_is_being_attacked:
		bot_make_new_plan(bot_number) #force new plans

	if plan_to_achieve.territories_to_defend.size() > 0: #being attacked
		action_executed = bot_move_troops_towards_pos(plan_to_achieve.territories_to_defend[0], bot_number)
		
	if !action_executed and plan_to_achieve.territories_to_conquer.size() > 0:
		if Game.tilesObj.ai_have_strength_to_conquer(plan_to_achieve.territories_to_conquer[0], bot_number):
			action_executed = bot_move_troops_towards_pos(plan_to_achieve.territories_to_conquer[0], bot_number)
		else:
			plan_to_achieve.territories_to_conquer.clear()
	
	if !action_executed and plan_to_achieve.troops.size() > 0:
		action_executed = bot_recruit_troops(bot_number)
	if !action_executed and plan_to_achieve.to_upgrade.size() > 0:
		if bot_upgrade_territory(plan_to_achieve.to_upgrade[0], bot_number): #upgrade sucessful
			action_executed = true
			plan_to_achieve.to_upgrade.clear()
	if !action_executed:
		bot_free_action(bot_number)
		
	"""
	match type_of_action_to_make:
		BOT_ACTIONS.DEFENSIVE:
			bot_game_defensive_action(bot_number)
		BOT_ACTIONS.OFFENSIVE:
			bot_game_offensive_action(bot_number)
		BOT_ACTIONS.GREEDY:
			bot_game_greedy_action(bot_number)
	"""
	action_in_turn_executed()

func bot_free_action(bot_number: int) -> bool:
	var minimum_gold_needed: float = gold_needed_by_plans(bot_number)
	print (minimum_gold_needed)
	if Game.tilesObj.get_total_gold(bot_number) <= minimum_gold_needed:
		return false
	#See if it can make some places productive
	var unproductive_territories: Array = Game.tilesObj.ai_get_cells_not_being_productive(bot_number)
	for cell in unproductive_territories:
		if Game.tilesObj.can_be_upgraded(cell, bot_number):
			if bot_upgrade_territory(cell, bot_number): #upgraded
				return true
	#See if it can build something
	var cells_without_buildings: Array = Game.tilesObj.ai_get_all_cells_without_buildings(bot_number)
	if bot_buy_building_at_cell(cells_without_buildings[rng.randi_range(0, cells_without_buildings.size()-1)], bot_number):
		return true
	
	#See if it can recruit something
	var cells_that_can_recruit: Array = Game.tilesObj.ai_get_all_cells_available_to_recruit(bot_number)
	if cells_that_can_recruit.size() > 0 and bot_make_new_troops(cells_that_can_recruit[rng.randi_range(0, cells_that_can_recruit.size()-1)], bot_number):
		return true
	return false
func bot_upgrade_territory(cell_to_upgrade: Vector2, bot_number: int) -> bool:
	var cell_data: Dictionary = Game.tilesObj.get_cell(cell_to_upgrade)
	
	var tile_type_id: int = cell_data.tile_id
	if  Game.tilesObj.is_upgrading(cell_to_upgrade):
		return false
	var tileTypeData = Game.tileTypes.getByID(tile_type_id)
	assert(Game.tileTypes.canBeUpgraded(tile_type_id))
	if tileTypeData.improve_prize > Game.tilesObj.get_total_gold(bot_number):
		return false
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.upgrade_tile(cell_to_upgrade)
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	return true

func bot_recruit_troops(bot_number: int) -> bool:
	var cells_that_can_recruit: Array = Game.tilesObj.ai_get_all_cells_available_to_recruit(bot_number)
	if cells_that_can_recruit.size() <= 0: #try to build a building
		var cells_without_buildings: Array = Game.tilesObj.ai_get_all_cells_without_buildings(bot_number)
		if cells_without_buildings.size() > 0:
			return bot_buy_building_at_cell(cells_without_buildings[rng.randi_range(0, cells_without_buildings.size()-1)], bot_number)
		else:
			return false
	else:
		return bot_make_new_troops(cells_that_can_recruit[rng.randi_range(0, cells_that_can_recruit.size()-1)], bot_number)

func bot_buy_building_at_cell(cell_pos: Vector2, bot_number: int) -> bool:
	if !check_if_player_can_buy_buildings(cell_pos, bot_number):
		return false
	
	var available_buildings_to_build: Array = []
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(bot_number)
	var buildingTypesList: Array = Game.buildingTypes.getList() #Gives a copy, not the original list edit is safe
	for i in range(buildingTypesList.size()):
		if Game.tilesObj.can_buy_building_at_cell(cell_pos, i, getTotalGoldAvailable, bot_number):
			available_buildings_to_build.append(i)
	Game.tilesObj.update_sync_data()
	Game.tilesObj.buy_building(cell_pos, available_buildings_to_build[rng.randi_range(0, available_buildings_to_build.size()-1)])
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	return true

func gold_needed_by_plans(bot_number: int) -> float:
	var bot_next_plan: Dictionary = Game.playersData[bot_number].bot_stats.next_plan
	var gold_needed: float = 10.0 #start with 10 to avoid doing any action with less than 10 of gold
	for cell_to_upgrade in bot_next_plan.to_upgrade:
		gold_needed += Game.tilesObj.gold_needed_to_upgrade(cell_to_upgrade)
	for troopToRecruit in bot_next_plan.troops:
		var buildingTypeDict: Dictionary = Game.buildingTypes.getByRecruitTroopType(troopToRecruit.troop_id)
		var deployements_needed: int = round(troopToRecruit.amount/buildingTypeDict.deploy_amount+0.5)
		gold_needed += buildingTypeDict.deploy_prize*deployements_needed
	return gold_needed

func bot_make_new_plan(bot_number: int) -> void:
	if !Game.is_current_player_a_bot():
		return
	#Stupid bot AI: Just conquer the weakest tiles and do nothing more than that
	var defensive_points:float = Game.playersData[bot_number].bot_stats.defensiveness*Game.rng.randf_range(0.0, 100.0)
	var ofensive_points:float = Game.playersData[bot_number].bot_stats.aggressiveness*Game.rng.randf_range(0.0, 100.0)
	var greedy_points:float = Game.playersData[bot_number].bot_stats.avarice*Game.rng.randf_range(0.0, 100.0)
	var sum_values: float = defensive_points+ofensive_points+greedy_points #chances of action
	var defensive_action_chances: float = (defensive_points/sum_values)*100.0
	var ofensive_action_chances: float = (ofensive_points/sum_values)*100.0
	var greedy_action_chances: float = (greedy_points/sum_values)*100.0
	var bot_next_plan: Dictionary = Game.playersData[bot_number].bot_stats.next_plan
	
	var territories_attacked: Array = Game.tilesObj.ai_all_cells_being_attacked(bot_number)
	for cell in territories_attacked:
		bot_next_plan.territories_to_defend.append(cell)
	
	if bot_next_plan.to_upgrade.size() > 0:
		Game.playersData[bot_number].bot_stats.next_plan = bot_next_plan
		return
	var unproductive_territories: Array = Game.tilesObj.ai_get_cells_not_being_productive(bot_number)
	for cell in unproductive_territories:
		if Game.tilesObj.can_be_upgraded(cell, bot_number):
				bot_next_plan.to_upgrade.append(cell)
				break
	
	if bot_next_plan.territories_to_conquer.size() > 0:
		Game.playersData[bot_number].bot_stats.next_plan = bot_next_plan
		return
	var wekeast_enemy_cell: Vector2 = Game.tilesObj.ai_get_weakest_enemy_cell(bot_number)
	#var richest_enemy_cell: Vector2 = Game.tilesObj.ai_get_richest_enemy_cell(bot_number)
	if Game.tilesObj.ai_have_strength_to_conquer(wekeast_enemy_cell, bot_number):
		bot_next_plan.territories_to_conquer.append(wekeast_enemy_cell)
	else:
		var strength_necessary: float = Game.tilesObj.get_enemies_troops_health(wekeast_enemy_cell, bot_number)
		var troop_id_to_recluit: int = Game.troopTypes.getIDByName("recluta")
		var troops_to_recluit: int = strength_necessary/Game.troopTypes.getAverageDamage(troop_id_to_recluit)
		bot_next_plan.troops.append({
			troop_id = Game.troopTypes.getIDByName("recluta"),
			amount = troops_to_recluit
		})

func bot_make_new_troops(cell_pos: Vector2, bot_number: int) -> bool:
	if !is_recruiting_possible(cell_pos, bot_number):
		return false
	var plan_to_achieve: Dictionary = Game.playersData[bot_number].bot_stats.next_plan
	var cell_data: Dictionary = Game.tilesObj.get_cell(cell_pos)
	var currentBuildingType = Game.buildingTypes.getByID(cell_data.building_id)
	var idTroopsToRecruit: int = currentBuildingType.id_troop_generate
	var ammountOfTroopsToRecruit: int = 0
	var upcomingTroopsDict: Dictionary = {
		owner = bot_number,
		troop_id= currentBuildingType.id_troop_generate,
		amount = currentBuildingType.deploy_amount,
		turns_left = currentBuildingType.turns_to_deploy_troops
	}
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.take_cell_gold(cell_pos, currentBuildingType.deploy_prize)
	Game.tilesObj.append_upcoming_troops(cell_pos, upcomingTroopsDict)
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	return true

func bot_move_troops_towards_pos(pos_to_move: Vector2, bot_number: int) -> bool:
	var cell_with_troops: Vector2 =  Game.tilesObj.ai_get_closest_troop_force_pos_to(pos_to_move, bot_number)
	if cell_with_troops == Vector2(-1, -1) or cell_with_troops == pos_to_move:
		return false
	var path_to_use: Array = Game.tilesObj.ai_get_path_to_from(cell_with_troops, pos_to_move, bot_number)
	var index_to_remove: int = path_to_use.find(cell_with_troops)
	if index_to_remove != -1:
		path_to_use.remove(index_to_remove)
	if path_to_use.size() > 0:
		Game.tilesObj.ai_move_all_warriors_from_to(cell_with_troops, path_to_use[0], bot_number)
	else:
		return false
	return true

func bot_game_defensive_action(bot_number: int):
	pass

func bot_game_offensive_action(bot_number: int):
	pass

func bot_game_greedy_action(bot_number: int):
	pass

func bot_process_pre_game(bot_number: int):
	if !Game.is_current_player_a_bot():
		return
	if !player_has_capital(bot_number):
		give_bot_a_capital(bot_number)
		return
		
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	var all_player_cells: Array = Game.tilesObj.get_all_player_tiles(bot_number)
	var get_extra_troops_action: bool = false #if true, it will get troops, if not, it will get a territory
	
	if Game.tilesObj.get_total_gold(bot_number) <= 0:
		bot_execute_give_extra_gold(bot_number, player_capital_pos)
		return
		
	if Game.tilesObj.get_total_gold_gain_and_losses(bot_number) <= 0:
		get_extra_troops_action = false
	else:
		get_extra_troops_action = rng.randi_range(0, 100) >= 50
	
	#print(Game.tilesObj.ai_get_farthest_player_cell_from(player_capital_pos, bot_number))
	var type_of_action_to_make: int = bot_get_type_of_action_to_make(bot_number)
	match type_of_action_to_make:
		BOT_ACTIONS.DEFENSIVE:
			if get_extra_troops_action:
				bot_execute_add_extra_troops(bot_number, player_capital_pos)
			else:
				var available_cells_to_get: Array = Game.tilesObj.ai_get_closest_available_to_buy_free_cell_to(player_capital_pos, bot_number)
				give_player_rural(bot_number, available_cells_to_get[rng.randi_range(0, available_cells_to_get.size()-1)])
				
		BOT_ACTIONS.OFFENSIVE:
			var bot_cells_farthest_from_capital: Array = Game.tilesObj.ai_get_farthest_player_cell_from(player_capital_pos, bot_number)
			var cell_to_use_picked: Vector2 = bot_cells_farthest_from_capital[rng.randi_range(0, bot_cells_farthest_from_capital.size()-1)]
			if get_extra_troops_action:
				bot_execute_add_extra_troops(bot_number, cell_to_use_picked)
			else:
				var available_cells_to_get: Array = Game.tilesObj.ai_get_closest_available_to_buy_free_cell_to(cell_to_use_picked, bot_number)
				give_player_rural(bot_number, available_cells_to_get[rng.randi_range(0, available_cells_to_get.size()-1)])
		BOT_ACTIONS.GREEDY:
			bot_execute_give_extra_gold(bot_number, all_player_cells[rng.randi_range(0, all_player_cells.size()-1)])
			
	Game.playersData[bot_number].selectLeft -= 1
	server_send_game_info()
	if Game.playersData[bot_number].selectLeft == 0: 
		move_to_next_player_turn()

func bot_get_type_of_action_to_make(bot_number: int) -> int:
	var defensive_points:float = Game.playersData[bot_number].bot_stats.defensiveness*Game.rng.randf_range(0.0, 100.0)
	var ofensive_points:float = Game.playersData[bot_number].bot_stats.aggressiveness*Game.rng.randf_range(0.0, 100.0)
	var greedy_points:float = Game.playersData[bot_number].bot_stats.avarice*Game.rng.randf_range(0.0, 100.0)
	
	if defensive_points >= ofensive_points and defensive_points >= greedy_points:
		return BOT_ACTIONS.DEFENSIVE
		
	if ofensive_points >= defensive_points and ofensive_points >= greedy_points:
		return BOT_ACTIONS.OFFENSIVE
		
	return BOT_ACTIONS.GREEDY
	
func give_bot_a_capital(bot_number: int):
	if !Game.is_current_player_a_bot():
		return
	give_player_capital(bot_number, Game.tilesObj.ai_pick_random_free_cell())


func bot_execute_give_extra_gold(bot_number: int, cell: Vector2):
	if !Game.is_current_player_a_bot():
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.add_cell_gold(cell, 10)
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func bot_execute_add_extra_troops(bot_number: int, cell: Vector2):
	if !Game.is_current_player_a_bot():
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	var extraRecruits: Dictionary = {
		owner = bot_number,
		troop_id = Game.troopTypes.getIDByName("recluta"),
		amount = 1000
	}
	Game.tilesObj.add_troops(cell, extraRecruits)
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func check_bot_plan_status(bot_number: int) -> void:
	var bot_next_plan: Dictionary = Game.playersData[bot_number].bot_stats.next_plan
	
	#Check territories to conquer battle status!
	var to_remove: bool = true
	while to_remove:
		to_remove = false
		for i in range(bot_next_plan.territories_to_conquer.size()):
			if Game.tilesObj.belongs_to_player(bot_next_plan.territories_to_conquer[i], bot_number): #already conquered!
				to_remove = true
				bot_next_plan.territories_to_conquer.remove(i)
				break
	#Check troops to be deployed status!
	var warriors_count: int = Game.tilesObj.get_all_warriors_count(bot_number)
	print("Warriors: " + str(warriors_count))
	if bot_next_plan.troops.size() > 0:
		if warriors_count >= bot_next_plan.troops[0].amount:
			bot_next_plan.troops.clear()
			
	if bot_next_plan.to_upgrade.size() > 0:
		if !Game.tilesObj.belongs_to_player(bot_next_plan.to_upgrade[0], bot_number):
			bot_next_plan.to_upgrade.clear() #in case the territory was conquered
			
	#Check defend battles status
	var territories_attacked: Array = Game.tilesObj.ai_all_cells_being_attacked(bot_number)
	var value_removed: bool = true
	while value_removed:
		value_removed = false
		for i in range(bot_next_plan.territories_to_defend.size()):
			var index_to_remove: int = territories_attacked.find(bot_next_plan.territories_to_defend[i])
			if index_to_remove == -1:
				bot_next_plan.territories_to_defend.remove(i)
				value_removed = true
				break
	
func is_bot_plan_empty(bot_number: int) -> bool:
	var bot_next_plan: Dictionary = Game.playersData[bot_number].bot_stats.next_plan
	if bot_next_plan.territories_to_conquer.size() > 0:
		return false
	if bot_next_plan.troops.size() > 0:
		return false
	if bot_next_plan.to_upgrade.size() > 0:
		return false
	if bot_next_plan.territories_to_defend.size() > 0:
		return false
	if bot_next_plan.gold > 0:
		return false
	return true

###################################
#	INIT FUNCTIONS
###################################


###################################
#	GAME LOGIC
###################################

func start_online_game():
	print("staring game...")
	change_game_status(Game.STATUS.PRE_GAME)
	for i in range(Game.playersData.size()):
		if Game.playersData[i].alive:
			Game.current_player_turn = i
			save_player_info()
			update_actions_available()
			server_send_game_info()
			print("Player " + str(i) + " turn")
			break
	Game.tilesObj.save_sync_data()

func game_interact():
	if !is_local_player_turn():
		return
	if Game.interactTileSelected == Game.current_tile_selected or Game.nextInteractTileSelected == Game.current_tile_selected:
		return
	
	if Game.interactTileSelected == Vector2(-1, -1) or (Game.interactTileSelected != Vector2(-1, -1) and Game.nextInteractTileSelected != Vector2(-1, -1)):
		if !Game.tilesObj.belongs_to_player(Game.current_tile_selected, Game.current_player_turn):
			Game.interactTileSelected = Vector2(-1, -1)
		else:
			Game.interactTileSelected = Game.current_tile_selected
		Game.nextInteractTileSelected = Vector2(-1, -1)
	elif Game.nextInteractTileSelected == Vector2(-1, -1):
		if can_do_tiles_actions(Game.interactTileSelected, Game.current_tile_selected, Game.current_player_turn):
			Game.nextInteractTileSelected = Game.current_tile_selected
			popup_tiles_actions()
		else:
			Game.interactTileSelected = Vector2(-1, -1)

func pre_game_interact():
	if !is_local_player_turn():
		return
	if Game.tilesObj.is_owned_by_player(Game.current_tile_selected):
		if Game.tilesObj.belongs_to_player(Game.current_tile_selected, Game.current_player_turn):
			$UI/ActionsMenu/ExtrasMenu.visible = true
		return
	if Game.tilesObj.is_next_to_enemy_territory(Game.current_tile_selected, Game.current_player_turn):
		return
	if !player_has_capital(Game.current_player_turn):
		give_player_capital(Game.current_player_turn, Game.current_tile_selected)
	elif Game.playersData[Game.current_player_turn].selectLeft > 0 :
		give_player_rural(Game.current_player_turn, Game.current_tile_selected)
		use_selection_point()

func change_game_status(new_status: int) -> void:
	var status_changed: bool = false
	if new_status != Game.current_game_status:
		status_changed = true
		server_send_game_info()
	Game.current_game_status = new_status
	match new_status:
		Game.STATUS.LOBBY_WAIT:
			$UI/HUD/GameInfo.visible = false
			$UI/HUD/PreGameInfo.visible = false
			$UI.open_lobby_window()
		Game.STATUS.PRE_GAME:
			$UI/HUD/GameInfo.visible = false
			$UI/HUD/PreGameInfo.visible = true
			$UI/ActionsMenu/WaitingPlayers.visible = false
		Game.STATUS.GAME_STARTED:
			$UI/HUD/PreGameInfo.visible = false
			$UI/HUD/GameInfo.visible = true
			$UI/ActionsMenu/WaitingPlayers.visible = false
			if status_changed:
				process_unused_tiles()
	if status_changed:
		print("Game Status changed to value: " + str(new_status))

func process_unused_tiles() -> void:
	if Game.Network.is_client():
		return
	#Game.tilesObj.recover_sync_data()
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			if !Game.tilesObj.is_owned_by_player(Vector2(x, y)):
				add_tribal_society_to_tile(Vector2(x, y))
	save_player_info() #Avoid weird bug
	Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_DELTA_TILES, {dictArray = Game.tilesObj.get_sync_neighbors(Game.current_player_turn) })
	#Game.tilesObj.save_sync_data()

func game_on() -> void:
	if Game.Network.is_client():
		return
	match Game.current_game_status:
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

func start_player_turn(player_number: int):
	Game.tilesObj.save_sync_data()
	Game.current_player_turn = player_number
	save_player_info()
	update_actions_available()
	server_send_game_info()
	print("Player " + str(player_number) + " turn")
	
func move_to_next_player_turn() -> void: 
	if Game.Network.is_client() and is_local_player_turn():
		Game.Network.net_send_event(self.node_id, NET_EVENTS.CLIENT_TURN_END, {player_turn = Game.current_player_turn})
	if Game.current_game_status == Game.STATUS.GAME_STARTED and !Game.Network.is_client():
		process_turn_end(Game.current_player_turn)
	elif Game.current_game_status == Game.STATUS.PRE_GAME and !Game.Network.is_client():
		Game.tilesObj.recover_sync_data()
		Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_DELTA_TILES, {dictArray = Game.tilesObj.get_sync_data() })
	var new_player_turn: int = -1
	for i in range(Game.current_player_turn, Game.playersData.size()):
		if i != Game.current_player_turn and Game.playersData[i].alive:
			new_player_turn = i
			break
	if new_player_turn == -1:
		for i in range(Game.playersData.size()):
			if i != Game.current_player_turn and Game.playersData[i].alive:
				new_player_turn = i
				break
	if new_player_turn == -1:
		new_player_turn = Game.current_player_turn
	start_player_turn(new_player_turn)

func update_actions_available() -> void:
	if Game.current_game_status == Game.STATUS.GAME_STARTED:
		actions_available = int(round(Game.tilesObj.get_number_of_productive_territories(Game.current_player_turn)/5.0 + 0.5))
		if actions_available < MIN_ACTIONS_PER_TURN:
			actions_available = MIN_ACTIONS_PER_TURN

func process_turn_end(playerNumber: int) -> void:
	update_gold_stats(playerNumber)
	process_tiles_turn_end(playerNumber)
	if did_player_lost(playerNumber):
		destroy_player(playerNumber)

func process_tiles_turn_end(playerNumber: int) -> void:
	Game.tilesObj.recover_sync_data()
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			process_tile_upgrade(Vector2(x, y), playerNumber)
			process_tile_builings(Vector2(x, y), playerNumber)
			process_tile_recruitments(Vector2(x, y), playerNumber)
			process_tile_battles(Vector2(x, y))
			update_tile_owner(Vector2(x, y))
	if Game.Network.is_server():
		var next_player_turn: int = Game.get_next_player_turn()
		var sync_arrayA: Array = Game.tilesObj.get_sync_neighbors(next_player_turn)
		var sync_arrayB: Array = Game.tilesObj.get_sync_data()

		var merged_sync_arrays: Array = Game.tilesObj.merge_sync_arrays(sync_arrayA, sync_arrayB)
		if next_player_turn != Game.current_player_turn:
			var sync_arrayC: Array = Game.tilesObj.get_sync_neighbors(Game.current_player_turn)
			merged_sync_arrays = Game.tilesObj.merge_sync_arrays(merged_sync_arrays.duplicate(true), sync_arrayC)
		Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_DELTA_TILES, {dictArray = merged_sync_arrays })
	Game.tilesObj.save_sync_data()

func update_tile_owner(cell: Vector2) -> void:
	var playersInTile: int = Game.tilesObj.get_number_of_players_in_cell(cell)
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
	var damageMultiplier: float = Game.rng.randf_range(0.25, 1.0) #some battles can last more than others
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
			if troopsToKill > troopDict.amount:
				 troopsToKill = troopDict.amount
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
				slaves_to_gain = int(Game.rng.randf_range(civiliansKilledDictionary.amount*0.25, civiliansKilledDictionary.amount*0.75))
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
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(playerNumber)
	var all_war_costs: float = Game.tilesObj.get_all_war_costs(playerNumber)
	#Step 1, update all gold in all the tiles
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			if Game.tilesObj.belongs_to_player(Vector2(x, y), playerNumber):
				
				if Vector2(x, y) == player_capital_pos:
					Game.tilesObj.take_cell_gold(Vector2(x, y), all_war_costs) # war costs implemented
	
				Game.tilesObj.update_gold_stats(Vector2(x, y), playerNumber)
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

###################################
#	BOOLEANS FUNCTIONS
###################################

func is_local_player_turn() -> bool:
	if !Game.Network.is_multiplayer() or Game.Network.is_server() and Game.is_current_player_a_bot():
		return true
	if Game.current_player_turn == Game.get_local_player_number():
		return true
	return false

func is_player_menu_open() -> bool:
	return $UI.is_a_menu_open()

func can_do_tiles_actions(startTile: Vector2, endTile: Vector2, playerNumber: int):
	if !Game.tilesObj.belongs_to_player(startTile, playerNumber):
		return false
	if !Game.tilesObj.is_next_to_tile(startTile,endTile):
		return false
	if !Game.tilesObj.belongs_to_player(endTile, playerNumber) and Game.tilesObj.get_warriors_count(startTile, playerNumber) <= 0: #don't allow civilians to invade
		return false
	return true

func did_player_lost(playerNumber: int) -> bool:
	return !player_has_capital(playerNumber)

func player_has_capital(playerNumber: int) -> bool:
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
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
	if tile_cell_data.upcomingTroops.size() >= 1: 
		return false
	return true

func check_if_player_can_buy_buildings(tile_pos: Vector2, playerNumber: int) -> bool:
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(playerNumber)
	var cellData: Dictionary = Game.tilesObj.get_cell(tile_pos)
	var buildingTypesList: Array = Game.buildingTypes.getList()
	for i in range(buildingTypesList.size()):
		if Game.tilesObj.can_buy_building_at_cell(tile_pos, i, getTotalGoldAvailable, playerNumber):
			return true
	return false

###################################
#	DRAWING & GRAPHICS TILES
###################################

###################################
#	GETTERS
###################################

###################################
#	UTIL & STUFF
###################################

func allow_player_interact():
	player_can_interact = true

func give_player_capital(playerNumber: int, tile_pos: Vector2) ->void:
	Game.tilesObj.update_sync_data()
	save_player_info()
	var starting_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = 5000
	}
	Game.tilesObj.give_to_a_player(playerNumber, tile_pos, Game.tileTypes.getIDByName("capital"), 0, starting_population)
	Game.tilesObj.set_name(tile_pos, "Capital")
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = tile_pos, cell_data = Game.tilesObj.get_cell(tile_pos)})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func give_player_rural(playerNumber: int, tile_pos: Vector2) ->void:
	Game.tilesObj.update_sync_data()
	save_player_info()
	var starting_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = 1000
	}
	Game.tilesObj.give_to_a_player(playerNumber, tile_pos, Game.tileTypes.getIDByName("rural"), 0, starting_population)
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = tile_pos, cell_data = Game.tilesObj.get_cell(tile_pos)})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func add_tribal_society_to_tile(cell: Vector2) -> void:
	Game.tilesObj.set_cell_gold(cell, round(Game.rng.randf_range(5.0, 20.0)))
	var troopsToAdd: Dictionary = {
		owner = -1,
		troop_id = Game.troopTypes.getIDByName("recluta"),
		amount = int(Game.rng.randf_range(250.0, 2000.0))
	}
	var civiliansToAdd: Dictionary = {
		owner = -1,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = int(Game.rng.randf_range(500.0, 5000.0))
	}
	Game.tilesObj.add_troops(cell, troopsToAdd)
	Game.tilesObj.add_troops(cell, civiliansToAdd)

func destroy_player(playerNumber: int):
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			if Game.tilesObj.belongs_to_player(Vector2(x, y), playerNumber):
				Game.tilesObj.clear_cell(Vector2(x, y))
	Game.playersData[playerNumber].alive = false
	print("PLAYER " + str(playerNumber) + " LOST!")

func change_tile_name(tile_pos: Vector2, new_name: String) -> void:
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer():
		player_mask = Game.get_local_player_number()
	if !Game.tilesObj.belongs_to_player(Vector2(tile_pos.x, tile_pos.y), player_mask):
		return
	if Game.Network.is_client(): # No need of server to send this, it will be send at the next turn
		Game.tilesObj.update_sync_data()

	Game.tilesObj.set_name(Vector2(tile_pos.x, tile_pos.y), new_name)
	
	if Game.Network.is_client(): # No need of server to send this, it will be send at the next turn
		Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data(player_mask) })

###################################
#	UI 
###################################

func update_build_menu():
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(Game.current_player_turn)
	$UI/ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.clear()
	var buildingTypesList: Array = Game.buildingTypes.getList() #Gives a copy, not the original list edit is safe
	for i in range(buildingTypesList.size()):
		if Game.tilesObj.can_buy_building_at_cell(Game.current_tile_selected, i, getTotalGoldAvailable, Game.current_player_turn):
			$UI/ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.add_item(buildingTypesList[i].name, i)
	
	update_build_menu_price($UI/ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.selected)

func update_build_menu_price(index: int):
	var building_type_id: int = $UI/ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.get_item_id(index)
	var currentBuildingTypeSelected = Game.buildingTypes.getByID(building_type_id)
	$UI/ActionsMenu/BuildingsMenu/VBoxContainer/HBoxContainer/BuilidngPriceText.text = str(currentBuildingTypeSelected.buy_prize)

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
	var troops_array: Array = Game.tilesObj.get_troops(Game.interactTileSelected)
	for troopDict in troops_array:
		if troopDict.owner != Game.current_player_turn:
			continue
		if actionTileToDo.currentTroopId == -1:
			actionTileToDo.currentTroopId = troopDict.troop_id
		actionTileToDo.troopsToMove.append( { troop_id = troopDict.troop_id, amountToMove = 0})

func update_tiles_actions_data():
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosDisponibles.text = str(Game.tilesObj.get_cell_gold(Game.interactTileSelected))
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.text = str(actionTileToDo.goldToSend)
	
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.clear()
	var troops_array: Array = Game.tilesObj.get_troops(Game.interactTileSelected)
	var troops_to_show_array: Array = []
	# Add always warriors first
	for troopDict in troops_array:
		if troopDict.owner != Game.current_player_turn:
			continue
		if troopDict.amount <= 0:
			continue
		if Game.troopTypes.getByID(troopDict.troop_id).is_warrior:
			troops_to_show_array.push_front({ name = Game.troopTypes.getByID(troopDict.troop_id).name, id = troopDict.troop_id})
		elif Game.tilesObj.belongs_to_player(Game.nextInteractTileSelected, Game.current_player_turn):
			troops_to_show_array.push_back({ name = Game.troopTypes.getByID(troopDict.troop_id).name, id = troopDict.troop_id})
	
	for troopData in troops_to_show_array:
		$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.add_item(troopData.name, troopData.id)

	update_troops_move_data($UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.selected)

func game_tile_show_info():
	if !Game.tilesObj.belongs_to_player(Game.current_tile_selected, Game.current_player_turn):
		return
	
	if !is_local_player_turn():
		$UI/ActionsMenu/InGameTileActions.visible = true
		return
	var cell_data: Dictionary = Game.tilesObj.get_cell(Game.current_tile_selected)
	
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/VenderTile.visible = Game.tileTypes.canBeSold(cell_data.tile_id)
	#if tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id ==  Game.tileTypes.getIDByName("capital"):
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/UrbanizarTile.visible = Game.tilesObj.can_be_upgraded(Game.current_tile_selected, Game.current_player_turn)
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/Construir.visible = check_if_player_can_buy_buildings(Game.current_tile_selected, Game.current_player_turn)
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/Reclutar.visible = is_recruiting_possible(Game.current_tile_selected, Game.current_player_turn)
	$UI/ActionsMenu/InGameTileActions.visible = true

#########################
#	BUTTONS & SIGNALS	#
#########################

func can_execute_action() -> bool:
	return actions_available > 0

func have_selection_points_left() -> bool:
	return Game.playersData[Game.current_player_turn].selectLeft > 0

func can_interact_with_menu() -> bool:
	return player_in_menu and player_can_interact

func execute_recruit_troops():
	if !is_local_player_turn() or !can_execute_action():
		return
	assert(is_recruiting_possible(Game.current_tile_selected, Game.current_player_turn))
	
	var cell_data: Dictionary = Game.tilesObj.get_cell(Game.current_tile_selected)
	
	var currentBuildingTypeSelected = Game.buildingTypes.getByID(cell_data.building_id)
	
	#step 1: get the types of troops to recruit and the amount
	var idTroopsToRecruit: int = currentBuildingTypeSelected.id_troop_generate
	var ammountOfTroopsToRecruit: int = 0
	
	var upcomingTroopsDict: Dictionary = {
		owner = Game.current_player_turn,
		troop_id= currentBuildingTypeSelected.id_troop_generate,
		amount = currentBuildingTypeSelected.deploy_amount,
		turns_left = currentBuildingTypeSelected.turns_to_deploy_troops
	}
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.take_cell_gold(Game.current_tile_selected, currentBuildingTypeSelected.deploy_prize)
	Game.tilesObj.append_upcoming_troops(Game.current_tile_selected, upcomingTroopsDict)
	action_in_turn_executed()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = Game.current_tile_selected, cell_data = Game.tilesObj.get_cell(Game.current_tile_selected)})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	
func execute_buy_building(var selectedBuildTypeId: int):
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(Game.current_player_turn)
	if !is_local_player_turn() or !can_execute_action() or !Game.tilesObj.can_buy_building_at_cell(Game.current_tile_selected, selectedBuildTypeId, getTotalGoldAvailable, Game.current_player_turn): 
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.buy_building(Game.current_tile_selected, selectedBuildTypeId)
	action_in_turn_executed()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = Game.current_tile_selected, cell_data = Game.tilesObj.get_cell(Game.current_tile_selected)})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func execute_open_build_window():
	update_build_menu()

func gui_urbanizar_tile():
	if !is_local_player_turn() or !can_execute_action():
		return
	var cell_data: Dictionary = Game.tilesObj.get_cell(Game.current_tile_selected)
	
	var tile_type_id: int = cell_data.tile_id
	if  Game.tilesObj.is_upgrading(Game.current_tile_selected):
		print("Already upgrading!")
		return
	var tileTypeData = Game.tileTypes.getByID(tile_type_id)
	assert(Game.tileTypes.canBeUpgraded(tile_type_id))
	if tileTypeData.improve_prize > Game.tilesObj.get_total_gold(Game.current_player_turn):
		print("Not enough money to improve!")
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.upgrade_tile(Game.current_tile_selected)
	action_in_turn_executed()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = Game.current_tile_selected, cell_data = Game.tilesObj.get_cell(Game.current_tile_selected)})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	$UI/ActionsMenu/InGameTileActions.visible = false

func update_troops_move_data( var index: int ):
	actionTileToDo.currentTroopId = $UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.get_item_id(index)
	var startX: int = Game.interactTileSelected.x
	var startY: int = Game.interactTileSelected.y
	var troops_array: Array = Game.tilesObj.get_troops(Game.interactTileSelected)
	
	for troopInActionTileDict in actionTileToDo.troopsToMove:
		if actionTileToDo.currentTroopId == troopInActionTileDict.troop_id:
			$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.text = str(troopInActionTileDict.amountToMove)
			break
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.text = "0"
	for troopDict in troops_array:
		if troopDict.owner != Game.current_player_turn:
			continue
		if troopDict.troop_id == actionTileToDo.currentTroopId:
			$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.text = str(troopDict.amount)
			break

func execute_accept_tiles_actions():
	if !is_local_player_turn() or !can_execute_action():
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	execute_tile_action()
	action_in_turn_executed()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = Game.interactTileSelected, cell_data = Game.tilesObj.get_cell(Game.interactTileSelected)})
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = Game.nextInteractTileSelected, cell_data = Game.tilesObj.get_cell(Game.nextInteractTileSelected)})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func action_in_turn_executed():
	if Game.current_game_status != Game.STATUS.GAME_STARTED:
		return
	actions_available-=1
	if Game.Network.is_client() and is_local_player_turn():
		Game.Network.net_send_event(self.node_id, NET_EVENTS.CLIENT_USE_ACTION, null)
		if actions_available <= 0:
			save_player_info() #Avoid weird stuff in multiplayer
		return
	server_send_game_info()
	if actions_available <= 0:
		move_to_next_player_turn()
		
func execute_tile_action():
	var startX: int = Game.interactTileSelected.x
	var startY: int = Game.interactTileSelected.y
	var endX: int = Game.nextInteractTileSelected.x
	var endY: int = Game.nextInteractTileSelected.y
	var troopToAddExists: bool = false
	
	#First, remove gold and troops from the starting cell
	Game.tilesObj.take_cell_gold(Game.interactTileSelected, actionTileToDo.goldToSend)
	var troops_start_array: Array = Game.tilesObj.get_troops(Game.interactTileSelected)
	var troops_end_array: Array = Game.tilesObj.get_troops(Game.nextInteractTileSelected)
	
	for startTroopDict in troops_start_array:
		if startTroopDict.owner != Game.current_player_turn:
			continue
		for toMoveTroopDict in actionTileToDo.troopsToMove:
			if startTroopDict.troop_id == toMoveTroopDict.troop_id:
				startTroopDict.amount -= toMoveTroopDict.amountToMove
	#Second move and add troops for the ending cell
	Game.tilesObj.add_cell_gold(Game.nextInteractTileSelected, actionTileToDo.goldToSend)
	for toMoveTroopDict in actionTileToDo.troopsToMove:
		if toMoveTroopDict.amountToMove <= 0:
			continue
		troopToAddExists = false
		for endTroopDict in troops_end_array:
			if endTroopDict.owner != Game.current_player_turn:
				continue
			if endTroopDict.troop_id == toMoveTroopDict.troop_id:
				endTroopDict.amount += toMoveTroopDict.amountToMove
				troopToAddExists = true
		if !troopToAddExists:
			Game.tilesObj.add_troops(Game.nextInteractTileSelected, {owner = Game.current_player_turn, troop_id = toMoveTroopDict.troop_id, amount = toMoveTroopDict.amountToMove})

func execute_btn_finish_turn():
	if !is_local_player_turn():
		return
	if Game.current_game_status == Game.STATUS.GAME_STARTED:
		move_to_next_player_turn()

func execute_give_extra_gold():
	if !is_local_player_turn() or !have_selection_points_left():
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.add_cell_gold(Game.current_tile_selected, 10)
	use_selection_point()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = Game.current_tile_selected, cell_data = Game.tilesObj.get_cell(Game.current_tile_selected)})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func execute_add_extra_troops():
	if !is_local_player_turn() or !have_selection_points_left():
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	var extraRecruits: Dictionary = {
		owner = Game.current_player_turn,
		troop_id = Game.troopTypes.getIDByName("recluta"),
		amount = 1000
	}
	Game.tilesObj.add_troops(Game.current_tile_selected, extraRecruits)
	use_selection_point()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {cell = Game.current_tile_selected, cell_data = Game.tilesObj.get_cell(Game.current_tile_selected)})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func use_selection_point():
	Game.playersData[Game.current_player_turn].selectLeft-=1
	if Game.Network.is_client() and Game.playersData[Game.current_player_turn].selectLeft >= 0:
		Game.Network.net_send_event(self.node_id, NET_EVENTS.CLIENT_USE_POINT, null)
		return
	server_send_game_info()
	if Game.playersData[Game.current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()

func save_player_info():
	if !is_local_player_turn():
		return
	saved_player_info.points_to_select_left = Game.playersData[Game.current_player_turn].selectLeft
	saved_player_info.actions_left = actions_available
	Game.tilesObj.save_tiles_data()
	
func undo_actions():
	if !is_local_player_turn():
		return
	Game.tilesObj.update_sync_data()
	Game.playersData[Game.current_player_turn].selectLeft = saved_player_info.points_to_select_left
	actions_available = saved_player_info.actions_left
	Game.tilesObj.restore_previous_tiles_data()
	var dictArrayToSync: Array = Game.tilesObj.get_sync_data()
	if dictArrayToSync.size() > 2:
		print("[WARNING] UNDO ACTIONS MODIFIED MORE THAN 2 TILES!")
	if dictArrayToSync.size() > 0: #Avoid useless syncs
		Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = dictArrayToSync })
	if Game.Network.is_server():
		server_send_game_info()
	elif Game.Network.is_client():
		client_send_game_info()

###########
# NETCODE #
###########

func server_send_game_info(unreliable: bool = false) -> void:
	if !Game.Network.is_server():
		return
	Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_UPDATE_GAME_INFO, {
		game_status = Game.current_game_status,
		player_turn = Game.current_player_turn,
		select_left = Game.playersData[Game.current_player_turn].selectLeft,
		actions_left = actions_available
	}, unreliable)

func client_send_game_info(unreliable: bool = false) -> void:
	if !Game.Network.is_client():
		return
	Game.Network.net_send_event(self.node_id, NET_EVENTS.CLIENT_SEND_GAME_INFO, {
		player_turn = Game.current_player_turn,
		select_left = Game.playersData[Game.current_player_turn].selectLeft,
		actions_left = actions_available
	}, unreliable)
	
#OPTIMIZAR NETCODE, USAR EVENTOS NO SNAPSHOTS!, Y USAR LO MINIMO Y NECESARIO
"""
func server_send_boop() -> Dictionary:
	var boopData = { }
	return boopData

func client_send_boop() -> Dictionary:
	var boopData = { }
	return boopData
func client_process_boop(boopData) -> void:

func server_process_boop(boopData) -> void:
"""

func server_process_event(eventId : int, eventData) -> void:
	match eventId:
		NET_EVENTS.UPDATE_TILE_DATA:
			Game.tilesObj.set_sync_data(eventData.dictArray)
			#Game.tilesObj.set_sync_cell_data(eventData.cell, eventData.cell_data)
		NET_EVENTS.CLIENT_USE_POINT:
			use_selection_point()
		NET_EVENTS.CLIENT_USE_ACTION:
			action_in_turn_executed()
		NET_EVENTS.CLIENT_TURN_END:
			if eventData.player_turn == Game.current_player_turn:
				move_to_next_player_turn()
		NET_EVENTS.CLIENT_SEND_GAME_INFO:
			if	Game.current_player_turn == eventData.player_turn:
				Game.playersData[Game.current_player_turn].selectLeft = eventData.select_left
				actions_available = eventData.actions_left
		_:
			print("Warning: Received unkwown event");
			
func client_process_event(eventId : int, eventData) -> void:
	match eventId:
		NET_EVENTS.SERVER_SEND_PLAYERS_DATA:
			var net_local_player_number: int = Game.get_local_player_number()
			for i in range(Game.playersData.size()):
				if eventData.playerDataArray.size() <= i:
					return
				if i == net_local_player_number:
					continue
				Game.playersData[i].clear()
				Game.playersData[i] = eventData.playerDataArray[i].duplicate(true)
		
		NET_EVENTS.UPDATE_TILE_DATA:
			Game.tilesObj.set_sync_data(eventData.dictArray)
		NET_EVENTS.SERVER_SEND_DELTA_TILES:
			Game.tilesObj.set_sync_data(eventData.dictArray)
		NET_EVENTS.SERVER_UPDATE_GAME_INFO:
			var old_player_turn: int = Game.current_player_turn
			change_game_status( eventData.game_status )
			Game.current_player_turn = eventData.player_turn
			if is_local_player_turn() and old_player_turn == Game.current_player_turn:
				if  Game.playersData[Game.current_player_turn].selectLeft > 0 and eventData.select_left > Game.playersData[Game.current_player_turn].selectLeft:
					return
				if actions_available > 0 and eventData.actions_left > actions_available:
					return
			if is_local_player_turn() and old_player_turn !=  Game.current_player_turn:
				save_player_info()
			Game.playersData[Game.current_player_turn].selectLeft = eventData.select_left
			actions_available = eventData.actions_left
		_:
			print("Warning: Received unkwown event");
