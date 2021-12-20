class_name BotObject
extends Object

const BOT_MIN_WARRIORS_TO_MOVE: int = 250
const BOT_SECS_TO_EXEC_ACTION: float = 1.0 #seconds for a bot to execute each action (not turn but every single action)
const BOT_MAX_TURNS_FOR_PLAN: int = 3 #bot can be using same plan as maximum as 3 turns, to avoid bots getting stuck with old plans
const BOT_MINIMUM_GOLD_TO_USE: float = 10.0
const BOT_MINIMUM_WARRIORS_AT_CAPITAL: int = 2000
const BOT_TURNS_TO_RESET_STATS: int = 15
const BOT_MIMINUM_GOLD_GAINS_DESIRED: float = 1.0
var bot_territories_to_recover: Array = [] #list with all of he territories a bot lost

enum BOT_ACTIONS {
	DEFENSIVE,
	OFFENSIVE,
	GREEDY
}
var game_node = null

var rng: RandomNumberGenerator

func _init(tmp_game_node, tmp_rng):
	rng = tmp_rng
	game_node = tmp_game_node
	for i in range(bot_territories_to_recover.size()):
		bot_territories_to_recover[i].clear()
	bot_territories_to_recover.clear()
	bot_territories_to_recover.resize(Game.MAX_PLAYERS)
	for i in range(bot_territories_to_recover.size()):
		bot_territories_to_recover[i] = [] #array

func execute_action(game_status: int, player_turn: int):
	if !Game.is_current_player_a_bot():
		return
	match game_status:
		Game.STATUS.PRE_GAME:
			bot_process_pre_game(player_turn)
		Game.STATUS.GAME_STARTED:
			bot_process_game(player_turn)

func bot_try_desperate_action(bot_number: int, bot_is_having_debt: bool) -> bool: #in case of desperate situation
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	
	if Game.tilesObj.is_cell_in_battle(player_capital_pos):
		return false
	
	var amount_of_territories: int = Game.tilesObj.get_amount_of_player_tiles(bot_number)
	var amount_of_buildings: int = Game.tilesObj.get_count_of_all_buildings_player_have(bot_number)
	var bot_total_gold: float = Game.tilesObj.get_total_gold(bot_number)
	var enemies_next_to_capital: Array = Game.tilesObj.ai_get_neighbor_player_enemies(player_capital_pos, bot_number)
	var bot_available_gold_to_use: float = bot_total_gold
	if bot_is_having_debt:
		bot_available_gold_to_use += Game.tilesObj.get_total_gold_gain_and_losses(bot_number)

	if enemies_next_to_capital.size() <= 0:
		return false
	if bot_available_gold_to_use > BOT_MINIMUM_GOLD_TO_USE and !bot_is_having_debt:
		return false
	if amount_of_buildings >= 2:
		return false
	if amount_of_territories >= 4 and !bot_is_having_debt:
		return false
	
	var strongest_enemy_cell: Vector2 = Game.tilesObj.ai_get_strongest_enemy_cell_in_array(enemies_next_to_capital, bot_number)
	#print("[BOT] Trying desperate defense")
	return Game.tilesObj.ai_move_warriors_from_to(player_capital_pos, strongest_enemy_cell, bot_number, 1.0, true)

func bot_is_lacking_troops(bot_number: int, type_of_attitude: int) -> bool:
	var amount_of_territories: int = Game.tilesObj.get_amount_of_player_tiles(bot_number)
	var amount_of_warriors: int = Game.tilesObj.get_all_warriors_count(bot_number)
	match type_of_attitude:
		BOT_ACTIONS.OFFENSIVE:
			return amount_of_warriors <= amount_of_territories*500 #Minimum 500 trops per territory
		BOT_ACTIONS.DEFENSIVE:
			return amount_of_warriors <= amount_of_territories*1000 #Minimum 1000 trops per territory
		BOT_ACTIONS.GREEDY:
			return amount_of_warriors <= amount_of_territories*500 #Minimum 500 trops per territory
	
	return false

func bot_needs_to_upgrade_unproductive_territories(bot_number: int, type_of_attitude: int) -> bool:
	var cells_not_being_productive: Array = Game.tilesObj.ai_get_cells_not_being_productive(bot_number)
	var amount_of_unproductive_territories: int = 0
	for cell in cells_not_being_productive:
		var tileTypeId: int = Game.tileTypes.getIDByName(Game.tilesObj.get_tile_type_dict(cell).name)
		if Game.tileTypes.canBeUpgraded(tileTypeId): #fix: avoid counting tiles that cannot be upgraded, this can make the bot be stuck
			amount_of_unproductive_territories+=1
		
	match type_of_attitude:
		BOT_ACTIONS.OFFENSIVE:
			return amount_of_unproductive_territories > 2 #Allows to have up to 2 unproductive territories
		BOT_ACTIONS.DEFENSIVE:
			return amount_of_unproductive_territories > 1 #Allows to have up to 1 unproductive territories
		BOT_ACTIONS.GREEDY:
			return amount_of_unproductive_territories > 1
	return false

