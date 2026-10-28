class_name RoomTemplates
extends RefCounted

# Coordinates are local [x, y] pairs. Walls are edges between pairs of cells,
# including the exterior neighbor; the doorway is the one omitted edge.
static func definition(kind: String, rotation: int) -> Dictionary:
	if kind not in ["reception", "diagnosis", "echo", "motion", "sensory", "recovery", "general_exam", "pharmacy", "ward"] or rotation < 0 or rotation > 3:
		return {}
	var size := 5 if kind=="ward" else 3 if kind in ["reception", "recovery"] else 4
	var door := [1, size - 1]
	var outside := [1, size]
	var equipment := [[0,0], [2,0]] if size == 3 else [[1,0], [2,0]]
	var service := [[0,1]] if size == 3 else [[1,1]]
	var staff := [[2,1]]
	var upgrade_equipment: Array = []
	var upgrade_service: Array = []
	if kind == "recovery":
		equipment = [[0,0]]
		staff = []
		upgrade_equipment = [[2,0]]
		upgrade_service = [[2,1]]
	elif kind=="general_exam":
		equipment=[[1,0]]
		service=[[1,1]]
		staff=[[2,1]]
	elif kind=="pharmacy":
		equipment=[[0,0],[1,0],[2,0]]
		service=[[1,1]]
		staff=[[2,1]]
	elif kind=="ward":
		door=[2,4]
		outside=[2,5]
		equipment=[[0,0],[1,0],[0,1],[1,1],[0,2],[1,2],[3,0],[4,0],[3,1],[4,1],[3,2],[4,2]]
		service=[[1,3],[3,3]]
		staff=[[4,3]]
	var cells: Array = []
	var walls: Array = []
	for y in range(size):
		for x in range(size):
			cells.append([x,y])
	for i in range(size):
		walls.append([[i,0], [i,-1]])
		walls.append([[0,i], [-1,i]])
		walls.append([[size-1,i], [size,i]])
		if i != door[0]:
			walls.append([[i,size-1], [i,size]])
	var result := {
		"size":size, "cells":cells, "wall_edges":walls,
		"door_cell":door, "door_outside_cell":outside,
		"equipment_cells":equipment, "service_cells":service, "staff_cells":staff,
		"upgrade_equipment_cells":upgrade_equipment, "upgrade_service_cells":upgrade_service
	}
	for key in ["cells", "equipment_cells", "service_cells", "staff_cells", "upgrade_equipment_cells", "upgrade_service_cells"]:
		for i in range(result[key].size()):
			result[key][i] = _rotate(result[key][i], size, rotation)
	for edge in result.wall_edges:
		edge[0] = _rotate(edge[0], size, rotation)
		edge[1] = _rotate(edge[1], size, rotation)
	result.door_cell = _rotate(door, size, rotation)
	result.door_outside_cell = _rotate(outside, size, rotation)
	return result

static func _rotate(point: Array, size: int, rotation: int) -> Array:
	var rotated := point.duplicate()
	for i in range(rotation):
		rotated = [size - 1 - rotated[1], rotated[0]]
	return rotated
