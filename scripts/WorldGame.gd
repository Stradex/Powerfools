class_name WorldGameNode
extends Node2D

# Tropas se pueden mover maximo 5 casilleros solamente, no más (no estoy seguro todavia)
# Poder quemar tierra
# Tabla de puntajes al perder o ganar la partida
# Estadisticas batallas ganadas y perdidas, soldados perdidos, etc...
# Facciones: Germanos, Galos, Persas, Esparta, Tebas, Macedonios, Griegos, Romanos, Cartago, Egipto, Escitas
# Elegir equipos a la hora de entrar al server (SEGUIR)
# Hacer que se puedan ver las tropias propias en territorio aliado.
# Ver las construcciones de los aliados
# Menu con construcciones 
# Mostrar turnos que tardan en hacerse las construcciones y eso
# Chat in game ( Ultimo a hacer )
# Opciones de marcadores en ciertas provincias
# Opciones de mostrar cordenadas en el mapa (A1, B2, ETC...)
# OBSERVACIÓN: Bug que hace que de la nada a veces clientes pierdan plata
# Cuando un jugador pierde, los bosques tienen que tener tribus!
# Que los jugadores reciban la info de manera instantanea
# Pantalla de VICTORIA: LA GUERRA ES PARA PUTOS, COMOS LOS PUTOS QUE JUEGAN ESTE JUEGO. 
# 	-> LA GUERRA NO ES UN JUEGO FOTO DE GHANDI
# Diferentes graficos para las bases
# Que los clientes puedan seleccionar su equipo.
# Que los aliados pueda ver los edificios que puedan 
# Que los clientes reciban informacion en tiempo real
# Hacer metropolis que cueste 60
# Variacion de las piedritas
# LIMPIAR CODIGO
# Que los bots sigan conquistando despues de ver a los players
# Auto save 1: cada 1 minuto, 2: cada 10 minutos, 3: cada 30 minutos
# Opción gráfica de pantalla completa y resoluciones
# Opciones de jugadores en el menu principal y no cuando joineas
# Dificultades de bots: individuales -> NORMAL, DIFICIL, PESADILLA
# PASO 1: LIMPIAR CODIGO
# Modo blitz: que los jugadores juegen su turno todos al mismo tiempo ( Ultra a futuro )

const BOT_MIN_WARRIORS_TO_MOVE: int = 250
const MIN_ACTIONS_PER_TURN: int = 3
const MININUM_TROOPS_TO_FIGHT: int = 5
const EXTRA_CIVILIANS_TO_GAIN_CONQUER: int = 500
const WORLD_GAME_NODE_ID: int = 666 #NODE ID unique
const AUTOSAVE_INTERVAL: float = 60.0 #Every 1 minute
const PLAYER_DATA_SYNC_INTERVAL: float = 2.0
const BOT_SECS_TO_EXEC_ACTION: float = 1.0 #seconds for a bot to execute each action (not turn but every single action)
const BOT_MAX_TURNS_FOR_PLAN: int = 3 #bot can be using same plan as maximum as 3 turns, to avoid bots getting stuck with old plans
const BOT_MINIMUM_GOLD_TO_USE: float = 10.0
const BOT_MINIMUM_WARRIORS_AT_CAPITAL: int = 2000
const BOT_TURNS_TO_RESET_STATS: int = 15

var time_offset: float = 0.0
var player_in_menu: bool = false
var player_can_interact: bool = true
var actions_available: int = MIN_ACTIONS_PER_TURN
var rng: RandomNumberGenerator = RandomNumberGenerator.new();
var node_id: int = -1
var undo_available: bool = true
var turn_number: int = 0

onready var tween: Tween
onready var net_sync_timer: Timer
onready var autosave_timer: Timer
onready var playerdata_sync_timer: Timer
onready var bot_actions_timer: Timer # to emulate that the bot takes time to execute actions
var NetBoop = Game.Boop_Object.new(self);

var bot_territories_to_recover: Array = [] #list with all of he territories a bot lost

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

var path_already_used_by_bot_in_turn: Array = []

###################################################
# GODOT _READY, _PROCESS & FUNDAMENTAL FUNCTIONS
###################################################

func _ready():
	init_timers_and_tweens()
	$UI.init_gui(self)
	init_game()
	for i in range(bot_territories_to_recover.size()):
		bot_territories_to_recover[i].clear()
	bot_territories_to_recover.clear()
	bot_territories_to_recover.resize(Game.MAX_PLAYERS)
	for i in range(bot_territories_to_recover.size()):
		bot_territories_to_recover[i] = [] #array
	
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
		if is_local_player_turn() and !Game.is_current_player_a_bot():
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
	
	if Input.is_action_just_pressed("debug_key"):
		debug_key_pressed()
	
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

func debug_key_pressed():
	var player_current_turn: int = Game.current_player_turn
	var tile_selected: Vector2 = Game.current_tile_selected

###########################
# INIT STUFF
###########################

func init_timers_and_tweens() -> void:
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

