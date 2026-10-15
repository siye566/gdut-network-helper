import 'dart:async';
import 'dart:convert';

class PortalResponse {
  final int statusCode;
  final String body;
  final String? location;
  const PortalResponse({
    required this.statusCode,
    required this.body,
    this.location,
  });
}

abstract interface class PortalTransport {
  Future<PortalResponse> request(Uri uri, {
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
  });
}

class Credentials {
  final String username;
  final String password;
  const Credentials(this.username, this.password);
}

enum PortalState { online, needsLogin, unsupported }

class PortalSnapshot {
  final PortalState state;
  final String clientIp;
  final String message;
  const PortalSnapshot({
    required this.state,
    required this.clientIp,
    required this.message,
  });
}

class PortalFailure implements Exception {
  final String message;
  final bool retryable;
  const PortalFailure(this.message, {this.retryable = false});
  @override
  String toString() => message;
}

/// Implements only the GDUT configuration observed on 2026-10-15.
/// The transport must disable redirects and must never log request URLs.
class DrcomClient {
  final PortalTransport _transport;
  final Uri _gateway;
  final int terminalType;
  final bool mobileAgreementAccepted;
  final String wlanAcIp;
  final String wlanAcName;
  int _sequence = 0;

  DrcomClient(PortalTransport transport, {
    Uri? gateway,
    this.terminalType = 1,
    this.mobileAgreementAccepted = false,
    this.wlanAcIp = '',
    this.wlanAcName = '',
  })
      : _transport = transport,
        _gateway = gateway ?? Uri.parse('http://10.0.3.2') {
    if (_gateway.host != '10.0.3.2' ||
        _gateway.scheme != 'http' || _gateway.port != 80 ||
        _gateway.userInfo.isNotEmpty || _gateway.hasQuery ||
        _gateway.hasFragment ||
        !{'', '/'}.contains(_gateway.path) ||
        !{1, 2}.contains(terminalType)) {
      throw const PortalFailure('不支持的校园认证入口或终端类型。');
    }
    if (wlanAcIp.isNotEmpty && !_validAcIp(wlanAcIp) ||
        wlanAcName.length > 128 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(wlanAcName)) {
      throw const PortalFailure('无线认证控制器配置无效，请重新采集认证页地址。');
    }
  }

  Future<PortalSnapshot> inspect() async {
    final context = await _readContext();
    if (context.online) return _snapshot(context, PortalState.online);
    return _snapshot(context, _supported(context.config)
        ? PortalState.needsLogin : PortalState.unsupported);
  }

  Future<PortalSnapshot> login(Credentials credentials) async {
    // Obtain the address and settings from the gateway on every attempt.
    final context = await _readContext();
    if (context.online) return _snapshot(context, PortalState.online);
    if (!_supported(context.config)) {
      return _snapshot(context, PortalState.unsupported);
    }
    if (wlanAcIp.isEmpty) {
      throw const PortalFailure('缺少本次无线网络的认证控制器，请重新采集浏览器认证页地址。');
    }
    if (!RegExp(r'^[A-Za-z0-9_.@-]{1,64}$').hasMatch(credentials.username) ||
        credentials.password.isEmpty || credentials.password.length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(credentials.password)) {
      throw const PortalFailure('请在本机填写有效的账号和密码。');
    }

    final version = await _checkLoginPage(context);
    if (_field(context.config, 'is_vlan') == '1') {
      // r=0 is the official page's query. r=1 activates a package and is
      // deliberately never implemented or sent by this client.
      final operator = await _jsonp('/eportal/portal/custom/operator', {
        'account': credentials.username,
        'r': '0',
      }, port: 801, version: version);
      if (operator['code']?.toString() != '1' ||
          operator['result']?.toString() != 'ok') {
        return const PortalSnapshot(
          state: PortalState.unsupported,
          clientIp: '',
          message: '套餐查询需要人工确认，请在官方认证网页处理后再试。',
        );
      }
    }

    // A switch while settings or package queries were loading invalidates
    // this attempt. Never submit a password using a cached client address.
    final latest = await _readLanding();
    if (latest.ip != context.landing.ip ||
        latest.mac != context.landing.mac) {
      throw const PortalFailure('网络已切换，正在等待新连接稳定。', retryable: true);
    }
    final prefix = terminalType == 2 ? ',1,' : ',0,';
    final result = await _jsonp('/eportal/portal/login', {
      'login_method': '1',
      'user_account': '$prefix${credentials.username}',
      'user_password': credentials.password,
      'wlan_user_ip': latest.ip,
      'wlan_user_ipv6': '',
      'wlan_user_mac': latest.mac,
      'wlan_ac_ip': wlanAcIp,
      'wlan_ac_name': wlanAcName,
      'terminal_type': '$terminalType',
      'lang': 'zh',
    }, port: 801, version: version);
    if (!{'1', 'ok'}.contains(result['result']?.toString())) {
      // A rejected credential-bearing request must never trigger an
      // automatic retry based on a vendor-specific error code.
      throw const PortalFailure(
        '认证未通过，请在官方网页检查账号、套餐或设备上限。',
      );
    }
    final verified = await _readContext();
    if (!verified.online || verified.landing.ip != latest.ip) {
      throw const PortalFailure('尚未确认当前连接认证在线，请重新检查。', retryable: true);
    }
    return _snapshot(verified, PortalState.online);
  }

