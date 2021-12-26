class_name NetworkBase
extends Node

const SNAPSHOT_DELAY = 1.0/10.0 #Msec to Sec (20hz)
const MAX_PLAYERS:int = 4
const SERVER_PORT:int = 27666
const SERVER_NETID: int = 1
const BOT_NETID: int = -666
var clients_connected: Array
var player_count: int = 1
const MAX_CLIENT_LATENCY: float = 0.4 #350ms
const MAX_MESSAGE_PING_BUFFER: int = 8 #Average from ammount
const NODENUM_NULL = -1

var pings: Array;
var client_latency: float = 0.0
var ping_counter = 0.0
var local_player_id = 0 # 0 = Server
var netentities: Array

# Netcode optimization: START (TODO in future, by now I just leave these vars and const)
const SV_MAX_SNAPSHOTS: int = 24 #How many snapshots at max to send at once each time using SNAPSHOT_DELAY
const SV_MAX_EVENTS: int = 16 #How many events at max to send at once
var snapshot_list: Array #elements: Dictionary { net_entity = null, queue_pos = 0}
var saved_event_list: Array #elements: Dictionary { net_id = -1, queue_pos = 0}
# Netcode optimiaztion: END

#DEBUG ONLY
var boops_sent_at_once: int = 0
#END DEBUG ONLY

var net_name: String = ""
var net_pin: int = 0

func ready():
	clear()
	Game.get_tree().connect("network_peer_connected", self, "_on_player_connected")
	Game.get_tree().connect("network_peer_disconnected", self, "_on_player_disconnect")
	Game.get_tree().connect("connected_to_server", self, "_on_player_joined_ok")
	Game.get_tree().connect("server_disconnected", self, "_on_server_shutdown")
	Game.get_tree().connect("connection_failed", self, "_on_connected_fail")
	
	var timer = Timer.new()
	timer.set_wait_time(SNAPSHOT_DELAY)
	timer.set_one_shot(false)
	timer.connect("timeout", self, "write_boop")
	Game.add_child(timer)
	timer.start()

func clear():
	netentities.clear()
	clients_connected.clear()
	player_count = 0
	local_player_id = 0
	saved_event_list.clear()
	for _i in range(MAX_PLAYERS):
		netentities.append(null)

func _on_connected_fail():
	print("Failed to join")

func _on_server_shutdown():
	print("Server shutdown")
	stop_networking()

func _on_player_joined_ok():
	print("player connected")
	if !Game.is_network_master():
		Game.rpc_id(SERVER_NETID, "game_process_rpc", "server_process_client_question", [Game.get_tree().get_network_unique_id(), net_name, net_pin])

func _on_player_connected(id):
	print("player connected...")
	if is_server():
		if Game.current_game_status == Game.STATUS.LOBBY_WAIT:
			var client_index:int = add_client(id)
			var player_number: int = Game.add_player(id, "client", 666)
			clients_connected[client_index].player_num = player_number

func _on_player_disconnect(id):
	print("player disconnected...")
	if is_server():
		var player_number: int = find_player_number_by_netid(id)
		clients_connected.remove(find_client_number_by_netid(id))
		player_count-=1
		if Game.current_game_status == Game.STATUS.LOBBY_WAIT:
			Game.remove_net_player(id)
		else: #make it a bot or something else until other human player join
			Game.playersData[player_number].netid = -1 #reset netid to let know server this player is not connected anymore

func add_client(netid: int, num: int = -1) -> int:
	print("Adding client with at position %d with netid %d" % [clients_connected.size(), netid])
	clients_connected.append({netId = netid, player_num = num, ingame = false})
	player_count+=1
	return player_count-1

#only true when client finally loaded the map
func client_is_ingame(clientNum: int) -> bool:
	return clients_connected[clientNum].ingame

func clients_in_server() -> int:
	return clients_connected.size()

func find_client_number_by_netid(netid: int):
	for i in range(clients_connected.size()):
		if clients_connected[i].netId == netid:
			return i
	return -1

func find_player_number_by_netid(netid: int):
	for i in range(Game.playersData.size()):
		if Game.playersData[i].netid == netid:
			return i
	return -1