func init_game() -> void:
	if Game.tilesObj:
		Game.tilesObj.clear()
	Game.tilesObj = TileGameObject.new(Game.tile_map_size, Game.tileTypes.getIDByName('vacio'), Game.tileTypes, Game.troopTypes, Game.buildingTypes, Game.rng)
	
	if Game.Network.is_multiplayer():
		change_game_status(Game.STATUS.LOBBY_WAIT)
	else:
		change_game_status(Game.STATUS.PRE_GAME)
		start_player_turn(0)
		Game.tilesObj.save_sync_data()

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
	change_game_status(data_to_load.game_current_status)
	#TODO: Sync player data CORRECTLY, RIGHT NOW IT ONLY WORKS FOR 2 PLAYERS AND NOTHING MORE!
	Game.tilesObj.set_all(data_to_load.tiles_data, data_to_load.tile_size)
	Game.current_player_turn = data_to_load.game_current_player_turn
	Game.playersData[Game.current_player_turn].selectLeft = data_to_load.game_points_to_select_left
	actions_available = data_to_load.game_actions_available
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
	if Game.Network.is_client(): #only server executes game logic
		return
	if !Game.is_current_player_a_bot():
		return
	match Game.current_game_status:
		Game.STATUS.PRE_GAME:
			bot_process_pre_game(Game.current_player_turn)
		Game.STATUS.GAME_STARTED:
			bot_process_game(Game.current_player_turn)

func bot_try_desperate_action(bot_number: int, bot_is_having_debt: bool) -> bool: #in case of desperate situation
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	
	if Game.tilesObj.is_cell_in_battle(player_capital_pos):
		return false
	
	var amount_of_territories: int = Game.tilesObj.get_amount_of_player_tiles(bot_number)
	var amount_of_buildings: int = Game.tilesObj.get_count_of_all_buildings_player_have(bot_number)
	var bot_total_gold: float = Game.tilesObj.get_total_gold(bot_number)
	var enemies_next_to_capital: Array = Game.tilesObj.ai_get_neighbor_player_enemies(player_capital_pos, bot_number)
	var bot_available_gold_to_use: float = bot_total_gold
	if bot_is_having_debt:
		bot_available_gold_to_use += Game.tilesObj.get_total_gold_gain_and_losses(bot_number)

	if enemies_next_to_capital.size() <= 0:
		return false
	if bot_available_gold_to_use > BOT_MINIMUM_GOLD_TO_USE and !bot_is_having_debt:
		return false
	if amount_of_buildings >= 2:
		return false
	if amount_of_territories >= 4 and !bot_is_having_debt:
		return false
	
	var strongest_enemy_cell: Vector2 = Game.tilesObj.ai_get_strongest_enemy_cell_in_array(enemies_next_to_capital, bot_number)
	print("[BOT] Trying desperate defense")
	return Game.tilesObj.ai_move_warriors_from_to(player_capital_pos, strongest_enemy_cell, bot_number, 1.0, true)

func bot_is_lacking_troops(bot_number: int, type_of_attitude: int) -> bool:
	var amount_of_territories: int = Game.tilesObj.get_amount_of_player_tiles(bot_number)
	var amount_of_warriors: int = Game.tilesObj.get_all_warriors_count(bot_number)
	match type_of_attitude:
		BOT_ACTIONS.OFFENSIVE:
			return amount_of_warriors <= amount_of_territories*500 #Minimum 500 trops per territory
		BOT_ACTIONS.DEFENSIVE:
			return amount_of_warriors <= amount_of_territories*1000 #Minimum 1000 trops per territory
		BOT_ACTIONS.GREEDY:
			return amount_of_warriors <= amount_of_territories*500 #Minimum 500 trops per territory
	
	return false

func bot_needs_to_upgrade_unproductive_territories(bot_number: int, type_of_attitude: int) -> bool:
	var cells_not_being_productive: Array = Game.tilesObj.ai_get_cells_not_being_productive(bot_number)
	var amount_of_unproductive_territories: int = 0
	for cell in cells_not_being_productive:
		var tileTypeId: int = Game.tileTypes.getIDByName(Game.tilesObj.get_tile_type_dict(cell).name)
		if Game.tileTypes.canBeUpgraded(tileTypeId): #fix: avoid counting tiles that cannot be upgraded, this can make the bot be stuck
			amount_of_unproductive_territories+=1
		
	match type_of_attitude:
		BOT_ACTIONS.OFFENSIVE:
			return amount_of_unproductive_territories > 2 #Allows to have up to 2 unproductive territories
		BOT_ACTIONS.DEFENSIVE:
			return amount_of_unproductive_territories > 1 #Allows to have up to 1 unproductive territories
		BOT_ACTIONS.GREEDY:
			return amount_of_unproductive_territories > 1
	return false

func bot_is_lacking_recruit_buildings(bot_number: int, type_of_attitude: int) -> bool:
	var amount_of_territories: int = Game.tilesObj.get_amount_of_player_tiles(bot_number)
	var amount_of_buildings: int = Game.tilesObj.get_count_of_all_buildings_player_have(bot_number)
	
	if amount_of_buildings <= 0: #avoid dividing by zero LOL
		return true
		
	var ratio_buildings_per_territory: float = float(amount_of_territories)/float(amount_of_buildings)
	match type_of_attitude:
		BOT_ACTIONS.OFFENSIVE:
			return ratio_buildings_per_territory <= 0.25 #25% of territories should have buildings as minimum
		BOT_ACTIONS.DEFENSIVE:
			return ratio_buildings_per_territory <= 0.4 #40% of territories should have buildings as minimum
		BOT_ACTIONS.GREEDY:
			return ratio_buildings_per_territory <= 0.2 #20% of territories should have buildings as minimum
	
	return false

