# 平台接入、构建与限制

项目共用 Flutter 业务源码，并提供原生工程生成脚本、Android Wi-Fi 请求模板及 Windows 安装包打包脚本。源码包含平台适配，不等于所有平台都经过构建、安装和现场认证。可用安装包与验证结果以 [Release](https://github.com/siye566/gdut-network-helper/releases) 的实际附件及说明为准。

## 平台运行方式

| 平台 | 已实现的运行逻辑 | 当前限制 |
| --- | --- | --- |
| Windows / macOS | 程序运行期间接收网络变化通知，自动模式下每 30 秒检查；最小化时进程可继续工作 | 退出后停止；无托盘、开机自启或系统服务 |
| Android | App 前台检查与认证；返回前台重新检查；请求绑定当前 Wi-Fi | 无后台服务、锁屏保活、开机自启；系统回收后无法持续运行 |
| iOS / iPadOS | App 前台检查与认证；返回前台重新检查 | 无后台切网自动触发、快捷指令或 HotspotHelper 接入 |

手机认证需用户主动查看并同意学校服务协议，每次应用会话重新确认。学校认证在线仅代表认证服务状态，不代表所有外网访问正常。

## 基础开发环境

- Flutter stable：项目最低声明 Flutter 3.35、Dart 3.9，实际还需满足所选平台插件要求。
- Node.js 18+：用于原生工程初始化与只读诊断。
- Windows：在 Windows 主机安装 Visual Studio 的 **Desktop development with C++**、Windows SDK 及 C++ ATL；打包还需 Inno Setup 6。
- macOS / iOS：在 Mac 主机安装与插件要求一致的 Xcode，配置开发签名及相应平台依赖。
- Android：Android SDK、Java 17；`connectivity_plus 7.3.2` 要求 Android Gradle Plugin 至少 8.12.1、Gradle wrapper 至少 8.13。

`connectivity_plus 7.3.2` 的 Apple 端要求 Xcode 至少 26.1.1；依赖要求见 [插件对应版本说明](https://pub.dev/packages/connectivity_plus/versions/7.3.2)。不要只依据项目 Flutter 最低版本判断完整工具链是否兼容。

## 生成原生工程

在项目根目录运行，例如只生成 Windows：

```powershell
node tool/bootstrap.mjs --platforms=windows
flutter pub get
flutter run -d windows
```

也可用 `--platforms=android`、`--platforms=macos,ios` 选择目标；省略参数时生成 Windows、macOS、Android、iOS 四个平台。

脚本通过 `flutter create --empty --no-pub --project-name gdut_network_helper --org cn.gduthelper` 在系统临时目录创建原生壳，仅复制缺失的平台目录，并配置新目录。现有 `pubspec.yaml`、`lib/` 与已经存在的平台目录不会被覆盖；脚本不复制测试源码，并清理新生成 Xcode 工程的模板测试引用，不自动编译。临时壳保留以便排查。

**如果某个平台目录已经存在，脚本会整体跳过。** 包括安全配置与原生请求接入都不会重新应用；维护者需要对照以下说明手动合并，不要把未配置的已有 runner 当作已接入。首次恢复依赖会生成 `pubspec.lock`，实际发布工程应保留该版本锁定记录。

## Windows 构建与分发

在 Windows 主机完成初始化与依赖恢复后：

```powershell
flutter build windows --release
powershell -File tool/package-windows.ps1
```

`package-windows.ps1` 要求已存在 `build/windows/x64/runner/Release/gdut_network_helper.exe`，不会代替 Flutter 构建。默认调用 `${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe`；位置不同时使用 `-IsccPath` 参数。

打包脚本将以下内容输出到 `dist/`：

- `gdut-network-helper-<版本>-windows-x64-setup.exe`：Windows x64 安装包。
- `gdut-network-helper-<版本>-windows-x64-portable.zip`：完整运行目录的便携压缩包。
- `SHA256SUMS.txt`：安装包与便携包的 SHA-256 校验值。

运行目录需要 Flutter 引擎、插件 DLL、`data/` 及 Visual C++ 运行库，不能只分发 EXE。脚本从构建主机 Visual Studio 的可再分发目录读取所需 x64 Release CRT；找不到必需文件时会失败，避免发布缺少运行依赖的包。

用户可在 [Release 页面](https://github.com/siye566/gdut-network-helper/releases) 按附件选择安装包或便携包。便携包需要完整解压。发布文件的系统兼容性、签名与验证情况应写入对应版本说明，不应因 Flutter 编译成功便声明现场认证通过。

### GitHub Actions

[Windows 构建工作流](../.github/workflows/build-windows.yml) 通过 `workflow_dispatch` 手动运行。流程恢复依赖、构建 Release、生成安装包与便携包，并包含静默安装、应用进程启动与卸载检查。只有对应运行实际成功后，才能把这些步骤记为已验证；进程存活检查也不能证明界面交互或真实认证成功。

工作流将生成文件、源码提交标识、Flutter 版本及依赖锁定文件上传为 Actions artifact，保留期限以工作流配置为准。Actions artifact 与公开 Release 附件是不同分发入口，发布 Release 时需使用实际成功构建的产物并记录来源。

## macOS 与 iOS

基础命令示例，在 Mac 上执行：

```sh
node tool/bootstrap.mjs --platforms=macos,ios
flutter pub get
flutter run -d macos
# iOS：连接设备并配置签名后，用 flutter devices 查询目标，再运行 flutter run -d <设备ID>
```

生成脚本为 macOS 的 DebugProfile、Release entitlements 增加 `com.apple.security.network.client`。macOS/iOS 添加本地网络用途说明，以及 `flutter_secure_storage 11.2.0` 文档要求的 `keychain-access-groups` 空数组；iOS 的 Debug、Profile、Release Runner 构建配置分别引用对应 entitlement 文件。

使用 Keychain Sharing entitlement 后需要检查签名与 provisioning。免费开发账号生成的机器专用开发配置不能当作跨 Mac 分发方案；iOS 分发也需符合自己的签名与分发配置。详情见 [flutter_secure_storage 11.2.0 配置](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0)。

客户端原生 Dart IO 请求维持准确的校园服务器 IP、端口白名单和禁重定向，不增加全局 ATS 任意 HTTP 放行。首次本地网络授权、系统安全存储、设备请求路由和真实认证仍需在设备上确认。

普通 iOS App 不能承诺永久后台监听 Wi-Fi。系统级热点认证涉及 Apple 批准的 HotspotHelper entitlement；当前项目没有接入。背景与能力说明可参见 [Apple iOS Wi-Fi API 概览](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)；[Wi-Fi 快捷指令触发器](https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios) 是后续可评估的方向，当前尚未实现。

## Android

源码运行示例：

```powershell
node tool/bootstrap.mjs --platforms=android
flutter pub get
flutter devices
flutter run -d <设备ID>
```

初始化脚本只在新生成 Android 壳的版本低于要求时提高 AGP / Gradle 版本，不降低更高版本。最低 SDK 至少 24（`url_launcher 6.3.3` 的要求），并保留 Flutter 本身更高的最低版本要求。

生成的 Manifest 配置 `INTERNET`、`ACCESS_NETWORK_STATE`、`allowBackup=false`，接入 `network_security_config.xml`。仅 `10.0.3.2` 允许明文流量，其他地址默认拒绝；XML 无法限制端口，80 / 801 的限制由请求代码执行。不读取 SSID，不申请定位、扫描或后台定位权限。

`MainActivity.kt` 提供 MethodChannel `gdut_helper/wifi_http`，方法 `request`：

```text
参数：{url: String, method: "GET" | "POST", body?: String, headers?: Map<String,String>}
返回：{statusCode: int, body: String, location: String?}
```

每次请求重新寻找活动 Wi-Fi，调用对应 `Network.openConnection`，避免未认证校园 Wi-Fi 被移动数据默认路由掩盖。没有 Wi-Fi 则失败；多个活动 Wi-Fi 同时存在时，当前选择系统报告的首个 Wi-Fi Network，仍需实机核实。允许目标仅为 `http://10.0.3.2` 的 80 或 801 端口，不跟随重定向。连接与读取超时各 8 秒，响应最大 512 KiB；请求由串行工作线程执行，结果回主线程。原生层不打印账号、密码、原始 URL 或服务器响应，只返回固定错误信息。

这些配置不能使被系统回收的应用自动恢复，也不能代替后台服务。当前主动在手机后台暂停认证，回前台重新检查。参见 [Android 后台限制](https://developer.android.com/develop/background-work/background-tasks/bg-work-restrictions)。

## 各平台共同的认证边界

- 门户仅允许 `10.0.3.2`，无线 AC 默认 `172.16.254.2`，来源为大学城 `gdut` 的已知跳转。其他 SSID 的 AC 可能不同，当前没有自动发现或多组 AC 切换配置。
- 设备 IP、MAC、VLAN 每次从新页面读取；不会复用用户历史链接中的客户端 IP。
- 当前认证协议使用 HTTP 和带凭据的 GET 查询。系统安全存储保护本地记录，不能为传输加密或证明服务端身份。
- 不跟随认证重定向，不执行远端 JavaScript，只解码精确回调包装中的 JSON；配置与模板变化会停止自动认证。
- 套餐只查询，不开通；验证码、运营商选择、设备上限等情况由用户在官方网页处理。
- 认证明确被拒后停止自动提交，核对并重新保存账号才解除暂停；临时故障有限重试，实际间隔还受检查周期和系统调度影响。

协议实现与只读现场核实详情见 [协议核实记录](protocol.md)。截至原始现场核实，没有执行真实账号登录、注销或无线切换验证；各平台仍需分别验证构建、安装、凭据保存、网络权限与校园认证，不能用其中一个阶段代替其余阶段。
