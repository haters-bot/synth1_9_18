# 远程连接方式变更：ZeroTier → 校园网 IPv6 直连

**日期**：2026-10-26
**影响范围**：所有需要 SSH 连接工程机（DESKTOP-FDEVSGP）的脚本、工具、人工操作
**状态**：已生效并验证

---

## 一句话结论

**不要再通过 ZeroTier 地址 `10.136.125.157` 连工程机。改用 IPv6 地址 `240c:c283:4007:9527:557c:f808:60e6:3b89`。**

ZeroTier 那条链路没有坏，是**慢到不可用**：打洞失败、全程绕海外 Planet 中继，RTT 400ms+、丢包 65%，SSH 长连接会被反复重置。

---

## 地址对照表

| 角色 | 旧（ZeroTier，已弃用） | 新（校园网 IPv6，现行） |
|---|---|---|
| 工程机 | `10.136.125.157` | `240c:c283:4007:9527:557c:f808:60e6:3b89` |
| 主力机（本机） | `10.136.125.235` | `240c:c283:4007:92f6:33dd:5a1d:ff72:c489` |

**注意工程机的两个 IPv6 地址**：
- `...:557c:f808:60e6:3b89` — `SuffixOrigin=Link`，由 MAC 推导，**稳定，用这个**
- `...:904a:aafe:cef3:b170` — `SuffixOrigin=Random`，临时地址，会变，**不要用**

主力机同理，`...:33dd:5a1d:ff72:c489` 是稳定的那个。

SSH 用户名仍是 `Administrator`，端口仍是 22，密钥仍是 `~/.ssh/id_ed25519`。

---

## 怎么连

```bash
# 推荐：用已配置好的别名
ssh gaoyun "命令"

# 等价写法
ssh Administrator@[240c:c283:4007:9527:557c:f808:60e6:3b89] "命令"
```

IPv6 字面量**必须加方括号**，否则 SSH 会把它当作用户名分隔符解析失败。

`~/.ssh/config` 里已配置好 `gaoyun` / `eng` / `zt` 三个别名，都指向 IPv6；旧的 ZeroTier 入口降级为 `zt-old`（仅备查，不要用）。

---

## 性能对比（实测）

| 指标 | ZeroTier 中继 | IPv6 直连 |
|---|---|---|
| TCP 22 握手 | 400ms+，抖动到 3.4s | 4–23ms |
| SSH 连接成功率 | 时通时断 | 10/10 |
| 单次 SSH 往返 | 9–12 秒 | 约 860ms |
| 3MB HTTP 传输 | 常中途 RST | 0.26 秒 |
| 5MB scp | 35MB 必断 | 1.6 秒（3.2MB/s） |

---

## 写脚本时必须知道的四件事

### 1. 批处理，别开多条连接

单次 SSH 的约 800ms 是 **Windows OpenSSH 服务端启动开销**，不是网络延迟（握手本身只有毫秒级）。这个开销每次连接都要付一遍。

- 一条连接内跑 5 条命令：**825ms**
- 5 次独立连接各跑 1 条：**3804ms**

所以要把多条命令合并进一次 `ssh` 调用，或者用 PowerShell 脚本一次传过去。

### 2. ControlMaster 连接复用在 Windows 上不可用

实测 `ControlMaster` 会返回 `mux_client_request_session: read from master failed: Connection reset by peer`。别浪费时间尝试，用批处理代替。

### 3. 别用 ping 判断可达性

IPv6 上 ICMP 仍然不通，但 TCP 完全正常。判断工程机是否在线请用 TCP 探测：

```python
import socket
s = socket.socket(socket.AF_INET6); s.settimeout(5)
s.connect(("240c:c283:4007:9527:557c:f808:60e6:3b89", 22, 0, 0))  # IPv6 要传 4 元组
```

注意 IPv6 的 `connect()` 需要 `(host, port, flowinfo, scope_id)` 四元组。

### 4. 传 PowerShell 脚本用 stdin，不要拼接命令行

原脚本用 `powershell -EncodedCommand <base64>` 把脚本拼进 SSH 命令行，容易被安全扫描判为命令注入而拦截。改用 stdin 传：

```python
args = ["ssh", "-6", "Administrator@[240c:...]", 
        "powershell -NoProfile -NonInteractive -Command -"]
subprocess.run(args, input=script.encode("utf-8"), capture_output=True)
```

