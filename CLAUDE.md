# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

easy-markdown — an AI-native markdown editor for iOS/macOS. No source code or build system yet. Key docs are in place:

- **`docs/PRODUCT.md`** — Product decisions, features, and constraints. Defines *what* and *why*. Decision IDs: `[D-XXX]`.
- **`docs/ARCHITECTURE.md`** — Technical governance. Defines *how* and *with what*. Decision IDs: `[A-XXX]`. **Read this before implementing any backlog item** — it specifies the framework, package, patterns, and hard rules for every feature.

When implementing a backlog item: read ARCHITECTURE.md §2 (feature-to-package mapping) to find where code goes, §9 (conventions) for rules, and the relevant technology section for patterns.

Update this file as the project takes shape with build commands and development workflows.

## Sprint Orchestration (aishore)

AI sprint runner. Backlog lives in `backlog/`, tool lives in `.aishore/`. Run `.aishore/aishore help` for full usage.

```bash
.aishore/aishore run [N|ID]         # Run sprints (branch, commit, merge, push per item)
.aishore/aishore groom [--backlog]  # Groom bugs or features
.aishore/aishore review             # Architecture review
.aishore/aishore status             # Backlog overview
```

After modifying `.aishore/` files, run `.aishore/aishore checksums` before committing.