func bot_is_lacking_recruit_buildings(bot_number: int, type_of_attitude: int) -> bool:
	var amount_of_territories: int = Game.tilesObj.get_amount_of_player_tiles(bot_number)
	var amount_of_buildings: int = Game.tilesObj.get_count_of_all_buildings_player_have(bot_number)
	
	if amount_of_buildings <= 0: #avoid dividing by zero LOL
		return true
		
	var ratio_buildings_per_territory: float = float(amount_of_territories)/float(amount_of_buildings)
	match type_of_attitude:
		BOT_ACTIONS.OFFENSIVE:
			return ratio_buildings_per_territory <= 0.25 #25% of territories should have buildings as minimum
		BOT_ACTIONS.DEFENSIVE:
			return ratio_buildings_per_territory <= 0.4 #40% of territories should have buildings as minimum
		BOT_ACTIONS.GREEDY:
			return ratio_buildings_per_territory <= 0.2 #20% of territories should have buildings as minimum
	
	return false

func bot_get_strength_needed_to_defend_capital(bot_number: int) -> Dictionary:
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	if	player_capital_pos == Vector2(-1, -1): 
		return {damage = 0.0, health = 0.0}

	var minimum_health_to_defend: float = float(Game.troopTypes.getByID(Game.troopTypes.getIDByName("recluta")).health)*float(BOT_MINIMUM_WARRIORS_AT_CAPITAL)
	var minimum_damage_to_defend: float = Game.troopTypes.getAverageDamage(Game.troopTypes.getIDByName("recluta"))*float(BOT_MINIMUM_WARRIORS_AT_CAPITAL)
	var enemies_close_to_capital_force: Dictionary = Game.tilesObj.ai_get_enemies_strength_close_to(player_capital_pos, bot_number)
	enemies_close_to_capital_force.damage+=minimum_damage_to_defend
	enemies_close_to_capital_force.health+=minimum_health_to_defend
	
	return enemies_close_to_capital_force

func bot_capital_in_danger(bot_number: int) -> bool:
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	if	player_capital_pos == Vector2(-1, -1): 
		return false
	var capital_health: float = Game.tilesObj.get_own_troops_health(player_capital_pos, bot_number)
	var capital_damage: float = Game.tilesObj.get_own_troops_damage(player_capital_pos, bot_number)
	
	var force_to_defend_capital: Dictionary = bot_get_strength_needed_to_defend_capital(bot_number)
	
	if force_to_defend_capital.damage >= capital_damage or force_to_defend_capital.health >= capital_health: #Capital under danger of attack!
		return true
	return false

func bot_percent_troops_allowed_to_move_from_capital(bot_number: int) -> float:
	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	if	player_capital_pos == Vector2(-1, -1) or bot_capital_in_danger(bot_number): 
		return 0.0
		
	if bot_capital_in_danger(bot_number):
		return 0.0
		
	var capital_health: float = Game.tilesObj.get_own_troops_health(player_capital_pos, bot_number)
	var capital_damage: float = Game.tilesObj.get_own_troops_damage(player_capital_pos, bot_number)
	var force_to_defend_capital: Dictionary = bot_get_strength_needed_to_defend_capital(bot_number)

	if capital_health <= 1.0 or capital_damage <= 1.0:
		return 0.0
		
	var health_defend_ratio: float = clamp((capital_health-force_to_defend_capital.health)/capital_health, 0.0, 1.0)
	var damage_defend_ratio: float = clamp((capital_damage-force_to_defend_capital.damage)/capital_damage, 0.0, 1.0)
	return min(health_defend_ratio, damage_defend_ratio)*0.8 #added 25% less just in case
	
func bot_process_game(bot_number: int) -> void:
	if !Game.is_current_player_a_bot():
		return

	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	if	player_capital_pos == Vector2(-1, -1): #player lost
		game_node.action_in_turn_executed()
		return

	var action_executed: bool = false
	var bot_is_having_debt: bool = Game.tilesObj.get_total_gold_gain_and_losses(bot_number) <= 0
	var enemy_reachable_capital: Vector2 = Game.tilesObj.ai_get_reachable_player_capital(bot_number)
	var bot_total_gold: float = Game.tilesObj.get_total_gold(bot_number)
	var bot_available_gold_to_use: float = bot_total_gold
	
	if bot_is_having_debt:
		bot_available_gold_to_use += Game.tilesObj.get_total_gold_gain_and_losses(bot_number)

	if bot_available_gold_to_use <= 0:
		Game.tilesObj.add_cell_gold(player_capital_pos, BOT_MINIMUM_GOLD_TO_USE)
	
	var type_of_attitude: int = bot_get_type_of_attitude(bot_number)
	
	match type_of_attitude:
		BOT_ACTIONS.OFFENSIVE:
			#print("[BOT] Playing ofensive")
			action_executed = bot_play_agressive(bot_number, player_capital_pos, bot_is_having_debt)
		BOT_ACTIONS.DEFENSIVE:
			#print("[BOT] Playing defensive")
			action_executed = bot_play_defensive(bot_number, player_capital_pos, bot_is_having_debt)
		BOT_ACTIONS.GREEDY:
			#print("[BOT] Playing greedy")
			action_executed = bot_play_greedy(bot_number, player_capital_pos, bot_is_having_debt)
	
	if !action_executed:
		print("bot doing nothing...")
	
	game_node.action_in_turn_executed()

