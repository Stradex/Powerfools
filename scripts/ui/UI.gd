extends CanvasLayer
var world_game_node: Node

var player_editing_index: int = -1

func init_gui(gameNode: Node):
	world_game_node = gameNode
	init_button_signals()
	init_menu_graphics()

func init_button_signals():
	$ActionsMenu/EditPlayer/VBoxContainer/HBoxContainer/Cancelar.connect("pressed", self, "gui_close_edit_player")
	$ActionsMenu/EditPlayer/VBoxContainer/HBoxContainer/Aceptar.connect("pressed", self, "gui_accept_edit_player")
	$ActionsMenu/WaitingPlayers/VBoxContainer/HBoxContainer/AddBot.connect("pressed", world_game_node, "gui_add_bot")
	$ActionsMenu/WaitingPlayers/VBoxContainer/PlayersList.connect("item_selected", world_game_node, "gui_player_selected")
	$ActionsMenu/InGameMenu/VBoxContainer/GuardarPartida.connect("pressed", self, "gui_save_game")
	$ActionsMenu/WaitingPlayers/VBoxContainer/HBoxContainer/LoadGame.connect("pressed", self, "gui_load_game")
	$ActionsMenu/WaitingPlayers/VBoxContainer/HBoxContainer/StartGame.connect("pressed", self, "gui_start_online_game")
	$ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.connect("item_selected", world_game_node, "update_build_menu_price")
	$ActionsMenu/InGameTileActions/VBoxContainer/Editar.connect("pressed", self, "gui_open_edit_tile_window")
	$ActionsMenu/InGameTileActions/VBoxContainer/Reclutar.connect("pressed", self, "gui_recruit_troops")
	$ActionsMenu/EditTile/VBoxContainer/HBoxContainer/Aceptar.connect("pressed", self, "gui_change_tile_name")
	$ActionsMenu/EditTile/VBoxContainer/HBoxContainer/Cancelar.connect("pressed", self, "gui_close_edit_tile_window")
	$ActionsMenu/BuildingsMenu/VBoxContainer/Comprar.connect("pressed", self, "gui_buy_building")
	$ActionsMenu/BuildingsMenu/VBoxContainer/Cancelar.connect("pressed", self, "gui_exit_build_window")
	$ActionsMenu/InGameMenu/VBoxContainer/Cancelar.connect("pressed", self, "gui_exit_ingame_menu_window")
	$ActionsMenu/InGameMenu/VBoxContainer/Deshacer.connect("pressed", self, "gui_undo_actions")
	$ActionsMenu/InGameTileActions/VBoxContainer/Construir.connect("pressed", self, "gui_open_build_window")
	$ActionsMenu/InGameTileActions/VBoxContainer/VenderTile.connect("pressed", self, "gui_vender_tile")
	$ActionsMenu/InGameTileActions/VBoxContainer/UrbanizarTile.connect("pressed", world_game_node, "gui_urbanizar_tile")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer2/TalentosAMover.connect("text_changed", world_game_node, "gold_to_move_text_changed")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TropasAMover.connect("text_changed", world_game_node, "troops_to_move_text_changed")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer4/TiposTropas.connect("item_selected", world_game_node, "update_troops_move_data")
	$HUD/GameInfo/HBoxContainer3/FinishTurn.connect("pressed", self, "btn_finish_turn")
	$ActionsMenu/ExtrasMenu/VBoxContainer/Cancelar.connect("pressed", self, "hide_extras_menu")
	$ActionsMenu/ExtrasMenu/VBoxContainer/ObtenerTalentos.connect("pressed", self, "give_extra_gold")
	$ActionsMenu/ExtrasMenu/VBoxContainer/ObtenerTropas.connect("pressed", self, "add_extra_troops")
	$ActionsMenu/InGameTileActions/VBoxContainer/Cancelar.connect("pressed", self, "hide_ingame_actions")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer/Cancelar.connect("pressed", self, "hide_tiles_actions")
	$ActionsMenu/TilesActions/VBoxContainer/HBoxContainer/Aceptar.connect("pressed", self, "accept_tiles_actions")
	$ActionsMenu/InGameMenu/VBoxContainer/Salir.connect("pressed", self, "gui_show_confirmation_window")
	$ActionsMenu/ConfirmationExit/VBoxContainer/HBoxContainer/ConfirmExit.connect("pressed", world_game_node, "exit_game")
	$ActionsMenu/ConfirmationExit/VBoxContainer/HBoxContainer/Cancel.connect("pressed", self, "gui_leave_confirmation_menu")
