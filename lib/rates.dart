import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'app_theme.dart';
import 'profiles.dart';
import 'l10n.dart';
import 'errors.dart';

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
        errorMessage = tr('Could not load rates: {error}', {'error': friendlyError(e, short: true)});
        loading = false;
      });
    }
  }

  // One currency, one source: flag, "USD → DZD", buy and sell.
  Widget _currencyCard(String pair, Map<String, dynamic>? row,
      {String? note}) {
    final scheme = Theme.of(context).colorScheme;
    final code = pair.split('/').first;
    final updated = DateTime.tryParse(row?['updated_at']?.toString() ?? '');

    Widget box(String label, double? value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(row == null ? '—' : '${_fmtRate(value)} DA',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(currencyFlag(code), style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pair.replaceAll('/', ' → '),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(tr('Updated {ago}', {'ago': updatedAgo(updated)}),
                          style: const TextStyle(
                              fontSize: 12, color: kMutedText)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                box(tr('Buy'), asDouble(row?['buy_rate'])),
                const SizedBox(width: 10),
                box(tr('Sell'), asDouble(row?['sell_rate'])),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(note, style: const TextStyle(color: AppColors.warning)),
            ],
          ],
        ),
      ),
    );
  }

  // How far the parallel rate is from the bank rate ("12% higher").
  String? _gapNote(Map<String, Map<String, dynamic>> bySource) {
    final bank = bySource['bank'];
    final market = _withOffset(bySource['black_market'], offset);
    if (bank == null || market == null) return null;
    final bankMid = _rateMid(bank);
    final marketMid = _rateMid(market);
    if (bankMid == null || marketMid == null || bankMid <= 0) return null;
    final gap = (marketMid - bankMid) / bankMid * 100;
    return tr(
        gap >= 0
            ? 'Indicative rate is {pct}% higher than the bank'
            : 'Indicative rate is {pct}% lower than the bank',
        {'pct': gap.abs().toStringAsFixed(0)});
  }

  // Under a parallel rate: "Estimated..." (no staff rate today) + the gap.
  String? _parallelNote(Map<String, Map<String, dynamic>> bySource) {
    final parts = <String>[
      if (bySource['black_market']?['location'] == 'estimate')
        tr('Estimated from the official rate.'),
    ];
    final gap = _gapNote(bySource);
    if (gap != null) parts.add(gap);
    return parts.isEmpty ? null : parts.join(' ');
  }

  Widget _footer() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          tr('Buy = what you get when you sell foreign currency. Sell = what you pay to buy it. These rates are indicative and updated by hand, so always agree the exact rate with the other person before exchanging anything.'),
          style: const TextStyle(fontSize: 12, color: kMutedText),
        ),
      );

  // A tab body that can be pulled down to refresh.
  Widget _tab(List<Widget> children) => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: children,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pairs = rates.keys.toList()..sort();
    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (errorMessage != null) {
      body = _tab([
        const SizedBox(height: 80),
        Center(
          child: Text(errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.cancelled)),
        ),
      ]);
    } else if (pairs.isEmpty) {
      body = _tab([
        const SizedBox(height: 80),
        Center(child: Text(tr('No rates available yet.'))),
      ]);
    } else {
      body = TabBarView(
        children: [
          // 1. Parallel market (Annaba), with the offset.
          _tab([
            Text(tr('Indicative rate (Annaba)'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final pair in pairs)
              _currencyCard(
                  pair, _withOffset(rates[pair]!['black_market'], offset),
                  note: _parallelNote(rates[pair]!)),
            _footer(),
          ]),
          // 2. Official bank rate.
          _tab([
            Text(tr('Bank'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final pair in pairs)
              _currencyCard(pair, rates[pair]!['bank']),
            _footer(),
          ]),
          // 3. Calculator (uses the parallel rates).
          _tab([
            _RateCalculator(rates: {
              for (final cur in ['USD', 'EUR'])
                cur: _withOffset(rates['$cur/DZD']?['black_market'], offset),
            }),
          ]),
        ],
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Exchange rates')),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.trending_up), text: tr('Parallel')),
              Tab(
                  icon: const Icon(Icons.account_balance_outlined),
                  text: tr('Official')),
              Tab(
                  icon: const Icon(Icons.calculate_outlined),
                  text: tr('Calculator')),
            ],
          ),
        ),
        body: body,
      ),
    );
  }
}

