---
name: driving-flutter-app
description: Drive the running Flutter debug app to see a change work — connect Marionette, hot reload, walk the flow, read logs and runtime errors, take screenshots. Use for the lead's short live check after a small UI change, when debugging behavior in the running app, and as the qa subagent's procedure.
---

# Driving the Flutter app

App launch configs, Marionette URIs, and the backend the debug app talks to are in `CLAUDE.md` → Project facts. For M/L tasks the live check is the `flutter:qa` pass; the lead does a short pass itself only for small changes.

## Connect

1. The app must already run from a launch config in Project facts (`dev-agent` pins the VM service port and disables auth codes so the MCP servers can attach; debug-only, on a trusted machine, never with a production backend). If none is running, ask the user to start one. Never launch a second instance.
2. Marionette `connect` to the app's URI. A 403 means the DDS still uses an auth code: take the `ws://…/<code>/ws` URI from the app's debug console ("Debug service listening on"). Connect fails → there is no debug session; say so and skip the live pass.
3. Apply edits with `hot_reload`; use `hot_restart` after changes to `initState`, globals, DI, or `main()`. Skip for comment-only edits.

## Walk the flow

- Find targets with `get_interactive_elements` (the app's widget keys make this reliable), then `tap`, `enter_text`, `scroll_to`, `press_key`, `press_back_button`.
- Check the states the change touches: loading, empty, error, success, saving — and the neighboring screens that share its widgets or blocs.
- Screenshots (`take_screenshots`) cost context: take them only where they show something, and at the window or device sizes Project facts names.

## Diagnose

- `get_logs` for app logs.
- Runtime errors and the widget tree: the `dart` MCP server (`get_runtime_errors`, `widget_inspector`) once connected to the IDE's tooling daemon — ask the user for the DTD URI ("Dart: Copy DTD URI to Clipboard") and pass it to `dtd`.
- Layout errors (overflow, unbounded constraints): `flutter-fix-layout-issues`.

## Data safety

The debug app talks to a non-production backend — staging or local emulators (Project facts; `di` rule → Build configuration). If it points at production, stop and tell the user. Create data only under the test account; delete, publish, pay, or send anything outward only when the user allowed it for this run.