func server_process_client_reconnect(id_client: int):
	var player_num: int = find_player_number_by_netid(id_client)
	Game.emit_signal("player_reconnects", id_client, player_num)

func server_process_client_question(id_client: int, client_name: String, client_pin: int):
	var player_num: int
	if Game.current_game_status == Game.STATUS.LOBBY_WAIT:
		player_num = find_player_number_by_netid(id_client)
	else:
		player_num = Game.get_player_number_by_pin_code(client_pin)
		if player_num == -1 or Game.playersData[player_num].netid != -1: #not allowed to join!, this player still in-game!
			Game.rpc_id(id_client, "game_process_rpc", "client_kicked", [{player_number = player_num}])
			return
		#succed
		

	Game.playersData[player_num].name = client_name
	Game.playersData[player_num].pin_code = client_pin
	Game.playersData[player_num].netid = id_client
	print("Update player %s (%d) with netid %d" % [client_name, player_num, id_client])
	send_rpc("new_client_connected", [clients_connected])
	Game.rpc_id(id_client, "game_process_rpc", "client_receive_answer", [{player_number = player_num, game_mod = Game.current_mod, game_status = Game.current_game_status}])

func client_kicked(receive_data: Dictionary):
	net_disconnect()
	Game.emit_signal("error_joining_server", "Not allowed to join server...")

func client_receive_answer(receive_data: Dictionary):
	print("player number: %d, uniqueid: %d" % [receive_data.player_number, Game.get_tree().get_network_unique_id()])
	local_player_id = receive_data.player_number
	if !Game.switch_to_mod(receive_data.game_mod): #client does not have the mod!
		print("[ERROR] Client does not have the mod server is using!")
		net_disconnect()
		Game.emit_signal("error_joining_server", "Server is using a mod that you don't not have...")
	else:
		Game.add_player(Game.get_tree().get_network_unique_id(), net_name, net_pin, receive_data.player_number)
		Game.start_new_game(true)
		if receive_data.game_status != Game.STATUS.LOBBY_WAIT: #connected in-game
			Game.rpc_id(SERVER_NETID, "game_process_rpc", "server_process_client_reconnect", [Game.get_tree().get_network_unique_id()])
			
func new_client_connected(new_clients_list: Array):
	clients_connected.clear()
	clients_connected = new_clients_list

func clear_players():
	var is_server: bool = false;
	for info in clients_connected:
		info.ingame = false
		if info.netId == 1:
			is_server = true
	if !is_server:
		clients_connected.append({netId = 1, ingame = false})

func client_send_ping():
	ping_counter = 0.0;
	Game.rpc_unreliable_id(SERVER_NETID, "server_receive_ping", Game.get_tree().get_network_unique_id())

remote func server_receive_ping(id_client):
	Game.rpc_unreliable_id(id_client, "client_receive_ping")

remote func client_receive_ping():
	pings.append(ping_counter)
	if pings.size() >= MAX_MESSAGE_PING_BUFFER:
		pings.pop_front()
	ping_counter = 0.0
	var sum_pings: float = 0.0
	for ping in pings:
		sum_pings+=ping
	client_latency = sum_pings / float(pings.size())

func net_disconnect() -> void:
	Game.get_tree().set_network_peer(null) #Destoy any previous networking session

func host_server(maxPlayers: int, client_name: String, client_pin: int, serverPort: int = SERVER_PORT):
	Game.get_tree().set_network_peer(null) #Destoy any previous networking session
	var host = NetworkedMultiplayerENet.new()
	print(host.create_server(serverPort, maxPlayers))
	Game.clear_players_data()
	net_name = client_name
	net_pin = client_pin
	Game.get_tree().set_network_peer(host)
	add_client(SERVER_NETID); #adding server as friend client always
	Game.add_player(SERVER_NETID, client_name, client_pin)
	Game.start_new_game(true)
	print("Hosting server...")

func join_server(ip: String, client_name: String, client_pin: int):
	Game.clear_players_data()
	net_name = client_name
	net_pin = client_pin
	ip = ip.replace(" ", "")
	Game.get_tree().set_network_peer(null) #Destoy any previous networking session
	var host = NetworkedMultiplayerENet.new()
	print(host.create_client(ip, SERVER_PORT))
	Game.get_tree().set_network_peer(host)
	#Game.start_new_game(true)
	print("Joining to server...")

