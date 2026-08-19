{
  lib,
  stdenvNoCC,
  xdg-utils,
}:

stdenvNoCC.mkDerivation {
  pname = "wsl-xdg-open";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/wsl-xdg-open"
    cp ${./wsl-xdg-open.sh} "$out/bin/xdg-open"
    cp ${./wsl-open-url.ps1} "$out/share/wsl-xdg-open/open-url.ps1"

    substituteInPlace "$out/bin/xdg-open" \
      --replace-fail '@xdgOpen@' '${xdg-utils}/bin/xdg-open' \
      --replace-fail '@powershell@' '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' \
      --replace-fail '@windowsScript@' "$out/share/wsl-xdg-open/open-url.ps1"
    chmod +x "$out/bin/xdg-open"

    runHook postInstall
  '';

  meta = {
    description = "WSL-aware xdg-open routing HTTP(S) URLs to the Windows default handler";
    license = lib.licenses.mit;
    mainProgram = "xdg-open";
    platforms = lib.platforms.linux;
  };
}
