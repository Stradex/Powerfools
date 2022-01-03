extends Node

const VERSION: String = "0.1.1" #Major, Minor, build count
const PORT: int = 27666
const MAX_PLAYERS: int = 8
const SNAPSHOT_DELAY: float = 1.0/30.0 #msec to sec
const GAME_DEFAULT_MOD: String = "base"
const CONFIG_FILE: String = "game_config.cfg";
const MAPS_FOLDER: String = "res://scenes/"
const START_MAP: String = "WorldGame.tscn"
const MENU_NODE: String = "res://scenes/MainMenu.tscn"
const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 720
const TILE_SIZE: int = 80
const GAME_FPS: int = 4 # we really don't need to much higher FPS, this is mostly for game logic, not graphic stuff
const DEBUG_MODE: bool = false
const BOT_NET_ID: int = -1
const BOT_STATS_FILE: String = "bots_difficulties.json"
const GAMEPLAY_SETTINGS_FILE: String = "game_settings.json"
const FUNCTILES_FILE: String = "func_settings.json"
var current_mod: String = "base"

var current_turn: int = 0
onready var troopTypes: TroopTypesObject = TroopTypesObject.new()
onready var buildingTypes: BuildingTypesObject = BuildingTypesObject.new()
onready var tileTypes: TilesTypesObject = TilesTypesObject.new()
onready var Network: NetworkBase = NetworkBase.new()
onready var FileSystem: FileSystemBase = FileSystemBase.new();
onready var Util: UtilObject = UtilObject.new()
onready var Config: ConfigObject = ConfigObject.new()
onready var tribalTroops: TribalSocietyObject = TribalSocietyObject.new()
onready var civilizationTypes: CivilizationTypesObject = CivilizationTypesObject.new()
var TileSetImporter: TileSetExternalImporter
var Boop_Object = preload("res://scripts/Netcode/Boop.gd");

var tilesObj: TileGameObject
var BotSystem: BotObject
var playersData: Array
var tile_map_size: Vector2 = Vector2(round(SCREEN_WIDTH/TILE_SIZE), round(SCREEN_HEIGHT/TILE_SIZE))
var current_tile_selected: Vector2 = Vector2.ZERO
var current_game_status: int = -1
var current_player_turn: int = -1
var interactTileSelected: Vector2 = Vector2(-1, -1)
var nextInteractTileSelected: Vector2 = Vector2(-1, -1)
var bot_difficulties_stats: Array = []
var tribes_types: Array = []
var cache_ip_to_connect: String = "127.0.0.1"
var error_message_to_show: String = ""

var gameplay_settings: Dictionary = {
	min_actions_in_game = 1,
	max_actions_in_game = 1,
	territories_per_action = 1,
	start_points = 1,
	gold_per_point = 10,
	troops_to_give_per_point = []
}

var functiles_dict: Dictionary = {
	allies_border = "",
	enemies_border = "",
	owned_border = "",
	not_owned_border = "",
	noinfo_tile = "",
	tile_hover = "",
	tile_hover_not_allowed = "",
	tile_not_selected= "",
	action_start_tile="",
	action_end_tile = "",
	civilian_overpopulation = "",
	civilian_underpopulation = "",
	civilian = "",
	tile_upgrading = "",
	tile_recruiting = "",
	tile_battle = ""
}

enum STATUS {
	LOBBY_WAIT, #Server just started and waiting for players to start
	PRE_GAME, #Select capital and territories for each players
	GAME_STARTED #game is going on
}

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

signal error_joining_server(error_message)
signal player_reconnects(net_id, player_number)

func _ready():
	rng.randomize()
	TileSetImporter = TileSetExternalImporter.new(FileSystem)
	Config.load_from_file(CONFIG_FILE)
	Engine.set_target_fps(Config.get_value("max_fps"))
	init_game_data()
	init_players()
	Network.ready()
	clear_players_data()
	update_settings()

func init_game_data():
	init_bots_stats()
	init_civilization_types()
	init_tiles_types()
	init_troops_types()
	init_buildings_types()
	init_tribal_societies()
	init_functiles()
	init_gameplay_settings()

