#!/usr/bin/env bash
#
# Fetches the Godot web export templates for the pinned editor.
#
# proto pins the editor itself (.prototools, via .proto/plugins/godot.toml) and
# moon installs it, so nothing here downloads an engine -- doing so would put a
# second Godot on the machine and export with whichever one PATH happened to
# reach first. That is exactly what this script did in its first version, and
# the export failed looking for templates the other engine had never asked for.
#
# What proto cannot do is the templates: they unpack into an absolute path
# outside proto's tool directory, and its plugin says so. `--export-release`
# without them does not fail loudly -- Godot reports a missing template and
# writes nothing, so the Vite build that follows finds an empty public/godot
# and ships a page with no game in it.
set -euo pipefail

command -v godot > /dev/null 2>&1 || {
  echo "::error::godot is not on PATH. proto installs it from .prototools; run 'proto install'." >&2
  exit 1
}

# The engine is the authority on which templates it will accept, so the version
# is read from the binary rather than from a pin of our own. A second pin could
# disagree with .prototools, and the failure would be this same silent one.
#
#   4.7.2.stable.official.ed1daf0bf  ->  4.7.2.stable  (the directory name)
#                                    ->  4.7.2-stable  (the release tag)
full="$(godot --version 2>/dev/null | head -1)"
dir_name="$(echo "${full}" | sed 's/^\([0-9.]*\.[a-z]*\).*/\1/')"
tag="$(echo "${dir_name}" | sed 's/\.\([a-z]*\)$/-\1/')"
[ -n "${dir_name}" ] && [ "${dir_name}" != "${full}" ] || {
  echo "::error::could not read a version from 'godot --version' (${full})." >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) data_dir="${HOME}/Library/Application Support/Godot" ;;
  *) data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/godot" ;;
esac
templates="${data_dir}/export_templates/${dir_name}"

# The web templates are the only ones this game exports, so their presence is
# what decides whether the archive has to be fetched again.
if [ -f "${templates}/web_release.zip" ] && [ -f "${templates}/web_debug.zip" ]; then
  echo "Godot ${dir_name} web export templates are installed."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

url="https://github.com/godotengine/godot/releases/download/${tag}/Godot_v${tag}_export_templates.tpz"
echo "Fetching the Godot ${dir_name} export templates"
curl -fsSL --retry 3 -o "${tmp}/templates.tpz" "${url}" || {
  echo "::error::could not download ${url}" >&2
  echo "  The editor reports ${full}; check that ${tag} is a published release." >&2
  exit 1
}

# A .tpz is a zip whose members all sit under templates/. Only the web ones are
# extracted: the full set is several gigabytes on disk, and every other
# platform in it is for a target nothing here exports.
mkdir -p "${templates}"
unzip -q -j -o "${tmp}/templates.tpz" 'templates/web_*' -d "${templates}"

[ -f "${templates}/web_release.zip" ] || {
  echo "::error::the template archive contained no web_release.zip." >&2
  exit 1
}
echo "Installed the web export templates into ${templates}"
