---
name: research
description: Investigate a question against primary sources and save the findings as one cited Markdown file in the repo. Use when the user wants a topic researched, docs or API facts gathered, a version claim checked, or reading legwork delegated to a background agent.
---

# Research

Delegate the reading to the `researcher` subagent and keep working while it reads.
The `researcher` holds the source rules and the output format. This skill only
writes its brief.

## Process

1. **Narrow the question.** One API, one behaviour, or one version claim returns a
   better note than "research X". Split a broad topic into the questions a
   decision is waiting on.
2. **Spawn one `researcher` in the background.**
   - Claude Code: call the Agent tool with `subagent_type: "researcher"`.
   - Codex: call `spawn_agent` with the `researcher` agent.

   Spawn exactly one per question. The `researcher` does not delegate.
3. **Write the brief.** The `researcher` starts with no conversation history.
   Give it:
   - the question, and the decision that waits on the answer;
   - versions and platforms that apply;
   - earlier notes on the topic, by path, to read first and extend;
   - the directory where this repo keeps research notes, when you know it.
4. **Continue the user's task.** Do not wait on the agent and do not repeat its
   reading yourself.
5. **Relay the result.** When the `researcher` reports, give the user the file
   path, the findings, and the items it marked unverified or unknown.

Derived from the `research` skill in mattpocock/skills (MIT). See `LICENSE`.