func init_civilization_types() -> void:
	civilizationTypes.clearList()
	if !civilizationTypes.load_from_file(current_mod, FileSystem): #in case the file does not exists in the mod folder, use the "base" one
		print("[DEBUG] use default civilization_types")
		civilizationTypes.load_from_file(GAME_DEFAULT_MOD, FileSystem)

func save_settings():
	Config.save_to_file(CONFIG_FILE)

func init_functiles():
	var file_path_to_use: String = current_mod + "/" + FUNCTILES_FILE
	if !FileSystem.file_exists(file_path_to_use):
		print("[DEBUG] use default func_tiles")
		file_path_to_use = GAME_DEFAULT_MOD + "/" + FUNCTILES_FILE
	var functilesImportedData: Dictionary = FileSystem.get_data_from_json(file_path_to_use)
	functiles_dict.allies_border = functilesImportedData["allies_border"]
	functiles_dict.enemies_border = functilesImportedData["enemies_border"]
	functiles_dict.owned_border = functilesImportedData["owned_border"]
	functiles_dict.not_owned_border = functilesImportedData["not_owned_border"]
	functiles_dict.noinfo_tile = functilesImportedData["noinfo_tile"]
	functiles_dict.tile_hover = functilesImportedData["tile_hover"]
	functiles_dict.tile_hover_not_allowed = functilesImportedData["tile_hover_not_allowed"]
	functiles_dict.action_start_tile = functilesImportedData["action_start_tile"]
	functiles_dict.action_end_tile = functilesImportedData["action_end_tile"]
	functiles_dict.tile_not_selected = functilesImportedData["tile_not_selected"]
	functiles_dict.civilian_overpopulation = functilesImportedData["civilian_overpopulation"]
	functiles_dict.civilian_underpopulation = functilesImportedData["civilian_underpopulation"]
	functiles_dict.civilian = functilesImportedData["civilian"]
	functiles_dict.tile_upgrading = functilesImportedData["tile_upgrading"]
	functiles_dict.tile_recruiting = functilesImportedData["tile_recruiting"]
	functiles_dict.tile_battle = functilesImportedData["tile_battle"]

func init_gameplay_settings():
	gameplay_settings.troops_to_give_per_point.clear()
	var file_path_to_use: String = current_mod + "/" + GAMEPLAY_SETTINGS_FILE
	if !FileSystem.file_exists(file_path_to_use):
		print("[DEBUG] use default gameplay_settings")
		file_path_to_use = GAME_DEFAULT_MOD + "/" + GAMEPLAY_SETTINGS_FILE
	var settingsImportedData: Dictionary = FileSystem.get_data_from_json(file_path_to_use)
	assert(settingsImportedData.has('min_actions_in_game'))
	gameplay_settings.min_actions_in_game = settingsImportedData["min_actions_in_game"]
	gameplay_settings.max_actions_in_game = settingsImportedData["max_actions_in_game"]
	gameplay_settings.territories_per_action = settingsImportedData["territories_per_action"]
	gameplay_settings.start_points = settingsImportedData["start_points"]
	gameplay_settings.gold_per_point = settingsImportedData["gold_per_point"]
	gameplay_settings.troops_to_give_per_point = settingsImportedData["troops_to_give_per_point"].duplicate(true)
	
func init_bots_stats():
	bot_difficulties_stats.clear()
	var file_path_to_use: String = current_mod + "/" + BOT_STATS_FILE
	if !FileSystem.file_exists(file_path_to_use):
		print("[DEBUG] use default bot_stats")
		file_path_to_use = GAME_DEFAULT_MOD + "/" + BOT_STATS_FILE
	var tilesImportedData: Dictionary = FileSystem.get_data_from_json(file_path_to_use)
	assert(tilesImportedData.has('difficulties'))
	for troopDict in tilesImportedData['difficulties']:
		bot_difficulties_stats.append({
			NAME = troopDict["name"],
			TROOPS_MULT = troopDict["troops_mult"],
			DISCOUNT_MULT = troopDict["buy_discount_mult"],
			EXTRA_GOLD_MULT = troopDict["extra_gold_mult"],
			GAINS_MULT = troopDict["gains_mult"],
			CAPITAL_MINIMUM_RECRUITS = troopDict["capital_minimum_recruits"],
			MINIMUM_BUILDINGS = troopDict["minimum_buildings"],
			MINIMUM_SAVINGS = troopDict["minimum_savings"],
			MAX_SAVINGS = troopDict["max_savings"]
		})

