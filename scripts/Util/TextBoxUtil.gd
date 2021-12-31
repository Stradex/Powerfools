class_name TextEditPlus
extends TextEdit

var max_length: int = -1
var chars_to_allow: String = ""
var clamp_values: Vector2 = Vector2(-1, -1) #max and min value

func set_max_length(new_max_length: int) -> void:
	if !is_connected("text_changed", self, "plus_text_changed"):
		connect("text_changed", self, "plus_text_changed")
	max_length = new_max_length

func allow_only_specific_chars(new_chars_to_allow: String) -> void:
	if !is_connected("text_changed", self, "plus_text_changed"):
		connect("text_changed", self, "plus_text_changed")
	chars_to_allow = new_chars_to_allow

#Shorthand
func only_numbers(min_value: int = -1, max_value: int = -1) -> void:
	if !is_connected("text_changed", self, "plus_text_changed"):
		connect("text_changed", self, "plus_text_changed")
	chars_to_allow = "0123456789"
	clamp_values = Vector2(min_value, max_value)

func plus_text_changed() -> void:
	var current_text: String = self.text
	if max_length > -1 and current_text.length() > max_length:
		current_text.erase(max_length, current_text.length()-max_length)
	
	if chars_to_allow.length() > 0:
		var cleaned: bool = false
		while !cleaned:
			cleaned = true
			for i in range(current_text.length()):
				if chars_to_allow.find(current_text[i]) == -1:
					cleaned = false
					current_text = current_text.replace(current_text[i], "")
					break

	var numeric_value: int = int(current_text)
	if clamp_values.x != -1:
		if numeric_value < clamp_values.x:
			numeric_value = clamp_values.x
			current_text = str(numeric_value)
	if clamp_values.y != -1:
		if numeric_value > clamp_values.y:
			numeric_value = clamp_values.y
			current_text = str(numeric_value)

	self.text = current_text
	cursor_set_column(self.text.length())
