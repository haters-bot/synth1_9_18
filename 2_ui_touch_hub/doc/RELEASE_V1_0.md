# UI Touch Hub V1.0 发布基线

## 身份与验收

- 已验收 UI：R15I，RTL `c988661`；原交接文档提交 `8398ac5`。
- 原标签：`verified/ui-R15I-20261017`、`deployed/ui-R15I-20261017`。
- 用户验收：文字、曲线更精细，触控正常；此前 FILTER/ENV 曲线、LFO 页签及节点拖动均已验收。
- 本次新增 README、发布说明和相对路径构建入口不改变已验收 RTL。
- 新增点击日志另作后续开发，不能把其验证结果混同为 R15I 的实机验收。

## 比特流与回退

- 本地归档：`impl/R15I_final_build2_20261017_2336/2_ui_touch_hub.fs`。
- 大小：35,117,569 bytes。
- SHA256：`3974EC45CAAA7FC88B8B2358ECC81CF563E5C2E0132572065CB94B52F2D8DC20`。
- 已部署审计：`impl/deploy_runs/20261017_233834_R15I_final/`；双机 hash 相同，Programmer 返回 0，摄像头已核对。
- Gowin 已完成 bitstream generation，但启动器挂住后人工结束，启动器最终退出码 -1；不能写成 gw_sh 正常 exit 0。
- 时序尚未收敛：最差 setup -1.216 ns，TNS -30.727 ns / 65 endpoints；hold 0；Fmax 58.084 MHz，目标 62.5 MHz。
- 资源：Logic 18,840 / 138,240；FF 4,030；BSRAM 3；DSP 39.5。

回退使用原始归档，不覆盖或删除当前产物：

```powershell
python tools/deploy_verified.py --label V1_0_R15I_rollback --fs impl/R15I_final_build2_20261017_2336/2_ui_touch_hub.fs
```

上述比特流留在本地归档和另存交付包中，不提交 Git。

## 范围限制

这是 UI V1.0，尚非三人整机 V1.0。当前未实现实体键盘事件入 UI；Note On/Off 顶层常零。
SPI 接收为本项目草案，尚无硬件队友确认依据。下游音频仓库已发展到不同的 CC 映射。
LFO 为本地七点编辑/预览，与音频队友的三点两曲率 LFO 不同；ENV2/3 本地独立编辑。
不要因为控件能动便宣称对应声音已经生效。
