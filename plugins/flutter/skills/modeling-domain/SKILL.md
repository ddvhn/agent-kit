---
name: modeling-domain
description: Model a feature in a Flutter app's pure-Dart domain package the DDD way — entities and value objects (immutable final classes, equality, validation at construction, behavior on the model), ubiquitous language, sealed results and sealed feature exceptions, enums with an unknown fallback mapped in data, drafts with domain validation, calculators and domain services, feature folders as bounded contexts, repository contracts, and where use cases go. Use when adding a feature or concept, adding a field or rule to a domain model, deciding between a result and an exception, or moving logic out of blocs, widgets, or repositories into domain.
---

# Modeling the domain

Policy: core `architecture-principles` (DDD, Clean Architecture) and `same-level-dependencies`; the stack `architecture` rule (layers, use cases) and `dart` rule (naming, `final class`, enums). Package layout and the use-case and exception bases: `scaffolding-flutter-app`. Tests come first: `testing-use-cases`.

## Ubiquitous language

- Name the concept the way the spec and the backend do, and keep that name in every layer: `Foo` / `FooDto` / `FooApiModel` / `FooDbModel` / `FooUiModel`, `fetchFoo`, `FetchFooUseCase`, copy keys `foo…`. A new term enters the feature's spec in `docs/` first.
- Different words for the same thing are a bug; the same word for different things is two concepts that need two names.
- Domain names say what the app does, not how: `PublishFooUseCase`, not `PostFooToServerUseCase`; `FooStatus.published`, not `isSynced`.

## Feature = bounded context

```
modules/domain/lib/src/foo/
  model/        foo.dart  foo_draft.dart  foo_exception.dart  redeem_foo_code_result.dart
  repository/   foo_repository.dart
  usecase/      publish_foo_use_case.dart
  calculator/   foo_schedule_calculator.dart
```

- A feature owns its models, contracts, exceptions, and use cases. Another feature uses them only through the barrels (`domain_model.dart`, `domain_repository.dart`, `domain_usecase.dart`).
- Across contexts, hold the other entity's id (`barId`), not the entity, unless the backend returns them together as one aggregate.
- An aggregate (a `Foo` with its `FooItem`s) changes as a whole through its own repository; nobody edits a child through another repository.
- `common/` holds only what is truly cross-feature: `AppException`, `CachePolicy`, `Paged<T>`, the use-case mixins.

## Entities and value objects

```dart
import 'package:equatable/equatable.dart';

/// `unknown`: a value this client does not know yet (mapped in data), so an
/// older app keeps working when the backend adds one.
enum FooStatus { draft, published, archived, unknown }

final class Foo extends Equatable {
  Foo({
    required this.id,
    required this.title,
    required this.status,
    required List<FooItem> items,
  }) : items = List.unmodifiable(items) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'must not be empty');
  }

  final String id;
  final String title;
  final FooStatus status;
  final List<FooItem> items;

  bool get isEditable => status == .draft;

  bool get canPublish => isEditable && items.isNotEmpty;

  Duration get totalDuration =>
      items.fold(Duration.zero, (total, item) => total + item.duration);

  @override
  List<Object?> get props => [id, title, status, items];
}

final class FooItem extends Equatable {
  const FooItem({required this.id, required this.duration});

  final String id;
  final Duration duration;

  @override
  List<Object?> get props => [id, duration];
}
```

