# 1.0.0 验证记录

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
