class_name CampaignBuildController
extends RefCounted

signal changed(view:Dictionary)
signal active_changed(value:bool)
signal preview_changed(proposal:Dictionary,result:Dictionary)
signal committed(result:Dictionary)
var session:GameSession
var world:HospitalWorld
var draft:CampaignBuildDraft
var active:bool:
	get:return draft!=null
var _gui_hit:Callable
var _receipt:=""
var _submitting:=false
var _generation:=0
var _pending_confirm:Dictionary={}
var _pending_advance:Dictionary={}
var _manual_openings:=false
var _snapshot:Dictionary={}
var _projection:Dictionary={}
var _owner_sim:Simulation
var _fingers:Dictionary={}
var _start:Dictionary={}
var _blocked:Dictionary={}
var _gesture_generation:Dictionary={}
var _dragged:=false
var _multitouch:=false
var _mouse_down:=false
var _draw_backup:Dictionary={}
var _draw_first:=-1
var _draw_last:=-1
var _draw_move:=false
var _preview_signature:=""
var _option_key:=""
var _option_cache:Array=[]
const BUILD_SNAP_MARGIN:=0.15

func initialize(owner_session:GameSession,view:HospitalWorld=null,gui_hit:Callable=Callable()) -> void:
	session=owner_session;world=view;_gui_hit=gui_hit;_owner_sim=session.sim

func _available(kind:String,snapshot:Dictionary={}) -> bool:
	if session==null or not session.is_campaign() or not session.catalog.campaign.facilities.has(kind):return false
	return not session.is_long_campaign() or LongCampaign.facility_unlocked(snapshot if not snapshot.is_empty() else session.sim.snapshot(),session.catalog,kind)

func begin_build(kind:String) -> bool:
	return _begin("build",kind,"")

func begin_install(kind:String,room_id:String) -> bool:
	return _begin("install",kind,room_id)

func begin_edit(room_id:String) -> bool:
	return _begin("edit","",room_id)

func _begin(mode:String,kind:String,room_id:String) -> bool:
	if session==null or session.storage_blocked or not session.is_campaign() or session.sim.snapshot().challenge.status!="running":return false
	var room:Dictionary=session.sim.snapshot().rooms.get(room_id,{})
	if mode!="build" and room.is_empty():return false
	if mode!="edit" and not _available(kind):return false
	if mode=="install" and str(room.unit_id)!=str(session.catalog.campaign.facilities[kind].unit_id):return false
	cancel()
	draft=CampaignBuildDraft.new();draft.initialize(mode,kind,room)
	_manual_openings=mode=="edit"
	_receipt=session.reserve_command_id();_owner_sim=session.sim
	active_changed.emit(true);present()
	return true

func cancel() -> void:
	_drop_confirm_request()
	var was_active:=active
	draft=null;_receipt="";_submitting=false;_projection={};_preview_signature=""
	_manual_openings=false
	_reset_pointers()
	if was_active:
		preview_changed.emit({},{"ok":false,"code":"cancelled","data":{}})
		changed.emit({"active":false});active_changed.emit(false)

func reset_input() -> void:
	cancel()

func _reset_pointers() -> void:
	_fingers.clear();_start.clear();_blocked.clear();_gesture_generation.clear();_dragged=false;_multitouch=false;_mouse_down=false
	_draw_backup={};_draw_first=-1;_draw_last=-1;_draw_move=false

func choose_cell(cell:int) -> void:
	if not active:return
	_drop_confirm_request()
	draft.choose_cell(cell);present()

func choose_wall(side:String,offset:int) -> void:
	if not active:return
	_drop_confirm_request()
	draft.choose_wall(side,offset);present()

func select_opening_tool(tool:String) -> void:
	if not active:return
	_drop_confirm_request()
	if draft.step==1 and tool in ["door","window","move","remove"]:_manual_openings=true
	draft.select_opening_tool(tool);present()

func choose_facility(kind:String) -> bool:
	if not active or draft.step!=3 or not _available(kind):return false
	var unit:String=str(session.catalog.campaign.facilities[kind].unit_id)
	if unit!=draft.unit_id and unit!="operations":return false
	_drop_confirm_request();draft.choose_facility(kind);present();return true

func select_facility(index:int) -> void:
	if not active:return
	_drop_confirm_request()
	draft.select_facility(index);present()

func remove_selected() -> bool:
	if not active:return false
	_drop_confirm_request()
	var removed:bool=draft.remove_selected()
	present()
	return removed

func adjust_bounds(size_delta:Vector2i,offset:Vector2i=Vector2i.ZERO) -> bool:
	if not active:return false
	_drop_confirm_request()
	var adjusted:bool=draft.adjust_bounds(size_delta,offset)
	present()
	return adjusted

func rotate() -> void:
	if active:_drop_confirm_request();draft.rotate();present()

