# asteroid_importer.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright (c) 2017-2020 Charlie Whitfield
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# *****************************************************************************
# Packs source file data to binaries used at runtime. See README.md. Units in
# the source files are: au, deg, deg/yr (last update, but verify!). We convert
# these to au, rad, rad/yr in the packed binaries. Convert from these when
# importing.

extends PopupPanel

const math := preload("res://ivoyager/static/math.gd")
const file_utils := preload("res://ivoyager/static/file_utils.gd")

const SCENE := "res://asteroid_importer/asteroid_importer.tscn"
const EXTENSION_NAME := "AsteroidImporter"
const EXTENSION_VERSION := "dev"
const EXTENSION_VERSION_YMD := 20191029

const DEBUG_PRINT_BINARY_TEXT := false
const REJECT_999 := false # reject mag "-9.99"; if false, accept but change to "99"
const N_ELEMENTS := 10

const SOURCE_PATH := "user://bigdata_source/"
const WRITE_BINARIES_DIR := "user://bigdata_binaries"
const BINARIES_EXTENSION := "vbinary"
const ASTEROID_ORBITAL_ELEMENTS_NUMBERED_FILE := "allnum.cat"
const ASTEROID_ORBITAL_ELEMENTS_MULTIOPPOSITION_FILE := "ufitobs.cat"
const ASTEROID_PROPER_ELEMENTS_FILES := ["all.syn", "tno.syn", "secres.syn"]
const SECULAR_RESONANT_FILE := "secres.syn" # This one in above list, but special
const TROJAN_PROPER_ELEMENTS_FILE := "tro.syn"
const ASTEROID_NAMES_FILE := "discover.tab"
const STATUS_INTERVAL := 20000
const BINARY_FILE_MAGNITUDES := MinorBodiesBuilder.BINARY_FILE_MAGNITUDES

var _table_data: Dictionary = Global.table_data
var _table_fields: Dictionary = Global.table_fields

# current processing
var _asteroid_elements := PoolRealArray()
var _asteroid_names := []
var _iau_numbers := [] # -1 for unnumbered
var _astdys2_lookup := {} # index by astdys-2 format (number string or "2010UZ106")
var _trojan_elements := {}
var _index := 0

const GRID_LAYOUT := [
	["_add_numbered", "Add Numbered", "Add numbered asteroids to the pool."],
	["_add_multiopposition", "Add Multiopposition", "Add multiopposition asteroids to the pool."],
	["_revise_names", "Revise Names", "Revise asteroid number to number-name where available.\n(Assumes numbered asteroids were added first above.)"],
	["_revise_proper", "Revise Proper Orbits", "Revise orbital elements to proper where available."],
	["_revise_trojans", "Revise Trojan Orbits", "Revise orbital elements to trojan proper where available."],
	["_make_binary_files", "Make Binaries", "Make binary files from pool."],
	["_start_over", "Start Over", "Clear data and start over."]
]

var _status_labels := []
var _function_index := -1
var _thread := Thread.new()

func extension_init() -> void:
	ProjectBuilder.connect("project_objects_instantiated", self, "_on_objects_instantiated")
	Global.connect("main_inited", self, "_on_main_inited")

func _on_objects_instantiated() -> void:
	Global.program.MainMenu.make_button("Ast. Import", 290, true, false, self, "_open")

func _on_main_inited() -> void:
	Global.program.GUITop.add_child(self)

func _ready() -> void:
	var layout_index := 0
	while layout_index < GRID_LAYOUT.size():
		var layout_item: Array = GRID_LAYOUT[layout_index] 
		var item_button := Button.new()
		item_button.connect("pressed", self, "_run_function", [layout_index])
		item_button.text = layout_item[1]
		$VBox/Grid.add_child(item_button)
		var item_label := Label.new()
		item_label.text = layout_item[2]
		item_label.rect_min_size = Vector2(400, 50)
		item_label.valign = Label.ALIGN_CENTER
		item_label.autowrap = true
		$VBox/Grid.add_child(item_label)
		var status_label := Label.new()
		status_label.rect_min_size = Vector2(100, 50)
		status_label.valign = Label.ALIGN_CENTER
		_status_labels.append(status_label)
		$VBox/Grid.add_child(status_label)
		layout_index += 1
	var close_button := Button.new()
	close_button.connect("pressed", self, "_close")
	close_button.text = "Close"
	$VBox/Grid.add_child(close_button)

