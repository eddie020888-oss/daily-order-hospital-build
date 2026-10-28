class_name CampaignBuildEditor
extends Control

signal active_changed(value:bool)
signal preview_changed(proposal:Dictionary,result:Dictionary)
signal committed(result:Dictionary)
var controller:CampaignBuildController
var card:CampaignBuildCard
var active:bool:
	get:return controller!=null and controller.active
var _external_gui_hit:Callable

func initialize(session:GameSession,world:HospitalWorld=null,external_gui_hit:Callable=Callable()) -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	_external_gui_hit=external_gui_hit
	controller=CampaignBuildController.new()
	controller.initialize(session,world,func(point:Vector2)->bool:return hits_gui(point) or (_external_gui_hit.is_valid() and bool(_external_gui_hit.call(point))))
	card=CampaignBuildCard.new();add_child(card);card.initialize(controller)
	controller.changed.connect(card.present)
	controller.active_changed.connect(func(value:bool)->void:active_changed.emit(value))
	controller.preview_changed.connect(func(proposal:Dictionary,result:Dictionary)->void:preview_changed.emit(proposal,result))
	controller.committed.connect(func(result:Dictionary)->void:committed.emit(result))

func begin_build(kind:String) -> bool:
	return controller.begin_build(kind)

func begin_install(kind:String,room_id:String) -> bool:
	return controller.begin_install(kind,room_id)

func begin_edit(room_id:String) -> bool:
	return controller.begin_edit(room_id)

func present(snapshot:Dictionary={}) -> void:
	if controller!=null:controller.present(snapshot)

func configure(safe_rect:Rect2) -> void:
	position=Vector2.ZERO;size=safe_rect.end+Vector2(8,8)
	if card!=null:card.configure(safe_rect)

func hits_gui(point:Vector2) -> bool:
	return active and card!=null and card.is_visible_in_tree() and card.get_global_rect().has_point(point)

func feed(event:InputEvent) -> bool:
	return controller.feed(event) if controller!=null else false

func cancel() -> void:
	if controller!=null:controller.cancel()

func reset_input() -> void:
	if controller!=null:controller.reset_input()

func _exit_tree() -> void:
	cancel()
