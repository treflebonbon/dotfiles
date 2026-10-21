# 同梱した Ultracite presets

この3つの実行時モジュールと型宣言は `ultracite@7.12.4` から byte-for-byte でコピーしています。npm integrity は `sha512-6jVEwaZBaytFm6XRoI3WGS2ZydrkrNvHTD0qTf7983ti2FlEWL1YcxnPaMaYuS6PkXqMhIK2XGr0cbsL4x5pQA==` です。このリポジトリで使う Ultracite の export は `oxlint/core`、`oxfmt`、共有 ignore 一覧だけです。Ultracite CLI とその依存パッケージは使いません。

この package は MIT license を宣言しています。license notice は [LICENSE](LICENSE) に保持しています。notice は upstream の [license.md](https://github.com/haydenbleasel/ultracite/blob/a1da2b95ccfe22fe3bdde0bce777cd6238970fad/license.md) で確認しました。

この snapshot は変更せず保持してください。upstream が preset のみの package または `braces` の修正済み依存経路を公開した時点で見直してください。更新時は対象 export を比較し、root config、lint、format、typecheck、OSV の各確認を再実行してください。upstream の config ファイルは project の lint/format 対象から除外し、pre-commit による書き換えを防いでいます。
