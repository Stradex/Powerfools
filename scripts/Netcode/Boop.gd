extends Object

var default_event_data: Dictionary = {
	event_id = -1,
	event_time = -1,
	event_data = {}
}

var current_boop: Array
var father_node: Node2D
var lastEventData: Array

func _init(node: Node2D):
	father_node = node;
	lastEventData.resize(Game.Network.MAX_PLAYERS)
	current_boop.resize(Game.Network.MAX_PLAYERS)
	for _i in range(Game.Network.MAX_PLAYERS):
		current_boop.append({}) #empty dictionary
		lastEventData.append([])

func update_event_data(event_data: Dictionary, client_num: int = 0):
	if !lastEventData[client_num]:
		lastEventData[client_num] = []
	for i in range(lastEventData[client_num].size()):
		if typeof(lastEventData[client_num][i]) != TYPE_DICTIONARY or !lastEventData[client_num][i].has('event_id') or !lastEventData[client_num][i].has('event_time'):
			lastEventData[client_num][i] = event_data.duplicate(true)
		if lastEventData[client_num][i].event_id == event_data.event_id and lastEventData[client_num][i].event_time <= event_data.event_time:
			lastEventData[client_num][i].clear()
			lastEventData[client_num][i] = event_data.duplicate(true)
	lastEventData[client_num].append(event_data.duplicate(true))

func get_event_data(event_id: int, client_num: int = 0):
	for i in range(lastEventData[client_num].size()):
		if typeof(lastEventData[client_num][i]) != TYPE_DICTIONARY or !lastEventData[client_num][i].has('event_id') or !lastEventData[client_num][i].has('event_time'):
			continue
		if lastEventData[client_num][i].event_id == event_id:
			if lastEventData[client_num][i].has('event_data') and typeof(lastEventData[client_num][i].event_data) == TYPE_DICTIONARY:
				return lastEventData[client_num][i].event_data.duplicate(true)
			else: #Null case
				return lastEventData[client_num][i].event_data
	print("[FATAL ERROR] get_event_data can't find event data")
	return {} #ERROR

func boops_are_equal(boopA: Dictionary, boopB: Dictionary) -> bool:
	for key in boopA:
		if !boopB.has(key) or boopB[key] != boopA[key]:
			return false;
	for key in boopB:
		if !boopA.has(key) or boopB[key] != boopA[key]:
			return false;
	return true; #they are totally equal

#Clients don't need to check for all clients for delta since they only send boops to server, so they always should use 0
func delta_boop_changed(new_boop: Dictionary, client_num: int = 0) -> bool:
	var retResult: bool = !current_boop[client_num] or new_boop.empty() or !boops_are_equal(new_boop, current_boop[client_num]);
	current_boop[client_num] = new_boop;
	return retResult;
