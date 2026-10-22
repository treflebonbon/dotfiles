# Coding standards

`code-review` の Standards 軸が読む、機械的な check にできない判断基準。固定の構文パターンは lint・hook・Bats に置き、ここへは書かない。

- 診断用に足した失敗経路（エラー時の代替出力、`-ErrorAction SilentlyContinue` など）には、その経路を通す fixture と、経路を外すと落ちるテストを付ける。
- command line や path を正規表現で解析するときは、値だけを引用した形、引数全体を引用した形、空白を含む値、引用のない値の fixture を含める。
- 待ち受けや対象範囲を絞るフィルタは、同じ対象を扱う既存の実装と条件（address、port 範囲）を揃えるか、揃えない理由をコメントに書く。
