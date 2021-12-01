extends CanvasLayer

onready var BTN_NewGame : TextureButton = $Buttons/NewGame
onready var BTN_Options : TextureButton = $Buttons/Options
onready var BTN_ExitGame : TextureButton = $Buttons/ExitGame

func _ready():
	BTN_NewGame.connect("pressed", self, "ui_start_sp_game")
	BTN_Options.connect("pressed", self, "ui_open_options")
	BTN_ExitGame.connect("pressed", self, "ui_exit_game")

func ui_start_sp_game():
	Game.start_new_game()

func ui_exit_game():
	get_tree().quit()

func ui_open_options():
	pass
