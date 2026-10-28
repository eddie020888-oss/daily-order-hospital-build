# 游戏场景运行美术来源

方向沿用用户已确认的 C 复古玩具三维人物器材与 A 手机界面。没有使用《主题医院》的模型、贴图或关卡素材。

60 位医生读自 `E:\CODEX\2026-10-19\医院医生独立建模\outputs\glb`，对应原始编号逐项写在 manifest.json 的 source 字段。原始 GLB、Blender 源文件及原作者脚本只读使用，未覆盖。运行版本合并为六个刚性身体部件，保留不同头型、身形、发型与服装，并缩减至每人不超过 10000 三角面。

8 位技术员、8 位接待员、48 个患者外形和六类设备为本轮新增的程序化首版模型。角色、设备分别有实际几何摘要和面数记录，见 manifest.json。几何摘要不相同不等于最终美术质量已经获得用户验收。

人物与器材的可编辑运行源文件保存在 `E:\CODEX\2026-10-19\医院场景美术实装\outputs\editable`，制作脚本在该目录的 work/build_runtime_art.py；原始制作脚本副本和用户指出的旧场景截图保存在该目录的 inputs。

portraits.png 与 equipment-thumbnails.png 由 Godot 加载本目录相同 GLB 实际渲染，不使用参考插画替代场景模型。生成脚本分别为 tests/render_scene_art_atlases.gd 和 tests/render_cast_rosters.gd。

动作采用六个刚性部件的关节控制，当前有走动、转向和简易操作表现，不是完整的骨骼蒙皮动作库。当前游戏仍只有医生、技术员、接待员和患者；资源库数量不等于同时在院人数或新职业、新关卡已完成。首关 36 个患者编号对应不同模型；员工总数上限仍为 8。

已有模型以显示为目的使用 glTF 顶点颜色。Compatibility 渲染器的颜色空间适配有独立色块试验佐证，原 GLB 保留规范的线性顶点颜色。


## Doctor01 refinement v10 (2026-10-26)

Rain Rig (CC) Blender Foundation | studio.blender.org

Original: https://studio.blender.org/characters/rain/v3/
License: CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/

Modified evaluated head/hair and face parts, baked runtime PBR colours, fitted to the original medical uniform/body, adjusted neck skinning and tied hair. Details and retained source attribution: `doctor-refinement-v10/ATTRIBUTION.txt` and `PROVENANCE.json`. Base body is Quaternius CC0.


## Doctor01 detail refinement v11 (2026-10-26)

Rain Rig (CC) Blender Foundation | studio.blender.org — CC BY4.0. Details: `doctor-refinement-v11/ATTRIBUTION.txt` and `PROVENANCE.json`. Added restrained material layers and original coat details; baseline artist facial topology, rig, body and actions retained.

## Unified cast v1 (2026-10-27)

124 matching 3D/portrait routes. Doctor01 v11 retained unchanged; other identities retain their existing bodies, costume, rest rigs and actions, with per-profile adapted Rain/Snow mature heads. Exact CC BY4.0 source credits and modifications: `unified-cast-v1/ATTRIBUTION.txt` and `PROVENANCE.json`. This is a modular cast, not 124 independently hand-sculpted source heads. Native engine checks do not establish iPhone performance.
