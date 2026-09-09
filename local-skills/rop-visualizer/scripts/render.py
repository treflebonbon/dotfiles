#!/usr/bin/env python3
"""Build a standalone flowchart HTML from a source-backed model and Mermaid SVG."""

import argparse
import datetime
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.min.js"
LANES = ("success", "error", "outside")
SVG_NS = "http://www.w3.org/2000/svg"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_model(path, repo):
    model = json.loads(path.read_text())
    for key in ("title", "entry", "summary", "start"):
        require(isinstance(model.get(key), str) and model[key], f"{key}: nonempty string required")
    nodes = model.get("nodes", [])
    require(isinstance(nodes, list) and nodes, "nodes: nonempty list required")
    ids = set()
    for node in nodes:
        node_id = node.get("id", "")
        require(re.fullmatch(r"[A-Z][A-Z0-9_]*", node_id), f"invalid node id: {node_id}")
        require(node_id not in ids, f"duplicate node: {node_id}")
        ids.add(node_id)
        require(node.get("lane") in LANES, f"{node_id}: invalid lane")
        for key in ("label", "summary"):
            require(isinstance(node.get(key), str) and node[key], f"{node_id}: {key} required")
        require(node.get("kind") in ("work", "recover", "bypass", "terminal", "boundary"), f"{node_id}: invalid kind")
        require(isinstance(node.get("notes", []), list) and all(isinstance(n, str) for n in node.get("notes", [])), f"{node_id}: notes must be strings")
        source = node.get("source")
        if source:
            file = (repo / source["path"]).resolve()
            require(not Path(source["path"]).is_absolute() and file.is_relative_to(repo), f"{node_id}: source must stay inside repo")
            content = file.read_text()
            lines = content.splitlines()
            start, end = source["start"], source.get("end", source["start"])
            require(type(start) is int and type(end) is int and 1 <= start <= end <= len(lines), f"{node_id}: invalid source range")
            node["excerpt"] = "\n".join(lines[start - 1:end])
            node["source_label"] = f"{source['path']}:{start}-{end}"
            node["source_sha256"] = hashlib.sha256(content.encode()).hexdigest()
        else:
            require(node["kind"] in ("bypass", "terminal"), f"{node_id}: source required for a real operation/boundary")
    require(model["start"] in ids, "start must name a node")
    edges = model.get("edges", [])
    require(isinstance(edges, list) and edges, "edges required")
    pairs = set()
    for edge in edges:
        pair = (edge.get("from"), edge.get("to"))
        require(all(n in ids for n in pair), f"unknown edge endpoint: {pair}")
        require(pair not in pairs, f"parallel edges require distinct junction nodes: {pair}")
        pairs.add(pair)
        require(isinstance(edge.get("label", ""), str), "edge label must be a string")
    paths = model.get("paths", [])
    require(isinstance(paths, list) and paths, "at least one source-supported path required")
    by_id = {n["id"]: n for n in nodes}
    for path_model in paths:
        require(isinstance(path_model.get("label"), str) and path_model["label"], "path label required")
        cursor = model["start"]
        require(path_model.get("edges"), "path edges required")
        for index in path_model["edges"]:
            require(type(index) is int and 0 <= index < len(edges), "invalid path edge index")
            edge = edges[index]
            require(edge["from"] == cursor, f"disconnected path {path_model['label']} at edge {index}")
            cursor = edge["to"]
        require(by_id[cursor]["kind"] in ("terminal", "boundary"), f"path {path_model['label']} does not end at a terminal/boundary")
    require(isinstance(model.get("limitations", []), list) and all(isinstance(x, str) for x in model.get("limitations", [])), "limitations must be strings")
    model["generated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    return model


def mermaid_label(value):
    value = " ".join(value.splitlines())
    for char in ('&', '"', '<', '>'):
        value = value.replace(char, f"#{ord(char)};")
    return value


def diagram(model):
    lines = ["flowchart TB"]
    for node in model["nodes"]:
        lines.append(f'  {node["id"]}["{mermaid_label(node["label"])}"]')
    for index, edge in enumerate(model["edges"]):
        label = edge.get("label", "")
        if label:
            lines.append(f'  %% {edge["from"]} to {edge["to"]}: {mermaid_label(label)}')
        lines.append(f'  {edge["from"]} E{index}@--> {edge["to"]}')
    colors = {"success": "#edf7f1,stroke:#257153,color:#173f30", "error": "#fceeee,stroke:#ac4545,color:#752c2c", "outside": "#f2f0fa,stroke:#71618c,color:#443454", "recover": "#fff5dd,stroke:#9a6b1d,color:#6c4812"}
    for key, color in colors.items():
        lines.append(f"  classDef {key} fill:{color}")
    lines.append("  classDef bypass stroke-dasharray:4 3")
    for node in model["nodes"]:
        color = "recover" if node["kind"] == "recover" else node["lane"]
        lines.append(f'  class {node["id"]} {color}')
        if node["kind"] == "bypass":
            lines.append(f'  class {node["id"]} bypass')
    return "\n".join(lines) + "\n"


def render_script(source):
    return """async page => {
  const tab = await page.context().newPage();
  try {
    await tab.bringToFront();
    await tab.goto('about:blank');
    await tab.addScriptTag({url: MERMAID_URL});
    return await tab.evaluate(async source => {
      mermaid.initialize({startOnLoad:false, securityLevel:'strict', htmlLabels:false,
        flowchart:{nodeSpacing:40, rankSpacing:48, curve:'linear'},
        theme:'base', themeVariables:{fontFamily:'system-ui, sans-serif', fontSize:'16px'}});
      const result = await mermaid.render('rop-flow', source);
      return {svg: result.svg};
    }, MERMAID_SOURCE);
  } finally { await tab.close(); }
}
""".replace("MERMAID_URL", json.dumps(MERMAID_URL)).replace("MERMAID_SOURCE", json.dumps(source))


def prepare_svg(svg, model):
    """Bind model identities without changing Mermaid's shapes or routing."""
    root = ET.fromstring(svg)
    require(root.tag == f"{{{SVG_NS}}}svg" and root.get("id"), "renderer did not return an identified SVG")
    seen = set()
    for element in root.iter():
        tag = element.tag.split("}")[-1]
        require(tag not in ("script", "iframe", "image", "use"), f"unexpected SVG element: {tag}")
        for key, value in element.attrib.items():
            key = key.split("}")[-1]
            require(not key.lower().startswith("on"), "SVG event handler rejected")
            if key in ("href", "src"):
                require(value.startswith("#"), "external SVG resource rejected")
        if element.get("id"):
            require(element.get("id") not in seen, f'duplicate SVG id: {element.get("id")}')
            seen.add(element.get("id"))
    require(not re.search(r"@import|url\(\s*['\"]?(?!#)[^\s)]", svg), "external SVG style resource rejected")
    nodes = [el for el in root.iter() if "node" in el.get("class", "").split()]
    edges = [el for el in root.iter() if "flowchart-link" in el.get("class", "").split()]
    require(len(nodes) == len(model["nodes"]), "Mermaid node count differs from model")
    require(len(edges) == len(model["edges"]), "Mermaid edge count differs from model")
    for node in model["nodes"]:
        pattern = re.escape(f'{root.get("id")}-flowchart-{node["id"]}-') + r"\d+"
        matches = [el for el in nodes if re.fullmatch(pattern, el.get("id", ""))]
        require(len(matches) == 1, f'Mermaid node missing or ambiguous: {node["id"]}')
        matches[0].set("data-node", node["id"])
    for index, edge in enumerate(model["edges"]):
        matches = [el for el in edges if el.tag == f"{{{SVG_NS}}}path" and el.get("data-id") == f"E{index}"]
        require(len(matches) == 1, f"Mermaid edge missing or ambiguous: E{index}")
        matches[0].set("data-edge-index", str(index))
        ET.SubElement(matches[0], f"{{{SVG_NS}}}title").text = edge.get("label", "")
    ET.register_namespace("", SVG_NS)
    return ET.tostring(root, encoding="unicode")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--session", help="existing Playwright CLI session name")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--rendered-json", type=Path, help="reuse a render result instead of opening a tab")
    args = parser.parse_args()
    try:
        require(args.output.suffix == ".html", "output must end in .html")
        require(not args.output.exists(), "output exists; choose a new name or explicitly remove an owned report")
        model = load_model(args.model, args.repo_root.resolve())
        source = diagram(model)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        mmd_path = args.output.with_suffix(".mmd")
        script_path = args.output.with_suffix(".render.js")
        require(not mmd_path.exists() and not script_path.exists(), "output source artifacts already exist; choose a new basename")
        mmd_path.write_text(source)
        script_path.write_text(render_script(source))
        if args.rendered_json:
            result = json.loads(args.rendered_json.read_text())
        else:
            require(args.session and re.fullmatch(r"[a-zA-Z0-9_-]+", args.session), "--session must name an existing Playwright CLI session")
            run = subprocess.run(["playwright-cli", f"-s={args.session}", "--raw", "run-code", f"--filename={script_path.resolve()}"], capture_output=True, text=True, timeout=90)
            require(run.returncode == 0, f"browser rendering failed: {run.stderr or run.stdout}")
            try:
                result = json.loads(run.stdout)
            except json.JSONDecodeError as exc:
                raise ValueError(f"browser did not return render JSON: {run.stdout[:1200]}") from exc
        svg = prepare_svg(result["svg"], model)
        assets = Path(__file__).resolve().parent.parent / "assets"
        template = (assets / "report.html").read_text()
        payload = json.dumps(model, ensure_ascii=False).replace("&", "\\u0026").replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
        replacements = {"__TITLE__": html.escape(model["title"]), "__SVG__": svg,
                        "__MODEL__": payload, "__MERMAID__": html.escape(source),
                        "__APP__": (assets / "report.js").read_text(),
                        "__CSS__": (assets / "report.css").read_text()}
        output = re.sub(r"__(?:TITLE|SVG|MODEL|MERMAID|APP|CSS)__", lambda match: replacements[match.group()], template)
        args.output.write_text(output)
        print(args.output.resolve())
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, ET.ParseError) as exc:
        print(f"rop-visualizer: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
