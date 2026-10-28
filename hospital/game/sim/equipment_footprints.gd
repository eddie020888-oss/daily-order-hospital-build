class_name EquipmentFootprints
extends RefCounted

## Version 2 geometry for NEW layouts. Legacy templates/save data are not
## reinterpreted here. One game cell is one metre of floor, not a clinical
## standard. Every body cell is hard-blocking; maintenance clearance remains
## walkable and must not be occupied by furniture. Patient/staff slots stay
## outside the body; a future seated animation does not change these slots.
## package_cost is the EXISTING facility base-package price, not a new price
## for a single machine. Reception is one two-cell combination (two old pods
## may occupy its two cells separately).

const VERSION := 2
const METRES_PER_CELL := 1.0
const RECOVERY_UPGRADE_COST := 400
const _PROFILES := {
	"reception":{
		"body_size":Vector2i(2,1),"minimum_room":Vector2i(3,3),"recommended_room":Vector2i(4,3),
		"package_cost":400,"tier":1,
		"reason":"基础接待组合保留两格台面；可用两个各占一格的原单台组合，患者与员工操作位另留。",
	},
	"diagnosis":{
		"body_size":Vector2i(2,2),"minimum_room":Vector2i(3,4),"recommended_room":Vector2i(4,4),
		"package_cost":800,"tier":2,
		"reason":"诊断设施采用二乘二本体，匹配工作站的重要性与外形；操作位外置，侧面保留可通行维护带。",
	},
	"echo":{
		"body_size":Vector2i(3,2),"minimum_room":Vector2i(4,4),"recommended_room":Vector2i(5,5),
		"package_cost":1000,"tier":2,
		"reason":"声环圆盘、双侧喇叭与底座需要宽幅本体；三乘二硬阻挡，正面操作与维护净空另计。",
	},
	"motion":{
		"body_size":Vector2i(3,3),"minimum_room":Vector2i(4,5),"recommended_room":Vector2i(5,5),
		"package_cost":1200,"tier":3,
		"reason":"动作校准设施由平台、扶栏与多向器械构成，三乘三本体体现较高阶设施的规模，操作位不并入阻挡。",
	},
	"sensory":{
		"body_size":Vector2i(2,3),"minimum_room":Vector2i(3,5),"recommended_room":Vector2i(4,5),
		"package_cost":1400,"tier":3,
		"reason":"感官分轨设施保留座舱的纵向体量，采用二乘三本体与侧方维护带，避免按售价统一套用两格。",
	},
	"recovery":{
		"body_size":Vector2i(1,2),"minimum_room":Vector2i(3,3),"recommended_room":Vector2i(3,4),
		"package_cost":600,"tier":1,
		"reason":"单席恢复设施为一乘二本体；升级在横向第二席增加同尺寸本体，两个服务位均在本体外。",
	},
	"general_exam":{
		"body_size":Vector2i(1,1),"minimum_room":Vector2i(4,4),"recommended_room":Vector2i(4,4),
		"package_cost":900,"tier":2,
		"reason":"综合诊察车占一格；患者与医生在车外操作，保留绕行空间。",
	},
	"pharmacy":{
		"body_size":Vector2i(3,1),"minimum_room":Vector2i(4,4),"recommended_room":Vector2i(4,4),
		"package_cost":1000,"tier":2,
		"reason":"自动发药机采用三乘一本体；取药与护理操作位在正面，不能被家具占用。",
	},
	"ward":{
		"body_size":Vector2i(5,3),"minimum_room":Vector2i(5,5),"recommended_room":Vector2i(5,5),
		"package_cost":1800,"tier":2,
		"reason":"两张各二乘三的留观床分列两侧，中间保留一格通道；两个服务位与护理位均在床外。",
	},
}
const _STATION_EXTRAS := {
	"reception":{
		"service_cells":[[0,1]],"staff_cells":[[1,1]],
		"upgrade_equipment_cells":[],"upgrade_service_cells":[],"clearance_cells":[],
	},
	"diagnosis":{
		"service_cells":[[0,2]],"staff_cells":[[1,2]],
		"upgrade_equipment_cells":[],"upgrade_service_cells":[],"clearance_cells":[[2,0],[2,1],[2,2]],
	},
	"echo":{
		"service_cells":[[1,2]],"staff_cells":[[2,2]],
		"upgrade_equipment_cells":[],"upgrade_service_cells":[],"clearance_cells":[[0,2]],
	},
	"motion":{
		"service_cells":[[1,3]],"staff_cells":[[2,3]],
		"upgrade_equipment_cells":[],"upgrade_service_cells":[],"clearance_cells":[[0,3]],
	},
	"sensory":{
		"service_cells":[[0,3]],"staff_cells":[[1,3]],
		"upgrade_equipment_cells":[],"upgrade_service_cells":[],"clearance_cells":[[2,0],[2,1],[2,2],[2,3]],
	},
	"recovery":{
		"service_cells":[[0,2]],"staff_cells":[],
		"upgrade_equipment_cells":[[2,0],[2,1]],"upgrade_service_cells":[[2,2]],"clearance_cells":[],
	},
	"general_exam":{
		"service_cells":[[0,1]],"staff_cells":[[1,1]],
		"upgrade_equipment_cells":[],"upgrade_service_cells":[],"clearance_cells":[[1,0]],
	},
	"pharmacy":{
		"service_cells":[[1,1]],"staff_cells":[[2,1]],
		"upgrade_equipment_cells":[],"upgrade_service_cells":[],"clearance_cells":[[0,1]],
	},
	"ward":{
		"service_cells":[[1,3],[3,3]],"staff_cells":[[4,3]],
		"upgrade_equipment_cells":[],"upgrade_service_cells":[],"clearance_cells":[[2,0],[2,1],[2,2],[2,3]],
	},
}
const _FURNITURE_SIZES := {"plant":Vector2i(1,1),"bench":Vector2i(2,1),"cabinet":Vector2i(1,1),"bin":Vector2i(1,1)}
const _FURNITURE_PRICES := {"plant":50,"bench":80,"cabinet":100,"bin":30}


