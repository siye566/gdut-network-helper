import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'core/drcom_client.dart';
import 'platform/device_transport.dart';

enum AssistantPhase { paused, checking, waiting, credentials, signingIn, online, attention }

final class AssistantController extends ChangeNotifier with WidgetsBindingObserver {
  // Captured from the user's university-town gdut redirect, not a school-wide constant.
  // A different wireless controller requires a fresh portal redirect/profile.
  final String wlanAcIp;
  final String wlanAcName;
  AssistantController({this.wlanAcIp = '172.16.254.2', this.wlanAcName = ''});
  AssistantPhase phase = AssistantPhase.paused;
  String message = '连接 gdut 或宿舍无线网后，点击检查。';
  String clientIp = '';
  bool automatic = false;
  bool busy = false;
  DateTime? lastChecked;
  final List<String> events = [];

  Credentials? _credentials;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _periodic;
  Timer? _debounce;
  DeviceTransport? _active;
  int _epoch = 0;
  int _failures = 0;
  DateTime? _nextAttempt;
  bool _blocked = false;
  bool _disposed = false;
  bool _mobileSuspended = false;
  bool mobileAgreementAccepted = false;

  void setMobileAgreementAccepted(bool value) {
    _invalidate();
    mobileAgreementAccepted = value;
    _notify();
    if (value && automatic) unawaited(check());
  }

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    _subscription = Connectivity().onConnectivityChanged.listen(
      (_) => _networkChanged(),
      onError: (_) => _log('系统网络通知不可用，仍会定时检查。'),
    );
    // Covers roaming where the network type remains Wi-Fi and no event arrives.
    _periodic = Timer.periodic(const Duration(seconds: 30), (_) {
      if (automatic && !_mobileSuspended) unawaited(check());
    });
  }

  void setCredentials(Credentials? value) {
    _invalidate();
    _credentials = value;
    _blocked = false;
    _failures = 0;
    _nextAttempt = null;
    phase = AssistantPhase.paused;
    message = value == null ? '已清除本机保存的账号。' : '账号已保存，可以检查校园网。';
    _notify();
  }

  void setAutomatic(bool value) {
    _invalidate();
    automatic = value;
    _failures = 0;
    _nextAttempt = null;
    // Changing this switch does not clear a rejected credential block.
    phase = AssistantPhase.paused;
    message = value ? '自动认证已开启，正在等待校园网。' : '自动认证已暂停。';
    _notify();
    if (value) unawaited(check());
  }

  void _networkChanged() {
    _invalidate();
    _debounce?.cancel();
    clientIp = '';
    if (!_blocked) {
      // A newly connected network may be campus Wi-Fi after failures elsewhere.
      _failures = 0;
      _nextAttempt = null;
    }
    _debounce = Timer(const Duration(seconds: 2), () {
      if (automatic && !_mobileSuspended) unawaited(check());
    });
  }

  void _invalidate() {
    _epoch++;
    _active?.cancel();
  }

  /// Manual checks bypass the delay but never silently submit rejected credentials.
  Future<void> check({bool manual = false}) async {
    if (_disposed || busy || _mobileSuspended) return;
    if (!manual && (!automatic || _blocked)) return;
    if (!manual && _nextAttempt != null && DateTime.now().isBefore(_nextAttempt!)) return;
    if (!manual && _failures >= 3) return;

    final epoch = _epoch;
    final transport = DeviceTransport();
    _active = transport;
    final client = DrcomClient(
      transport,
      terminalType: Platform.isAndroid || Platform.isIOS ? 2 : 1,
      mobileAgreementAccepted: mobileAgreementAccepted,
      wlanAcIp: wlanAcIp,
      wlanAcName: wlanAcName,
    );
    busy = true;
    phase = AssistantPhase.checking;
    message = '正在检查大学城校园认证服务…';
    _notify();
    try {
      var snapshot = await client.inspect();
      if (_disposed || epoch != _epoch) return;
      clientIp = snapshot.clientIp;
      lastChecked = DateTime.now();
      if (snapshot.state == PortalState.unsupported) {
        throw PortalFailure(snapshot.message);
      }
      if (snapshot.state == PortalState.needsLogin) {
        if (_blocked) {
          phase = AssistantPhase.attention;
          message = '上次认证被拒绝，请核对并重新保存账号，或使用网页登录。';
          return;
        }
        if (!automatic && !manual) return;
        if (_credentials == null) {
          phase = AssistantPhase.credentials;
          message = '校园网需要认证，请先保存自己的账号密码。';
          return;
        }
        if ((Platform.isAndroid || Platform.isIOS) && !mobileAgreementAccepted) {
          phase = AssistantPhase.attention;
          message = '请先查看并同意学校服务协议，再进行手机认证。';
          return;
        }
        phase = AssistantPhase.signingIn;
        message = '正在使用当前网络参数认证…';
        _notify();
        snapshot = await client.login(_credentials!);
        if (_disposed || epoch != _epoch) return;
        if (snapshot.state == PortalState.unsupported) {
          throw PortalFailure(snapshot.message);
        }
        if (snapshot.state != PortalState.online) {
          throw const PortalFailure('认证尚未确认成功，请使用网页登录检查。');
        }
      }
      phase = AssistantPhase.online;
      message = '校园网认证在线';
      clientIp = snapshot.clientIp;
      _failures = 0;
      _nextAttempt = null;
      _log('校园认证服务已确认在线。');
    } on PortalFailure catch (error) {
      if (_disposed || epoch != _epoch) return;
      lastChecked = DateTime.now();
      _failures++;
      if (error.retryable && _failures < 3) {
        _nextAttempt = DateTime.now().add(Duration(seconds: _failures == 1 ? 10 : 30));
        phase = AssistantPhase.waiting;
        message = automatic
            ? '${error.message} 稍后重试（$_failures/3）。'
            : '${error.message} 请稍后点击检查。';
      } else {
        _blocked = !error.retryable;
        phase = AssistantPhase.attention;
        message = error.retryable
            ? '${error.message} 已暂停重试，点击检查可再试一次。'
            : error.message;
      }
      _log(message);
    } catch (_) {
      if (_disposed || epoch != _epoch) return;
      _blocked = true;
      phase = AssistantPhase.attention;
      message = '检查未完成，已暂停自动认证，请使用网页登录。';
      _log(message);
    } finally {
      transport.cancel();
      if (identical(_active, transport)) _active = null;
      busy = false;
      if (!_disposed && epoch != _epoch) {
        phase = AssistantPhase.paused;
        message = '网络或设置已变化，等待下一次检查。';
      }
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _mobileSuspended = true;
      _invalidate();
    } else if (state == AppLifecycleState.resumed) {
      _mobileSuspended = false;
      _networkChanged();
    }
  }

  void _log(String value) {
    if (_disposed) return;
    // Only locally defined messages enter this log, never raw server responses.
    if (events.isNotEmpty && events.first.endsWith(value)) return;
    final now = DateTime.now();
    events.insert(0, '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}  $value');
    if (events.length > 20) events.removeLast();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _periodic?.cancel();
    _debounce?.cancel();
    _invalidate();
    super.dispose();
  }
}
