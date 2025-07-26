#!/usr/bin/env bash
set -euo pipefail

shopt -s extglob globstar nullglob   # enable ** and other extended globs

usage() {
    echo "Usage: $0 [-i <glob-pattern>]… <directory>" >&2
    echo "       Patterns are evaluated relative to <directory>." >&2
    exit 1
}

# --------------- argument parsing -----------------
IGNORE_GLOBS=()
while (( $# )); do
    case $1 in
        -i|--ignore)
            [[ $# -ge 2 ]] || usage
            IGNORE_GLOBS+=("$2")
            shift 2;;
        -h|--help) usage;;
        --) shift; break;;
        -*) echo "Unknown option $1" >&2; usage;;
        *)  [[ -z ${TARGET_DIR:-} ]] || usage; TARGET_DIR="$1"; shift;;
    esac
done
[[ -n ${TARGET_DIR:-} ]] || usage
TARGET_DIR="$(realpath "$TARGET_DIR")"
OUTPUT="$(pwd)/prompt"
[[ -d "$TARGET_DIR" ]] || { echo "'$TARGET_DIR' is not a directory" >&2; exit 1; }

# --------------- git integration ------------------
if GIT_ROOT=$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null); then
    CHECK_IGNORE="git -C \"$GIT_ROOT\" check-ignore -q"
else
    CHECK_IGNORE="false"
fi

# --------------- helper: ignore test --------------
should_ignore() {
    local abs="$1" rel="${1#$TARGET_DIR/}"
    for pat in "${IGNORE_GLOBS[@]}"; do
        case $pat in
            # explicit glob patterns – leave them to Bash’s matcher
            *[*?]\**|*[*?]*) [[ $rel == $pat ]] && return 0;;
            # directory name / plain prefix – match anything beneath it
            *) [[ $rel == $pat* ]] && return 0;;
        esac
    done
    eval $CHECK_IGNORE "\"$abs\"" && return 0
    return 1
}

# --------------- main processing ------------------
rm -f "$OUTPUT"

echo "always write out the complete code files examples and command so it can be easily copy pasted. don't shorten any output make the complete implementation. remember to always write everything out to completion." > "$OUTPUT"

KEPT_FILES=()

# Collect files first
while IFS= read -r -d '' file; do
    [[ -f $file ]] || continue
    [[ $(realpath "$file") == "$OUTPUT" ]] && continue
    should_ignore "$file" && continue

    KEPT_FILES+=("$file")
done < <(find "$TARGET_DIR" -type f -not -path "$TARGET_DIR/.git/*" -print0 | sort -z)

# Write filtered tree to output
if (( ${#KEPT_FILES[@]} )); then
    echo "==== TREE STRUCTURE ====" >> "$OUTPUT"
    (
        cd "$TARGET_DIR"
        for f in "${KEPT_FILES[@]}"; do
            printf '%s\n' "${f#$TARGET_DIR/}"
        done | tree --fromfile
    ) >> "$OUTPUT"
fi

echo -e "\n\n==== FILE CONTENTS ====
" >> "$OUTPUT"

# Now write file contents
for file in "${KEPT_FILES[@]}"; do
    rel="${file#$TARGET_DIR/}"
    echo "===== FILE: $rel =====" >> "$OUTPUT"
    cat "$file" >> "$OUTPUT"
    echo -e "\n\n" >> "$OUTPUT"
done

# Filtered tree on stdout (optional, as before)
if (( ${#KEPT_FILES[@]} )); then
    (
        cd "$TARGET_DIR"
        for f in "${KEPT_FILES[@]}"; do
            printf '%s\n' "${f#$TARGET_DIR/}"
        done | tree --fromfile
    )
fi

echo "Prompt written to '$OUTPUT'"

