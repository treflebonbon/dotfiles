# Orca の native 協働

`orca-cli` と `orchestration` の skill を読み、現在の runtime guide と receipt を正本にする。コマンド例は [CLI reference](https://www.onorca.dev/docs/cli/reference) と [Orchestration](https://www.onorca.dev/docs/cli/orchestration) を 2026-10-10 に照合した。

実行ファイルは `orca-cli` の選択規則で一度だけ決める。`ORCA_CLI_COMMAND` が設定済みならその値、次に `ORCA_DEV_REPO_ROOT` を公開する dev session なら `orca-dev`、Linux の Orca 管理外 terminal なら WSL bridge を含む `orca-ide`、それ以外は `orca` を使う。Linux 管理外で bare `orca` を実行しない。

以下の `ORCA` は選んだ実行ファイルへの置換用で、literal コマンドや shell 変数ではない。最初に版が一致する guide を読み、以降も同じ実行ファイルを使う。起動不能なら正確なエラーを報告し、別実行ファイルへ自動で切り替えない。

```text
ORCA skills get orca-cli --json
ORCA skills get orchestration --json
```

共有 receipt と reply は、SKILL.md で作成した `/tmp/codex` 配下の run directory に置く。以降の `$run_dir` はその確認済み絶対パスを指す。保存・中断からの復旧は [証跡の保存と復旧](evidence.md) に従う。

## native 評価前の preflight

評価前に、本番と同じ native 起動経路で root → peer の深度と起動 effective 値（agent / model / effort）を smoke 確認する。`nested_worker_depth_exceeded` はシナリオの失敗採点ではなく環境不適合として別に記録する。設定変更や新しい Run の作成で深度をリセットしたことにしない。

Run / Dispatch の receipt は、独立した runtime の期待値と照合する。`scripts/orca-preflight.py` は保存済み JSON を読むだけで、CLI の wrapper、Run の bind、権限付与、再送は行わない。

```text
python3 <skill-dir>/scripts/orca-preflight.py coordinator <run-receipt.json> --run <expected-run-id> --handle <coordinator-handle>
python3 <skill-dir>/scripts/orca-preflight.py worker-show <worker-show-receipt.json> --dispatch <expected-dispatch-id> --task <expected-task-id> --assignee <expected-terminal-handle>
```

coordinator receipt は `ok: true` と `result.run.id` / `result.run.coordinator_handle` の一致を要する。worker-show receipt は `ok: true` と `result.dispatch.id` / `taskId` / `assigneeHandle` の一致、および `status: dispatched` を要する。settled、error、malformed、欠落、不一致は拒否する。期待値は preamble または runtime の bound Run / worker-start 結果から取り、検査対象の receipt から作らない。

## 役割別の正規経路

以下の `run-create`／`worker-start` の例は初回起動用。再開時は既存 receipt を照合し、native の現在状態を確認してから続ける。起動コマンドを再実行せず、読取り例を使う。receipt の存在だけを完了と扱わず、不正・未完了なら保持して復旧手順へ戻る。

### 普通の dispatched worker

自分の live preamble の handle で、自分の inbox を読む。通常の dispatched worker は `--run` を付けず、status を含む全 delivery を確認する。

```text
ORCA orchestration check --terminal <worker-handle> --wait --timeout-ms 45000 --json
ORCA orchestration check --terminal <worker-handle> --ack <delivery-id-from-result-json> --wait --timeout-ms 45000 --json
```

### coordinator

coordinator は自分の terminal handle で Run を作成・bindし、返った Run ID を全 task / worker 操作に使う。

```text
: "${run_dir:?共有 run directory の絶対パスを指定してください}"
(set -C; ORCA orchestration run-create --objective "<元候補の改善>" --from <coordinator-handle> --json > "$run_dir/run-create.json")
ORCA orchestration check --terminal <coordinator-handle> --run <run-id> --wait --timeout-ms 45000 --json
ORCA orchestration task-create --spec "<候補ID・AC・非目標・所有範囲・writerまたはreviewer>" --task-title "<title>" --run <run-id> --from <coordinator-handle> --json
receipt_dir=$(mktemp -d "$run_dir/worker.XXXXXX")
(set -C; ORCA orchestration worker-start --task <task-id> --worktree id:<returned-worktree-id> --agent claude --run <run-id> --from <coordinator-handle> --json > "$receipt_dir/worker-start.json")
(set -C; ORCA orchestration worker-show --dispatch <dispatch-id> --json > "$receipt_dir/worker-show.json")
python3 <skill-dir>/scripts/orca-preflight.py coordinator "$run_dir/run-create.json" --run <bound-run-id> --handle <runtime-handle>
python3 <skill-dir>/scripts/orca-preflight.py worker-show "$receipt_dir/worker-show.json" --dispatch <started-dispatch-id> --task <started-task-id> --assignee <started-terminal-handle>
```

worker ごとに `mktemp` の返した receipt directory を保持し、再実行時は既存 receipt を読み直す。新しい worker には新しい directory を作る。checkpoint には全 worker の各 receipt ファイルを明示して渡す。

保存した `run-create` receipt と、独立して分かっている Run ID / coordinator handle を coordinator preflight に渡す。`worker-show` receipt も start が返した Task / Dispatch / terminal と照合してから進む。reviewer は別 terminal の read-only peer とし、worker を別 runtime の subagent に置換しない。

peer には共有の絶対 reply-file を渡し、1 行目を `DONE <REQ> <sha>` にさせる。採用前に、この行と応答内の Task / Dispatch ID を `worker-start` receipt と照合する。`worker-start` に read-only の強制指定はないため、所有範囲は spec に明記し、完了後に native と fixture の `git status` と入力 hash が未変更であることを確認してから採用する。

### nested coordinator

実 worker がさらに peer を監督するときは、自分が owner となる child Run を作成・bindする。上位 coordinator から自分の Dispatch 宛てに届く follow-up と child worker の message は、child Run に bind した自分の terminal inbox で処理する。上位 Task / Dispatch / REQ / SHA は保持し、上位へ返す完了は live preamble の handle と Task / Dispatch ID を使う。

```text
: "${run_dir:?共有 run directory の絶対パスを指定してください}"
child_run_dir=$(mktemp -d "$run_dir/child-run.XXXXXX")
(set -C; ORCA orchestration run-create --objective "<child work>" --from <nested-coordinator-handle> --json > "$child_run_dir/run-create.json")
ORCA orchestration check --terminal <nested-coordinator-handle> --run <child-run-id> --wait --timeout-ms 45000 --json
ORCA orchestration task-create --spec "<child task>" --task-title "<title>" --run <child-run-id> --from <nested-coordinator-handle> --json
child_receipt_dir=$(mktemp -d "$child_run_dir/worker.XXXXXX")
(set -C; ORCA orchestration worker-start --task <child-task-id> --worktree id:<child-worktree-id> --agent codex --run <child-run-id> --from <nested-coordinator-handle> --json > "$child_receipt_dir/worker-start.json")
```

peer の ID / Run で上位の ID を置き換えたり、上位 coordinator の mailbox を直接読んだりしない。

上位 coordinator から nested Dispatch への follow-up は、安定した Dispatch 宛てに送り `--run` を省略する。child coordinator の `check` / `reply` / ack は child Run を指定し、上位 coordinator の `check` / `reply` / ack は上位 Run を指定する。

```text
ORCA orchestration send --to dispatch:<nested-dispatch-id> --from <coordinator-handle> --subject "follow-up" --body "<literal body>" --type status --json
```

## ID を receipt から渡す

ID を手入力・再構成せず、JSON receipt を `json.load` し、その値を `subprocess.run` の argv list に渡す。以下は選択済み CLI を `orca` に設定する例。実行時の第1引数に上記 `$run_dir`、第2引数に対象 worker の `$receipt_dir` を渡す。coordinator の expected Run ID は bound inbox の peek 結果、handle は runtime が出した `ORCA_TERMINAL_HANDLE` と照合する。worker-show の expected 値は worker-start receipt から取り出す。

```bash
python3 - "${run_dir:?共有 run directory の絶対パスを指定してください}" "${receipt_dir:?対象 worker の receipt directory を指定してください}" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
receipt_dir = Path(sys.argv[2])

orca = "orca-ide"  # ここを選択済み CLI に置き換える
checker = "<skill-dir>/scripts/orca-preflight.py"
with open(run_dir / "run-create.json", encoding="utf-8") as stream:
    created = json.load(stream)
run = created["result"]["run"]
handle = os.environ["ORCA_TERMINAL_HANDLE"]
bound = subprocess.run(
    [orca, "orchestration", "check", "--terminal", handle, "--peek", "--json"],
    capture_output=True,
    text=True,
    check=True,
)
run_id = json.loads(bound.stdout)["result"]["runId"]
subprocess.run(
    [sys.executable, checker, "coordinator", str(run_dir / "run-create.json"), "--run", run_id, "--handle", handle],
    check=True,
)
subprocess.run(
    [orca, "orchestration", "check", "--terminal", handle, "--run", run_id, "--wait", "--timeout-ms", "45000", "--json"],
    check=True,
)

with open(receipt_dir / "worker-start.json", encoding="utf-8") as stream:
    started = json.load(stream)["result"]
assignee = next(
    effect["id"] for effect in started["effects"]
    if effect.get("kind") == "terminal" and effect.get("role") == "agent"
)
shown_path = receipt_dir / "worker-show.json"
if not shown_path.exists():
    shown = subprocess.run(
        [orca, "orchestration", "worker-show", "--dispatch", started["dispatchId"], "--json"],
        capture_output=True,
        text=True,
        check=True,
    )
    with open(shown_path, "x", encoding="utf-8") as stream:
        stream.write(shown.stdout)
subprocess.run(
    [sys.executable, checker, "worker-show", str(receipt_dir / "worker-show.json"), "--dispatch", started["dispatchId"], "--task", started["taskId"], "--assignee", assignee],
    check=True,
)
PY
```

ordinary / nested worker の `check` は filter なしで whole FIFO を読むため、`status` follow-up でも起きる。全 message を処理してから、JSON の `result.deliveryId` を同じ handle の `--ack` argv に渡す。`consumer_fenced` は例外を成功扱いせず、その場で停止する。

## literal message body

shell 展開を避けるため、body を argv の一要素として `subprocess.run` に渡す。`shell=True` や shell command 文字列は使わない。live receipt の宛先・handle・Run ID に置き換える。

<!-- literal-safe-example:start -->

```python
import subprocess

body = "\n".join((
    "レビューの要点:",
    'literal $HOME、$(printf test)、`バッククォート`、"二重引用符"、\'一重引用符\' を含む。',
))
orca = "orca-ide"  # ここを選択済み CLI に置き換える
subprocess.run(
    [
        orca,
        "orchestration", "send",
        "--to", "run:<run-id>",
        "--run", "<run-id>",
        "--from", "<sender-handle>",
        "--subject", "レビュー依頼",
        "--body", body,
        "--type", "status",
        "--json",
    ],
    check=True,
)
```

<!-- literal-safe-example:end -->

## 検証記録

検証記録は全採点と native receipt が確定し、一つにまとまった evidence packet を受け取った後にだけ書く。全 raw log は保管し、本文には選んだ項目と参照先だけを表示する。usage が取得できない場合は `null` とし、0 や推定値で埋めない。`tool_uses` または `duration_ms` が欠けた round は strict convergence の判定に含めず、既存の `empirical-prompt-tuning` 規則どおり `qualitative plateau; quantitative convergence unverified` と記録して metadata を提供する runtime で再評価するか、`resource cutoff` として終了する。native boundary smoke は native 境界の成立確認、committed SHA の Standards / Spec review はコード差分の確認として別々に記録し、相互の証拠にしない。

## inbox / settlement

Delivery の全 message を処理してから ack する。完了は現在の Task ID / Dispatch ID、依頼 ID／SHA と検証結果を照合して採用する。terminal の idle や送信成功だけでは完了にしない。`consumer_fenced` を受けたら停止し、再試行も `worker_done` も送らず、receipt とエラーを保持する。

共有・remote の状態をローカルから推測せず、接続喪失を process 終了と扱わない。settlement は runtime guide に従い、完了済み reviewer は worker-read で記録を保存してから worker-release する。保留・状態不明の process を停止・release せず保持する。`run` / `run-stop` は廃止されたため使わず、共有状態の `reset` はこのフローで実行しない。