func back() -> void:
	if not active:return
	_drop_confirm_request()
	draft.step=maxi(2 if draft.mode=="install" else 0,draft.step-1)
	if draft.step==1:_manual_openings=true
	present()

func advance() -> bool:
	if not active:return false
	_drop_confirm_request()
	present()
	if not bool(_projection.get("can_advance",false)):return false
	draft.step+=1;present();return true

func _estimate(_snapshot_value:Dictionary) -> int:
	var cost:=0
	if draft.mode=="build":cost=150+maxi(0,int(draft.layout.width)*int(draft.layout.height))*8
	elif not draft.original_layout.is_empty():cost=maxi(0,int(draft.layout.width)*int(draft.layout.height)-int(draft.original_layout.width)*int(draft.original_layout.height))*8
	for item:Dictionary in draft.layout.facilities:
		if not draft._preserved(str(item.id)):cost+=int(session.catalog.campaign.facilities.get(item.kind,{}).get("cost",0))
	return cost

func present(snapshot:Dictionary={}) -> Dictionary:
	if not active:return {"active":false}
	if _submitting:return _projection
	if session.sim!=_owner_sim or session.storage_blocked:cancel();return {"active":false}
	_snapshot=snapshot if not snapshot.is_empty() else session.sim.snapshot()
	var proposal:Dictionary=draft.proposal()
	var signature:String=JSON.stringify([proposal,draft.step,draft.selected_index,draft.selected_kind,draft.opening_tool,draft.selected_opening,draft.bounds_issue,_generation,_pending_confirm.is_empty(),_snapshot.tick,_snapshot.get("command_sequence",0)])
	if signature==_preview_signature:return _projection
	_preview_signature=signature
	var preview:Dictionary=FacilityLayout.preview(_snapshot,proposal)
	var quote:int=_estimate(_snapshot)
	var bounds_error:String=draft.bounds_error(_snapshot)
	var ready:bool=draft.required_placed()
	# Clone-only command validation supplies the same financial/locked/busy
	# gates as confirmation; the running simulation and receipts are untouched.
	if preview.get("ok",false):
		var state:=ClinicState.new();state.data=_snapshot.duplicate(true)
		var command:Dictionary=draft.command();command.id="__campaign_scene_quote__"
		while state.data.command_receipts.has(command.id):command.id+="_"
		var checked:Dictionary=CampaignCommands.apply(state,session.catalog,command)
		if checked.get("ok",false):quote=int(checked.get("data",{}).get("cost",quote))
		else:preview={"ok":false,"code":checked.code,"data":preview.get("data",{}),"detail":checked.get("data",{})}
	var can_advance:=false
	match draft.step:
		0:can_advance=bounds_error==""
		1:can_advance=bool(preview.get("ok",false)) and not draft.layout.doors.is_empty()
		2:can_advance=bool(preview.get("ok",false)) and ready
	var names:Dictionary=session.catalog.campaign.facilities
	var option_key:String=JSON.stringify([draft.unit_id,_snapshot.level_id,_snapshot.get("schema_version",0),_snapshot.campaign.get("phase_index",-1)])
	if option_key!=_option_key:
		_option_key=option_key;_option_cache=[]
		for kind:String in names:
			var item:Dictionary=names[kind]
			if str(item.unit_id) not in [draft.unit_id,"operations"] or not _available(kind,_snapshot):continue
			_option_cache.append({"id":kind,"name":str(item.name),"cost":int(item.cost)})
	var options:Array=_option_cache

	_projection={"active":true,"mode":draft.mode,"step":draft.step,"kind":draft.kind,"name":str(names.get(draft.kind,{}).get("name","科室")),"unit_id":draft.unit_id,"room_id":draft.room_id,"proposal":proposal,"preview":preview,"bounds_error":bounds_error,"bounds_issue":draft.bounds_issue,"queued_confirm":not _pending_confirm.is_empty(),"can_advance":can_advance,"can_confirm":draft.step==3 and ready and preview.get("ok",false) and not _submitting and _pending_confirm.is_empty(),"quote":quote,"cash":int(_snapshot.cash),"balance":int(_snapshot.cash)-quote,"opening_tool":draft.opening_tool,"selected_index":draft.selected_index,"selected_kind":draft.selected_kind,"options":options}
	changed.emit(_projection.duplicate(true));preview_changed.emit(proposal.duplicate(true),preview.duplicate(true))
	return _projection

func view() -> Dictionary:
	return present().duplicate(true)

func _drop_confirm_request() -> void:
	_generation+=1
	_pending_confirm={}
	_pending_advance={}
	_preview_signature=""

