# 布局布线构建档位

## 为什么当前布局布线较慢

现有一次完整报告中：

- 布局耗时约 14 分 8 秒；
- 布线耗时约 34 分 14 秒；
- 总耗时约 48 分 46 秒；
- Logic 使用率 38%，BSRAM 使用率 43%，DSP 使用率 34%。

因此主要耗时位于布线搜索，而不是综合解析。工程同时包含 DDR3 接口、多种 BSRAM 延迟线、DSP 运算和多个时钟域；在 `Place Option = 3`、`Route Option = 2`、时序驱动和保持时间修正都开启时，每次全量搜索会明显变慢。

## 三种构建档位

`remote_build.ps1` 和 `build_on_remote.ps1` 现在接受 `-BuildProfile`：

| 档位 | 用途 | 策略 |
| --- | --- | --- |
| `Signoff` | 正式上板、最终报告 | 全量高努力布局布线；默认档位 |
| `Fast` | 较大改动后的功能试跑 | 降低布局和布线搜索强度，仍保留时序驱动与保持时间修正 |
| `Incremental` | 已有成功基线后的少量 RTL 改动 | 复用构建电脑 `impl` 中的上一版布局布线结果 |

示例：

```powershell
# 快速功能迭代
.\scripts\remote_build.ps1 -BuildProfile Fast

# 小改动，复用上一次成功结果
.\scripts\remote_build.ps1 -BuildProfile Incremental

# 正式构建；不写参数时也是这一档
.\scripts\remote_build.ps1 -BuildProfile Signoff
```

从开发电脑触发远程构建时，同样追加 `-BuildProfile Fast` 或 `-BuildProfile Incremental`。

`build_on_remote.ps1` 会先在构建电脑执行 `git pull`，再加载远端的构建脚本。这样即使本次提交修改了 `remote_build.ps1` 本身，也不会继续运行 PowerShell 已经载入内存的旧版本。

## 使用边界

- `Fast` 生成的码流仍必须检查 Setup/Hold 报告；它适合功能验证，不作为最终时序结论。
- `Incremental` 只适合改动范围较小且构建电脑保留了上一版 `impl` 的情况。
- 修改 PLL、时钟约束、DDR3 IP、存储结构、振荡器实体数或大范围数据通路后，应改回 `Signoff`。
- 每隔若干次增量构建，应执行一次 `Signoff`，防止长期复用旧布局掩盖新的拥塞问题。
- 三个档位均会写入构建包的 `build_metadata.json`，便于区分快速测试码流和正式码流。
- 三路异步 UART 的第一同步级都已声明为 false path，避免布局器尝试优化不存在固定相位关系的外部输入路径；第二同步级及其后级逻辑仍正常参与时序分析。

## 推荐工作流

1. 首次或结构性修改：`Signoff`。
2. 只改协议、参数映射或少量控制逻辑：优先 `Incremental`。
3. 增量布局无法收敛或没有可复用基线：改用 `Fast`。
4. 功能确认后：再运行一次 `Signoff` 并保存完整时序报告。
