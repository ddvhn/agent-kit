---
description: The SubagentStart hook gives core:developer the minimal-change rule.
tags: [smoke, subagents]
plugins: ["../../../plugins/core"]
runs: 1
max_turns: 4
allowed_tools: [Agent]
---

Use the Agent tool to run the core:developer subagent with exactly this prompt: "Do not use any tools. Quote the first sentence under the heading Minimal change in your context. If there is no such heading, reply exactly MISSING." Then repeat its reply verbatim.