func _queue_auto_advance(step:int) -> void:
	if not active or _submitting or not _fingers.is_empty() or step not in [1,2] or draft.step!=step:return
	if step==1 and _manual_openings:return
	var projection:Dictionary=present()
	if not active or not projection.get("can_advance",false) or not projection.get("preview",{}).get("ok",false):return
	_pending_advance={"receipt":_receipt,"generation":_generation,"step":step,"intent":JSON.stringify(draft.capture_state())}
	_flush_auto_advance.call_deferred(_receipt,_generation,step)

func _flush_auto_advance(receipt:String,generation:int,step:int) -> void:
	if not active or _submitting or _pending_advance.is_empty():return
	if receipt!=_receipt or generation!=_generation or str(_pending_advance.receipt)!=receipt or int(_pending_advance.generation)!=generation or int(_pending_advance.step)!=step:return
	var intent:String=str(_pending_advance.intent)
	_pending_advance={}
	if not _fingers.is_empty() or _multitouch or _dragged or not _pending_confirm.is_empty():return
	if draft.step!=step or step not in [1,2] or (step==1 and _manual_openings) or JSON.stringify(draft.capture_state())!=intent:return
	var projection:Dictionary=present()
	if not active or not projection.get("can_advance",false) or not projection.get("preview",{}).get("ok",false):return
	# A released world placement may only enter equipment/support. Never buy.
	advance()

func request_confirm() -> bool:
	# Godot may emit the emulated mouse GUI pressed signal before Main sees
	# the source ScreenTouch release. Preserve the pointer gate and wait for
	# that exact explicit GUI intent to become idle instead of discarding it.
	if not active or _submitting or not _pending_confirm.is_empty() or _multitouch or _dragged:return false
	if _fingers.size()>1:return false
	for index:Variant in _fingers:
		if not bool(_blocked.get(index,false)):return false
	present()
	if not _projection.get("can_confirm",false):return false
	_pending_confirm={"receipt":_receipt,"generation":_generation,"intent":JSON.stringify(draft.capture_state())}
	var receipt:String=_receipt
	var generation:int=_generation
	_preview_signature="";present()
	_flush_requested_confirm.call_deferred(receipt,generation)
	return true

func _flush_requested_confirm(receipt:String,generation:int) -> void:
	if not active or _submitting or _pending_confirm.is_empty():return
	if receipt!=_receipt or generation!=_generation or str(_pending_confirm.receipt)!=receipt or int(_pending_confirm.generation)!=generation:return
	if _multitouch or _dragged or JSON.stringify(draft.capture_state())!=str(_pending_confirm.intent):
		_drop_confirm_request();present();return
	if not _fingers.is_empty():return
	_pending_confirm={};_preview_signature=""
	confirm()

func confirm() -> Dictionary:
	if not active or _submitting or not _fingers.is_empty() or not _pending_confirm.is_empty():return {"ok":false,"code":"construction_not_ready","data":{}}
	_preview_signature="";present()
	if not _projection.get("can_confirm",false):
		var code:String=str(_projection.get("preview",{}).get("code","construction_not_ready"))
		return {"ok":false,"code":"construction_not_ready" if code=="ok" else code,"data":{}}
	var command:Dictionary=draft.command();command.id=_receipt
	_submitting=true
	var result:Dictionary=session.submit(command)
	_submitting=false
	if result.get("ok",false):cancel();committed.emit(result.duplicate(true))
	else:_preview_signature="";present()
	return result

func _hits_gui(point:Vector2) -> bool:
	return _gui_hit.is_valid() and bool(_gui_hit.call(point))

func feed(event:InputEvent) -> bool:
	if not active:return false
	if event is InputEventScreenTouch:
		if event.canceled:reset_input()
		else:_pointer(event.index,event.pressed,event.position)
		return true
	if event is InputEventScreenDrag:_motion(event.index,event.position);return true
	if event is InputEventMouseButton and event.device!=-1:
		if event.button_index==MOUSE_BUTTON_LEFT:_mouse_down=event.pressed;_pointer(-1,event.pressed,event.position);return true
		if event.pressed and world!=null and not _hits_gui(event.position):
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:world.camera_rig.set_zoom(world.camera_rig.zoom_size-1)
			if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:world.camera_rig.set_zoom(world.camera_rig.zoom_size+1)
		return true
	if event is InputEventMouseMotion and _mouse_down:_motion(-1,event.position);return true
	return false

