import 'package:domain/domain_model.dart';
import 'package:domain/domain_usecase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ui/keys.dart';
import 'package:ui/src/application/application.dart';
import 'package:ui/src/di.dart';

class _MockFetchFooUseCase extends Mock implements FetchFooUseCase {}

/// The real ui wiring over a fake use case: injectUiLayer, the router, and
/// the app root.
void main() {
  // A tear-off runs the const constructor at runtime, so coverage sees it.
  const application = Application.new;

  setUp(() {
    final fetchFoo = _MockFetchFooUseCase();
    when(fetchFoo.call).thenAnswer((_) async => const Foo(id: 'foo-1'));
    GetIt.instance.registerSingleton<FetchFooUseCase>(fetchFoo);
    injectUiLayer(GetIt.instance);
  });

  tearDown(GetIt.instance.reset);

  testWidgets('starts on the home page', (tester) async {
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    expect(find.byKey(keys.home.foo('foo-1')), findsOneWidget);
  });

  testWidgets('an unknown location shows the not-found page', (tester) async {
    await tester.pumpWidget(application());
    await tester.pumpAndSettle();

    inject<GoRouter>().go('/no-such-page');
    await tester.pumpAndSettle();

    expect(find.byKey(keys.home.page), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
