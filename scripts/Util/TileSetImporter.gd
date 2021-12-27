class_name TileSetExternalImporter
extends Object

var file_system: FileSystemBase

func _init(init_file_system):
	file_system = init_file_system

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

	for i in range(png_images_in_folder.size()):
		var path_img: String = folder_path + "/" + png_images_in_folder[i]
		new_tile_set.create_tile(i)
		new_tile_set.tile_set_texture(i, load_external_tex(path_img))
		new_tile_set.tile_set_name(i, png_images_in_folder[i].get_basename())

	return new_tile_set