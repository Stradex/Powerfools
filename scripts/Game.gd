extends Node

const VERSION: String = "0.1.1" #Major, Minor, build count
const PORT: int = 27666
const MAX_PLAYERS: int = 4
const SNAPSHOT_DELAY: float = 1.0/30.0 #msec to sec
const MAPS_FOLDER: String = "res://scenes/"
const START_MAP: String = "WorldGame.tscn"
const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 720
const TILE_SIZE: int = 80
const GAME_FPS: int = 4 # we really don't need to much higher FPS, this is mostly for game logic, not graphic stuff
const DATA_FILES_FOLDER: String = "data";
var current_turn: int = 0
onready var troopTypes: TroopTypesObject = TroopTypesObject.new()
onready var buildingTypes: BuildingTypesObject = BuildingTypesObject.new()
onready var tileTypes: TilesTypesObject = TilesTypesObject.new()
onready var Network: NetworkBase = NetworkBase.new()
onready var FileSystem: FileSystemBase = FileSystemBase.new();
var Boop_Object = preload("res://scripts/Netcode/Boop.gd");

var tilesObj: TileGameObject
var playersData: Array
var tile_map_size: Vector2 = Vector2(round(SCREEN_WIDTH/TILE_SIZE), round(SCREEN_HEIGHT/TILE_SIZE))
var current_tile_selected: Vector2 = Vector2.ZERO
var current_game_status: int = -1
var current_player_turn: int = -1
var interactTileSelected: Vector2 = Vector2(-1, -1)
var nextInteractTileSelected: Vector2 = Vector2(-1, -1)

var local_name: String = "player"
var local_pin: int = 0

enum STATUS {
	LOBBY_WAIT, #Server just started and waiting for players to start
	PRE_GAME, #Select capital and territories for each players
	GAME_STARTED #game is going on
}

var defaultCivilizationNames: Array = [
	"Asiria",
	"Egipto",
	"Persia",
	"Sparta"
]

func _ready():
	init_players()
	init_tiles_types()
	init_troops_types()
	init_buildings_types()
	Network.ready()
	clear_players_data()
	

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
			netid = -1
		})

func init_tiles_types():
	tileTypes.clearList()
	#Adding tiles START
	tileTypes.add({
		name = "vacio",
		next_stage = "rural",
		improve_prize = 15,
		turns_to_improve = 3,
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
		turns_to_improve = 5,
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
		improve_prize = 100,
		turns_to_improve = 10,
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
	"""
	buildingTypes.add({
		name = "Campo Militar",
		buy_prize = 50,
		sell_prize = 15,
		deploy_prize = 5,
		turns_to_build = 10,
		id_troop_generate = troopTypes.getIDByName("recluta"),
		building_img = 'military_camp',
		turns_to_deploy_troops = 3,
		deploy_amount = 500
	})
	"""
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
		init_player(0, Game.Network.SERVER_NETID) #human
		init_player(1, Game.Network.SERVER_NETID, "bot", 1, true) #bot
	change_to_map(START_MAP)

func init_player(player_id: int, net_id: int, player_name: String = "player", player_pin: int = 0, is_bot:bool = false):
	playersData[player_id].alive = true
	playersData[player_id].isBot = is_bot
	playersData[player_id].selectLeft = 10
	playersData[player_id].netid = net_id
	playersData[player_id].name = player_name
	playersData[player_id].pin_code = player_pin
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

func add_player(netid: int, player_name: String, player_pin: int, forceid: int = -1) -> int:
	var free_player_index: int = 0
	for i in range(playersData.size()):
		if playersData[i].netid != -1:
			free_player_index += 1
			if playersData[i].netid == netid: #already exists this player
				playersData[i].name = player_name
				playersData[i].pin_code = player_pin
				print("The player %d with netid %d was already in the list!!" % [i, netid])
				return i
			continue
		break
	
	if forceid != -1:
		free_player_index = forceid
	
	init_player(free_player_index, netid, player_name, player_pin)
	return free_player_index

remote func change_to_map(map_name: String):
	var full_map_path: String = self.MAPS_FOLDER + map_name;
	get_tree().call_deferred("change_scene", full_map_path);

func pause() -> void:
	get_tree().paused = true
	
func unpause() -> void:
	get_tree().paused = false

remote func game_process_rpc(method_name: String, data: Array): 
	Network.callv(method_name, data);
