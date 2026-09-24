// S-4 model.mjs doesn't export functions (no export statement) - inline copy check.
import fs from 'node:fs';
const src = fs.readFileSync('/tmp/nix-shell.1IE6Qp/nix-shell.nIPVB2/nix-shell.lisrE2/nix-shell.lLt6rM/claude-1000/-home-ubuntu-ghq-github-com-treflebonbon-dotfiles/0df31814-6774-43dc-9854-523dea1cded4/scratchpad/ab/blind/S-4/model.mjs', 'utf8');
console.log(src.includes('export'));