func bot_play_agressive(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool) -> bool:
	if bot_try_to_defend_own_capital(bot_number, player_capital_pos):
		return true
	elif bot_try_to_attack_enemy_capital(bot_number, player_capital_pos, bot_is_having_debt, BOT_ACTIONS.OFFENSIVE): 
		return true	
	elif bot_try_to_attack_enemy(bot_number, BOT_ACTIONS.OFFENSIVE, bot_is_having_debt):
		return true
	elif bot_try_to_defend_own_territory(bot_number, player_capital_pos):
		return true
	elif bot_try_to_recover_territory(bot_number, player_capital_pos, bot_is_having_debt):
		return true
	elif bot_try_buy_or_upgrade(bot_number, BOT_ACTIONS.OFFENSIVE):
		return true
	elif bot_try_desperate_action(bot_number, bot_is_having_debt):
		return true
	elif bot_try_to_move_troops_to_frontiers(bot_number):
		return true
	return false
		
func bot_play_defensive(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool) -> bool:
	if bot_try_to_defend_own_capital(bot_number, player_capital_pos):
		return true
	elif bot_try_to_defend_own_territory(bot_number, player_capital_pos):
		return true
	elif bot_try_to_recover_territory(bot_number, player_capital_pos, bot_is_having_debt):
		return true
	elif bot_try_buy_or_upgrade(bot_number, BOT_ACTIONS.DEFENSIVE):
		return true
	elif bot_try_to_attack_enemy(bot_number, BOT_ACTIONS.DEFENSIVE, bot_is_having_debt):
		return true
	elif bot_try_to_attack_enemy_capital(bot_number, player_capital_pos, bot_is_having_debt, BOT_ACTIONS.DEFENSIVE):
		return true	
	elif bot_try_desperate_action(bot_number, bot_is_having_debt):
		return true
	elif bot_try_to_move_troops_to_frontiers(bot_number):
		return true
	return false
	
func bot_play_greedy(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool) -> bool:
	if bot_try_to_defend_own_capital(bot_number, player_capital_pos):
		return true
	elif bot_try_to_recover_territory(bot_number, player_capital_pos, bot_is_having_debt):
		return true
	elif bot_try_buy_or_upgrade(bot_number, BOT_ACTIONS.DEFENSIVE):
		return true
	elif bot_try_to_attack_enemy_capital(bot_number, player_capital_pos, bot_is_having_debt, BOT_ACTIONS.GREEDY):
		return true	
	elif bot_try_to_defend_own_territory(bot_number, player_capital_pos):
		return true
	elif bot_try_to_attack_enemy(bot_number, BOT_ACTIONS.GREEDY, bot_is_having_debt):
		return true
	elif bot_try_desperate_action(bot_number, bot_is_having_debt):
		return true
	elif bot_try_to_move_troops_to_frontiers(bot_number):
		return true
	return false

func bot_try_to_move_troops_to_frontiers(bot_number: int) -> bool:
	var inner_territories: Array = Game.tilesObj.ai_get_inner_territories(bot_number)
	var outer_territories: Array = Game.tilesObj.ai_get_outer_territories(bot_number)
	
	if outer_territories.size() <= 0 or inner_territories.size() <= 0:
		return false
	
	var cells_in_danger: Array = Game.tilesObj.ai_get_all_cells_in_danger(bot_number)
	var cells_with_warriors: Array = Game.tilesObj.get_all_tiles_with_warriors_from_player(bot_number, BOT_MIN_WARRIORS_TO_MOVE)
	var all_bot_cells: Array = Game.tilesObj.get_all_player_tiles(bot_number)
	var cells_without_warriors: Array = Game.Util.array_substract(all_bot_cells, cells_with_warriors)
	inner_territories = Game.Util.array_substract(inner_territories, cells_in_danger)
	inner_territories = Game.Util.array_substract(inner_territories, cells_without_warriors)
	
	if inner_territories.size() <= 0:
		return false
	
	#var cell_to_move_troops_from: Vector2 = Game.tilesObj.ai_get_strongest_available_cell_in_array(inner_territories, bot_number)
	var cell_to_move_troops_towards: Vector2 = Game.tilesObj.ai_get_weakest_cell_in_array(outer_territories, bot_number)
	if bot_move_troops_towards_pos(cell_to_move_troops_towards, bot_number):
		#print("[BOT] moving troops towards borders...")
		return true
	return false

