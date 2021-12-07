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

var current_turn: int = 0

onready var troopTypes: TroopTypesObject = TroopTypesObject.new()
onready var buildingTypes: BuildingTypesObject = BuildingTypesObject.new()
onready var tileTypes: TilesTypesObject = TilesTypesObject.new()
var tilesObj: TileGameObject

var playersData: Array

var tile_map_size: Vector2 = Vector2(round(SCREEN_WIDTH/TILE_SIZE), round(SCREEN_HEIGHT/TILE_SIZE))

var current_tile_selected: Vector2 = Vector2.ZERO
var current_game_status: int = -1
var current_player_turn: int = -1

var interactTileSelected: Vector2 = Vector2(-1, -1)
var nextInteractTileSelected: Vector2 = Vector2(-1, -1)

enum STATUS {
	PRE_GAME, #Select capital and territories for each players
	GAME_STARTED #game is going on
}

var defaultCivilizationNames: Array = [
	"Asiria",
	"Egipto",
	"Persia",
	"Sparta"
]

#var InvalidTile: Dictionary = {
#	name = "invalid",
#	next_stage = "none", #leave it blank if this tile cannot be improved
#	improve_prize = 0,
#	turns_to_improve = 0,
#	gold_to_produce = 0, #ammount of gold to produce per turn
#	strength_boost = 0, #ammount of extra damage in % that the owner of this tile gets in their troops
#	sell_prize = 0, #ammount of gold to receive in case of this sold
#	conquer_gain = 0 #ammount of gold to receive in case of conquering this land
#}

func _ready():
	init_players()
	init_tiles_types()
	init_troops_types()
	init_buildings_types()

func init_players():
	playersData.clear()
	for i in range (MAX_PLAYERS):
		playersData.append({
			name = 'Player ' + str(i+1),
			civilizationName = defaultCivilizationNames[i],
			alive = false,
			isBot = false,
			selectLeft = 0
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
	#Adding buildings START
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
	#Adding builinds END

func init_troops_types():
	troopTypes.clearList()
	
	#Adding troops start
	troopTypes.add({
		name = "civil",
		no_building = true,
		can_be_bought = false,
		is_warrior = false,
		cost_to_make = 0,
		damage = Vector2(0.2, 0.5),
		idle_cost_per_turn = 0,
		moving_cost_per_turn = 1,
		battle_cost_per_turn = 1,
		health = 1
	})
	
	#Tropa recluta default
	troopTypes.add({
		name = "recluta",
		no_building = false,
		can_be_bought = true,
		is_warrior = true,
		cost_to_make = 5,
		damage = Vector2(1, 3),
		idle_cost_per_turn = 1,
		moving_cost_per_turn = 1.5,
		battle_cost_per_turn = 2,
		health = 3
	})
	#Adding troops ends

func start_new_game():
	change_to_map(START_MAP);
	current_player_turn = 0
	playersData[0].alive = true
	playersData[0].isBot = false
	playersData[0].selectLeft = 10
	playersData[1].alive = true
	playersData[1].isBot = false
	playersData[1].selectLeft = 10

remote func change_to_map(map_name: String):
	var full_map_path: String = self.MAPS_FOLDER + map_name;
	get_tree().call_deferred("change_scene", full_map_path);

func pause() -> void:
	get_tree().paused = true
	
func unpause() -> void:
	get_tree().paused = false

func is_singleplayer_game():
	return !get_tree().has_network_peer()

func is_network_master_or_sp(caller: Node):
	return is_singleplayer_game() or caller.is_network_master()

func is_client() -> bool:
	return get_tree().has_network_peer() and !get_tree().is_network_server()

func is_client_connected() -> bool:
	if !get_tree().has_network_peer() or get_tree().is_network_server():
		return false
	return get_tree().get_network_peer().get_connection_status() == get_tree().get_network_peer().CONNECTION_CONNECTED
