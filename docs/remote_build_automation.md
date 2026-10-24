# 远程综合布线自动化

## 目标

使用两条固定命令完成日常远程构建：

1. 14700K 构建电脑拉取 `main`、运行 Gowin 完整流程并打包结果。
2. 开发电脑从 Windows 共享目录复制并解压最新码流和报告。

自动化脚本不会自动提交源码、不会自动解决 Git 冲突，也不会删除旧的 `impl`。这样可以确保每个码流都能对应到一个已经提交的 Git commit。

## 文件

- `scripts/remote_build.ps1`：在构建电脑执行。
- `scripts/fetch_remote_build.ps1`：在开发电脑执行。
- `scripts/build_on_remote.ps1`：可选，在开发电脑上一条命令完成推送、远程构建和取回。
- `build_results/`：开发电脑接收构建结果的本地目录，已加入 `.gitignore`。

## 第一次配置构建电脑

构建电脑上的仓库目录假设为：

```text
D:\FPGA\synth1_9_18
```

Gowin EDA 使用与开发电脑相同的版本。脚本按以下顺序寻找 `gw_sh.exe`：

1. `-GowinSh` 参数；
2. `GOWIN_SH` 环境变量；
3. `PATH`；
4. Gowin V1.9.12.03 在 `C:`、`D:`、`E:` 下的常见安装位置。

如果安装位置不同，可以设置一次用户环境变量：

```powershell
[Environment]::SetEnvironmentVariable(
    "GOWIN_SH",
    "D:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe",
    "User"
)
```

重新打开 PowerShell 后生效。

建立用于回传结果的目录：

```powershell
New-Item -ItemType Directory -Force D:\FPGA\build_output
```

使用管理员 PowerShell 共享该目录，只需执行一次：

```powershell
New-SmbShare -Name FPGA_Builds -Path D:\FPGA\build_output -ReadAccess $env:USERNAME
```

如果开发电脑使用不同的 Windows 用户，可以在目录属性的“共享”和“安全”页面中给该用户添加只读权限。

查看构建电脑名称：

```powershell
hostname
```

假设结果为 `BUILD-PC`，开发电脑访问路径就是：

```text
\\BUILD-PC\FPGA_Builds
```

## 日常使用

### 1. 开发电脑提交源码

先正常检查并提交代码：

```powershell
git status
git add <本次确认需要提交的文件>
git commit -m "描述本次修改"
git push origin main
```

脚本有意不替代这一步，因为自动执行 `git add .` 可能把 Gowin 临时文件或未完成实验一并提交。

### 2. 构建电脑一键构建

```powershell
cd D:\FPGA\synth1_9_18
powershell -ExecutionPolicy Bypass -File .\scripts\remote_build.ps1
```

脚本依次执行：

1. 检查工作区是否干净；
2. `git fetch` 和 `git pull --ff-only`；
3. 生成临时 Tcl 脚本；
4. 通过 `gw_sh.exe` 执行 `open_project`、`run all` 和 `run close`；
5. 确认本次构建生成了新的 `.fs`；
6. 打包 `.fs`、`.bin`、综合日志、布局布线报告和构建元数据；
7. 更新共享目录中的 `latest.json`。

默认输出目录为：

```text
D:\FPGA\build_output
```

如果 Gowin 安装位置或输出目录不同：

```powershell
.\scripts\remote_build.ps1 `
    -GowinSh "E:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe" `
    -OutputRoot "E:\FPGA_Builds"
```

### 3. 开发电脑一键取回

```powershell
cd E:\GOWINproject\synth1_10_10\synth1_9_18
powershell -ExecutionPolicy Bypass -File .\scripts\fetch_remote_build.ps1 `
    -RemoteShare "\\BUILD-PC\FPGA_Builds"
```

脚本会把最新压缩包复制到 `build_results/`，解压后打印：

- Git commit；
- 构建电脑名称；
- 构建耗时；
- `.fs` 文件路径。

## 可复现性保护

构建脚本默认拒绝脏工作区，防止产生无法追溯的码流。出现以下提示时，应先检查远程电脑上的本地修改：

```text
The repository is not clean.
```

需要对未提交实验做临时构建时，可以显式使用：

```powershell
.\scripts\remote_build.ps1 -SkipPull -AllowDirty
```

这种结果的元数据仍会记录当前 commit，但无法完整表示未提交差异，因此不应作为正式板测版本。

## 官方命令依据

本项目安装的 Gowin Tcl 用户指南说明：

- `gw_sh.exe <script file>` 可直接执行 Tcl 脚本；
- `open_project <file>` 打开现有 `.gprj`；
- `run all` 执行综合和布局布线完整流程；
- `run close` 关闭当前工程。

脚本只封装以上官方流程，不修改器件、约束、IP参数和工程策略。

## 可选：本机一条命令完成全部流程

构建电脑启用 Windows OpenSSH Server 后，本机可以直接触发远程构建。以下命令需要在构建电脑的管理员 PowerShell 中执行一次：

```powershell
Get-WindowsCapability -Online | Where-Object Name -Like "OpenSSH.Server*"
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

开发电脑先验证能够登录：

```powershell
ssh teenagekiller@BUILD-PC
```

验证成功后，在开发电脑的工程目录运行：

```powershell
.\scripts\build_on_remote.ps1 `
    -RemoteHost "BUILD-PC" `
    -RemoteUser "teenagekiller"
```

如果构建电脑名称无法解析，可以把 `BUILD-PC` 换成局域网 IP。如果远程仓库或共享路径不同：

```powershell
.\scripts\build_on_remote.ps1 `
    -RemoteHost "192.168.31.96" `
    -RemoteUser "teenagekiller" `
    -RemoteProjectRoot "D:\FPGA\synth1_9_18" `
    -RemoteShare "\\192.168.31.96\FPGA_Builds"
```

该脚本会拒绝本机脏工作区；它不会自动执行 `git add` 或 `git commit`。成功后还会核对远程产物中记录的 commit 是否与本机 HEAD 完全一致，从而避免误拿旧码流。