func _open() -> void:
	Global.program.Main.require_stop(self)
	popup()

func _run_function(layout_index: int) -> void:
	_function_index = layout_index
	var layout_item: Array = GRID_LAYOUT[layout_index]
	var function: String = layout_item[0]
	if Global.use_threads:
		if _thread.is_active():
			_thread.wait_to_finish()
		_thread.start(self, "_run_in_thread", function)
	else:
		call(function)

func _run_in_thread(function: String) -> void:
	call(function)

func _add_numbered() -> void:
	_read_astdys_cat_file(ASTEROID_ORBITAL_ELEMENTS_NUMBERED_FILE)
	
func _add_multiopposition() -> void:
	_read_astdys_cat_file(ASTEROID_ORBITAL_ELEMENTS_MULTIOPPOSITION_FILE)
	
func _revise_names() -> void:
	# The name file used here and asteroid numbered file both both have
	# line number = asteroid number. We test that and use for indexing.
	var index := 0
	var renamed := 0
	var path := SOURCE_PATH + ASTEROID_NAMES_FILE
	var read_file = File.new()
	if read_file.open(path, File.READ) != OK:
#		print("Could not open ", path)
		_update_status("Could not open " + path)
		return
	var line: String = read_file.get_line()
	var status_index := STATUS_INTERVAL
	while not read_file.eof_reached():
		var number := int(line.substr(0, 6))
		assert(number == index + 1)
		assert(number == int(_asteroid_names[index]))
		var astdys2_name := line.substr(7, 17)
		astdys2_name = astdys2_name.strip_edges(false, true)
		if astdys2_name == "-":
			astdys2_name = ""
		if astdys2_name == "": # get and format year-number astdys2_name, if any
			astdys2_name = line.substr(25, 4) + line.substr(30, 6) # skip space conforms w/ AstDyS-2
			if astdys2_name.substr(0, 1) == "-":
				astdys2_name = ""
			else:
				astdys2_name = astdys2_name.strip_edges(false, true)
		if astdys2_name:
			renamed += 1
#			if not _astdys2_lookup.has(astdys2_name):
#				_fallback_lookup_table[astdys2_name] = index
			astdys2_name = str(number) + " " + astdys2_name
			if renamed == status_index:
				_update_status("%s renamed (current: \"%s\" to \"%s\"" % [renamed, _asteroid_names[index], astdys2_name])
#				_update_status(str(renamed) + " renamed (current: \"", _asteroid_names[index], "\" to \"", astdys2_name, "\"")
				status_index += STATUS_INTERVAL
			_asteroid_names[index] = astdys2_name
		line = read_file.get_line()
		index += 1
	read_file.close()
	_update_status(str(renamed) + " renamed")

func _revise_proper() -> void:
	# TODO: Secular resonant are only patially implemented (we simply skip e here)
	var revised := 0
	var n_not_found := 0
	var status_index := STATUS_INTERVAL
	for file_name in ASTEROID_PROPER_ELEMENTS_FILES:
		var secular_resonance: bool = file_name == SECULAR_RESONANT_FILE
		print("secular_resonance ", secular_resonance)
		var path: String = SOURCE_PATH + file_name
		var read_file := File.new()
		if read_file.open(path, File.READ) != OK:
