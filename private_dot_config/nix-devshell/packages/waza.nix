{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;

  releases = {
    x86_64-linux = {
      asset = "waza-linux-amd64";
      hash = "sha256-qAE4w9N9SOlH71tBShukZXk1tzNNLOvkfPcdAEaA8lA=";
    };
    aarch64-linux = {
      asset = "waza-linux-arm64";
      hash = "sha256-HPZ4hdfdtgR6rJ2pMsUWnIyJ7qAJJvP+w3Bp4CSeYl0=";
    };
    aarch64-darwin = {
      asset = "waza-darwin-arm64";
      hash = "sha256-9HMuNQph4i9EDd/n/O3C54FmH9fAOc8wBa+QurXVLA8=";
    };
  };

  release = releases.${system} or (throw "waza is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waza";
  version = "0.39.0";

  src = fetchurl {
    url = "https://github.com/microsoft/waza/releases/download/v${finalAttrs.version}/${release.asset}";
    inherit (release) hash;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/waza"
    runHook postInstall
  '';

  meta = {
    description = "AI agent skills evaluation framework";
    homepage = "https://github.com/microsoft/waza";
    license = lib.licenses.mit;
    mainProgram = "waza";
    platforms = builtins.attrNames releases;
  };
})
