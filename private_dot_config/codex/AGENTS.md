# Guidelines

## Language

- Think in English, respond in Japanese.

## Behavior

- Implement clear requests rather than only suggesting changes. Infer routine, reversible steps that stay within the requested scope.
- If tests are incorrect or a task is unreasonable, explain the conflict instead of bypassing it.
- Address root causes and do not use destructive shortcuts such as `--no-verify`.
- Give a reasoned recommendation when asked to choose, unless the decision genuinely belongs to the user.
- Prefer the smallest change that is best for the whole task, including known cross-file effects.

## Investigation before answering

- Inspect referenced code and files before making claims or edits.
- Verify task-critical premises in the current environment.
- When confidence affects the next decision, distinguish confirmed, inferred, and unconfirmed claims.

## Parallel tool calls

Run independent reads and checks in parallel. Sequence calls only when a later call depends on an earlier result.

## Destructive actions

Confirm before actions that are destructive, hard to reverse, or affect shared systems:

- Destructive: deleting files/branches, dropping DB tables, `rm -rf`
- Hard-to-reverse: `git reset --hard`, amending published commits
- High-impact or shared: direct pushes to a default branch, merging/closing/reopening/deleting PRs or issues, releases, workflow dispatches, repository settings or secrets, non-GitHub messages, and shared infrastructure

Routine GitHub collaboration writes do not need a second confirmation once the user has requested the outcome and the content is settled. This covers non-force pushes from the current topic branch using `git-push-topic`; creating, editing, or commenting on PRs and issues; reviewing or marking a PR ready; and creating or editing labels. This does not expand the task's scope.

Requests to address pull request review feedback authorize a Review Round. For that workflow, use `gh-review-thread` rather than the GitHub plugin for thread-aware reads and writes. Group the selected threads into one `fix: address PR review feedback` commit, verify the changes, publish with `git-push-topic`, then post a Japanese reply with the short commit SHA, change summary, and verification result to each addressed thread and resolve it. Mark explanation-only threads with `--explanation-only` and do not create an empty commit. Continue after per-thread failures; leave ambiguous, rejected, failed-verification, unpublished, or failed threads open and report why.

Force pushes are prohibited by policy. Direct raw `git push` commands and common wrapper or global-option variants are blocked by runtime rules. Use `git-push-topic` for the current topic branch. Use `git-push-reviewed` for a default-branch push only after explicit approval.

## GitHub / PR

- PR titles must use Conventional Commits because squash merge uses the PR title as the commit title. Do not add agent prefixes such as `[codex]`.

## Clarifying questions

Use the interactive question tool when it is available and a material choice or clarification is required. Otherwise ask one concise direct question. When presenting choices:

- Provide 2-4 options with their trade-offs
- Put the recommended option first and label it `(Recommended)`
- Show code comparisons when supported and allow multiple selections for independent choices
- Batch up to 4 independent questions

## Quality

Prefer the minimum complexity that satisfies the current task. Avoid unrelated features or refactors, hypothetical abstractions, compatibility shims, and comments on self-evident code. Add validation and comments when the current behavior requires them.

## Visualization

Use Mermaid code blocks, not ASCII art or box-drawing characters.
