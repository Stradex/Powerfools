extends Node

const VERSION: String = "0.1.1" #Major, Minor, build count
const PORT: int = 27666
const MAX_PLAYERS: int = 4
const SNAPSHOT_DELAY: float = 1.0/30.0 #msec to sec

const MAPS_FOLDER: String = "res://scenes/"
const START_MAP: String = "WorldGame.tscn"

const SCREEN_WIDTH: int = 1280
const SCREEN_HEIGHT: int = 720
const TILE_SIZE: int = 80

func start_new_game():
	change_to_map(START_MAP);

remote func change_to_map(map_name: String):
	var full_map_path: String = self.MAPS_FOLDER + map_name;
	get_tree().call_deferred("change_scene", full_map_path);

func pause() -> void:
	get_tree().paused = true
	
func unpause() -> void:
	get_tree().paused = false

func is_singleplayer_game():
	return !get_tree().has_network_peer()

func is_network_master_or_sp(caller: Node):
	return is_singleplayer_game() or caller.is_network_master()

func is_client() -> bool:
	return get_tree().has_network_peer() and !get_tree().is_network_server()

func is_client_connected() -> bool:
	if !get_tree().has_network_peer() or get_tree().is_network_server():
		return false
	return get_tree().get_network_peer().get_connection_status() == get_tree().get_network_peer().CONNECTION_CONNECTED