  Future<_Context> _readContext() async {
    final landing = await _readLanding();
    final response = await _jsonp('/eportal/portal/page/loadConfig', {
      'program_index': '',
      'wlan_vlan_id': landing.vlan,
      'wlan_user_ip': base64Encode(utf8.encode(landing.ip)),
      'wlan_user_ipv6': '',
      'wlan_user_ssid': '',
      'wlan_user_areaid': '',
      'wlan_ac_ip': base64Encode(utf8.encode(wlanAcIp)),
      'wlan_ap_mac': '000000000000',
      'gw_id': '000000000000',
    }, port: 801);
    if (response['code']?.toString() != '1' || response['data'] is! Map) {
      throw const PortalFailure('无法读取校园认证配置，请打开官方认证网页。');
    }
    final config = Map<String, dynamic>.from(response['data'] as Map);
    // The observed gateway uses the kernel status endpoint; other modes
    // require additional protocol support rather than assuming offline.
    if (_field(config, 'check_online_method') != '0') {
      return _Context(landing, config, false);
    }
    final status = await _jsonp('/drcom/chkstatus', {});
    final value = status['result']?.toString();
    if (value != '0' && value != '1') {
      throw const PortalFailure('校园认证状态格式已变化，请打开官方网页。');
    }
    final statusIp = status['v46ip'] ?? status['ss5'] ?? status['v4ip'];
    if (statusIp is String && statusIp.trim().isNotEmpty &&
        statusIp.trim() != landing.ip) {
      throw const PortalFailure('网络地址正在变化，请稍后重试。', retryable: true);
    }
    return _Context(landing, config, value == '1');
  }

  bool _supported(Map<String, dynamic> config) {
    const expected = {
      'login_method': '1', 'en_md5': '0', 'password_cut': '0',
      'enable_r3': '0', 'account_prefix': '1', 'en_perceive': '0',
      'check_online_method': '0', 'ipv6_state': '0', 'io_mode': '0',
      'register_mode': '1', 'enable_https': '0',
    };
    return expected.entries.every((e) => _field(config, e.key) == e.value) &&
        config.containsKey('account_suffix') &&
        _field(config, 'account_suffix').isEmpty &&
        {'0', '1'}.contains(_field(config, 'is_vlan'));
  }

  Future<_Landing> _readLanding() async {
    final html = await _get(_gateway.resolve('/a79.htm'));
    if (!html.contains('Dr.COMWebLoginID_')) {
      throw const PortalFailure('当前页面不是已支持的校园认证页。');
    }
    String variable(String name) {
      final pattern = RegExp(
        '\\b${RegExp.escape(name)}\\s*=\\s*([\'\"])([^\'\"]*)[\'\"]',
      );
      return pattern.firstMatch(html)?.group(2)?.trim() ?? '';
    }
    final ip = [variable('v46ip'), variable('ss5'), variable('v4ip')]
        .firstWhere(_validIp, orElse: () => '');
    final mac = variable('ss4').replaceAll(RegExp(r'[:-]'), '');
    final vlan = variable('vlanid');
    if (ip.isEmpty || !RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(mac) ||
        !RegExp(r'^\d{1,4}$').hasMatch(vlan) || int.parse(vlan) > 4095) {
      throw const PortalFailure('无法从校园认证页确认当前连接地址。', retryable: true);
    }
    return _Landing(ip, mac, vlan);
  }

