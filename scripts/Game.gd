extends Node

const VERSION: String = "0.1.1" #Major, Minor, build count
const PORT: int = 27666
const MAX_PLAYERS: int = 8
const SNAPSHOT_DELAY: float = 1.0/30.0 #msec to sec
const MAPS_FOLDER: String = "res://scenes/"
const START_MAP: String = "WorldGame.tscn"
const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 720
const TILE_SIZE: int = 80
const GAME_FPS: int = 4 # we really don't need to much higher FPS, this is mostly for game logic, not graphic stuff
const DATA_FILES_FOLDER: String = "data";
const DEBUG_MODE: bool = true

var current_turn: int = 0
onready var troopTypes: TroopTypesObject = TroopTypesObject.new()
onready var buildingTypes: BuildingTypesObject = BuildingTypesObject.new()
onready var tileTypes: TilesTypesObject = TilesTypesObject.new()
onready var Network: NetworkBase = NetworkBase.new()
onready var FileSystem: FileSystemBase = FileSystemBase.new();
onready var Util: UtilObject = UtilObject.new()
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

var local_name: String = "player"
var local_pin: int = 0

var bot_difficulties_stats: Array = []

enum STATUS {
	LOBBY_WAIT, #Server just started and waiting for players to start
	PRE_GAME, #Select capital and territories for each players
	GAME_STARTED #game is going on
}

enum BOT_DIFFICULTY {
	EASY,
	NORMAL,
	HARD,
	NIGHTMARE,
	MAX_DIFFICULTIES
}

var defaultCivilizationNames: Array = [
	"Asiria",
	"Egipto",
	"Persia",
	"Sparta",
	"Roma",
	"Cartago",
	"Tebas",
	"Argos"
]
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready():
	rng.randomize()
	init_bots_stats()
	init_players()
	init_tiles_types()
	init_troops_types()
	init_buildings_types()
	Network.ready()
	clear_players_data()
	

func init_bots_stats():
	bot_difficulties_stats.clear()
	bot_difficulties_stats.resize(BOT_DIFFICULTY.MAX_DIFFICULTIES)
	bot_difficulties_stats[BOT_DIFFICULTY.EASY] = {
		TROOPS_MULT = 1.0,
		DISCOUNT_MULT = 1.0,
		EXTRA_GOLD_MULT = 1.0,
		GAINS_MULT = 1.0,
		CAPITAL_MINIMUM_RECRUITS = 1000,
		MINIMUM_BUILDINGS = 1
	}
	bot_difficulties_stats[BOT_DIFFICULTY.NORMAL] = {
		TROOPS_MULT = 1.2,
		DISCOUNT_MULT = 0.85,
		EXTRA_GOLD_MULT = 1.25,
		GAINS_MULT = 1.1,
		CAPITAL_MINIMUM_RECRUITS = 2000,
		MINIMUM_BUILDINGS = 2
	}
	bot_difficulties_stats[BOT_DIFFICULTY.HARD] = {
		TROOPS_MULT = 1.5,
		DISCOUNT_MULT = 0.65,
		EXTRA_GOLD_MULT = 1.5,
		GAINS_MULT = 1.25,
		CAPITAL_MINIMUM_RECRUITS = 3000,
		MINIMUM_BUILDINGS = 3
	}
	bot_difficulties_stats[BOT_DIFFICULTY.NIGHTMARE] = {
		TROOPS_MULT = 2.0,
		DISCOUNT_MULT = 0.5,
		EXTRA_GOLD_MULT = 2.0,
		GAINS_MULT = 1.5,
		CAPITAL_MINIMUM_RECRUITS = 5000,
		MINIMUM_BUILDINGS = 4
	}

func init_players():
	playersData.clear()
	for i in range (MAX_PLAYERS):
		playersData.append({
			name = 'Player ' + str(i+1),
			pin_code = 000,
			civilizationName = defaultCivilizationNames[i],
			alive = false,
			isBot = false,
			selectLeft = 0,
			netid = -1,
			team = -1, #-1 equals no team, so enemy with everyone 
			turns_played = 0,
			bot_stats = {}
		})

