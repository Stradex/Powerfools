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
onready var FullScreenCheckBox: CheckBox = $Options/HBoxContainer/FullScreen

var ip_to_join: String = "127.0.0.1"

func _ready():
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
	update_resolution_list()
	ui_go_to_menu()

func update_resolution_list() -> void:
	ResolutionOptions.clear()
	for res in resolutions:
		ResolutionOptions.add_item(res)
	ResolutionOptions.select(0)
	
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

func ui_go_to_menu():
	$MultiplayerMenu.visible = false
	$PlayerSettingsMenu.visible = false
	$Buttons.visible = true
	$Options.visible = false

func ui_open_multiplayer_window():
	$MultiplayerMenu.visible = true
	$Buttons.visible = false

func ui_join_game():
	ip_to_join = $MultiplayerMenu/IPTextBox.text
	var player_name: String = Game.Config.get_value("name")
	var player_pin: int = int(Game.Config.get_value("pin_code"))
	Game.Network.join_server(ip_to_join, player_name, player_pin)

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