func bot_get_strength_needed_to_defend_capital(bot_number: int) -> Dictionary:
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	if	player_capital_pos == Vector2(-1, -1): 
		return {damage = 0.0, health = 0.0}

	var minimum_health_to_defend: float = float(Game.troopTypes.getByID(Game.troopTypes.getIDByName("recluta")).health)*float(BOT_MINIMUM_WARRIORS_AT_CAPITAL)
	var minimum_damage_to_defend: float = Game.troopTypes.getAverageDamage(Game.troopTypes.getIDByName("recluta"))*float(BOT_MINIMUM_WARRIORS_AT_CAPITAL)
	var enemies_close_to_capital_force: Dictionary = Game.tilesObj.ai_get_enemies_strength_close_to(player_capital_pos, bot_number)
	enemies_close_to_capital_force.damage+=minimum_damage_to_defend
	enemies_close_to_capital_force.health+=minimum_health_to_defend
	
	return enemies_close_to_capital_force

func bot_capital_in_danger(bot_number: int) -> bool:
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	if	player_capital_pos == Vector2(-1, -1): 
		return false
	var capital_health: float = Game.tilesObj.get_own_troops_health(player_capital_pos, bot_number)
	var capital_damage: float = Game.tilesObj.get_own_troops_damage(player_capital_pos, bot_number)
	
	var force_to_defend_capital: Dictionary = bot_get_strength_needed_to_defend_capital(bot_number)
	
	if force_to_defend_capital.damage >= capital_damage or force_to_defend_capital.health >= capital_health: #Capital under danger of attack!
		return true
	return false

func bot_percent_troops_allowed_to_move_from_capital(bot_number: int) -> float:
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	if	player_capital_pos == Vector2(-1, -1) or bot_capital_in_danger(bot_number): 
		return 0.0
		
	if bot_capital_in_danger(bot_number):
		return 0.0
		
	var capital_health: float = Game.tilesObj.get_own_troops_health(player_capital_pos, bot_number)
	var capital_damage: float = Game.tilesObj.get_own_troops_damage(player_capital_pos, bot_number)
	var force_to_defend_capital: Dictionary = bot_get_strength_needed_to_defend_capital(bot_number)

	if capital_health <= 1.0 or capital_damage <= 1.0:
		return 0.0
		
	var health_defend_ratio: float = clamp((capital_health-force_to_defend_capital.health)/capital_health, 0.0, 1.0)
	var damage_defend_ratio: float = clamp((capital_damage-force_to_defend_capital.damage)/capital_damage, 0.0, 1.0)
	return min(health_defend_ratio, damage_defend_ratio)*0.8 #added 25% less just in case
	
func bot_process_game(bot_number: int) -> void:
	if !Game.is_current_player_a_bot():
		return

	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	if	player_capital_pos == Vector2(-1, -1): #player lost
		action_in_turn_executed()
		return

	var action_executed: bool = false
	var bot_is_having_debt: bool = Game.tilesObj.get_total_gold_gain_and_losses(bot_number) <= 0
	var enemy_reachable_capital: Vector2 = Game.tilesObj.ai_get_reachable_player_capital(bot_number)
	var bot_total_gold: float = Game.tilesObj.get_total_gold(bot_number)
	var bot_available_gold_to_use: float = bot_total_gold
	
	if bot_is_having_debt:
		bot_available_gold_to_use += Game.tilesObj.get_total_gold_gain_and_losses(bot_number)

	if bot_available_gold_to_use <= 0:
		Game.tilesObj.add_cell_gold(player_capital_pos, BOT_MINIMUM_GOLD_TO_USE)
	
	var type_of_attitude: int = bot_get_type_of_attitude(bot_number)
	
	match type_of_attitude:
		BOT_ACTIONS.OFFENSIVE:
			print("[BOT] Playing ofensive")
			action_executed = bot_play_agressive(bot_number, player_capital_pos, bot_is_having_debt)
		BOT_ACTIONS.DEFENSIVE:
			print("[BOT] Playing defensive")
			action_executed = bot_play_defensive(bot_number, player_capital_pos, bot_is_having_debt)
		BOT_ACTIONS.GREEDY:
			print("[BOT] Playing greedy")
			action_executed = bot_play_greedy(bot_number, player_capital_pos, bot_is_having_debt)
	
	if !action_executed:
		print("bot doing nothing...")
	
	action_in_turn_executed()

func bot_play_agressive(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool) -> bool:
	if bot_try_to_defend_own_capital(bot_number, player_capital_pos):
		return true
	#last argument true = try to attack enemies capital that are close to allies territories too
	elif bot_try_to_attack_enemy_capital(bot_number, player_capital_pos, bot_is_having_debt, BOT_ACTIONS.OFFENSIVE): 
		return true	
	elif bot_try_to_attack_enemy(bot_number, BOT_ACTIONS.OFFENSIVE, bot_is_having_debt):
		return true
	elif bot_try_to_defend_own_territory(bot_number, player_capital_pos):
		return true
	elif bot_try_to_recover_territory(bot_number, player_capital_pos, bot_is_having_debt):
		return true
	elif bot_try_buy_or_upgrade(bot_number, BOT_ACTIONS.OFFENSIVE):
		return true
	elif bot_try_desperate_action(bot_number, bot_is_having_debt):
		return true
	elif bot_try_to_move_troops_to_frontiers(bot_number):
		return true
	return false
		