func init_menu_graphics():
	close_all_windows()
	init_tile_coordinates()
	$GameFinished.visible = false
	$ActionsMenu.visible = true
	$HUD.visible = true
	$ActionsMenu/EditPlayer/VBoxContainer/DifficultyPanel/BotDifficulty.clear()
	for i in range(Game.bot_difficulties_stats.size()):
		$ActionsMenu/EditPlayer/VBoxContainer/DifficultyPanel/BotDifficulty.add_item(Game.bot_difficulties_stats[i].NAME, i)
	$HUD/GameInfo/Waiting.visible = false
	$TilesCoordinates.visible = false

func init_tile_coordinates():
	var dynamic_font = DynamicFont.new()
	dynamic_font.font_data = load("res://assets/fonts/PixelOperatorMono8-Bold.ttf")
	dynamic_font.size = 20
	dynamic_font.outline_size = 3
	dynamic_font.outline_color = Color( 0, 0, 0, 0.75 )
	dynamic_font.use_filter = true
	
	var transform_to_apply: Dictionary = world_game_node.get_tiles_node_transformation()
	#print(transform_to_apply)
	for obj in $TilesCoordinates.get_children(): #removing old labels just in case
		if obj.is_in_group("label_coords"):
			$TilesCoordinates.remove_child(obj)
			obj.remove_from_group("label_coords")
			obj.queue_free()
		
	#var 
	var game_coods: Dictionary = Game.tilesObj.get_all_tile_coords()
	for x in range(game_coods.coords_size.x):
		for y in range(game_coods.coords_size.y):
			var vboxconteiner: VBoxContainer = VBoxContainer.new()
			var position_to_use: Vector2 = Vector2(x*Game.TILE_SIZE*transform_to_apply.scale.x, y*Game.TILE_SIZE*transform_to_apply.scale.y)
			position_to_use+=transform_to_apply.position
			vboxconteiner.rect_position = position_to_use
			vboxconteiner.rect_size = Vector2(Game.TILE_SIZE*transform_to_apply.scale.x, Game.TILE_SIZE*transform_to_apply.scale.y)
			vboxconteiner.alignment = BoxContainer.ALIGN_CENTER
			var label: Label = Label.new()
			label.text = game_coods.coords[x][y]
			label.align = Label.ALIGN_CENTER
			label.add_font_override("font", dynamic_font)
			vboxconteiner.add_child(label)
			vboxconteiner.add_to_group("label_coords")
			$TilesCoordinates.add_child(vboxconteiner)

###################################
#	BUTTONS & SIGNALS
###################################
func close_all_windows() -> void:
	$ActionsMenu/InGameTileActions.visible = false
	$ActionsMenu/ExtrasMenu.visible = false
	$ActionsMenu/TilesActions.visible = false
	$ActionsMenu/BuildingsMenu.visible = false
	$ActionsMenu/InGameMenu.visible = false
	$ActionsMenu/EditTile.visible = false
	$ActionsMenu/WaitingPlayers.visible = false
	$ActionsMenu/EditPlayer.visible = false
	$ActionsMenu/ConfirmationExit.visible = false
	$TilesCoordinates.visible = false

func gui_leave_confirmation_menu():
	if !world_game_node.can_interact_with_menu():
		return
	close_all_windows()
	$ActionsMenu/InGameMenu.visible = true

func gui_show_confirmation_window():
	if !world_game_node.can_interact_with_menu():
		return
	close_all_windows()
	$ActionsMenu/ConfirmationExit.visible = true

func show_game_coords() -> void:
	$TilesCoordinates.visible = true
	$ActionsMenu.visible = false
	$HUD.visible = false

func hide_game_coords() -> void:
	$TilesCoordinates.visible = false
	$ActionsMenu.visible = true
	$HUD.visible = true

