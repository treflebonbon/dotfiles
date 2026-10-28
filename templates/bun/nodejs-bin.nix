{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  stdenvNoCC,
}:

let
  releases = {
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-bBcqmrZxj3uAH7WnvUhq8u5eMnWAhqBLhPzOKqdwleY=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-26v3ocv5R+YFn/rSwnuABB25feoeVTtir97n8T/KM24=";
    };
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-ZUunneYVVkfiIyGTK0Xyocy3BZdswzfJuOJ4vrCFpig=";
    };
  };
  release = releases.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "nodejs";
  version = "24.22.1";
  # Linux の replaceDirectDependencies が同長の store 名を必要とする。
  name = "nodejs-slim-${finalAttrs.version}";

  src = fetchurl {
    url = "https://nodejs.org/dist/v${finalAttrs.version}/node-v${finalAttrs.version}-${release.platform}.tar.xz";
    inherit (release) hash;
  };

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ stdenv.cc.cc.lib ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out/"
    PATH="$out/bin:$PATH" patchShebangs "$out/lib/node_modules"
    runHook postInstall
  '';

  meta = {
    description = "Official Node.js release binary with bundled Brotli security fixes";
    homepage = "https://nodejs.org";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    license = lib.licenses.mit;
    mainProgram = "node";
    platforms = builtins.attrNames releases;
  };
})
