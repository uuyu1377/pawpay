import 'package:flutter/material.dart';

import '../services/game_api_service.dart';
import '../theme/app_palette.dart';

/// ★ 新增：發票對獎頁
/// 號碼來源是財政部公開的中獎號碼 RSS（由 8000 後端抓取、比對）。
/// 只會對「掃描過、有發票號碼」的發票。
class InvoiceLotteryPage extends StatefulWidget {
  const InvoiceLotteryPage({super.key});

  @override
  State<InvoiceLotteryPage> createState() => _InvoiceLotteryPageState();
}

class _InvoiceLotteryPageState extends State<InvoiceLotteryPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = GameApiService.instance;
      final uid = await api.resolveCurrentUserId();
      final data = await api.checkInvoiceLottery(userId: uid);
      // 看過這一頁就算看過通知了，之後不再跳中獎提醒
      api.markInvoiceLotterySeen(userId: uid).catchError((_) {});
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '無法連線到伺服器，請確認網路後再試一次';
      });
    }
  }

  List<Map<String, dynamic>> get _wins =>
      ((_data['wins'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  int _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

  String _money(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${d.year}/${d.month}/${d.day}';
  }

  String _fmtInvoice(String inv) =>
      inv.length == 10 ? '${inv.substring(0, 2)}-${inv.substring(2)}' : inv;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        foregroundColor: p.accentInk,
        title: Text('發票對獎', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError(p)
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildSummary(p),
            const SizedBox(height: 16),
            if (_wins.isNotEmpty) ...[
              Text('中獎發票', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
              const SizedBox(height: 8),
              ..._wins.map((w) => _buildWinCard(p, w)),
              const SizedBox(height: 16),
            ],
            if (_data['latest_period'] is Map) _buildNumbers(p, Map<String, dynamic>.from(_data['latest_period'])),
            const SizedBox(height: 16),
            Text(
              '對獎結果僅供參考，請以財政部公告為準。\n'
              '只會對「掃描過」的發票；手動記帳沒有發票號碼，無法對獎。\n'
              '雲端發票專屬獎不在公開號碼裡，中獎時財政部會另外通知你。',
              style: TextStyle(fontSize: 12, color: p.ink2, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(AppPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: p.ink2),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.ink)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('重新載入')),
        ]),
      ),
    );
  }

  Widget _buildSummary(AppPalette p) {
    final active = _wins.where((w) => w['expired'] != true).toList();
    final total = active.fold<int>(0, (sum, w) => sum + _asInt(w['prize_amount']));
    final checked = _asInt(_data['checked_count']);
    final waiting = _asInt(_data['waiting_count']);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: total > 0
              ? const [Color(0xFFFFE08A), Color(0xFFFFB86B)]
              : [p.card, p.accentSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: p.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(total > 0 ? '🎉 恭喜中獎！' : '🧾 這幾期還沒中獎',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.ink)),
        const SizedBox(height: 6),
        Text(
          total > 0 ? '可領 \$${_money(total)}' : '繼續掃發票記帳，下次就是你！',
          style: TextStyle(fontSize: total > 0 ? 30 : 16, fontWeight: FontWeight.w900, color: p.ink),
        ),
        const SizedBox(height: 10),
        Text(
          '已對獎 $checked 張${waiting > 0 ? '・等待開獎 $waiting 張' : ''}',
          style: TextStyle(fontSize: 13, color: p.ink2),
        ),
      ]),
    );
  }

  Widget _buildWinCard(AppPalette p, Map<String, dynamic> w) {
    final expired = w['expired'] == true;
    final amount = _asInt(w['prize_amount']);
    final merchant = (w['merchant_name'] ?? '').toString();
    final date = _fmtDate(w['date']?.toString());
    final spent = w['spent'];
    return Opacity(
      opacity: expired ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: expired ? p.line : const Color(0xFFFFB86B), width: 1.5),
        ),
        child: Row(children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: expired ? p.line : const Color(0xFFFFF1D6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Text(w['prize_name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('\$${_money(amount)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE65100))),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_fmtInvoice(w['invoice_number']?.toString() ?? ''),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink, letterSpacing: 1)),
              const SizedBox(height: 3),
              Text(
                [
                  if (date.isNotEmpty) date,
                  if (merchant.isNotEmpty) merchant,
                  if (spent != null) '消費 \$${_money((spent as num).round())}',
                ].join('・'),
                style: TextStyle(fontSize: 12, color: p.ink2),
              ),
              const SizedBox(height: 3),
              Text(
                expired
                    ? '已超過領獎期限（${_fmtDate(w['claim_end']?.toString())}）'
                    : '領獎期間 ${_fmtDate(w['claim_start']?.toString())} ～ ${_fmtDate(w['claim_end']?.toString())}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: expired ? p.ink2 : const Color(0xFFE65100),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildNumbers(AppPalette p, Map<String, dynamic> period) {
    final first = ((period['first_prizes'] as List?) ?? const []).map((e) => '$e').toList();
    final extra = ((period['extra_sixth'] as List?) ?? const []).map((e) => '$e').toList();
    Widget row(String label, String value, String note) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 64, child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: p.ink))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink, letterSpacing: 1)),
            Text(note, style: TextStyle(fontSize: 11, color: p.ink2)),
          ]),
        ),
      ]),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${period['title']} 中獎號碼',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink)),
        Text('領獎期間 ${_fmtDate(period['claim_start']?.toString())} ～ ${_fmtDate(period['claim_end']?.toString())}',
            style: TextStyle(fontSize: 12, color: p.ink2)),
        const Divider(height: 20),
        row('特別獎', '${period['special_prize'] ?? '-'}', '8 碼全中 1,000 萬'),
        row('特獎', '${period['grand_prize'] ?? '-'}', '8 碼全中 200 萬'),
        row('頭獎', first.join('\n'), '8 碼全中 20 萬；末 7～3 碼相同為二～六獎（4 萬～200 元）'),
        if (extra.isNotEmpty) row('增開六獎', extra.join('、'), '末 3 碼相同 200 元'),
      ]),
    );
  }
}
