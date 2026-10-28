extends SceneTree

var failed := 0
var passed := 0
const DIRECTORY := "res://assets/characters-prerendered/doctor-02-clean-hq-v2"

func _initialize() -> void: _run.call_deferred()

func check(value: bool,label: String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("MANIFEST PASS: " if value else "MANIFEST FAIL: ")+label)

func _run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+"/manifest.json"))
	var good := PrerenderedCharacter.create_from_manifest("doctor-02",data,DIRECTORY)
	check(good!=null and good.get_child_count()==2,"complete data constructs the actual sprite and shadow")
	if good!=null:good.free()
	for field in ["pixel_size","center_height","ortho_height","camera_offset","clips","frame_size"]:
		var missing := data.duplicate(true);missing.erase(field)
		rejected(missing,"missing "+field+" falls back before constructing a partial body")
	for offset in [[],[0,1,0],[0,0,0],[8.5,"bad",23],[8.5,19,23,0]]:
		var invalid := data.duplicate(true);invalid.camera_offset=offset
		rejected(invalid,"invalid camera offset is rejected: "+str(offset))
	for scale_value in [0,-1,INF,NAN,"bad"]:
		var invalid := data.duplicate(true);invalid.pixel_size=scale_value
		rejected(invalid,"invalid pixel scale is rejected: "+str(scale_value))
	var invalid := data.duplicate(true);invalid.frame_size=[192.5,256]
	rejected(invalid,"fractional frame dimensions cannot silently truncate")
	invalid=data.duplicate(true);invalid.clips.Walk=[]
	rejected(invalid,"non-dictionary clip is rejected")
	invalid=data.duplicate(true);invalid.clips.Walk.frames=8.5
	rejected(invalid,"fractional frame count is rejected")
	invalid=data.duplicate(true);invalid.clips.Walk.duration=INF
	rejected(invalid,"non-finite duration is rejected")
	invalid=data.duplicate(true);invalid.clips.Walk.texture="missing.png"
	rejected(invalid,"missing atlas falls back")
	invalid=data.duplicate(true);invalid.clips.Walk.texture="portrait.png";invalid.clips.Walk.pages[0]="portrait.png"
	rejected(invalid,"real texture dimensions must match declared walk frames")
	invalid=data.duplicate(true);invalid.clips.Walk.atlas_size=[0,0]
	rejected(invalid,"invalid declared atlas dimensions are rejected")
	invalid=data.duplicate(true);invalid.clips.Walk.texture="../doctor-02/walk.png"
	rejected(invalid,"atlas path must stay a basename in its character directory")
	rejected(null,"malformed JSON result falls back")
	print("MANIFEST RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)

func rejected(data: Variant,label: String) -> void:
	var result := PrerenderedCharacter.create_from_manifest("doctor-02",data,DIRECTORY)
	check(result==null,label)
	if result!=null:result.free()
