{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs,
}:

buildNpmPackage {
  pname = "cloudflare-cli";
  version = "1.0.0-beta.24";

  src = ./cloudflare-cli;
  npmDepsHash = "sha256-CiniMT0yjNwUBNPQEp4CNA/oDba6gcG7pXSYmRV6nAg=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
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