static func profile(kind:String) -> Dictionary:
	if not _PROFILES.has(kind):
		return {}
	return _PROFILES[kind].duplicate(true)


static func station(kind:String) -> Dictionary:
	if not _PROFILES.has(kind):
		return {}
	var result:Dictionary=_STATION_EXTRAS[kind].duplicate(true)
	result["equipment_cells"]=_rectangle(_PROFILES[kind].body_size)
	if kind=="ward":
		# body_size is the assembly envelope, not a solid rectangle. The two
		# independent 2x3 beds must never turn the middle aisle into an obstacle.
		result["equipment_cells"]=[[0,0],[1,0],[0,1],[1,1],[0,2],[1,2],[3,0],[4,0],[3,1],[4,1],[3,2],[4,2]]
	return result


static func minimum_room(kind:String) -> Vector2i:
	if not _PROFILES.has(kind):
		return Vector2i.ZERO
	return _PROFILES[kind].minimum_room


static func fits_room(kind:String,width:int,height:int) -> bool:
	if not _PROFILES.has(kind) or width<=0 or height<=0:
		return false
	var size:Vector2i=minimum_room(kind)
	return (width>=size.x and height>=size.y) or (width>=size.y and height>=size.x)


static func body_label(kind:String) -> String:
	if not _PROFILES.has(kind):
		return ""
	if kind=="ward":return "双床 · 每床 2×3 · 共12格"
	var size:Vector2i=_PROFILES[kind].body_size
	return "本体 %d×%d · %d格" % [size.x,size.y,size.x*size.y]


static func furniture_size(kind:String,rotation:int=0) -> Vector2i:
	if not _FURNITURE_SIZES.has(kind) or rotation<0 or rotation>3:
		return Vector2i.ZERO
	var size:Vector2i=_FURNITURE_SIZES[kind]
	return Vector2i(size.y,size.x) if rotation%2==1 else size


## Returns the full occupied rectangle INCLUDING item.x/y translation. Invalid
## or fractional placements return []; room-boundary validation stays with the
## caller. Rotation changes the rectangle axes while retaining its top-left.
static func furniture_cells(item:Dictionary) -> Array[Array]:
	var result:Array[Array]=[]
	if not item.get("kind",null) is String:
		return result
	for key in ["x","y","rotation"]:
		if not item.get(key,null) is int:
			return result
	if item.x<0 or item.y<0:
		return result
	var size:Vector2i=furniture_size(item.kind,item.rotation)
	for y in range(size.y):
		for x in range(size.x):
			result.append([item.x+x,item.y+y])
	return result


static func furniture_price(kind:String) -> int:
	return _FURNITURE_PRICES.get(kind,0)


static func _rectangle(size:Vector2i) -> Array[Array]:
	var result:Array[Array]=[]
	for y in range(size.y):
		for x in range(size.x):
			result.append([x,y])
	return result
