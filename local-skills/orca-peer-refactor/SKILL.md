---
name: orca-peer-refactor
description: "Orca の native orchestration を使った候補改善を明示依頼されたときに使う。/improve-codebase-architecture が提示済みの元候補を固定し、supervised worker の writer と read-only peer の協働、検証、独立レビューを経て PR にする。人への設計質問を peer 相談へ置き換える。通常 session でも使える。"
---

# orca-peer-refactor

**成果物：元の候補に対応する PR と検証結果。** [規範契約](~/runtime/autonomous-peer-contract.md) を先に読む。候補探索はやり直さず、現在の依頼・元レポート・実コードから進める。既存の承認は引き継ぎ、skill 自体から外部操作の権限は得ない。

## 1. 元の候補を固定

提示済み artifact と、その提示時の repo・source SHA を読む。提示時に記録された repo の共通 Git dir の絶対パスを使い、未記録なら artifact が示す元 repo から read-only で解決する。出所が確認できない場合、現在の cwd で補わず保留する。候補がゼロなら Top recommendation は「該当候補なし」とし、候補選択質問をせず、完了 report を出す。候補があるのに peer 依頼未承認で未選択なら pin しない。人が選んだ候補（「両方」など）は保持する。人が peer 協働を明示依頼して選択を委任した場合だけ、推薦順位を渡さず peer にコード・ADR・反例から元候補を選ばせ、その候補を pin する。artifact 不明・別 repo・出所不明なら再探索で補わず保留する。

HTML report の pin は、静的検査と実ブラウザ描画検査が成功し、その後に同じ artifact を提示した場合だけ行う。`python3 <skill-dir>/scripts/check-architecture-report.py <report.html>` は Mermaid `<pre>` の raw text と期待図数を検査するだけで、実描画を証明しない。提示前に検査されていない report は、検査後に提示し直す。HTML 検査の失敗時は pin しない。Markdown artifact は従来経路を保ち、HTML 描画検査を要求しない。候補ゼロ、または peer 依頼未承認で未選択ならこの pin 手順へ入らない。peer 協働の明示依頼で選択を委任された場合は、peer が元候補一覧から選んだ候補を pin してよい。

`skill_dir` は source checkout では `<repo>/local-skills/herdr-peer-refactor` または `<repo>/local-skills/orca-peer-refactor`、配備後は `$HOME/.agents/skills/<skill>` または `$HOME/.claude/skills/<skill>` に設定する（`<skill>` はこの skill の name）。配備後に source の `local-skills/...` path は使わない。Orca 内蔵 page の操作は `orca-cli`、この検証用の外部 browser は `playwright-cli` を使う。実ブラウザでは report の directory を loopback のみで listen する HTTP server で配信し、`playwright-cli` で開いて次の script を実行する。`file:` URL は CLI が拒否する。server への URL と report artifact の path が一致することを確認し、検査後に server を停止する。

```bash
: "${skill_dir:?現在の skill directory を指定してください}"
report="/absolute/path/to/report.html"
python3 "$skill_dir/scripts/check-architecture-report.py" "$report"
python3 -m http.server 8765 --bind 127.0.0.1 --directory "$(dirname "$report")"
```

別 terminal:

```bash
: "${skill_dir:?現在の skill directory を指定してください}"
report="/absolute/path/to/report.html"
expected=1 # 静的 checker の expected_mermaid_diagrams
render_script="$skill_dir/scripts/check-architecture-render.js"
playwright-cli open "http://127.0.0.1:8765/$(basename "$report")?__architecture_expected_mermaid=$expected"
playwright-cli run-code "$(sed '$s/;$//' "$render_script")"
```

描画検査は静的 checker の期待図数を URL の `__architecture_expected_mermaid` に渡し、HTML の raw `pre.mermaid` 数と Mermaid 実行後の container 数、各 container に SVG がちょうど1個あることを照合する。ページの HTTP 応答成功、`.error-icon` / `.error-text` 等の error marker、uncaught browser error、favicon.ico 取得失敗以外の console error も確認する。成功結果を確認してから report を提示し、選択済み候補または明示 peer 依頼で peer が選んだ元候補を pin する。修正版は元 artifact を上書きせず、新しい artifact として再検査・提示する。

oxfmt が JS expression の末尾に追加する `;` だけを除いてから `run-code` に渡す。CLI が source を expression として括るために必要な処理である。

`.tmp/architecture-run/` に候補ごとの `id`、元の `title`、`acceptance`（受入条件の配列）、`non_goals`（非目標の配列）、`owned_files`（変更担当のファイル・行範囲の配列）を JSON に記録する。受入条件は元の改善意図を具体化し、既存 helper の整備など別の目的へ差し替えない。peer と合意した非目標も明記する。

```bash
python3 <skill-dir>/scripts/candidate-record.py pin <artifact> <source-repo-common-dir> <source-sha> <candidates.json> <record.json>
python3 <skill-dir>/scripts/candidate-record.py check <record.json> <candidates.json> <record-sha256>
```

