class_name WorldGameNode
extends Node2D

# Poder vender territorios
# Tabla de puntajes al perder o ganar la partida
# Estadisticas batallas ganadas y perdidas, soldados perdidos, etc...
# Facciones: Germanos, Galos, Persas, Esparta, Tebas, Macedonios, Griegos, Romanos, Cartago, Egipto, Escitas
# Ver las construcciones de los aliados
# Menu con construcciones
# Mostrar turnos que tardan en hacerse las construcciones y eso
# Chat in game ( Ultimo a hacer )
# Opciones de marcadores en ciertas provincias
# Que los jugadores reciban la info de manera instantanea
# Pantalla de VICTORIA: LA GUERRA ES PARA PUTOS, COMOS LOS PUTOS QUE JUEGAN ESTE JUEGO 
# 	-> LA GUERRA NO ES UN JUEGO FOTO DE GHANDI
# Diferentes graficos para las bases
# Que los clientes puedan seleccionar su equipo
# Que los aliados pueda ver los edificios que puedan
# Que los clientes reciban informacion en tiempo real
# Auto save 1: cada 1 minuto, 2: cada 10 minutos, 3: cada 30 minutos
# Cuanto terreno tenes info
# Dificultad experto.
# Que las tropas no se generen una vez conquistado un territorio
# Que los bots puedan tener formaciones
# No poder robarle talentos a tus aliados del orto jaja
# Fixear que la duración de la partida en los clientes dice cero.
# Estadisticas: Todas las batallas (equipos en batalla, cantidad de tropas, tropas al finalizar la batalla) [TOP 10]
# sEGUNDA Vez que se entra crashea
# Que los civiles aparezcan arriba de todo cuando pones tile info
# Edificio, intel. (Podes moverlo solo una vez por turno, que ilumine solo los casilleros de alado)
# Implementar sistema de lago

const MIN_ACTIONS_PER_TURN: int = 3
const MININUM_TROOPS_TO_FIGHT: int = 5
const EXTRA_CIVILIANS_TO_GAIN_CONQUER: int = 500
const WORLD_GAME_NODE_ID: int = 666 #NODE ID unique
const AUTOSAVE_INTERVAL: float = 60.0 #Everyminute
const PLAYER_DATA_SYNC_INTERVAL: float = 4.0
const GAME_STATS_SYNC_INTERVAL: float = 5.0
const BOT_SECS_TO_EXEC_ACTION: float = 1.0 #seconds for a bot to execute each action (not turn but every single action)
const BOT_TURNS_TO_RESET_STATS: int = 15
const EXTRA_CIVILIANS_PER_TURN: int = 200

var time_offset: float = 0.0
var player_in_menu: bool = false
var player_can_interact: bool = true
var actions_available: int = MIN_ACTIONS_PER_TURN
var rng: RandomNumberGenerator = RandomNumberGenerator.new();
var node_id: int = -1
var undo_available: bool = false
var turn_number: int = 0
var game_start_time: float = 0.0

onready var tween: Tween
onready var server_tween: Tween
onready var net_sync_timer: Timer
onready var autosave_timer: Timer
onready var playerdata_sync_timer: Timer
onready var gamestats_sync_timer: Timer
onready var bot_actions_timer: Timer # to emulate that the bot takes time to execute actions
var NetBoop = Game.Boop_Object.new(self);

var players_stats: Array = []
var battle_stats: Array = []
var client_stats: Dictionary = {
	battles_won = 0,
	battles_lost = 0,
	battles_total = 0
}
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
	UPDATE_TILE_NAME, #To avoid desync problems just send the name when a client changes the name of a tile
	CLIENT_USE_POINT,
	CLIENT_USE_ACTION,
	CLIENT_TURN_END,
	SERVER_SEND_DELTA_TILES,
	SERVER_UPDATE_GAME_INFO,
	CLIENT_SEND_GAME_INFO,
	SERVER_SEND_PLAYERS_DATA,
	SERVER_FORCE_PLAYER_DATA,
	SERVER_SEND_GAME_ENDED,
	SERVER_SEND_INFO_MESSAGE,
	SERVER_SEND_GAMESTATS_DATA,
	MAX_EVENTS
}
###################################################
# GODOT _READY, _PROCESS & FUNDAMENTAL FUNCTIONS
###################################################

func _ready():
	Game.prepare_new_game()
	init_timers_and_tweens()
	init_game()
	get_tree().connect("network_peer_connected", self, "_on_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_player_disconnect")
	get_tree().connect("server_disconnected", self, "_server_disconnected")
	Game.connect("player_reconnects", self, "_player_reconnects")
	$UI.init_gui(self)
	if Game.Network.is_multiplayer():
		$UI/ActionsMenu/WaitingPlayers.visible = true
	Game.Network.register_synced_node(self, WORLD_GAME_NODE_ID);

func _process(delta):
	var player_was_in_menu: bool = player_in_menu
	player_in_menu = is_player_menu_open()
	if player_was_in_menu != player_in_menu: #little delay to avoid player spaming actions and also bugs
		player_can_interact = false
		tween.interpolate_callback(self, 0.25, "allow_player_interact")
		tween.start()

	if !player_in_menu and player_can_interact:
		$Tiles.update_selection_tiles()
		
	time_offset+=delta
	if (time_offset > 1.0/Game.GAME_FPS):
		time_offset = 0.0
		game_frame(player_in_menu or !player_can_interact)

func game_frame(player_in_menu: bool) -> void:
	$UI.gui_update_game_info()
	$UI.update_server_info()
	$UI/HUD/GameInfo/HBoxContainer/ActionsLeftText.text = str(actions_available)
	$UI/HUD/PreGameInfo/HBoxContainer/PointsLeftText.text = str(Game.playersData[Game.current_player_turn].selectLeft)
	game_on()
	$Tiles.update_building_tiles()
	if player_in_menu:
		$UI.hide_wait_finish_for_player()
		$Tiles.update_tiles_bit_masks()
		return

	$UI.update_lobby_info()
	$UI.gui_update_tile_info(Game.current_tile_selected)
	$UI.gui_update_civilization_info()
	#$Tiles.update_visibility_tiles()
	if is_local_player_turn():
		$UI.hide_wait_for_player()
	else:
		$UI.show_wait_for_player()
	$Tiles.update_tiles_bit_masks()

