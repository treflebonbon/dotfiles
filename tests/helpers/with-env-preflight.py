"""Exercise this revision's public Nix app through the real isolated raw entry."""

import os
from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parents[2]
fixture = Path(tempfile.mkdtemp(prefix="with-env-271-preflight-", dir="/tmp"))
environment = os.environ | {
    "PROJECT_ROOT": str(source),
    "BATS_TEST_TMPDIR": str(fixture),
}
script = r"""
set -eu
source "$PROJECT_ROOT/tests/helpers/raw-codex.bash"
raw_fixture
mkdir -p "$RAW_BASE/work/dotfiles/private_dot_local/bin"
cp "$PROJECT_ROOT/flake.nix" "$PROJECT_ROOT/flake.lock" "$RAW_BASE/work/dotfiles/"
cp "$PROJECT_ROOT/private_dot_local/bin/executable_devshell-env" "$RAW_BASE/work/dotfiles/private_dot_local/bin/"
cat > "$RAW_BASE/work/flake.nix" <<'NIX'
{
  inputs.dotfiles.url = "path:./dotfiles";
  inputs.nixpkgs.follows = "dotfiles/nixpkgs";
  outputs = { nixpkgs, dotfiles, ... }: {
    devShells.x86_64-linux.default = let pkgs = import nixpkgs { system = "x86_64-linux"; }; in pkgs.mkShell {
      packages = [ dotfiles.packages.x86_64-linux.with-env pkgs.hello ];
      RAW_APP = "${dotfiles.packages.x86_64-linux.with-env}/bin/with-env";
      PROJECT_257 = "prepared";
      shellHook = ''
        test -z "''${RAW_DUMMY_SECRET+x}"
        test ! -e .env
        printf 'hook\n' >> hook-calls
        export HOOK_257=ready
      '';
    };
  };
}
NIX
cat > "$RAW_BASE/work/task.sh" <<'TASK'
set -eu
test "$PROJECT_257/$HOOK_257" = prepared/ready
test -z "${RAW_DUMMY_SECRET+x}"
test -z "$(cat .env 2>/dev/null || true)"
test "$(wc -l < hook-calls)" -eq 1
test ! -e envrc-executed
set +e
"$RAW_APP" --prepared -- bash -c 'test "$1/$2" = "two words/"; test -z "${RAW_DUMMY_SECRET+x}"; hello; exit 23' _ 'two words' ''
status=$?
set -e
test "$status" -eq 23
printf public > app-result.txt
git add app-result.txt
git commit -qm 'test: public app inside isolation'
printf PUBLIC_APP_ISOLATED_OK
TASK
printf 'touch envrc-executed\n' > "$RAW_BASE/work/.envrc"
raw_admit flake.nix task.sh .envrc dotfiles/flake.nix dotfiles/flake.lock dotfiles/private_dot_local/bin/executable_devshell-env
export RAW_DUMMY_SECRET=dummy-inherited-public-app
raw_run sandbox -- bash task.sh
[ "$(git -C "$RAW_BASE/work" log -1 --format=%s)" = 'test: public app inside isolation' ]
[ "$(cat "$RAW_BASE/work/.env")" = RAW_DUMMY_SECRET=dummy-root-secret ]
raw_cli untrust
if raw_run sandbox -- true; then exit 1; fi
printf '\ntrusted: exit=0; revoked: rejected\n'
"""
result = subprocess.run(
    ["bash", "-c", script], env=environment, text=True, capture_output=True
)
(fixture / "preflight.log").write_text(result.stdout + result.stderr)
if result.returncode:
    print(result.stdout + result.stderr)
print(f"Evidence: {fixture}")
raise SystemExit(result.returncode)
