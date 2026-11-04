import 'dart:async';
import 'package:flutter/material.dart';
import 'config.dart';
import 'profiles.dart';
import 'l10n.dart';

// ---------------- Exchange rates ----------------

String _fmtRate(double? v) {
  if (v == null) return '—';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

double? _rateMid(Map<String, dynamic> row) {
  final buy = asDouble(row['buy_rate']);
  final sell = asDouble(row['sell_rate']);
  if (buy == null || sell == null) return null;
  return (buy + sell) / 2;
}

String updatedAgo(DateTime? d) {
  if (d == null) return tr('unknown');
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return tr('just now');
  if (diff.inMinutes < 60) return tr('{n} min ago', {'n': diff.inMinutes});
  if (diff.inHours < 24) return tr('{n} h ago', {'n': diff.inHours});
  return tr('{n} days ago', {'n': diff.inDays});
}

class ExchangeRatesScreen extends StatefulWidget {
  const ExchangeRatesScreen({super.key});

  @override
  State<ExchangeRatesScreen> createState() => _ExchangeRatesScreenState();
}

class _ExchangeRatesScreenState extends State<ExchangeRatesScreen> {
  // pair -> source -> newest row
  Map<String, Map<String, Map<String, dynamic>>> rates = {};
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final data = await supabase
          .from('exchange_rates')
          .select()
          .order('updated_at', ascending: false);
      final rows = List<Map<String, dynamic>>.from(data);

      final grouped = <String, Map<String, Map<String, dynamic>>>{};
      for (final row in rows) {
        final pair = row['pair'].toString();
        final source = row['source'].toString();
        grouped.putIfAbsent(pair, () => {});
        // rows arrive newest-first, so keep the first one per source
        grouped[pair]!.putIfAbsent(source, () => row);
      }

      if (!mounted) return;
      setState(() {
        rates = grouped;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = tr('Could not load rates: {error}', {'error': e});
        loading = false;
      });
    }
  }

  Widget _rateRow(String label, Map<String, dynamic>? row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label)),
          Expanded(
            flex: 2,
            child: Text(
              row == null ? '—' : _fmtRate(asDouble(row['buy_rate'])),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row == null ? '—' : _fmtRate(asDouble(row['sell_rate'])),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pairCard(String pair, Map<String, Map<String, dynamic>> bySource) {
    final bank = bySource['bank'];
    final market = bySource['black_market'];

    String? gapText;
    if (bank != null && market != null) {
      final bankMid = _rateMid(bank);
      final marketMid = _rateMid(market);
      if (bankMid != null && marketMid != null && bankMid > 0) {
        final gap = (marketMid - bankMid) / bankMid * 100;
        gapText =
            tr(gap >= 0
                ? 'Parallel market is {pct}% higher than the bank'
                : 'Parallel market is {pct}% lower than the bank',
            {'pct': gap.abs().toStringAsFixed(0)});
      }
    }

    DateTime? newest;
    for (final row in [bank, market]) {
      final d = DateTime.tryParse(row?['updated_at']?.toString() ?? '');
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pair.replaceAll('/', ' → '),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(flex: 3, child: Text('')),
                Expanded(
                  flex: 2,
                  child: Text(tr('Buy'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: kMutedText, fontSize: 12)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(tr('Sell'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: kMutedText, fontSize: 12)),
                ),
              ],
            ),
            _rateRow(tr('Bank'), bank),
            _rateRow(tr('Parallel market'), market),
            if (gapText != null) ...[
              const SizedBox(height: 8),
              Text(gapText, style: const TextStyle(color: Colors.deepOrange)),
            ],
            const SizedBox(height: 8),
            Text(
              tr('Updated {ago}', {'ago': updatedAgo(newest)}),
              style: const TextStyle(fontSize: 12, color: kMutedText),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pairs = rates.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Exchange rates'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? ListView(
                    children: [
                      const SizedBox(height: 100),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  )
                : pairs.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(height: 100),
                          Center(child: Text(tr('No rates available yet.'))),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final pair in pairs)
                            _pairCard(pair, rates[pair]!),
                          Text(
                            tr('Buy = what you get when you sell foreign currency. Sell = what you pay to buy it. These rates are indicative and updated by hand, so always agree the exact rate with the other person before exchanging anything.'),
                            style: TextStyle(fontSize: 12, color: kMutedText),
                          ),
                        ],
                      ),
      ),
    );
  }
}
