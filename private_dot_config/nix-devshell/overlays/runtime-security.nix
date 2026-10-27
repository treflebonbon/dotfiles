{ nixpkgs, system }:

let
  patched = import nixpkgs { inherit system; };
in
final: prev:
let
  buildNpmPackage = prev.buildNpmPackage.override { nodejs = patched.nodejs_24; };
  # shortcut: Linux の同じ Node.js 24 ABI・同長の store 名だけ置換し、共有 channel の修正後に通常の package に戻す。
  rewrap =
    package:
    if prev.stdenv.isDarwin then
      package.override { nodejs-slim = patched.nodejs-slim_24; }
    else
      (prev.replaceDirectDependencies {
        drv = package;
        replacements = [
          {
            oldDependency = prev.nodejs-slim;
            newDependency = patched.nodejs-slim_24;
          }
        ];
      }).overrideAttrs
        (_: {
          inherit (package) pname version meta;
        });
in
{
  typescript = prev.typescript.override { inherit buildNpmPackage; };
  typescript-language-server = prev.typescript-language-server.override {
    nodejs = patched.nodejs_24;
    typescript = final.typescript;
  };
  oxfmt = rewrap prev.oxfmt;
  oxlint = rewrap prev.oxlint;
  markdownlint-cli2 = prev.markdownlint-cli2.override { inherit buildNpmPackage; };
  marp-cli = prev.marp-cli.override {
    inherit buildNpmPackage;
    nodejs = patched.nodejs_24;
  };
}
