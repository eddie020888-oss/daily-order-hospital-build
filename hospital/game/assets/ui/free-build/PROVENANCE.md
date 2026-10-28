# 自由建造家具缩略图

plant.png、bench.png、cabinet.png、bin.png 于2026-10-19从本游戏RoomFurniture.create(kind)分别原生渲染。PNG为128×128透明缩略图，未修改原始模型。

绿植来源为res://assets/models/interior-v2/plant.glb；其余物件由res://presentation/room_furniture.gd调用现有圆角几何生成，与实际场景一致。未使用第三方游戏截图或生成插画。

可重现脚本：E:/CODEX/2026-10-19/医院UI再次纠偏/work/render_furniture_thumbnails.gd；运行日志：同项目reports/thumbnails.log.output.txt。仅初始化时加载四张静态图，不在游戏运行中创建额外3D预览视口。
