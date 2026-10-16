# Power Management

原生 macOS 电源管理 App。按 **⌘ Space**，输入 **Power**，打开 **Power Management**，直接在窗口里查看和切换防睡眠状态。

## 日常使用

安装位置：`/Applications/Power Management.app`。

- **开启防睡眠**：禁用系统、显示器和磁盘的自动睡眠，同时作用于插电和电池模式；安装每 15 秒重新应用设置的后台服务。
- **恢复正常睡眠**：停止并移除后台服务，恢复本次开启前保存的电源设置。对没有备份的旧版安装，采用旧版的正常睡眠默认值。
- **刷新**（⌘R）：重新读取真实的系统设置；窗口也会每 15 秒自动刷新。
- **诊断信息**：展开查看 `pmset` 和 `launchctl` 输出，也可复制。
- 关闭窗口后可从菜单栏电源图标重新打开，也可再次通过 Spotlight 打开。退出 App 不会停止已经启用的系统防睡眠服务。

打开 App 只读取状态。点击切换按钮时，由 macOS 弹出管理员授权；取消授权不会执行切换。App 不保存密码。

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
/Library/LaunchDaemons/com.yuwangzhi.codex-power-keepawake.plist
/Library/Application Support/com.yuwangzhi.power-management/
```

最后一个目录由 root 持有、权限为 `0700`，保存开启前的 `pmset` 快照。恢复时只解析并恢复本工具会改动的数值设置，不执行备份内容。已有备份会保留到恢复完成，重复开启不会覆盖原始快照。安装失败时尝试回滚。

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
- `Tests/`、`test.sh`：状态和供电解析、路径转义、权限守卫，以及隔离的开启/重复开启/恢复/失败回滚/旧版兼容验证。
- `install.sh`、`restore-default-sleep.sh`、`power-settings.sh`：后台服务与电源快照管理。
- `CHANGELOG.md`、`VALIDATION.md`：版本变更与实际验证记录。

图标由内置 imagegen 生成；原始文件和完整提示词保存在 `Resources/AppIcon.png` 与 `Resources/ICON.md`，构建时生成各尺寸 `.icns`。

## 诊断

```sh
'/Applications/Power Management.app/Contents/MacOS/PowerManagement' --diagnose
pmset -g custom
pmset -g batt
launchctl print system/com.yuwangzhi.codex-power-keepawake
```

`--diagnose` 只输出 JSON，不启动窗口、不修改设置。状态包含两种供电模式的设置，后台服务有文件但未加载、服务执行失败或设置不完整时，显示“防睡眠需要修复”。