#			print("Could not open ", path)
			_update_status("Could not open " + path)
			continue
		var line := read_file.get_line()
		while not read_file.eof_reached():
			if line.substr(0, 1) == "%":
				line = read_file.get_line()
				continue
			var line_array := line.split(" ", false)
			var astdys2_name: String = line_array[0]
			var index: int
			if _astdys2_lookup.has(astdys2_name):
				index = _astdys2_lookup[astdys2_name]
	#		elif _fallback_lookup_table.has(astdys2_name):
	#			index = _fallback_lookup_table[astdys2_name]
			else:
				n_not_found += 1
				line = read_file.get_line()
				continue
			var mag_str: String = line_array[1]
			if mag_str == "-9.99":
				if REJECT_999:
					line = read_file.get_line()
					continue
				else:
					mag_str = "99"
			var magnitude := float(mag_str)
			var proper_a := float(line_array[2]) # in au
			var proper_e := float(line_array[3])
			var proper_i := asin(float(line_array[4])) # file has sin(i)
			var proper_n := deg2rad(float(line_array[5])) # now rad/yr
			_asteroid_elements[index * N_ELEMENTS] = proper_a
			if not secular_resonance:
				_asteroid_elements[index * N_ELEMENTS + 1] = proper_e
			_asteroid_elements[index * N_ELEMENTS + 2] = proper_i
			_asteroid_elements[index * N_ELEMENTS + 6] = proper_n
			# Note: Magnitues in .syn files are not EXACTLY the same as .cat.
			# Can magnitude be "proper"? In any case, we replace it.
			_asteroid_elements[index * N_ELEMENTS + 7] = magnitude
			revised += 1
			if revised == status_index:
				_update_status("%s orbits revised to proper" % revised)
				status_index += STATUS_INTERVAL
			line = read_file.get_line()
		read_file.close()
	_update_status("%s orbits revised to proper\n(Did not find %s)" % [revised, n_not_found])

func _revise_trojans() -> void:
	# For trojans, we revise to proper e & i and save L-point, d, D & f in
	# _trojan_elements indexed by index (for writing to separate "L4", "L5"
	# binaries).
	var revised := 0
	var n_not_found := 0
	var status_index := STATUS_INTERVAL
	var path := SOURCE_PATH + TROJAN_PROPER_ELEMENTS_FILE
	var read_file := File.new()
	if read_file.open(path, File.READ) != OK:
#		print("Could not open ", path)
		_update_status("Could not open " + path)
		return
	var line := read_file.get_line()
	while not read_file.eof_reached():
		if line.substr(0, 1) == "%":
			line = read_file.get_line()
			continue
		var line_array := line.split(" ", false)
		var astdys2_name: String = line_array[0]
		var index: int
		if _astdys2_lookup.has(astdys2_name):
			index = _astdys2_lookup[astdys2_name]
#		elif _fallback_lookup_table.has(astdys2_name):
#			index = _fallback_lookup_table[astdys2_name]
		else:
			n_not_found += 1
			line = read_file.get_line()
			continue
		var mag_str: String = line_array[1]
		if mag_str == "-9.99":
			if REJECT_999:
				line = read_file.get_line()
				continue
			else:
				mag_str = "99"
		var magnitude := float(mag_str)
		var d := float(line_array[2]) # au
		var D := deg2rad(float(line_array[3])) # deg -> rad
		var f := deg2rad(float(line_array[4])) # deg/y -> rad/y
		var proper_e := float(line_array[5])
		var proper_i := asin(float(line_array[7])) # file has sin(i)
		var l_point: String = line_array[9] # either "4" or "5"
		# Regular propers
		_asteroid_elements[index * N_ELEMENTS + 1] = proper_e
		_asteroid_elements[index * N_ELEMENTS + 2] = proper_i
		_asteroid_elements[index * N_ELEMENTS + 7] = magnitude
		# Trojan data
		_trojan_elements[index] = [l_point, d, D, f]
		
		revised += 1
		if revised == status_index:
			_update_status("%s orbits revised to proper" % revised)
			status_index += STATUS_INTERVAL
		line = read_file.get_line()
	read_file.close()
	_update_status("%s orbits revised to proper\n(Did not find %s)" % [revised, n_not_found])