func init_players():
	playersData.clear()
	for i in range (MAX_PLAYERS):
		playersData.append({
			name = 'Player ' + str(i+1),
			pin_code = 000,
			civilizationName = civilizationTypes.getByID(i).default_name,
			civilization_id = i,
			alive = false,
			isBot = false,
			selectLeft = 0,
			netid = -1,
			team = -1, #-1 equals no team, so enemy with everyone 
			turns_played = 0,
			bot_stats = {}
		})

func init_tribal_societies():
	tribalTroops.clearList()
	if !tribalTroops.load_from_file(current_mod, FileSystem): #in case the file does not exists in the mod folder, use the "base" one
		print("[DEBUG] use default tribal_types")
		tribalTroops.load_from_file(GAME_DEFAULT_MOD, FileSystem)
		
func init_tiles_types():
	tileTypes.clearList()
	if !tileTypes.load_from_file(current_mod, FileSystem, civilizationTypes): #in case the file does not exists in the mod folder, use the "base" one
		print("[DEBUG] use default tile_types")
		tileTypes.load_from_file(GAME_DEFAULT_MOD, FileSystem, civilizationTypes)

func init_buildings_types():
	buildingTypes.clearList()
	if !buildingTypes.load_from_file(current_mod, FileSystem, troopTypes): #in case the file does not exists in the mod folder, use the "base" one
		print("[DEBUG] use default building_types")
		buildingTypes.load_from_file(GAME_DEFAULT_MOD, FileSystem, troopTypes)

func init_troops_types():
	troopTypes.clearList()
	if !troopTypes.load_from_file(current_mod, FileSystem):
		print("[DEBUG] use default troop_types")
		troopTypes.load_from_file(GAME_DEFAULT_MOD, FileSystem)

func clear_players_data():
	for i in range(playersData.size()):
		playersData[i].netid = -1
		playersData[i].alive = false
		playersData[i].pin_code = 0

func get_player_number_by_pin_code(pin_code: int) -> int:
	for i in range(playersData.size()):
		if playersData[i].pin_code == pin_code:
			return i
	return -1

func start_new_game(is_mp_game: bool = false):
	current_player_turn = 0
	if !is_mp_game:
		init_player(0, Network.SERVER_NETID, "Stradex", 555, true, 1) #human
		init_player(1, Network.SERVER_NETID, "bot", 1, true, 1) #bot - team 1
		init_player(2, Network.SERVER_NETID, "bot", 1, true, 1) #bot - team 2
		init_player(3, Network.SERVER_NETID, "bot", 3, true, 1) #bot - team 2
		init_player(4, Network.SERVER_NETID, "bot", 3, true, 2) #bot - team 2
		init_player(5, Network.SERVER_NETID, "bot", 3, true, 2) #bot - team 2
		init_player(6, Network.SERVER_NETID, "bot", 3, true, 2) #bot - team 2
		init_player(7, Network.SERVER_NETID, "bot", 3, true, 2) #bot - team 2
		set_bot_difficulty(0, 0)
		set_bot_difficulty(1, 0)
		set_bot_difficulty(2, 0)
		set_bot_difficulty(3, 0)
		set_bot_difficulty(4, 0)
		set_bot_difficulty(5, 0)
		set_bot_difficulty(6, 0)
		set_bot_difficulty(7, 0)
		
	change_to_map(START_MAP)

func are_player_allies(playerA: int, playerB: int) -> bool:
	if playerA == playerB:
		return true
	if playerA < 0 or playerB < 0: #tribal society
		return false
	if playersData[playerA].team == -1 or playersData[playerB].team == -1:
		return false
	return playersData[playerA].team == playersData[playerB].team

