use proc_macro2::Span;
use serde_json::{json, Value};
use std::{env, fs};
use syn::{spanned::Spanned, visit::Visit, Expr};

struct Extractor<'a> {
    path: &'a str,
    source: &'a str,
    offsets: Vec<usize>,
    nodes: Vec<Value>,
    scopes: Vec<usize>,
}
impl Extractor<'_> {
    fn offset(&self, line: usize, column: usize) -> usize {
        let base = self.offsets[line - 1];
        let text = self.source[base..].split('\n').next().unwrap_or("");
        base + text.char_indices().nth(column).map_or(text.len(), |(offset, _)| offset)
    }
    fn query(&mut self, id: usize, span: Span) {
        self.nodes[id]["queryLine"] = json!(span.start().line);
        self.nodes[id]["queryColumn"] = json!(span.start().column);
    }
    fn record(&mut self, kind: &str, span: Span) -> usize {
        let start = span.start();
        let end = span.end();
        let lo = self.offset(start.line, start.column);
        let hi = self.offset(end.line, end.column);
        let text: String = self.source.get(lo..hi).unwrap_or("").chars().take(180).collect();
        let id = self.nodes.len();
        self.nodes.push(json!({"path": self.path, "start": start.line, "end": end.line,
            "column": start.column, "kind": kind, "text": text, "scope": self.scopes.last(),
            "type": null}));
        id
    }
}
impl<'ast> Visit<'ast> for Extractor<'_> {
    fn visit_item_fn(&mut self, node: &'ast syn::ItemFn) {
        let id = self.record("function", node.span());
        self.query(id, node.sig.ident.span());
        self.scopes.push(id);
        syn::visit::visit_item_fn(self, node);
        self.scopes.pop();
    }
    fn visit_impl_item_fn(&mut self, node: &'ast syn::ImplItemFn) {
        let id = self.record("method", node.span());
        self.query(id, node.sig.ident.span());
        self.scopes.push(id);
        syn::visit::visit_impl_item_fn(self, node);
        self.scopes.pop();
    }
    fn visit_expr(&mut self, node: &'ast Expr) {
        let kind = match node {
            Expr::Try(_) => "try", Expr::Call(_) => "call", Expr::MethodCall(_) => "method_call",
            Expr::Match(_) => "match", Expr::Return(_) => "return", Expr::If(_) => "if",
            Expr::Closure(_) => "closure", Expr::Async(_) => "async", Expr::Loop(_) => "loop",
            Expr::ForLoop(_) => "for", Expr::While(_) => "while", Expr::Break(_) => "break",
            Expr::Continue(_) => "continue", Expr::Macro(_) => "unexpanded_macro", _ => "",
        };
        let scope = matches!(node, Expr::Closure(_) | Expr::Async(_));
        if !kind.is_empty() {
            let id = self.record(kind, node.span());
            match node {
                Expr::MethodCall(call) => self.query(id, call.method.span()),
                Expr::Call(call) => {
                    if let Expr::Path(path) = call.func.as_ref() {
                        if let Some(segment) = path.path.segments.last() {
                            self.query(id, segment.ident.span());
                        }
                    }
                }
                _ => {}
            }
            if scope { self.scopes.push(id); }
        }
        syn::visit::visit_expr(self, node);
        if scope { self.scopes.pop(); }
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut output = Vec::new();
    for file in env::args().skip(1) {
        let source = fs::read_to_string(&file)?;
        let parsed = syn::parse_file(&source)?;
        let mut offsets = vec![0];
        offsets.extend(source.match_indices('\n').map(|(i, _)| i + 1));
        let mut visitor = Extractor { path: &file, source: &source, offsets, nodes: vec![], scopes: vec![] };
        visitor.visit_file(&parsed);
        output.extend(visitor.nodes);
    }
    println!("{}", json!({"nodes": output, "diagnostics": []}));
    Ok(())
}
