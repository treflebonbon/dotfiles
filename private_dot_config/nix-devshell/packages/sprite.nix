{
  autoPatchelfHook,
  fetchurl,
  installShellFiles,
  lib,
  stdenvNoCC,
}:

let
  inherit (stdenvNoCC.hostPlatform) isLinux system;

  releases = {
    x86_64-linux = {
      asset = "sprite-linux-amd64.tar.gz";
      hash = "sha256-UlgRQoNfiFTSIgaj67qcNriXEcorM0XPJC1Doy3HnP4=";
    };
    aarch64-linux = {
      asset = "sprite-linux-arm64.tar.gz";
      hash = "sha256-taj5QskS1bRgv0QFh9nu/IXUvzJCXGxiDP6lYPaL5tU=";
    };
    aarch64-darwin = {
      asset = "sprite-darwin-arm64.tar.gz";
      hash = "sha256-HoYKvupDS4Lak5ce07yZ8VkgafzxlSI0YNb6pg+xRTg=";
    };
  };

  release = releases.${system} or (throw "sprite is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "sprite";
  version = "0.0.1-rc48";

  src = fetchurl {
    url = "https://sprites-binaries.t3.storage.dev/client/v${finalAttrs.version}/${release.asset}";
    inherit (release) hash;
  };

  sourceRoot = ".";
  nativeBuildInputs = [ installShellFiles ] ++ lib.optionals isLinux [ autoPatchelfHook ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 sprite "$out/bin/sprite"
    runHook postInstall
  '';

  # Linux のバイナリは fixupPhase で動的リンカのパスが修正されてから実行できる。
  postPhases = [ "installCompletions" ];
  installCompletions = ''
    export HOME="$TMPDIR"
    "$out/bin/sprite" completion bash > sprite.bash
    "$out/bin/sprite" completion zsh > sprite.zsh
    "$out/bin/sprite" completion fish > sprite.fish
    installShellCompletion --cmd sprite \
      --bash sprite.bash \
      --zsh sprite.zsh \
      --fish sprite.fish
  '';

  meta = {
    description = "Command-line interface for Fly.io Sprites";
    homepage = "https://sprites.dev";
    mainProgram = "sprite";
    platforms = builtins.attrNames releases;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