func bot_play_defensive(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool) -> bool:
	if bot_try_to_defend_own_capital(bot_number, player_capital_pos):
		return true
	elif bot_try_to_defend_own_territory(bot_number, player_capital_pos):
		return true
	elif bot_try_to_recover_territory(bot_number, player_capital_pos, bot_is_having_debt):
		return true
	elif bot_try_buy_or_upgrade(bot_number, BOT_ACTIONS.DEFENSIVE):
		return true
	elif bot_try_to_attack_enemy(bot_number, BOT_ACTIONS.DEFENSIVE, bot_is_having_debt):
		return true
	elif bot_try_to_attack_enemy_capital(bot_number, player_capital_pos, bot_is_having_debt, BOT_ACTIONS.DEFENSIVE):
		return true	
	elif bot_try_desperate_action(bot_number, bot_is_having_debt):
		return true
	elif bot_try_to_move_troops_to_frontiers(bot_number):
		return true
	return false
	
func bot_play_greedy(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool) -> bool:
	if bot_try_to_defend_own_capital(bot_number, player_capital_pos):
		return true
	elif bot_try_to_recover_territory(bot_number, player_capital_pos, bot_is_having_debt):
		return true
	elif bot_try_buy_or_upgrade(bot_number, BOT_ACTIONS.DEFENSIVE):
		return true
	elif bot_try_to_attack_enemy_capital(bot_number, player_capital_pos, bot_is_having_debt, BOT_ACTIONS.GREEDY):
		return true	
	elif bot_try_to_defend_own_territory(bot_number, player_capital_pos):
		return true
	elif bot_try_to_attack_enemy(bot_number, BOT_ACTIONS.GREEDY, bot_is_having_debt):
		return true
	elif bot_try_desperate_action(bot_number, bot_is_having_debt):
		return true
	elif bot_try_to_move_troops_to_frontiers(bot_number):
		return true
	return false

func bot_try_to_move_troops_to_frontiers(bot_number: int) -> bool:
	var inner_territories: Array = Game.tilesObj.ai_get_inner_territories(bot_number)
	var outer_territories: Array = Game.tilesObj.ai_get_outer_territories(bot_number)
	
	if outer_territories.size() <= 0 or inner_territories.size() <= 0:
		return false
	
	var cells_in_danger: Array = Game.tilesObj.ai_get_all_cells_in_danger(bot_number)
	var cells_with_warriors: Array = Game.tilesObj.get_all_tiles_with_warriors_from_player(bot_number, BOT_MIN_WARRIORS_TO_MOVE)
	var all_bot_cells: Array = Game.tilesObj.get_all_player_tiles(bot_number)
	var cells_without_warriors: Array = Game.Util.array_substract(all_bot_cells, cells_with_warriors)
	inner_territories = Game.Util.array_substract(inner_territories, cells_in_danger)
	inner_territories = Game.Util.array_substract(inner_territories, cells_without_warriors)
	
	if inner_territories.size() <= 0:
		return false
	
	#var cell_to_move_troops_from: Vector2 = Game.tilesObj.ai_get_strongest_available_cell_in_array(inner_territories, bot_number)
	var cell_to_move_troops_towards: Vector2 = Game.tilesObj.ai_get_weakest_cell_in_array(outer_territories, bot_number)
	if bot_move_troops_towards_pos(cell_to_move_troops_towards, bot_number):
		print("[BOT] moving troops towards borders...")
		return true
	return false

func bot_try_to_recover_territory(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool) -> bool:
	var territories_to_recover: Array = Game.tilesObj.ai_order_cells_by_distance_to(bot_territories_to_recover[bot_number], player_capital_pos)
	for to_recover_cell in territories_to_recover:
		if Game.tilesObj.get_owner(to_recover_cell) == bot_number:
			continue
		if !Game.tilesObj.ai_have_strength_to_conquer(to_recover_cell, bot_number) and !bot_is_having_debt:
			continue
		if bot_move_troops_towards_pos(to_recover_cell, bot_number, bot_is_having_debt):
			print("[BOT] recovering territory...")
			return true
	return false

func bot_try_to_defend_own_capital(bot_number: int, player_capital_pos: Vector2) -> bool:
	var capital_in_danger: bool = bot_capital_in_danger(bot_number)
	if !capital_in_danger:
		return false
	print("BOT trying to defend own capital")
	return bot_move_troops_towards_pos(player_capital_pos, bot_number, true) #Fixme: Force to move towards capital

