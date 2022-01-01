extends Node2D


onready var auto_tile_img: int = $AutoTileTest.tile_set.find_tile_by_name('autotile1')
onready var auto_tile_overlay: int = $AutoTileTestOverlay.tile_set.find_tile_by_name('autotile1_overlay')

# Called when the node enters the scene tree for the first time.
func _ready():
	var tile_size: Vector2 = Vector2(64, 64)
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if $AutoTileTest.get_cellv(Vector2(x, y)) == -1:
				$AutoTileTestOverlay.set_cellv(Vector2(x, y), -1)
			else:
				$AutoTileTestOverlay.set_cellv(Vector2(x, y), auto_tile_overlay)

	$AutoTileTest.update_bitmask_region();
	$AutoTileTestOverlay.update_bitmask_region();
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
