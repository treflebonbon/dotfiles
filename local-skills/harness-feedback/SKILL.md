---
name: harness-feedback
description: Analyze Codex or Claude transcript JSONL to detect deviation patterns between skill or agent instructions and actual execution, then propose small instruction fixes.
allowed-tools: Read, Glob, Grep, Bash(jq:*), Bash(nl:*), Bash(awk:*), Bash(ls:*)
metadata:
  depends_on: []
  topics: [harness, transcript, deviation-analysis, observability]
  source: llm
---

# harness-feedback

## Contract

### Input

Accept one optional argument:

| Mode           | Argument                | Behavior                                                                    |
| -------------- | ----------------------- | --------------------------------------------------------------------------- |
| Auto           | none                    | Select the previous transcript matching the current project.                |
| Direct path    | path ending in `.jsonl` | Analyze that transcript directly.                                           |
| Project filter | directory path or name  | Select the newest transcript whose metadata or path maps to that directory. |

If the selected transcript is the active harness-feedback session, skip it and choose the previous matching transcript. In Auto mode, never fall back to a transcript from another project. If no previous matching transcript exists, report "No previous transcript found for the current project" and exit successfully.

### Evidence Extraction

1. Read the transcript before making claims.
2. Preserve line numbers or event identifiers for every finding.
3. Extract agent/skill/tool invocations, progress events, denials, blocked tool calls, and completion claims.
4. Skip huge persisted outputs unless they are necessary evidence.
5. If no skill or agent invocation is found, report "No skill/agent invocations found" and exit successfully.

### Artifact Inputs

When available near the transcript or handoff directory, read these artifacts and cite them in findings:

- `contract.json`: acceptance criteria and verification classification.
- `review.json`: normalized spec or quality review verdicts.
- `active-eval.json`: active evaluation status and result evidence.

Missing or malformed artifacts are warn-only; transcript-only analysis must still complete.

### Skill Definition Resolution

Resolve each referenced skill or agent in this order:

1. Exact local skill or agent definition.
2. Namespace-stripped skill name.
3. External or unknown skill, recorded as skipped.

Read the resolved definition before judging whether behavior deviated from it.

### Effective Contract Resolution

Before deviation analysis, resolve the instructions visible in the transcript into the **effective contract** in this precedence order:

1. System and developer instructions.
2. Applicable project `AGENTS.md` instructions.
3. The invoked skill or agent definition.
4. Open-ended guidance in that definition.

Read the applicable higher-priority instructions before judging the lower-priority skill. When a higher-priority instruction explicitly replaces a lower-priority rule, evaluate execution against the replacement. Do not count compliance with the effective contract as a deviation from the lower-priority skill.

If the conflict is relevant to understanding the run, report it under `## Contract warnings` with the lower-priority rule, the higher-priority replacement, the resulting effective contract, and why it was excluded from findings. Contract warnings do not affect finding counts or severity. Omit the section when there are no warnings.

### Deviation Analysis

Classify findings as step skipped, order violation, instruction ignored, tool mismatch, output format violation, or excessive action. Execution states: completed, blocked, denied, unknown. Before creating a finding, perform scope matching: the rule's subject, target layer, function or artifact kind, and execution context must match the observed action. Severity is `critical` only when the deviation bypassed an approval or safety boundary, omitted a required verification or review, made a false completion claim, or compromised the correctness of the result. Harmless ordering differences and additional verification are not critical and may be excluded when they cause no contract or outcome violation. Blocked or denied actions are normally `minor` unless they caused a false completion claim.

See [references/deviation-categories.md](references/deviation-categories.md) for full category definitions, severity rules, and false-positive prevention rules.

### Artifact-driven enrichment

Artifact context can strengthen evidence and severity without inventing new finding types:

- If `contract.json` lists verifiable criteria but `active-eval.json` is missing or skipped, classify as step skipped.
- If `review.json` has a `NEEDS_CHANGES` verdict but the transcript claims completion, classify as instruction ignored.
- If active evaluation results cover fewer verifiable criteria than the contract requires, cite both artifacts and classify as step skipped.

### Report Output

Print a Markdown report:

```markdown
# Harness Feedback Report

## Summary

- Transcript: <path>
- Session: <id>
- Skills used: <names>
- Agents used: <names>
- Findings: <count> items (critical: <n>, minor: <n>)

## Findings

### [skill-name] <category>

- **Severity**: critical|minor
- **Execution state**: completed|blocked|denied|unknown
- **Expected**: <instruction from the resolved definition>
- **Actual**: <observed behavior>
- **Evidence**: transcript lines and artifact paths
- **Proposed fix**: <small instruction or test change>
```

If findings are empty, include "No deviations found". When transcript evidence shows premature completion, repeated user nudges, or incomplete validation loops, add a `Goal opportunity` section per [references/goal-opportunity.md](references/goal-opportunity.md).

Use [references/normative-examples.md](references/normative-examples.md) as acceptance examples for transcript selection, effective-contract resolution, scope matching, and severity.

## Guardrails

- Do not infer behavior from a transcript that has not been opened.
- Do not propose broad rewrites when a targeted instruction or test would fix the issue.
- Do not include secrets from transcript artifacts in summaries.

## Claude Runtime Notes

- Keep Claude transcript analysis tools in `allowed-tools`, especially `Read`, `Glob`, `Grep`, `jq`, `nl`, `awk`, and `ls`.
- Treat Claude Code transcript JSONL as the runtime-specific input format.
- Claude transcripts live under `~/.claude/projects/<escaped-project-path>/*.jsonl`; when auto-selecting, choose the previous matching project transcript and skip the active harness-feedback session.
- Claude event shapes to inspect include top-level events plus nested `message.content` `tool_use` / `tool_result` entries.
- Scope transcript analysis to top-level events; do not infer hidden subagent execution bodies.
- For `/goal` recommendations, remember Claude's evaluator reads only the conversation and does not run tools; require the agent to surface verification evidence such as test output, PR state, or checklist status before the goal can be judged complete.

## Codex Runtime Notes

- Codex transcripts live under `$CODEX_HOME/sessions/YYYY/MM/DD/*.jsonl` or `~/.codex/sessions/YYYY/MM/DD/*.jsonl`.
- Codex event types to inspect: `response_item`, `mcp_tool_call_end`, and `function_call_output`.
- Prefer Codex transcripts in a Codex runtime; fall back to Claude transcripts for legacy analysis.