func _input(event):

	if Input.is_action_just_pressed("zoom_in_hud"):
		$Tiles.position = Vector2(0.0, 0.0)
		$Tiles.scale = Vector2(1.0, 1.0)
		$UI.init_tile_coordinates()
	elif Input.is_action_just_pressed("zoom_out_hud"):
		$Tiles.position = Vector2(60.0, 0.0)
		$Tiles.scale = Vector2(0.9, 0.9)
		$UI.init_tile_coordinates()

	if Input.is_action_just_pressed("toggle_ingame_menu"):
		if !player_in_menu and player_can_interact:
			if Game.interactTileSelected != Vector2(-1, -1):
				Game.interactTileSelected = Vector2(-1, -1)
				Game.nextInteractTileSelected = Vector2(-1, -1)
			else:
				$UI.gui_open_ingame_menu_window(is_local_player_turn())
		else:
			$UI.close_all_windows()
			if Game.current_game_status == Game.STATUS.LOBBY_WAIT:
				$UI.open_lobby_window()

	if player_in_menu or !player_can_interact:
		return

	if Input.is_action_just_pressed("toggle_tile_info"):
		$UI/HUD/TileInfo.visible = !$UI/HUD/TileInfo.visible
	if Input.is_action_just_pressed("toggle_civ_info"):
		$UI/HUD/CivilizationInfo.visible = !$UI/HUD/CivilizationInfo.visible

	if Input.is_action_just_pressed("toggle_coords"):
		$UI.show_game_coords()	
	elif Input.is_action_just_released("toggle_coords"):
		$UI.hide_game_coords()	

	if Input.is_action_just_pressed("toggle_stats"):
		$UI.ui_open_game_stats()
	elif Input.is_action_just_released("toggle_stats"):
		$UI.ui_close_game_stats()
	
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

func debug_key_pressed():
	if Game.Network.is_server():
		save_game_as("partida.json")

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
	gamestats_sync_timer = Timer.new()
	gamestats_sync_timer.set_wait_time(GAME_STATS_SYNC_INTERVAL)
	gamestats_sync_timer.connect("timeout", self, "on_gamestats_sync_timeout")
	bot_actions_timer = Timer.new()
	bot_actions_timer.set_wait_time(BOT_SECS_TO_EXEC_ACTION)
	bot_actions_timer.connect("timeout", self, "on_bot_actions_timeout")
	add_child(tween)
	add_child(net_sync_timer)
	add_child(playerdata_sync_timer)
	add_child(gamestats_sync_timer)
	add_child(bot_actions_timer)
	net_sync_timer.start()
	playerdata_sync_timer.start()
	bot_actions_timer.start()
	gamestats_sync_timer.start()
	
	if !Game.Network.is_multiplayer() or Game.Network.is_server():
		autosave_timer = Timer.new()
		autosave_timer.set_wait_time(AUTOSAVE_INTERVAL)
		autosave_timer.connect("timeout", self, "on_autosave_timeout")
		add_child(autosave_timer)
		autosave_timer.start()
	if Game.Network.is_server():
		server_tween = Tween.new()
		add_child(server_tween)
	
func init_game() -> void:
	game_start_time = OS.get_ticks_msec()
	if Game.tilesObj:
		Game.tilesObj.clear()
	Game.tilesObj = TileGameObject.new(Game.tile_map_size, Game.tileTypes.getIDByName('vacio'), Game.tileTypes, Game.troopTypes, Game.buildingTypes, Game.rng)
	
	if Game.BotSystem:
		Game.BotSystem.clear()
	Game.BotSystem = BotObject.new(self, rng)
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
		tile_size = Game.tilesObj.get_size(),
		game_player_stats = players_stats.duplicate(true),
		game_battle_stats = battle_stats.duplicate(true)
	}
	Game.FileSystem.save_as_json(Game.get_save_game_folder() + file_name, data_to_save)

func load_game_from(file_name: String):
	if Game.Network.is_client():
		return
	Game.tilesObj.update_sync_data()
	var data_to_load: Dictionary = Game.FileSystem.load_as_dict(Game.get_save_game_folder() + file_name)
	change_game_status(data_to_load.game_current_status) 
	sync_players_from_load_game(data_to_load.players_data)
	#TODO: Sync player data CORRECTLY, RIGHT NOW IT ONLY WORKS FOR 2 PLAYERS AND NOTHING MORE!
	Game.tilesObj.set_all(data_to_load.tiles_data, data_to_load.tile_size)
	players_stats = data_to_load.game_player_stats.duplicate(true)
	battle_stats = data_to_load.game_battle_stats.duplicate(true)
	init_player_stats()
	Game.current_player_turn = data_to_load.game_current_player_turn
	for player in Game.playersData:
		player.selectLeft = 0
	actions_available = data_to_load.game_actions_available
	server_send_game_info()
	Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_DELTA_TILES, {dictArray = Game.tilesObj.get_sync_data() })
	Game.tilesObj.save_sync_data()

func sync_players_from_load_game(load_player_data: Array) -> void:
	if !Game.Network.is_multiplayer():
		return
	var player_data_ordered: bool = false
	while !player_data_ordered: #set players first
		player_data_ordered = true
		for i in range(load_player_data.size()):
			var player_number: int = Game.get_player_number_by_pin_code(load_player_data[i].pin_code)
			if load_player_data[i].isBot or player_number == -1 or player_number == i or Game.playersData[player_number].pin_code == load_player_data[i].pin_code: #nothing to change here
				continue
			Game.playersData[player_number] = Game.playersData[i].duplicate(true)
			var net_id: int = Game.playersData[i].netid
			Game.playersData[i] = load_player_data[i]
			Game.playersData[i].netid = net_id #backup netid!
			player_data_ordered = false
			break
	#Set bots now
	for i in range(load_player_data.size()):
		if !load_player_data[i].isBot:
			continue
		Game.playersData[i] = load_player_data[i]
		
	Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_FORCE_PLAYER_DATA, {playerDataArray = Game.playersData.duplicate(true) }) #Unreliable, to avoid overflow of netcode
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

func on_gamestats_sync_timeout():
	
	if Game.Network.is_client() or Game.current_game_status == Game.STATUS.LOBBY_WAIT:
		return

	for i in range(Game.playersData.size()): #sending to all clients different messages
		if i == Game.get_local_player_number():
			continue
		if !Game.playersData[i].alive:
			continue
		if Game.playersData[i].isBot:
			continue
		if Game.playersData[i].netid == -1:
			continue
		var tmpLastBattleId: int = get_lastest_battle(i)
		var tmpLastBattle = null
		if tmpLastBattleId != -1:
			tmpLastBattle = battle_stats[tmpLastBattleId]
		Game.Network.server_send_event_id(Game.playersData[i].netid, self.node_id, NET_EVENTS.SERVER_SEND_GAMESTATS_DATA, {
			lastBattleID = tmpLastBattleId,
			lastBattle = tmpLastBattle,
			totalKilledInBattle = get_total_killed_in_battle(i),
			battlesTotal = get_total_battles(i),
			battlesWon = get_total_battles_won(i)
		}, true) #Unreliable, to avoid overflow of netcode
##################
#	BOT STUFF	 #
##################