func _make_binary_files() -> void:
	# Binary files have name format such as "NE.22.5.vbinary" where NE is
	# orbit group (defined in data_tables/asteroid_import_data.txt) and 22.5
	# is the magnitude cutoff (contains everything brighter than this and
	# not already in smaller numbered binaries).
	# The binary is made using Godot function store_var(array) where array is
	# [<n_indexes>, <N_ELEMENTS>, <_asteroid_elements>, <_asteroid_names>,
	# <trojan_elements or null>]
	
	var group_data: Array = _table_data.asteroid_groups
	var group_fields: Dictionary = _table_fields.asteroid_groups
	var tot_indexes := _asteroid_names.size()
	_update_status("tot_indexes: %s" % tot_indexes)
	print("N_ELEMENTS: ", N_ELEMENTS)
	var added := 0
	
	# Store indexes by file_name where data will be stored
	var index_dict := {}
	var mags := []
	for mag_str in BINARY_FILE_MAGNITUDES:
		mags.append(float(mag_str))
	var trojan_group := {}
	var trojan_file_groups := []
	for row_data in group_data:
		var is_trojans := row_data[group_fields.trojan_of] as bool
		var group: String = row_data[group_fields.group]
		trojan_group[group] = is_trojans
		if not is_trojans:
			index_dict[group] = {}
			for mag_str in BINARY_FILE_MAGNITUDES:
				index_dict[group][mag_str] = []
		else:
			trojan_file_groups.append(group + "4")
			trojan_file_groups.append(group + "5")
			index_dict[group + "4"] = {}
			index_dict[group + "5"] = {}
			for mag_str in BINARY_FILE_MAGNITUDES:
				index_dict[group + "4"][mag_str] = []
			for mag_str in BINARY_FILE_MAGNITUDES:
				index_dict[group + "5"][mag_str] = []

	var all_criteria := {}
	var au := UnitDefs.AU
	for row_data in group_data:
		var group: String = row_data[group_fields.group]
		all_criteria[group] = {
			min_q = row_data[group_fields.min_q] / au if row_data[group_fields.min_q] != null else 0.0,
			max_q = row_data[group_fields.max_q] / au if row_data[group_fields.max_q] != null else INF,
			min_a = row_data[group_fields.min_a] / au if row_data[group_fields.min_a] != null else 0.0,
			max_a = row_data[group_fields.max_a] / au if row_data[group_fields.max_a] != null else INF
		}
	var status_index := STATUS_INTERVAL
	for index in range(tot_indexes):
		var a: float = _asteroid_elements[index * N_ELEMENTS]
		var e: float = _asteroid_elements[index * N_ELEMENTS + 1]
		var q: float = (1.0 - e) * a
		var magnitude: float = _asteroid_elements[index * N_ELEMENTS + 7]
		var mag_str: String = BINARY_FILE_MAGNITUDES[mags.bsearch(magnitude)]
		for group in all_criteria:
			var criteria = all_criteria[group]
			if a <= criteria.min_a or a > criteria.max_a:
				continue
			if q <= criteria.min_q or q > criteria.max_q:
				continue
			var is_trojan: bool = _trojan_elements.has(index)
			if is_trojan != trojan_group[group]:
				continue
			# passes all criteria, so add index to a group
			if is_trojan:
				var l_point: String = _trojan_elements[index][0]
				index_dict[group + l_point][mag_str].append(index)
			else:
				index_dict[group][mag_str].append(index)
			added += 1
			if added == status_index:
				_update_status("%s indexes added (current prefix: %s.%s)" % [added, group, mag_str])
				status_index += STATUS_INTERVAL
			break
	print("%s indexes added" % added)
	if added != tot_indexes:
		print("WARNING! %s added different than %s index number. Check data table criteria." % [added, tot_indexes])
	
	# Write binaries
	print("Writing binaries to ", WRITE_BINARIES_DIR)
	file_utils.make_or_clear_dir(WRITE_BINARIES_DIR)
	var asteroid_group := AsteroidGroup.new()
	for file_group in index_dict:
		var is_trojans: bool = trojan_file_groups.has(file_group)
		for mag_str in index_dict[file_group]:
			var indexes: Array = index_dict[file_group][mag_str]
			var n_indexes := indexes.size()
			if n_indexes == 0:
				continue
			asteroid_group.clear_for_import()
			asteroid_group.is_trojans = is_trojans # bypassing init
			asteroid_group.expand_arrays(n_indexes)
			for index in indexes:
				var name_: String = _asteroid_names[index]
				var keplerian_elements := []
				keplerian_elements.resize(7)
				var i := 0
				while i < 7:
					keplerian_elements[i] = _asteroid_elements[index * N_ELEMENTS + i]
					i += 1
				var magnitude: float = _asteroid_elements[index * N_ELEMENTS + 7]
				if not is_trojans:
					asteroid_group.set_data(name_, magnitude, keplerian_elements)
				else:
					var interm_trojan_elements: Array = _trojan_elements[index]
					var d: float = interm_trojan_elements[1]
					var D: float = interm_trojan_elements[2]
					var f: float = interm_trojan_elements[3]
					var th0: float = 0.0 # calculated on import
					var trojan_elements := [d, D, f, th0]
					asteroid_group.set_trojan_data(name_, magnitude, keplerian_elements, trojan_elements)
		
			var file_name := "%s.%s.%s" % [file_group, mag_str, BINARIES_EXTENSION]
			_update_status("%s (number indexes: %s)" % [file_name, n_indexes])
			var path := WRITE_BINARIES_DIR + "/" + file_name
			var binary := File.new()
			if binary.open(path, File.WRITE) != OK:
