# 给队友的同步说明

UI Touch Hub 已整理为 V1.0（已验收 R15I：触控跟手，FILTER/ENV/LFO 可直接拖动），
位于共享仓库 ui-touch-hub-v1.0 分支的 2_ui_touch_hub/。音频根目录布局保持原样。
已上传草稿 PR：https://github.com/haters-bot/synth1_9_18/pull/1 ，尚未合并 main。
已验收普通固件标签为 ui-v1.0.0，日志扩展单独提交，不混为同一版硬件验收。

新增独立点击日志诊断工程：DEBUG USB 的 COM6、115200 8N1，可记录坐标、按钮/旋钮、
曲线和内部参数请求；PC 实时打印并保存 bin/JSONL。普通工程仍为 MIDI 31250。
诊断版使用同一 U15 TX，暂停该引脚对外 MIDI；参数请求不等于音频接收确认。

本轮未改队友协议。对照音频 main 85edc82，UI 旧 CC、ENV 对应关系和七点 LFO 与音频三点模型
存在差异，见 doc/TEAM_INTEGRATION_2026-10-17.md。上游还需提供发送端工程、帧格式和接线；
三人需确认 ENV/Hold 语义、LFO 模型、初值同步/回读、触控抢占，再改接口。

UI/日志验收不代表音频全链路已联调，时序仍有负裕量。实测证据和已知限制见
doc/CODEX_TOUCH_TRACE_HANDOFF_2026-10-18.md。本说明供用户转发，没有自动给队友发消息。
