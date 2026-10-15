# 广东工业大学无线校园网协议核实记录

2026 年 10 月 15 日，仅通过 HTTP GET 读取校园网认证页面、静态脚本、页面配置和当前连接状态。没有执行登录、注销、套餐开通或账号修改，也没有在文档保存现场账号、姓名、IP 或 MAC。实现尚未经过真实账号登录验证。

## 官方资料与入口

- [苹果设备连接 GDUT 网络教程](https://nic.gdut.edu.cn/info/1029/2401.htm)：大学城、番禺校区页面入口 `10.0.3.2`；东风路、龙洞校区 `10.0.3.6`。
- [访问学校无线网络操作指引](https://nic.gdut.edu.cn/info/1029/2396.htm)：连接 `gdut` 后用统一认证账号密码在网页登录。
- [宿舍网络排障指南](https://nic.gdut.edu.cn/info/1029/2747.htm)：大学城宿舍有带房号的 SSID，建议宿舍优先连接对应信号；随机 MAC 可能引起设备上限与掉线。

本次现场只核实 `10.0.3.2`，客户端目前也只允许该入口。`10.0.3.6` 虽是官方列出的其他校区入口，其协议一致性尚未现场验证，本版本不启用。

无线 AC 信息来自用户实际跳转：`wlanacip=172.16.254.2`，`wlanacname` 为空。`AssistantController` 将它作为当前大学城 `gdut` 连接配置传入核心；不是全校固定值。核心的配置请求对 AC IP 使用 Base64，登录请求使用原文。裸 `/` 和 `/a79.htm` 的只读响应均没有可用于动态发现 AC 的重定向，因此本版本尚未实现无线 AC 自动发现；若另一 SSID 的 AC 不同，须重新采集跳转并更新连接配置。缺少 AC 时核心拒绝提交无线登录。客户端 IP 仍从每次新页面中读取，不使用用户旧链接里的 IP。现场只读状态查询可能经过有线或代理路径，不能视为无线登录验证。

## 实际加载链与字段

`/a79.htm` 引用 `/a41.js`，后者在 `isJSMin=1` 时实际加载 `/a40.js`。压缩脚本版本 `jsVersion='4.1.3'`；另外读取了对应可读源码 `/a43.js`、`/a44.js` 和 `/a58.js` 作交叉核实。没有执行下载的 JavaScript。

1. `/a41.js` 的 `term.init`（约 837 行）从页面变量取得 IP、MAC、VLAN；原网页也接受 URL 参数。助手只使用新请求 `/a79.htm` 的变量，不接受旧重定向 URL 内的客户端 IP。`v46ip/ss5/v4ip` 取有效 IPv4，MAC 取 `ss4`，VLAN 取 `vlanid`。页面中的全零 MAC 是有效占位值，不编造设备标识。
2. `/a41.js` 的 `getPageInfo`（约 98 行）使用 GET JSONP `/eportal/portal/page/loadConfig`，HTTP 端口 `801`。字段：`program_index`、`wlan_vlan_id`、`wlan_user_ip`、`wlan_user_ipv6`、`wlan_user_ssid`、`wlan_user_areaid`、`wlan_ac_ip`、`wlan_ap_mac`、`gw_id`。配置请求的 IPv4 和 AC IP 使用 Base64，登录请求的 IPv4 不编码为 Base64。
3. 本次配置为 `login_method=1`、`is_vlan=1`、`en_md5=0`、`password_cut=0`、`enable_r3=0`、`account_prefix=1`、`en_perceive=0`、`check_online_method=0`、`ipv6_state=0`、`account_suffix=''`、`register_mode=1`、`io_mode=0`、`enable_https=0`。助手只支持这组关键协议开关；VLAN 开关允许 0 或 1。
4. `/a44.js` 第 3—58 行覆盖 `login.login`：`login_method=1` 路由到 `login_portal`。第 60—80 行传入 `login_method`、`user_account`、`user_password`、`wlan_user_ip`、`wlan_user_ipv6`、`wlan_user_mac`、`wlan_ac_ip`、`wlan_ac_name`、`jsVersion`。`/a43.js` 第 773—778 行决定账号前缀：普通电脑 `,0,`、手机 `,1,`。已核实配置不需要截断或 MD5；助手遇这些开关变化会停止自动认证。
5. `/a43.js` 第 976—1036 行的 `portal_login` 添加 `terminal_type`、`lang`，发送 GET JSONP `http://<入口>:801/eportal/portal/login`。`/a41.js` 第 629—674 行统一 URL 编码各字段，并添加 `callback`、`jsVersion`、随机 `v`、`lang`。响应 `result=1` 或 `result='ok'` 表示接口报告登录成功；助手随后重新读取入口、配置与状态确认同一个 IP 认证在线。
6. `/a41.js` 第 188—242 行的默认状态接口是 `http://<入口>/drcom/chkstatus`，`result=1` 在线，`result=0` 不在线。本次只读查询显示认证在线，因此未触发实际登录验证。认证在线不等于外网访问正常。

`/a79.htm` 内的 `authloginpath='/eportal/?c=ACSetting&a=Login'` 是客户端兼容元数据，不能据此替代实际网页加载链。

## 套餐与人工操作边界

`/a58.js` 第 19—55 行的 `custom.vlanOperator` 会先调用 `/eportal/portal/custom/operator?account=...&r=0`。源码把 `r=0` 注释为查询；若 `result='fail'`，原网页弹出“新计费系统首次 wifi 登录，是否开通”的确认，再由用户决定是否发送 `r=1`。

助手仅在用户执行登录时查询 `r=0`。只接受明确的 `code=1` 且 `result='ok'`；其他结果交回官方网页，绝不发送 `r=1`，也不代用户确认新套餐。查询返回其他成功形态的兼容性仍需现场核实。

登录前动态检查实际表单。当前电脑及手机页面验证码控件均隐藏。手机页面另有 `C1` 协议复选框和相对链接 `a09.htm`，即 `http://10.0.3.2/a09.htm`。只有用户在本次应用会话主动阅读链接并勾选同意，外层传入 `mobileAgreementAccepted=true`，且动态模板仍包含该精确链接时，核心才放行手机 `C1`。同意状态不持久化，默认值为 false。其他协议控件、可见验证码、运营商选择、其他账号前缀选择或脚本版本变化均停止自动认证。所有 JSONP 只按精确回调包装提取 JSON 后 `jsonDecode`，不使用 `eval`。

所有登录接口明确拒绝均为不可自动重试；不根据厂商 `ret_code` 猜测是否适宜重复提交密码。

## 传输和凭据要求

现场认证端点使用 HTTP，原网页的 GET 查询带账号密码；助手遵照核实的现有协议，不宣称加密传输。凭据只在本机由系统安全存储保存；传输层不得记录 URL、查询参数、响应原文或含请求地址的异常，也必须关闭 HTTP 重定向，避免把凭据转发到其他地址。核心校验入口白名单、响应大小、JSONP 包装与配置开关，用固定文字报告失败。

正式使用应先在连接到用户指定校园 Wi-Fi 时进行。核心只负责认证协议；平台网络识别、凭据存储、单任务互斥、有限退避和后台生命周期由外层管理。没有为未知校区、IPv6、MD5、第三方 AC 或新模板猜测参数。