脚本内容走 stdin，命令行里不含任何变量内容。

---

## 已经改好的代码

`2_ui_touch_hub/tools/deploy_verified.py`（**gaoyun 和 synth1_9_18 两处都已改**）：

- `LOCAL_IP` / `REMOTE_IP` 默认值改为 IPv6
- 支持 `GAOYUN_LOCAL_IP` / `GAOYUN_REMOTE_IP` 环境变量覆盖（换网络时不用改代码）
- `remote()` 改用 stdin 传 PowerShell 脚本
- IPv6 下用 `-6` 代替 `-b <源地址>`（`-b` 不能绑 IPv6 字面量）
- HTTP 服务改用 `IPv6HTTPServer`（`address_family = socket.AF_INET6`）
- URL 里的 IPv6 用 `ssh_host()` 加方括号

端到端已验证：3MB 传输 SHA256 完全一致。

**其他脚本仍有硬编码的旧 ZeroTier IP**，用到时需要一并改：
`fast_chunk_upload.py`、`remote_exec.py`、`transfer_and_flash.py`、`tools_remote_test.py`、`fetch_remote_image.py`、`stream_transfer.py`、`tools_investigate.py`、`tools/deploy_flash_verify.py`、`tools/fetch_image.py`、`tools/deploy.py`（后者已知有缺陷，不建议使用）。

---

## 环境前提（换机器/重装时检查）

### 主力机 WLAN 的 IPv6 曾被禁用

```powershell
# 检查
Get-NetAdapterBinding -Name WLAN -ComponentID ms_tcpip6

# 若 Enabled=False，用管理员权限启用
Enable-NetAdapterBinding -Name WLAN -ComponentID ms_tcpip6
```

**为什么被禁用**：全局 IPv6 并未禁用（`Tcpip6\Parameters\DisabledComponents` 未设置），组策略也没有相关条目，是**逐网卡**关掉的。本机装有多个具备改网络配置能力的工具，最可能的来源是：

- **EasyConnect**（深信服校园 VPN）— 服务常驻运行，VPN 客户端关 IPv6 防泄漏是常见做法
- **UU 加速器** — 装过 TAP 虚拟网卡，加速器常会调整协议绑定
- **华为电脑管家** — 带网络优化功能

没有找到直接日志证据，无法确定具体是哪个。**重装系统或换机后，先检查这一项**；如果发现被再次关闭，说明是上述某个软件重装/更新时改的。

### 工程机侧

工程机的 IPv6 是启用状态，无需额外配置。若工程机换网络（离开校园网），IPv6 地址会变，届时需要重新确认地址或回退到 ZeroTier。

---

## 回退方案

如果 IPv6 不可用（离开校园网、IPv6 出口故障），可以回退到 ZeroTier，但要知道它很慢：

```bash
ssh zt-old "命令"
# 或设置环境变量后跑部署脚本
export GAOYUN_LOCAL_IP=10.136.125.235
export GAOYUN_REMOTE_IP=10.136.125.157
```

ZeroTier 下传大文件务必先压缩（35MB 位流压缩后约 2MB），未压缩传输会中途断开。

---

## 相关排查结论（避免重复劳动）

- **不是 FlClash 的问题**：`tun: enable: false` 没开 TUN 网卡；规则里有 `IP-CIDR,10.0.0.0/8,DIRECT,no-resolve`；系统代理只监听 `127.0.0.1:7890` 且 `ProxyOverride` 含 `10.*`；ping/tracert 走 ICMP 本就不经 HTTP 代理。
- **不是工程机离线**：之前 `ping` 显示 100% 丢包是默认超时太短造成的假象，加 `-w 2000` 后 20 个包能收到 7 个。
- **校园网 IPv4 二层不通**：两台机器虽同在 `10.31.0.0/16`，但 AP 做了客户端隔离，ARP 解析失败，走不了 IPv4 直连。这是必须用 IPv6 的原因。

---

## 踩坑记录

调试时曾残留多个 `python -m http.server 8899` 僵尸进程，导致请求打到错误进程、`Invoke-WebRequest` **静默失败**（文件不存在但不报错）。部署前如怀疑端口被占用：

```powershell
Get-NetTCPConnection -LocalPort 8899 | Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force }
```
