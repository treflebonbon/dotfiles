import path from "node:path";

import { Project, SyntaxKind } from "ts-morph";

const [root, config, ...files] = process.argv.slice(2);
const project = new Project({ tsConfigFilePath: config });
const interesting = new Set([
  SyntaxKind.CallExpression,
  SyntaxKind.ReturnStatement,
  SyntaxKind.IfStatement,
  SyntaxKind.ConditionalExpression,
  SyntaxKind.YieldExpression,
  SyntaxKind.ThrowStatement,
  SyntaxKind.ArrowFunction,
  SyntaxKind.FunctionDeclaration,
  SyntaxKind.FunctionExpression,
]);
const nodes = [];
for (const file of files) {
  const source =
    project.getSourceFile(path.resolve(root, file)) ??
    project.addSourceFileAtPath(path.resolve(root, file));
  for (const node of source
    .getDescendants()
    .filter((n) => interesting.has(n.getKind()))) {
    const record = {
      end: node.getEndLineNumber(),
      kind: node.getKindName(),
      path: file,
      start: node.getStartLineNumber(),
      text: node.getText().slice(0, 180),
    };
    try {
      const type = node.getType();
      record.type =
        type.isAny() || type.isUnknown()
          ? null
          : type.getText(node).slice(0, 600);
      if (node.getKind() === SyntaxKind.CallExpression) {
        const expression = node.getExpression();
        let symbol = expression.getSymbol();
        if (symbol?.isAlias()) {
          symbol = symbol.getAliasedSymbol();
        }
        record.declarations = (symbol?.getDeclarations() ?? []).map((d) => ({
          path: path.relative(root, d.getSourceFile().getFilePath()),
          start: d.getStartLineNumber(),
        }));
        record.returnType = node.getReturnType().getText(node).slice(0, 600);
      }
    } catch (error) {
      record.unresolved = String(error);
    }
    nodes.push(record);
  }
}
const diagnostics = project.getPreEmitDiagnostics().map((d) => ({
  code: d.getCode(),
  message:
    typeof d.getMessageText() === "string"
      ? d.getMessageText()
      : d.getMessageText().getMessageText(),
  path: d.getSourceFile()
    ? path.relative(root, d.getSourceFile().getFilePath())
    : null,
  start: d.getStart(),
}));
process.stdout.write(JSON.stringify({ diagnostics, nodes }));
