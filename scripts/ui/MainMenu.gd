extends CanvasLayer

var resolutions: Array = [
	"640x360",
	"960x540",
	"1280x720",
	"1600x900",
	"1920x1080",
	"2240x1260",
	"2560x1440"
]

var ui_mods_list: Array = []

onready var ModsList: OptionButton = $ModsTab/ModsList
onready var BTN_ModsCancel: TextureButton = $ModsTab/Back
onready var BTN_ModsApply: TextureButton = $ModsTab/Apply
onready var ResolutionOptions : OptionButton = $Options/Resolution
onready var BTN_NewGame : TextureButton = $Buttons/NewGame
onready var BTN_Multiplayer : TextureButton = $Buttons/Multiplayer
onready var BTN_ExitGame : TextureButton = $Buttons/ExitGame
onready var BTN_JoinGame : TextureButton = $MultiplayerMenu/JoinServer
onready var BTN_HostGame : TextureButton = $MultiplayerMenu/HostServer
onready var BTN_GoToMenu : TextureButton = $MultiplayerMenu/GoBack
onready var BTN_ApplyPlayerSettings: TextureButton = $PlayerSettingsMenu/ApplyChanges
onready var BTN_CancelPlayerSettings: TextureButton = $PlayerSettingsMenu/Cancel
onready var BTN_PlayerSettings: TextureButton = $MultiplayerMenu/PlayerOptions
onready var BTN_BackToMenu: TextureButton = $Options/Back
onready var BTN_Options: TextureButton = $Buttons/Options
onready var BTN_ApplyOptions: TextureButton = $Options/Apply
onready var BTN_Mods: TextureButton = $Buttons/Mods
onready var FullScreenCheckBox: CheckBox = $Options/HBoxContainer/FullScreen
onready var BTN_CancelJoin: TextureButton = $JoiningServer/CancelJoin
onready var BTN_AcceptJoinFailed: TextureButton = $ErrorJoining/HBoxContainer/OK
onready var BTN_Reconnect: TextureButton = $ErrorJoining/HBoxContainer/Reconnect

func _ready():
	var cfg_ip_cached: String = Game.Config.get_value("ip_default")
	if cfg_ip_cached.length() > 1:
		Game.cache_ip_to_connect = cfg_ip_cached
	BTN_NewGame.connect("pressed", self, "ui_start_sp_game")
	BTN_Multiplayer.connect("pressed", self, "ui_open_multiplayer_window")
	BTN_ExitGame.connect("pressed", self, "ui_exit_game")
	BTN_JoinGame.connect("pressed", self, "ui_join_game")
	BTN_HostGame.connect("pressed", self , "ui_host_game")
	BTN_GoToMenu.connect("pressed", self , "ui_go_to_menu")
	BTN_BackToMenu.connect("pressed", self, "ui_go_to_menu")
	BTN_ApplyPlayerSettings.connect("pressed", self, "ui_apply_player_settings")
	BTN_CancelPlayerSettings.connect("pressed", self, "ui_close_player_settings")
	BTN_PlayerSettings.connect("pressed", self, "ui_open_player_settings")
	BTN_Options.connect("pressed", self, "ui_open_options")
	BTN_ApplyOptions.connect("pressed", self, "ui_apply_options")
	BTN_Mods.connect("pressed", self, "ui_open_mods_tab")
	BTN_ModsCancel.connect("pressed", self, "ui_go_to_menu")
	BTN_ModsApply.connect("pressed", self, "ui_change_mod")
	BTN_CancelJoin.connect("pressed", self, "ui_cancel_join")
	BTN_AcceptJoinFailed.connect("pressed", self, "ui_cancel_join")
	BTN_Reconnect.connect("pressed", self, "ui_reconnect")
	Game.connect("error_joining_server", self, "ui_failed_to_join")
	ui_mods_list.clear()
	update_resolution_list()
	ui_go_to_menu()
	if Game.error_message_to_show.length() > 1:
		ui_failed_to_join(Game.error_message_to_show)
		Game.error_message_to_show = ""

func update_resolution_list() -> void:
	ResolutionOptions.clear()
	for res in resolutions:
		ResolutionOptions.add_item(res)
	ResolutionOptions.select(0)

func ui_cancel_join() -> void:
	$MultiplayerMenu.visible = true
	$ErrorJoining.visible = false
	$JoiningServer.visible = false

func get_string_from_resoltion(res_vec: Vector2) -> String:
	return (str(int(res_vec.x)) + "x" + str(int(res_vec.y)));