func bot_try_to_attack_enemy_capital(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool, type_of_attitude: int) -> bool:
	var enemy_reachable_capital: Vector2 = Vector2(-1, -1)
	var force_to_attack_enemy_capital: bool = bot_is_having_debt
	match type_of_attitude:
		BOT_ACTIONS.GREEDY:
			enemy_reachable_capital = Game.tilesObj.ai_get_reachable_player_capital(bot_number)
		BOT_ACTIONS.DEFENSIVE:
			enemy_reachable_capital = Game.tilesObj.ai_get_reachable_player_capital(bot_number)
		BOT_ACTIONS.OFFENSIVE:
			force_to_attack_enemy_capital = true
			enemy_reachable_capital = Game.tilesObj.ai_get_reachable_player_capital(bot_number, true) #Ofensive bots can attack capitals that are only close to allies territories too
	
	if enemy_reachable_capital != Vector2(-1, -1):
		#var path_to_enemy_capital: Array = Game.tilesObj.ai_get_attack_path_from_to(player_capital_pos, enemy_reachable_capital, bot_number)
		#var strongest_enemy_cell_in_path: Vector2 = Game.tilesObj.ai_get_strongest_enemy_cell_in_path(path_to_enemy_capital, bot_number)
		if Game.tilesObj.ai_have_strength_to_conquer(enemy_reachable_capital, bot_number) or bot_is_having_debt:
			if bot_move_troops_towards_pos(enemy_reachable_capital, bot_number, force_to_attack_enemy_capital):
				return true
	
	return false

func bot_try_to_attack_enemy(bot_number: int, type_of_attitude: int, bot_is_having_debt: int) -> bool:
	var cell_to_attack: Vector2 = bot_get_cell_to_attack(bot_number, type_of_attitude)
	if !Game.tilesObj.ai_have_strength_to_conquer(cell_to_attack, bot_number) and !bot_is_having_debt:
		return false
	return bot_move_troops_towards_pos(cell_to_attack, bot_number, bot_is_having_debt)
		
func bot_try_to_defend_own_territory(bot_number: int, player_capital_pos: Vector2) -> bool:
	var cells_to_defend: Array = Game.tilesObj.ai_order_cells_by_distance_to(Game.tilesObj.ai_get_all_cells_in_danger(bot_number), player_capital_pos)
	for cell in cells_to_defend:
		if bot_move_troops_towards_pos(cell, bot_number): # Try to defend this position
			return true
	return false

func bot_try_to_upgrade_territory(bot_number: int) -> bool:
	var bot_cells: Array = Game.tilesObj.get_all_player_tiles(bot_number)
	for cell in bot_cells:
		if Game.tilesObj.can_be_upgraded(cell, bot_number):
			if bot_upgrade_territory(cell, bot_number): #upgraded
				print("[BOT] upgrading territory")
				return true
	return false

func bot_try_to_upgrade_unproductive_territories(bot_number: int) -> bool:
	var unproductive_territories: Array = Game.tilesObj.ai_get_cells_not_being_productive(bot_number)
	for cell in unproductive_territories:
		if Game.tilesObj.can_be_upgraded(cell, bot_number):
			if bot_upgrade_territory(cell, bot_number): #upgraded
				print("[BOT] upgrading unproductive territory")
				return true
	return false

func bot_try_to_make_a_building(bot_number: int) -> bool:
	var cells_without_buildings: Array = Game.tilesObj.ai_get_all_cells_without_buildings(bot_number)
	if cells_without_buildings.size() > 0 and bot_buy_building_at_cell(cells_without_buildings[rng.randi_range(0, cells_without_buildings.size()-1)], bot_number):
		print("[BOT] making a building")
		return true
		
	return false

func bot_try_to_recruit_troops(bot_number: int) -> bool:
	var cells_that_can_recruit: Array = Game.tilesObj.ai_get_all_cells_available_to_recruit(bot_number)
	if cells_that_can_recruit.size() > 0 and bot_make_new_troops(cells_that_can_recruit[rng.randi_range(0, cells_that_can_recruit.size()-1)], bot_number):
		print("[BOT] recruiting troops")
		return true
	return false

func bot_try_buy_or_upgrade(bot_number: int, type_of_attitude: int) -> bool:
	var bot_gains: float = Game.tilesObj.get_total_gold_gain_and_losses(bot_number)
	var bot_total_gold: float = Game.tilesObj.get_total_gold(bot_number)
	var bot_available_gold_to_use: float = bot_total_gold
	if bot_gains < 0.0:
		 bot_available_gold_to_use += bot_gains

	if bot_available_gold_to_use <= BOT_MINIMUM_GOLD_TO_USE: #avoid buying stuff in case bot does not have good money
		return false

	if bot_needs_to_upgrade_unproductive_territories(bot_number, type_of_attitude):
		print("[BOT] is having too many unproductive territories...")
		return bot_try_to_upgrade_unproductive_territories(bot_number)
	elif bot_is_lacking_troops(bot_number, type_of_attitude):
		print("[BOT] is lacking troops...")
		return bot_try_to_recruit_troops(bot_number) or bot_try_to_make_a_building(bot_number)
	elif bot_is_lacking_recruit_buildings(bot_number, type_of_attitude):
		print("[BOT] is lacking buildings...")
		return bot_try_to_make_a_building(bot_number)

	match type_of_attitude:
		BOT_ACTIONS.GREEDY:
			if bot_try_to_upgrade_unproductive_territories(bot_number):
				return true
			elif bot_try_to_upgrade_territory(bot_number):
				return true
			elif bot_try_to_make_a_building(bot_number):
				return true
			elif bot_try_to_recruit_troops(bot_number):
				return true
		BOT_ACTIONS.DEFENSIVE:
			if bot_try_to_upgrade_unproductive_territories(bot_number):
				return true
			elif bot_try_to_make_a_building(bot_number):
				return true
			elif bot_try_to_recruit_troops(bot_number):
				return true
			elif bot_try_to_upgrade_territory(bot_number):
				return true
		BOT_ACTIONS.OFFENSIVE:
			if bot_try_to_make_a_building(bot_number):
				return true
			elif bot_try_to_recruit_troops(bot_number):
				return true
			elif bot_try_to_upgrade_unproductive_territories(bot_number):
				return true
			elif bot_try_to_upgrade_territory(bot_number):
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
	Game.tilesObj.queue_upgrade_cell(cell_to_upgrade)
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

