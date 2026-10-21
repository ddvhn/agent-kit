---
name: writing-widget-tests
description: Write Flutter widget and golden tests for a screen the kit way — pumpScreen with the real theme, localization, platform, text scale, and size; the screen's real blocs registered in GetIt over mocktail use cases; every control in every state (enabled, disabled, loading, success, each error, offline, empty, maximum); double and concurrent taps, back during a submit, disposal before the answer; accessibility guidelines and overflow at large text; base and stress goldens with bundled fonts and --update-goldens. Use when adding or changing a screen, a screen state, a shared widget, or a bloc (blocs are tested through their screen).
---

# Writing widget tests

Policy: the `testing` rule → Rules; the `blocs` rule; Policy below. Template: `scaffolding-flutter-app` → `templates/modules/ui/test/` (`helpers/pump_screen.dart`, `home/pages/home_page_test.dart`). Use cases themselves: `testing-use-cases`.


## Policy

Every interactive control (button, row, toggle, field, gesture) is pressed in every state it can be in:

- **States:** enabled; disabled (tap does nothing); loading (tap ignored, no second request); success; each error the server or device can return (by code, timeout, 5xx, no network, permission denied); offline; empty and maximum data.
- **Double tap:** two fast taps → one bloc call, one queue item, one idempotency key, one navigation push.
- **Concurrent taps, lifecycle:** two controls tapped at once → one action wins, no exception; a tap during a transition, back during a submit, a tap after the screen started closing; the app backgrounded during a request; the screen disposed before the answer (no emit or `setState` after close). Tested once on the shared action control and again on the main-loop screens the project lists.
- **Accessibility:** a semantics label, the tap-target size, and no overflow at text scale 1.3 and 2.0 on a 360-wide screen (`dart` rule).
- Every enum from the API gets a test feeding an unknown value that renders the neutral fallback.

- One base golden per screen state (light theme, the template locale, text scale 1.0) and one stress golden per screen (dark theme, the longest locale, text scale 1.3 and 2.0, 360 wide, longest strings). Not the full theme × locale × scale matrix per state.
- `Adaptive*` widgets and the page helper get a golden or a widget test per platform (iOS, Android, web).
- A new state gets its golden in the same change; an updated golden is looked at before it is committed. Goldens render with the bundled fonts, so they match across machines.

## Setup

- Tests live in `modules/ui/test/`, mirroring `lib/src` (`test/foo/pages/foo_page_test.dart`); shared helpers in `test/helpers/`.
- `flutter_test_config.dart` initializes the logger and blocks the network (`HttpOverrides`).
- Mock the use cases (`mocktail`), register the **real** blocs over them in `GetIt`, reset in `tearDown`:

```dart
class _MockFetchFoo extends Mock implements FetchFooUseCase {}
class _MockSaveFoo extends Mock implements SaveFooUseCase {}

void main() {
  late _MockFetchFoo fetchFoo;
  late _MockSaveFoo saveFoo;

  setUpAll(() => registerFallbackValue(const Foo(id: 'fallback')));

  setUp(() {
    fetchFoo = _MockFetchFoo();
    saveFoo = _MockSaveFoo();
    GetIt.instance
      ..registerFactory(() => LoadFooBloc(fetchFoo))
      ..registerFactory(() => SaveFooBloc(saveFoo));
  });

  tearDown(GetIt.instance.reset);
}
```

- `pumpScreen(tester, const FooPage(fooId: 'foo-1'), platform:, brightness:, locale:, textScale:, size:)` pumps the page with the app's theme and copy. A page that needs a router gets a `GoRouter` with only that route.
- Find widgets by keys from `keys.dart` (`keys.foo.saveButton`), never by text, so a copy change does not break a test.
- Control time with `Completer`s for pending answers and `tester.pump(duration)` / `fake_async` for timers; never real delays.

## Every control in every state

For each interactive control, a test per state it can be in:

| State | Arrange | Expect |
| --- | --- | --- |
| Loading | a `Completer` never completed | skeleton present, static chrome present, control disabled |
| Success | the use case returns the value | content by key; skeleton gone |
| Empty | an empty list / null | the empty view |
| Maximum | the longest list and strings | no overflow, the list scrolls (`ListView.builder`) |
| Each error | `thenThrow` each domain exception the use case declares (network, timeout, server code, permission) | the matching message key and a retry where it applies |
| Failed refresh | a value, then an error on reload | the content stays; an inline notice or toast |
| Disabled | the precondition unmet | a tap does nothing: `verifyNever(() => saveFoo(any()))` |
| Action in progress | the save `Completer` pending | spinner inside the button; another tap is ignored |
| Offline | the network exception, or the connectivity fake off | the offline banner; online-only buttons disabled with the hint |

## Taps, races, lifecycle

```dart
testWidgets('a double tap on save saves once', (tester) async {
  final pending = Completer<void>();
  when(() => saveFoo(any())).thenAnswer((_) => pending.future);
  await pumpScreen(tester, const FooPage(fooId: 'foo-1'));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(keys.foo.saveButton));
  await tester.tap(find.byKey(keys.foo.saveButton), warnIfMissed: false);
  pending.complete();
  await tester.pumpAndSettle();

  verify(() => saveFoo(any())).called(1);
});
```

- **Double tap:** one use-case call, one navigation (count pushes with a `NavigatorObserver` mock), one queued item.
- **Concurrent taps:** two controls tapped before a pump (`tester.tap(a); tester.tap(b);`) or interleaved `startGesture` down / up: exactly one action, `tester.takeException()` is null.
- **Back during a submit:** start the save, `tester.pageBack()` (or `Navigator.maybePop`), complete the answer: no exception, no emit after close.
- **Disposed before the answer:** pump a different widget (`pumpWidget(const SizedBox())`) while the `Completer` is pending, then complete it.
- **Backgrounded:** `tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused)` during the request, then `resumed`.

These races run once on the shared action control and again on the main-loop screens the project lists; other screens cover states, errors, and double taps.

## Accessibility

```dart
final handle = tester.ensureSemantics();
await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
await expectLater(tester, meetsGuideline(textContrastGuideline));
handle.dispose();
```

Plus no overflow at `textScale: 1.3` and `2.0` with `size: Size(360, 640)` (`expect(tester.takeException(), isNull)`).

## Goldens

- Fonts: load the bundled fonts once in `flutter_test_config.dart` (a `FontLoader` per family over the font assets listed in `pubspec.yaml`, plus `MaterialIcons` / `CupertinoIcons` from the Flutter SDK; `golden_toolkit` is discontinued), so text renders the same on every machine; goldens never use the Ahem fallback.
- Base golden per state: light, the template locale, text scale 1.0, default size — `matchesGoldenFile('goldens/foo_page_loaded.png')` on the page's root key.
- One stress golden per screen: dark, the longest locale, text scale 1.3 and 2.0, 360 wide, the longest strings and maximum data.
- `Adaptive*` widgets and platform-specific screens: one golden per `UiPlatform` (`building-adaptive-widgets`).
- Update with `flutter test --update-goldens <file>`, then open every changed PNG before committing; a golden nobody looked at is a silenced check.
- Goldens rendered on one OS: when the team mixes macOS and Linux, render them in one place (the project says where) or set a small tolerance through a custom `GoldenFileComparator`.

## Unknown values

Every enum from the API has a widget test with the `unknown` value: the screen renders the neutral fallback (icon and word), no exception.

## Verify

`scripts/test.sh unit` (or `flutter test modules/ui` with `--coverage`): every new state has a test and a golden, coverage of the screen and its blocs is complete.
