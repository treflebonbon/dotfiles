import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True

renderer_path = Path(sys.argv.pop(1)).resolve()
sys.path.insert(0, str(renderer_path.parent))
spec = importlib.util.spec_from_file_location("rop_renderer", renderer_path)
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


class RendererContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "source.ts").write_text('const input = "</script><img src=x>";\nreturn validate(input);\n')
        self.model = {
            "title": "契約確認", "entry": "source.ts:run", "summary": "検証する", "start": "V",
            "nodes": [
                {"id": "V", "label": '検証 "値"', "lane": "success", "kind": "work", "summary": "検証成功は OK、失敗は ERR", "source": {"path": "source.ts", "start": 1, "end": 2}},
                {"id": "OK", "label": "成功", "lane": "success", "kind": "terminal", "summary": "成功終了"},
                {"id": "ERR", "label": "失敗", "lane": "error", "kind": "terminal", "summary": "失敗終了"},
            ],
            "edges": [{"from": "V", "to": "OK"}, {"from": "V", "to": "ERR"}],
            "paths": [{"label": "成功", "edges": [0]}, {"label": "失敗", "edges": [1]}],
        }
        self.svg = ('<svg xmlns="http://www.w3.org/2000/svg" id="rop-flow" viewBox="0 0 400 300">'
                    '<g class="node" id="rop-flow-flowchart-V-0" transform="translate(100,25)"/>'
                    '<g class="node" id="rop-flow-flowchart-OK-1"/>'
                    '<g class="node" id="rop-flow-flowchart-ERR-2"/>'
                    '<path class="flowchart-link" data-id="E0" d="M100,50 L100,80"/>'
                    '<path class="flowchart-link" data-id="E1" d="M150,50 L250,80"/></svg>')

    def load(self, model=None):
        path = self.root / "flow.json"
        path.write_text(json.dumps(model or self.model))
        return renderer.load_model(path, self.root)

    def test_source_excerpt_is_read_from_real_lines(self):
        model = self.load()
        self.assertEqual(model["nodes"][0]["excerpt"], (self.root / "source.ts").read_text().rstrip())
        self.assertEqual(len(model["nodes"][0]["source_sha256"]), 64)

    def test_rejects_out_of_repo_source_and_invalid_lines(self):
        for source in ({"path": "../other.ts", "start": 1}, {"path": "source.ts", "start": 1, "end": 3}):
            with self.subTest(source=source):
                model = copy.deepcopy(self.model)
                model["nodes"][0]["source"] = source
                with self.assertRaises((ValueError, OSError)):
                    self.load(model)

    def test_rejects_disconnected_or_nonterminal_paths(self):
        for edges in ([0, 1], [], [3]):
            with self.subTest(edges=edges):
                model = copy.deepcopy(self.model)
                model["paths"][0]["edges"] = edges
                with self.assertRaises(ValueError):
                    self.load(model)

        model = copy.deepcopy(self.model)
        model["nodes"][1]["kind"] = "work"
        model["nodes"][1]["source"] = {"path": "source.ts", "start": 1}
        with self.assertRaisesRegex(ValueError, "does not end at a terminal"):
            self.load(model)

    def test_rejects_duplicate_nodes_and_parallel_edges(self):
        model = copy.deepcopy(self.model)
        model["nodes"][1]["id"] = "V"
        with self.assertRaises(ValueError):
            self.load(model)
        model = copy.deepcopy(self.model)
        model["edges"].append(dict(model["edges"][0]))
        with self.assertRaises(ValueError):
            self.load(model)

    def test_mermaid_preserves_branches_and_escapes_labels(self):
        source = renderer.diagram(self.load())
        self.assertTrue(source.startswith("flowchart TB\n"))
        self.assertIn('V["検証 #34;値#34;"]', source)
        self.assertIn("V E0@--> OK", source)
        self.assertIn("V E1@--> ERR", source)

    def test_svg_must_match_model_and_contain_no_external_content(self):
        svg = self.svg
        renderer.prepare_svg(svg, self.load())
        for bad in (svg.replace('id="rop-flow-flowchart-V-0"', 'id="missing"'),
                    svg.replace('data-id="E1"', 'data-id="E0"'),
                    svg.replace('data-id="E1"', 'data-id="E3"'),
                    svg.replace('</svg>', '<g id="rop-flow"/></svg>'),
                    svg.replace('</svg>', '<g class="node" id="rop-flow-flowchart-V-9"/></svg>'),
                    svg.replace('</svg>', '<script>alert(1)</script></svg>'),
                    svg.replace('</svg>', '<a href="https://example.com"/></svg>'),
                    svg.replace('</svg>', '<g onclick="alert(1)"/></svg>')):
            with self.subTest(svg=bad):
                with self.assertRaises(ValueError):
                    renderer.prepare_svg(bad, self.load())

    def test_binding_preserves_mermaid_geometry_and_edge_identity(self):
        model = self.load()
        model["edges"][1]["label"] = "失敗 < 入力"
        original = ET.fromstring(self.svg)
        bound = ET.fromstring(renderer.prepare_svg(self.svg, model))
        ns = {"s": "http://www.w3.org/2000/svg"}
        self.assertEqual(bound.attrib, original.attrib)
        for before, after in zip(original.findall('s:g', ns), bound.findall('s:g', ns)):
            self.assertEqual({k: after.get(k) for k in before.attrib}, before.attrib)
        self.assertEqual([el.get("data-node") for el in bound.findall('s:g', ns)], ["V", "OK", "ERR"])
        for index, (before, after) in enumerate(zip(original.findall('s:path', ns), bound.findall('s:path', ns))):
            self.assertEqual(after.get("d"), before.get("d"))
            self.assertEqual(after.get("data-edge-index"), str(index))
        self.assertEqual(bound.findall('s:path', ns)[1].find('s:title', ns).text, "失敗 < 入力")


if __name__ == "__main__":
    unittest.main()