func _pointer(index:int,pressed:bool,point:Vector2) -> void:
	if pressed:
		var pending:bool=not _pending_confirm.is_empty() or not _pending_advance.is_empty()
		_drop_confirm_request()
		if pending:present()
		_fingers[index]=point;_start[index]=point;_blocked[index]=_hits_gui(point)
		_gesture_generation[index]=_generation
		if _fingers.size()==1:_dragged=false;_multitouch=false
		else:
			_multitouch=true
			if not _draw_backup.is_empty() and active:
				draft.restore_state(_draw_backup);_draw_backup={};_draw_first=-1;_draw_last=-1;present()
		return
	if not _fingers.has(index):return
	var tap:bool=not _multitouch and not _dragged and not _blocked[index] and not _hits_gui(point) and int(_gesture_generation.get(index,-1))==_generation
	if not _pending_confirm.is_empty() and (_multitouch or _dragged or not bool(_blocked[index]) or not _hits_gui(point)):
		_drop_confirm_request();present()
	if not _draw_backup.is_empty() and active:
		if _hits_gui(point) or _multitouch or world==null or world.camera_rig.screen_to_cell(point)<0:draft.restore_state(_draw_backup)
		else:_update_draw(point)
		_draw_backup={};_draw_first=-1;_draw_last=-1;present()
	_fingers.erase(index);_start.erase(index);_blocked.erase(index);_gesture_generation.erase(index)
	if _fingers.is_empty() and not _pending_confirm.is_empty():
		_flush_requested_confirm.call_deferred(str(_pending_confirm.receipt),int(_pending_confirm.generation))
	if tap and active:
		var finished_step:int=draft.step
		if _tap(point):_queue_auto_advance(finished_step)

func _motion(index:int,point:Vector2) -> void:
	if not active or not _fingers.has(index) or world==null:return
	var before:Vector2=_fingers[index]
	if _fingers.size()>=2:
		var keys:Array=_fingers.keys();var other:int=keys[1] if keys[0]==index else keys[0]
		if not _blocked[index] and not _blocked[other]:
			var previous:float=before.distance_to(_fingers[other]);var current:float=point.distance_to(_fingers[other])
			if previous>1 and current>1:world.camera_rig.set_zoom(world.camera_rig.zoom_size*previous/current)
	elif not _blocked[index] and not _multitouch:
		if point.distance_to(_start[index])>10:_dragged=true
		if _dragged:
			if draft.step==0:
				if _draw_backup.is_empty():
					_draw_backup=draft.capture_state();_draw_first=world.camera_rig.screen_to_cell(_start[index]);_draw_last=_draw_first;_draw_move=false
					var local:=Vector2i(_draw_first%24-draft.origin_cell%24,int(_draw_first/24)-int(draft.origin_cell/24))
					_draw_move=draft.mode=="build" and draft.origin_cell>=0 and int(draft.layout.width)>=3 and local.x>=0 and local.y>=0 and local.x<int(draft.layout.width) and local.y<int(draft.layout.height)
				if not _hits_gui(point):_update_draw(point);present()
			else:world.camera_rig.pan(_floor_point(before)-_floor_point(point))
	_fingers[index]=point

func _construction_cell(point:Vector2) -> int:
	var picked:int=world.camera_rig.screen_to_cell(point)
	if picked<0 or _draw_last<0:return picked
	var at:Vector3=_floor_point(point)
	var x:int=picked%24;var y:int=int(picked/24)
	var old_x:int=_draw_last%24;var old_y:int=int(_draw_last/24)
	if absf(at.x-float(old_x))<=0.5+BUILD_SNAP_MARGIN:x=old_x
	if absf(at.z-float(old_y))<=0.5+BUILD_SNAP_MARGIN:y=old_y
	if (x==0 or x==23 or y==0 or y==17) and not (x==0 and y==9):return picked
	return y*24+x

func _update_draw(point:Vector2) -> void:
	var cell:int=_construction_cell(point)
	if cell<0 or _draw_first<0:return
	_draw_last=cell
	if _draw_move:
		draft.restore_state(_draw_backup)
		draft.adjust_bounds(Vector2i.ZERO,Vector2i(cell%24-_draw_first%24,int(cell/24)-int(_draw_first/24)))
	else:draft.set_bounds(draft.origin_cell if draft.mode=="edit" else _draw_first,cell)

func _floor_point(point:Vector2) -> Vector3:
	var camera:Camera3D=world.camera_rig.camera
	var origin:Vector3=camera.project_ray_origin(point);var direction:Vector3=camera.project_ray_normal(point)
	return origin-direction*(origin.y/direction.y)

func _tap(point:Vector2) -> bool:
	if not active or world==null:return false
	if draft.step==1:
		var wall:Dictionary=world.camera_rig.screen_to_wall(point,draft.origin_cell,int(draft.layout.width),int(draft.layout.height))
		if wall.is_empty():return false
		choose_wall(str(wall.side),int(wall.offset));return true
	if draft.step==0 and int(draft.layout.width)>=3 and int(draft.layout.height)>=3:return false
	var cell:int=world.camera_rig.screen_to_cell(point)
	if cell<0:return false
	if draft.step in [2,3]:
		var local:=Vector2i(cell%24-draft.origin_cell%24,int(cell/24)-int(draft.origin_cell/24))
		if local.x<0 or local.y<0 or local.x>=int(draft.layout.width) or local.y>=int(draft.layout.height):return false
	choose_cell(cell);return true
