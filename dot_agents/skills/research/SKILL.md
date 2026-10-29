---
name: research
description: Investigate a question against primary sources and save the findings as one cited Markdown file in the repo. Use when the user wants a topic researched, docs or API facts gathered, a version claim checked, or reading legwork delegated to a background agent.
---

# Research

Delegate the reading to the `researcher` subagent and keep working while it reads.
The `researcher` holds the source rules and the output format. This skill only
writes its brief.

## Process

1. **List the requirements.** Name the decision the research serves and the goal
   behind it. Break the goal into the requirements any solution must meet: what
   must be shared, what must stay apart, what must survive, what must stay
   unchanged. Tag each requirement with its source: `user` when the user stated
   it, `inferred` when you derived it. Ask the user to confirm the `inferred`
   ones before you spawn, or carry them into the brief as unconfirmed. Done when
   every requirement has a tag.
2. **Narrow the question.** Give each `researcher` one decision. Split a broad
   topic into the decisions that wait on it.
3. **Spawn one `researcher` in the background.**
   - Claude Code: call the Agent tool with `subagent_type: "researcher"`.
   - Codex: call `spawn_agent` with the `researcher` agent.

   Spawn exactly one per decision. The `researcher` does not delegate.
4. **Write the brief.** The `researcher` starts with no conversation history.
   Give it:
   - the decision, its goal, and the tagged requirements;
   - versions and platforms that apply;
   - earlier notes on the topic, by path, to read first and extend. For each
     note, state the premises it rested on (platform, version, the question it
     answered) and which of them differ now;
   - the directory where this repo keeps research notes, when you know it.
5. **Continue the user's task.** Do not wait on the agent and do not repeat its
   reading yourself.
6. **Relay the result.** When the `researcher` reports, give the user the file
   path, the options that meet the requirements, the requirements still
   unconfirmed, and the items it marked unverified or unknown.

Derived from the `research` skill in mattpocock/skills (MIT). See `LICENSE`.