func bot_get_cell_to_attack(bot_number: int, type_of_attitude: int) -> Vector2:
	var cell_to_attack: Vector2
	
	match type_of_attitude:
		BOT_ACTIONS.GREEDY:
			cell_to_attack =  Game.tilesObj.ai_get_richest_enemy_cell(bot_number)
			#awful code, I am sorry
			if cell_to_attack == Vector2(-1, -1): 
				cell_to_attack = Game.tilesObj.ai_get_richest_enemy_cell(bot_number, true) #use allies territories
		BOT_ACTIONS.DEFENSIVE:
			cell_to_attack = Game.tilesObj.ai_get_closest_to_capital_player_enemy_cell(bot_number)
			if cell_to_attack == Vector2(-1, -1): 
				cell_to_attack = Game.tilesObj.ai_get_closest_to_capital_enemy_cell(bot_number)
		BOT_ACTIONS.OFFENSIVE:
			cell_to_attack = Game.tilesObj.ai_get_weakest_player_enemy_cell(bot_number)
			if cell_to_attack == Vector2(-1, -1):
				cell_to_attack = Game.tilesObj.ai_get_weakest_player_enemy_cell(bot_number, true)
			if cell_to_attack == Vector2(-1, -1):
				cell_to_attack = Game.tilesObj.ai_get_weakest_enemy_cell(bot_number)
			if cell_to_attack == Vector2(-1, -1):
				cell_to_attack = Game.tilesObj.ai_get_weakest_enemy_cell(bot_number, true)
	
	return cell_to_attack

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

func bot_make_new_troops(cell_pos: Vector2, bot_number: int) -> bool:
	if !is_recruiting_possible(cell_pos, bot_number):
		return false
	var cell_data: Dictionary = Game.tilesObj.get_cell(cell_pos)
	var currentBuildingType = Game.buildingTypes.getByID(cell_data.building_id)
	var idTroopsToRecruit: int = currentBuildingType.id_troop_generate
	var ammountOfTroopsToRecruit: int = 0
	
	var upcomingTroopsDict: Dictionary = {
		owner = bot_number,
		troop_id= currentBuildingType.id_troop_generate,
		amount = int(float(currentBuildingType.deploy_amount)*Game.get_bot_troops_multiplier(bot_number)),
		turns_left = currentBuildingType.turns_to_deploy_troops
	}
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.take_cell_gold(cell_pos, float(currentBuildingType.deploy_prize)*Game.get_bot_discount_multiplier(bot_number))
	Game.tilesObj.append_upcoming_troops(cell_pos, upcomingTroopsDict)
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	return true

func bot_clear_cache_path_to_follow(bot_number: int) -> void:
	Game.playersData[bot_number].bot_stats.path_to_follow.clear()

func bot_cache_path_to_follow_pop_front(bot_number: int) -> void:
	Game.playersData[bot_number].bot_stats.path_to_follow.pop_front()

func bot_update_cache_path_to_follow(bot_number: int, new_path_to_follow: Array) -> void:
	bot_clear_cache_path_to_follow(bot_number)
	Game.playersData[bot_number].bot_stats.path_to_follow = new_path_to_follow.duplicate(true)

func check_if_bot_can_use_cache_path_to_follow(bot_number: int, start_pos: Vector2, end_pos: Vector2) -> bool:
	if Game.playersData[bot_number].bot_stats.path_to_follow.size() < 2:
		return false
	var first_path_element: Vector2 = Game.playersData[bot_number].bot_stats.path_to_follow[0]
	var last_path_element: Vector2 = Game.playersData[bot_number].bot_stats.path_to_follow[Game.playersData[bot_number].bot_stats.path_to_follow.size()-1]
	
	return first_path_element == start_pos and last_path_element == end_pos

func bot_get_next_pos_in_cache_path_to_follow(bot_number: int) -> Vector2:
	if Game.playersData[bot_number].bot_stats.path_to_follow.size() < 2:
		return Vector2(-1, -1)
	return Game.playersData[bot_number].bot_stats.path_to_follow[1]

func bot_move_troops_from_to(start_pos: Vector2, end_pos: Vector2, bot_number: int, force_to_move: bool = false) -> bool:
	var percent_troops_to_move: float = 1.0
	if start_pos == Vector2(-1, -1) or end_pos == Vector2(-1, -1) or start_pos == end_pos:
		return false
	if !Game.tilesObj.is_next_to_tile(start_pos, end_pos):
		return false

	var bot_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	
	if start_pos == bot_capital_pos:
		percent_troops_to_move = float(bot_percent_troops_allowed_to_move_from_capital(bot_number))
		if percent_troops_to_move <= 0.1:
			return false
			
	var amount_troops_to_move: int = int(floor(float(Game.tilesObj.get_warriors_count(start_pos, bot_number))*percent_troops_to_move))
	if  amount_troops_to_move < BOT_MIN_WARRIORS_TO_MOVE:
		return false
	
	if end_pos == bot_capital_pos:
		force_to_move = true #always move everything towards own capital
		
	if force_to_move or Game.tilesObj.ai_can_conquer_enemy_pos(start_pos, end_pos, bot_number):
		if start_pos == bot_capital_pos:
			force_to_move = false #hack to avoid moving all trops from capital and only the needed percent
		return Game.tilesObj.ai_move_warriors_from_to(start_pos, end_pos, bot_number, percent_troops_to_move, force_to_move)
		
	return false

