extends CanvasLayer

onready var BTN_NewGame : TextureButton = $Buttons/NewGame
onready var BTN_Multiplayer : TextureButton = $Buttons/Multiplayer
onready var BTN_ExitGame : TextureButton = $Buttons/ExitGame
onready var BTN_JoinGame : TextureButton = $MultiplayerMenu/JoinServer
onready var BTN_HostGame : TextureButton = $MultiplayerMenu/HostServer
onready var BTN_GoToMenu : TextureButton = $MultiplayerMenu/GoBack
onready var BTN_StartOnlineGame: TextureButton = $PlayerSettingsMenu/Start
onready var BTN_CancelOnlineGame: TextureButton = $PlayerSettingsMenu/Cancel

var ip_to_join: String = "127.0.0.1"
var joining_server: bool = false

func _ready():
	BTN_NewGame.connect("pressed", self, "ui_start_sp_game")
	BTN_Multiplayer.connect("pressed", self, "ui_open_multiplayer_window")
	BTN_ExitGame.connect("pressed", self, "ui_exit_game")
	BTN_JoinGame.connect("pressed", self, "ui_join_game")
	BTN_HostGame.connect("pressed", self , "ui_host_game")
	BTN_GoToMenu.connect("pressed", self , "ui_go_to_menu")
	BTN_StartOnlineGame.connect("pressed", self, "ui_start_online_game")
	BTN_CancelOnlineGame.connect("pressed", self, "ui_cancel_online_game")
	ui_go_to_menu()

func ui_start_sp_game():
	Game.start_new_game()

func ui_exit_game():
	get_tree().quit()

func ui_go_to_menu():
	$MultiplayerMenu.visible = false
	$PlayerSettingsMenu.visible = false
	$Buttons.visible = true

func ui_open_multiplayer_window():
	$MultiplayerMenu.visible = true
	$Buttons.visible = false

func ui_join_game():
	joining_server = true
	ip_to_join = $MultiplayerMenu/IPTextBox.text
	$PlayerSettingsMenu.visible = true
	$MultiplayerMenu.visible = false

func ui_host_game():
	joining_server = false
	$PlayerSettingsMenu.visible = true
	$MultiplayerMenu.visible = false

func ui_cancel_online_game():
	joining_server = false
	$PlayerSettingsMenu.visible = false
	$MultiplayerMenu.visible = true

func ui_start_online_game():
	var player_name_str: String = $PlayerSettingsMenu/PlayerNameTextBox.text
	var player_pin: int = int($PlayerSettingsMenu/PlayerPinTextBox.text)
	if joining_server:
		Game.Network.join_server(ip_to_join, player_name_str, player_pin)
	else:
		Game.Network.host_server(2, player_name_str, player_pin)
