---
description: A request to make a save work without network loads queueing-offline-actions.
tags: [triggers]
plugins: ["../../../plugins/flutter", "../../../plugins/core"]
runs: 1
max_turns: 6
allowed_tools: [Skill, Read, Glob, Grep]
---

Saving a foo in our Flutter app fails when the phone has no network. Make it work offline: show the change at once, send it when the network is back, never twice, and roll it back if the server refuses. Plan the subtasks.
