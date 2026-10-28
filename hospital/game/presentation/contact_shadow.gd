class_name ContactShadow
extends RefCounted

# A small display-only grounding mark. It casts no shadow, owns no collision,
# and uses one shared material rather than a light or render target per object.
static var _material:ShaderMaterial
static func create(radius:Vector2,opacity:float=.14) -> MeshInstance3D:
	if _material==null:
		var shader:=Shader.new()
		shader.code="""shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 shadow_color=vec3(0.22,0.27,0.24);
void fragment(){
  float radius=length((UV-vec2(0.5))*2.0);
  float weight=pow(max(0.0,1.0-radius),2.0);
  ALBEDO=shadow_color;
  ALPHA=weight*COLOR.a;
}
"""
		_material=ShaderMaterial.new();_material.shader=shader
	var mesh:=PlaneMesh.new()
	mesh.size=radius*2
	var arrays:=mesh.get_mesh_arrays()
	var colors:=PackedColorArray()
	colors.resize(arrays[Mesh.ARRAY_VERTEX].size());colors.fill(Color(1,1,1,clampf(opacity,0,.3)))
	arrays[Mesh.ARRAY_COLOR]=colors
	var tinted:=ArrayMesh.new();tinted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var shadow:=MeshInstance3D.new();shadow.name="SoftContactShadow"
	shadow.mesh=tinted;shadow.material_override=_material
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.set_meta("display_only_contact_shadow",true)
	return shadow
