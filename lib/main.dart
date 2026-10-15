import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'assistant_controller.dart';
import 'core/drcom_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CampusApp());
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '广工校园网助手',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff16675d)),
        scaffoldBackgroundColor: const Color(0xfff4f6f3),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const CampusHome(),
    );
  }
}

class CampusHome extends StatefulWidget {
  const CampusHome({super.key});

  @override
  State<CampusHome> createState() => _CampusHomeState();
}

class _CampusHomeState extends State<CampusHome> {
  static const _storageKey = 'gdut_helper_settings_v1';
  final _storage = const FlutterSecureStorage();
  final _assistant = AssistantController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  Credentials? _saved;
  bool _ready = false;
  bool _saving = false;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _assistant.initialize();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (!mounted) return;
      if (raw != null) {
        final value = jsonDecode(raw);
        if (value is! Map<String, dynamic> ||
            value['username'] is! String || value['password'] is! String) {
          throw const FormatException('invalid settings');
        }
        final username = value['username'] as String;
        final password = value['password'] as String;
        if (username.isNotEmpty && password.isNotEmpty) {
          _saved = Credentials(username, password);
          _username.text = username;
          _password.text = password;
          _assistant.setCredentials(_saved);
          _assistant.setAutomatic(value['automatic'] == true);
        }
      }
    } catch (_) {
      if (!mounted) return;
      _storageError = '未能读取系统安全存储。请检查本机权限，再保存账号。';
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _persist(Credentials credentials, bool automatic) {
    return _storage.write(
      key: _storageKey,
      value: jsonEncode({
        'username': credentials.username,
        'password': credentials.password,
        'automatic': automatic,
      }),
    );
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      _notice('请输入校园网账号和密码。');
      return;
    }
    setState(() => _saving = true);
    try {
      final credentials = Credentials(username, password);
      await _persist(credentials, _assistant.automatic);
      if (!mounted) return;
      _saved = credentials;
      _assistant.setCredentials(credentials);
      setState(() => _storageError = null);
      _notice('已保存到本机安全存储。');
      if (_assistant.automatic) _assistant.check();
    } catch (_) {
      if (mounted) setState(() => _storageError = '保存失败，请检查系统安全存储；账号尚未更新。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setAutomatic(bool value) async {
    if (_saved == null) {
      _notice('请先保存账号，再开启自动认证。');
      return;
    }
    setState(() => _saving = true);
    // Pausing takes effect immediately even if local storage is unavailable.
    if (!value) _assistant.setAutomatic(false);
    try {
      await _persist(_saved!, value);
      if (!mounted) return;
      _assistant.setAutomatic(value);
      setState(() => _storageError = null);
    } catch (_) {
      if (mounted) setState(() => _storageError = '未能保存自动认证设置，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _forget() async {
    setState(() => _saving = true);
    _assistant.setAutomatic(false);
    _assistant.setCredentials(null);
    _saved = null;
    _username.clear();
    _password.clear();
    try {
      await _storage.delete(key: _storageKey);
      if (!mounted) return;
      setState(() => _storageError = null);
      _notice('已删除本机保存的账号。');
    } catch (_) {
      if (mounted) setState(() => _storageError = '已停止认证，但系统存储删除失败，请再次点击清除账号。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openOfficialPage(String path) async {
    final uri = Uri(scheme: 'http', host: '10.0.3.2', path: path);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Fall back to copying only a fixed, credential-free official URL.
    }
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    _notice('无法打开浏览器，已复制地址，请手动打开。');
  }

  @override
  void dispose() {
    _assistant.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _assistant,
      builder: (context, _) {
        final locked = !_ready || _saving || _assistant.busy;
        return Scaffold(
          appBar: AppBar(
            title: const Text('广工校园网助手'),
            backgroundColor: Colors.transparent,
            actions: const [Padding(padding: EdgeInsets.all(16), child: Text('大学城 · v0.1'))],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('走到哪里，连到哪里。', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    const Text('在宿舍无线网与 gdut 之间切换时，检查认证状态并按需登录。'),
                    const SizedBox(height: 24),
                    _statusCard(),
                    const SizedBox(height: 20),
                    LayoutBuilder(builder: (context, constraints) {
                      final account = _accountCard(locked);
                      final activity = _activityCard();
                      if (constraints.maxWidth < 720) {
                        return Column(children: [account, const SizedBox(height: 20), activity]);
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Expanded(child: account), const SizedBox(width: 20), Expanded(child: activity)],
                      );
                    }),
                    const SizedBox(height: 20),
                    Text(
                      Platform.isAndroid || Platform.isIOS
                          ? '手机当前支持打开助手时检查和认证。切到后台后受系统限制，返回助手会重新检查。'
                          : '保持程序运行即可定时检查；最小化可继续工作，退出后停止。当前版本尚未接入托盘和开机启动。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('“认证在线”表示学校认证服务返回在线状态，不代表所有外网服务均可访问。', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusCard() {
    final active = _assistant.phase == AssistantPhase.online;
    final title = switch (_assistant.phase) {
      AssistantPhase.paused => '等待连接',
      AssistantPhase.checking => '正在检查',
      AssistantPhase.waiting => '等待重试',
      AssistantPhase.credentials => '需要保存账号',
      AssistantPhase.signingIn => '正在认证',
      AssistantPhase.online => '认证在线',
      AssistantPhase.attention => '需要处理',
    };
    return Card(
      color: active ? const Color(0xffe0efe7) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(active ? Icons.wifi_rounded : Icons.wifi_find_rounded, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            if (_assistant.busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 12),
          Text(_assistant.message),
          if (_assistant.clientIp.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('当前校园 IP  ${_assistant.clientIp}', style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_assistant.lastChecked != null) ...[
            const SizedBox(height: 6),
            Text('最近检查  ${_assistant.lastChecked!.toLocal().toString().substring(0, 19)}', style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: !_ready || _saving || _assistant.busy ? null : () => _assistant.check(manual: true),
              icon: const Icon(Icons.refresh),
              label: const Text('检查并认证'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openOfficialPage('/a79.htm'),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('打开网页登录'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _accountCard(bool locked) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('本机账号', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('使用网页登录时的账号和密码，输入完整账号。'),
          const SizedBox(height: 20),
          TextField(
            controller: _username,
            enabled: !locked,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '校园网账号', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            enabled: !locked,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '校园网密码', prefixIcon: Icon(Icons.lock_outline)),
          ),
          const SizedBox(height: 16),
          if (Platform.isAndroid || Platform.isIOS) ...[
            TextButton.icon(
              onPressed: () => _openOfficialPage('/a09.htm'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('查看学校《服务协议》'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('我已阅读并同意学校《服务协议》'),
              subtitle: const Text('由你主动确认；本次退出助手后不保留此选项。'),
              value: _assistant.mobileAgreementAccepted,
              onChanged: locked ? null : (value) => _assistant.setMobileAgreementAccepted(value ?? false),
            ),
            const SizedBox(height: 12),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动认证'),
            subtitle: const Text('运行期间检查切网与认证状态'),
            value: _assistant.automatic,
            onChanged: !_ready || _saving || (_assistant.busy && !_assistant.automatic)
                ? null
                : _setAutomatic,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton(onPressed: locked ? null : _save, child: const Text('保存账号')),
            TextButton(onPressed: locked ? null : _forget, child: const Text('清除账号')),
          ]),
          if (_storageError != null) ...[
            const SizedBox(height: 12),
            Text(_storageError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          const Text('账号保存在系统安全存储中，不上传到第三方。认证请求直接发送到学校门户；该门户目前使用 HTTP。', style: TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _activityCard() {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('最近活动', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (_assistant.events.isEmpty) const Text('等待第一次检查。')
          else ..._assistant.events.take(8).map((event) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(event, style: const TextStyle(fontSize: 13, height: 1.6)),
          )),
          const Divider(height: 32),
          const Text('如何使用', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('1. 连接 gdut 或宿舍无线网。\n2. 保存自己的校园网账号。\n3. 点击“检查并认证”，确认后开启自动认证。', style: TextStyle(height: 1.8)),
        ]),
      ),
    );
  }
}