func on_bot_actions_timeout():
	if Game.Network.is_client(): #only server executes bot game logic
		return
	Game.BotSystem.execute_action(Game.current_game_status, Game.current_player_turn)

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
			if Input.is_action_pressed("select_modifier") and Game.tilesObj.get_warriors_count(Game.interactTileSelected, Game.current_player_turn) > 0: #send all
				move_all_troops_from_to(Game.interactTileSelected, Game.nextInteractTileSelected, Game.current_player_turn)
			else:
				popup_tiles_actions()
		else:
			Game.interactTileSelected = Vector2(-1, -1)

func move_all_troops_from_to(from: Vector2, to: Vector2, player_number: int) -> void:
	clear_action_tile_to_do()
	var troops_array: Array = Game.tilesObj.get_troops(from)
	for troopDict in troops_array:
		if troopDict.owner != player_number:
			continue
		if !Game.troopTypes.getByID(troopDict.troop_id).is_warrior: # do not move civilians
			continue
		for toMoveTroopsDict in actionTileToDo.troopsToMove:
			if toMoveTroopsDict.troop_id == troopDict.troop_id:
				toMoveTroopsDict.amountToMove = troopDict.amount
	print(actionTileToDo.troopsToMove)
	execute_accept_tiles_actions()

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
			print("lala")
		Game.STATUS.PRE_GAME:
			$UI/HUD/GameInfo.visible = false
			$UI/HUD/PreGameInfo.visible = true
			$UI/ActionsMenu/WaitingPlayers.visible = false
		Game.STATUS.GAME_STARTED:
			init_player_stats()
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
	
	Game.tilesObj.pcg_generate_rocks(rng.randf_range(0.25, 0.50))
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			if !Game.tilesObj.is_owned_by_any_player(Vector2(x, y)) and Game.tilesObj.is_tile_walkeable(Vector2(x, y)):
				add_tribal_society_to_tile(Vector2(x, y))
	save_player_info() #Avoid weird bug
	Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_DELTA_TILES, {dictArray = Game.tilesObj.get_sync_neighbors(Game.current_player_turn) })

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
	undo_available = false
	Game.current_player_turn = player_number
	if Game.current_player_turn == Game.get_local_player_number():
		$Sounds/player_turn.play()
	if Game.Network.is_client():
		return
	
	Game.tilesObj.save_sync_data()
	save_player_info()
	update_actions_available()
	server_send_game_info()
	update_population_stats()
	#var best_battle: int = get_best_battle()
	#if best_battle != -1:
	#	print("Mejor pelea: " + str(battle_stats[best_battle]))
	if Game.current_game_status == Game.STATUS.GAME_STARTED:
		Game.playersData[player_number].turns_played+=1
		if Game.is_current_player_a_bot():
			print(Game.playersData[player_number].turns_played % BOT_TURNS_TO_RESET_STATS)
			if Game.playersData[player_number].turns_played % BOT_TURNS_TO_RESET_STATS == 0:
				Game.bot_reset_stats(player_number)
			
	
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
		actions_available = int(round(Game.tilesObj.get_number_of_productive_territories(Game.current_player_turn)/float(Game.gameplay_settings.territories_per_action) + Game.tilesObj.get_extra_actions_amount(Game.current_player_turn)))
		print(Game.tilesObj.get_extra_actions_amount(Game.current_player_turn))
		if actions_available < Game.gameplay_settings.min_actions_in_game:
			actions_available = Game.gameplay_settings.min_actions_in_game
		elif actions_available > Game.gameplay_settings.max_actions_in_game:
			actions_available = Game.gameplay_settings.max_actions_in_game

func check_if_game_finished() -> bool:
	var all_player_capitals: Array = Game.tilesObj.get_all_capitals()
	var players_alive: Array = []
	for capital in all_player_capitals:
		var player_owner: int = Game.tilesObj.get_cell_owner(capital)
		if players_alive.find(player_owner) == -1:
			players_alive.append(player_owner)
			
	for playerA in players_alive:
		for playerB in players_alive:
			if !Game.are_player_allies(playerA, playerB):
				return false
	
	return true

func process_turn_end(playerNumber: int) -> void:
	Game.tilesObj.recover_sync_data()
	
	update_gold_stats(playerNumber)
	process_tiles_turn_end(playerNumber)
	if did_player_lost(playerNumber):
		destroy_player(playerNumber)
		
	if check_if_game_finished():
		if Game.Network.is_server():
			Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_GAME_ENDED, null)
		$UI/GameFinished.visible = true
		$UI.open_finish_game_screen((OS.get_ticks_msec() - game_start_time)/60000.0)
		return
	
	if Game.Network.is_server():
		var next_player_turn: int = Game.get_next_player_turn()
		var sync_arrayA: Array = Game.tilesObj.get_sync_neighbors(next_player_turn)
		for i in range(Game.playersData.size()): #sync allies neighbors too (avoid forest desync bug)
			if i == next_player_turn:
				continue
			if !Game.playersData[i].alive:
				continue
			if !Game.are_player_allies(next_player_turn, i):
				continue
			sync_arrayA = Game.tilesObj.merge_sync_arrays(sync_arrayA.duplicate(true), Game.tilesObj.get_sync_neighbors(i))

		var sync_arrayB: Array = Game.tilesObj.get_sync_data()
		var merged_sync_arrays: Array = Game.tilesObj.merge_sync_arrays(sync_arrayA, sync_arrayB)
		
		if next_player_turn != Game.current_player_turn and !Game.are_player_allies(Game.current_player_turn, next_player_turn): #sync next turn enemy player neighbors
			merged_sync_arrays = Game.tilesObj.merge_sync_arrays(merged_sync_arrays.duplicate(true), Game.tilesObj.get_sync_neighbors(Game.current_player_turn))
		
		Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_DELTA_TILES, {dictArray = merged_sync_arrays })
	Game.tilesObj.save_sync_data()

func process_tiles_turn_end(playerNumber: int) -> void:
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			process_tile_sell(Vector2(x, y), playerNumber)
			process_tile_upgrade(Vector2(x, y), playerNumber)
			process_tile_buildings(Vector2(x, y), playerNumber)
			process_tile_recruitments(Vector2(x, y), playerNumber)
			process_tile_battles(Vector2(x, y))
			update_tile_owner(Vector2(x, y))
			process_tile_underpopulation(Vector2(x, y), playerNumber)

#func process_

func process_tile_sell(cell: Vector2, playerNumber: int) -> void:
	if !Game.tilesObj.belongs_to_player(cell, playerNumber):
		return
	var cell_data: Dictionary = Game.tilesObj.get_cell(cell)
	var tileTypeData = Game.tileTypes.getByID(cell_data.tile_id)
	
	if cell_data.turns_to_sell <= 0:
		return
	if Game.tilesObj.is_cell_in_battle(cell):
		cell_data.turns_to_sell=0 #cancel the sell of a territory if a battle starts!
		return

	cell_data.turns_to_sell-=1
	if cell_data.turns_to_sell == 0: #tile sold!
		var capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(playerNumber)
		var gold_at_cell: float = Game.tilesObj.get_cell_gold(cell)
		Game.tilesObj.add_cell_gold(capital_pos, tileTypeData.sell_prize+gold_at_cell)
		var troops_backup: Array = Game.tilesObj.get_troops(cell, true) #true = get a duplicate(true) copy
		Game.tilesObj.clear_cell(cell)
		Game.tilesObj.set_troops(cell, troops_backup)
		add_tribal_society_to_tile(cell)
		
