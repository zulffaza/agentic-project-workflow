#!/usr/bin/env bash
# ============================================================================
# instruction_register.sh — validate the bounded instruction-consistency register.
#
#   tests/instruction_register.sh check [--register FILE] [--root DIR]
#
# Test support, not a user command. Register format: "# instruction-register v1",
# then TAB-separated rows:
#   id  owner  section  surfaces  required  retired
#
#   owner     tooling-relative file that owns the canonical contract
#   section   exact heading text in the owner (without leading #), or -
#             (the section bounds the required-text check and must exist)
#   surfaces  - (owner only) or comma-separated tooling-relative files scanned
#             whole for the retired pattern
#   required  literal text that must appear in the owner section, or -
#   retired   ERE that must be absent from every surface, or -
#
# The register catches known retirements; it cannot prove semantic consistency
# and cannot detect paraphrases. Human reconciliation still decides.
# ============================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$HERE/../.." && pwd)"

usage() {
  cat <<'EOF'
usage: instruction_register.sh check [--register FILE] [--root DIR]

  --register FILE  register TSV (default: tooling/tests/expectations/instructions.tsv)
  --root DIR       bundle root the tooling-relative paths resolve against
EOF
}

CMD=""
ROOT="$DEFAULT_ROOT"
REGISTER="$DEFAULT_ROOT/tooling/tests/expectations/instructions.tsv"
while [ $# -gt 0 ]; do
  case "$1" in
    check) CMD="check"; shift ;;
    --register) [ $# -ge 2 ] || { echo "instruction_register: --register needs a value" >&2; exit 2; }; REGISTER="$2"; shift 2 ;;
    --root) [ $# -ge 2 ] || { echo "instruction_register: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "instruction_register: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ "$CMD" = check ] || { echo "instruction_register: the check command is required" >&2; usage >&2; exit 2; }
[ -d "$ROOT" ] || { echo "instruction_register: root not found: $ROOT" >&2; exit 2; }
[ -f "$REGISTER" ] || { echo "instruction_register: register not found: $REGISTER" >&2; exit 2; }

awk -v root="$ROOT" '
function err(msg) { printf "instruction-register: %s: %s\n", id, msg > "/dev/stderr"; bad = 1 }

function load(path,   line, rc) {
  if (path in content) return content[path]
  content[path] = ""
  rc = (getline line < (root "/tooling/" path))
  if (rc < 0) { content[path] = "\001MISSING"; return content[path] }
  if (rc > 0) {
    content[path] = line "\n"
    while ((getline line < (root "/tooling/" path)) > 0) content[path] = content[path] line "\n"
  }
  close(root "/tooling/" path)
  return content[path]
}

function section_text(path, head,   txt, line, lines, n, i, out, inb, name) {
  txt = load(path)
  if (txt == "\001MISSING") return txt
  if (head == "-") return txt
  out = ""
  inb = 0
  n = split(txt, lines, "\n")
  for (i = 1; i <= n; i++) {
    line = lines[i]
    if (line ~ /^#{1,6}[ \t]/) {
      name = line
      sub(/^#{1,6}[ \t]+/, "", name)
      sub(/[ \t]+$/, "", name)
      if (!inb && name == head) { inb = 1; continue }
      if (inb) break
    } else if (inb) {
      out = out line "\n"
    }
  }
  return out
}

$0 ~ /^#/ {
  if ($0 == "# instruction-register v1") header = 1
  next
}
$0 == "" { next }
{
  n = split($0, f, "\t")
  if (n != 6) {
    printf "instruction-register: line %d: expected 6 tab-separated fields, found %d\n", NR, n > "/dev/stderr"
    bad = 1
    next
  }
  rows++
  ids[rows] = f[1]
  owners[rows] = f[2]
  sections[rows] = f[3]
  surfaces[rows] = f[4]
  required[rows] = f[5]
  retired[rows] = f[6]
}

END {
  if (!header) {
    printf "instruction-register: missing header \"# instruction-register v1\"\n" > "/dev/stderr"
    bad = 1
  }
  if (rows == 0) {
    printf "instruction-register: no contract rows\n" > "/dev/stderr"
    bad = 1
  }
  for (i = 1; i <= rows; i++) {
    id = ids[i]
    if (id == "") { printf "instruction-register: row %d has an empty id\n", i > "/dev/stderr"; bad = 1; continue }
    if (id in seen_id) { err("duplicate contract id"); continue }
    seen_id[id] = 1

    txt = section_text(owners[i], sections[i])
    if (txt == "\001MISSING") { err("owner file not found: " owners[i]); continue }
    if (sections[i] != "-" && txt == "") { err("owner section not found or empty: " sections[i] " in " owners[i]); continue }
    if (required[i] != "-" && index(txt, required[i]) == 0) {
      err("required text missing from " owners[i] " § " sections[i] ": " required[i])
    }

    if (retired[i] != "-") {
      list = surfaces[i]
      if (list == "-") list = owners[i]
      else if (index("," list ",", "," owners[i] ",") == 0) list = owners[i] "," list
      m = split(list, files, ",")
      for (j = 1; j <= m; j++) {
        if (files[j] == "") continue
        stxt = load(files[j])
        if (stxt == "\001MISSING") { err("surface file not found: " files[j]); continue }
        if (match(stxt, retired[i]) > 0) {
          err("retired text reappeared in " files[j] ": " retired[i])
        }
      }
    }
    ok++
  }
  if (bad) exit 1
  printf "instruction-register: ok (%d contracts)\n", ok
}
' "$REGISTER"