func bot_try_to_recover_territory(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool) -> bool:
	var territories_to_recover: Array = Game.tilesObj.ai_order_cells_by_distance_to(bot_territories_to_recover[bot_number], player_capital_pos)
	for to_recover_cell in territories_to_recover:
		if Game.tilesObj.get_owner(to_recover_cell) == bot_number:
			continue
		if !Game.tilesObj.ai_have_strength_to_conquer(to_recover_cell, bot_number) and !bot_is_having_debt:
			continue
		if bot_move_troops_towards_pos(to_recover_cell, bot_number, bot_is_having_debt):
			#print("[BOT] recovering territory...")
			return true
	return false

func bot_try_to_defend_own_capital(bot_number: int, player_capital_pos: Vector2) -> bool:
	var capital_in_danger: bool = bot_capital_in_danger(bot_number)
	if !capital_in_danger:
		return false
	#print("BOT trying to defend own capital")
	return bot_move_troops_towards_pos(player_capital_pos, bot_number, true) #Fixme: Force to move towards capital

func bot_try_to_attack_enemy_capital(bot_number: int, player_capital_pos: Vector2, bot_is_having_debt: bool, type_of_attitude: int) -> bool:
	var enemy_reachable_capital: Vector2 = Vector2(-1, -1)
	var force_to_attack_enemy_capital: bool = bot_is_having_debt
	match type_of_attitude:
		BOT_ACTIONS.GREEDY:
			enemy_reachable_capital = Game.tilesObj.ai_get_reachable_player_capital(bot_number)
		BOT_ACTIONS.DEFENSIVE:
			enemy_reachable_capital = Game.tilesObj.ai_get_reachable_player_capital(bot_number)
		BOT_ACTIONS.OFFENSIVE:
			force_to_attack_enemy_capital = true
			enemy_reachable_capital = Game.tilesObj.ai_get_reachable_player_capital(bot_number, true) #Ofensive bots can attack capitals that are only close to allies territories too
	
	if enemy_reachable_capital != Vector2(-1, -1):
		#var path_to_enemy_capital: Array = Game.tilesObj.ai_get_attack_path_from_to(player_capital_pos, enemy_reachable_capital, bot_number)
		#var strongest_enemy_cell_in_path: Vector2 = Game.tilesObj.ai_get_strongest_enemy_cell_in_path(path_to_enemy_capital, bot_number)
		if Game.tilesObj.ai_have_strength_to_conquer(enemy_reachable_capital, bot_number) or bot_is_having_debt:
			if bot_move_troops_towards_pos(enemy_reachable_capital, bot_number, force_to_attack_enemy_capital):
				return true
	
	return false

func bot_try_to_attack_enemy(bot_number: int, type_of_attitude: int, bot_is_having_debt: int) -> bool:
	var cell_to_attack: Vector2 = bot_get_cell_to_attack(bot_number, type_of_attitude)
	if !Game.tilesObj.ai_have_strength_to_conquer(cell_to_attack, bot_number) and !bot_is_having_debt:
		return false
	return bot_move_troops_towards_pos(cell_to_attack, bot_number, bot_is_having_debt)
		
func bot_try_to_defend_own_territory(bot_number: int, player_capital_pos: Vector2) -> bool:
	var cells_to_defend: Array = Game.tilesObj.ai_order_cells_by_distance_to(Game.tilesObj.ai_get_all_cells_in_danger(bot_number), player_capital_pos)
	for cell in cells_to_defend:
		if bot_move_troops_towards_pos(cell, bot_number): # Try to defend this position
			return true
	return false

func bot_try_to_upgrade_territory(bot_number: int) -> bool:
	var bot_cells: Array = Game.tilesObj.get_all_player_tiles(bot_number)
	for cell in bot_cells:
		if Game.tilesObj.can_be_upgraded(cell, bot_number):
			if bot_upgrade_territory(cell, bot_number): #upgraded
				#print("[BOT] upgrading territory")
				return true
	return false

func bot_try_to_upgrade_unproductive_territories(bot_number: int) -> bool:
	var unproductive_territories: Array = Game.tilesObj.ai_get_cells_not_being_productive(bot_number)
	for cell in unproductive_territories:
		if Game.tilesObj.can_be_upgraded(cell, bot_number):
			if bot_upgrade_territory(cell, bot_number): #upgraded
				#print("[BOT] upgrading unproductive territory")
				return true
	return false