func process_tile_underpopulation(cell: Vector2, playerNumber: int) -> void:
	if !Game.tilesObj.belongs_to_player(cell, playerNumber):
		return
	if Game.tilesObj.has_minimum_civilization(cell, playerNumber):
		return
	if Game.tilesObj.is_cell_in_battle(cell):
		return
	var extra_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = EXTRA_CIVILIANS_PER_TURN
	}
	print("Giving extra civilization per turn")
	Game.tilesObj.add_troops(cell, extra_population)
	return

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
	append_battle_stats(tile_pos)
	var battle_stats_id: int = get_battle_stats_id(tile_pos)
	assert(battle_stats_id != -1)
	battle_stats[battle_stats_id].duration += 1
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
		var enemiesWarriorStrength: Array = []
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
				
			update_killed_in_battle(troopDict.owner, troopDict.troop_id, troopsToKill)
			update_battle_stats(tile_pos, troopDict.owner, troopDict.troop_id, troopsToKill)
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
		finish_battle_stats(tile_pos)
		var playerWhoWonId: int = Game.tilesObj.get_strongest_player_in_cell(tile_pos) #give the cell to the strongest ally
		
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
				if Game.BotSystem.bot_territories_to_recover[bot_number].find(tile_pos) == -1:
					Game.BotSystem.bot_territories_to_recover[bot_number].append(tile_pos)
			elif Game.is_player_a_bot(playerWhoWonId):
				bot_number = playerWhoWonId
				Game.BotSystem.bot_territories_to_recover[bot_number] = Game.Util.array_search_and_remove(Game.BotSystem.bot_territories_to_recover[bot_number], tile_pos)
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

func process_tile_buildings(tile_pos: Vector2, playerNumber: int) -> void:
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
	var all_travel_costs: float = Game.tilesObj.get_all_travel_costs(playerNumber)
	#Step 1, update all gold in all the tiles
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			if Game.tilesObj.belongs_to_player(Vector2(x, y), playerNumber):
				
				if Vector2(x, y) == player_capital_pos:
					Game.tilesObj.take_cell_gold(Vector2(x, y), all_war_costs + all_travel_costs) # travel and war costs implemented
	
				Game.tilesObj.update_gold_stats(Vector2(x, y), playerNumber)
				var cellGold: float = Game.tilesObj.get_cell_gold(Vector2(x, y))
				totalAmountOfGold+= cellGold
				if cellGold > 0.0:
					positiveBalanceTerritories.append(Vector2(x, y))
				elif cellGold < 0.0:
					negativeBalanceTerritories.append(Vector2(x, y))

	if totalAmountOfGold < 0:
		var capitalVec2Coords: Vector2 = Game.tilesObj.get_player_capital_vec2(playerNumber)
		var gold_to_give: float = 10.0
		if Game.is_player_a_bot(playerNumber):
			gold_to_give*=Game.get_bot_gains_multiplier(playerNumber)
			if float(totalAmountOfGold) < -gold_to_give:
				gold_to_give += float(-totalAmountOfGold)
				print("[BOT] Saving stupid bot from bankrupcy")

		if (positiveBalanceTerritories.size() <= 0 or float(totalAmountOfGold) < -gold_to_give):
			destroy_player(playerNumber)
			return
		#first, remove the capital
		
		var capitalId: int = -1
		for i in range(positiveBalanceTerritories.size()):
			if positiveBalanceTerritories[i] == capitalVec2Coords:
				capitalId = i
		if capitalId != -1:
			positiveBalanceTerritories.remove(capitalId)
		if positiveBalanceTerritories.size() <= 0:
			destroy_player(playerNumber)
			return
		Game.tilesObj.add_cell_gold(capitalVec2Coords, gold_to_give)
		var rndCellToSell: int = rng.randi_range(0, positiveBalanceTerritories.size() -1)
		Game.tilesObj.clear_cell(positiveBalanceTerritories[rndCellToSell])
		add_tribal_society_to_tile(positiveBalanceTerritories[rndCellToSell])
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
	#if !Game.Network.is_multiplayer() or Game.Network.is_server() and Game.is_current_player_a_bot():
	#	return true
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
	if !Game.tilesObj.belongs_to_player(endTile, playerNumber) and Game.tilesObj.get_warriors_count(startTile, playerNumber) <= 0 and !Game.tilesObj.belongs_to_allies(endTile, playerNumber):
		return false
	if Game.tilesObj.get_civilian_count(startTile, playerNumber) <= 0 and Game.tilesObj.get_warriors_count(startTile, playerNumber) <= 0: #can't do nothing there is no one in the tile
		return false
	if !Game.tilesObj.is_tile_walkeable(startTile) or !Game.tilesObj.is_tile_walkeable(endTile):
		return false
	if Game.tilesObj.is_cell_in_battle(startTile) and !Game.tilesObj.belongs_to_player(endTile, playerNumber): #Don't allow troops to attack other enemy territories while in battle!
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
	var deploy_prize: float = float(currentBuildingType.deploy_prize)
	if Game.is_player_a_bot(playerNumber):
		deploy_prize *= Game.get_bot_discount_multiplier(playerNumber)
	if deploy_prize > Game.tilesObj.get_total_gold(playerNumber):
		return false
	if tile_cell_data.upcomingTroops.size() >= 1: 
		return false
	return true

func check_if_player_can_buy_buildings(tile_pos: Vector2, playerNumber: int) -> bool:
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(playerNumber)
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

func give_troops_to_player_and_sync(cell: Vector2, player_number: int, troop_array: Array, multiplier: float = 1.0) -> void:
	Game.tilesObj.update_sync_data()
	for troop in troop_array:
		Game.tilesObj.add_troops(cell, {
			owner = player_number,
			troop_id = Game.troopTypes.getIDByName(troop.troop_name),
			amount = int(round(float(troop.amount)*multiplier))
		})
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })


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

func add_tribal_society_to_tile(cell: Vector2) -> void:
	var cell_data: Dictionary = Game.tilesObj.get_cell(cell)
	var tribesAmount: int = Game.tribalTroops.getCount()
	var tribeId: int = Game.rng.randi_range(0, tribesAmount-1)
	var tribeDict: Dictionary = Game.tribalTroops.getByID(tribeId)
	cell_data.tribe_owner = tribeId
	Game.tilesObj.set_cell_gold(cell, round(Game.rng.randf_range(float(tribeDict.min_gold), float(tribeDict.max_gold))))
	for troop in tribeDict.troops:
		Game.tilesObj.add_troops(cell, {
			owner = -1,
			troop_id = Game.troopTypes.getIDByName(troop.troop_name),
			amount = Game.rng.randi_range(troop.min_amount, troop.max_amount)
		})