`pin` は提示元の共通 Git dir と実行先 repo の一致を確認してから、artifact の内容・提示元 repo・元 SHA・候補を固定し、既存 record を上書きしない。出力された record の SHA-256 はファイル外の会話の実行記録に残し、`check` に必ず渡す。record と候補を同時に変更しても、この fingerprint と一致しなければ保留する。元 SHA を ancestor に保つ descendant HEAD や rebase 後も元の出所を保つ。source-sha は完全な commit SHA を使う。`pin` と `check` は、共通 Git dir が第2引数と一致する提示元 repo の cwd で実行する。native checkout など別 repo の cwd では拒否されるため、出所を差し替えず保留する。`check` は設計前、再開時、公開前に行う。候補を追加・変更する承認がある場合は、理由と旧 record を保持して新しい run にする。

## 2. worktree と担当

`runtime/skill-harness.md` の native 機構で候補ごとに validated task worktree を作成する。親は調整、候補ごとに writer は一人、別 terminal の peer は read-only とする。他者の未 commit 変更は引き取らない。

[Orca 手順](references/orca.md) を読み、Orca の worker / terminal を使う。内部 subagent を native peer の実績として扱わない。Herdr で行う場合は `herdr-peer-refactor` を使う。

並行数は利用可能な slot と所有範囲に合わせて記録する。同じファイルでも別 hunk かつ挙動が独立なら並行にできる。読取り依存を含む意味的な競合は直列にする。公開前に実差分を `check-owned.sh <worktree> <base> <owned-files>` で照合し、並行差分の Git 結合と挙動の整合を別々に確認する。main を取り込む・rebase した後は、`check-owned.sh` の base を新しい main の SHA にする。旧 base のままだと、取り込んだ変更が範囲外と判定される。範囲付きの宣言(`path:start-end`)は、新 base のファイルでの行番号に読み替えて渡す(record の `owned_files` は変えない)。

## 3. peer と設計

`codebase-design` の語彙を使い、未確定の問い・選択肢・元候補・AC・非目標・関連 ADR を peer に渡す。自分の結論を先に渡さず、反例または peer 自身の検証を求める。可逆な判断は根拠付き Peer Decision として記録する。モデルが同じかどうかで権限を変えない。

人の回答を待つ `grilling` を呼んで peer の回答を人の回答として扱わない。判断の frontier を peer と詰める。複数 session にまたがる仕様化が必要な場合だけ `to-spec` / `to-tickets` を使い、候補 ID と受入条件を引き継ぐ。小さな候補は設計記録から直接実装する。issue は任意で、承認済みの場合だけ 目的・AC・非目標・検証方法・関連ファイル／入口・判断済み tradeoff を載せて作る。

新しい ADR・仕様・schema、破壊的操作、課金、共有環境の判断が必要なら、その候補を Held Candidate として提案と根拠を残す。既に明示承認された同じ判断を再質問しない。他の候補は進める。

## 4. 実装と検証

writer は `tdd` で AC を外部から観測する失敗を再現し、最小の変更を実装する。移動した処理の拒否・失敗分類・確定・冪等性を保つ。新規・変更した各テストは、対象の挙動を一時的に消すと赤になることを実際に確認して記録する(**mutation check**)。委譲・拒否・回数の検証が、何を消しても通る形になるのを防ぐ。実装前に base を固定し、repo の必要な全チェックを完了する。main が進んだ場合は未公開 branch に取り込み、再検証する。

peer 応答は依頼 ID・対象 SHA・検証根拠が一致して初めて完了とする。idle・送信成功・dashboard・古い応答は完了ではない。失敗後に再送する前に状態と成果物を照会する。`blocked`、確認不能、同じ失敗 2 回、予算超過は保留し、writer の pane（Orca では terminal）・worktree を保持する。

## 5. 独立レビュー

commit 済みの最終 SHA に `code-review` の **Standards** と **Spec** を独立した read-only peer で並行実行する。Spec には元 artifact・固定 record・AC・非目標・現在の依頼を渡す。過去の参考資料と現在の要件を区別し、候補から helper 整備などへの逸脱を検査する。

reviewer の sandbox では repo の検査を実行できないことがある。親が最終 SHA の repo チェック(typecheck・lint・対象テスト)を task worktree で実行し、結果ファイルを依頼に添える。reviewer には読取りと判断を求め、検証用の harness を自作させない。reviewer の環境に `code-review` skill が無いときは、Standards／Spec の観点を依頼文に書く。

reviewer から base と対象 SHA の Git object が読めるか先に確認する。読めなければ primary repo の read-only な pane（Orca では terminal）で同じ SHA を検査する。権限を広げたり、渡した patch だけを元 repo 全体の検証済みレビューと呼んだりしない。

指摘を実コードで確認し、修正・検証・commit の後は新しい SHA に再レビューする。新 HEAD に古い SHA の結果を流用しない。並行 branch の `merge-tree` 成功は挙動テストの代わりではない。

## 6. PR と報告

公開前に record・所有範囲・検証・両軸の対象 SHA を再確認する。`git-push-topic` で topic を公開し、`pr` で PR 本文を書く。元の候補 ID／名称、受入条件と結果、非目標、Peer Decision、保留理由を含める。issue がある場合だけ `Closes #N` を付ける。外部書込みは依頼の承認範囲に限り、issue／報告の再送は既存 `gh-once.sh` で重複を避ける。

レビュー指摘対応は `gh-review-thread` で、修正の公開後に返信・resolve する。最後に `gh pr view --json state,headRefOid,isDraft` を読み直し、元候補 → PR、最終 SHA、検証、未実行・保留を報告する。merge と issue の直接 close は行わない。未 merge の task source から配備しない。
