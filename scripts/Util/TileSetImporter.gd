class_name TileSetExternalImporter
extends Object

var file_system: FileSystemBase
var auto_tile_res

func _init(init_file_system):
	file_system = init_file_system
	auto_tile_res = load('res://tilesResources/AutoTile1.tres')

#Returnes a whole tileset from a folder with images
func load_external_tex(path: String) -> ImageTexture:
	var tex_file = File.new()
	tex_file.open(path, File.READ)
	var bytes = tex_file.get_buffer(tex_file.get_len())
	var img = Image.new()
	var data = img.load_png_from_buffer(bytes)
	var imgtex = ImageTexture.new()
	imgtex.create_from_image(img)
	tex_file.close()
	return imgtex

func create_overlay_tile(tile_from: TileSet, tile_id: int) -> void:
	var new_tile_id: int = tile_id+1
	tile_from.create_tile(new_tile_id)
	print(tile_from.tile_get_name(tile_id) + "_overlay")
	tile_from.tile_set_name(new_tile_id, tile_from.tile_get_name(tile_id) + "_overlay")
	copy_autotile_from_to(tile_from, tile_id, tile_from, new_tile_id, Vector2(0, -1))


func copy_autotile_from_to(tile_from: TileSet, tile_id_from: int, tile_to: TileSet, tile_id_to: int, bitmask_subtile_offset = Vector2(0, 0)) -> void:
	var tile_region: Rect2 = tile_from.tile_get_region(tile_id_from)
	var auto_tile_size: Vector2 = tile_from.autotile_get_size(tile_id_from)
	var region_offset: Vector2 = Vector2(bitmask_subtile_offset.x*auto_tile_size.x, bitmask_subtile_offset.y*auto_tile_size.y)
	var subtiles_size: Vector2 = Vector2(round(tile_region.end.x/auto_tile_size.x), round(tile_region.end.y/auto_tile_size.y))
	tile_region.position += region_offset
	tile_region.end += region_offset
	tile_to.tile_set_light_occluder(tile_id_to, tile_from.tile_get_light_occluder(tile_id_from))
	tile_to.tile_set_material(tile_id_to, tile_from.tile_get_material(tile_id_from))
	tile_to.tile_set_modulate(tile_id_to, tile_from.tile_get_modulate(tile_id_from))
	tile_to.tile_set_navigation_polygon(tile_id_to, tile_from.tile_get_navigation_polygon(tile_id_from))
	tile_to.tile_set_navigation_polygon_offset(tile_id_to, tile_from.tile_get_navigation_polygon_offset(tile_id_from))
	tile_to.tile_set_normal_map(tile_id_to, tile_from.tile_get_normal_map(tile_id_from))
	tile_to.tile_set_occluder_offset(tile_id_to, tile_from.tile_get_occluder_offset(tile_id_from))
	tile_to.tile_set_region(tile_id_to, tile_region)
	tile_to.tile_set_shapes(tile_id_to, tile_from.tile_get_shapes(tile_id_from).duplicate(true))
	tile_to.tile_set_texture(tile_id_to, tile_from.tile_get_texture(tile_id_from))
	tile_to.tile_set_texture_offset(tile_id_to, tile_from.tile_get_texture_offset(tile_id_from))
	tile_to.tile_set_tile_mode(tile_id_to, tile_from.tile_get_tile_mode(tile_id_from))
	tile_to.tile_set_z_index(tile_id_to, tile_from.tile_get_z_index(tile_id_from))
	tile_to.autotile_clear_bitmask_map(tile_id_to)
	tile_to.autotile_set_size(tile_id_to, tile_from.autotile_get_size(tile_id_from))
	tile_to.autotile_set_bitmask_mode(tile_id_to, tile_from.autotile_get_bitmask_mode(tile_id_from))
	tile_to.autotile_set_icon_coordinate(tile_id_to, tile_from.autotile_get_icon_coordinate(tile_id_from))
	tile_to.autotile_set_spacing(tile_id_to, tile_from.autotile_get_spacing(tile_id_from))
	for x in range(subtiles_size.x):
		for y in range(subtiles_size.y):
			tile_to.autotile_set_bitmask(tile_id_to, Vector2(x, y),  tile_from.autotile_get_bitmask(tile_id_from, Vector2(x,y)))
			tile_to.autotile_set_light_occluder(tile_id_to, tile_from.autotile_get_light_occluder(tile_id_from, Vector2(x, y)), Vector2(x, y))
			tile_to.autotile_set_navigation_polygon(tile_id_to, tile_from.autotile_get_navigation_polygon(tile_id_from, Vector2(x, y)), Vector2(x, y))
			tile_to.autotile_set_subtile_priority(tile_id_to, Vector2(x, y), tile_from.autotile_get_subtile_priority(tile_id_from, Vector2(x, y)))
			tile_to.autotile_set_z_index(tile_id_to, Vector2(x, y), tile_from.autotile_get_z_index(tile_id_from, Vector2(x, y)))

func append_to_tileset_from_folder(folder_path: String, tile_set: TileSet) -> void:
	var png_images_in_folder: Array = file_system.list_files_in_directory(folder_path, ".png")
	var tiles_count: int = tile_set.get_tiles_ids().size()
	for i in range(png_images_in_folder.size()):
		var tile_name_str: String = png_images_in_folder[i].get_basename()
		if tile_set.find_tile_by_name(tile_name_str) != -1: #already exists, do nothing avoid duplicates.
			continue
		var path_img: String = folder_path + "/" + png_images_in_folder[i]
		tile_set.create_tile(tiles_count)
		tile_set.tile_set_texture(tiles_count, load_external_tex(path_img))
		tile_set.tile_set_name(tiles_count, tile_name_str)
		tiles_count+=1
		
func make_tileset_from_folder(folder_path: String) -> TileSet:
	var new_tile_set: TileSet = TileSet.new()
	var png_images_in_folder: Array = file_system.list_files_in_directory(folder_path, ".png")
	
	var tiles_count: int = 0
	var is_auto_tile: bool = false
	for i in range(png_images_in_folder.size()):
		var tile_name_str: String = png_images_in_folder[i].get_basename()
		var path_img: String = folder_path + "/" + png_images_in_folder[i]
		new_tile_set.create_tile(tiles_count)
		is_auto_tile = tile_name_str.to_lower().find("_auto1_") == 0
		if is_auto_tile: #starts with _auto1_
			copy_autotile_from_to(auto_tile_res, auto_tile_res.find_tile_by_name('autotile1'), new_tile_set, tiles_count)
		new_tile_set.tile_set_texture(tiles_count, load_external_tex(path_img))
		new_tile_set.tile_set_name(tiles_count, tile_name_str)
		if is_auto_tile: #starts with _auto1_
			create_overlay_tile(new_tile_set, tiles_count)
			tiles_count+=1
		tiles_count+=1
	return new_tile_set
