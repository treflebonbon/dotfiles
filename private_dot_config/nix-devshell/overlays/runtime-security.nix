final: prev:
let
  nodejs = prev.callPackage ../packages/nodejs-bin.nix { };
  buildNpmPackage = prev.buildNpmPackage.override { inherit nodejs; };
  # shortcut: Linux の同じ Node.js 24 ABI・同長の store 名だけ置換し、共有 channel の修正版と cache 収録を確認後に戻す。
  rewrap =
    package:
    if prev.stdenv.hostPlatform.isDarwin then
      package.override { nodejs-slim = nodejs; }
    else
      (prev.replaceDirectDependencies {
        drv = package;
        replacements = [
          {
            oldDependency = prev.nodejs-slim;
            newDependency = nodejs;
          }
        ];
      }).overrideAttrs
        (_: {
          inherit (package) pname version meta;
        });
in
{
  nodejs-bin = nodejs;
  typescript = prev.typescript.override { inherit buildNpmPackage; };
  typescript-language-server = prev.typescript-language-server.override {
    inherit nodejs;
    typescript = final.typescript;
  };
  oxfmt = rewrap prev.oxfmt;
  oxlint = rewrap prev.oxlint;
  markdownlint-cli2 = prev.markdownlint-cli2.override { inherit buildNpmPackage; };
  marp-cli = prev.marp-cli.override {
    inherit buildNpmPackage nodejs;
  };
}
