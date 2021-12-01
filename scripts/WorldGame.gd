extends Node2D

onready var id_tile_non_selected: int = $SelectionTiles.tile_set.find_tile_by_name('off')
onready var id_tile_selected: int = $SelectionTiles.tile_set.find_tile_by_name('tile_hover')

var enemies_grid: CuteGrid = CuteGrid.new(32, Vector2(Game.SCREEN_WIDTH, Game.SCREEN_HEIGHT));
var rng: RandomNumberGenerator = RandomNumberGenerator.new();

func _ready():
	pass # Replace with function body.

func _process(delta):
	update_selection_tiles()

func update_selection_tiles():

	var mouse_pos: Vector2 = get_global_mouse_position()
	var tile_selected: Vector2 = $SelectionTiles.world_to_map(mouse_pos)
	var tile_map_size: Vector2 = Vector2(round(Game.SCREEN_WIDTH/Game.TILE_SIZE), round(Game.SCREEN_HEIGHT/Game.TILE_SIZE))
	for x in range(tile_map_size.x):
		for y in range(tile_map_size.y):
			if Vector2(x, y) == tile_selected:
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_selected)
			else:
				$SelectionTiles.set_cellv(Vector2(x, y), id_tile_non_selected)
