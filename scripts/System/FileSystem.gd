class_name FileSystemBase
extends Object

func save_as_json(var path : String, var data_to_save):
	var file = File.new()
	file.open(path, File.WRITE)
	file.store_var(data_to_save)
	file.close()

func load_as_dict (var path : String) -> Dictionary:
	var file = File.new()
	file.open(path, File.READ)
	var theDict = file.get_var()
	file.close()
	return theDict

func list_directories(path) -> Array:
	var directories: Array = []
	var dir = Directory.new()
	# Not working in export, I need to fix the problem in engine or wait for update.
	# if !dir.dir_exists(path):
	# 	return [];
	dir.open(path)
	dir.list_dir_begin()
	while true:
		var directory = dir.get_next()
		if directory == "":
			break
		if !directory.begins_with(".") and dir.current_is_dir():
			directories.append(directory)
	dir.list_dir_end()
	return directories
	
func list_files_in_directory(path, extension: String = "") -> Array:
	var files: Array = []
	var dir = Directory.new()
	# Not working in export, I need to fix the problem in engine or wait for update.
	# if !dir.dir_exists(path):
	# 	return [];
	dir.open(path)
	dir.list_dir_begin()
	while true:
		var file = dir.get_next()
		if file == "":
			break
		elif !file.begins_with(".") && (extension.length() <= 1 || file.ends_with(extension)):
			files.append(file)
	dir.list_dir_end()

	return files

func file_exists(filename: String) -> bool:
	var file: File = File.new()
	return file.file_exists(filename)

func get_data_from_json(filename: String) -> Dictionary:
	var file: File = File.new()
	assert(file.file_exists(filename), ("¡The file %s doesn't exists!" % filename))
	file.open(filename, File.READ) #Assumes the file exists
	var text = file.get_as_text()
	var data = parse_json(serialize_for_json(text))
	file.close()
	return data

func serialize_for_json(jsonstr: String) -> String:
	var stringSerialized: String = ""
	var ignore: bool = false
	var str_length: int = jsonstr.length()
	for i in range(0, str_length):
		if jsonstr[i] == "\n":
			ignore = false
		elif i < (str_length-1) && jsonstr[i] == '/' && jsonstr[i+1] == "/":
			ignore = true
		if !ignore:
			stringSerialized+=jsonstr[i]
	return stringSerialized
