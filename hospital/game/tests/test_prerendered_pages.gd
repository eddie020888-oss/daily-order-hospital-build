extends SceneTree
const DIRECTORY := "res://assets/characters-prerendered/doctor-02-clean-hq-v2"
var passed := 0
var failed := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	if value:passed+=1
	else:failed+=1
	print(("PAGES PASS: " if value else "PAGES FAIL: ")+label)
func _run() -> void:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+"/manifest.json"))
	var body := PrerenderedCharacter.create_from_manifest("doctor-02",data,DIRECTORY)
	check(body!=null,"high resolution version 2 pages create an actual body")
	if body==null:quit(1);return
	root.add_child(body);body.set_process(false)
	check(is_equal_approx(body.sprite.pixel_size,2.0/512),"high resolution pixels keep original world size")
	for direction in range(8):
		body.present_state("Walk",TAU*direction/8,1)
		check(body.sprite.texture.resource_path.ends_with("walk-%d.png" % (direction/2)),"heading %d loads its own page" % direction)
		check(body.sprite.region_rect.end.x<=1536 and body.sprite.region_rect.end.y<=2048,"heading %d stays in its page" % direction)
	body.present_state("Walk",TAU*3/8,1)
	body.advance_animation(.81)
	check(body.frame_index==6 and body.sprite.region_rect==Rect2(768,1536,384,512),"frame six uses second row of the actual direction page")
	var time := body.animation_time
	body.present_state("Walk",PI,1)
	check(body.frame_index==6 and is_equal_approx(time,body.animation_time) and body.sprite.region_rect==Rect2(768,512,384,512),"page turn preserves gait phase and chooses the correct region")
	body.present_state("Idle",TAU*7/8,1)
	check(body.sprite.texture.resource_path.ends_with("idle-1.png") and body.sprite.region_rect==Rect2(0,1536,384,512),"idle uses its four-directions-per-page layout")
	var other := PrerenderedCharacter.create_from_manifest("doctor-02",data,DIRECTORY)
	root.add_child(other);other.set_process(false)
	body.present_state("Walk",0,1);other.present_state("Walk",TAU/8,1)
	check(body.sprite.texture==other.sprite.texture,"actors on the same active page share a texture")
	for mutation in ["pages","columns","rows_per_direction","directions_per_page"]:
		var invalid: Dictionary=data.duplicate(true);invalid.clips.Walk.erase(mutation)
		var rejected := PrerenderedCharacter.create_from_manifest("doctor-02",invalid,DIRECTORY)
		check(rejected==null,"missing layout "+mutation+" falls back")
		if rejected!=null:rejected.free()
	var legacy: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters-prerendered/doctor-02/manifest.json"))
	var old := PrerenderedCharacter.create_from_manifest("doctor-02",legacy,"res://assets/characters-prerendered/doctor-02")
	check(old!=null,"existing version one assets still load")
	if old!=null:old.free()
	body.free();other.free()
	print("PAGES RESULT: passed=%d failed=%d" % [passed,failed])
	quit(1 if failed else 0)
