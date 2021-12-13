extends CanvasLayer
var world_game_node: Node

func init_gui(gameNode: Node):
	world_game_node = gameNode
	init_button_signals()
	init_menu_graphics()

func init_button_signals():
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

func init_menu_graphics():
	close_all_windows()
	$HUD/GameInfo/Waiting.visible = false

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
	for i in range(Game.playersData.size()):
		if !Game.playersData[i].alive:
			continue
		$ActionsMenu/WaitingPlayers/VBoxContainer/LobbyText.text += "\t" + Game.playersData[i].name + "\n"

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
	return $ActionsMenu/EditTile.visible or $ActionsMenu/ExtrasMenu.visible or $ActionsMenu/InGameTileActions.visible or $ActionsMenu/TilesActions.visible or $ActionsMenu/BuildingsMenu.visible or $ActionsMenu/InGameMenu.visible

func gui_recruit_troops():
	world_game_node.execute_recruit_troops()
	$ActionsMenu/InGameTileActions.visible = false
	
func gui_buy_building():
	var selectionIndex: int = $ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.selected
	var selectedBuildTypeId: int = int($ActionsMenu/BuildingsMenu/VBoxContainer/BuildingsList.get_item_id(selectionIndex))
	if selectedBuildTypeId< 0:
		return
	world_game_node.execute_buy_building(selectedBuildTypeId)
	$ActionsMenu/BuildingsMenu.visible = false

func gui_exit_build_window():
	close_all_windows()
	$ActionsMenu/ExtrasMenu.visible = true

func gui_exit_ingame_menu_window():
	close_all_windows()

func gui_open_ingame_menu_window():
	close_all_windows()
	if Game.Network.is_client():
		$ActionsMenu/InGameMenu/VBoxContainer/GuardarPartida.visible = false
	else:
		$ActionsMenu/InGameMenu/VBoxContainer/GuardarPartida.visible = true
	$ActionsMenu/InGameMenu.visible = true

func open_lobby_window():
	$ActionsMenu/WaitingPlayers.visible = true
	if Game.Network.is_client():
		$ActionsMenu/WaitingPlayers/VBoxContainer/HBoxContainer.visible = false
	else:
		$ActionsMenu/WaitingPlayers/VBoxContainer/HBoxContainer.visible = true

func gui_open_build_window():
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
	if Game.Network.is_multiplayer():
		player_mask = Game.get_local_player_number()

	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer5/CivilizationText.text = str(Game.playersData[player_mask].civilizationName)
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer/TotTalentosText.text = str(stepify(Game.tilesObj.get_total_gold(player_mask), 0.1))
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer2/StrengthText.text = str(Game.tilesObj.get_total_strength(player_mask))
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer6/GainText.text = str(stepify(Game.tilesObj.get_total_gold_gain_and_losses(player_mask), 0.1))
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer7/WarCostsText.text = str(stepify(Game.tilesObj.get_all_war_costs(player_mask), 0.1))

	var civilizationTroopsInfo: Array = Game.tilesObj.get_civ_population_info(player_mask)
	var populationStr: String = ""
	
	for troopDict in civilizationTroopsInfo:
		populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	
	$HUD/CivilizationInfo/VBoxContainer/HBoxContainer4/TotPopulationText.text = populationStr


func gui_update_tile_info(tile_pos: Vector2) -> void:
	
	var player_mask: int = Game.current_player_turn
	if Game.Network.is_multiplayer():
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
	var troops_array: Array = Game.tilesObj.get_troops(tile_pos)
	for troopDict in troops_array:
		if troopDict.amount <= 0:
			continue
		if troopDict.owner == player_mask:
			populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
		else:
			isEnemyPopulation = true
	if isEnemyPopulation:
		populationStr += "Enemigos: \n"
		for troopDict in troops_array:
			if troopDict.amount <= 0 or troopDict.owner == player_mask: 
				continue
			populationStr += "* " + str(Game.troopTypes.getName(troopDict.troop_id)) + ": " + str(troopDict.amount) + "\n"
	$HUD/TileInfo/VBoxContainer/HBoxContainer4/PopulationText.text = populationStr

func allow_show_tile_info(tile_pos: Vector2, playerNumber: int) -> bool:
	var tile_cell_data: Dictionary = Game.tilesObj.get_cell(tile_pos)
	if tile_cell_data.owner == playerNumber:
		return true
	if Game.tilesObj.is_next_to_player_territory(tile_pos, playerNumber):
		return true
	return Game.tilesObj.has_troops_or_citizen(tile_pos, playerNumber)
