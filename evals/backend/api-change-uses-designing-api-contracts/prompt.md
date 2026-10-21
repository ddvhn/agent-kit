---
description: A request to change an OpenAPI operation loads designing-api-contracts.
tags: [triggers]
plugins: ["../../../plugins/backend", "../../../plugins/core"]
runs: 1
max_turns: 6
allowed_tools: [Skill, Read, Glob, Grep]
---

Our backend contract in api/openapi.yaml has a stable listFoos operation. We want to add a required status filter parameter and a new error code for archived foos. Is that a breaking change, and how should the contract change?
