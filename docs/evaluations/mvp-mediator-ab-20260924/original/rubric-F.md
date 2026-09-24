1. [critical] 既存bindingからpending/result/errorを導出し、二重のisSubmitting/reducer/storeや独自runtimeを追加しない。
2. [critical] 新しいMediator class/CoRチェーン/Root再編/操作ID/状態機械を形式的に追加せず、既存の所有者を維持する。
3. tooltipの開閉を局所に保ち、複数Context consumerと既存フォームの入力・形式チェックを維持する。
4. 業務検証をユースケースに残し、表示条件のために再実装しない。Atom採用だけを保証とせず、課題に与えたbindingの確認済み保証を根拠にする。
5. 投稿中表示、完了/失敗表示、tooltip独立性の確認項目を示し、未実行アプリ検査を成功扱いしない。
6. 追加不要なパターンの理由を今回の制約に結び付け、strict Passive Viewのための一律の購読移動や中継専用層を要求しない。