- `final class`, `final` fields, unmodifiable collections. Domain models are snapshots: value equality on every field so bloc states compare correctly; compare identity explicitly (`a.id == b.id`) where that is the question.
- **Invariants at construction.** A broken invariant from trusted input is a bug: `ArgumentError` / `StateError` (the data layer's guard turns it into `UnknownException`). Input from the user is not an invariant: parse it into a value object or validate a draft.
- **Behavior on the model**: derived values and state questions (`canPublish`, `totalDuration`, `isExpired(now:)`) live on the entity, not in blocs or widgets. Time is a parameter (`now`), never `DateTime.now()` inside the model.
- No JSON, no `fromDto` / `toDto` (data maps), no Flutter types (`Color`, `IconData`, `Locale` from Flutter, `BuildContext`), no localized text.
- `copyWith` only when something edits the model (a draft); not by default.

Value object, parsed from user input:

```dart
final class EmailAddress extends Equatable {
  const EmailAddress._(this.value);

  /// Null when [raw] is not an email address; the form shows the violation.
  static EmailAddress? tryParse(String raw) {
    final value = raw.trim().toLowerCase();
    return _pattern.hasMatch(value) ? EmailAddress._(value) : null;
  }

  static final _pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final String value;

  @override
  List<Object?> get props => [value];
}
```

## Enums with an unknown fallback

- Every enum that comes from the backend has `unknown`. The Api model maps unrecognized wire values to it (`@JsonKey(unknownEnumValue: …)` on the Api enum, then DTO → domain); domain never parses strings.
- The UI shows `unknown` as a neutral state and hides actions that depend on the value. A `switch` over the enum stays exhaustive — no `default`.

## Drafts and validation

What the user edits before the backend creates the entity is a draft with its own rules; violations are domain values, not strings:

```dart
enum FooDraftViolation { titleMissing, titleTooLong, noItems }

final class FooDraft extends Equatable {
  const FooDraft({required this.title, required this.itemIds});

  static const maxTitleLength = 80;

  final String title;
  final List<String> itemIds;

  Set<FooDraftViolation> validate() => {
    if (title.trim().isEmpty) .titleMissing,
    if (title.length > maxTitleLength) .titleTooLong,
    if (itemIds.isEmpty) .noItems,
  };

  FooDraft copyWith({String? title, List<String>? itemIds}) => FooDraft(
    title: title ?? this.title,
    itemIds: itemIds ?? this.itemIds,
  );

  @override
  List<Object?> get props => [title, itemIds];
}
```

The use case that submits it validates first and throws `FooDraftInvalidException(violations)`; the bloc keeps it in its failure state and the form marks fields (`writing-action-blocs`). The backend stays the authority: the client check saves a round trip, it does not replace the server's.

## Results vs exceptions

| Outcome | Model it as |
| --- | --- |
| An expected alternative the UI shows as normal (code already redeemed, nothing to sync, partial match) | a **sealed result** returned by the use case |
| A failure that aborts the action and that a catcher branches on (offline, not found, rule violated) | a **sealed exception** thrown (`handling-errors`) |
| A bug nobody branches on | `ArgumentError` / `StateError` / `UnknownException` |

```dart
sealed class RedeemFooCodeResult {
  const RedeemFooCodeResult();
}

final class RedeemFooCodeResultSuccess extends RedeemFooCodeResult {
  const RedeemFooCodeResultSuccess({required this.credits});

  final int credits;
}

final class RedeemFooCodeResultAlreadyRedeemed extends RedeemFooCodeResult {
  const RedeemFooCodeResultAlreadyRedeemed();
}

final class RedeemFooCodeResultExpired extends RedeemFooCodeResult {
  const RedeemFooCodeResultExpired({required this.expiredAt});

  final DateTime expiredAt;
}
```

Feature exceptions extend the app's `FeatureException`, sealed per feature, all in one file:

```dart
sealed class FooException extends FeatureException {
  const FooException();
}

final class FooDraftInvalidException extends FooException {
  const FooDraftInvalidException(this.violations);

  final Set<FooDraftViolation> violations;
}

final class FooNotPublishableException extends FooException {
  const FooNotPublishableException();
}
```

Add a subtype only when some catcher handles it differently from the existing ones (core `minimal-change`).

## Calculators and domain services

A rule several use cases need goes one level down into a pure calculator, not into one use case that others call (core `same-level-dependencies`):

```dart
abstract final class FooScheduleCalculator {
  static DateTime finishTime(Foo foo, {required DateTime startedAt}) =>
      startedAt.add(foo.totalDuration);

  static bool isOverdue(
    Foo foo, {
    required DateTime startedAt,
    required DateTime now,
  }) => now.isAfter(finishTime(foo, startedAt: startedAt));
}
```

- Static and pure when it has no dependencies; a class with constructor injection, registered in `injectDomainLayer`, only when it needs a collaborator.
- A rule that belongs to one entity is a method on that entity, not a calculator.

## Repository contracts

```dart
abstract interface class FooRepository {
  Future<Foo> fetchFoo({
    required String fooId,
    required CachePolicy cachePolicy,
  });

  Future<Foo> createFoo({required FooDraft draft});

  Future<Foo> publishFoo({required String fooId});

  /// Fires after the backend confirmed a change to any foo.
  Stream<void> get fooUpdates;
}
```

- In `foo/repository/`, domain types only, named parameters, `CachePolicy` on reads when the app caches. Naming and implementation: `creating-flutter-repositories`.
- One contract per aggregate or SDK capability (`PushNotificationsRepository`), never a service interface in domain.

## Use cases

```dart
typedef PublishFooUseCaseParams = ({String fooId});

abstract class PublishFooUseCase
    with CallableUseCase<PublishFooUseCaseParams, Foo> {}

final class PublishFooUseCaseImpl extends PublishFooUseCase {
  PublishFooUseCaseImpl(this._fooRepository);

  final FooRepository _fooRepository;

  @override
  Future<Foo> call(PublishFooUseCaseParams params) async {
    final foo = await _fooRepository.fetchFoo(
      fooId: params.fooId,
      cachePolicy: .network,
    );
    if (!foo.canPublish) {
      log.w('Foo ${params.fooId} is not publishable: ${foo.status.name}');
      throw const FooNotPublishableException();
    }
    return _fooRepository.publishFoo(fooId: params.fooId);
  }
}
```

- File `publish_foo_use_case.dart` in the feature that owns the user action; params are a record typedef; no-param, sync, and observing variants use the matching mixin (observing: `observing-data`).
- A use case exists when there is a rule or orchestration (several repositories, ordering, a domain check). A plain CRUD call with no rule may go from the bloc to the repository contract directly (core `architecture-principles` → Pragmatism; the stack `architecture` rule).
- Domain may log through the pure-Dart `log` (a rule rejection, a deliberately swallowed failure); it still throws typed exceptions for callers (`handling-errors`).
- Use cases never call each other; shared steps go into a calculator or one level up into the caller.
- Registered with `registerFactory` in `injectDomainLayer`; exported from `domain_usecase.dart` with `hide PublishFooUseCaseImpl`.

## Procedure

1. Read the spec (or write the acceptance criteria) and list the nouns, rules, and outcomes in its words.
2. Place each: entity / value object / draft / enum / result / exception / calculator / repository method / use case. Logic found in a bloc, widget, or repository that is a rule moves here.
3. Write the failing tests for rules and use cases (`testing-use-cases`), then the models, then the code.
4. Export through the barrels; register use cases.
5. Map in data (`creating-flutter-repositories`), present in ui (`FooUiModel.fromFoo`).

## Checks

- [ ] Same name as spec and backend in every layer
- [ ] `final class`, immutable, value equality; invariants checked at construction; no JSON or Flutter
- [ ] Behavior on the model; time passed in
- [ ] Backend enums have `unknown`, mapped in data
- [ ] User input validated by value objects or a draft's `validate()`; violations are enums
- [ ] Sealed result for expected alternatives, sealed `FooException` for branched-on failures
- [ ] Shared rules in a calculator; no use case → use case
- [ ] Contracts are `abstract interface class` with domain types only
