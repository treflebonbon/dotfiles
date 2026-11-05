{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs,
  python3,
}:

buildNpmPackage {
  pname = "cloudflare-cli";
  version = "1.0.0-beta.25";

  src = ./cloudflare-cli;
  npmDepsHash = "sha256-PuCNYhXbteBGnh3+J2Ec728xFVfA7wO9r57UTnCEZBw=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    mkdir -p "$out/bin"
    substitute "$src/cloudflare-inspect.py" "$out/bin/cloudflare-inspect" \
      --replace-fail '#!/usr/bin/env -S python3 -I' '#!${python3}/bin/python3 -I'
    chmod +x "$out/bin/cloudflare-inspect"
    cli="$out/lib/node_modules/dotfiles-cloudflare-cli/node_modules/cf/bin/cf"
    for name in cf cloudflare; do
      makeWrapper ${nodejs}/bin/node "$out/bin/$name" \
        --add-flags "$cli" \
        --set CF_DELEGATION 1 \
        --set CF_SEND_TELEMETRY false
    done
  '';

  meta = {
    description = "Cloudflare official CLI (pinned beta)";
    homepage = "https://developers.cloudflare.com/cf/";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "cf";
    platforms = lib.platforms.unix;
  };
}
