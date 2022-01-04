class_name NewTileMap
extends TileMap

var old_tile_data: Array = []
var tile_size: Vector2 = Vector2(0, 0)

func init_tile_data_array(new_tile_size: Vector2):
	tile_size = new_tile_size
	for x in range(tile_size.x):
		old_tile_data.append([])
		for y in range(tile_size.y):
			old_tile_data[x].append(-1)

func update_tile_data_array() -> void:
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			old_tile_data[x][y] = self.get_cellv(Vector2(x, y))

func set_cellv_optimized(pos: Vector2, new_value: int) -> void:
	if old_tile_data[pos.x][pos.y] == new_value:
		return #no need to updated, NOTHING changed!
	set_cellv(pos, new_value)#only now update.

func check_if_tile_has_changed() -> bool:
	for x in range(tile_size.x):
		for y in range(tile_size.y):
			if (old_tile_data[x][y] != self.get_cellv(Vector2(x, y))):
				return true
	return false
