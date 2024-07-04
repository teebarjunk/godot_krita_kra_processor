@tool
class_name Krita

enum ImageFormat { PNG, WEBP, JPEG }

class Bytes:
	var newline := "\n".to_ascii_buffer()[0]
	var bytes: PackedByteArray
	var index := 0
	
	func _init(bytes: PackedByteArray):
		self.bytes = bytes
	
	func next_byte() -> int:
		var byte := bytes[index]
		index += 1
		return byte
	
	func next_line() -> String:
		var next := bytes.find(newline, index)
		var result := bytes.slice(index, next)
		index = next + 1
		return result.get_string_from_ascii()
	
	func next_buffer(size: int) -> PackedByteArray:
		var output := bytes.slice(index, index+size)
		index += size + 1
		return output


class KraFile extends ZIPReader:
	var path: String
	var error: int
	var maindoc: XML
	var doc_image: Dictionary
	var size := Vector2i.ZERO
	var resolution := Vector2.ZERO
	
	var image_dir := "res://"
	var image_format := ImageFormat.PNG
	var image_quality := 0.8
	var image_lossy := false
	
	var layers_by_uuid := {}
	
	func _init(path: String):
		self.path = path
		error = open(path)
		
		if error == OK:
			var maindoc_xml := read_file("maindoc.xml")
			maindoc = XML.new(maindoc_xml)
			
			doc_image = maindoc.get_first("DOC/IMAGE")
			size.x = doc_image.width.to_int()
			size.y = doc_image.height.to_int()
			resolution.x = doc_image["x-res"].to_float()
			resolution.y = doc_image["y-res"].to_float()
			_preprocess_layer({}, doc_image)
			
			image_dir = path.get_base_dir().path_join(get_kra_name())
	
	func list_files():
		for file in get_files():
			print(file)
	
	func get_preview() -> ImageTexture:
		return _get_image("preview.png", 256, 256)
	
	func get_mergedimage() -> ImageTexture:
		return _get_image("mergedimage.png", size.x, size.y)
	
	func _get_image(file_path: String, w: int, h: int) -> ImageTexture:
		if file_exists(file_path):
			var bytes := read_file(file_path)
			var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
			return ImageTexture.create_from_image(image)
		push_error("No %s at %s." % [file_path, path])
		return null
	
	func get_layer_child(layer: Dictionary, child_path: String) -> Dictionary:
		var child := layer
		for part in child_path.split("/"):
			var _child := _get_child(child, part)
			if _child:
				child = _child
			else:
				push_error("No child %s in %s." % [child_path, layer.name])
				return {}
		return child
	
	func _get_child(layer: Dictionary, child_name: String) -> Dictionary:
		if "layers" in layer:
			for child in layer.layers:
				if child.name == child_name:
					return child
		return {}
	
	func dict_match(dict: Dictionary, filter: Dictionary) -> bool:
		for key in filter:
			if not key in dict or dict[key] != filter[key]:
				return false
		return true
	
	## Returns a list of all layers that have attributes matching the given filter.
	func get_layers_filtered(filter: Dictionary) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for layer in layers_by_uuid.values():
			if dict_match(layer, filter):
				out.append(layer)
		return out
	
	func get_layer_alpha(layer: Dictionary) -> float:
		return layer.get("opacity", "255.0").to_float() / 255.0
	
	func get_layer_visible(layer: Dictionary) -> bool:
		return layer.get("visible", "1") == "1"
	
	func get_layer_locked(layer: Dictionary) -> bool:
		return layer.get("locked", "1") == "1"
	
	func get_layer_blendmode(layer: Dictionary) -> int:
		match layer.get("compositeop", "normal"):
			"normal": return CanvasItemMaterial.BLEND_MODE_MIX
		push_error("Not imlpemented.")
		return -1
	
	func get_layer_descendants(layer: Dictionary) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		if "layers" in layer:
			for child in layer.layers:
				out.append(child)
				out.append_array(get_layer_descendants(child))
		return out
	
	func get_layer_descendants_filtered(layer: Dictionary, filter: Dictionary) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for child in get_layer_descendants(layer):
			if dict_match(child, filter):
				out.append(child)
		return out
	
	func get_layer_shape_data(layer: Dictionary) -> Dictionary:
		if not layer.nodetype == "shapelayer":
			push_error("Layer \"%s\" is not a \"shapelayer\" it's a \"%s\"." % [layer.name, layer.nodetype])
			return {}
		
		var layer_id: String = layer.filename
		var layer_path := "%s/layers/%s.shapelayer/content.svg" % [get_kra_name(), layer_id]
		if file_exists(layer_path):
			var layer_xml := XML.new(read_file(layer_path))
			return layer_xml.data["svg"][0]
		push_error("No shape layer data at %s." % layer_path)
		return {}
	
	func get_layer_shapes_as_polygons(layer: Dictionary) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		var shape_data := get_layer_shape_data(layer)
		for shape in shape_data.get("path", []):
			shape.polygon = SVG.path_to_polygon(shape)
			shape.erase("d")
			shape.erase("transform")
			out.append(shape)
		for shape in shape_data.get("ellipse", []):
			shape.polygon = SVG.ellipse_to_polygon(shape)
			shape.erase("d")
			shape.erase("transform")
			out.append(shape)
		for shape in shape_data.get("rect", []):
			shape.polygon = SVG.rect_to_polygon(shape)
			shape.erase("d")
			shape.erase("transform")
			out.append(shape)
		return out
	
	func get_all_shapes() -> Dictionary:
		var shapes := {}
		for file in get_files():
			if file.ends_with(".shapelayer/content.svg"):
				var layer_id := file.trim_prefix("%s/layers/" % get_kra_name()).trim_suffix(".shapelayer/content.svg")
				var layer_xml := XML.new(read_file(file))
				shapes[layer_id] = layer_xml.data["svg"][0]
		return shapes
	
	## Returns a node tree built from DOC/IMAGE.
	func get_as_node() -> Node:
		var scene := layer_to_node(doc_image)
		scene.name = doc_image.name
		scene.custom_minimum_size = size
		scene.size = size
		if "origin" in doc_image:
			scene.position = -doc_image.origin
			scene.pivot_offset = doc_image.origin
		return scene
	
	func _preprocess_layer(parent: Dictionary, layer: Dictionary):
		if "uuid" in layer:
			layers_by_uuid[layer.uuid] = layer
		
		# Fix layer nesting.
		if "layers" in layer:
			layer.layers = layer.layers[0].layer
			
			for sublayer in layer.layers:
				_preprocess_layer(layer, sublayer)
		
			for i in range(len(layer.layers)-1, -1, -1):
				if "origin" in layer.layers[i]:
					var id := get_paintlayer(layer.layers[i].filename)
					var img: Image = id.image
					layer["origin"] = id.position - img.get_size() * .5
					layer.layers.remove_at(i)
			
			if len(layer.layers) == 0:
				layer.erase("layers")
		
		# Fix layer name.
		var layer_name: String = layer.name
		if "[" in layer_name:
			var p := layer_name.split("[", true, 1)
			layer.name = p[0].strip_edges()
			
			if not layer.name:
				layer.name = "_unnamed_"
			
			var args := p[1].split("]", true, 1)[0].strip_edges()
			for arg in args.split(" "):
				var key: String
				var val
				if ":" in arg:
					var kv := arg.split(":", true, 1)
					key = kv[0]
					val = kv[1]
				else:
					key = arg
					val = true
				
				if key.begins_with(".."):
					key = key.trim_prefix("..")
					parent[key] = val
				elif key.begins_with("."):
					key = key.trim_prefix(".")
					if "layers" in layer:
						for sublayer in layer.layers:
							sublayer[key] = val
				else:
					layer[key] = val

	func layer_to_node(layer: Dictionary) -> Node:
		var layer_name: String = layer.name
		var layer_args := {}
		var layer_node: Node = null
		var layer_origin := layer.get("origin", Vector2.ZERO)
		
		if "nodetype" in layer:
			var layer_node_class: String
			
			if "node" in layer:
				layer_node_class = layer.node 
			elif "point" in layer:
				layer_node_class = "Node2D"
			else:
				match layer.nodetype:
					"grouplayer": layer_node_class = "Control"
					"paintlayer": layer_node_class = "TextureRect"
					"shapelayer": layer_node_class = "TextureRect"
					#"clonelayer": pass # TODO
					#"generatorlayer": pass # TODO
					var layer_type:
						push_error("%s layers not implemented." % layer_type)
						return
			
			layer_node = ClassDB.instantiate(layer_node_class)
			layer_node.name = layer_name
			layer_node.modulate.a = layer.opacity.to_float() / 255.0
			layer_node.visible = layer.visible == "1"
			
			if "group" in layer:
				for group in layer.group.split(","):
					layer_node.add_to_group(group, true)
			
			# Load texture.
			match layer.nodetype:
				"paintlayer":
					var image_data := get_paintlayer(layer.filename)
					if image_data:
						if "point" in layer:
							layer_node.position = layer_origin + image_data.position + image_data.image.get_size() * .5
						
						else:
							var image_path := save_paintlayer(image_data)
							apply_texture(layer_node, image_path)
							layer_node.position = layer_origin + image_data.position
				
				"shapelayer":
					var shape_data := get_shapelayer(layer.filename)
					if shape_data:
						var image_path := save_shapelayer(shape_data)
						apply_texture(layer_node, image_path)
						layer_node.position = layer_origin
		
		# DOC/IMAGE
		# Base node that others are a child of.
		else:
			layer_node = Control.new()
		
		# Update children.
		if "layers" in layer:
			var layers: Array = layer.layers
			for i in range(len(layers)-1, -1, -1):
				var node := layer_to_node(layers[i])
				if node:
					layer_node.add_child(node)
		
		return layer_node
	
	func apply_texture(node: Node, texture_path: String):
		if "texture" in node:
			var texture := load(texture_path)
			if texture:
				node.texture = texture
				
				if node is Sprite2D:
					node.offset = texture.get_size() * .5
		else:
			push_error("Couldn't apply texture %s to %s." % [texture_path, node])
		
	func get_kra_name() -> String:
		return path.get_basename().get_file()
	
	func get_paintlayer(layer_id: String) -> Dictionary:
		var layer_path := "%s/layers/%s" % [get_kra_name(), layer_id]
		if not file_exists(layer_path):
			push_error("No pixellayer %s in %s." % [layer_path, path])
			return {}
		
		var bytes := Bytes.new(read_file(layer_path))
		
		var version := bytes.next_line().split(" ", true, 1)[1].to_int()
		var tile_width := bytes.next_line().split(" ", true, 1)[1].to_int()
		var tile_height := bytes.next_line().split(" ", true, 1)[1].to_int()
		var pixel_size := bytes.next_line().split(" ", true, 1)[1].to_int()
		var tile_count := bytes.next_line().split(" ", true, 1)[1].to_int()
		
		var image: Image
		var position := Vector2.ZERO
		
		if tile_count == 0:
			image = Image.create(1, 1, false, Image.FORMAT_RGB8)
			image.set_pixel(0, 0, Color.TRANSPARENT)
		
		else:
			var uncompressed_size := tile_width * tile_height * pixel_size + 1
			var tiles := []
			var minx := 999999
			var miny := 999999
			var maxx := -999999
			var maxy := -999999
			
			for i in range(tile_count):
				var line := bytes.next_line()
				if line == "":
					break
				
				var split_data := line.split(",")
				var tile_x := split_data[0].to_int()
				var tile_y := split_data[1].to_int()
				var compress_type := split_data[2]
				var compress_size := split_data[3].to_int() - 1
				var compressed := bytes.next_byte() # TODO
				var tile_bytes := bytes.next_buffer(compress_size)
				minx = mini(tile_x, minx)
				miny = mini(tile_y, miny)
				maxx = maxi(tile_x + tile_width, maxx)
				maxy = maxi(tile_y + tile_height, maxy)
				
				var new_bytes := PackedByteArray()
				new_bytes.resize(uncompressed_size)
				_decompress_lzf(tile_bytes, new_bytes)
				bytes.index -= 1 # TODO: Understand why this is needed???
				tiles.append([tile_x, tile_y, new_bytes])
			
			var image_width := maxx - minx
			var image_height := maxy - miny
			var step := uncompressed_size / 4
			var off_g := step
			var off_r := step * 2
			var off_a := step * 3
			
			var clrs := PackedByteArray()
			clrs.resize(image_width * image_height * 4)
			
			var alpha_min_x := image_width
			var alpha_min_y := image_height
			var alpha_max_x := 0
			var alpha_max_y := 0
			
			for tile in tiles:
				var tile_x: int = tile[0]
				var tile_y: int = tile[1]
				var tile_bytes: PackedByteArray = tile[2]
				for ty in tile_height:
					for tx in tile_width:
						var i := ty * tile_width + tx
						var image_x := tile_x + tx - minx
						var image_y := tile_y + ty - miny
						var pixel_offset: int = (image_y * image_width + image_x) * 4
						var r := tile_bytes[i + off_r]
						var g := tile_bytes[i + off_g]
						var b := tile_bytes[i]
						var a := tile_bytes[i + off_a]
						clrs[pixel_offset + 0] = r
						clrs[pixel_offset + 1] = g
						clrs[pixel_offset + 2] = b
						clrs[pixel_offset + 3] = a
						
						# Does pixel contain data?
						if a > 0 or r > 0 or g > 0 or b > a:
							alpha_min_x = mini(alpha_min_x, image_x)
							alpha_min_y = mini(alpha_min_y, image_y)
							alpha_max_x = maxi(alpha_max_x, image_x)
							alpha_max_y = maxi(alpha_max_y, image_y)
			
			# Create image.
			image = Image.create_from_data(image_width, image_height, false, Image.FORMAT_RGBA8, clrs)
			# Crop to non transparent area.
			image = image.get_region(Rect2i(alpha_min_x, alpha_min_y, alpha_max_x-alpha_min_x, alpha_max_y-alpha_min_y))
			
			position = Vector2(minx + alpha_min_x, miny + alpha_min_y)
		
		return { image=image, position=position, layer_id=layer_id }
	
	func _decompress_lzf(indata: PackedByteArray, outdata: PackedByteArray) -> void:
		var iidx := 0
		var oidx := 0
		var in_len := len(indata)
		
		while iidx < in_len:
			var ctrl := indata[iidx]
			iidx += 1
			
			if ctrl < 32:
				for i in ctrl + 1:
					outdata[oidx] = indata[iidx]
					oidx += 1
					iidx += 1
			else:
				var lenn := ctrl >> 5
				if lenn == 7:
					lenn += indata[iidx]
					iidx += 1
				
				var ref := oidx - ((ctrl & 0x1f) << 8) - indata[iidx] - 1
				iidx += 1
				
				for i in lenn + 2:
					outdata[oidx] = outdata[ref]
					oidx += 1
					ref += 1
	
	func get_shapelayer(layer_id: String) -> Dictionary:
		var layer_path := "%s/layers/%s.shapelayer/content.svg" % [get_kra_name(), layer_id]
		if not file_exists(layer_path):
			push_error("No shape layer %s in %s." % [layer_path, path])
			return {}
		var bytes := read_file(layer_path)
		return { bytes=bytes, layer_id=layer_id }
	
	func _create_directory(dir: String):
		var d := DirAccess.open("res://")
		if not d.dir_exists(dir):
			d.make_dir_recursive(dir)
	
	## Returns path file was saved to.
	func save_paintlayer(data: Dictionary) -> String:
		var save_path := image_dir.path_join(data.layer_id)
		match image_format:
			ImageFormat.PNG: save_path += ".png"
			ImageFormat.WEBP: save_path += ".webp"
			ImageFormat.JPEG: save_path += ".jpeg"
		_create_directory(save_path.get_base_dir())
		if Krita.save_image(data.image, save_path, image_quality, image_lossy):
			return save_path
		return ""
	
	## Returns path file was saved to.
	func save_shapelayer(data: Dictionary) -> String:
		var save_path := image_dir.path_join(data.layer_id) + ".svg"
		_create_directory(save_path.get_base_dir())
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		file.store_buffer(data.bytes)
		
		# HACK: Forcibly edit import setting for SVG scale (pixels per inch).
		if Engine.is_editor_hint():
			var import_path := save_path + ".import"
			var import_settings := ConfigFile.new()
			if FileAccess.file_exists(import_path):
				import_settings.load(import_path)
			var svg_scale := resolution.x / 100.0
			import_settings.set_value("params", "svg/scale", svg_scale)
			import_settings.save(import_path)
		
		return save_path

static func _set_owner_recursive(node: Node, owner: Node):
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)

## Returns the path it was saved to.
static func save_image(image: Image, save_path: String, quality := 0.8, lossy := false) -> bool:
	if save_path.begins_with("res://"):
		# Create dir if it doesn't exist.
		var dir := DirAccess.open("res://")
		var base_dir := save_path.get_base_dir()
		if not dir.dir_exists_absolute(base_dir):
			dir.make_dir_absolute(base_dir)
		
		match save_path.get_extension():
			"png": return OK == image.save_png(save_path)
			"webp": return OK == image.save_webp(save_path, lossy, quality)
			"jpg", "jpeg": return OK == image.save_jpg(save_path, quality)
			var bad_form: push_error("Unsupported image format '%s'" % [bad_form])
	else:
		push_error("Images must be saved into res://. (Tried saving to %s)" % save_path)
	return false