func stop_networking() -> void:
	Game.get_tree().call_deferred("set_network_peer", null)
	clear()

#################
# UTIL METHODS  #
#################

func is_multiplayer() -> bool:
	return Game.get_tree().has_network_peer()
	
func is_client() -> bool:
	if !Game.get_tree().has_network_peer() || Game.get_tree().is_network_server():
		return false
	return true
	
func is_server() -> bool:
	if Game.get_tree().has_network_peer() && !Game.get_tree().is_network_server():
		return false
	return true
	
func is_local_player(player_id: int) -> bool:
	if Game.get_tree().has_network_peer() && player_id != local_player_id:
		return false
	return true

##################
# NETWORK BOOPS  #
##################
func write_boop() -> void:
	if !Game.get_tree().has_network_peer():
		return

	if Game.get_tree().is_network_server():
		server_send_boop()
	else:
		client_send_boop()

func server_send_boop() -> void:
	if player_count <= 0:
		return
	boops_sent_at_once = 0
	for entity in netentities:
		if server_entity_send_boop(entity):
			boops_sent_at_once+=1

func server_entity_send_boop(entity) -> bool:
	var boop_was_sent: bool = false #DEBUG ONLY, DELETE LATER
	if entity && entity.has_method("server_send_boop") && entity.is_inside_tree():
		var boopData: Dictionary = entity.server_send_boop()
		if !boopData or boopData.empty():
			return false
		#This loop it's to have unique boop deltas for each client, to avoid bad syncing
		for client in clients_connected:
			if !client:
				continue
			if client.netId == SERVER_NETID: #to avoid sending a boop to oneself as server
				continue
			var clientNum: int = find_client_number_by_netid(client.netId)
			if entity.NetBoop.delta_boop_changed(boopData, clientNum):
				send_rpc_unreliable_id(client.netId, "client_process_boop", [entity.node_id, boopData])
				boop_was_sent = true
	return boop_was_sent

func client_send_boop() -> void:
	for entity in netentities:
		client_entity_send_boop(entity)

func client_entity_send_boop(entity) -> void:
	if entity && entity.has_method("client_send_boop") && entity.is_inside_tree():
		var boopData: Dictionary = entity.client_send_boop()
		if !boopData or boopData.empty():
			return
		if entity.NetBoop.delta_boop_changed(boopData):
			send_rpc_unreliable_id(SERVER_NETID, "server_process_boop", [entity.node_id, boopData])

func client_process_boop(entityId, message) -> void:
	if entityId < netentities.size() && netentities[entityId] && netentities[entityId].is_inside_tree():
		if netentities[entityId].has_method("client_process_boop"):
			netentities[entityId].client_process_boop(message)

func server_process_boop(entityId, message) -> void:
	if entityId < netentities.size() && netentities[entityId] && netentities[entityId].is_inside_tree():
		if netentities[entityId].has_method("server_process_boop"):
			netentities[entityId].server_process_boop(message)

##################
# NETWORK EVENTS #
##################

func save_event_to_list(entityId, eventId, eventData, unreliable) -> void:
	saved_event_list.append({evEntId = entityId, evId = eventId, evData = eventData, evUnreliable = unreliable})

func net_send_event(entityId, eventId, eventData=null, unreliable = false) -> void:
	if !is_multiplayer():
		return
	if is_client():
		client_send_event(entityId, eventId, eventData, unreliable)
	else:
		server_send_event(entityId, eventId, eventData, unreliable)
		
func client_send_event(entityId, eventId, eventData=null, unreliable = false) -> void:
	#print("client sending event...")
	var eventTime: int = OS.get_ticks_msec()
	if is_client():
		if unreliable: # When it is not vital to the event to reach the server (not recommended unless necessary)
			send_rpc_unreliable_id(SERVER_NETID, "server_process_event", [entityId, eventId, eventTime, eventData])
		else:
			send_rpc_id(SERVER_NETID, "server_process_event", [entityId, eventId, eventTime, eventData])

