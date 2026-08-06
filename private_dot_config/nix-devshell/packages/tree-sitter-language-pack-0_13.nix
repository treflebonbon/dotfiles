{
  lib,
  buildPythonPackage,
  fetchPypi,
  pytestCheckHook,
  nix-update-script,

  # build-system
  cython,
  setuptools,
  typing-extensions,

  # dependencies
  tree-sitter,
  tree-sitter-c-sharp,
  tree-sitter-embedded-template,
  tree-sitter-yaml,
}:

# CRG 2.3.7 requires tree-sitter-language-pack >=0.9,<1. Version 0.13.0
# ships the parsers in its source distribution; 1.x is outside CRG's range.
# Keep this definition aligned with Nixpkgs cc53eadb (the 0.13.0 update).
buildPythonPackage rec {
  pname = "tree-sitter-language-pack";
  version = "0.13.0";
  pyproject = true;

  src = fetchPypi {
    pname = "tree_sitter_language_pack";
    inherit version;
    hash = "sha256-AyA0xeJ7H24AcwuefC28ggO0cA0MaB/QGdbe/PYRg+w=";
  };

  # The shared package set has typing-extensions 4.14.1.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail "typing-extensions>=4.15.0" "typing-extensions>=4.14.1"
  '';

  nativeCheckInputs = [ pytestCheckHook ];

  build-system = [
    cython
    setuptools
    typing-extensions
  ];

  dependencies = [
    tree-sitter
    tree-sitter-c-sharp
    tree-sitter-embedded-template
    tree-sitter-yaml
  ];

  pythonRelaxDeps = [
    "tree-sitter"
    "tree-sitter-embedded-template"
    "tree-sitter-yaml"
  ];

  pythonImportsCheck = [
    "tree_sitter_language_pack"
    "tree_sitter_language_pack.bindings"
  ];

  # Import the installed package during checks, not the source tree.
  preCheck = ''
    rm -r tree_sitter_language_pack
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Comprehensive collection of tree-sitter languages";
    homepage = "https://github.com/Goldziher/tree-sitter-language-pack";
    changelog = "https://github.com/Goldziher/tree-sitter-language-pack/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ yzx9 ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
