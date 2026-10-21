---
description: The go plugin SessionStart hooks put the Go rule into the main session.
tags: [smoke, context]
plugins: ["../../../plugins/go", "../../../plugins/backend", "../../../plugins/core"]
runs: 1
max_turns: 2
---

Without using any tools, quote the first bullet under the heading "# Go" in your context. If there is no such heading, reply exactly MISSING.