  Future<String> _checkLoginPage(_Context context) async {
    final config = context.config;
    final program = _field(config, 'program_index');
    final index = _field(config, 'page_index');
    if (![program, index].every((s) =>
        RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(s))) {
      throw const PortalFailure('认证页面配置已变化，请使用官方网页。');
    }
    final script = await _get(_gateway.resolve('/a40.js'), maxLength: 1500000);
    final version = RegExp(r'''\bjsVersion\s*=\s*['"]([0-9.]{1,20})['"]''')
        .firstMatch(script)?.group(1);
    if (version != '4.1.3' || !script.contains('login.login_portal=function') ||
        !script.contains("page.portal_api+\"custom/operator\"")) {
      throw const PortalFailure('认证脚本版本已变化，请使用官方网页。');
    }
    final kind = terminalType == 2 ? 'mobile' : 'pc';
    final templateUri = _gateway.replace(
      port: 801,
      path: '/eportal/extern/$program/$index/$kind.js',
    );
    final template = (await _get(templateUri, maxLength: 1000000))
        .replaceAll(r'\"', '"').replaceAll(r"\'", "'");
    if (!template.contains('bodyContent=') || !template.contains('name="DDDDD"') ||
        !template.contains('name="upass"')) {
      throw const PortalFailure('认证表单无法识别，请使用官方网页。');
    }
    for (final tag in RegExp(r'<(?:input|select|div)\b[^>]*>', caseSensitive: false)
        .allMatches(template).map((m) => m.group(0)!)) {
      final name = RegExp(r'''\bname\s*=\s*['"]([^'"]+)['"]''',
          caseSensitive: false).firstMatch(tag)?.group(1);
      if (name == 'captcha' &&
          !RegExp(r'display\s*:\s*none', caseSensitive: false).hasMatch(tag)) {
        throw const PortalFailure('当前认证需要验证码，请使用官方网页。');
      }
      if (name == 'C1') {
        final agreementLink = RegExp(
          r'''\bhref\s*=\s*['"]a09\.htm['"]''',
          caseSensitive: false,
        ).hasMatch(template);
        if (terminalType != 2 || !mobileAgreementAccepted || !agreementLink) {
          throw const PortalFailure('请先阅读并主动同意官方上网服务协议。');
        }
      }
      if ({'ISP_select', 'ISP_radio', 'checkIOMode', 'checkPerceive'}
          .contains(name)) {
        throw const PortalFailure('当前认证需要人工选择或确认，请使用官方网页。');
      }
    }
    return version!;
  }

  Future<Map<String, dynamic>> _jsonp(String path, Map<String, String> data,
      {int port = 80, String version = '4.X'}) async {
    final callback = 'gdutHelper${++_sequence}';
    final uri = _gateway.replace(port: port, path: path, queryParameters: {
      'callback': callback,
      ...data,
      'jsVersion': version,
      'v': '${DateTime.now().microsecondsSinceEpoch % 10000 + 500}',
      'lang': 'zh',
    });
    final response = await _get(uri);
    // Accept only the exact callback plus a JSON object. Never execute JS.
    final wrapper = RegExp(
      '^\\s*${RegExp.escape(callback)}\\s*\\((\\{[\\s\\S]*\\})\\)\\s*;?\\s*\$',
    ).firstMatch(response);
    if (wrapper == null) {
      throw const PortalFailure('认证响应格式已变化，请使用官方网页。');
    }
    try {
      final value = jsonDecode(wrapper.group(1)!);
      if (value is! Map<String, dynamic>) throw const FormatException();
      return value;
    } catch (_) {
      throw const PortalFailure('认证响应格式无效，请使用官方网页。');
    }
  }

  Future<String> _get(Uri uri, {int maxLength = 262144}) async {
    try {
      final response = await _transport.request(uri, headers: const {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      }).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || response.location != null ||
          response.body.isEmpty || response.body.length > maxLength) {
        throw const PortalFailure('校园认证响应异常，请打开官方网页检查。');
      }
      return response.body;
    } on PortalFailure {
      rethrow;
    } catch (_) {
      // Transport exceptions can include credential-bearing GET URLs.
      throw const PortalFailure('暂时无法连接校园认证服务。', retryable: true);
    }
  }

  static bool _validIp(String value) {
    final pieces = value.split('.');
    if (pieces.length != 4 || pieces.any((s) => !RegExp(r'^\d{1,3}$').hasMatch(s))) {
      return false;
    }
    final octets = pieces.map(int.parse).toList();
    return octets.every((i) => i <= 255) && octets.first == 10;
  }

  static bool _validAcIp(String value) {
    final pieces = value.split('.');
    if (pieces.length != 4 || pieces.any((s) => !RegExp(r'^\d{1,3}$').hasMatch(s))) {
      return false;
    }
    final octets = pieces.map(int.parse).toList();
    if (octets.any((i) => i > 255)) return false;
    return octets[0] == 10 ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168);
  }

  static String _field(Map<String, dynamic> map, String key) =>
      map[key]?.toString() ?? '';

  PortalSnapshot _snapshot(_Context context, PortalState state) => PortalSnapshot(
    state: state,
    clientIp: context.landing.ip,
    message: switch (state) {
      PortalState.online => '当前连接的校园认证在线。',
      PortalState.needsLogin => '当前连接需要校园网认证。',
      PortalState.unsupported => '认证配置尚未支持，请使用官方认证网页。',
    },
  );
}

class _Landing {
  final String ip;
  final String mac;
  final String vlan;
  const _Landing(this.ip, this.mac, this.vlan);
}

class _Context {
  final _Landing landing;
  final Map<String, dynamic> config;
  final bool online;
  const _Context(this.landing, this.config, this.online);
}
