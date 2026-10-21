---
description: The SubagentStart hooks give core:developer the Go rule.
tags: [smoke, subagents]
plugins: ["../../../plugins/go", "../../../plugins/backend", "../../../plugins/core"]
runs: 1
max_turns: 4
allowed_tools: [Agent]
---

Use the Agent tool to run the core:developer subagent with exactly this prompt: "Do not use any tools. Quote the first bullet under the heading # Go in your context. If there is no such heading, reply exactly MISSING." Then repeat its reply verbatim.
