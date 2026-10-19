# Power Management

原生 macOS 电源管理 App。按 **⌘ Space**，输入 **Power**，打开 **Power Management**，直接在窗口里查看和切换防睡眠状态。

## 日常使用

安装位置：`/Applications/Power Management.app`。

- **开启防睡眠**：禁用系统、显示器和磁盘的自动睡眠，同时将当前登录用户的自动屏保设为**永不**；作用于插电和电池模式，后台服务每 15 秒检查并重新应用设置。
- **恢复正常睡眠**：停止并移除后台服务，恢复本次开启前保存的电源设置，并将自动屏保设为 **20 分钟后**。屏保按此固定规则切换；对没有电源备份的旧版安装，采用旧版的正常睡眠默认值。
- **刷新**（⌘R）：重新读取真实的系统设置；窗口也会每 15 秒自动刷新。
- **诊断信息**：展开查看 `pmset` 和 `launchctl` 输出，也可复制。
- **自动屏保**：在“当前睡眠策略”中显示实际生效的屏保时间。
- 关闭窗口后可从菜单栏电源图标重新打开，也可再次通过 Spotlight 打开。退出 App 不会停止已经启用的系统防睡眠服务。

打开 App 只读取状态。点击切换按钮时，由 macOS 弹出管理员授权；取消授权不会执行切换。App 不保存密码。

从 1.0.0 升级且已开启防睡眠时，首次会显示“防睡眠需要修复”：点击“修复并开启防睡眠”，完成一次系统管理员授权，即可升级后台服务并启用屏保联动。安装新版 App 本身不会替换正在运行的系统服务。

防睡眠会增加电池消耗与发热，合盖运行时需保持散热。网络断开、关机及电量耗尽仍会影响远程连接。

## 构建与安装

需要 macOS 13+ 和 Apple Command Line Tools（`xcode-select --install`），无第三方运行依赖。

```sh
./test.sh
./build.sh --install                 # 当前 CPU 架构，安装并登记 Spotlight
./build.sh --universal --install     # Apple Silicon + Intel 通用版本
./package.sh                        # 生成通用版 ZIP 与 SHA256SUMS.txt
```

构建结果位于 `.build/Power Management.app`，发布包位于 `dist/`。更新安装前会备份已有同名 App 到 `~/Library/Application Support/Power Management/Backups/`。发布包使用本地 ad-hoc 签名；未做 Developer ID 公证。

Spotlight 通过 App 的文件名、`CFBundleName` 与 Launch Services 登记识别英文名称。安装脚本执行 `lsregister -f` 与 `mdimport`，不会重建全盘索引。

## 电源服务

沿用原来的服务标识，避免与旧版本重复安装：

```text
/usr/local/sbin/codex-power-keepawake.sh
/usr/local/sbin/screensaver-settings.sh
/Library/LaunchDaemons/com.yuwangzhi.codex-power-keepawake.plist
/Library/Application Support/com.yuwangzhi.power-management/
```

最后一个目录由 root 持有、权限为 `0700`，保存开启前的 `pmset` 快照。恢复时只解析并恢复本工具会改动的数值设置，不执行备份内容。已有备份会保留到恢复完成，重复开启不会覆盖原始快照。安装失败时尝试回滚。

屏保属于用户偏好。系统服务通过 `launchctl asuser` 和 `sudo -u` 在当前桌面用户的上下文中读写 `com.apple.screensaver` 的当前主机 `idleTime`；不改 root 的屏保设置。尚无桌面用户登录时跳过，登录后由下次后台检查应用。失败回滚恢复该次开启前的屏保时间；主动关闭防睡眠固定设为 1200 秒。此功能只调整自动启动屏保的时间，不修改登录密码或锁屏密码策略，也不会阻止手动锁屏或触发角。

命令行入口仍可使用：

```sh
sudo ./install.sh
sudo ./restore-default-sleep.sh
./debug-查看电源状态.sh
```

`toggle-keepawake.sh` 为旧版兼容入口，调用同一套安装/恢复脚本。旧的两个 AppleScript 启动器已改为打开原生 App；日常只需使用 **Power Management**。

## 项目结构

- `Sources/`：SwiftUI 窗口、菜单栏、实时状态解析和管理员授权。
- `Resources/`：App 元数据、原始透明 PNG 图标与生成提示词。
- `Tests/`、`test.sh`：状态和供电解析、路径转义、权限守卫，以及隔离的屏保联动、桌面用户上下文、后台修正、开启/重复开启/恢复/失败回滚/旧版兼容验证。
- `install.sh`、`restore-default-sleep.sh`、`power-settings.sh`、`screensaver-settings.sh`：后台服务、电源快照与屏保管理。
- `CHANGELOG.md`、`VALIDATION.md`：版本变更与实际验证记录。

图标由内置 imagegen 生成；原始文件和完整提示词保存在 `Resources/AppIcon.png` 与 `Resources/ICON.md`，构建时生成各尺寸 `.icns`。

## 诊断

```sh
'/Applications/Power Management.app/Contents/MacOS/PowerManagement' --diagnose
pmset -g custom
pmset -g batt
launchctl print system/com.yuwangzhi.codex-power-keepawake
```

`--diagnose` 只输出 JSON，不启动窗口、不修改设置。状态包含两种供电模式的设置、`screenSaverIdleSeconds` 与 `screenSaverGuardInstalled`。后台服务有文件但未加载、服务执行失败、旧服务未支持屏保或设置不完整时，显示“防睡眠需要修复”。

屏保状态读取采用 Apple 的当前用户/当前主机偏好域：[CFPreferencesCopyValue](https://developer.apple.com/documentation/corefoundation/cfpreferencescopyvalue(_:_:_:_:))、[CFPreferencesSynchronize](https://developer.apple.com/documentation/corefoundation/cfpreferencessynchronize(_:_:_:))。
