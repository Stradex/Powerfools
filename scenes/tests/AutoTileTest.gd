extends Node2D


onready var auto_tile_img: int = $AutoTileTest.tile_set.find_tile_by_name('autotile1')
#onready var auto_tile_overlay: int = $AutoTileTestOverlay.tile_set.find_tile_by_name('autotile1_overlay')

# Called when the node enters the scene tree for the first time.
func _ready():
	create_overlay_tile()
	var overlay_tile_id: int = $AutoTileTestOverlay.tile_set.find_tile_by_name($AutoTileTestOverlay.tile_set.tile_get_name(auto_tile_img) + '_overlay')
	var tile_size: Vector2 = Vector2(64, 64)
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if $AutoTileTest.get_cellv(Vector2(x, y)) == -1:
				$AutoTileTestOverlay.set_cellv(Vector2(x, y), -1)
			else:
				$AutoTileTestOverlay.set_cellv(Vector2(x, y), overlay_tile_id)

	$AutoTileTest.update_bitmask_region()
	$AutoTileTestOverlay.update_bitmask_region()

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func create_overlay_tile() -> void:
	var tiles_count: int = $AutoTileTest.tile_set.get_tiles_ids().size()
	$AutoTileTest.tile_set.create_tile(tiles_count)
	$AutoTileTest.tile_set.tile_set_texture(tiles_count, $AutoTileTest.tile_set.tile_get_texture(auto_tile_img))
	$AutoTileTest.tile_set.tile_set_name(tiles_count, $AutoTileTest.tile_set.tile_get_name(auto_tile_img) + "_overlay")
	var overlay_tile_id: int = $AutoTileTest.tile_set.find_tile_by_name($AutoTileTest.tile_set.tile_get_name(auto_tile_img) + '_overlay')
	Game.TileSetImporter.copy_autotile_from_to($AutoTileTest.tile_set, auto_tile_img, $AutoTileTest.tile_set, overlay_tile_id, Vector2(0, -1))
	$AutoTileTestOverlay.tile_set = $AutoTileTest.tile_set