func init_tiles_types():
	tileTypes.clearList()
	#Adding tiles START
	tileTypes.add({
		name = "vacio",
		next_stage = "rural",
		improve_prize = 15,
		turns_to_improve = 2,
		gold_to_produce = 0,
		strength_boost = 0,
		sell_prize = 2,
		conquer_gain = 2, #edit later
		tile_img = 'tile_empty',
		min_civil_to_produce_gold = 0, #minimum amount of civilians to produce gold
		max_civil_to_produce_gold = 0  #maximum amount of civilians to produce gold
	})
	tileTypes.add({
		name = "rural",
		next_stage = "ciudad",
		improve_prize = 30,
		turns_to_improve = 3,
		gold_to_produce = 1,
		strength_boost = 0,
		sell_prize = 5,
		conquer_gain = 5, #edit later
		tile_img = 'tile_rural',
		min_civil_to_produce_gold = 500, #minimum amount of civilians to produce gold
		max_civil_to_produce_gold = 2000  #maximum amount of civilians to produce gold
	})
	tileTypes.add({
		name = "ciudad",
		next_stage = "metropolis",
		improve_prize = 60,
		turns_to_improve = 6,
		gold_to_produce = 2,
		strength_boost = 0.1,
		sell_prize = 10,
		conquer_gain = 15, #edit later
		tile_img = 'tile_city',
		min_civil_to_produce_gold = 1000, #minimum amount of civilians to produce gold
		max_civil_to_produce_gold = 5000  #maximum amount of civilians to produce gold
	})
	tileTypes.add({
		name = "metropolis",
		next_stage = "", #leave empty if there is no more improvements left
		improve_prize = 0,
		turns_to_improve = 0,
		gold_to_produce = 3,
		strength_boost = 0.2,
		sell_prize = 30,
		conquer_gain = 50, #edit later
		tile_img = 'tile_metropolis',
		min_civil_to_produce_gold = 2500, #minimum amount of civilians to produce gold
		max_civil_to_produce_gold = 10000  #maximum amount of civilians to produce gold
	})
	tileTypes.add({
		name = "capital",
		next_stage = "", #leave empty if there is no more improvements left
		improve_prize = 0,
		turns_to_improve = 0,
		gold_to_produce = 4,
		strength_boost = 0.25,
		sell_prize = -1,
		conquer_gain = 100, #edit later
		tile_img = 'tile_capital',
		min_civil_to_produce_gold = 5000, #minimum amount of civilians to produce gold
		max_civil_to_produce_gold = 20000  #maximum amount of civilians to produce gold
	})
	#Adding tiles END

func init_buildings_types():
	buildingTypes.clearList()
	buildingTypes.load_from_file(DATA_FILES_FOLDER, FileSystem, troopTypes)
	#Adding buildings START
	#Adding builinds END

func init_troops_types():
	troopTypes.clearList()
	troopTypes.load_from_file(DATA_FILES_FOLDER, FileSystem)

func clear_players_data():
	for i in range(playersData.size()):
		playersData[i].netid = -1
		playersData[i].alive = false

func start_new_game(is_mp_game: bool = false):
	current_player_turn = 0
	if !is_mp_game:
		init_player(0, Game.Network.SERVER_NETID, "Stradex", 555, true, 1) #human
		init_player(1, Game.Network.SERVER_NETID, "bot", 1, true, 2) #bot - team 1
		#init_player(2, Game.Network.SERVER_NETID, "bot", 1, true, 2) #bot - team 1
		#init_player(2, Game.Network.SERVER_NETID, "bot", 3, true, 2) #bot - team 2
		#init_player(3, Game.Network.SERVER_NETID, "bot", 4, true, 2) #bot - team 2
		#init_player(4, Game.Network.SERVER_NETID, "bot", 4, true, 2) #bot - team 2
		set_bot_difficulty(0, BOT_DIFFICULTY.NIGHTMARE)
		set_bot_difficulty(1, BOT_DIFFICULTY.HARD)
		#set_bot_difficulty(2, BOT_DIFFICULTY.HARD)
		#set_bot_difficulty(2, BOT_DIFFICULTY.EASY)
		#set_bot_difficulty(3, BOT_DIFFICULTY.EASY)
		#set_bot_difficulty(4, BOT_DIFFICULTY.EASY)
	#else:
	#	init_player(2, Game.Network.SERVER_NETID, "bot", 2, true, 1) #Just for testing only
	#	init_player(3, Game.Network.SERVER_NETID, "bot", 3, true, 1) #Just for testing only
	#	init_player(4, Game.Network.SERVER_NETID, "bot", 4, true, 1) #Just for testing only
		#init_player(5, Game.Network.SERVER_NETID, "bot", 5, true, 1) #Just for testing only
	change_to_map(START_MAP)

func are_player_allies(playerA: int, playerB: int) -> bool:
	if playerA == playerB:
		return true
	if playerA < 0 or playerB < 0:
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
	playersData[player_id].selectLeft = 10
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
			difficulty = BOT_DIFFICULTY.HARD,
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

func get_free_netid() -> int:
	var new_net_id: int = Game.Network.BOT_NETID
	var netid_exists: bool = true
	while netid_exists:
		netid_exists = false
		for i in range(playersData.size()):
			if playersData[i].netid == new_net_id:
				new_net_id-=1
				netid_exists = true
				break
	return new_net_id
		
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

func is_player_a_bot(playerNumber: int) -> bool:
	return playersData[playerNumber].isBot

func is_current_player_a_bot() -> bool:
	return playersData[current_player_turn].isBot

remote func change_to_map(map_name: String):
	var full_map_path: String = self.MAPS_FOLDER + map_name;
	get_tree().call_deferred("change_scene", full_map_path);

func pause() -> void:
	get_tree().paused = true
	
func unpause() -> void:
	get_tree().paused = false

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
