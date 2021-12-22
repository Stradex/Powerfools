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
# OBSERVACIÓN: Bug que hace que de la nada a veces clientes pierdan plata
# Que los jugadores reciban la info de manera instantanea
# Pantalla de VICTORIA: LA GUERRA ES PARA PUTOS, COMOS LOS PUTOS QUE JUEGAN ESTE JUEGO. 
# 	-> LA GUERRA NO ES UN JUEGO FOTO DE GHANDI
# Diferentes graficos para las bases
# Que los clientes puedan seleccionar su equipo.
# Que los aliados pueda ver los edificios que puedan 
# Que los clientes reciban informacion en tiempo real
# Auto save 1: cada 1 minuto, 2: cada 10 minutos, 3: cada 30 minutos
# Opción gráfica de pantalla completa y resoluciones
# Opciones de jugadores en el menu principal y no cuando joineas
# PASO 1: LIMPIAR CODIGO
# Modo blitz: que los jugadores juegen su turno todos al mismo tiempo ( Ultra a futuro )
# Cuanto terreno tenes info
# Agregar: que los civiles se regeneren 
# Dificultad experto.
# Que las tropas no se generen una vez conquistado un territorio.
# Que los civiles se vayan reproduciendo por turno (para llegar al minimo necesario para ser productivo), 200 por turno si faltan.
# Que los bots puedan tener formaciones
# Que los bots cuando juegan en equipo se ayuden unos a otros.
# No poder robarle atlentos a tus aliados del orto jaja

const MIN_ACTIONS_PER_TURN: int = 3
const MININUM_TROOPS_TO_FIGHT: int = 5
const EXTRA_CIVILIANS_TO_GAIN_CONQUER: int = 500
const WORLD_GAME_NODE_ID: int = 666 #NODE ID unique
const AUTOSAVE_INTERVAL: float = 60.0 #Every 1 minute
const PLAYER_DATA_SYNC_INTERVAL: float = 2.0
const BOT_SECS_TO_EXEC_ACTION: float = 1.0 #seconds for a bot to execute each action (not turn but every single action)
const BOT_MAX_TURNS_FOR_PLAN: int = 3 #bot can be using same plan as maximum as 3 turns, to avoid bots getting stuck with old plans
const BOT_TURNS_TO_RESET_STATS: int = 15

var time_offset: float = 0.0
var player_in_menu: bool = false
var player_can_interact: bool = true
var actions_available: int = MIN_ACTIONS_PER_TURN
var rng: RandomNumberGenerator = RandomNumberGenerator.new();
var node_id: int = -1
var undo_available: bool = true
var turn_number: int = 0
var game_start_time: float = 0.0

onready var tween: Tween
onready var server_tween: Tween
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
	SERVER_SEND_GAME_ENDED,
	MAX_EVENTS
}
###################################################
# GODOT _READY, _PROCESS & FUNDAMENTAL FUNCTIONS
###################################################

func _ready():
	init_timers_and_tweens()
	init_game()
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

	if Input.is_action_just_pressed("zoom_in_hud"):
		$Tiles.position = Vector2(0.0, 0.0)
		$Tiles.scale = Vector2(1.0, 1.0)
		$UI.init_tile_coordinates()
	elif Input.is_action_just_pressed("zoom_out_hud"):
		$Tiles.position = Vector2(60.0, 0.0)
		$Tiles.scale = Vector2(0.9, 0.9)
		$UI.init_tile_coordinates()

	if player_in_menu or !player_can_interact:
		return
	
	if Input.is_action_just_pressed("toggle_coords"):
		$UI.show_game_coords()	
	elif Input.is_action_just_released("toggle_coords"):
		$UI.hide_game_coords()	

	
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
			print("lala")
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
	Game.current_player_turn = player_number
	if Game.current_player_turn == Game.get_local_player_number():
		$Sounds/player_turn.play()
	if Game.Network.is_client():
		return
	Game.tilesObj.save_sync_data()
	save_player_info()
	update_actions_available()
	server_send_game_info()
	
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
		actions_available = int(round(Game.tilesObj.get_number_of_productive_territories(Game.current_player_turn)/5.0 + 0.5))
		if actions_available < MIN_ACTIONS_PER_TURN:
			actions_available = MIN_ACTIONS_PER_TURN

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

func give_troops_to_player_and_sync(cell: Vector2, player_number: int, troop_name: String, amount_to_give: int) -> void:
	Game.tilesObj.update_sync_data()
	var extraTroops: Dictionary = {
		owner = player_number,
		troop_id = Game.troopTypes.getIDByName(troop_name),
		amount = amount_to_give
	}
	Game.tilesObj.add_troops(cell, extraTroops)
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
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

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
		$UI/ActionsMenu/InGameTileActions.visible = false
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
	Game.add_player(-1, "bot [D]", 758, -1, true)

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
	if !is_local_player_turn() or !can_execute_action():
		return
	save_player_info()
	Game.tilesObj.update_sync_data()
	execute_tile_action()
	action_in_turn_executed()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func action_in_turn_executed():
	if Game.current_game_status != Game.STATUS.GAME_STARTED:
		return
	actions_available-=1

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
	Game.tilesObj.add_cell_gold(Game.current_tile_selected, 10)
	use_selection_point()
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func execute_add_extra_troops():
	if !is_local_player_turn() or !have_selection_points_left():
		return
	save_player_info()
	#give_troops_to_player_and_sync(Game.current_tile_selected, Game.current_player_turn, "recluta", 1000)
	Game.tilesObj.update_sync_data()
	var extraTroops: Dictionary = {
		owner = Game.current_player_turn,
		troop_id = Game.troopTypes.getIDByName("recluta"),
		amount = 1000
	}
	Game.tilesObj.add_troops(Game.current_tile_selected, extraTroops)
	#Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	use_selection_point()

func use_selection_point():
	if Game.Network.is_client() and !is_local_player_turn():
		return
	Game.playersData[Game.current_player_turn].selectLeft-=1
	
	if Game.Network.is_client() and Game.playersData[Game.current_player_turn].selectLeft >= 0:
		Game.Network.net_send_event(self.node_id, NET_EVENTS.CLIENT_USE_POINT,  {player_turn = Game.current_player_turn, dictArray = Game.tilesObj.get_sync_data()})
		return
	elif is_local_player_turn() or Game.is_current_player_a_bot():
		Game.Network.net_send_event(self.node_id, NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
			
	if Game.Network.is_client() and Game.playersData[Game.current_player_turn].selectLeft >= 0:
		Game.Network.net_send_event(self.node_id, NET_EVENTS.CLIENT_USE_POINT, {player_turn = Game.current_player_turn})
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
	
func get_tiles_node_transformation() -> Dictionary:
	return {scale = $Tiles.scale, position = $Tiles.position}

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
			if is_local_player_turn() and old_player_turn != Game.current_player_turn:
				save_player_info()
			
			if Game.get_local_player_number() == Game.current_player_turn and old_player_turn != Game.current_player_turn:
				$Sounds/player_turn.play()
			Game.playersData[Game.current_player_turn].selectLeft = eventData.select_left
			actions_available = eventData.actions_left
		NET_EVENTS.SERVER_SEND_GAME_ENDED:
			$UI/GameFinished.visible = true
		_:
			print("Warning: Received unkwown event")
