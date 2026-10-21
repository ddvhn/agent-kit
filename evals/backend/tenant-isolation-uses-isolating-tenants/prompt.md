---
description: A request to add a tenant table with Row-Level Security loads isolating-tenants-in-postgres.
tags: [triggers]
plugins: ["../../../plugins/backend", "../../../plugins/core"]
runs: 1
max_turns: 6
allowed_tools: [Skill, Read, Glob, Grep]
---

We keep every customer in one shared Postgres database. Plan the first tenant-owned table so one tenant can never read or reference another tenant's rows, and the tests that prove it.