func bot_move_troops_towards_pos(pos_to_move: Vector2, bot_number: int, force_to_move: bool = false) -> bool:
	if pos_to_move == Vector2(-1, -1):
		return false
	var pos_to_move_towards: Vector2 = Vector2(-1, -1)
	var start_pos_to_move: Vector2 = Vector2(-1, -1)
	var bot_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	var available_cells_to_use: Array
	
	if force_to_move:
		available_cells_to_use = Game.tilesObj.get_all_tiles_with_warriors_from_player(bot_number, BOT_MIN_WARRIORS_TO_MOVE)
		available_cells_to_use = Game.Util.array_search_and_remove(available_cells_to_use, pos_to_move)
	else:
		available_cells_to_use = Game.tilesObj.ai_get_cells_available_to_conquer_pos(bot_number, pos_to_move, BOT_MIN_WARRIORS_TO_MOVE)
	
	available_cells_to_use = Game.tilesObj.ai_order_cells_by_distance_to(available_cells_to_use, pos_to_move)
	
	for start_pos in available_cells_to_use:
		if Game.tilesObj.is_cell_in_battle(start_pos):
			continue
		# Try to use cache path, to avoid problems
		if check_if_bot_can_use_cache_path_to_follow(bot_number, start_pos, pos_to_move) and bot_move_troops_from_to(start_pos, bot_get_next_pos_in_cache_path_to_follow(bot_number), bot_number, force_to_move):
			bot_cache_path_to_follow_pop_front(bot_number)
			$Tiles.debug_tile_path([start_pos, pos_to_move])
			#print("[BOT] moving troops using cached path...")
			return true
			
		var path_to_use: Array = Game.tilesObj.ai_get_attack_path_from_to(start_pos, pos_to_move, bot_number)
		path_to_use = Game.Util.array_search_and_remove(path_to_use, start_pos)
		if path_to_use.size() <= 0:
			continue
		
		if bot_move_troops_from_to(start_pos, path_to_use[0], bot_number, force_to_move):
			if path_to_use.size() > 1:
				bot_update_cache_path_to_follow(bot_number, path_to_use)
			$Tiles.debug_tile_path([start_pos, pos_to_move])
			#print("[BOT] Moving troops...")
			return true
	
	bot_clear_cache_path_to_follow(bot_number) #clear it in case it failed
	return false

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
	
	#use_selection_point()
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

func bot_get_type_of_attitude(bot_number: int) -> int:
	var defensive_points:float = Game.playersData[bot_number].bot_stats.defensiveness
	var ofensive_points:float = Game.playersData[bot_number].bot_stats.aggressiveness
	var greedy_points:float = Game.playersData[bot_number].bot_stats.avarice
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
	Game.tilesObj.add_cell_gold(cell, 10.0*Game.get_bot_extra_gold_multiplier(bot_number))
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func bot_execute_add_extra_troops(bot_number: int, cell: Vector2):
	if !Game.is_current_player_a_bot():
		return
	save_player_info()
	give_troops_to_player_and_sync(cell, bot_number, "recluta", int(round(1000.0*Game.get_bot_troops_multiplier(bot_number))))

func give_troops_to_player_and_sync(cell: Vector2, player_number: int, troop_name: String, amount_to_give: int) -> void:
	Game.tilesObj.update_sync_data()
	var extraTroops: Dictionary = {
		owner = player_number,
		troop_id = Game.troopTypes.getIDByName(troop_name),
		amount = amount_to_give
	}
	Game.tilesObj.add_troops(cell, extraTroops)
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

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

func player_can_select_tile_as_first_interaction(tile_pos: Vector2, player_number: int) -> bool:
	if Game.tilesObj.belongs_to_player(tile_pos, player_number):
		return true
	if Game.tilesObj.belongs_to_allies(tile_pos, player_number) and Game.tilesObj.player_has_troops_in_cell(tile_pos, player_number):
		return true
	return false

