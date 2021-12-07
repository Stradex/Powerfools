extends Object

var current_boop: Array;
var father_node: Node2D;

func _init(node: Node2D):
	father_node = node;
	current_boop.resize(Game.Network.MAX_PLAYERS);
	for _i in range(Game.Network.MAX_PLAYERS):
		current_boop.append({}); #empty dictionary

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
