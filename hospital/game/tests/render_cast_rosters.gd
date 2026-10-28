extends SceneTree

var output:="E:/CODEX/2026-10-19/医院场景美术实装/outputs/人物逐位检视-最终"
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless": quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1080,1320)
	root.msaa_3d=Viewport.MSAA_4X
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("eee6d4")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("fff6e6");settings.ambient_light_energy=.55
	env.environment=settings;stage.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);sun.light_energy=.70;stage.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.45
	camera.position=Vector3(.25,2.20,9);stage.add_child(camera);camera.look_at(Vector3(0,1.83,0))
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	var groups:={"医生":[],"技术员与接待员":[],"患者":[]}
	for entry in manifest.characters:
		groups["医生" if entry.role=="doctor" else "患者" if entry.role=="patient" else "技术员与接待员"].append(entry)
	var files: Array=[]
	for group in groups:
		var entries: Array=groups[group]
		for start in range(0,entries.size(),6):
			var cast:=Node3D.new();stage.add_child(cast)
			for index in range(start,mini(start+6,entries.size())):
				var entry: Dictionary=entries[index]
				var local_index: int=index-start
				var person:=ActorView.new();person.entity_id="review_%03d" % int(str(entry.id).get_slice("-",1))
				cast.add_child(person)
				var role: String=entry.role
				person.present({"role":role,"disease_id":"echo","cell":0,"phase":"idle"},role!="patient")
				person.symptoms.hide();person.cure_feedback.hide();person.set_process(false)
				person.position=Vector3((local_index%3-1)*1.10,1.90 if local_index<3 else 0,0)
				person._body_root.rotation.y=-.12 if local_index%2 else .12
				var label:=Label3D.new();label.font=load("res://ui/theme.tres").default_font
				label.font_size=32;label.pixel_size=.0033;label.text=str(entry.id)
				label.modulate=Color("173f46");label.outline_size=0
				label.position=person.position+Vector3(0,-.09,.03);cast.add_child(label)
			for _i in range(3): await process_frame;await RenderingServer.frame_post_draw
			var path:=output.path_join("%s-%02d.png" % [group,start/6+1])
			if FileAccess.file_exists(path) or root.get_texture().get_image().save_png(path)!=OK: quit(1);return
			files.append({"file":path,"assets":entries.slice(start,mini(start+6,entries.size())).map(func(e: Dictionary)->String:return e.id)})
			stage.remove_child(cast);cast.queue_free()
	var file:=FileAccess.open(output.path_join("index.json"),FileAccess.WRITE);file.store_string(JSON.stringify(files,"  "));file.close()
	print("CAST ROSTERS: images=%d characters=%d" % [files.size(),manifest.characters.size()])
	quit()
