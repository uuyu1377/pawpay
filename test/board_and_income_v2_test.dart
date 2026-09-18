import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_interface/services/recurring_income_review_service.dart';
import 'package:user_interface/widgets/board_3d_geometry.dart';
import 'package:user_interface/widgets/board_scene_model.dart';
import 'package:user_interface/widgets/island_board_3d.dart';
import 'package:user_interface/widgets/income_review_problem.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final Future<ResponseBody> Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => reply(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object value, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

Map<String, Object> _review(String id) => {
  'rule_id': int.parse(id),
  'scheduled_date': '2026-09-16',
  'transaction_id': id,
  'status': 'pending',
  'version': 0,
  'category_name': '薪水',
  'amount': '30000',
  'currency': 'TWD',
  'note': '',
};

void main() {
  test('all stops retain their order and have room for separate 3D tiles', () {
    for (final count in [22, 28]) {
      final route = boardRoute3D(count, magic: count == 22);
      expect(route.length, count);
      for (var i = 0; i < count; i++) {
        final next = (i + 1) % count;
        final minimum = .10 * (boardTileScale3D(i, magic: count == 22) +
            boardTileScale3D(next, magic: count == 22));
        expect((route[i] - route[next]).length, greaterThan(minimum));
      }
    }
  });

  test('camera projects height and changes visible perspective on orbit', () {
    final first = BoardCamera3D(size: const Size(390, 450));
    final rotated = BoardCamera3D(size: const Size(390, 450), yaw: 1.2);
    const ground = BoardPoint3(.4, 0, .3);
    const roof = BoardPoint3(.4, .4, .3);
    expect(
      first.project(roof).screen.dy,
      lessThan(first.project(ground).screen.dy),
    );
    expect(
      (first.project(roof).screen - rotated.project(roof).screen).distance,
      greaterThan(10),
    );
  });

  test(
    'visible labels never overlap at small widths or different camera angles',
    () {
      for (final width in [320.0, 390.0, 600.0]) {
        for (final yaw in [-.2, 0.0, math.pi / 2, math.pi]) {
          final size = Size(width, 410);
          final camera = BoardCamera3D(size: size, yaw: yaw);
          final occupied = <Rect>[];
          for (final point in boardRoute3D(28)) {
            final rect = placeBoardLabel3D(
              anchor: camera.project(point).screen,
              labelSize: const Size(44, 21),
              viewport: size,
              occupied: occupied,
              center: Offset(width / 2, 205),
            );
            if (rect == null) continue;
            expect(occupied.any((r) => r.overlaps(rect)), isFalse);
            occupied.add(rect);
          }
          expect(occupied.length, greaterThan(5));
        }
      }
    },
  );

  testWidgets(
    '3D board rotates, resets, and lets users choose every location',
    (tester) async {
      final model = await tester.runAsync(() => BoardSceneModel.load(false));
      final sites = List.generate(
        28,
        (i) => BoardSite3D(
          name: '地點 $i',
          kind: 'land',
          cost: 1000,
          rent: 200,
          level: 1,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: IslandBoard3D(
                model: model,
                sites: sites,
                pawns: const [
                  BoardPawn3D(
                    id: 0,
                    name: '您',
                    step: 0,
                    color: Colors.blue,
                    emoji: '●',
                  ),
                  BoardPawn3D(
                    id: 1,
                    name: '小明',
                    step: 0,
                    color: Colors.red,
                    emoji: '●',
                  ),
                  BoardPawn3D(
                    id: 2,
                    name: '小美',
                    step: 0,
                    color: Colors.green,
                    emoji: '●',
                  ),
                  BoardPawn3D(
                    id: 3,
                    name: '系統',
                    step: 0,
                    color: Colors.orange,
                    emoji: '●',
                  ),
                ],
                activePlayerId: 0,
                magic: false,
                accent: Colors.pink,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final paint = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is IslandScenePainter3D,
      );
      await tester.drag(paint, const Offset(90, 12));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('重設視角'));
      await tester.pump();
      await tester.tap(find.byTooltip('全部地點'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsWidgets);
      await tester.tap(find.text('地點 2'));
      await tester.pumpAndSettle();
      expect(find.text('地點 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'HTML 404 identifies missing deployment; JSON 404 identifies missing record',
    () async {
      for (final isJson in [false, true]) {
        final dio = Dio()
          ..httpClientAdapter = _Adapter(
            (_) async => isJson
                ? _json({'status': 'error', 'message': '找不到這筆固定收入'}, 404)
                : ResponseBody.fromString('<html>Not found</html>', 404),
          );
        final service = RecurringIncomeReviewService.forTesting(
          dio: dio,
          identity: () async => const IncomeReviewIdentity('7', 'test-token'),
        );
        await expectLater(
          service.fetchIndex(['1']),
          throwsA(
            isA<RecurringIncomeReviewException>().having(
              (e) => e.kind,
              'failure',
              isJson
                  ? IncomeReviewFailure.conflict
                  : IncomeReviewFailure.unavailable,
            ),
          ),
        );
      }
    },
  );

  test(
    'more than 500 IDs are batched and duplicates/local IDs cannot break all reviews',
    () async {
      final batches = <int>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) async {
          final ids = (options.data as Map)['transaction_ids'] as List;
          batches.add(ids.length);
          expect(options.headers['Authorization'], 'Bearer test-token');
          return _json({
            'status': 'success',
            'reviews': ids.map((id) => _review(id as String)).toList(),
          });
        });
      final service = RecurringIncomeReviewService.forTesting(
        dio: dio,
        identity: () async => const IncomeReviewIdentity('7', 'test-token'),
      );
      final rows = await service.fetchIndex([
        ...List.generate(501, (i) => '${i + 1}'),
        '1',
        'local-draft',
        '-7',
      ]);
      expect(rows.length, 501);
      expect(batches, [200, 200, 101]);
    },
  );

  test(
    'an account change while a response is in flight discards its data',
    () async {
      var identity = const IncomeReviewIdentity('7', 'first-token');
      final dio = Dio()
        ..httpClientAdapter = _Adapter((_) async {
          identity = const IncomeReviewIdentity('8', 'second-token');
          return _json({
            'status': 'success',
            'reviews': [_review('1')],
          });
        });
      final service = RecurringIncomeReviewService.forTesting(
        dio: dio,
        identity: () async => identity,
      );
      await expectLater(
        service.fetchIndex(['1']),
        throwsA(
          isA<RecurringIncomeReviewException>().having(
            (e) => e.code,
            'code',
            'review_account_changed',
          ),
        ),
      );
    },
  );

  test('missing login is not sent as an arbitrary user ID fallback', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        calls++;
        return _json({'status': 'success', 'reviews': []});
      });
    final service = RecurringIncomeReviewService.forTesting(
      dio: dio,
      identity: () async {
        throw const RecurringIncomeReviewException(
          '請登入',
          kind: IncomeReviewFailure.login,
        );
      },
    );
    await expectLater(
      service.fetchIndex(['1']),
      throwsA(isA<RecurringIncomeReviewException>()),
    );
    expect(calls, 0);
  });

  test(
    'invalid amount and overflowed calendar dates never become valid records',
    () {
      expect(
        () =>
            RecurringIncomeReview.fromJson({..._review('1'), 'amount': 'NaN'}),
        throwsFormatException,
      );
      expect(
        () => RecurringIncomeReview.fromJson({
          ..._review('1'),
          'scheduled_date': '2026-02-31',
        }),
        throwsFormatException,
      );
    },
  );

  testWidgets('service failure fits a narrow phone with large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: const SizedBox(
              width: 288,
              child: IncomeReviewProblem(
                problem: RecurringIncomeReviewException(
                  '固定收入確認服務尚未啟用',
                  kind: IncomeReviewFailure.unavailable,
                ),
                onRetry: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('查看原因'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}

void _noop() {}
