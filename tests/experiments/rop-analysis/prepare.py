"""Materialize experiment-only projects; retain the original fixtures verbatim."""
import json
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
WORK = REPO / 'tmp/rop-analysis-comparison'


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def prepare():
    old = REPO / 'local-skills/rop-visualizer/evals/fixtures'
    cases = []
    for name, lang, entry in [
        ('effect-checkout', 'ts', 'checkout'), ('rust-checkout', 'rust', 'checkout'),
        ('holdout-local-scope', 'rust', 'charge_invoice'), ('ts-symbols', 'ts', 'checkout'),
        ('rust-symbols', 'rust', 'checkout'),
    ]:
        root = WORK / 'inputs' / name
        root.mkdir(parents=True, exist_ok=True)
        if lang == 'ts':
            write(root / 'package.json', json.dumps({'private': True, 'type': 'module',
                  'dependencies': {'effect': '3.9.2'}}))
            write(root / 'tsconfig.json', json.dumps({'compilerOptions': {'target': 'ES2022',
                  'module': 'NodeNext', 'moduleResolution': 'NodeNext', 'strict': True,
                  'skipLibCheck': True, 'noEmit': True}, 'include': ['src/**/*.ts']}))
            if name == 'ts-symbols':
                write(root / 'src/main.ts', (HERE / 'fixtures/ts-main.ts.fixture').read_text())
                write(root / 'src/operations.ts', (HERE / 'fixtures/ts-operations.ts.fixture').read_text())
                write(root / 'src/exports.ts', "export { Effect as Fx } from 'effect';\n")
            else:
                write(root / 'src/main.ts', (old / 'effect-checkout.ts.fixture').read_text())
            subprocess.run(['npm', 'install', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=root, check=True)
            files = sorted(str(p.relative_to(root)) for p in (root / 'src').glob('*.ts'))
            source = 'src/main.ts'
        else:
            write(root / 'Cargo.toml', f'[package]\nname = "{name}"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"\n')
            source = 'src/lib.rs'
            if name == 'rust-symbols':
                write(root / source, (HERE / 'fixtures/rust-lib.rs.fixture').read_text())
                write(root / 'src/parser.rs', (HERE / 'fixtures/rust-parser.rs.fixture').read_text())
            elif name == 'holdout-local-scope':
                # A declaration-only extern symbol supplies a signature, not a fabricated body.
                source = 'src/invoice.rs'
                write(root / source, (old / f'{name}.rs.fixture').read_text())
                write(root / 'src/lib.rs', 'include!("invoice.rs");\nmod gateway {\n'
                      '    extern "Rust" { #[link_name = "quote_tax"] fn external_quote_tax(country: &str) -> Result<u8, super::InvoiceError>; }\n'
                      '    pub(super) fn quote_tax(country: &str) -> Result<u8, super::InvoiceError> { unsafe { external_quote_tax(country) } }\n}\n')
            else:
                write(root / source, (old / f'{name}.rs.fixture').read_text())
            files = sorted(str(p.relative_to(root)) for p in (root / 'src').glob('*.rs'))
        cases.append({'id': name, 'language': lang, 'root': str(root), 'entry': f'{source}:{entry}',
                      'files': files, 'config': 'tsconfig.json' if lang == 'ts' else 'Cargo.toml',
                      'scope': 'Entry and the provided local callees. An extern declaration is an unknown implementation boundary.'})
    write(WORK / 'cases-local.json', json.dumps(cases, indent=2))


if __name__ == '__main__':
    prepare()