func bot_reset_stats(bot_number: int) -> void:
	rng.randomize()
	playersData[bot_number].bot_stats.aggressiveness = rng.randf_range(0.1, 1.0)
	playersData[bot_number].bot_stats.defensiveness  = rng.randf_range(0.1, 1.0)
	playersData[bot_number].bot_stats.avarice = rng.randf_range(0.1, 1.0)
	print("[BOT] reseting stats...")

func init_player(player_id: int, net_id: int, player_name: String = "player", player_pin: int = 0, is_bot:bool = false, team:int = -1):
	playersData[player_id].alive = true
	playersData[player_id].isBot = is_bot
	playersData[player_id].selectLeft = gameplay_settings.start_points
	playersData[player_id].netid = net_id
	playersData[player_id].name = player_name
	playersData[player_id].pin_code = player_pin
	playersData[player_id].team = team
	playersData[player_id].turns_played = 0
	if is_bot:
		playersData[player_id].bot_stats = {
			aggressiveness =  rng.randf_range(0.1, 1.0), #the bigger, the most willing to start expanding and looking for other players the bot will be
			defensiveness  =  rng.randf_range(0.1, 1.0), #the bigger, the most willing to make a strong defense the bot will be willing to
			avarice = rng.randf_range(0.1, 1.0),  #the bigger, the most amount of gains and gold the bot will wish to have
			troops_quality = rng.randf_range(0.1, 1.0), #the bigger, the best kind of troops the bot will want to have
			difficulty = 0,
			path_to_follow = []
		}
	else:
		playersData[player_id].bot_stats.clear()
	
	print("Adding player %s (%d) with netid %d" % [player_name, player_id, net_id])

func get_player_count() -> int:
	var player_count: int = 0
	for i in range(playersData.size()):
		if playersData[i].alive:
			player_count+=1
	return player_count

func get_local_player() -> Dictionary:
	for i in range(playersData.size()):
		if playersData[i].netid == get_tree().get_network_unique_id():
			return playersData[i]
	return {}

func get_local_player_number() -> int:
	if !Network.is_multiplayer():
		return 0
	for i in range(playersData.size()):
		if playersData[i].netid == get_tree().get_network_unique_id():
			return i
	return -1

func get_player_by_netid(var net_id) -> int:
	for i in range(playersData.size()):
		if playersData[i].netid == net_id:
			return i
	return -1

func get_free_netid() -> int:
	var new_net_id: int = Network.BOT_NETID
	var netid_exists: bool = true
	while netid_exists:
		netid_exists = false
		for i in range(playersData.size()):
			if playersData[i].netid == new_net_id:
				new_net_id-=1
				netid_exists = true
				break
	return new_net_id

func kick_player(player_number:int) -> void:
	if Game.Network.is_client() or playersData[player_number].netid == get_tree().get_network_unique_id():
		return
	if !playersData[player_number].isBot and playersData[player_number].netid != get_tree().get_network_unique_id():
		Game.Network.kick_client(playersData[player_number].netid)
	remove_player(player_number)
	
func remove_player(player_number: int) -> void:
	playersData[player_number].name = 'Player ' + str(player_number+1)
	playersData[player_number].pin_code = 000
	playersData[player_number].civilizationName = civilizationTypes.getByID(player_number).default_name
	playersData[player_number].civilization_id = player_number
	playersData[player_number].alive = false
	playersData[player_number].isBot = false
	playersData[player_number].selectLeft = false
	playersData[player_number].netid = -1
	playersData[player_number].team = -1
	playersData[player_number].turns_played = 0
	playersData[player_number].bot_stats.clear()
	
func remove_net_player(netid: int) -> void:
	var player_id: int = get_player_by_netid(netid)
	if player_id == -1:
		return
	remove_player(player_id)

func add_player(netid: int, player_name: String, player_pin: int, forceid: int = -1, isBot: bool = false) -> int:
	
	if isBot:
		netid = get_free_netid()
	
	var free_player_index: int = 0
	for i in range(playersData.size()):
		if playersData[i].netid != -1:
			free_player_index += 1
			if playersData[i].netid == netid: #already exists this player
				playersData[i].name = player_name
				playersData[i].pin_code = player_pin
				playersData[i].isBot =  isBot
				print("The player %d with netid %d was already in the list!!" % [i, netid])
				return i
			continue
		break
	
	if forceid != -1:
		free_player_index = forceid
	
	init_player(free_player_index, netid, player_name, player_pin, isBot)
	return free_player_index

