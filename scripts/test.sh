#!/usr/bin/env bash
# Runs the unit tests. Works with full Xcode or with only the Command Line Tools
# (which ship Swift Testing, but neither on the default search path nor with its
# Foundation cross-import overlay, hence the extra flags).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

args=()
developer_dir="$(xcode-select -p 2>/dev/null || true)"
clt_frameworks="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
if [[ "${developer_dir}" == "/Library/Developer/CommandLineTools" && -d "${clt_frameworks}" ]]; then
    args+=(-Xswiftc -F"${clt_frameworks}" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -F"${clt_frameworks}" -Xlinker -rpath -Xlinker "${clt_frameworks}")
fi

exec swift test ${args[@]+"${args[@]}"} "$@"
