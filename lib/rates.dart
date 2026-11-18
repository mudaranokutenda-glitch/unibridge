import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'app_theme.dart';
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

// Used when the setting cannot be read (the table may not exist yet).
const double kDefaultParallelOffset = -2;

// The parallel-market row as it is SHOWN: the offset is added to buy and sell.
// The stored data is not changed.
Map<String, dynamic>? _withOffset(Map<String, dynamic>? row, double offset) {
  if (row == null) return null;
  final buy = asDouble(row['buy_rate']);
  final sell = asDouble(row['sell_rate']);
  return {
    ...row,
    'buy_rate': buy == null ? null : buy + offset,
    'sell_rate': sell == null ? null : sell + offset,
  };
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
  // DZD added to the parallel-market rates when they are SHOWN (table app_settings).
  double offset = kDefaultParallelOffset;

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

      // The offset for the parallel-market rates (admin changes it in SQL).
      var loadedOffset = kDefaultParallelOffset;
      try {
        final row = await supabase
            .from('app_settings')
            .select('value')
            .eq('key', 'parallel_rate_offset')
            .maybeSingle();
        loadedOffset = asDouble(row?['value']) ?? kDefaultParallelOffset;
      } catch (e) {
        debugPrint('Could not read the rate offset, using the default: $e');
      }

      if (!mounted) return;
      setState(() {
        rates = grouped;
        offset = loadedOffset;
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
    final market = _withOffset(bySource['black_market'], offset);

    String? gapText;
    if (bank != null && market != null) {
      final bankMid = _rateMid(bank);
      final marketMid = _rateMid(market);
      if (bankMid != null && marketMid != null && bankMid > 0) {
        final gap = (marketMid - bankMid) / bankMid * 100;
        gapText =
            tr(gap >= 0
                ? 'Indicative rate is {pct}% higher than the bank'
                : 'Indicative rate is {pct}% lower than the bank',
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
            _rateRow(tr('Indicative rate (Annaba)'), market),
            if (gapText != null) ...[
              const SizedBox(height: 8),
              Text(gapText, style: const TextStyle(color: AppColors.warning)),
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
                            style: const TextStyle(color: AppColors.cancelled),
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
                          _RateCalculator(
                              rates: {
                            for (final cur in ['USD', 'EUR'])
                              cur: _withOffset(
                                  rates['$cur/DZD']?['black_market'], offset),
                          }),
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

// ---------------- Calculator (at the top of the rates screen) ----------------
// Uses only the DISPLAYED indicative rates (parallel market with the offset).
// Amount = foreign currency. Result = dinars (DA).
//   I send foreign currency / I receive DA : amount x buy rate
//   I receive foreign currency / I send DA : amount x sell rate

class _RateCalculator extends StatefulWidget {
  // 'USD' / 'EUR' -> the displayed row (buy_rate, sell_rate), or null
  final Map<String, Map<String, dynamic>?> rates;
  const _RateCalculator({required this.rates});

  @override
  State<_RateCalculator> createState() => _RateCalculatorState();
}

class _RateCalculatorState extends State<_RateCalculator> {
  String currency = 'USD';
  bool iSendForeign = true; // true: I send foreign currency, I receive DA
  final amountController = TextEditingController();

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  String _thousands(double v) {
    final whole = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(' ');
      b.write(whole[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.rates[currency];
    final rate =
        asDouble(row?[iSendForeign ? 'buy_rate' : 'sell_rate']);
    final amount =
        double.tryParse(amountController.text.trim().replaceAll(',', '.'));

    String result;
    if (rate == null) {
      result = tr('No rate available for {currency}.', {'currency': currency});
    } else if (amount == null) {
      result = '';
    } else {
      result = '${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)} $currency'
          ' ${iSendForeign ? '→' : '←'} ${_thousands(amount * rate)} DA';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Calculator'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'USD', label: Text('USD')),
                ButtonSegment(value: 'EUR', label: Text('EUR')),
              ],
              selected: {currency},
              onSelectionChanged: (v) => setState(() => currency = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: InputDecoration(
                  labelText: tr('Amount in {currency}', {'currency': currency})),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: iSendForeign,
              onChanged: (v) => setState(() => iSendForeign = v ?? true),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: true,
                    title: Text(tr('I send foreign currency / I receive DA')),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: false,
                    title: Text(tr('I receive foreign currency / I send DA')),
                  ),
                ],
              ),
            ),
            if (result.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(result,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 8),
            Text(tr('Indicative, not a guarantee'),
                style: const TextStyle(fontSize: 12, color: kMutedText)),
          ],
        ),
      ),
    );
  }
}
