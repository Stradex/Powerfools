extends CanvasLayer
var world_game_node: Node

func init_gui(gameNode: Node):
	world_game_node = gameNode
	init_button_signals()
	init_menu_graphics()

func init_button_signals():
	$ActionsMenu/InGameTileActions/VBoxContainer/Reclutar.connect("pressed", self, "gui_recruit_troops")
	$ActionsMenu/BuildingsMenu/VBoxContainer/Comprar.connect("pressed", self, "gui_buy_building")
	$ActionsMenu/BuildingsMenu/VBoxContainer/Cancelar.connect("pressed", self, "gui_exit_build_window")
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
	$ActionsMenu/InGameTileActions.visible = false
	$ActionsMenu/ExtrasMenu.visible = false
	$ActionsMenu/TilesActions.visible = false
	$ActionsMenu/BuildingsMenu.visible = false


###################################
#	BUTTONS & SIGNALS
###################################

func is_a_menu_open() -> bool:
	return $ActionsMenu/ExtrasMenu.visible or $ActionsMenu/InGameTileActions.visible or $ActionsMenu/TilesActions.visible or $ActionsMenu/BuildingsMenu.visible

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
	$ActionsMenu/ExtrasMenu.visible = true
	$ActionsMenu/BuildingsMenu.visible = false

func gui_open_build_window():
	$ActionsMenu/BuildingsMenu.visible = true
	$ActionsMenu/ExtrasMenu.visible = false
	$ActionsMenu/InGameTileActions.visible = false
	$ActionsMenu/TilesActions.visible = false
	world_game_node.execute_open_build_window()

func hide_tiles_actions():
	if !world_game_node.can_interact_with_menu():
		return
	$ActionsMenu/TilesActions.visible = false

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