func gui_open_edit_player(var player_index: int) -> void:
	close_all_windows()
	if Game.Network.is_client():
		return
	player_editing_index = player_index
	$ActionsMenu/EditPlayer/VBoxContainer/HBoxContainer2/PlayerNameText.text = str(Game.playersData[player_index].name)
	$ActionsMenu/EditPlayer/VBoxContainer/HBoxContainer3/PlayerTeamText.text = str(Game.playersData[player_index].team)
	
	if Game.playersData[player_index].isBot:
		$ActionsMenu/EditPlayer/VBoxContainer/DifficultyPanel.visible = true
		$ActionsMenu/EditPlayer/VBoxContainer/DifficultyPanel/BotDifficulty.select(Game.playersData[player_index].bot_stats.difficulty)
	else:
		$ActionsMenu/EditPlayer/VBoxContainer/DifficultyPanel.visible = false
	
	$ActionsMenu/EditPlayer.visible = true


func gui_accept_edit_player() -> void:
	if Game.Network.is_client():
		gui_close_edit_player()
		return
	Game.playersData[player_editing_index].team = int($ActionsMenu/EditPlayer/VBoxContainer/HBoxContainer3/PlayerTeamText.text)
	if Game.playersData[player_editing_index].isBot:
		var difficulty_index: int = $ActionsMenu/EditPlayer/VBoxContainer/DifficultyPanel/BotDifficulty.selected
		Game.playersData[player_editing_index].bot_stats.difficulty = difficulty_index
		var difficulty_name: String = Game.bot_difficulties_stats[difficulty_index].NAME
		Game.playersData[player_editing_index].name = "bot [" + difficulty_name + "]"
	gui_close_edit_player()

func gui_close_edit_player() -> void:
	close_all_windows()
	player_editing_index = -1
	$ActionsMenu/WaitingPlayers.visible = true

func gui_open_edit_tile_window() -> void:
	if !world_game_node.can_interact_with_menu():
		return
	close_all_windows()
	$ActionsMenu/EditTile/VBoxContainer/HBoxContainer2/NombreTextEdit.text = str(Game.tilesObj.get_name(Game.current_tile_selected))
	$ActionsMenu/EditTile.visible = true

func gui_load_game() -> void:
	assert(!Game.Network.is_multiplayer() or Game.Network.is_server())
	world_game_node.load_game_from("partida.json")

func gui_save_game() -> void:
	assert(!Game.Network.is_multiplayer() or Game.Network.is_server())
	world_game_node.save_game_as("partida.json")
	close_all_windows()

func gui_start_online_game() -> void:
	close_all_windows()
	world_game_node.start_online_game()

func update_lobby_info() -> void:
	$ActionsMenu/WaitingPlayers/VBoxContainer/LobbyText.text = "Players:\n"
	$ActionsMenu/WaitingPlayers/VBoxContainer/PlayersList.clear()
	
	for i in range(Game.playersData.size()):
		if !Game.playersData[i].alive:
			continue
		$ActionsMenu/WaitingPlayers/VBoxContainer/PlayersList.add_item(str(i) + ": " + Game.playersData[i].name + " [ " + str(Game.playersData[i].team) + "]")

func gui_close_edit_tile_window() -> void:
	close_all_windows()

func gui_change_tile_name() -> void:
	gui_close_edit_tile_window()
	world_game_node.change_tile_name(Game.current_tile_selected, $ActionsMenu/EditTile/VBoxContainer/HBoxContainer2/NombreTextEdit.text)
	

func gui_undo_actions() -> void:
	world_game_node.undo_actions()
	gui_exit_ingame_menu_window()
	

func show_wait_for_player() -> void:
	$HUD/GameInfo/Waiting.visible = true
	$HUD/GameInfo/HBoxContainer3/FinishTurn.visible = false

func hide_wait_for_player() -> void:
	$HUD/GameInfo/Waiting.visible = false
	$HUD/GameInfo/HBoxContainer3/FinishTurn.visible = true

func is_a_menu_open() -> bool:
	return $ActionsMenu/ConfirmationExit.visible or $ActionsMenu/EditTile.visible or $ActionsMenu/ExtrasMenu.visible or $ActionsMenu/InGameTileActions.visible or $ActionsMenu/TilesActions.visible or $ActionsMenu/BuildingsMenu.visible or $ActionsMenu/InGameMenu.visible