func destroy_player(playerNumber: int):
	for x in range(Game.tile_map_size.x):
		for y in range(Game.tile_map_size.y):
			if Game.tilesObj.belongs_to_player(Vector2(x, y), playerNumber):
				Game.tilesObj.remove_troops_from_player(Vector2(x, y), playerNumber)
				var troops_backup: Array = Game.tilesObj.get_troops(Vector2(x,y), true) #true = get a duplicate(true) copy
				Game.tilesObj.clear_cell(Vector2(x, y))
				Game.tilesObj.set_troops(Vector2(x, y), troops_backup)
				add_tribal_society_to_tile(Vector2(x, y))
	Game.playersData[playerNumber].alive = false
	print("PLAYER " + str(playerNumber) + " LOST!")

func change_tile_name(tile_pos: Vector2, new_name: String) -> void:
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer():
		player_mask = Game.get_local_player_number()
	if !Game.tilesObj.belongs_to_player(tile_pos, player_mask):
		return
	if Game.tilesObj.get_name(tile_pos) == new_name:
		return #no need to sync!
	#if Game.Network.is_client(): # No need of server to send this, it will be send at the next turn
	#	Game.tilesObj.update_sync_data()

	Game.tilesObj.set_name(tile_pos, new_name)
	Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_NAME, {cell_pos = tile_pos, cell_name = new_name })

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

func is_action_tile_to_do_empty():
	if actionTileToDo.goldToSend > 0.0:
		return false
	for toMoveTroopDict in actionTileToDo.troopsToMove:
		if toMoveTroopDict.amountToMove > 0.0:
			return false
	return true

func update_tiles_actions_data():
	var cell_gold: float = floor(Game.tilesObj.get_cell_gold(Game.interactTileSelected))
	if cell_gold < 0.0:
		cell_gold = 0.0
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosDisponibles.text = str(cell_gold)
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
	
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.visible = troops_to_show_array.size() > 0
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.visible = troops_to_show_array.size() > 0
	$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasDisponibles.visible = troops_to_show_array.size() > 0
	for troopData in troops_to_show_array:
		$UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.add_item(troopData.name, troopData.id)
	
	if troops_to_show_array.size() > 0:
		update_troops_move_data($UI/ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.selected)

func game_tile_show_info():
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer():
		player_mask = Game.get_local_player_number()
		
	if !Game.tilesObj.belongs_to_player(Game.current_tile_selected, player_mask):
		return
	
	var allowed_to_modify_things: bool = is_local_player_turn() or !Game.Network.is_multiplayer()

	$UI/ActionsMenu/InGameTileActions/VBoxContainer/VenderTile.visible = allowed_to_modify_things and Game.tilesObj.can_cell_be_sold(Game.current_tile_selected)
	#if tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id ==  Game.tileTypes.getIDByName("capital"):
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/UrbanizarTile.visible = allowed_to_modify_things and Game.tilesObj.can_be_upgraded(Game.current_tile_selected, Game.current_player_turn)
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/Construir.visible = allowed_to_modify_things and check_if_player_can_buy_buildings(Game.current_tile_selected, Game.current_player_turn)
	$UI/ActionsMenu/InGameTileActions/VBoxContainer/Reclutar.visible = allowed_to_modify_things and is_recruiting_possible(Game.current_tile_selected, Game.current_player_turn)
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
	Game.add_player(-1, "bot", Game.BOT_NET_ID, -1, true)

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
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	
func execute_buy_building(var selectedBuildTypeId: int):
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(Game.current_player_turn)
	if !is_local_player_turn() or !can_execute_action() or !Game.tilesObj.can_buy_building_at_cell(Game.current_tile_selected, selectedBuildTypeId, getTotalGoldAvailable, Game.current_player_turn): 
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.buy_building(Game.current_tile_selected, selectedBuildTypeId)
	action_in_turn_executed()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func execute_open_build_window():
	update_build_menu()

func gui_vender_tile():
	if !is_local_player_turn() or !can_execute_action():
		return
	if !Game.tilesObj.can_cell_be_sold(Game.current_tile_selected):
		return
	var cell_data: Dictionary = Game.tilesObj.get_cell(Game.current_tile_selected)
	var tileTypeData = Game.tileTypes.getByID(cell_data.tile_id)
	save_player_info()
	Game.tilesObj.update_sync_data()
	cell_data.turns_to_sell = 2 #2 turns to sold
	action_in_turn_executed()
	
	$UI/ActionsMenu/InGameTileActions.visible = false
	
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
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
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
	if !is_local_player_turn() or !can_execute_action() or is_action_tile_to_do_empty():
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	execute_tile_action()
	action_in_turn_executed()
	Game.nextInteractTileSelected = Vector2(-1, -1) #reset
	Game.interactTileSelected = Vector2(-1, -1) #reset
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func action_in_turn_executed():
	if Game.current_game_status != Game.STATUS.GAME_STARTED:
		return
	actions_available-=1
	if is_local_player_turn():
		undo_available = true
	if is_local_player_turn() or Game.is_current_player_a_bot():
		if Game.Network.is_client() and is_local_player_turn() :
			Game.Network.net_send_event(self.node_id, NET_EVENTS.CLIENT_USE_ACTION,  {player_turn = Game.current_player_turn, dictArray = Game.tilesObj.get_sync_data()})
		else:
			Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	
	if actions_available <= 0:
		save_player_info() #Avoid weird stuff in multiplayer
	
	if Game.Network.is_client():
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
	Game.tilesObj.add_cell_gold(Game.current_tile_selected, Game.gameplay_settings.gold_per_point)
	use_selection_point()

func execute_add_extra_troops():
	if !is_local_player_turn() or !have_selection_points_left():
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	var troops_to_add: Array = Game.gameplay_settings.troops_to_give_per_point
	for troop in troops_to_add:
		Game.tilesObj.add_troops(Game.current_tile_selected, {
			owner = Game.current_player_turn,
			troop_id = Game.troopTypes.getIDByName(troop.troop_name),
			amount = int(troop.amount)
		})
	use_selection_point()

