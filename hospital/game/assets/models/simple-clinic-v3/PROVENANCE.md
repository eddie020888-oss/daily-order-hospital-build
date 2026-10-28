# 医生外观修订候选（未验收）

2026-10-20，仅用于已有 D01 / canonical `doctor-02`；患者 P01 继续使用 simple-clinic-v2。没有复制给其他身份。

- 可编辑源：`E:/CODEX/2026-10-20/医院整体画面修正/work/candidates/doctor-02/D01-polished-editable.blend`
- 导出源：同目录 `D01-polished-rigged.glb`；本目录 `doctor-02.glb` 为逐字节复制。
- 生成脚本：`E:/CODEX/2026-10-20/医院整体画面修正/work/build_polished_characters_roundhair.py`
- 来源骨架与四段动作：`E:/CODEX/2026-10-19/医院诊室可玩样板/work/doctor-consult-06/doctor-consult-editable.blend`，原件未修改。
- 面部与服装采用本项目独立程序网格，静态表情；本次医生改为连续圆润短波发。没有新增面部动画。
- 20 骨骼、Idle / Walk / Examine / Consult，坐诊 8 秒。运行时除 Consult 外循环，遵循现有游戏播放器设定。
- `doctor-02-portrait.png` 为同一模型的 Blender 头像渲染。
- 6198 顶点、11998 三角；这不是全院角色数量或手机性能结论。
- 导出与干净场景重新导入记录：`E:/CODEX/2026-10-20/医院整体画面修正/reports/character-handoff.json`。

仅为真实游戏接入候选。代码验证、导出检查与用户美术验收分别记录；保留此前模型及失败候选。
