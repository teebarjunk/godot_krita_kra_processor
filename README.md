# Krita .kra processor in GDScript [alpha]
Process a .kra Krita file with pure GDScript without external libraries or dependencies.

```gdscript
var kra = KRAFile.new("path/to/file.kra")

# Print file names
kra.list_files()

# Get preview.png
var tex = kra.get_preview()

# Get mergedimage.png
var tex = kra.get_mergedimage()

kra.get_layer_child()
kra.get_layers_filtered()
kra.get_layer_descendants()
kra.get_layer_descendants_filtered()

kra.get_layer_shape_data()
kra.get_layer_shapes_as_polygons()
kra.get_all_shapes()

# Returns a node tree built from DOC/IMAGE
kra.get_as_node()

kra.layer_to_node()
kra.get_paintlayer(layer_id)
kra.get_shapelayer(layer_id)
kra.save_paintlayer()
kra.save_shapelayer()
```

## Layer Support
- Paint layers `paintlayer`
- Group layers `grouplayer`
- Shape layers `shapelayer`
	- Text doesn't seem to work.
- **TODO** Fill layers `generatorlayer`
- **TODO** Clone layers `clonelayers`
- **TODO** File layers `filelayer`

# Tags
- Add tags between `[]`: `layer_name [tag]`
- Seperate multiple tags with space: `[tag1 tag2]`
- Set tag value with `:`: `[tag:true tag2:0.1 group:player]`
- `.tag` will apply to all children.
- `..tag` will apply to parent.

|Tag|Example|Description|
|---|-------|-----------|
|group|`group:face,left`|Add node to group(s)|
|origin|`origin`|Center of this layer will become the origin of it's parent.|
|node|`node=Sprite2D`|Change from default `TextureRect`|
