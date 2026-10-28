class_name GridEquipmentFrames
extends RefCounted

## Art-only manifest: no simulation or save schema is changed. Source corners
## are ordered in WORLD ground axes, not around the apparatus' local yaw.
const MANIFEST:="res://assets/equipment/grid-isometric-v3/frames.json"
const CATALOG_MANIFEST:="res://assets/equipment/catalog-isometric-v1/catalog.json"
const CATALOG_IDS:={"general_exam":"U01-E1","pharmacy":"U28-E1","ward":"U23-E1"}
static var _frames:Dictionary={}
static var _loaded:=false
static var _catalog_items:Dictionary={}
static var _catalog_loaded:=false

static func frame(kind:String,quarter:int) -> Dictionary:
	if CATALOG_IDS.has(kind) or has_catalog(kind):return _catalog_frame(kind,quarter)
	if not _loaded:
		_loaded=true
		if FileAccess.file_exists(MANIFEST):
			var document:Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
			if document is Dictionary and document.get("version")==1 and document.get("frames") is Dictionary:_frames=document.frames
	var raw:Dictionary=_frames.get("%s-q%d"%[kind,quarter],{})
	if raw.is_empty():
		if kind=="echo" and quarter==0:
			return {"path":"res://assets/equipment/grid-isometric-v2/echo-q0.png","enabled":true,"pixel_size":.0035,"foot_px":Vector2(670,831),"ground_corners_px":GridEquipmentProjection.SOURCE_CORNERS.duplicate(),"body_size":Vector2(3,2)}
		return {"path":"","enabled":false}
	if not raw.get("path") is String or not raw.get("corners") is Array or raw.corners.size()!=4:return {"path":"","enabled":false}
	var corners:Array[Vector2]=[]
	for point in raw.corners:
		if not point is Array or point.size()!=2:return {"path":"","enabled":false}
		corners.append(Vector2(float(point[0]),float(point[1])))
	var body:Vector2=EquipmentFootprints.profile(kind).get("body_size",Vector2i.ZERO)
	if quarter%2:body=Vector2(body.y,body.x)
	return {"path":raw.path,"enabled":true,"pixel_size":.0035,"foot_px":(corners[0]+corners[2])*.5,"ground_corners_px":corners,"body_size":body}

static func _catalog_frame(kind:String,quarter:int) -> Dictionary:
	if quarter<0 or quarter>3:return {"path":"","enabled":false}
	_load_catalog()
	var catalog_id:String=CATALOG_IDS.get(kind,kind)
	var entry:Dictionary=_catalog_items.get(catalog_id,{})
	for view:Variant in entry.get("views",[]):
		if not view is Dictionary or view.get("quarter",-1)!=quarter:continue
		if not view.get("path") is String or not view.get("corners") is Array or view.corners.size()!=4 or not view.get("body_size") is Array or view.body_size.size()!=2:break
		var corners:Array[Vector2]=[]
		for point:Variant in view.corners:
			if not point is Array or point.size()!=2:return {"path":"","enabled":false}
			corners.append(Vector2(float(point[0]),float(point[1])))
		return {"path":view.path,"enabled":true,"pixel_size":.0035,"foot_px":(corners[0]+corners[2])*.5,"ground_corners_px":corners,"body_size":Vector2(view.body_size[0],view.body_size[1]),"catalog_id":entry.id}
	return {"path":"","enabled":false}

static func has_catalog(kind:String) -> bool:
	_load_catalog()
	return _catalog_items.has(CATALOG_IDS.get(kind,kind))

static func catalog_item(kind:String) -> Dictionary:
	_load_catalog()
	return _catalog_items.get(CATALOG_IDS.get(kind,kind),{}).duplicate(true)

static func _load_catalog() -> void:
	if not _catalog_loaded:
		_catalog_loaded=true
		if FileAccess.file_exists(CATALOG_MANIFEST):
			var document:Variant=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_MANIFEST))
			if document is Dictionary and document.get("items") is Array:
				for item:Variant in document.items:
					if item is Dictionary and item.get("id") is String:_catalog_items[item.id]=item
