---
name: testing-use-cases
description: Test-drive domain logic in a Flutter app the kit way — write the failing test first from the acceptance criteria, unit-test use cases, entities, drafts, and calculators in the pure-Dart domain package with dart test and mocktail repository doubles (fallback values for enums and record params), stream assertions with emitsInOrder, error mapping and pass-through, no Flutter in domain tests, blocs covered through their screen's widget tests (bloc_test only by exception), and how this layer fits with repository round-trips and Patrol flows. Use when adding or changing a use case, a domain rule, an entity method, or a calculator, when fixing a domain bug (reproduce it in a test first), or when setting up domain or bloc unit tests.
---

# Testing use cases

Policy: core `architecture-principles` (TDD, test at the layer that owns the behavior) and `minimal-change`; the stack `testing` rule. Suites, commands, and where blocs are tested: `CLAUDE.md` and the repository's `.claude/rules/`. Other layers: `testing-flutter-apps` (choosing a suite), `persisting-with-isar` (database round-trips), `writing-patrol-tests` (flows).

## Where each behavior is tested

| Behavior | Test | Doubles |
| --- | --- | --- |
| Entity, value object, draft rules, calculators | domain unit (`dart test`) | none — pure functions |
| Use case orchestration and rules, error pass-through and mapping | domain unit | mocktail repository contracts |
| Observing use cases (streams, combining) | domain unit | `StreamController`s behind mocked contracts |
| Bloc state machine | ui widget tests of the screen, real bloc (`writing-widget-tests`); `bloc_test` only by exception | mocked use cases / repository contracts |
| Mapping, storage, cache policy, error classification | data unit | real per-test database, mocked API client |
| User flows through real UI, blocs, repositories | integration (Patrol) | only I/O replaced |

Each behavior is asserted once, at its owner. A rule proven in a domain test is not re-proven through the UI; the flow test proves the wiring.

## TDD loop

1. From the acceptance criteria, list the cases: the happy path, each rule branch, each failure a caller handles. A bug: the case that reproduces it.
2. Create the contract and an `Impl` whose `call` throws `UnimplementedError`, so the test compiles and fails on behavior, not on a missing type.
3. Write one test; run it (`dart test test/foo/usecase/publish_foo_use_case_test.dart`); confirm it fails for the expected reason.
4. Write the minimum code to pass; run again. Next case.
5. Refactor with the suite green. `delivering-changes` runs this per subtask.

Never weaken an assertion, add a skip, or delete a test to get green.

## Domain package setup

- Pure Dart: `dev_dependencies: test, mocktail`; tests import `package:test/test.dart`, never `flutter_test` (it would pull Flutter into domain). Run with `dart test` in `modules/domain`.
- Domain code may log (the `log` package is pure Dart): a test file whose code under test logs calls `setUpAll(initializeLogger)` (or a shared helper in `test/`); without a directory it writes to the console only.
- Mirror `lib/src/` under `test/`. Builders named for what they return (`mockFoo` → `Foo`) in `test/mocks/`, with defaults so each test states only what it is about:

```dart
Foo mockFoo({
  String id = 'foo-1',
  FooStatus status = .draft,
  List<FooItem> items = const [
    FooItem(id: 'item-1', duration: Duration(minutes: 5)),
  ],
}) => Foo(id: id, title: 'Foo', status: status, items: items);
```

- Tests import the implementation from `src/` (it is hidden from the barrel); that is the one place outside domain allowed to.

## Use case test

```dart
import 'package:domain/domain_model.dart';
import 'package:domain/domain_repository.dart';
import 'package:domain/src/foo/usecase/publish_foo_use_case.dart';
import 'package:log/log.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../mocks/mock_foo.dart';

final class _MockFooRepository extends Mock implements FooRepository {}

void main() {
  late _MockFooRepository fooRepository;
  late PublishFooUseCase useCase;

  setUpAll(() async {
    await initializeLogger();
    registerFallbackValue(CachePolicy.network);
  });

  setUp(() {
    fooRepository = _MockFooRepository();
    useCase = PublishFooUseCaseImpl(fooRepository);
  });

  void stubFetch(Future<Foo> Function() answer) => when(
    () => fooRepository.fetchFoo(
      fooId: 'foo-1',
      cachePolicy: any(named: 'cachePolicy'),
    ),
  ).thenAnswer((_) => answer());

  test('publishes a draft with items', () async {
    stubFetch(() async => mockFoo());
    when(
      () => fooRepository.publishFoo(fooId: 'foo-1'),
    ).thenAnswer((_) async => mockFoo(status: .published));

    final foo = await useCase((fooId: 'foo-1'));

    expect(foo.status, FooStatus.published);
    verify(
      () => fooRepository.fetchFoo(fooId: 'foo-1', cachePolicy: .network),
    ).called(1);
  });

  test('rejects a draft without items and does not publish', () async {
    stubFetch(() async => mockFoo(items: const []));

    await expectLater(
      useCase((fooId: 'foo-1')),
      throwsA(isA<FooNotPublishableException>()),
    );
    verifyNever(() => fooRepository.publishFoo(fooId: any(named: 'fooId')));
  });

  test('passes repository failures through unchanged', () async {
    stubFetch(() => Future.error(const NetworkUnavailableException()));

    await expectLater(
      useCase((fooId: 'foo-1')),
      throwsA(isA<NetworkUnavailableException>()),
    );
  });
}
```