func game_interact():
	if !is_local_player_turn():
		return
	if Game.interactTileSelected == Game.current_tile_selected or Game.nextInteractTileSelected == Game.current_tile_selected:
		return
	
	if Game.interactTileSelected == Vector2(-1, -1) or (Game.interactTileSelected != Vector2(-1, -1) and Game.nextInteractTileSelected != Vector2(-1, -1)):
		if !player_can_select_tile_as_first_interaction(Game.current_tile_selected, Game.current_player_turn):
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
	if Game.tilesObj.is_owned_by_any_player(Game.current_tile_selected):
		if Game.tilesObj.belongs_to_player(Game.current_tile_selected, Game.current_player_turn):
			$UI/ActionsMenu/ExtrasMenu.visible = true
		return
	if Game.tilesObj.is_next_to_player_enemy_territory(Game.current_tile_selected, Game.current_player_turn):
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
	
	#add rocks first
	Game.tilesObj.pcg_generate_rocks(rng.randf_range(0.25, 0.50))
	#Game.tilesObj.recover_sync_data()
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			if !Game.tilesObj.is_owned_by_any_player(Vector2(x, y)) and Game.tilesObj.is_tile_walkeable(Vector2(x, y)):
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
	
	if Game.current_game_status == Game.STATUS.GAME_STARTED:
		Game.playersData[player_number].turns_played+=1
		if Game.is_current_player_a_bot():
			print(Game.playersData[player_number].turns_played % BOT_TURNS_TO_RESET_STATS)
			if Game.playersData[player_number].turns_played % BOT_TURNS_TO_RESET_STATS == 0:
				Game.bot_reset_stats(player_number)
			path_already_used_by_bot_in_turn.clear()
			
	
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
	Game.tilesObj.recover_sync_data()
	
	update_gold_stats(playerNumber)
	process_tiles_turn_end(playerNumber)
	if did_player_lost(playerNumber):
		destroy_player(playerNumber)

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

func process_tiles_turn_end(playerNumber: int) -> void:
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			process_tile_upgrade(Vector2(x, y), playerNumber)
			process_tile_builings(Vector2(x, y), playerNumber)
			process_tile_recruitments(Vector2(x, y), playerNumber)
			process_tile_battles(Vector2(x, y))
			update_tile_owner(Vector2(x, y))

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
			if Game.are_player_allies(damageToDo.owner, troopDict.owner):
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
			if Game.are_player_allies(damageToDo.owner, troopDict.owner):
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
		
		if !Game.are_player_allies(Game.tilesObj.get_cell_owner(tile_pos), playerWhoWonId): #do not take your allies troops if you were helping with the defense.
			
			var bot_number: int = -1
			if Game.is_player_a_bot(Game.tilesObj.get_cell_owner(tile_pos)):
				bot_number = Game.tilesObj.get_cell_owner(tile_pos)
				if bot_territories_to_recover[bot_number].find(tile_pos) == -1:
					bot_territories_to_recover[bot_number].append(tile_pos)
			elif Game.is_player_a_bot(playerWhoWonId):
				bot_number = playerWhoWonId
				bot_territories_to_recover[bot_number] = Game.Util.array_search_and_remove(bot_territories_to_recover[bot_number], tile_pos)
				print(bot_territories_to_recover)
				
			Game.tilesObj.set_cell_owner(tile_pos, playerWhoWonId)

		if Game.is_player_a_bot(playerWhoWonId):
			Game.tilesObj.add_cell_gold(tile_pos, 5.0) #give extra gold to bot when conquers
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
		Game.tilesObj.finish_upgrade_cell(tile_pos, playerNumber)

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
	if !player_can_select_tile_as_first_interaction(startTile, playerNumber):
		return false
	if !Game.tilesObj.is_next_to_tile(startTile,endTile):
		return false
	if !Game.tilesObj.belongs_to_player(endTile, playerNumber) and Game.tilesObj.get_warriors_count(startTile, playerNumber) <= 0: #don't allow civilians to invade
		return false
	if !Game.tilesObj.is_tile_walkeable(startTile) or !Game.tilesObj.is_tile_walkeable(endTile):
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
				add_tribal_society_to_tile(Vector2(x, y))
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

func gui_player_selected(index: int):
	if Game.Network.is_client():
		return
	var player_text: String = $UI/ActionsMenu/WaitingPlayers/VBoxContainer/PlayersList.get_item_text(index)
	var cut_pos: int = player_text.find(":")
	player_text.erase(cut_pos, player_text.length()-cut_pos)
	var player_index: int = int(player_text)
	$UI.gui_open_edit_player(player_index)
	print("index Selected: " + str(player_index))

func gui_add_bot():
	if Game.Network.is_client():
		return
	Game.add_player(-1, "bot", 758, -1, true)

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
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	
func execute_buy_building(var selectedBuildTypeId: int):
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(Game.current_player_turn)
	if !is_local_player_turn() or !can_execute_action() or !Game.tilesObj.can_buy_building_at_cell(Game.current_tile_selected, selectedBuildTypeId, getTotalGoldAvailable, Game.current_player_turn): 
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.buy_building(Game.current_tile_selected, selectedBuildTypeId)
	action_in_turn_executed()
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
	Game.tilesObj.queue_upgrade_cell(Game.current_tile_selected)
	action_in_turn_executed()
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
	give_troops_to_player_and_sync(Game.current_tile_selected, Game.current_player_turn, "recluta", 1000)
	use_selection_point()

func use_selection_point():
	if Game.Network.is_client() and !is_local_player_turn():
		return
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
			if eventData.player_turn == Game.current_player_turn and !Game.is_current_player_a_bot():
				move_to_next_player_turn()
		NET_EVENTS.CLIENT_SEND_GAME_INFO:
			if	Game.current_player_turn == eventData.player_turn and !Game.is_current_player_a_bot():
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
					Game.playersData[i].team = eventData.playerDataArray[i].team
					#Game.playersData[i].alive = eventData.playerDataArray[i].alive
				else:
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
			print("Warning: Received unkwown event")
