import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../widgets/common.dart';
import 'tx_details_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = ApiClient.instance;
  final List<TxItem> _items = [];
  String? _next;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _next = null;
      _done = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.history(WalletSession.instance.address ?? '', limit: 20, next: _next);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _next = page.next;
        _done = page.next == null || page.items.isEmpty;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction history')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length + 1,
          itemBuilder: (context, i) {
            if (i < _items.length) {
              final tx = _items[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: TxTile(tx,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => TxDetailsScreen(tx: tx)))),
                ),
              );
            }
            if (_error != null) return ErrorRetry(message: _error!, onRetry: _loadMore);
            if (_loading) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No transactions yet')),
              );
            }
            if (_done) return const SizedBox(height: 24);
            return TextButton(onPressed: _loadMore, child: const Text('Load more'));
          },
        ),
      ),
    );
  }
}