func get_resolution_from_string(res_str: String) -> Vector2:
	var str_array: PoolStringArray = res_str.split("x");
	return Vector2(int(str_array[0]),int(str_array[1]));
	
func ui_start_sp_game():
	Game.start_new_game()

func ui_exit_game():
	get_tree().quit()

func ui_open_options():
	
	FullScreenCheckBox.pressed = Game.Config.get_value("fullscreen");
	var resolutionStr: String = get_string_from_resoltion(Game.Config.get_value("resolution"));
	for i in range(resolutions.size()):
		if resolutionStr == resolutions[i]:
			ResolutionOptions.selected = i
			break
			
	$MultiplayerMenu.visible = false
	$PlayerSettingsMenu.visible = false
	$Buttons.visible = false
	$Options.visible = true

func close_all_menus():
	$MultiplayerMenu.visible = false
	$PlayerSettingsMenu.visible = false
	$Buttons.visible = false
	$Options.visible = false
	$ModsTab.visible = false
	$JoiningServer.visible = false
	$ErrorJoining.visible = false

func ui_go_to_menu():
	$MultiplayerMenu.visible = false
	$PlayerSettingsMenu.visible = false
	$Buttons.visible = true
	$Options.visible = false
	$ModsTab.visible = false
	$JoiningServer.visible = false
	$ErrorJoining.visible = false

func ui_change_mod() -> void:
	Game.switch_to_mod(ui_mods_list[ModsList.selected])
	ui_go_to_menu()

func ui_open_mods_tab():
	ModsList.clear()
	ui_mods_list.clear()
	var mods_list: Array = Game.get_mods_list()
	var select_index: int = 0
	for i in range(mods_list.size()):
		ui_mods_list.append(mods_list[i])
		ModsList.add_item(mods_list[i])
		if Game.current_mod.to_lower() == mods_list[i].to_lower():
			select_index = i
	ModsList.select(select_index)
	$ModsTab.visible = true
	$Buttons.visible = false
	
func ui_open_multiplayer_window():
	$MultiplayerMenu/IPTextBox.text = Game.cache_ip_to_connect
	$MultiplayerMenu.visible = true
	$Buttons.visible = false

func ui_join_game():
	Game.cache_ip_to_connect = $MultiplayerMenu/IPTextBox.text
	var player_name: String = Game.Config.get_value("name")
	var player_pin: int = int(Game.Config.get_value("pin_code"))
	Game.Network.join_server(Game.cache_ip_to_connect, player_name, player_pin)
	$MultiplayerMenu.visible = false
	$JoiningServer.visible = true

func ui_reconnect():
	var player_name: String = Game.Config.get_value("name")
	var player_pin: int = int(Game.Config.get_value("pin_code"))
	Game.Network.join_server(Game.cache_ip_to_connect, player_name, player_pin)
	close_all_menus()
	$JoiningServer.visible = true

func ui_host_game():
	var player_name: String = Game.Config.get_value("name")
	var player_pin: int = int(Game.Config.get_value("pin_code"))
	Game.Network.host_server(Game.MAX_PLAYERS, player_name, player_pin)

func ui_start_online_game():
	var player_name_str: String = $PlayerSettingsMenu/PlayerNameTextBox.text
	var player_pin: int = int($PlayerSettingsMenu/PlayerPinTextBox.text)

func ui_open_player_settings():
	$PlayerSettingsMenu/PlayerNameTextBox.text = Game.Config.get_value("name")
	$PlayerSettingsMenu/PlayerPinTextBox.text = str(Game.Config.get_value("pin_code"))
	$PlayerSettingsMenu.visible = true
	$MultiplayerMenu.visible = false

func ui_apply_player_settings():
	Game.Config.set_value("name", $PlayerSettingsMenu/PlayerNameTextBox.text)
	Game.Config.set_value("pin_code", int($PlayerSettingsMenu/PlayerPinTextBox.text))
	Game.save_settings()
	ui_close_player_settings()

func ui_close_player_settings():
	$PlayerSettingsMenu.visible = false
	$MultiplayerMenu.visible = true

func ui_apply_options():
	Game.Config.set_value("fullscreen", FullScreenCheckBox.pressed);
	Game.Config.set_value("resolution", get_resolution_from_string(resolutions[ResolutionOptions.selected]));
	Game.save_settings()
	ui_go_to_menu()
	Game.update_settings()

func ui_failed_to_join(error_msg: String) -> void:
	close_all_menus()
	$ErrorJoining/ErrorLabel.text = error_msg
	$ErrorJoining.visible = true