func use_selection_point():
	if Game.Network.is_client() and !is_local_player_turn():
		return
	if is_local_player_turn():
		undo_available = true
	Game.playersData[Game.current_player_turn].selectLeft-=1
	
	if Game.Network.is_client():
		if Game.playersData[Game.current_player_turn].selectLeft >= 0:
			Game.Network.net_send_event(self.node_id, NET_EVENTS.CLIENT_USE_POINT,  {player_turn = Game.current_player_turn, dictArray = Game.tilesObj.get_sync_data()})
		return
	elif is_local_player_turn() or Game.is_current_player_a_bot():
		Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

	server_send_game_info()
	if Game.playersData[Game.current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()

func save_player_info():
	if !is_local_player_turn() and (!Game.is_current_player_a_bot() or Game.Network.is_client()):
		return

	saved_player_info.points_to_select_left = Game.playersData[Game.current_player_turn].selectLeft
	saved_player_info.actions_left = actions_available
	Game.tilesObj.save_tiles_data()
	
func undo_actions():
	if !undo_available:
		return
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
		
	undo_available = false

###############
# STATS STUFF #
###############

func init_player_stats() -> void:
	if Game.Network.is_client():
		return #only server calculate this, and send info to clients at the end of the game...
	if players_stats.size() > 0:
		return #already initialized
	for player in Game.playersData:
		if !player.alive:
			players_stats.append(null)
			continue
		players_stats.append({
			killed_in_battle = [], #array with data of type of troops killed
			peak_population = [], #array with the peak of population you had 
			current_population = []
			#battles = []
		})

func update_population_stats() -> void:
	if Game.Network.is_client():
		return #only server calculate this, and send info to clients at the end of the game...
	for i in range(Game.playersData.size()):
		if !Game.playersData[i].alive:
			continue
		if players_stats.size() <= i:
			continue
		if typeof(players_stats[i]) == TYPE_NIL:
			continue
		var total_population: Array = Game.tilesObj.get_civ_population_info(i)
		players_stats[i].current_population = total_population
		for troopDict in total_population:
			var should_append: bool = true
			for peakDict in players_stats[i].peak_population:
				if peakDict.troop_id == troopDict.troop_id:
					should_append = false
					if peakDict.amount < troopDict.amount:
						peakDict = troopDict.duplicate(true)
			if should_append:
				players_stats[i].peak_population.append(troopDict.duplicate(true))

func update_killed_in_battle(player_number: int, t_id: int, amount_killed: int) -> void:
	if player_number < 0:
		return #not a player, probably tribal society
	for killedDict in players_stats[player_number].killed_in_battle:
		if killedDict.troop_id == t_id:
			killedDict.amount += amount_killed
			return
	players_stats[player_number].killed_in_battle.append({troop_id = t_id, amount = amount_killed})

func get_total_killed_in_battle(player_number: int) -> Array:
	if players_stats.size() <= player_number or typeof(players_stats[player_number].killed_in_battle) == TYPE_NIL:
		return []
	return players_stats[player_number].killed_in_battle

func get_total_battles_lost(player_number: int) -> int:
	return get_total_battles(player_number) - get_total_battles_won(player_number)
	
func get_total_battles_won(player_number: int) -> int:
	var battles_won: int = 0
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if !is_player_a_winner_in_battle_stats(i, player_number):
			continue
		battles_won+=1
	return battles_won

func get_total_battles(player_number: int) -> int:
	var battle_count: int = 0
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if !is_player_in_battle_stats(i, player_number):
			continue
		battle_count+=1
	return battle_count

func finish_battle_stats(tile_pos: Vector2) -> void:
	var battle_id: int = get_battle_stats_id(tile_pos)
	assert(battle_id != -1)
	battle_stats[battle_id].remaining = Game.tilesObj.get_troops_clean(tile_pos).duplicate(true)
	battle_stats[battle_id].in_progress = false #battle finished

func check_if_battle_stats_already_exists(tile_pos: Vector2) -> bool:
	for battle in battle_stats:
		if typeof(battle) == TYPE_NIL:
			continue
		if !battle.in_progress:
			continue
		if battle.pos == tile_pos:
			return true
	return false

func get_battle_stats_id(tile_pos: Vector2) -> int:
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if !battle_stats[i].in_progress:
			continue
		if battle_stats[i].pos == tile_pos:
			return i
	return -1

func update_battle_stats(tile_pos: Vector2, victim: int, t_id: int, amount_killed: int) -> void:
	var battle_id: int = get_battle_stats_id(tile_pos)
	assert(battle_id != -1)
	for killedDict in battle_stats[battle_id].killed:
		if killedDict.troop_id != t_id:
			continue
		if killedDict.owner != victim:
			continue
		killedDict.amount += amount_killed
		return
	battle_stats[battle_id].killed.append({
		troop_id = t_id,
		owner = victim,
		amount = amount_killed
	})

func append_battle_stats(tile_pos: Vector2) -> void:
	if !Game.tilesObj.is_cell_in_battle(tile_pos) or check_if_battle_stats_already_exists(tile_pos):
		return
	battle_stats.append({
		pos = tile_pos,
		in_progress = true,
		duration = 0, #turns the battle lasted
		killed = [],
		remaining = [] #troops that survived the battle
	})

func get_players_in_battle_stats(battle_id: int) -> Array:
	var all_dict: Array = Game.Util.array_addition(battle_stats[battle_id].killed, battle_stats[battle_id].remaining, true) #allow duplicates
	var players_in_battle: Array = []
	
	for troopDict in all_dict:
		if troopDict.amount <= 0:
			continue
		if players_in_battle.find(troopDict.owner) == -1:
			players_in_battle.append(troopDict.owner)
	return players_in_battle

func get_battle_stats_strength(battle_id: int) -> float:
	var all_dict: Array = Game.Util.array_addition(battle_stats[battle_id].killed, battle_stats[battle_id].remaining, true) #allow duplicates
	var total_force: float = 0.0
	for troopDict in all_dict:
		if troopDict.amount <= 0:
			continue
		var troopsHealth: float = Game.troopTypes.getByID(troopDict.troop_id).health*troopDict.amount
		var troopsDamage: float = troopDict.amount*(Game.troopTypes.getByID(troopDict.troop_id).damage.x + Game.troopTypes.getByID(troopDict.troop_id).damage.y)/2.0
		total_force+=troopsHealth+troopsDamage
	return total_force

func get_teams_data_from_battle_stats(battle_id: int) -> Array:
	var all_dict: Array = Game.Util.array_addition(battle_stats[battle_id].killed, battle_stats[battle_id].remaining, true) #allow duplicates
	var teams_data: Array = []
	
	for troopDict in all_dict:
		if troopDict.amount <= 0:
			continue
		var troopsHealth: float = Game.troopTypes.getByID(troopDict.troop_id).health*troopDict.amount
		var troopsDamage: float = troopDict.amount*(Game.troopTypes.getByID(troopDict.troop_id).damage.x + Game.troopTypes.getByID(troopDict.troop_id).damage.y)/2.0
		var should_append_player: bool = true
		var team_id: int = -1
		for i in range(teams_data.size()):
			for player_num in teams_data[i].players:
				if Game.are_player_allies(player_num, troopDict.owner):
					team_id = i
				if player_num == troopDict.owner:
					should_append_player = false
					break

		if team_id == -1: #make new team and append player
			teams_data.append({
				players = [troopDict.owner],
				strength = troopsHealth + troopsDamage
			})
			continue
		if should_append_player:
			teams_data[team_id].players.append(troopDict.owner)
		teams_data[team_id].strength += troopsHealth + troopsDamage
		
	return teams_data

#the lower the value, the best comeback
func battle_comeback_points(battle_id: int, player_number: int = -1) -> float:
	var teams_data: Array = get_teams_data_from_battle_stats(battle_id)
	var winner_team: int = -1
	for remainingDict in battle_stats[battle_id].remaining:
		if remainingDict.amount <= 0:
			continue
		for i in range(teams_data.size()):
			if teams_data[i].players.find(remainingDict.owner) != -1:
				winner_team = i
				break
		if winner_team != -1:
			break
	assert(winner_team != -1)
	var max_enemy_strength: float = -1.0
	for i in range(teams_data.size()):
		if i == winner_team:
			continue
		if max_enemy_strength == -1.0:
			max_enemy_strength = teams_data[i].strength
		
		if teams_data[i].strength > max_enemy_strength:
			max_enemy_strength = teams_data[i].strength
	if teams_data[winner_team].strength <= 0:
		return 0.0
	return teams_data[winner_team].strength/max_enemy_strength #the lower the value,the better the comeback

#1.0 being perfectly balanced - 0.0 being totally unbalanced
func calculate_battle_balance_points(battle_id: int) -> float:
	var teams_data: Array = get_teams_data_from_battle_stats(battle_id)
	var max_strength: float = -1.0
	var min_strength: float = -1.0
	for team in teams_data:
		if max_strength == -1.0:
			max_strength = team.strength
		if min_strength == -1.0:
			min_strength = team.strength
		
		if team.strength > max_strength:
			max_strength = team.strength
		if team.strength < min_strength:
			min_strength = team.strength
	if min_strength <= 0.0:
		return 0.0 #total unbalanced
	return min_strength/max_strength

func is_player_a_winner_in_battle_stats(battle_id: int, player_number: int) -> bool:
	if !is_player_in_battle_stats(battle_id, player_number):
		return false
	for troopDict in battle_stats[battle_id].remaining:
		if Game.are_player_allies(troopDict.owner, player_number):
			return true
	return false

func is_player_in_battle_stats(battle_id: int, player_number: int) -> bool:
	var all_dict: Array = Game.Util.array_addition(battle_stats[battle_id].killed, battle_stats[battle_id].remaining, true) #allow duplicates
	for troopDict in all_dict:
		if troopDict.owner == player_number:
			return true
	return false

func get_battle_points(battle_id:int, max_balance_points:float, max_duration:float, max_players:float, max_force:float, max_comeback:float, player_number: int=-1, imprimir: bool = false) -> float:
	var balance_ratio: float = (calculate_battle_balance_points(battle_id)/max_balance_points)*0.85
	var duration_ratio: float = (float(battle_stats[battle_id].duration)/max_duration)
	var players_ratio: float = float(get_players_in_battle_stats(battle_id).size())/max_players
	var force_ratio: float = (get_battle_stats_strength(battle_id)/max_force)
	var comeback_ratio: float = max_comeback/battle_comeback_points(battle_id, player_number)*0.85

	return (balance_ratio+duration_ratio+players_ratio+force_ratio+comeback_ratio)/5.0

func get_lastest_battle(player_number: int) -> int:
	var lastest_battle: int = -1
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if player_number != -1 and !is_player_in_battle_stats(i, player_number):
			continue
		lastest_battle = i
	return lastest_battle

func get_best_battle(player_number: int = -1) -> int:
	var best_battle: int = -1
	var most_balanced_battle = get_most_balanced_battle(player_number)
	var longest_battle = get_longest_battle(player_number)
	var battle_with_most_players = get_battle_with_most_players(player_number)
	var battle_with_biggest_force = get_battle_with_biggest_force(player_number)
	var battle_with_best_comeback = get_battle_with_best_comeback(player_number)
	
	if most_balanced_battle == -1 or longest_battle == -1 or battle_with_most_players == -1 or battle_with_biggest_force == -1 or battle_with_best_comeback == -1:
		return -1
	
	var max_balance_points: float = calculate_battle_balance_points(most_balanced_battle)
	var max_duration: float =  float(battle_stats[longest_battle].duration)
	var max_players: float = float(get_players_in_battle_stats(battle_with_most_players).size())
	var max_force: float = get_battle_stats_strength(battle_with_biggest_force)
	var max_comeback: float = battle_comeback_points(battle_with_best_comeback, player_number)
	if max_comeback <= 0.0:
		max_comeback == 0.01 #avoid bug
	
	var current_best_ratio: float = 0.0
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if player_number != -1 and !is_player_in_battle_stats(i, player_number):
			continue
		var total_ratio: float = get_battle_points(i, max_balance_points, max_duration, max_players, max_force, max_comeback, player_number)
		if best_battle == -1:
			current_best_ratio = total_ratio
			best_battle = i
			continue
		if total_ratio > current_best_ratio:
			best_battle = i
			current_best_ratio = total_ratio

	return best_battle
#Get battle where all the forces (including remaning) are the most equal
func get_most_balanced_battle(player_number: int = -1) -> int:
	var most_balanced_battle: int = -1
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if player_number != -1 and !is_player_in_battle_stats(i, player_number):
			continue
		if most_balanced_battle == -1:
			most_balanced_battle = i
			continue
		if calculate_battle_balance_points(i) > calculate_battle_balance_points(most_balanced_battle):
			most_balanced_battle = i
	return most_balanced_battle 

func get_longest_battle(player_number: int = -1) -> int:
	var longest_battle_id: int = -1
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if player_number != -1 and !is_player_in_battle_stats(i, player_number):
			continue
		if longest_battle_id == -1:
			longest_battle_id = i
			continue
		if battle_stats[i].duration > battle_stats[longest_battle_id].duration:
			longest_battle_id = i
	return longest_battle_id

func get_battle_with_most_players(player_number: int = -1) -> int:
	var battle_with_most_players: int = -1
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if player_number != -1 and !is_player_in_battle_stats(i, player_number):
			continue
		if battle_with_most_players == -1:
			battle_with_most_players = i
			continue
		if get_players_in_battle_stats(i).size() > get_players_in_battle_stats(battle_with_most_players).size():
			battle_with_most_players = i
	return battle_with_most_players
	
func get_battle_with_biggest_force(player_number: int = -1) -> int:
	var battle_with_biggest_force: int = -1
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if player_number != -1 and !is_player_in_battle_stats(i, player_number):
			continue
		if battle_with_biggest_force == -1:
			battle_with_biggest_force = i
			continue
		if get_battle_stats_strength(i) > get_battle_stats_strength(battle_with_biggest_force):
			battle_with_biggest_force = i
	return battle_with_biggest_force

func get_battle_with_best_comeback(player_number: int = -1) -> int:
	var battle_with_best_comeback: int = -1
	for i in range(battle_stats.size()):
		if typeof(battle_stats[i]) == TYPE_NIL:
			continue
		if battle_stats[i].in_progress: #only calculate this from already finished battles!
			continue
		if player_number != -1 and !is_player_in_battle_stats(i, player_number):
			continue
		if battle_with_best_comeback == -1:
			battle_with_best_comeback = i
			continue
		if battle_comeback_points(i) < battle_comeback_points(battle_with_best_comeback):
			battle_with_best_comeback = i
	return battle_with_best_comeback

###########
# NETCODE #
###########

func net_client_stats_init():
	if players_stats.size() > 0:
		return #already initialized
	for player in Game.playersData:
		if !player.alive:
			players_stats.append(null)
			continue
		players_stats.append({
			killed_in_battle = [], #array with data of type of troops killed
			peak_population = [], #array with the peak of population you had 
			current_population = []
		})

func _server_disconnected():
	exit_game("Disconnected from server....")

func _player_reconnects(id, player_number):
	if Game.Network.is_client():
		return
	var sync_arrayA: Array = Game.tilesObj.get_sync_data(player_number, true)
	var sync_arrayB: Array = Game.tilesObj.get_sync_neighbors(player_number)
	var merged_sync_arrays: Array = Game.tilesObj.merge_sync_arrays(sync_arrayA, sync_arrayB)
	for i in range(Game.playersData.size()): #sync allies
		if i == player_number:
			continue
		if !Game.playersData[i].alive:
			continue
		if !Game.are_player_allies(player_number, i):
			continue
		var sync_array_tmp: Array = Game.tilesObj.get_sync_data(i, true)
		merged_sync_arrays = Game.tilesObj.merge_sync_arrays(merged_sync_arrays.duplicate(true), sync_array_tmp)

	var message_to_show = Game.playersData[player_number].name + " reconnected..."
	$UI.show_error_message(message_to_show)
	Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_INFO_MESSAGE, {msg = message_to_show })
	Game.Network.server_send_event_id(id, self.node_id, NET_EVENTS.SERVER_SEND_DELTA_TILES, {dictArray = merged_sync_arrays })
	Game.Network.server_send_event_id(id, self.node_id, NET_EVENTS.SERVER_UPDATE_GAME_INFO, {
		game_status = Game.current_game_status,
		player_turn = Game.current_player_turn,
		select_left = Game.playersData[Game.current_player_turn].selectLeft,
		actions_left = actions_available
	})
	
