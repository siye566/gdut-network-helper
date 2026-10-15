# 平台接入与限制

本交付包含 Flutter 业务源码、原生配置生成脚本及 Android Wi-Fi 请求模板。本机未安装 Flutter，没有执行 Flutter 编译、打包或真机验证；目前不是可直接安装的成品。

## 生成原生工程

安装 Flutter stable 与 Node.js 18 或以上版本，在项目根目录运行：

```powershell
node tool/bootstrap.mjs
flutter pub get
flutter run -d windows
```

脚本通过 `flutter create --platforms=windows,macos,android,ios --empty --no-pub --project-name gdut_network_helper --org cn.gduthelper` 在系统临时目录创建原生壳，然后仅复制缺失的平台目录。项目现有 `pubspec.yaml`、`lib/` 与已经存在的平台目录不会被覆盖。脚本不复制测试源码，并清理新生成 Xcode 项目的模板测试引用。不运行测试、不编译，不删除用户文件；临时壳保留以便排查。

如果已有 `android/`、`ios/` 或 `macos/`，脚本会整体跳过，包括安全配置与原生请求接入；此时应由维护者对照下面的配置手动合并。不要把已存在但尚未配置的 runner 当作已接入。

## Windows 与 macOS

Windows 需要 Visual Studio 的 Desktop development with C++ 组件；`flutter_secure_storage` 还要求 C++ ATL。macOS/iOS 需要在 Mac 上安装 Xcode，并配置相应开发签名。

macOS 的 DebugProfile、Release entitlements 增加 `com.apple.security.network.client`。macOS/iOS 增加本地网络用途说明，以及 `flutter_secure_storage 11.2.0` 文档要求的 `keychain-access-groups` 空数组。iOS 的 Debug、Profile、Release Runner 构建配置均实际设置 `CODE_SIGN_ENTITLEMENTS`，分别引用 DebugProfile 或 Release 文件。

macOS 使用 Keychain Sharing entitlement 后涉及 provisioning：免费开发账号生成的机器专用开发配置不能当作跨 Mac 分发方案。分发时须检查自己的签名与 profile。详情见 [flutter_secure_storage 11.2.0 配置](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0)。

客户端原生 Dart IO 请求必须维持准确的校园服务器 IP、端口白名单和禁重定向；不增加全局 ATS 任意 HTTP 放行。本地网络访问首次授权需在设备上实际确认。

## Android

`connectivity_plus 7.3.2` 要求 Android Gradle Plugin 至少 8.12.1、Gradle wrapper 至少 8.13、Java 17；初始化脚本只在新生成 Android 壳的版本低于要求时提升对应版本，不降低更新版本。Apple 端该插件要求 Xcode 至少 26.1.1。依赖要求见 [插件官方说明](https://pub.dev/packages/connectivity_plus/versions/7.3.2)。

自动生成的 Manifest 配置 `INTERNET`、`ACCESS_NETWORK_STATE`、`allowBackup=false`，并接入 `network_security_config.xml`。仅 `10.0.3.2` 允许明文流量，其余地址默认拒绝；XML 无法限制端口，80/801 的限制由请求代码执行。最低 SDK 至少 24（url_launcher 6.3.3 的要求），并保留 Flutter 本身更高的最低版本要求。

`MainActivity.kt` 提供 MethodChannel `gdut_helper/wifi_http`，方法 `request`：

```text
参数：{url: String, method: "GET" | "POST", body?: String, headers?: Map<String,String>}
返回：{statusCode: int, body: String, location: String?}
```

每次请求都重新寻找当前连接的 Wi-Fi，调用该 `Network.openConnection`，避免未认证校园 Wi-Fi 被手机移动数据的默认路由掩盖。没有 Wi-Fi 就失败。允许的目标仅 `http://10.0.3.2` 的 80（含省略端口）或 801；不跟随重定向，3xx 状态原样交给认证层处理。连接与读取超时各 8 秒，响应最大 512 KiB；串行工作线程发请求，结果回主线程。错误只返回固定消息，原生层不打印账号、密码、原始 URL 或服务器响应。

这依旧需要连接校园 Wi-Fi 后实机验证；若设备存在多个同时活动的 Wi-Fi 网络，目前选择系统报告的首个 Wi-Fi Network。模板不读取 SSID，也没有申请定位、扫描或后台定位权限。

## 手机 MVP 的边界

手机第一版应在 App 可见时检查认证状态、执行登录，并在用户返回 App 后再次检查。没有实现后台保活、前台常驻服务或开机自启；不能保证锁屏、被系统回收之后还能检测切网。Android 网络事件注册也不能使已死亡进程自动复活，相关规则见 [Android 后台限制](https://developer.android.com/develop/background-work/background-tasks/bg-work-restrictions)。

iOS 尚未实现“连接 gdut”快捷指令。普通 App 不能承诺永久后台监听 Wi-Fi；系统级热点认证需 Apple 批准 HotspotHelper entitlement，iOS 26 另有对应扩展。见 [Apple iOS Wi-Fi API 说明](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)、[Wi-Fi 快捷指令触发器](https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios)。

认证接口是否匹配学校当前页面、账号套餐/运营商参数、各校区网络是否一致，均须接入真实校园网后确认。服务器通过 HTTP 接收凭据是现有协议约束；系统安全存储只保护本地凭据，无法为 HTTP 传输增加加密。

