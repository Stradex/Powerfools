class_name UtilObject
extends Object

func arrays_contents_are_equal(arrayA: Array, arrayB: Array) -> bool:
	var arrayASize: int = arrayA.size()
	var arrayBSize: int = arrayB.size()
	if arrayASize != arrayBSize:
		return false
	for i in range(arrayASize):
		if typeof(arrayA[i]) != typeof(arrayA[i]):
			return false
		if typeof(arrayA[i]) == TYPE_DICTIONARY:
			if dicts_are_equal(arrayA[i], arrayB[i]):
				continue
			else:
				return false
		if typeof(arrayA[i]) == TYPE_ARRAY:
			if arrays_contents_are_equal(arrayA[i], arrayB[i]):
				continue
			else:
				return false
		if arrayA[i] != arrayB[i]:
			return false
	return true

func dicts_are_equal(dictA: Dictionary, dictB: Dictionary) -> bool:
	for key in dictA:
		if !dictB.has(key):
			return false
		if typeof(dictA[key]) != typeof(dictB[key]):
			return false
		if  typeof(dictA[key]) == TYPE_DICTIONARY:
			if dicts_are_equal(dictA[key], dictB[key]):
				continue
			else:
				return false
		if  typeof(dictA[key]) == TYPE_ARRAY:
			if arrays_contents_are_equal(dictA[key], dictB[key]):
				continue
			else:
				return false
		if dictB[key] != dictA[key]:
			return false
			
	for key in dictB:
		if !dictA.has(key):
			return false
		if typeof(dictA[key]) != typeof(dictB[key]):
			return false
		if  typeof(dictA[key]) == TYPE_DICTIONARY:
			if dicts_are_equal(dictA[key], dictB[key]):
				continue
			else:
				return false
		if  typeof(dictA[key]) == TYPE_ARRAY:
			if arrays_contents_are_equal(dictA[key], dictB[key]):
				continue
			else:
				return false
		if dictB[key] != dictA[key]:
			return false

	return true; #they are totally equal

func array_search_and_remove(array_data: Array, element_to_remove) -> Array:
	var return_array: Array = array_data.duplicate(true)
	var remove_index: int = return_array.find(element_to_remove)
	while remove_index != -1:
		return_array.remove(remove_index)
		remove_index = return_array.find(element_to_remove)
	return return_array

#return_array = arrayA - arrayB
func array_substract(arrayA: Array, arrayB: Array) -> Array:
	var return_array: Array = []
	for i in range(arrayA.size()):
		if arrayB.find(arrayA[i]) == -1:
			return_array.append(arrayA[i])
	return return_array

#return_array = arrayA + arrayB (no duplicates)
func array_addition(arrayA: Array, arrayB: Array, allow_duplicates: bool = false) -> Array:
	var return_array: Array = []
	return_array = arrayA.duplicate(true)
	for i in range(arrayB.size()):
		if arrayA.find(arrayB[i]) != -1 and !allow_duplicates:
			continue
		return_array.append(arrayB[i])
	return return_array
	
func convert_multidimentional_array_into_onedimensional(array_of_arrays: Array, allow_duplicates: bool = false) -> Array:
	var single_array: Array = []
	for data in array_of_arrays:
		if  typeof(data) != TYPE_ARRAY:
			if single_array.find(data) == -1 or allow_duplicates: 
				single_array.append(data)
		else:
			single_array = array_addition(single_array, convert_multidimentional_array_into_onedimensional(data, allow_duplicates), allow_duplicates)
	return single_array