func gui_recruit_troops():
	if !world_game_node.can_interact_with_menu():
		return
	world_game_node.execute_recruit_troops()
	$ActionsMenu/InGameTileActions.visible = false
	
func gui_buy_building():
	if !world_game_node.can_interact_with_menu():
		return
	var selectionIndex: int = $ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.selected
	var selectedBuildTypeId: int = int($ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.get_item_id(selectionIndex))
	if selectedBuildTypeId< 0:
		return
	world_game_node.execute_buy_building(selectedBuildTypeId)
	$ActionsMenu/BuildingsMenu.visible = false

func gui_exit_build_window():
	close_all_windows()
	$ActionsMenu/InGameTileActions.visible = true

func gui_exit_ingame_menu_window():
	close_all_windows()

func gui_open_ingame_menu_window(is_local_player: bool):
	close_all_windows()
	if Game.Network.is_client():
		$ActionsMenu/InGameMenu/VBoxContainer/GuardarPartida.visible = false
	else:
		$ActionsMenu/InGameMenu/VBoxContainer/GuardarPartida.visible = true
	if !is_local_player:
		$ActionsMenu/InGameMenu/VBoxContainer/Deshacer.visible = false
	else:
		$ActionsMenu/InGameMenu/VBoxContainer/Deshacer.visible = true
	$ActionsMenu/InGameMenu.visible = true

func open_lobby_window():
	$ActionsMenu/WaitingPlayers.visible = true
	if Game.Network.is_client():
		$ActionsMenu/WaitingPlayers/VBoxContainer/HBoxContainer.visible = false
	else:
		$ActionsMenu/WaitingPlayers/VBoxContainer/HBoxContainer.visible = true

func gui_open_build_window():
	if !world_game_node.can_interact_with_menu():
		return
	close_all_windows()
	$ActionsMenu/BuildingsMenu.visible = true
	world_game_node.execute_open_build_window()

func hide_tiles_actions():
	if !world_game_node.can_interact_with_menu():
		return
	close_all_windows()

func accept_tiles_actions():
	if !world_game_node.can_interact_with_menu():
		return
	world_game_node.execute_accept_tiles_actions()
	$ActionsMenu/TilesActions.visible = false

func hide_ingame_actions():
	if !world_game_node.can_interact_with_menu():
		return
	$ActionsMenu/InGameTileActions.visible = false
	
func hide_extras_menu():
	if !world_game_node.can_interact_with_menu():
		return
	$ActionsMenu/ExtrasMenu.visible = false

func btn_finish_turn():
	world_game_node.execute_btn_finish_turn()

func give_extra_gold():
	if !world_game_node.can_interact_with_menu():
		return
	$ActionsMenu/ExtrasMenu.visible = false
	world_game_node.execute_give_extra_gold()

func add_extra_troops():
	if !world_game_node.can_interact_with_menu():
		return
	$ActionsMenu/ExtrasMenu.visible = false
	world_game_node.execute_add_extra_troops()

func update_server_info():
	$HUD/ServerInfo/HBoxContainer/PlayerCountText.text = str(Game.get_player_count())

func gui_update_civilization_info() -> void:
	
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer() or Game.is_current_player_a_bot():
		player_mask = Game.get_local_player_number()
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer5/CivilizationText.text = str(Game.playersData[player_mask].civilizationName)
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer/TotTalentosText.text = str(stepify(Game.tilesObj.get_total_gold(player_mask), 0.1))
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer2/StrengthText.text = str(Game.tilesObj.get_total_strength(player_mask))
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer6/GainText.text = str(stepify(Game.tilesObj.get_total_gold_gain_and_losses(player_mask), 0.1))
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer7/WarCostsText.text = str(stepify(Game.tilesObj.get_all_war_costs(player_mask), 0.1)) 
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer8/TravelCostsText.text = str(stepify(Game.tilesObj.get_all_travel_costs(player_mask), 0.1)) 

	var civilizationTroopsInfo: Array = Game.tilesObj.get_civ_population_info(player_mask)
	var populationStr: String = ""
	
	for troopDict in civilizationTroopsInfo:
		populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer4/TotPopulationText.text = populationStr


