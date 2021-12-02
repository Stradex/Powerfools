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
var player_in_menu: bool = false
var tiles_data = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new();

onready var default_tile: Dictionary = {
	owner = -1,
	name = "untitled",
	tile_id = Game.tileTypes.getIDByName("vacio"),
	gold = 0,
	troops = []
}

var current_tile_selected: Vector2 = Vector2.ZERO

func _ready():
	$ActionsMenu/InGameTileActions.visible = false
	$ActionsMenu/ExtrasMenu.visible = false
	$ActionsMenu/ExtrasMenu/VBoxContainer/Cancelar.connect("pressed", self, "hide_extras_menu")
	$ActionsMenu/ExtrasMenu/VBoxContainer/ObtenerTalentos.connect("pressed", self, "give_extra_gold")
	$ActionsMenu/ExtrasMenu/VBoxContainer/ObtenerTropas.connect("pressed", self, "add_extra_troops")
	$ActionsMenu/InGameTileActions/VBoxContainer/Cancelar.connect("pressed", self, "hide_ingame_actions")
	init_tile_data()
	change_game_status(Game.STATUS.PRE_GAME)
	move_to_next_player_turn()

func hide_ingame_actions():
	$ActionsMenu/InGameTileActions.visible = false
	
func hide_extras_menu():
	$ActionsMenu/ExtrasMenu.visible = false

func give_extra_gold():
	tiles_data[current_tile_selected.x][current_tile_selected.y].gold += 10
	$ActionsMenu/ExtrasMenu.visible = false
	Game.playersData[current_player_turn].selectLeft-=1
	if Game.playersData[current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()

func add_extra_troops():
	var extraRecruits: Dictionary = {
		owner = current_player_turn,
		troop_id = Game.troopTypes.getIDByName("recluta"),
		amount = 1000
	}
	add_troops_to_tile(current_tile_selected, extraRecruits)
	$ActionsMenu/ExtrasMenu.visible = false
	Game.playersData[current_player_turn].selectLeft-=1
	if Game.playersData[current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()

func init_tile_data() -> void: 
	tiles_data = []
	for x in range(tile_map_size.x):
		tiles_data.append([])
		for y in range(tile_map_size.y):
			tiles_data[x].append(default_tile.duplicate(true))

func _process(delta):
	player_in_menu = $ActionsMenu/ExtrasMenu.visible or $ActionsMenu/InGameTileActions.visible
	if player_in_menu:
		return
	update_selection_tiles()
	time_offset+=delta
	if (time_offset > 1.0/Game.GAME_FPS):
		time_offset = 0.0
		game_on()
		update_building_tiles()
		gui_update_tile_info(current_tile_selected)
		gui_update_civilization_info(current_player_turn)
		$PreGameInfo/HBoxContainer/PointsLeftText.text = str(Game.playersData[current_player_turn].selectLeft)

func update_building_tiles() -> void:
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			var tileImgToSet = $BuildingsTiles.tile_set.find_tile_by_name(Game.tileTypes.getImg(tiles_data[x][y].tile_id))
			$BuildingsTiles.set_cellv(Vector2(x, y), tileImgToSet)
			
func update_selection_tiles() -> void:

	var mouse_pos: Vector2 = get_global_mouse_position()
	var tile_selected: Vector2 = $SelectionTiles.world_to_map(mouse_pos)
	if current_tile_selected == tile_selected:
		return
	
	if tile_selected.x >= tile_map_size.x or tile_selected.x < 0 or tile_selected.y >= tile_map_size.y or tile_selected.y < 0:
		return
	
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if Vector2(x, y) == tile_selected:
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_selected)
			else:
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_non_selected)
	current_tile_selected = tile_selected

func _input(event):
	if $ActionsMenu/ExtrasMenu.visible:
		return
	if Input.is_action_just_pressed("toggle_tile_info"):
		$TileInfo.visible = !$TileInfo.visible 
	if Input.is_action_just_pressed("toggle_civ_info"):
		$CivilizationInfo.visible = !$CivilizationInfo.visible
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
				pass

func game_tile_show_info():
	if tiles_data[current_tile_selected.x][current_tile_selected.y].owner != current_player_turn:
		return
	
	$ActionsMenu/InGameTileActions/VBoxContainer/VenderTile.visible = Game.tileTypes.canBeSold(tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id)
	#if tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id ==  Game.tileTypes.getIDByName("capital"):
	$ActionsMenu/InGameTileActions/VBoxContainer/UrbanizarTile.visible = Game.tileTypes.canBeUpgraded(tiles_data[current_tile_selected.x][current_tile_selected.y].tile_id)
	$ActionsMenu/InGameTileActions.visible = true

func pre_game_interact():
	if is_tile_owned_by_player(current_tile_selected):
		if tiles_data[current_tile_selected.x][current_tile_selected.y].owner == current_player_turn:
			$ActionsMenu/ExtrasMenu.visible = true
		return
	if !player_has_capital(current_player_turn):
		give_player_capital(current_player_turn, current_tile_selected)
	elif Game.playersData[current_player_turn].selectLeft > 0 :
		give_player_rural(current_player_turn, current_tile_selected)
		Game.playersData[current_player_turn].selectLeft-=1
	
	if Game.playersData[current_player_turn].selectLeft == 0: 
		move_to_next_player_turn()
