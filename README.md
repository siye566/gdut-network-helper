# 广工校园网助手

**面向广东工业大学大学城校区的无线校园网认证助手。** 从宿舍 `gdut-宿舍号` 切到教学区 `gdut` 后，如果学校要求重新认证，助手会在运行期间检查当前认证状态，并在需要时使用你保存的账号登录。

项目使用 Flutter 编写，共用 Windows、macOS、Android、iOS 的界面与认证核心。已提供 Windows x64 预览安装包与便携版；其他平台仍需自行构建和实机验证。手机目前需要打开助手，尚未实现切网后全程无操作的后台认证。

[下载 Windows 安装包](https://github.com/siye566/gdut-network-helper/releases/download/v0.1.0-preview.1/gdut-network-helper-0.1.0-windows-x64-setup.exe) · [下载便携 ZIP](https://github.com/siye566/gdut-network-helper/releases/download/v0.1.0-preview.1/gdut-network-helper-0.1.0-windows-x64-portable.zip) · [版本说明](https://github.com/siye566/gdut-network-helper/releases/tag/v0.1.0-preview.1) · [平台接入说明](docs/platforms.md) · [协议核实记录](docs/protocol.md) · [反馈问题](https://github.com/siye566/gdut-network-helper/issues)

> 这是个人开发的辅助工具，并非学校官方客户端。实际适配范围为已核实的大学城认证入口 `10.0.3.2` 与当前无线 AC 配置，其他校区、宿舍或认证页面可能需要进一步适配。

## 解决什么问题

连接 Wi-Fi 并不一定意味着完成校园网认证。走出宿舍、进入教学楼后，即使已经连上 `gdut`，仍可能需要打开浏览器再次登录。

助手把这段过程集中在一个窗口里：连接校园 Wi-Fi → 检查学校认证服务 → 已在线则保持状态，需要认证时才登录。它显示当前校园 IP、最近检查时间和近期活动；遇到验证码、套餐开通或未知页面时提示你转到官方网页处理。

## 当前功能

- **按需认证**：先检查在线状态，避免每次网络变化都直接重复提交账号密码。
- **跟随网络变化**：网络通知后等待 2 秒再检查；自动模式下每 30 秒检查一次，补充 Wi-Fi 到 Wi-Fi 切换时可能缺失的系统通知。
- **重新读取网络参数**：每次认证读取当前设备的 IP、MAC、VLAN 和门户配置，不复用旧认证链接中的客户端 IP；切网会使旧操作失效。
- **本机保存账号**：账号、密码和自动认证开关由 `flutter_secure_storage` 保存，支持清除；无需注册额外账号或部署服务端。
- **有限重试**：临时网络错误进入退避，连续失败后暂停；认证被明确拒绝时停止自动提交，需要核对并重新保存账号。
- **Android Wi-Fi 请求适配**：原生请求绑定当前 Wi-Fi，避免未认证校园网被移动数据默认路由掩盖。
- **保留人工入口**：一键打开官方网页登录；手机用户需要主动查看并同意学校服务协议，该勾选不跨应用会话保存。
- **只读诊断**：可独立运行 Node.js 工具检查门户与认证状态，不输入或提交账号密码。

## 平台能力

下表表示源码已实现的运行方式，**不代表每个平台均已完成打包、安装或真实登录验证**。可下载文件与构建结果以 [Release](https://github.com/siye566/gdut-network-helper/releases) 的实际附件和说明为准。

| 平台 | 运行期间的检查与认证 | 后台与退出后的行为 | 分发方式 |
| --- | --- | --- | --- |
| Windows x64 | 手动检查、网络变化后检查、定时检查 | 最小化可继续；退出后停止；尚无托盘与开机启动 | 已发布安装包、便携 ZIP 预览版，见 Release |
| macOS | 共用桌面认证逻辑 | 保持进程运行时检查；退出后停止；尚无托盘与开机启动 | 源码构建，需 Mac 开发与签名环境 |
| Android | App 前台检查，返回前台后重新检查；请求绑定 Wi-Fi | 暂无后台服务或锁屏保活，不能保证后台切网自动登录 | 源码构建与设备验证 |
| iOS / iPadOS | App 前台检查，返回前台后重新检查 | 暂无后台切网触发、快捷指令或 HotspotHelper 接入 | 需 Mac、Xcode 和开发签名 |

## Windows 安装与首次使用

1. 打开 [最新版本页面](https://github.com/siye566/gdut-network-helper/releases)，检查版本说明与适用架构。当前版本为 `v0.1.0-preview.1`，提供安装版与便携版。
2. 下载名称含 `windows-x64-setup.exe` 的附件并运行；便携版下载含 `windows-x64-portable.zip` 的附件，将**整个压缩包**解压后运行 `gdut_network_helper.exe`，保留同目录中的 DLL 与 `data/`。不要只复制主程序。
3. 可对照该版本的 `SHA256SUMS.txt` 核验下载文件。在 PowerShell 中运行 `Get-FileHash .\下载的文件名.exe -Algorithm SHA256`，比较哈希值。
4. 连接 `gdut` 或宿舍无线网。首次使用先在浏览器确认学校门户能打开、自己的账号能够正常登录。
5. 打开助手，输入网页登录使用的**完整账号**与密码，点击“保存账号”。账号只需在自己的设备输入，不要提交到 GitHub 或反馈区。
6. 点击“检查并认证”，核对实际结果；确认可用后开启“自动认证”，保持程序运行。

手机使用流程相同，但认证前还需要点击“查看学校《服务协议》”并主动勾选同意。需要查看认证状态或完成认证时，应将助手打开到前台。

“认证在线”表示学校认证接口确认当前连接在线，**不保证所有外网服务均可访问**。程序没有注销按钮；退出或关闭自动认证会停止助手后续操作，不会主动注销校园网。

首个 Windows 预览包没有代码签名，Windows 可能显示“未知发布者”；请只从本仓库 Release 下载并核对 SHA-256。安装包面向 Windows 10 1809 或更新版本的 x64 系统，默认安装到当前用户目录，不需要管理员安装。

## 账号与传输边界

| 环节 | 当前行为 |
| --- | --- |
| 本地保存 | 使用系统安全存储保存账号、密码与自动认证设置；“清除账号”会尝试删除对应记录 |
| 认证目标 | 请求直接发送到 `10.0.3.2`，应用请求白名单只允许 HTTP 80 / 801 端口 |
| 传输协议 | 已核实的学校门户使用 **HTTP**，登录 GET 请求包含账号密码；本机安全存储不能为网络传输增加加密 |
| 请求与日志 | 禁止跟随重定向；限制响应大小；应用活动日志使用固定文字，不记录原始请求 URL 或服务器响应 |
| 额外服务 | 无额外认证服务器，应用没有向第三方上传账号、遥测或云同步的逻辑 |
| 人工操作 | 套餐接口只查询，不开通；可见验证码、运营商选择、协议变化等交回官方网页 |

仅在你信任并确认连接正确的校园网络中使用。学校 HTTP 协议无法让客户端独立证明网络对端身份，不能把地址白名单理解为加密或服务器身份验证。反馈问题时请遮住账号、IP、MAC 和其他个人信息，不要提交带密码的请求链接、抓包或系统日志。

## 适配范围与验证状态

- 当前入口：`http://10.0.3.2/a79.htm`，无线 AC 为 `172.16.254.2`，AC 名称为空；AC 来自大学城 `gdut` 实际跳转参数，不是全校通用常量。
- 每次读取当前设备 IP；**尚未实现按 SSID 选择多组 AC 或自动发现 AC**。宿舍 SSID 使用其他控制器时，需要新的跳转信息与适配。
- 严格匹配已核实的 Dr.COM 配置与脚本版本 `4.1.3`；配置变化会暂停，不猜测新参数。
- 尚未适配或核实其他校区、`10.0.3.6`、IPv6 认证、MD5 模式、验证码及额外运营商选择。
- 2026-10-15 已只读读取现场门户、官方脚本、动态配置与在线状态，并运行 Node 诊断；只读访问可能经过有线或代理路径，不能作为无线认证成功的证据。
- 2026-10-18 已通过 [Windows 构建流水线](https://github.com/siye566/gdut-network-helper/actions/runs/39088292342) 完成 Release 编译、打包、静默安装、8 秒进程启动与卸载检查；构建源码提交为 `1ecde00`。这些检查未覆盖手工界面交互、保存真实账号或校园网登录。
- **尚未使用真实账号验证登录、宿舍与教学区之间的无线切换、各平台的安全存储与手机权限。** 构建成功、安装成功、真实校园认证成功是不同阶段，具体发布产物的验证情况见对应 Release 说明。

完整字段、协议判断与资料来源见 [协议核实记录](docs/protocol.md)。

## 无账号只读诊断

安装 Node.js 18+，连接校园网后在源码目录运行：

```powershell
node tool/inspect.mjs
```

工具仅访问学校入口与状态接口，不登录、不注销、不提交账号。输出门户能否识别、认证状态和能否读取当前 IP，不输出账号、姓名或 MAC。可用于区分“门户不可达”与“认证页面尚未支持”，不替代真实登录验证。

## 从源码运行与构建

本次预览版构建使用 Flutter **3.47.7** / Dart **3.13.5**，已提交对应 `pubspec.lock`，GitHub Actions 固定此 Flutter 版本。

基础环境：Flutter stable（项目最低声明 Flutter 3.35 / Dart 3.9）、Node.js 18+，以及目标平台的原生开发工具。插件可能有更高的工具链要求，详情见 [平台接入说明](docs/platforms.md)。

```powershell
git clone https://github.com/siye566/gdut-network-helper.git
cd gdut-network-helper
node tool/bootstrap.mjs --platforms=windows
flutter pub get
flutter run -d windows
```

`bootstrap` 在临时目录生成官方原生工程，只复制并配置缺失的平台目录；保留现有 `pubspec.yaml`、`lib/` 和已有平台目录，不自动编译。要生成全部四个平台目录，可省略 `--platforms`；已有平台目录的安全与原生配置需按平台说明手动核对。

Windows Release 构建和打包：

```powershell
flutter build windows --release
powershell -File tool/package-windows.ps1
```

打包需要 Visual Studio C++ 工具链与 Inno Setup 6。脚本将 Flutter Release 目录、插件 DLL、数据文件及所需 Visual C++ 运行库一起打包，输出到 `dist/`。当前脚本默认生成 x64 安装包、便携 ZIP 与 `SHA256SUMS.txt`。如果 Inno Setup 安装在其他目录，使用脚本的 `-IsccPath` 参数指定 `ISCC.exe`。

仓库的 [Windows 构建工作流](.github/workflows/build-windows.yml) 可从 GitHub Actions 手动触发，生成产物供下载。工作流的实际执行与校验结果以对应运行记录为准；工作流产物不会仅因构建完成就自动成为公开 Release 附件。

## 代码结构

```text
lib/
  main.dart                       界面、系统安全存储与官方网页入口
  assistant_controller.dart        网络通知、生命周期、认证调度与退避
  core/drcom_client.dart           门户解析、配置校验、状态检查与认证协议
  platform/device_transport.dart  请求白名单、超时、重定向限制与平台请求
platform_templates/android/       Android Wi-Fi 请求与网络安全配置模板
tool/bootstrap.mjs                生成并配置缺失的 Flutter 原生工程
tool/inspect.mjs                  无账号只读诊断
tool/package-windows.ps1          Windows 安装包与便携包打包
packaging/windows/                Inno Setup 配置
.github/workflows/                GitHub Actions 构建流程
docs/                            平台说明与协议核实记录
```

## 常见问题

| 现象 | 建议排查 |
| --- | --- |
| 浏览器也打不开 `10.0.3.2` | 确认连接正确校园 Wi-Fi，检查 VPN、代理或网络路由；可运行只读诊断。助手不能修复学校服务器或 Wi-Fi 本身故障 |
| Wi-Fi 已连接，仍提示认证服务不可达 | 稍候网络稳定，再点击“检查并认证”；确认当前校区与入口一致。Android 首次安装需确保原生 Wi-Fi 模板已接入 |
| 提示认证未通过 | 先使用官方网页检查账号、密码、套餐与设备上限；核对后重新保存账号，解除自动提交暂停 |
| 提示验证码、套餐或页面无法识别 | 点击“打开网页登录”完成所需人工操作；不要反复提交或修改参数绕过 |
| 宿舍可以、教学区不行，或反过来 | 两个 SSID 可能使用不同 AC；采集新认证页中的 `wlanacip`、`wlanacname` 后反馈，遮住账号和客户端 IP，不发送密码 |
| 手机锁屏或后台没有自动认证 | 当前版本仅支持前台；返回助手后检查。尚无后台服务或 iOS 切网自动化 |
| 保存或清除账号失败 | 检查系统安全存储权限。清除失败时应用已停止本次自动认证，但持久记录可能仍在，请修复权限后再次清除 |
| 解压后运行提示缺 DLL | 重新解压完整便携包，保留 DLL 与 `data/`，避免只移动 EXE；也可使用该版本安装包 |

提交 Issue 时建议说明系统版本、安装包版本或源码提交、校区、SSID 类型、界面提示与只读诊断结果。请勿附账号密码或含凭据的 URL。