func server_send_event(entityId, eventId, eventData=null, unreliable = false, saveEvent = false) -> void:
	#print("server sending event...")
	var eventTime: int = OS.get_ticks_msec()
	if is_server():
		if saveEvent:
			save_event_to_list(entityId, eventId, eventData, unreliable)
		if unreliable: # When it is not vital to the event to reach the server (not recommended unless necessary)
			send_rpc_unreliable("client_process_event", [entityId, eventId, eventTime, eventData])
		else:
			send_rpc("client_process_event", [entityId, eventId, eventTime, eventData])

func server_send_event_id(clientId, entityId, eventId, eventData=null, unreliable = false, saveEvent = false) -> void:
	#print("server sending event...")
	var eventTime: int = OS.get_ticks_msec()
	if is_server():
		if saveEvent:
			save_event_to_list(entityId, eventId, eventData, unreliable)
		if unreliable: # When it is not vital to the event to reach the server (not recommended unless necessary)
			send_rpc_unreliable_id(clientId, "client_process_event", [entityId, eventId, eventTime, eventData])
		else:
			send_rpc_id(clientId, "client_process_event", [entityId, eventId, eventTime, eventData])

func server_process_event(entityId, eventId, eventTime, eventData) -> void:
	if !is_server():
		return
	if entityId < netentities.size() && netentities[entityId] && netentities[entityId].is_inside_tree():
		if netentities[entityId].has_method("server_process_event"):
			netentities[entityId].NetBoop.update_event_data({event_id = eventId, event_time = eventTime, event_data = eventData})
			netentities[entityId].server_process_event(eventId, netentities[entityId].NetBoop.get_event_data(eventId))
			
func client_process_event(entityId, eventId, eventTime, eventData) -> void:
	if !is_client():
		return
	if entityId < netentities.size() && netentities[entityId] && netentities[entityId].is_inside_tree():
		if netentities[entityId].has_method("client_process_event"):
			netentities[entityId].NetBoop.update_event_data({event_id = eventId, event_time = eventTime, event_data = eventData})
			netentities[entityId].client_process_event(eventId, netentities[entityId].NetBoop.get_event_data(eventId))

#######################
# NETWORK RPC METHODS #
#######################

func send_rpc_id(id: int, method_name: String, args: Array) -> void:
	if !is_multiplayer():
		print("[Warning] trying to call send_rpc_id during singleplayer")
		return
	Game.callv("rpc_id", [id, "game_process_rpc", method_name, args])

func send_rpc_unreliable_id(id: int, method_name: String, args: Array) -> void:
	if !is_multiplayer():
		print("[Warning] trying to call send_rpc_unreliable_id during singleplayer")
		return;
	Game.callv("rpc_unreliable_id", [id, "game_process_rpc", method_name, args])
	
func send_rpc(method_name: String, args: Array) -> void:
	if !is_multiplayer():
		print("[Warning] trying to call send_rpc during singleplayer")
		return
	Game.callv("rpc", ["game_process_rpc", method_name, args])

func send_rpc_unreliable(method_name: String, args: Array) -> void:
	if !is_multiplayer():
		print("[Warning] trying to call rpc_unreliable during singleplayer")
		return
	Game.callv("rpc_unreliable", ["game_process_rpc", method_name, args])

######################
# NET NODES HANDLING #
######################

func register_synced_node(nodeEntity: Node, forceId = NODENUM_NULL ) -> void:
	if !is_multiplayer():
		return
	var freeIndex = MAX_PLAYERS
	if forceId >= 0:
		freeIndex = forceId
		print("Forcing id: " + str(freeIndex))
	else:
		while freeIndex < netentities.size() and netentities[freeIndex]:
			freeIndex+=1

	while freeIndex >= netentities.size(): #dinamic netenities array
		netentities.append(null)

	nodeEntity.node_id = freeIndex
	netentities[nodeEntity.node_id] = nodeEntity
	print("Registering entity [ID " + str(freeIndex) + "] : " + nodeEntity.get_class())

func unregister_synced_node(nodeEntity: Node):
	if !is_multiplayer():
		return
	if nodeEntity.node_id >= netentities.size() or nodeEntity.node_id < 0:
		return
	print("Unregistering entity [ID " + str(nodeEntity.node_id) + "] : " + nodeEntity.get_class())
	netentities[nodeEntity.node_id] = null