#Gameplay stuff related here

func change_game_status(new_status: int) -> void:
	current_game_status = new_status
	match new_status:
		Game.STATUS.PRE_GAME:
			$GameInfo.visible = false
			$PreGameInfo.visible = true
		Game.STATUS.GAME_STARTED:
			$PreGameInfo.visible = false
			$GameInfo.visible = true
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

func is_tile_owned_by_player(tile_pos: Vector2) -> bool:
	return tiles_data[tile_pos.x][tile_pos.y].owner >= 0

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
	tiles_data[tile_pos.x][tile_pos.y].name =  "Territorio #" + str(get_player_tiles_count(playerNumber)-1)
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
	tiles_data[tile_pos.x][tile_pos.y].name = "Capital"

func give_player_rural(playerNumber: int, tile_pos: Vector2) ->void:
	var starting_population: Dictionary = {
		owner = playerNumber,
		troop_id = Game.troopTypes.getIDByName("civil"),
		amount = 1000
	}
	give_player_a_tile(playerNumber, tile_pos, Game.tileTypes.getIDByName("rural"), 0, starting_population)

func get_total_gold(playerNumber: int) -> float:
	var totalGold: float = 0.0
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if tiles_data[x][y].owner == playerNumber:
				totalGold += tiles_data[x][y].gold
	return floor(totalGold)

func get_tile_strength(tilePos: Vector2, playerNumber: int) -> float:
	var totalStrength: float = 0.0
	var totalTroops: int = 0
	var totalHealth: int = 0
	var averageHealth: float = 0.0
	for troopDict in tiles_data[tilePos.x][tilePos.y].troops:
		if troopDict.owner != playerNumber:
			continue
		totalHealth += Game.troopTypes.getByID(troopDict.troop_id).health*troopDict.amount
		totalTroops += troopDict.amount
		var averageTroopDamage: float = (Game.troopTypes.getByID(troopDict.troop_id).damage.x + Game.troopTypes.getByID(troopDict.troop_id).damage.y)/2.0
		totalStrength += averageTroopDamage*troopDict.amount

	if totalTroops > 0:
		averageHealth = float(totalHealth) / float(totalTroops)
	return round(totalStrength*averageHealth/200.0)

func get_total_strength(playerNumber: int) -> float:
	var totalStrength: float = 0.0
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			totalStrength+= get_tile_strength(Vector2(x, y), playerNumber)
	
	return totalStrength

func get_civ_population_info(playerNumber: int) -> Array:
	var troopsInfo: Array = []
	var troopExists: bool = false
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			for troopDict in tiles_data[x][y].troops:
				if troopDict.owner != playerNumber:
					continue
				troopExists = false
				for returnTroop in troopsInfo:
					if returnTroop.troop_id == troopDict.troop_id:
						returnTroop.amount += troopDict.amount
						troopExists = true
				if !troopExists:
					troopsInfo.append({troop_id = troopDict.troop_id, amount = troopDict.amount})
	return troopsInfo
	
func gui_update_civilization_info(playerNumber: int) -> void:
	$CivilizationInfo/VBoxContainer/HBoxContainer5/CivilizationText.text = str(Game.playersData[playerNumber].civilizationName)
	$CivilizationInfo/VBoxContainer/HBoxContainer/TotTalentosText.text = str(get_total_gold(playerNumber))
	$CivilizationInfo/VBoxContainer/HBoxContainer2/StrengthText.text = str(get_total_strength(playerNumber))
	var civilizationTroopsInfo: Array = get_civ_population_info(playerNumber)
	var populationStr: String = ""
	
	for troopDict in civilizationTroopsInfo:
		populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	
	$CivilizationInfo/VBoxContainer/HBoxContainer4/TotPopulationText.text = populationStr

func gui_update_tile_info(tile_pos: Vector2) -> void:
	"""
	if current_game_status == Game.STATUS.PRE_GAME:
		$TileInfo/VBoxContainer/HBoxContainer5/TurnText.text = "PRE-GAME: " + str(Game.playersData[current_player_turn].civilizationName)
	elif current_game_status == Game.STATUS.GAME_STARTED:
		$TileInfo/VBoxContainer/HBoxContainer5/TurnText.text = str(Game.playersData[current_player_turn].civilizationName)
	else:
		$TileInfo/VBoxContainer/HBoxContainer5/TurnText.text = "??"
	"""
	
	$TileInfo/VBoxContainer/HBoxContainer5/TileName.text = tiles_data[tile_pos.x][tile_pos.y].name
	if tiles_data[tile_pos.x][tile_pos.y].owner == -1:
		$TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = "No info"
	else:
		$TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = str(Game.playersData[tiles_data[tile_pos.x][tile_pos.y].owner].civilizationName)
	$TileInfo/VBoxContainer/HBoxContainer2/Amount.text = str(floor(tiles_data[tile_pos.x][tile_pos.y].gold))
	
	$TileInfo/VBoxContainer/HBoxContainer6/StrengthText.text = str(get_tile_strength(tile_pos, current_player_turn))
	
	var populationStr: String = ""
	
	for troopDict in tiles_data[tile_pos.x][tile_pos.y].troops:
		populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	
	$TileInfo/VBoxContainer/HBoxContainer4/PopulationText.text = populationStr
