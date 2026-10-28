class_name GridEquipmentProjection
extends RefCounted

## Fixed isometric art has explicit base-corner correspondences. Project its
## floor plane into the real grid, and fold the upper depth proxy inside the
## same body rectangle. This is not a reconstructed 3D or seated-patient rig.
const BODY_SIZE:=Vector2(3,2)
const EDGE_INSET:=.02
const SOURCE_CORNERS:=[Vector2(561,557),Vector2(1125,890),Vector2(779,1105),Vector2(215,772)]

static func point(pixel:Vector2,source_corners:Array=SOURCE_CORNERS,body_size:Vector2=BODY_SIZE) -> Vector3:
	var along_x:Vector2=source_corners[1]-source_corners[0]
	var along_z:Vector2=source_corners[3]-source_corners[0]
	var relative:Vector2=pixel-source_corners[0]
	var determinant:float=along_x.cross(along_z)
	var u:float=relative.cross(along_z)/determinant
	var v:float=along_x.cross(relative)/determinant
	var visible_size:=body_size-Vector2.ONE*(2.0*EDGE_INSET)
	var ground:=Vector2((u-.5)*visible_size.x,(v-.5)*visible_size.y)
	# Raising Y and moving X/Z equally follows the fixed (1,1,1) camera ray,
	# retaining the exact calibrated image projection at every proxy vertex.
	var height:float=maxf(0,maxf(-visible_size.x*.5-ground.x,-visible_size.y*.5-ground.y))
	return Vector3(ground.x+height,HospitalInteriorArt.ROOM_FLOOR_TOP+.007+height,ground.y+height)

static func room_point(pixel:Vector2,source_corners:Array,body_size:Vector2,interior:Rect2) -> Vector3:
	var at:=point(pixel,source_corners,body_size)
	if not interior.has_area():return at
	# The original fold sits against the far body planes. A real room wall
	# extends inside its grid edge, so that fold can be buried inside plaster.
	# Move the proxy along the exact fixed-camera ray: its source
	# projection, ground corners, logical body and texture all stay unchanged.
	var required:=maxf(0.0,maxf(interior.position.x-at.x,interior.position.y-at.z))
	var available:=maxf(0.0,minf(interior.end.x-at.x,interior.end.y-at.z))
	# Parts of the photographed tabletop also project inside the base diamond;
	# h=0 in the old fold therefore does not mean that a texel depicts the floor.
	# Keep only the four authored ground anchors pinned, with a one-pixel blend.
	var anchor_distance:=INF
	for corner:Vector2 in source_corners:anchor_distance=minf(anchor_distance,pixel.distance_to(corner))
	return at+Vector3.ONE*minf(required,available)*smoothstep(0.0,1.0,anchor_distance)

static func mesh(texture_size:Vector2,source_corners:Array=SOURCE_CORNERS,body_size:Vector2=BODY_SIZE,local_from_world:Basis=Basis.IDENTITY,interior:Rect2=Rect2()) -> ArrayMesh:
	var xs:Array[float]=[]
	var ys:Array[float]=[]
	for step in range(41):
		xs.append(texture_size.x*step/40.0)
		ys.append(texture_size.y*step/40.0)
	# Include exact authored corner UVs, rather than merely reporting corners
	# that the actual render mesh does not reach on the ground.
	var anchor_offsets:Array=[-1.0,0.0,1.0] if interior.has_area() else [0.0]
	for corner:Vector2 in source_corners:
		# A narrow local lattice keeps anchor pinning from spreading over the
		# coarse mesh and cutting a visible stripe through the actual apparatus.
		for offset in anchor_offsets:
			# Authored anchors may deliberately lie outside transparent canvas.
			# Keep their original UV exactly, including in the default library path.
			var x:float=corner.x if offset==0.0 else clampf(corner.x+offset,0.0,texture_size.x)
			var y:float=corner.y if offset==0.0 else clampf(corner.y+offset,0.0,texture_size.y)
			if x not in xs:xs.append(x)
			if y not in ys:ys.append(y)
	xs.sort();ys.sort()
	var builder:=SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(ys.size()-1):
		for x in range(xs.size()-1):
			var corners:=[Vector2(xs[x],ys[y]),Vector2(xs[x+1],ys[y]),Vector2(xs[x+1],ys[y+1]),Vector2(xs[x],ys[y+1])]
			for index in [0,1,2,0,2,3]:
				builder.set_uv(corners[index]/texture_size)
				builder.set_normal(Vector3(1,1,1).normalized())
				builder.add_vertex(local_from_world*room_point(corners[index],source_corners,body_size,interior))
	return builder.commit()
