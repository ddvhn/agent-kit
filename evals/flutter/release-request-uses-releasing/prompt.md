---
description: A request to upload the Flutter app to TestFlight and Google Play loads releasing-flutter-apps.
tags: [triggers]
plugins: ["../../../plugins/flutter", "../../../plugins/core"]
runs: 1
max_turns: 6
allowed_tools: [Skill, Read, Glob, Grep]
---

Set up uploads of our Flutter app to TestFlight and the Google Play internal track for the dev, staging, and prod flavors, with build numbers taken from the stores and a tag per upload. Plan the setup.
