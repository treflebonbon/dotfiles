{
  fetchurl,
  stdenv,
  makeWrapper,
}:

# numtide/llm-agents.nix dropped x86_64-darwin packaging for claude-code in
# 718f56b955bb (2026-07-21, "Drop x86_64-darwin support"), so llm.claude-code
# throws "Unsupported system: x86_64-darwin" when built on Intel Mac. Anthropic
# itself still ships a darwin-x64 build at every release (verified by hand for
# each version below via HTTP HEAD/GET against the URL template below), so this
# package restores it locally instead of dropping Intel Mac support.
#
# Keep `version` equal to `llm.claude-code.version` at the current llm-agents pin, not
# to minClaudeCode in ../modules/ai.nix. The floor only moves when a release earns it,
# so tying this file to the floor lets a pin bump raise claude-code on the other three
# systems while x86_64-darwin silently stays behind — the assert still passes.
# Whenever the pin changes claude-code's version, update `version` here and recompute:
#   curl -fsSL "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/<version>/darwin-x64/claude" | sha256sum
#   nix hash convert --hash-algo sha256 --to sri <hex digest>
let
  version = "2.1.220";
  hash = "sha256-3Ke+CqfT2SSDbUQODG2OPUfvPI5h+lgJtUuQFxcM4vM=";
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/darwin-x64/claude";
    inherit hash;
  };

  dontUnpack = true;
  dontStrip = true; # do not mess with the bun runtime

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/claude
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/claude \
      --argv0 claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default DISABLE_NON_ESSENTIAL_MODEL_CALLS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1
  '';

  # Bun links against /usr/lib/libicucore.A.dylib, which the Nix macOS sandbox
  # blocks access to (see llm.claude-code's own package.nix for the same note).
  __noChroot = true;

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster (local x86_64-darwin restoration)";
    homepage = "https://claude.ai/code";
    changelog = "https://github.com/anthropics/claude-code/releases";
    mainProgram = "claude";
    platforms = [ "x86_64-darwin" ];
  };
}
