---
type: decision
title: Dogfood の実行完了と証跡の充足を分けて扱う
description: 実行失敗や証跡欠落を finding 件数から独立して記録し、候補レビューと連続0件の判定条件を分ける
tags: [adr, dogfood, evidence, skills]
timestamp: 2026-09-07
status: accepted
---

# Dogfood の実行完了と証跡の充足を分けて扱う

現行 runner は起動に失敗しても finding が0件なら対象の読み込み成功を報告し、画像や trace の保存に失敗しても予定のパスを Evidence に載せる。Dogfood 実行結果として検査の完了状況、収集済み finding、証跡の充足と収集失敗をまとめ、候補レビューへ進める条件と、検査を十分に完了したと数える条件を分ける。

## Decision

1. 検査処理と終了処理が完了し、画像や trace などの証跡だけが欠けた場合は、欠落理由を記した「警告付き完了」として終了コード0で候補レビューへ進める。finding の有無は実行の成否と独立させる。
2. 起動、annotation、ブラウザ終了処理などの失敗で実行全体が完了しなかった場合は、非0で終了して自動の候補レビューを停止する。収集済み finding と失敗・未確認範囲を保持し、明示的な `--resume` でその候補をレビューできる。再開によって過去の実行を正常完了に読み替えない。
3. 対象ページの読み込み失敗を観測した後、残りの検査処理と終了処理が完了した場合は、実行完了と読み込み失敗の finding を併記する。既存の High / functional の候補としてレビューへ進めるが、対象を正常に読み込めたとは記載しない。
4. 検査内容と finding を記録した `report.md` を最低限の記録とする。画像、trace、console/network の補助ファイルがすべて保存できなくても、理由を記した警告付き完了としてレビューできる。report 自体を保存できない場合は実行失敗とする。
5. 複数サイクルの終了条件である「連続2回、Critical / High / Medium（P0–P2）の finding が0件」には、証跡欠落のある警告付き完了を数えず、連続回数をリセットする。候補レビューが可能なことと、この終了条件に数えられることは区別する。
6. `--resume` は、実行状態の記録がない旧版・外部 report も「実行状態不明」と明示して候補レビューに利用できる。正常完了や連続0件の根拠には使わず、既存 report に成功状態を補って書き戻さない。
7. 同じ出力ルート内で Dogfood 試行ごとに保存先を分け、各試行の report と証跡を保持する。ルートの `report.md` は最新試行を示す。再試行前の観測・証跡を最新試行へ混ぜず、browser の profile identity は従来どおり同じ出力ルートから決める。
8. 後続処理の正本は Markdown の `report.md` とし、実行状態と証跡の充足、失敗・警告・未確認範囲を明示する。既存の `### ISSUE-NNN:` finding ブロックを維持し、新しい結果 JSON を正本として追加しない。
9. 終了コードは0を完了、1を実行失敗、2を MV3 再試行可とする。runner は headless で service worker が未登録で、他に実行失敗・終了失敗がなく、report を確定できた場合だけ2を返す。呼出側は2を受けた場合だけ同じ出力ルートで headed を1回実行し、report 内の文言で再試行を決めない。headed でも未登録なら既存の Critical finding として確定し、他に実行失敗がなければ0で候補レビューへ進める。

## Module と interface

既存 runner の CLI を外部 seam にする。Dogfood 実行結果を扱う module は runner の implementation 内で、観測の保持、証跡の収集結果、終了処理後の report 確定と終了コードの導出を所有する。Web / MV3 / annotation の caller に結果の照合手順を分散させず、この interface の depth によって共通の leverage と locality を得る。

公開する情報は実行状態、対象で観測された finding、証跡の取得状況を区別する。画像・trace の収集失敗や runner の起動・終了失敗を、対象アプリの finding として自動で Issue 候補にしない。WSL2 の video のように対応しない収集項目は対象外であり、収集失敗や警告として連続0件を妨げない。

後続のレビューは report を読み、通常の新規実行では終了コード0のときだけ自動で進む。明示的な `--resume` は保存済みの観測をレビューする操作であり、新しい検査やサイクルを実行したことにはならない。

