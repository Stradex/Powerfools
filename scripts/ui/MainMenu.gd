extends CanvasLayer

onready var BTN_NewGame : TextureButton = $Buttons/NewGame
onready var BTN_Multiplayer : TextureButton = $Buttons/Multiplayer
onready var BTN_ExitGame : TextureButton = $Buttons/ExitGame
onready var BTN_JoinGame : TextureButton = $MultiplayerMenu/JoinServer
onready var BTN_HostGame : TextureButton = $MultiplayerMenu/HostServer
onready var BTN_GoToMenu : TextureButton = $MultiplayerMenu/GoBack

func _ready():
	BTN_NewGame.connect("pressed", self, "ui_start_sp_game")
	BTN_Multiplayer.connect("pressed", self, "ui_open_multiplayer_window")
	BTN_ExitGame.connect("pressed", self, "ui_exit_game")
	BTN_JoinGame.connect("pressed", self, "ui_join_game")
	BTN_HostGame.connect("pressed", self , "ui_host_game")
	BTN_GoToMenu.connect("pressed", self , "ui_go_to_menu")
	ui_go_to_menu()

func ui_start_sp_game():
	Game.start_new_game()

func ui_exit_game():
	get_tree().quit()

func ui_go_to_menu():
	$MultiplayerMenu.visible = false
	$Buttons.visible = true

func ui_open_multiplayer_window():
	$MultiplayerMenu.visible = true
	$Buttons.visible = false

func ui_join_game():
	pass

func ui_host_game():
	pass