func bot_try_to_make_a_building(bot_number: int) -> bool:
	var cells_without_buildings: Array = Game.tilesObj.ai_get_all_cells_without_buildings(bot_number)

	while cells_without_buildings.size() > 0:
		var random_index: int  = rng.randi_range(0, cells_without_buildings.size()-1)
		if bot_buy_building_at_cell(cells_without_buildings[random_index], bot_number):
			return true
		cells_without_buildings.remove(random_index)

	return false

func bot_try_to_recruit_troops(bot_number: int) -> bool:
	#ai_order_cells_by_distance_to
	var cells_that_can_recruit: Array = Game.tilesObj.ai_get_all_cells_available_to_recruit(bot_number)
	
	while cells_that_can_recruit.size() > 0:
		var random_index: int  = rng.randi_range(0, cells_that_can_recruit.size()-1)
		if bot_make_new_troops(cells_that_can_recruit[random_index], bot_number):
			return true
		cells_that_can_recruit.remove(random_index)
		
	return false

func bot_try_buy_or_upgrade(bot_number: int, type_of_attitude: int) -> bool:
	var bot_gains: float = Game.tilesObj.get_total_gold_gain_and_losses(bot_number)
	var bot_total_gold: float = Game.tilesObj.get_total_gold(bot_number)
	var bot_available_gold_to_use: float = bot_total_gold
	if bot_gains < 0.0:
		 bot_available_gold_to_use += bot_gains

	if bot_available_gold_to_use <= BOT_MINIMUM_GOLD_TO_USE: #avoid buying stuff in case bot does not have good money
		return false

	if bot_gains >= BOT_MIMINUM_GOLD_GAINS_DESIRED and bot_is_lacking_troops(bot_number, type_of_attitude):
		print("[BOT] is lacking troops...")
		return bot_try_to_recruit_troops(bot_number) or bot_try_to_make_a_building(bot_number)
	elif bot_is_lacking_recruit_buildings(bot_number, type_of_attitude) and bot_gains >= BOT_MIMINUM_GOLD_GAINS_DESIRED:
		print("[BOT] is lacking buildings...")
		return bot_try_to_make_a_building(bot_number)
	elif bot_needs_to_upgrade_unproductive_territories(bot_number, type_of_attitude):
		print("[BOT] is having too many unproductive territories...")
		return bot_try_to_upgrade_unproductive_territories(bot_number)

	match type_of_attitude:
		BOT_ACTIONS.GREEDY:
			if bot_try_to_upgrade_unproductive_territories(bot_number):
				return true
			elif bot_try_to_upgrade_territory(bot_number):
				return true
			elif bot_try_to_make_a_building(bot_number):
				return true
			elif bot_try_to_recruit_troops(bot_number):
				return true
		BOT_ACTIONS.DEFENSIVE:
			if bot_try_to_upgrade_unproductive_territories(bot_number):
				return true
			elif bot_try_to_make_a_building(bot_number):
				return true
			elif bot_try_to_recruit_troops(bot_number):
				return true
			elif bot_try_to_upgrade_territory(bot_number):
				return true
		BOT_ACTIONS.OFFENSIVE:
			if bot_try_to_make_a_building(bot_number):
				return true
			elif bot_try_to_recruit_troops(bot_number):
				return true
			elif bot_try_to_upgrade_unproductive_territories(bot_number):
				return true
			elif bot_try_to_upgrade_territory(bot_number):
				return true
	return false

