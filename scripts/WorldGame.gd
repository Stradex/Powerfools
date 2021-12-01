extends Node2D

#TODO: 
#	1) Prepare the player/civilization data object where all the data should be stored
#	2) Prepare the tile/cell data object (data that should be stored in the tile)
#	3) Prepare the object data for different troops (recruits, soldiers and Elite)

onready var id_tile_non_selected: int = $SelectionTiles.tile_set.find_tile_by_name('off')
onready var id_tile_selected: int = $SelectionTiles.tile_set.find_tile_by_name('tile_hover')
onready var tile_map_size: Vector2 = Vector2(round(Game.SCREEN_WIDTH/Game.TILE_SIZE), round(Game.SCREEN_HEIGHT/Game.TILE_SIZE))

onready var current_game_status: int = -1
onready var current_player_turn: int = -1
var time_offset: float = 0.0

var tiles_data = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new();

onready var default_tile: Dictionary = {
	owner = -1,
	name = "untitled",
	tile_id = Game.tileTypes.getIDByName("rural"),
	gold = 0,
	troops = []
}

var current_tile_selected: Vector2 = Vector2.ZERO

func _ready():
	init_tile_data()
	change_game_status(Game.STATUS.PRE_GAME)
	move_to_next_player_turn()

func init_tile_data() -> void: 
	tiles_data = []
	for x in range(tile_map_size.x):
		tiles_data.append([])
		for y in range(tile_map_size.y):
			tiles_data[x].append(default_tile.duplicate(true))

func _process(delta):
	update_selection_tiles()
	time_offset+=delta
	if (time_offset > 1.0/Game.GAME_FPS):
		time_offset = 0.0
		game_on()

func update_selection_tiles() -> void:

	var mouse_pos: Vector2 = get_global_mouse_position()
	var tile_selected: Vector2 = $SelectionTiles.world_to_map(mouse_pos)
	if current_tile_selected == tile_selected:
		return
	
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if Vector2(x, y) == tile_selected:
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_selected)
			else:
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_non_selected)
	current_tile_selected = tile_selected

func _input(event):
	if Input.is_action_just_pressed("show_info"):
		print("Tile " + str(current_tile_selected) + " data:\n\t"  + str(tiles_data[current_tile_selected.x][current_tile_selected.y]))
	if Input.is_action_just_pressed("interact"):
		match current_game_status:
			Game.STATUS.PRE_GAME:
				pre_game_interact()
			Game.STATUS.GAME_STARTED:
				pass

func pre_game_interact():
	if !player_has_capital(current_player_turn):
		give_player_capital(current_player_turn, current_tile_selected)
	elif Game.playersData[current_player_turn].selectLeft >= 0 :
		pass

#Gameplay stuff related here

func change_game_status(new_status: int) -> void:
	current_game_status = new_status
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
	for i in range(Game.playersData.size()):
		if i != current_player_turn and Game.playersData[i].alive:
			current_player_turn = i
			print("Player " + str(i) + " turn")
			return
		i+=1

#Util stuff

func player_has_capital(playerNumber: int) -> bool:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber and tiles_data[x][y].tile_id == Game.tileTypes.getIDByName("capital"):
				return true
	return false

func get_player_tiles_count(playerNumber: int) -> int:
	var count: int = 0
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber:
				count+=1
	return count

func give_player_a_tile(playerNumber: int, tile_pos: Vector2, tile_type_id: int, add_gold: int, add_troops: Dictionary) -> void:
	tiles_data[tile_pos.x][tile_pos.y].owner = playerNumber
	tiles_data[tile_pos.x][tile_pos.y].gold += add_gold
	tiles_data[tile_pos.x][tile_pos.y].tile_id = tile_type_id
	tiles_data[tile_pos.x][tile_pos.y].name =  str(Game.playersData[playerNumber].civilizationName) + ": Territorio #" + str(get_player_tiles_count(playerNumber)-1)
	add_troops_to_tile(tile_pos, add_troops)


func add_troops_to_tile(tile_pos: Vector2, add_troops: Dictionary) -> void:
	for i in range(tiles_data[tile_pos.x][tile_pos.y].troops.size()):
		if tiles_data[tile_pos.x][tile_pos.y].troops[i].owner == add_troops.owner and tiles_data[tile_pos.x][tile_pos.y].troops[i].troop_id == add_troops.troop_id:
			tiles_data[tile_pos.x][tile_pos.y].troops[i].amount += add_troops.amount
			return
	tiles_data[tile_pos.x][tile_pos.y].troops.append(add_troops)

#Shorthands util

func give_player_capital(playerNumber: int, tile_pos: Vector2) ->void:
	var starting_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = 10000
	}
	give_player_a_tile(playerNumber, tile_pos, Game.tileTypes.getIDByName("capital"), 0, starting_population)
	tiles_data[tile_pos.x][tile_pos.y].name = str(Game.playersData[playerNumber].civilizationName) + ": Capital"
