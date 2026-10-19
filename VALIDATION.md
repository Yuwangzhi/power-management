# 验证记录

## 1.1.0 — 2026-10-19（Asia/Shanghai）

环境：Apple Silicon Mac，macOS 26.6。

- `./test.sh` 通过：屏保 0/1200 秒联动、后台修正被改动的屏保、重复应用不重复写偏好、桌面用户上下文、登录窗口跳过、缺省偏好、非法参数、失败时恢复原屏保、旧版正常睡眠恢复，以及原有电源解析/快照/回滚测试。
- `./build.sh --universal --install` 通过，本机 `/Applications/Power Management.app` 已更新到 1.1.0；安装前的版本按原流程保存为 ZIP。
- 实际打开安装后的原生窗口并检查：新增“自动屏保”状态、“开启时永不，关闭时 20 分钟后”的勾选提示、修复/恢复按钮和 v1.1.0 均显示完整。
- 在真实用户上下文运行 App 内同源屏保脚本，设置 1200 秒后，重新打开系统设置确认“20 分钟后”；随后恢复为 0 秒，原生 App 和 `--diagnose` 确认“永不”。系统设置已打开的页面可能保留旧显示，重启系统设置后读取到新值。
- 原生 arm64 与 Rosetta x86_64 的 `--diagnose` 均通过，包含屏保时间与后台屏保控制安装状态。
- `codesign --verify --strict` 通过，`lipo -archs` 为 `x86_64 arm64`；已安装和发布构建的可执行文件 SHA-256 一致：`5ea554f9f40578707e0742d4c2e0b66687eff06b929f337aad814f8722e7655d`。
- Spotlight 索引查询仍返回 `/Applications/Power Management.app`。
- `./package.sh` 生成 1.1.0 通用版 ZIP，ZIP 完整性和 `SHA256SUMS.txt` 校验通过。
- Command Line Tools 链接 Intel slice 时提示其 `libswiftCompatibilityPacks.a` 缺少 x86_64 slice；构建成功，生成的 Intel 二进制已通过本机 Rosetta 诊断运行验证。

验证边界：安装新版 App 无需管理员权限，但替换旧系统后台服务需要系统管理员授权。本次已从新版窗口发起“修复并开启防睡眠”，当时系统正在等待用户完成授权；真实后台切换与自动修正尚未核验。屏保设置读写已在本机实测，完整模式切换、后台修正和失败回滚在隔离环境核验。没有把隔离测试记为真实管理员切换结果。

## 1.0.0

日期：2026-10-17（Asia/Shanghai）。环境：Apple Silicon Mac，macOS 26.6，Apple Command Line Tools / Swift 6.4。

## 已完成

- SwiftUI / AppKit 原生窗口构建，Apple Silicon + Intel 通用二进制生成。
- 安装到 `/Applications/Power Management.app`；安装包和实际安装的可执行文件一致，ad-hoc 签名通过 `codesign --verify --strict`。
- 打开真实窗口，目视检查图标、状态卡片、电源/电量、睡眠策略表、按钮、提示和版本；无可见截断。
- 实际点击刷新、展开/折叠诊断，点击复制后界面显示“诊断信息已复制”。
- 实时读取到后台服务已加载、`SleepDisabled=1`、两种供电模式的系统/显示器/磁盘睡眠值均为 `0`，与界面显示一致。
- Spotlight 索引查询 `mdfind -onlyin /Applications Power` 返回 `/Applications/Power Management.app`。`mdls` 确认名称为 `Power Management`、类型为应用程序、bundle ID 正确。
- 读取到系统 Spotlight ⌘Space 快捷键已启用。Launch Services 已登记安装位置。
- 旧的两个 `.app` 启动器已重新编译，反编译确认均改为打开原生 App。
- 原始图标含透明通道；构建生成 16–1024 像素 `.icns` 图像。
- `./test.sh` 通过：正常、防睡眠、部分启用、服务异常、读取失败、AC/电池状态、中文/空格/引号/命令替换字符的路径转义、两个 root 入口的权限守卫。
- 隔离环境运行生产脚本的副本，验证开启、重复开启保留首次快照、恢复全部被改动的原始设置、bootstrap 失败回滚、没有快照的旧版恢复。仅将系统路径及 `pmset` / `launchctl` 等替换为临时目录中的桩；未对真实系统执行这些切换测试。
- Intel slice 经 Rosetta 执行 `--diagnose` 成功；原生 arm64 执行同一诊断成功。
- 通用 ZIP 通过完整性检查，发布包附 SHA-256。
- 安装备份采用 ZIP，旧 App 可从废纸篓恢复，避免备份目录中的同名 `.app` 被重复识别。

## 验证边界

- 未在这次验证中输入管理员密码或实际切换本机电源策略；真实管理员授权后的切换仍需用户在系统授权窗中完成。
- Spotlight 搜索浮层的原生 UI 访问超时，未自动核验“⌘Space → 键入 Power → 回车”整条键盘流程；索引命中、快捷键配置与原生 App 启动已分别核验。
- Intel 为本机 Rosetta 验证，未在独立 Intel Mac 或 macOS 13 设备上测试。
- 未做 Developer ID 签名或 Apple 公证。

完整可重跑的验证入口：`./test.sh`、`./build.sh --universal --install`、安装后 `PowerManagement --diagnose`。
