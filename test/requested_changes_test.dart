import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_interface/services/recurring_income_review_service.dart';
import 'package:user_interface/widgets/recurring_income_review_bar.dart';
import 'package:user_interface/widgets/toy_gacha_art.dart';
import 'package:user_interface/widgets/roof_category_art.dart';

RecurringIncomeReview review(String state) => RecurringIncomeReview(
  ruleId: 1, scheduledDate: '2026-09-15', transactionId: '100',
  status: state, version: 0, categoryName: '薪水', amount: 30000,
  currency: 'TWD', note: '',
);

void main() {
  testWidgets('income actions fit narrow phones with large text', (tester) async {
    final actions = <String>[];
    for (final state in ['pending', 'confirmed', 'cancelled']) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 288,
          child: RecurringIncomeReviewBar(review: review(state), busy: false,
            onAction: actions.add))),
      ))));
      expect(tester.takeException(), isNull);
      if (state == 'pending') {
        await tester.tap(find.text('確認'));
        expect(actions.last, 'confirm');
      }
      if (state == 'cancelled') {
        expect(find.text('取消本次'), findsNothing);
        await tester.tap(find.text('復原本次'));
        expect(actions.last, 'restore');
      }
    }
  });

  testWidgets('busy income cannot send duplicate actions', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RecurringIncomeReviewBar(
      review: review('pending'), busy: true, onAction: (_) => fail('busy action')))));
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('gacha layers and all roof categories paint without exceptions', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: Column(children: [
        const SizedBox(width: 260, height: 400, child: Stack(children: [
          CustomPaint(size: Size(260, 400), painter: GachaArtPainter()),
          Positioned(left: 60, top: 100, child: CustomPaint(size: Size(36, 36),
            painter: ToyCapsulePainter(color: Colors.red))),
          CustomPaint(size: Size(260, 400), painter: GachaGlassPainter()),
        ])),
        CustomPaint(size: const Size(300, 320), painter: _RoofSamples()),
      ]),
    ))));
    expect(tester.takeException(), isNull);
  });

  test('malformed review cannot silently become an unchecked income', () {
    expect(() => RecurringIncomeReview.fromJson({'status': 'unknown'}), throwsFormatException);
  });
}

class _RoofSamples extends CustomPainter {
  @override
  void paint(Canvas c, Size size) {
    const names = ['飲食', '交通', '生活用品', '娛樂', '服飾美容', '醫療健康',
      '學費與教材', '禮物與送禮', '投資理財', '通訊網路', '家庭旅遊', '住房',
      '家具家電', '保險費用', '自訂分類'];
    for (var i = 0; i < names.length; i++) {
      RoofCategoryArt.paint(c, names[i], Offset(40 + (i % 4) * 73.0, 52 + (i ~/ 4) * 70.0));
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