func _on_player_connected(id):
	$UI.show_error_message("Player connected....")

func _on_player_disconnect(id):
	if Game.Network.is_server():
		var player_id: int = Game.get_player_by_netid(id)
		var message_to_show: String = ""
		if player_id == -1:
			message_to_show = "A player disconnected..."
		else:
			message_to_show = Game.playersData[player_id].name + " disconnected..."
		$UI.show_error_message(message_to_show)
		Game.Network.net_send_event(self.node_id, NET_EVENTS.SERVER_SEND_INFO_MESSAGE, {msg = message_to_show })
	if id == Game.get_tree().get_network_unique_id(): #we disconnected!
		exit_game("Disconnected from server....")

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
	
func get_tiles_node_transformation() -> Dictionary:
	return {scale = $Tiles.scale, position = $Tiles.position}

func exit_game(error_msg: String = ""):
	Game.Network.client_kicked({reason = error_msg})

func client_update_player_data(playerData, force: bool) -> void:
	#SERVER_SEND_GAME_ENDED
	var net_local_player_number: int = Game.get_local_player_number()
	for i in range(Game.playersData.size()):
		if playerData.size() <= i:
			return
		if i == net_local_player_number and !force:
			Game.playersData[i].team = playerData[i].team
		else:
			Game.playersData[i].clear()
			Game.playersData[i] = playerData[i].duplicate(true)

