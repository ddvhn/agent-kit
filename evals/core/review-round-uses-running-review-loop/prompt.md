---
description: A request for the next review round of a PR loads running-review-loop.
tags: [triggers]
plugins: ["../../../plugins/core"]
runs: 1
max_turns: 6
allowed_tools: [Skill, Read, Glob, Grep]
---

Round 1 of the review on PR #12 found two blocking issues; both are fixed in new commits. Start review round 2.
