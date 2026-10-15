import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/drcom_client.dart';

/// One operation owns one transport. Network changes cancel the whole operation.
final class DeviceTransport implements PortalTransport {
  static const _channel = MethodChannel('gdut_helper/wifi_http');
  static const _limit = 512 * 1024;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..findProxy = ((_) => 'DIRECT');
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  void _guard() {
    if (_cancelled) throw const PortalFailure('网络已变化，请重新检查。');
  }

  @override
  Future<PortalResponse> request(
    Uri uri, {
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
  }) async {
    _guard();
    if (uri.scheme != 'http' ||
        uri.host != '10.0.3.2' ||
        !{80, 801}.contains(uri.port) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !{'GET', 'POST'}.contains(method)) {
      throw const PortalFailure('认证请求地址不在允许范围内。');
    }
    try {
      final PortalResponse result;
      if (Platform.isAndroid) {
        final data = await _channel.invokeMapMethod<String, dynamic>(
          'request',
          {'url': uri.toString(), 'method': method, 'body': body, 'headers': headers},
        ).timeout(const Duration(seconds: 18));
        _guard();
        if (data == null || data['statusCode'] is! int || data['body'] is! String) {
          throw const PortalFailure('未能读取 Wi-Fi 认证响应。', retryable: true);
        }
        final text = data['body'] as String;
        if (utf8.encode(text).length > _limit * 3) {
          throw const PortalFailure('认证响应过大，请改用网页登录。');
        }
        result = PortalResponse(
          statusCode: data['statusCode'] as int,
          body: text,
          location: data['location'] as String?,
        );
      } else {
        result = await _requestDirect(uri, method, body, headers)
            .timeout(const Duration(seconds: 15));
      }
      _guard();
      if (result.statusCode >= 300 && result.statusCode < 400) {
        // Never forward a password to an address returned by the network.
        throw const PortalFailure('认证入口发生跳转，请先在浏览器确认登录页。');
      }
      if (result.statusCode != 200) {
        throw PortalFailure(
          '校园认证服务暂不可用（HTTP ${result.statusCode}）。',
          retryable: result.statusCode >= 500,
        );
      }
      return result;
    } on PortalFailure {
      rethrow;
    } on PlatformException catch (error) {
      // Do not expose native exception text: it may contain a credential URL.
      throw PortalFailure(
        error.code == 'NO_WIFI'
            ? '请连接校园 Wi-Fi；当前未找到可用的无线网络。'
            : '未能通过 Wi-Fi 访问认证服务。',
        retryable: true,
      );
    } on MissingPluginException {
      throw const PortalFailure('安卓网络适配尚未安装，请先运行项目初始化命令。');
    } on TimeoutException {
      cancel();
      throw const PortalFailure('访问校园认证服务超时。', retryable: true);
    } on SocketException {
      throw const PortalFailure('当前无法访问大学城校园网认证服务。', retryable: true);
    } on HttpException {
      throw const PortalFailure('认证连接已中断。', retryable: true);
    } catch (_) {
      throw const PortalFailure('读取认证服务失败，请稍后重试。', retryable: true);
    }
  }

  Future<PortalResponse> _requestDirect(
    Uri uri,
    String method,
    String? body,
    Map<String, String> headers,
  ) async {
    final request = await _client.openUrl(method, uri);
    _guard();
    request.followRedirects = false;
    headers.forEach((key, value) => request.headers.set(key, value));
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (body != null) request.add(utf8.encode(body));
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      _guard();
      if (bytes.length + chunk.length > _limit) {
        request.abort();
        throw const PortalFailure('认证响应过大，请改用网页登录。');
      }
      bytes.addAll(chunk);
    }
    return PortalResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes, allowMalformed: true),
      location: response.headers.value(HttpHeaders.locationHeader),
    );
  }
}