func server_process_event(eventId : int, eventData) -> void:
	match eventId:
		NET_EVENTS.UPDATE_TILE_DATA:
			Game.tilesObj.set_sync_data(eventData.dictArray)
		NET_EVENTS.CLIENT_USE_POINT:
			if eventData.player_turn == Game.current_player_turn and !Game.is_current_player_a_bot():
				Game.tilesObj.set_sync_data(eventData.dictArray)
				use_selection_point()
		NET_EVENTS.CLIENT_USE_ACTION:
			if eventData.player_turn == Game.current_player_turn and !Game.is_current_player_a_bot():
				Game.tilesObj.set_sync_data(eventData.dictArray)
				action_in_turn_executed()
		NET_EVENTS.CLIENT_TURN_END:
			if eventData.player_turn == Game.current_player_turn and !Game.is_current_player_a_bot():
				move_to_next_player_turn()
		NET_EVENTS.CLIENT_SEND_GAME_INFO:
			if	Game.current_player_turn == eventData.player_turn and !Game.is_current_player_a_bot():
				Game.playersData[Game.current_player_turn].selectLeft = eventData.select_left
				actions_available = eventData.actions_left
		NET_EVENTS.UPDATE_TILE_NAME:
			Game.tilesObj.set_name(eventData.cell_pos, eventData.cell_name)
		_:
			print("Warning: Received unkwown event");
			
func client_process_event(eventId : int, eventData) -> void:
	match eventId:
		NET_EVENTS.SERVER_SEND_PLAYERS_DATA:
			client_update_player_data(eventData.playerDataArray, false)
		NET_EVENTS.SERVER_FORCE_PLAYER_DATA:
			client_update_player_data(eventData.playerDataArray, true)
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
			if is_local_player_turn() and old_player_turn != Game.current_player_turn:
				undo_available = false #new turn started
				save_player_info()
				$Sounds/player_turn.play()
			Game.playersData[Game.current_player_turn].selectLeft = eventData.select_left
			actions_available = eventData.actions_left
		NET_EVENTS.SERVER_SEND_INFO_MESSAGE:
			$UI.show_error_message(eventData.msg)
		NET_EVENTS.SERVER_SEND_GAME_ENDED:
			$UI/GameFinished.visible = true
			$UI.open_finish_game_screen((OS.get_ticks_msec() - game_start_time)/60000.0)
		NET_EVENTS.UPDATE_TILE_NAME:
			Game.tilesObj.set_name(eventData.cell_pos, eventData.cell_name)
		NET_EVENTS.SERVER_SEND_GAMESTATS_DATA:
			net_client_stats_init()
			var local_player_num: int = Game.get_local_player_number()
			players_stats[local_player_num].killed_in_battle = eventData.totalKilledInBattle.duplicate(true)
			var last_battle_id: int = eventData.lastBattleID
			if last_battle_id >= 0:
				battle_stats.resize(last_battle_id+1)
				battle_stats[last_battle_id] = eventData.lastBattle.duplicate(true)
			client_stats.battles_won = eventData.battlesWon
			client_stats.battles_total = eventData.battlesTotal
			client_stats.battles_lost = eventData.battlesTotal - eventData.battlesWon
		_:
			print("Warning: Received unkwown event")