- Mock the **contract** (`implements FooRepository`), never an implementation. A stateful fake (an in-memory repository with a controller) is fine when a test drives several calls against changing state; keep it in `test/mocks/`.
- Async failures: `thenAnswer((_) => Future.error(…))`, not `thenThrow` (which throws synchronously from a method that returns a `Future`).
- `any()` / `any(named:)` for a non-primitive type needs `registerFallbackValue` once in `setUpAll`: enums (`CachePolicy.network`), DTOs and domain types, and record params when mocking a use case (`registerFallbackValue((draft: draft))`). In a record literal passed as a fallback, write enum values in full (`CachePolicy.cache`): there is no context type for dot shorthands.
- `verify` what the use case decided (which calls, with which arguments) and `verifyNever` the call a rule must prevent. Do not verify incidental reads.
- Time: a use case that needs the clock takes it in the constructor (`DateTime Function() now`); tests pass a fixed one. Same for ids (`String Function() newId`).

## Streams

```dart
final home = ObserveHomeUseCaseImpl(sessionRepository, barRepository)();
final expectation = expectLater(
  home,
  emitsInOrder([
    (session: signedIn, unreadCount: 0),
    (session: signedIn, unreadCount: 3),
    emitsDone,
  ]),
);
sessions.add(signedIn);
counts
  ..add(0)
  ..add(0)
  ..add(3);
await Future.wait([sessions.close(), counts.close()]);
await expectation;
```

Start the expectation before adding events; close the controllers so `emitsDone` (and no extra events) is checked. `current` gets its own plain test.

## Pure domain logic

Entities, drafts, value objects, and calculators are tested directly, table-style, with no doubles:

```dart
test('validate lists every violation', () {
  const draft = FooDraft(title: ' ', itemIds: []);
  expect(draft.validate(), {
    FooDraftViolation.titleMissing,
    FooDraftViolation.noItems,
  });
});

test('isOverdue after the finish time', () {
  final foo = mockFoo();
  final startedAt = DateTime.utc(2026, 1, 1, 10);
  expect(
    FooScheduleCalculator.isOverdue(
      foo,
      startedAt: startedAt,
      now: startedAt.add(const Duration(minutes: 6)),
    ),
    isTrue,
  );
});
```

Cover each rule's boundary (at the limit, one past it) — the cases most likely to break.

## Bloc tests

Blocs are tested through their screen by default (`writing-widget-tests`; `blocs` rule). A `bloc_test` only for a case no widget or flow test can reach, or where the project unit-tests blocs: in the ui package with `flutter_test`, `bloc_test`, and `mocktail`, mocking the use case (or the repository contract for plain CRUD blocs):

```dart
final class _MockCreateFooUseCase extends Mock implements CreateFooUseCase {}

blocTest<CreateFooBloc, CreateFooBlocState>(
  'keeps the domain exception in Failure',
  setUp: () => when(() => createFoo(any())).thenAnswer(
    (_) => Future.error(const FooDraftInvalidException({.noItems})),
  ),
  build: () => CreateFooBloc(createFoo),
  act: (bloc) => bloc.submit(draft: draft),
  expect: () => [
    const CreateFooBlocStateInProgress(),
    isA<CreateFooBlocStateFailure>().having(
      (state) => state.error,
      'error',
      isA<FooDraftInvalidException>(),
    ),
  ],
);
```

- Blocs log failures, so the ui and data test suites initialize the logger once in `test/flutter_test_config.dart` (`await initializeLogger()` before `testMain()`).
- State lists per transition: the load-bloc list in `writing-load-blocs`, action blocs in `writing-action-blocs`, observers in `observing-data`, pages in `paging-lists`.
- A bloc test asserts states and presentation events, never private fields or the use case's internals.

## Checks

- [ ] Test written first and seen failing for the right reason
- [ ] Domain tests use `package:test` and run with `dart test`; no Flutter imports
- [ ] Contracts mocked, not implementations; fallbacks registered for enums, models, and record params
- [ ] Happy path, each rule branch with its boundary, each handled failure, and pass-through of repository exceptions
- [ ] Streams asserted with `emitsInOrder` (and `emitsDone`); `current` tested
- [ ] Clock and id generators injected, fixed in tests
- [ ] No behavior asserted twice across layers
