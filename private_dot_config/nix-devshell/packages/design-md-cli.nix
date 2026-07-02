{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs,
}:

buildNpmPackage {
  pname = "design-md";
  version = "0.2.0";

  src = ./design-md-cli;

  npmDepsHash = "sha256-gaP7EjUh50DjjmpK1v8uhkzcrXooS+bnQQ0Ybzk11NA=";
  npmFlags = [ "--legacy-peer-deps" ];

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    cli="$out/lib/node_modules/design-md/node_modules/@google/design.md/dist/index.js"

    makeWrapper ${nodejs}/bin/node "$out/bin/design.md" \
      --add-flags "$cli"
    makeWrapper ${nodejs}/bin/node "$out/bin/designmd" \
      --add-flags "$cli"
  '';

  meta = {
    description = "DESIGN.md CLI - lint/diff/export design-system tokens for AI agents";
    homepage = "https://github.com/google-labs-code/design.md";
    license = lib.licenses.asl20;
    mainProgram = "design.md";
    platforms = lib.platforms.unix;
  };
}
