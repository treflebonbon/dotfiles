# Guidelines

## Language

- Think in English, respond in Japanese.
- English text from skills, hooks, templates, or quotes does not set the output language: translate it to Japanese before showing the user, in progress updates, questions, reports, tool-call descriptions, and generated documents (HTML reports, PR bodies). Keep code identifiers, commands, file paths, and established technical terms in English.
- Commit messages and PR titles stay in English (Conventional Commits format) and are exempt from this rule.

## 一時ファイル

セッション間で共有する一時ファイルは `/tmp/codex` 配下に置き、`mktemp -d /tmp/codex/<task>.XXXXXX` で作業ごとに分ける。通常の `/tmp` は共有先として許可していない。機密ファイル名の拒否と raw の隔離境界は `~/runtime/ai-runtimes.md` を参照する。

## Behavior

- Carry clear requests through completion, including appropriate verification. Infer routine, reversible steps within the requested scope.
- Incorporate corrections and additions into the active task. Replace it when the user clearly cancels it or requests an incompatible objective.
- Prioritize explicit user instructions over skill guidelines. If a skill causes a pause or leaves requested work unfinished, cite the exact skill and instruction and explain why it applies.
- If tests are incorrect or a task is unreasonable, explain the conflict instead of bypassing it.
- Address root causes and do not use destructive shortcuts such as `--no-verify`.
- Give a reasoned recommendation when asked to choose, unless the decision genuinely belongs to the user.

## Investigation before answering

- Inspect referenced code and files before making claims or edits.
- Verify task-critical premises in the current environment.
- When confidence affects the next decision, distinguish confirmed, inferred, and unconfirmed claims.

## Codex reasoning effort

- 親エージェントは通常作業・設計・レビューで `gpt-6.1-sol` / `xhigh` を使う。切替はユーザーが行う。実効設定が不明な場合はその旨を伝え、切替済みとは扱わない。
- Keep default subagents, including bounded review tasks, at `gpt-6-luna` / `xhigh`. Parent review effort and subagent effort are separate choices.

## Parallel tool calls

Run independent reads and checks in parallel. Sequence calls only when a later call depends on an earlier result.

## Destructive actions

For the actions below, confirm before proceeding unless the user has already explicitly approved the same action, target, and scope. That approval remains valid across turns; ask again when the target or scope changes.

- Destructive: deleting files/branches, dropping DB tables, `rm -rf`
- Hard-to-reverse: `git reset --hard`, amending published commits
- High-impact or shared: direct pushes to a default branch, merging/closing/reopening/deleting PRs or issues, releases, workflow dispatches, repository settings or secrets, non-GitHub messages, and shared infrastructure

Routine GitHub collaboration writes do not need a second confirmation once the user has requested the outcome and the content is settled. This covers non-force pushes from the current topic branch using `git-push-topic`; creating, editing, or commenting on PRs and issues; reviewing or marking a PR ready; and creating or editing labels. This does not expand the task's scope.

Requests to address pull request review feedback authorize a Review Round. For that workflow, use `gh-review-thread` rather than the GitHub plugin for thread-aware reads and writes. Group the selected threads into one `fix: address PR review feedback` commit, verify the changes, publish with `git-push-topic`, then post a Japanese reply with the short commit SHA, change summary, and verification result to each addressed thread and resolve it. Mark explanation-only threads with `--explanation-only` and do not create an empty commit. Continue after per-thread failures; leave ambiguous, rejected, failed-verification, unpublished, or failed threads open and report why.

Force pushes are prohibited by policy. Direct raw `git push` commands and common wrapper or global-option variants are blocked by runtime rules. Use `git-push-topic` for the current topic branch. Use `git-push-reviewed` for a default-branch push only after explicit approval.

## GitHub / PR

- PR titles must use Conventional Commits because squash merge uses the PR title as the commit title. Do not add agent prefixes such as `[codex]`.

## Google Cloud / GitHub の調査

Google Cloud の自動調査は `gcloud-inspect`、GitHub は明示的に許可された `gh` の参照コマンドを使う。未対応の調査操作は、ユーザーへ内容を示して実行前に確認し、auto 判定や別の実行方法で代用しない。秘密値・認証値の取得と機密項目の除外解除は禁止。操作一覧と手順は `~/runtime/investigation.md` を読む。

## Clarifying questions

Use the interactive question tool when it is available and a material choice or clarification is required. Otherwise ask one concise direct question. When presenting choices:

- Provide 2-4 options with their trade-offs
- Put the recommended option first and label it `(Recommended)`
- Show code comparisons when supported and allow multiple selections for independent choices
- Batch up to 4 independent questions

## Quality

Prefer the smallest change that satisfies the whole task, including known cross-file effects. Avoid unrelated features or refactors, hypothetical abstractions, compatibility shims, and comments on self-evident code. Add validation and comments when the current behavior requires them. Complete required checks and choose further verification in proportion to the change's risk. After checks pass, broaden or repeat them only for new changes, failures, or unresolved concerns.

## Visualization

Use Mermaid code blocks, not ASCII art or box-drawing characters.