func set_bot_difficulty(bot_number: int, new_difficulty: int) -> void:
	playersData[bot_number].bot_stats.difficulty = new_difficulty
	
func get_bot_difficulty(bot_number: int) -> int:
	return playersData[bot_number].bot_stats.difficulty

func get_next_player_turn() -> int:
	for i in range(playersData.size()):
		if i != current_player_turn and playersData[i].alive:
			return i
	return current_player_turn

func get_bot_minimum_buildings(bot_number: int) -> int:
	return get_bot_difficulty_stats(bot_number).MINIMUM_BUILDINGS

func get_bot_minimum_capital_troops(bot_number: int) -> int:
	return get_bot_difficulty_stats(bot_number).CAPITAL_MINIMUM_RECRUITS

func get_bot_difficulty_stats(bot_number: int) -> Dictionary:
	return bot_difficulties_stats[get_bot_difficulty(bot_number)]

func get_bot_troops_multiplier(bot_number: int) -> float:
	return get_bot_difficulty_stats(bot_number).TROOPS_MULT
	
func get_bot_discount_multiplier(bot_number: int) -> float:
	return get_bot_difficulty_stats(bot_number).DISCOUNT_MULT

func get_bot_extra_gold_multiplier(bot_number: int) -> float:
	return get_bot_difficulty_stats(bot_number).EXTRA_GOLD_MULT

func get_bot_gains_multiplier(bot_number: int) -> float:
	return get_bot_difficulty_stats(bot_number).GAINS_MULT

func get_bot_minimum_savings(bot_number: int) -> float:
	return float(get_bot_difficulty_stats(bot_number).MINIMUM_SAVINGS)

func get_bot_max_savings(bot_number: int) -> float:
	return float(get_bot_difficulty_stats(bot_number).MAX_SAVINGS)

func is_player_a_bot(playerNumber: int) -> bool:
	if playerNumber == -1:
		return false
	return playersData[playerNumber].isBot

func is_current_player_a_bot() -> bool:
	return playersData[current_player_turn].isBot

remote func change_to_map(map_name: String):
	var full_map_path: String = self.MAPS_FOLDER + map_name
	get_tree().call_deferred("change_scene", full_map_path)

func go_to_main_menu(error_msg: String = ""):
	error_message_to_show = error_msg
	get_tree().call_deferred("change_scene", MENU_NODE)


func pause() -> void:
	get_tree().paused = true
	
func unpause() -> void:
	get_tree().paused = false

func update_settings():
	OS.window_fullscreen = Config.get_value("fullscreen")
	OS.set_window_size(Config.get_value("resolution"))

func get_max_float(numbers_array: Array) -> float:
	var new_array: Array = numbers_array.duplicate(true)
	new_array.sort()
	return max(new_array[0], new_array[new_array.size()-1])

func get_min_float(numbers_array: Array) -> float:
	var new_array: Array = numbers_array.duplicate(true)
	new_array.sort()
	return min(new_array[0], new_array[new_array.size()-1])

remote func game_process_rpc(method_name: String, data: Array): 
	Network.callv(method_name, data);

func get_save_game_folder() -> String:
	return current_mod + "/saves/"  

func prepare_new_game() -> void:
	current_tile_selected = Vector2.ZERO
	current_game_status = -1
	current_player_turn = -1


func get_mods_list() -> Array:
	var directories_list: Array = FileSystem.list_directories("./")
	var mod_list: Array = []
	for directory in directories_list:
		if FileSystem.list_files_in_directory(directory, ".json").size() > 0:
			mod_list.append(directory)
	return mod_list

func switch_to_mod(new_mode: String) -> bool:
	var mod_list: Array = get_mods_list()
	var mod_exists: bool = false
	for mod_name in mod_list:
		if new_mode.to_lower() == mod_name.to_lower():
			mod_exists = true
			break
	if !mod_exists:
		return false
	current_mod = new_mode
	init_game_data()
	return true
