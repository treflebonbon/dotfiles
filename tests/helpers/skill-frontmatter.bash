# shellcheck shell=bash
# Skill frontmatter parsing helpers for static sanity tests
#
# Bash helpers used by tests/skills.bats to statically inspect
# skills/*/SKILL.md frontmatter without depending on yq.
#
# Portability: awk invocations use only POSIX constructs (no 3-arg match,
# no gensub, no delete-array). Capture-group extraction is done with bash
# built-in regex (BASH_REMATCH) instead of gawk-only 3-arg match().

# Extract raw `allowed-tools:` value from a SKILL.md frontmatter.
# Prints empty string (exit 0) if absent or frontmatter malformed.
skill_allowed_tools_raw() {
    local skill_md="$1"
    awk '
        BEGIN { in_fm = 0; fm_seen = 0 }
        /^---$/ {
            if (fm_seen == 0) { in_fm = 1; fm_seen = 1; next }
            else { exit }
        }
        in_fm && /^allowed-tools:[[:space:]]*/ {
            sub(/^allowed-tools:[[:space:]]*/, "")
            print
            exit
        }
    ' "$skill_md"
}

# Return 0 if allowed-tools key is present in frontmatter, 1 otherwise.
skill_has_allowed_tools() {
    local skill_md="$1"
    awk '
        BEGIN { in_fm = 0; fm_seen = 0; found = 0 }
        /^---$/ {
            if (fm_seen == 0) { in_fm = 1; fm_seen = 1; next }
            else { exit }
        }
        in_fm && /^allowed-tools:[[:space:]]*/ { found = 1; exit }
        END { exit (found ? 0 : 1) }
    ' "$skill_md"
}

# Split comma-separated allowed-tools value into one entry per line.
# Handles values like: `Bash(git:*), Read, Skill(foo), Bash(gh issue view:*)`.
skill_allowed_tools_entries() {
    local raw="$1"
    # Comma outside parentheses is the delimiter. Use a small awk state machine.
    awk -v s="$raw" '
        BEGIN {
            n = length(s); depth = 0; buf = ""
            for (i = 1; i <= n; i++) {
                c = substr(s, i, 1)
                if (c == "(") { depth++; buf = buf c; continue }
                if (c == ")") { depth--; buf = buf c; continue }
                if (c == "," && depth == 0) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", buf)
                    if (buf != "") print buf
                    buf = ""
                    continue
                }
                buf = buf c
            }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", buf)
            if (buf != "") print buf
        }
    '
}

# From an entry like `Bash(git:*)`, `Bash(gh issue view:*)`, `Bash(rm /tmp:*)`
# print the leading command token only (`git`, `gh`, `rm`).
# For non-Bash entries prints nothing.
skill_bash_entry_head() {
    local entry="$1"
    # Match `Bash(<prefix>` where prefix is everything up to the first
    # `:` or `)`. Covers `Bash(git:*)`, `Bash(gh issue view:*)`,
    # `Bash(rm /tmp:*)`, bare `Bash(git)`, and `Bash(git*)`.
    if [[ ! "$entry" =~ ^Bash\(([^:\)]*) ]]; then
        return 0
    fi
    local inner="${BASH_REMATCH[1]}"
    # Take first whitespace-delimited token.
    local head="${inner%%[[:space:]]*}"
    # Strip trailing `*` if no colon was present (e.g. `Bash(git*)`).
    head="${head%\*}"
    [ -n "$head" ] && printf '%s\n' "$head"
}

# Broad system-level Bash wildcards that warrant a static warning.
# A wildcard is "broad" when the entire inner pattern is `<head>:*` (no
# subcommand / argument prefix narrowing it). e.g. `Bash(gh:*)` is broad
# but `Bash(gh issue view:*)` is not. These heads cover CLI surfaces that
# include destructive subcommands and should be narrowed case by case.
skill_broad_bash_head_regex='^(git|gh|sh|bash|zsh)$'

# Return 0 if the entry is a broad system-level Bash wildcard
# (e.g. `Bash(git:*)`, `Bash(gh:*)`, `Bash(sh:*)`).
# Returns 1 for narrowed forms (`Bash(gh issue view:*)`, `Bash(rm /tmp:*)`)
# and for non-Bash entries.
skill_bash_entry_is_broad() {
    local entry="$1"
    local inner
    if [[ "$entry" =~ ^Bash\((.*):\*\)$ ]]; then
        inner="${BASH_REMATCH[1]}"
    else
        return 1
    fi
    # Broad iff inner has no whitespace (no subcommand narrowing)
    # and head matches the broad set.
    if [[ "$inner" =~ [[:space:]] ]]; then
        return 1
    fi
    if [[ "$inner" =~ $skill_broad_bash_head_regex ]]; then
        return 0
    fi
    return 1
}
