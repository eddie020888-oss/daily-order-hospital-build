# R01/T01 简洁人物第二版（未验收）

2026-10-20，本轮新增两名独立人物：staff_001 → receptionist-01 / R01，staff_003 → technician-03 / T01。保留此前 simple-support-v1 与所有旧运行模型。

- 可编辑源：`E:/CODEX/2026-10-20/医院整体画面继续优化/work/candidates/staff-reception-02/R01-support-editable.blend`、`staff-tech-02/T01-support-editable.blend`。
- 完整生成源：同项目 `work/build_support_staff_02.py`，第一版源与输出保留。当前 GLB 与同源头像逐字节复制自两个第二版候选目录。
- 造型依据：`E:/CODEX/2026-10-19/医院十二位代表角色/inputs/01-staff-roster.png`、`work/R01-01/R01-elder-receptionist-sculpt.blend` 与 `work/T01-01/T01-neutral-sculpt.blend`。原文件只读，未导入旧高模、未覆盖。
- 两人原运行资产只有六个刚性部件，没有蒙皮/动画。本轮分别新建网格、20骨架和三段 Actions，按自身身体比例放置关节，没有把医生身体换色作为两人。
- 共同动作规范为 Idle 2秒、Walk 32个帧间隔/30FPS（1.0666667秒）、Examine 2.4秒；均循环，无根运动。接待员是迎接/引导手势，技术员是克制的双手操作手势，没有虚构 Consult 坐诊片段或精确器材接触事件。
- 第二版改薄圆鞋形、接待员额前宽发束，以及新两人的步幅/行走骨盆高度。Walk 的源站立段匹配速度为 .8125/.84375 米每秒，实际游戏仅这两个身份根据显示速度调节步频；旧 D01/P01 动作和上限保留。
- R01 9759 三角，T01 10806 三角；这不是手机性能通过证明。没有外部贴图；头像来自各自实际模型。
- 源文件重开、动作采样、干净复制目录重导入和当前 GLB 哈希见该项目 `reports/support-handoff.json`；真实游戏与回归证据见 `reports/final-evidence-audit.json`。

静态表情，无手指骨、运行时地面 IK 或全转弯锁脚承诺。技术验证与源渲染不替代用户人物/整体美术验收。其他身份没有套用此模型。
