{
  callPackage,
  inputs,
  lib,
  python3,
}:

let
  minFastMcp = "3.2.4";
  minTreeSitterLanguagePack = "0.9.0";

  # The shared nixpkgs pin still has FastMCP 3.2.3, below CRG's declared
  # runtime floor. Reuse the newer package definitions already pinned as a
  # source-only input instead of moving the shared package set.
  python = python3.override {
    self = python;
    packageOverrides = final: _prev: {
      fastmcp = final.callPackage (
        inputs.nixpkgs-ai-sources + "/pkgs/development/python-modules/fastmcp/default.nix"
      ) { };
      fastmcp-slim = final.callPackage (
        inputs.nixpkgs-ai-sources + "/pkgs/development/python-modules/fastmcp-slim/default.nix"
      ) { };
      tree-sitter-language-pack = final.callPackage ./tree-sitter-language-pack-0_13.nix { };
    };
  };

  upstream = callPackage (inputs.llm-agents.outPath + "/packages/code-review-graph/package.nix") {
    python3 = python;
  };
in
assert lib.assertMsg (lib.versionAtLeast python.pkgs.fastmcp.version minFastMcp) ''
  code-review-graph requires FastMCP ${minFastMcp} or newer, but the selected
  Python package set provides ${python.pkgs.fastmcp.version}.
'';
assert lib.assertMsg
  (
    lib.versionAtLeast python.pkgs.tree-sitter-language-pack.version minTreeSitterLanguagePack
    && lib.versionOlder python.pkgs.tree-sitter-language-pack.version "1"
  )
  ''
    code-review-graph requires tree-sitter-language-pack >=${minTreeSitterLanguagePack},<1,
    but the selected Python package set provides ${python.pkgs.tree-sitter-language-pack.version}.
  '';
upstream.overridePythonAttrs (old: {
  # llm-agents creates a nested Python package set to disable FastMCP checks.
  # Replace its runtime inputs with the corrected package set above so the
  # shared-nixpkgs FastMCP and parser bundle do not leak back into the closure.
  build-system = [ python.pkgs.hatchling ];
  dependencies = with python.pkgs; [
    mcp
    fastmcp
    tree-sitter
    tree-sitter-language-pack
    networkx
    watchdog
  ];

  postPatch = ''
    substituteInPlace code_review_graph/parser.py \
      --replace-fail 'sys.executable, "-I"' \
        '"${python.withPackages (ps: [ ps.tree-sitter-language-pack ])}/bin/python", "-I"'
  '';

  passthru = (old.passthru or { }) // {
    fastmcpVersion = python.pkgs.fastmcp.version;
    treeSitterLanguagePackVersion = python.pkgs.tree-sitter-language-pack.version;
  };

  meta = old.meta // {
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