// Flag shown for each currency.
String currencyFlag(String code) => const {
      'USD': '🇺🇸',
      'EUR': '🇪🇺',
      'DZD': '🇩🇿',
      'GBP': '🇬🇧',
      'ZAR': '🇿🇦',
      'CAD': '🇨🇦',
      'CNY': '🇨🇳',
      'TRY': '🇹🇷',
      'AED': '🇦🇪',
      'SAR': '🇸🇦',
    }[code.toUpperCase()] ??
    '💱';

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
  // Optional: use only a part of the amount (1 to 100 %). null = off.
  int? percent;

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

  // 50 -> "50", 12.5 -> "12.5", 12.345 -> "12.35"
  String _num(double v) {
    final fixed = v.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Widget _percentChip(int p) {
    final selected = percent == p;
    return ChoiceChip(
      label: Text('$p%'),
      selected: selected,
      onSelected: (_) => setState(() => percent = p),
    );
  }

  Widget _resultBox(BuildContext context, double amount, double rate) {
    final scheme = Theme.of(context).colorScheme;
    final p = percent;
    final part = p == null ? amount : amount * p / 100;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 14);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.sky.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p != null)
            Text(
              tr('{percent} of {amount} = {part}', {
                'percent': '$p%',
                'amount': '${_num(amount)} $currency',
                'part': '${_num(part)} $currency',
              }),
              style: muted,
            ),
          Text(
            '${_num(part)} $currency × ${_num(rate)} DA/$currency',
            style: muted,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '= ${_thousands(part * rate)} DA',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.sky),
            ),
          ),
          Text(
            iSendForeign
                ? tr('You receive this in dinars.')
                : tr('You pay this in dinars.'),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.rates[currency];
    final rate =
        asDouble(row?[iSendForeign ? 'buy_rate' : 'sell_rate']);
    final amount =
        double.tryParse(amountController.text.trim().replaceAll(',', '.'));

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
              segments: [
                ButtonSegment(
                    value: 'USD', label: Text('${currencyFlag('USD')} USD')),
                ButtonSegment(
                    value: 'EUR', label: Text('${currencyFlag('EUR')} EUR')),
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
            const SizedBox(height: 10),
            // Optional percentage: off by default.
            FilterChip(
              avatar: const Icon(Icons.percent, size: 18),
              label: Text(percent == null
                  ? tr('Percentage')
                  : tr('Percentage: {percent}', {'percent': '$percent%'})),
              selected: percent != null,
              onSelected: (on) => setState(() => percent = on ? 50 : null),
            ),
            if (percent != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 100,
                      divisions: 99,
                      value: percent!.toDouble(),
                      label: '$percent%',
                      onChanged: (v) => setState(() => percent = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text('$percent%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [for (final p in [10, 25, 50, 75, 90]) _percentChip(p)],
              ),
            ],
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
            if (rate == null) ...[
              const SizedBox(height: 8),
              Text(tr('No rate available for {currency}.',
                  {'currency': currency})),
            ] else if (amount != null && amount > 0) ...[
              const SizedBox(height: 8),
              _resultBox(context, amount, rate),
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


// ---------------- Parallel rates (Staff hub, Attaché / admin) ----------------
// Today's square rate in Annaba. It is shown instead of the estimate for
// parallel_manual_hours (24 h by default). Saved by set_parallel_rate (SQL).

class ParallelRatesEditScreen extends StatefulWidget {
  const ParallelRatesEditScreen({super.key});

  @override
  State<ParallelRatesEditScreen> createState() =>
      _ParallelRatesEditScreenState();
}

class _ParallelRatesEditScreenState extends State<ParallelRatesEditScreen> {
  static const pairs = ['USD/DZD', 'EUR/DZD'];
  final buy = {for (final p in pairs) p: TextEditingController()};
  final sell = {for (final p in pairs) p: TextEditingController()};
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [...buy.values, ...sell.values]) {
      c.dispose();
    }
    super.dispose();
  }

  // Prefill with the newest parallel rate of each pair.
  Future<void> load() async {
    try {
      final data = await supabase
          .from('exchange_rates')
          .select()
          .eq('source', 'black_market')
          .order('updated_at', ascending: false)
          .limit(20);
      for (final p in pairs) {
        final row = List<Map<String, dynamic>>.from(data)
            .where((r) => r['pair'] == p)
            .firstOrNull;
        if (row != null) {
          buy[p]!.text = _fmtRate(asDouble(row['buy_rate']));
          sell[p]!.text = _fmtRate(asDouble(row['sell_rate']));
        }
      }
    } catch (e) {
      debugPrint('Could not load parallel rates: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  double? _read(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  Future<void> save() async {
    setState(() => saving = true);
    try {
      for (final p in pairs) {
        final b = _read(buy[p]!);
        final s = _read(sell[p]!);
        if (b == null && s == null) continue; // left empty: not changed
        if (b == null || s == null) {
          throw tr('Fill in both buy and sell for {pair}.', {'pair': p});
        }
        await supabase.rpc('set_parallel_rate',
            params: {'p_pair': p, 'p_buy': b, 'p_sell': s});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Parallel rates saved.'))));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is String ? e : friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final input = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      LengthLimitingTextInputFormatter(8),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Parallel rates'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(tr("Type today's square rate in Annaba (DA). It replaces the estimate for 24 hours.")),
                const SizedBox(height: 12),
                for (final p in pairs)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${currencyFlag(p.split('/').first)}  ${p.replaceAll('/', ' → ')}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: buy[p],
                                  enabled: !saving,
                                  keyboardType: const TextInputType
                                      .numberWithOptions(decimal: true),
                                  inputFormatters: input,
                                  decoration:
                                      InputDecoration(labelText: tr('Buy')),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: sell[p],
                                  enabled: !saving,
                                  keyboardType: const TextInputType
                                      .numberWithOptions(decimal: true),
                                  inputFormatters: input,
                                  decoration:
                                      InputDecoration(labelText: tr('Sell')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: const Icon(Icons.check),
                  label: Text(saving ? tr('Saving...') : tr('Save')),
                ),
              ],
            ),
    );
  }
}