#				print("Could not write ", path)
				_update_status("Could not write " + path)
				return
			asteroid_group.write_binary(binary)
			binary.close()

	_update_status("%s asteroids written to binaries\n(of %s total)" % [added, tot_indexes])

func _start_over() -> void:
	_asteroid_elements.resize(0)
	_asteroid_names.clear()
	_iau_numbers.clear()
	_astdys2_lookup.clear()
	_index = 0
	yield(get_tree(), "idle_frame")
	for i in range(GRID_LAYOUT.size()):
		_status_labels[i].text = ""

func _close() -> void:
	hide()
	Global.program.Main.allow_run(self)

func _update_status(message) -> void:
	yield(get_tree(), "idle_frame")
	_status_labels[_function_index].text = message
	print(message)
	
func _read_astdys_cat_file(data_file: String) -> void:
	# _asteroid_elements contain N_ELEMENTS floats per index: the first
	# 7 elements of keplerian_elements, magnitude (after propers: s, g, L)
	# for each asteroid.
	var path := SOURCE_PATH + data_file
	var read_file := File.new()
	if read_file.open(path, File.READ) != OK:
#		print("Could not open ", path)
		_update_status("Could not open " + path)
		return
	var line := read_file.get_line()
	while line.substr(0, 1) != "!":
		line = read_file.get_line()
	line = read_file.get_line() # data starts after line starting with "!"
	var status_index := _index + STATUS_INTERVAL
	while not read_file.eof_reached():
		var line_array := line.split(" ", false)
		var mag_str: String = line_array[8]
		if mag_str == "-9.99":
			if REJECT_999:
				line = read_file.get_line()
				continue
			else:
				mag_str = "99"
		var astdys2_name: String = line_array[0]
		astdys2_name = astdys2_name.replace("'", "")
		_astdys2_lookup[astdys2_name] = _index
		_asteroid_names.append(astdys2_name)
		_asteroid_elements.append(float(line_array[2])) # a (in au)
		_asteroid_elements.append(float(line_array[3])) # e
		_asteroid_elements.append(deg2rad(float(line_array[4]))) # i
		_asteroid_elements.append(deg2rad(float(line_array[5]))) # Om
		_asteroid_elements.append(deg2rad(float(line_array[6]))) # w
		_asteroid_elements.append(deg2rad(float(line_array[7]))) # M0
		_asteroid_elements.append(0.0) # n; needed for proper orbits
		_asteroid_elements.append(float(mag_str)) # magnitude
		for _i in range(N_ELEMENTS - 8):
			 _asteroid_elements.append(0.0) # will be s, g, L from propers
		line = read_file.get_line()
		_index += 1
		if _index == status_index:
			_update_status(str(_index) + " total asteroids (current: " + astdys2_name + ")")
			status_index += STATUS_INTERVAL
	read_file.close()
	_update_status(str(_index) + " total asteroids")
