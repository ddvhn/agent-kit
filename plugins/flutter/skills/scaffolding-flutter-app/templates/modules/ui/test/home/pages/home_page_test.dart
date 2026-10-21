import 'dart:async';

import 'package:domain/domain_model.dart';
import 'package:domain/domain_usecase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ui/keys.dart';
import 'package:ui/src/foo/blocs/load_foo_bloc.dart';
import 'package:ui/src/home/pages/home_page.dart';

import '../../helpers/pump_screen.dart';

class _MockFetchFooUseCase extends Mock implements FetchFooUseCase {}

/// The screen with its real bloc over a fake use case (blocs rule → Tests):
/// every state, the retry control, a double tap, and accessibility.
void main() {
  late _MockFetchFooUseCase fetchFoo;

  setUp(() {
    fetchFoo = _MockFetchFooUseCase();
    GetIt.instance.registerFactory(() => LoadFooBloc(fetchFoo));
  });

  tearDown(GetIt.instance.reset);

  testWidgets('shows a skeleton, then the foo', (tester) async {
    final pending = Completer<Foo>();
    when(fetchFoo.call).thenAnswer((_) => pending.future);

    await pumpScreen(tester, const HomePage());
    expect(find.byKey(keys.home.skeleton), findsOneWidget);

    pending.complete(const Foo(id: 'foo-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(keys.home.foo('foo-1')), findsOneWidget);
    expect(find.byKey(keys.home.skeleton), findsNothing);
  });

  testWidgets('a double tap on retry loads once', (tester) async {
    // The second call stays pending while both taps land, so the second tap
    // hits a bloc that is still loading and must be ignored.
    final pending = Completer<Foo>();
    var calls = 0;
    when(fetchFoo.call).thenAnswer((_) {
      calls++;
      if (calls == 1) {
        return Future.error(const NetworkUnavailableException());
      }
      return pending.future;
    });

    await pumpScreen(tester, const HomePage());
    await tester.pumpAndSettle();
    final retry = find.byKey(keys.widgets.errorViewRetry);
    await tester.tap(retry);
    await tester.tap(retry, warnIfMissed: false);
    pending.complete(const Foo(id: 'foo-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(keys.home.foo('foo-1')), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('a failed refresh keeps the foo on screen', (tester) async {
    when(fetchFoo.call).thenAnswer((_) async => const Foo(id: 'foo-1'));
    await pumpScreen(tester, const HomePage());
    await tester.pumpAndSettle();

    when(
      fetchFoo.call,
    ).thenAnswer((_) => Future.error(const NetworkUnavailableException()));
    await tester.fling(
      find.byKey(keys.home.foo('foo-1')),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(keys.home.foo('foo-1')), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('the error state meets the tap-target guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    when(
      fetchFoo.call,
    ).thenAnswer((_) => Future.error(const NetworkUnavailableException()));

    await pumpScreen(tester, const HomePage());
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('no overflow at 2x text on a 360-wide screen', (tester) async {
    when(
      fetchFoo.call,
    ).thenAnswer((_) => Future.error(const NetworkUnavailableException()));

    await pumpScreen(
      tester,
      const HomePage(),
      textScale: 2,
      size: const Size(360, 640),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
