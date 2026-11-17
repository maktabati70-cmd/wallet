import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_config.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class RemoteConfig {
  RemoteConfig(Map<String, dynamic> j)
      : network = j['network'] as String,
        isTestnet = j['is_testnet'] as bool,
        explorerTxUrl = j['explorer_tx_url'] as String,
        sendingEnabled = j['sending_enabled'] as bool,
        serviceFeePercent = (j['fees'] as Map)['service_fee_percent'] as String,
        minServiceFee = (j['fees'] as Map)['min_service_fee'] as String,
        maxServiceFee = (j['fees'] as Map)['max_service_fee'] as String,
        minSend = (j['fees'] as Map)['min_send'] as String,
        maxSend = (j['fees'] as Map)['max_send'] as String,
        resourceDisclosure = (j['fees'] as Map)['resource_fee_disclosure'] as String;

  final String network;
  final bool isTestnet;
  final String explorerTxUrl;
  final bool sendingEnabled;
  final String serviceFeePercent;
  final String minServiceFee;
  final String maxServiceFee;
  final String minSend;
  final String maxSend;
  final String resourceDisclosure;
}

class Balance {
  Balance(Map<String, dynamic> j)
      : activated = j['activated'] as bool,
        usdtMicro = j['usdt_micro'] as int,
        trxSun = j['trx_sun'] as int;
  final bool activated;
  final int usdtMicro;
  final int trxSun;
}

class TxItem {
  TxItem(Map<String, dynamic> j)
      : txid = j['txid'] as String,
        time = DateTime.fromMillisecondsSinceEpoch(j['timestamp_ms'] as int),
        from = j['from'] as String,
        to = j['to'] as String,
        amountMicro = j['amount_micro'] as int,
        direction = j['direction'] as String,
        status = j['status'] as String,
        explorerUrl = j['explorer_url'] as String;

  final String txid;
  final DateTime time;
  final String from;
  final String to;
  final int amountMicro;
  final String direction; // in | out | self
  final String status; // confirmed | pending | failed
  final String explorerUrl;

  bool get incoming => direction == 'in';
  String get counterparty => incoming ? from : to;
}

class HistoryPage {
  HistoryPage(this.items, this.next);
  final List<TxItem> items;
  final String? next;
}

class FeeQuote {
  FeeQuote(Map<String, dynamic> j)
      : id = j['quote_id'] as String,
        expiresAt = DateTime.parse(j['expires_at'] as String),
        fromAddress = j['from_address'] as String,
        toAddress = j['to_address'] as String,
        amount = j['amount'] as String,
        serviceFee = j['service_fee'] as String,
        serviceFeePercent = j['service_fee_percent'] as String,
        resourceFee = j['resource_fee'] as String,
        totalFee = j['total_fee'] as String,
        recipientReceives = j['recipient_receives'] as String,
        recipientIsNew = j['recipient_is_new'] as bool,
        disclosure = j['resource_fee_disclosure'] as String,
        sendingEnabled = j['sending_enabled'] as bool;

  final String id;
  final DateTime expiresAt;
  final String fromAddress;
  final String toAddress;
  final String amount;
  final String serviceFee;
  final String serviceFeePercent;
  final String resourceFee;
  final String totalFee;
  final String recipientReceives;
  final bool recipientIsNew;
  final String disclosure;
  final bool sendingEnabled;
}

/// Talks to our backend only. The backend never receives keys or phrases.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();
  // Generous: a free-tier server may need ~1 minute to wake up.
  static const _timeout = Duration(seconds: 70);
  RemoteConfig? _config;

  Uri _u(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    final http.Response r;
    try {
      r = await call().timeout(_timeout);
    } on SocketException {
      throw ApiException('No internet connection.');
    } on TimeoutException {
      throw ApiException('The server is starting up. Please try again in a moment.');
    } on http.ClientException {
      throw ApiException('Could not reach the server.');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Unexpected server response.', r.statusCode);
    }
    if (r.statusCode >= 400) {
      throw ApiException(_errorText(body, r.statusCode), r.statusCode);
    }
    return body;
  }

  static String _errorText(Map<String, dynamic> body, int code) {
    final d = body['detail'];
    if (d is String) return d;
    if (d is List && d.isNotEmpty && d.first is Map) {
      final msg = (d.first as Map)['msg'];
      if (msg is String) return msg.replaceFirst('Value error, ', '');
    }
    if (code == 429) return 'Too many requests. Please wait a moment.';
    return 'Server error ($code).';
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> data) => _send(() =>
      _http.post(_u(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(data)));

  Future<RemoteConfig> config({bool refresh = false}) async {
    if (_config != null && !refresh) return _config!;
    _config = RemoteConfig(await _send(() => _http.get(_u('/v1/config'))));
    return _config!;
  }

  Future<Balance> balance(String address) async =>
      Balance(await _post('/v1/wallet/balance', {'address': address}));

  Future<HistoryPage> history(String address, {int limit = 20, String? next}) async {
    final j = await _post('/v1/wallet/history', {'address': address, 'limit': limit, 'fingerprint': next});
    final items = (j['items'] as List)
        .map((e) => TxItem(Map<String, dynamic>.from(e as Map)))
        .toList();
    return HistoryPage(items, j['next'] as String?);
  }

  Future<FeeQuote> quote({required String from, required String to, required String amount}) async =>
      FeeQuote(await _post('/v1/quotes', {'from_address': from, 'to_address': to, 'amount': amount}));
}
