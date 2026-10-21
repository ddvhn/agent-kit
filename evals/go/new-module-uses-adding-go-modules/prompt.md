---
description: A request for a new bounded context in a Go backend loads adding-go-modules.
tags: [triggers]
plugins: ["../../../plugins/go", "../../../plugins/backend", "../../../plugins/core"]
runs: 1
max_turns: 6
allowed_tools: [Skill, Read, Glob, Grep]
---

Our Go modular monolith needs a new invoices module with its own tables, use cases, and endpoints. Plan how to add it.
