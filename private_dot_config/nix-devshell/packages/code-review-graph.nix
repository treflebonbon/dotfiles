{
  inputs,
  lib,
  system,
}:

let
  minFastMcp = "3.2.4";
  package = inputs.llm-agents.packages.${system}.code-review-graph;
  fastmcp = builtins.head (
    builtins.filter (dependency: (dependency.pname or "") == "fastmcp") package.propagatedBuildInputs
  );
in
assert lib.assertMsg (lib.versionAtLeast fastmcp.version minFastMcp) ''
  code-review-graph は FastMCP ${minFastMcp} 以上が必要ですが、llm-agents の選択版は ${fastmcp.version} です。
'';
package
