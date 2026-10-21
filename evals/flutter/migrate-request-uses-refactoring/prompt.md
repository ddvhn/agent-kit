---
description: A request to move an existing Flutter app onto the kit architecture loads refactoring-to-kit-architecture.
tags: [triggers]
plugins: ["../../../plugins/flutter", "../../../plugins/core"]
runs: 1
max_turns: 6
allowed_tools: [Skill, Read, Glob, Grep]
---

Our existing Flutter app keeps business logic in its cubits, has no use cases, and uses plain Navigator routes. Plan how to migrate it to the kit architecture step by step without breaking it.