## 試行と証跡の保存

試行別ディレクトリには report とその試行の画像、trace、console/network、対応する video、annotation の応答・PNG・snapshot をまとめる。ルートの report と試行別の report は同じ Dogfood 実行結果から生成し、それぞれの report を含むディレクトリを基準に証跡パスを表す。ルートからの通常レビューと、過去の試行を指定する `--resume` のどちらでも同じ finding ブロックを読めるようにする。

Evidence に載せるのは、その試行で取得に成功し、保存を確認できたファイルだけとする。試行別ディレクトリがあっても予定パスの生成だけで取得成功にはせず、失敗理由は証跡の参照と分けて report に記録する。過去の動画を含むルート全体の走査や、固定名の旧ファイルの存在だけで今回の証跡を認定する方式は採用しない。

試行開始時に未完了と分かる report を用意し、前回の完了 report を今回の成功として使わない。捕捉できる実行失敗では収集済みの観測を保持して終了処理を試み、その結果も含めて report を確定する。annotation の応答を取得した後に detach が失敗した場合も、得られた応答と読み取れた finding を保持する。

report の書込み途中の内容を完了状態として公開しない。report を保存できなければ非0と stderr で失敗を伝え、候補レビューや MV3 再試行を自動で開始しない。書込み不能や強制終了で最終 report が残せない場合まで、観測の完全保存を保証するものではない。

## 検証と変更範囲

テストは caller と同じ CLI interface を通り、終了コード、report の状態と finding、実際に保存された証跡を照合する。一時 filesystem を使い、実 Playwright と失敗を注入する adapter を内部 seam で使い分ける。render 関数単独のテストを主な保証にせず、既存の annotation・MV3・CDP の成功経路も維持する。

- 正常完了、navigation finding、画像・trace の欠落、補助ファイルがすべて欠落した場合の0終了と report の整合。
- 起動・annotation・終了失敗、主処理と終了処理の両方の失敗、report 保存失敗の非0終了と観測・診断の保持。
- headless の MV3 未登録だけが2を返し、終了失敗を伴う場合や headed の実行では再試行を要求しないこと。
- 同じ出力ルートでの再試行に古い画像・trace・動画が混ざらず、過去の試行も正しい相対パスでレビューできること。
- 警告・失敗・状態不明を連続0件へ数えないことと、旧版・外部 report を読み取り専用でレビューできること。

実装対象は runner と必要な内部 module、`dogfood-to-issues` の呼出し・再開・連続回数の契約、関連する証跡・検証文書とテストに限る。Managed Chrome 所有権の module は結果を受け取る依存として維持する。既知の screenshot timeout や Dashboard 起動失敗そのものの修復は別の問題として扱い、本変更の効果はその失敗を正確に記録できることとする。

## Consequences

証跡の取得を必須にして候補レビューを一律に止める案は、既に記録された観測まで利用できなくなるため採用しない。一方、警告付き完了を連続0件に数える案は採用せず、証跡欠落が続く間は複数サイクルの終了条件を満たせないことを受け入れる。失敗した実行から自動でレビューへ進む案も採用せず、明示的な再開で失敗状態を認識したうえで利用する。

試行別の保存は固定パスの上書きよりディスクを使うが、再試行前の監査記録と今回の証跡を区別できる。保存先の変更に合わせて smoke test と証跡パスの期待値を更新する。外部の旧 report は変換せず、既存の読み取り契約で状態不明として扱う。

[ADR-0038](0038-keep-wsl2-browser-free.md) の証跡収集対象と WSL2 の video-free 契約は維持し、収集に失敗した実行の報告・レビュー条件を本決定で明確にする。正常系の実機検証で取得成功を確認する責務は、警告付き完了の導入によって省略しない。Managed Chrome の所有権と復旧条件は [ADR-0047](0047-centralize-managed-chrome-ownership.md) を維持する。

関連: [CONTEXT.md](../../CONTEXT.md) / [Dogfood runner](../../local-skills/dogfood-to-issues/references/playwright-dogfood-runner.mjs) / [Report Parsing](../../local-skills/dogfood-to-issues/references/report-parsing.md)
