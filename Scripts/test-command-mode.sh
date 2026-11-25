#!/bin/zsh
# Command mode check (Blueprint 075). Runs real jobs through a built Layerworks.app and checks
# each result. Usage: Scripts/test-command-mode.sh /path/to/Layerworks.app
# Uses the app's own Command folder (no job folder chosen in Settings): the sandbox allows it.
set -u
APP="${1:?usage: test-command-mode.sh /path/to/Layerworks.app}/Contents/MacOS/Layerworks"
C="$HOME/Library/Containers/com.nightgard.Layerworks/Data/Documents/Command"
mkdir -p "$C" || exit 1
T="lw-selftest"
fails=0
check() { if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1 (got $2, want $3)"; fails=$((fails+1)); fi }

# Input: a 2 × 2 PNG (embedded below), enough to check erase, resize, export and save.
/usr/bin/base64 -d > "$C/$T-in.png" <<'B64'
iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwnwEIGBgYAA4HAf+B7G2PAAAAAElFTkSuQmCC
B64
cat > "$C/$T-1.json" <<J
{ "name": "$T-1", "width": 2, "height": 2, "steps": [
  { "do": "addImage", "file": "$T-in.png" }, { "do": "magicErase" }, { "do": "resize", "width": 4 },
  { "do": "exportPNG", "file": "$T-out.png" }, { "do": "saveProject", "file": "$T-out" } ] }
J
cat > "$C/$T-2.json" <<J
{ "name": "$T-2", "steps": [ { "do": "open", "file": "$T-out.layerworks" }, { "do": "imagePlayground" },
  { "do": "exportPNG", "file": "$T-never.png" } ] }
J
cat > "$C/$T-3.json" <<J
{ "name": "$T-3", "steps": [ { "do": "addImage", "file": "../x.png" } ] }
J
rm -f "$C/$T-never.png"
"$APP" --help >/dev/null;                 check "--help exits 0" $? 0
"$APP" --command "$T-1.json" >/dev/null;  check "job 1 exits 0" $? 0
[[ -f "$C/$T-out.png" ]];                 check "exportPNG wrote a file" $? 0
[[ -d "$C/$T-out.layerworks" ]];          check "saveProject wrote a package" $? 0
w=$(sips -g pixelWidth "$C/$T-out.png" | awk '/pixelWidth/ {print $2}'); check "resize width" "$w" 4
"$APP" --command "$T-2.json" | grep -q "^STOP 2 imagePlayground"; check "imagePlayground stops" $? 0
[[ ! -f "$C/$T-never.png" ]];             check "no step runs after the stop" $? 0
"$APP" --command "$T-3.json" >/dev/null;  check "a refused name fails the step (exit 1)" $? 1
"$APP" --command /etc/passwd 2>/dev/null; check "a path as the job is a usage error (exit 2)" $? 2
grep -q '"result" : "ok"' "$C/$T-1.status.json"; check "status file written" $? 0
rm -rf "$C/$T"-*
print "$(( 10 - fails )) of 10 passed"
exit $(( fails > 0 ))