func gui_update_tile_info(tile_pos: Vector2) -> void:
	
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer() or Game.is_current_player_a_bot():
		player_mask = Game.get_local_player_number()
	var cell_data: Dictionary = Game.tilesObj.get_cell(tile_pos)
	if Game.current_game_status == Game.STATUS.PRE_GAME:
		$HUD/GameInfo/HBoxContainer2/TurnText.text = "PRE-GAME: " + str(Game.playersData[Game.current_player_turn].civilizationName)
	elif Game.current_game_status == Game.STATUS.GAME_STARTED:
		$HUD/GameInfo/HBoxContainer2/TurnText.text = str(Game.playersData[Game.current_player_turn].civilizationName)
	else:
		$HUD/GameInfo/HBoxContainer2/TurnText.text = "??"

	if !allow_show_tile_info(tile_pos, player_mask):
		$HUD/TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = "No info"
		$HUD/TileInfo/VBoxContainer/HBoxContainer2/Amount.text = "No info"
		$HUD/TileInfo/VBoxContainer/HBoxContainer6/StrengthText.text = "No info"
		$HUD/TileInfo/VBoxContainer/HBoxContainer7/GainsText.text = "No info"
		$HUD/TileInfo/VBoxContainer/HBoxContainer4/PopulationText.text = "No info"
		return
	
	$HUD/TileInfo/VBoxContainer/HBoxContainer5/TileName.text = cell_data.name
	if cell_data.owner == -1:
		$HUD/TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = "No info"
	else:
		$HUD/TileInfo/VBoxContainer/HBoxContainer/OwnerName.text = str(Game.playersData[cell_data.owner].civilizationName)
	$HUD/TileInfo/VBoxContainer/HBoxContainer2/Amount.text = str(floor(cell_data.gold))
	
	$HUD/TileInfo/VBoxContainer/HBoxContainer6/StrengthText.text = str(Game.tilesObj.get_strength(tile_pos, player_mask))
	$HUD/TileInfo/VBoxContainer/HBoxContainer7/GainsText.text = str(stepify(Game.tilesObj.get_cell_gold_gain_and_losses(tile_pos, player_mask), 0.1))
	
	var populationStr: String = ""
	var isEnemyPopulation: bool = false
	var isAllyPopulation: bool = false
	var troops_array: Array = Game.tilesObj.get_troops(tile_pos)
	for troopDict in troops_array:
		if troopDict.amount <= 0:
			continue
		if troopDict.owner == player_mask:
			populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
		elif Game.are_player_allies(troopDict.owner, player_mask):
			isAllyPopulation = true
		else:
			isEnemyPopulation = true
	if isEnemyPopulation:
		populationStr += "Enemigos: \n"
		for troopDict in troops_array:
			if troopDict.amount <= 0 or troopDict.owner == player_mask or Game.are_player_allies(troopDict.owner, player_mask):
				continue
			populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	if isAllyPopulation:
		populationStr += "Aliados: \n"
		for troopDict in troops_array:
			if troopDict.amount <= 0 or troopDict.owner == player_mask or !Game.are_player_allies(troopDict.owner, player_mask):
				continue
			populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"

	$HUD/TileInfo/VBoxContainer/HBoxContainer4/PopulationText.text = populationStr

func allow_show_tile_info(tile_pos: Vector2, playerNumber: int) -> bool:
	if Game.DEBUG_MODE:
		return true
	var tile_cell_data: Dictionary = Game.tilesObj.get_cell(tile_pos)
	if tile_cell_data.owner == playerNumber:
		return true
	if Game.tilesObj.is_next_to_player_territory(tile_pos, playerNumber):
		return true
	if Game.tilesObj.belongs_to_allies(tile_pos, playerNumber):
		return true
	if Game.tilesObj.is_next_to_allies_territory_with_own_troops(tile_pos, playerNumber):
		return true
	return Game.tilesObj.has_troops_or_citizen(tile_pos, playerNumber)

func open_finish_game_screen(game_duration: float) -> void:
	close_all_windows()
	$GameFinished.visible = true
	$GameFinished/CenterContainer/HBoxContainer/DurationText.text = str(int(round(game_duration))) + " minutos"