func bot_upgrade_territory(cell_to_upgrade: Vector2, bot_number: int) -> bool:
	var cell_data: Dictionary = Game.tilesObj.get_cell(cell_to_upgrade)
	
	var tile_type_id: int = cell_data.tile_id
	if  Game.tilesObj.is_upgrading(cell_to_upgrade):
		return false
	var tileTypeData = Game.tileTypes.getByID(tile_type_id)
	assert(Game.tileTypes.canBeUpgraded(tile_type_id))
	if tileTypeData.improve_prize > Game.tilesObj.get_total_gold(bot_number):
		return false
	game_node.save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.queue_upgrade_cell(cell_to_upgrade)
	Game.Network.net_send_event(game_node.node_id, game_node.NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	return true

func bot_recruit_troops(bot_number: int) -> bool:
	var cells_that_can_recruit: Array = Game.tilesObj.ai_get_all_cells_available_to_recruit(bot_number)
	if cells_that_can_recruit.size() <= 0: #try to build a building
		var cells_without_buildings: Array = Game.tilesObj.ai_get_all_cells_without_buildings(bot_number)
		if cells_without_buildings.size() > 0:
			return bot_buy_building_at_cell(cells_without_buildings[rng.randi_range(0, cells_without_buildings.size()-1)], bot_number)
		else:
			return false
	else:
		return bot_make_new_troops(cells_that_can_recruit[rng.randi_range(0, cells_that_can_recruit.size()-1)], bot_number)

func bot_get_cell_to_attack(bot_number: int, type_of_attitude: int) -> Vector2:
	var cell_to_attack: Vector2
	
	match type_of_attitude:
		BOT_ACTIONS.GREEDY:
			cell_to_attack =  Game.tilesObj.ai_get_richest_enemy_cell(bot_number)
			#awful code, I am sorry
			if cell_to_attack == Vector2(-1, -1): 
				cell_to_attack = Game.tilesObj.ai_get_richest_enemy_cell(bot_number, true) #use allies territories
		BOT_ACTIONS.DEFENSIVE:
			cell_to_attack = Game.tilesObj.ai_get_closest_to_capital_player_enemy_cell(bot_number)
			if cell_to_attack == Vector2(-1, -1): 
				cell_to_attack = Game.tilesObj.ai_get_closest_to_capital_enemy_cell(bot_number)
		BOT_ACTIONS.OFFENSIVE:
			cell_to_attack = Game.tilesObj.ai_get_weakest_player_enemy_cell(bot_number)
			if cell_to_attack == Vector2(-1, -1):
				cell_to_attack = Game.tilesObj.ai_get_weakest_player_enemy_cell(bot_number, true)
			if cell_to_attack == Vector2(-1, -1):
				cell_to_attack = Game.tilesObj.ai_get_weakest_enemy_cell(bot_number)
			if cell_to_attack == Vector2(-1, -1):
				cell_to_attack = Game.tilesObj.ai_get_weakest_enemy_cell(bot_number, true)
	
	return cell_to_attack

func bot_buy_building_at_cell(cell_pos: Vector2, bot_number: int) -> bool:
	if !game_node.check_if_player_can_buy_buildings(cell_pos, bot_number):
		return false
	
	var available_buildings_to_build: Array = []
	var getTotalGoldAvailable: int = Game.tilesObj.get_total_gold(bot_number)
	var buildingTypesList: Array = Game.buildingTypes.getList() #Gives a copy, not the original list edit is safe
	for i in range(buildingTypesList.size()):
		if Game.tilesObj.can_buy_building_at_cell(cell_pos, i, getTotalGoldAvailable, bot_number):
			available_buildings_to_build.append(i)
	var best_building_id_to_buy: int = -1
	for i in available_buildings_to_build:
		if best_building_id_to_buy == -1:
			best_building_id_to_buy = i
			continue
		var best_building_dict_prize: float = Game.buildingTypes.getByID(best_building_id_to_buy).buy_prize
		var current_building_dict_prize: float = Game.buildingTypes.getByID(i).buy_prize
		if current_building_dict_prize >= best_building_dict_prize:
			 best_building_id_to_buy = i
		
	Game.tilesObj.update_sync_data()
	Game.tilesObj.buy_building(cell_pos, available_buildings_to_build[best_building_id_to_buy])
	Game.Network.net_send_event(game_node.node_id, game_node.NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	return true

func bot_make_new_troops(cell_pos: Vector2, bot_number: int) -> bool:
	if !game_node.is_recruiting_possible(cell_pos, bot_number):
		return false
	var cell_data: Dictionary = Game.tilesObj.get_cell(cell_pos)
	var currentBuildingType = Game.buildingTypes.getByID(cell_data.building_id)
	var idTroopsToRecruit: int = currentBuildingType.id_troop_generate
	var ammountOfTroopsToRecruit: int = 0
	
	var upcomingTroopsDict: Dictionary = {
		owner = bot_number,
		troop_id= currentBuildingType.id_troop_generate,
		amount = int(float(currentBuildingType.deploy_amount)*Game.get_bot_troops_multiplier(bot_number)),
		turns_left = currentBuildingType.turns_to_deploy_troops
	}
	game_node.save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.take_cell_gold(cell_pos, float(currentBuildingType.deploy_prize)*Game.get_bot_discount_multiplier(bot_number))
	Game.tilesObj.append_upcoming_troops(cell_pos, upcomingTroopsDict)
	Game.Network.net_send_event(game_node.node_id, game_node.NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })
	return true

func bot_clear_cache_path_to_follow(bot_number: int) -> void:
	Game.playersData[bot_number].bot_stats.path_to_follow.clear()

func bot_cache_path_to_follow_pop_front(bot_number: int) -> void:
	Game.playersData[bot_number].bot_stats.path_to_follow.pop_front()

func bot_update_cache_path_to_follow(bot_number: int, new_path_to_follow: Array) -> void:
	bot_clear_cache_path_to_follow(bot_number)
	Game.playersData[bot_number].bot_stats.path_to_follow = new_path_to_follow.duplicate(true)

func check_if_bot_can_use_cache_path_to_follow(bot_number: int, start_pos: Vector2, end_pos: Vector2) -> bool:
	if Game.playersData[bot_number].bot_stats.path_to_follow.size() < 2:
		return false
	var first_path_element: Vector2 = Game.playersData[bot_number].bot_stats.path_to_follow[0]
	var last_path_element: Vector2 = Game.playersData[bot_number].bot_stats.path_to_follow[Game.playersData[bot_number].bot_stats.path_to_follow.size()-1]
	
	return first_path_element == start_pos and last_path_element == end_pos

func bot_get_next_pos_in_cache_path_to_follow(bot_number: int) -> Vector2:
	if Game.playersData[bot_number].bot_stats.path_to_follow.size() < 2:
		return Vector2(-1, -1)
	return Game.playersData[bot_number].bot_stats.path_to_follow[1]

func bot_move_troops_from_to(start_pos: Vector2, end_pos: Vector2, bot_number: int, force_to_move: bool = false) -> bool:
	var percent_troops_to_move: float = 1.0
	if start_pos == Vector2(-1, -1) or end_pos == Vector2(-1, -1) or start_pos == end_pos:
		return false
	if !Game.tilesObj.is_next_to_tile(start_pos, end_pos):
		return false

	var bot_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	
	if start_pos == bot_capital_pos:
		percent_troops_to_move = float(bot_percent_troops_allowed_to_move_from_capital(bot_number))
		if percent_troops_to_move <= 0.1:
			return false
			
	var amount_troops_to_move: int = int(floor(float(Game.tilesObj.get_warriors_count(start_pos, bot_number))*percent_troops_to_move))
	if  amount_troops_to_move < BOT_MIN_WARRIORS_TO_MOVE:
		return false
	
	if end_pos == bot_capital_pos:
		force_to_move = true #always move everything towards own capital
		
	if force_to_move or Game.tilesObj.ai_can_conquer_enemy_pos(start_pos, end_pos, bot_number):
		if start_pos == bot_capital_pos:
			force_to_move = false #hack to avoid moving all trops from capital and only the needed percent
		return Game.tilesObj.ai_move_warriors_from_to(start_pos, end_pos, bot_number, percent_troops_to_move, force_to_move)
		
	return false

func bot_move_troops_towards_pos(pos_to_move: Vector2, bot_number: int, force_to_move: bool = false) -> bool:
	if pos_to_move == Vector2(-1, -1):
		return false
	var pos_to_move_towards: Vector2 = Vector2(-1, -1)
	var start_pos_to_move: Vector2 = Vector2(-1, -1)
	var bot_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	var available_cells_to_use: Array
	
	if force_to_move:
		available_cells_to_use = Game.tilesObj.get_all_tiles_with_warriors_from_player(bot_number, BOT_MIN_WARRIORS_TO_MOVE)
		available_cells_to_use = Game.Util.array_search_and_remove(available_cells_to_use, pos_to_move)
	else:
		available_cells_to_use = Game.tilesObj.ai_get_cells_available_to_conquer_pos(bot_number, pos_to_move, BOT_MIN_WARRIORS_TO_MOVE)
	
	available_cells_to_use = Game.tilesObj.ai_order_cells_by_distance_to(available_cells_to_use, pos_to_move)
	
	for start_pos in available_cells_to_use:
		if Game.tilesObj.is_cell_in_battle(start_pos):
			continue
		# Try to use cache path, to avoid problems
		if check_if_bot_can_use_cache_path_to_follow(bot_number, start_pos, pos_to_move) and bot_move_troops_from_to(start_pos, bot_get_next_pos_in_cache_path_to_follow(bot_number), bot_number, force_to_move):
			bot_cache_path_to_follow_pop_front(bot_number)
			#game_node.get_node()$Tiles.debug_tile_path([start_pos, pos_to_move])
			#print("[BOT] moving troops using cached path...")
			return true
			
		var path_to_use: Array = Game.tilesObj.ai_get_attack_path_from_to(start_pos, pos_to_move, bot_number)
		path_to_use = Game.Util.array_search_and_remove(path_to_use, start_pos)
		if path_to_use.size() <= 0:
			continue
		
		if bot_move_troops_from_to(start_pos, path_to_use[0], bot_number, force_to_move):
			if path_to_use.size() > 1:
				bot_update_cache_path_to_follow(bot_number, path_to_use)
			#$Tiles.debug_tile_path([start_pos, pos_to_move])
			#print("[BOT] Moving troops...")
			return true
	
	bot_clear_cache_path_to_follow(bot_number) #clear it in case it failed
	return false

func bot_process_pre_game(bot_number: int):
	if !Game.is_current_player_a_bot():
		return
	if !game_node.player_has_capital(bot_number):
		give_bot_a_capital(bot_number)
		return

	var player_capital_pos: Vector2 = Game.tilesObj.get_player_capital_vec2(bot_number)
	var all_player_cells: Array = Game.tilesObj.get_all_player_tiles(bot_number)
	var get_extra_troops_action: bool = false #if true, it will get troops, if not, it will get a territory
	
	if Game.tilesObj.get_total_gold(bot_number) <= 0:
		bot_execute_give_extra_gold(bot_number, player_capital_pos)
		return
		
	if Game.tilesObj.get_total_gold_gain_and_losses(bot_number) <= 0:
		get_extra_troops_action = false
	else:
		get_extra_troops_action = rng.randi_range(0, 100) >= 50
	
	var type_of_action_to_make: int = bot_get_type_of_action_to_make(bot_number)
	match type_of_action_to_make:
		BOT_ACTIONS.DEFENSIVE:
			if get_extra_troops_action:
				bot_execute_add_extra_troops(bot_number, player_capital_pos)
			else:
				var available_cells_to_get: Array = Game.tilesObj.ai_get_closest_available_to_buy_free_cell_to(player_capital_pos, bot_number)
				game_node.give_player_rural(bot_number, available_cells_to_get[rng.randi_range(0, available_cells_to_get.size()-1)])
				
		BOT_ACTIONS.OFFENSIVE:
			var bot_cells_farthest_from_capital: Array = Game.tilesObj.ai_get_farthest_player_cell_from(player_capital_pos, bot_number)
			var cell_to_use_picked: Vector2 = bot_cells_farthest_from_capital[rng.randi_range(0, bot_cells_farthest_from_capital.size()-1)]
			if get_extra_troops_action:
				bot_execute_add_extra_troops(bot_number, cell_to_use_picked)
			else:
				var available_cells_to_get: Array = Game.tilesObj.ai_get_closest_available_to_buy_free_cell_to(cell_to_use_picked, bot_number)
				game_node.give_player_rural(bot_number, available_cells_to_get[rng.randi_range(0, available_cells_to_get.size()-1)])
		BOT_ACTIONS.GREEDY:
			bot_execute_give_extra_gold(bot_number, all_player_cells[rng.randi_range(0, all_player_cells.size()-1)])
	
	#use_selection_point()
	Game.playersData[bot_number].selectLeft -= 1
	game_node.server_send_game_info()
	if Game.playersData[bot_number].selectLeft == 0:
		game_node.move_to_next_player_turn()
	
func bot_get_type_of_action_to_make(bot_number: int) -> int:
	var defensive_points:float = Game.playersData[bot_number].bot_stats.defensiveness*Game.rng.randf_range(0.0, 100.0)
	var ofensive_points:float = Game.playersData[bot_number].bot_stats.aggressiveness*Game.rng.randf_range(0.0, 100.0)
	var greedy_points:float = Game.playersData[bot_number].bot_stats.avarice*Game.rng.randf_range(0.0, 100.0)
	
	if defensive_points >= ofensive_points and defensive_points >= greedy_points:
		return BOT_ACTIONS.DEFENSIVE
		
	if ofensive_points >= defensive_points and ofensive_points >= greedy_points:
		return BOT_ACTIONS.OFFENSIVE
		
	return BOT_ACTIONS.GREEDY

func bot_get_type_of_attitude(bot_number: int) -> int:
	var defensive_points:float = Game.playersData[bot_number].bot_stats.defensiveness
	var ofensive_points:float = Game.playersData[bot_number].bot_stats.aggressiveness
	var greedy_points:float = Game.playersData[bot_number].bot_stats.avarice
	if defensive_points >= ofensive_points and defensive_points >= greedy_points:
		return BOT_ACTIONS.DEFENSIVE
		
	if ofensive_points >= defensive_points and ofensive_points >= greedy_points:
		return BOT_ACTIONS.OFFENSIVE
	return BOT_ACTIONS.GREEDY

func give_bot_a_capital(bot_number: int):
	if !Game.is_current_player_a_bot():
		return
	game_node.give_player_capital(bot_number, Game.tilesObj.ai_pick_random_free_cell())

func bot_execute_give_extra_gold(bot_number: int, cell: Vector2):
	if !Game.is_current_player_a_bot():
		return
	game_node.save_player_info()
	Game.tilesObj.update_sync_data()
	Game.tilesObj.add_cell_gold(cell, 10.0*Game.get_bot_extra_gold_multiplier(bot_number))
	Game.Network.net_send_event(game_node.node_id, game_node.NET_EVENTS.UPDATE_TILE_DATA, {dictArray = Game.tilesObj.get_sync_data() })

func bot_execute_add_extra_troops(bot_number: int, cell: Vector2):
	if !Game.is_current_player_a_bot():
		return
	game_node.save_player_info()
	game_node.give_troops_to_player_and_sync(cell, bot_number, "recluta", int(round(1000.0*Game.get_bot_troops_multiplier(bot_number))))
