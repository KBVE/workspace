#!/usr/bin/env bash
#
# Puts the Godot editor and its matching web export templates where the build
# can find them.
#
# Lives beside the game rather than in the release workflow so that shipping a
# game stays a moon.yml edit: the workflow installs the toolchains the
# workspace declares, and a step naming this game would put a project back in a
# shared file. Same reasoning as rentearth-bevy's ensure-wasm-bindgen.sh.
#
# The templates matter as much as the binary. `--export-release "Web"` against
# an editor with no templates installed does not fail loudly -- it reports a
# missing template and writes nothing, so the vite build that follows finds an
# empty public/godot and ships a page with no game in it.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The exact build to install. Kept in its own file rather than derived from
# project.godot, which records only the feature level ("4.7") and cannot say
# which build of it -- stable, rc, dev -- this game is tested against.
version="$(tr -d '[:space:]' < "${project_dir}/.godot-version")"
[ -n "${version}" ] || { echo "error: .godot-version is empty." >&2; exit 1; }

# ...but the two must still agree, or the game is exported by an engine whose
# feature level its own project file does not claim.
feature="$(sed -n 's/^config\/features=PackedStringArray("\([0-9]*\.[0-9]*\)".*/\1/p' \
  "${project_dir}/godot/project.godot")"
case "${version}" in
  "${feature}"-*|"${feature}") ;;
  *)
    echo "error: .godot-version is ${version}, but project.godot claims feature level ${feature}." >&2
    exit 1
    ;;
esac

# 4.7-stable -> 4.7.stable, which is what the editor calls the directory it
# looks for templates in.
template_dir_name="${version/-/.}"

bin_dir="${GODOT_BIN_DIR:-${HOME}/.local/bin}"

case "$(uname -s)" in
  Linux)
    archive="Godot_v${version}_linux.x86_64"
    data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/godot"
    ;;
  Darwin)
    archive="Godot_v${version}_macos.universal"
    data_dir="${HOME}/Library/Application Support/Godot"
    ;;
  *)
    echo "error: no Godot download for $(uname -s)." >&2
    echo "  Install Godot ${version} with its export templates and put it on PATH." >&2
    exit 1
    ;;
esac

templates="${data_dir}/export_templates/${template_dir_name}"
base="https://github.com/godotengine/godot/releases/download/${version}"

installed_version() {
  command -v "$1" > /dev/null 2>&1 || return 1
  # `4.7.stable.official.abcdef123` -> `4.7-stable`
  "$1" --version 2>/dev/null | head -1 | sed 's/^\([0-9]*\.[0-9]*\)\.\([a-z]*\).*/\1-\2/'
}

need_binary=1
if [ "$(installed_version "${bin_dir}/godot" || true)" = "${version}" ]; then
  need_binary=0
elif [ "$(installed_version godot || true)" = "${version}" ]; then
  need_binary=0
fi

# The web template is the only one this game exports, so its presence is what
# decides whether the ~700MB template archive has to be fetched again.
need_templates=1
[ -f "${templates}/web_release.zip" ] && need_templates=0

if [ "${need_binary}" = 0 ] && [ "${need_templates}" = 0 ]; then
  echo "Godot ${version} and its web export templates are already installed."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fetch() {
  curl -fsSL --retry 3 -o "$2" "$1" || {
    echo "error: could not download $1" >&2
    echo "  Check that ${version} is a real release and update .godot-version." >&2
    exit 1
  }
}

if [ "${need_binary}" = 1 ]; then
  echo "Installing Godot ${version} into ${bin_dir}"
  fetch "${base}/${archive}.zip" "${tmp}/godot.zip"
  unzip -q "${tmp}/godot.zip" -d "${tmp}/godot"
  mkdir -p "${bin_dir}"
  case "$(uname -s)" in
    Linux) install -m 0755 "${tmp}/godot/${archive}" "${bin_dir}/godot" ;;
    Darwin)
      # The macOS download is an .app bundle, so the binary inside it is what
      # goes on PATH. Copied rather than symlinked out of the temp directory,
      # which this script deletes on exit.
      rm -rf "${bin_dir}/Godot.app"
      cp -R "${tmp}/godot/Godot.app" "${bin_dir}/Godot.app"
      ln -sf "${bin_dir}/Godot.app/Contents/MacOS/Godot" "${bin_dir}/godot"
      ;;
  esac
fi

if [ "${need_templates}" = 1 ]; then
  echo "Installing the Godot ${version} export templates"
  fetch "${base}/Godot_v${version}_export_templates.tpz" "${tmp}/templates.tpz"
  # A .tpz is a zip whose members all sit under templates/.
  unzip -q "${tmp}/templates.tpz" -d "${tmp}/templates"
  mkdir -p "${templates}"
  cp -R "${tmp}/templates/templates/." "${templates}/"
  [ -f "${templates}/web_release.zip" ] || {
    echo "error: the template archive contained no web_release.zip." >&2
    exit 1
  }
fi

case ":${PATH}:" in
  *":${bin_dir}:"*) ;;
  *) echo "warning: ${bin_dir} is not on PATH, so \`godot\` will not be found." >&2 ;;
esac

echo "Godot $("${bin_dir}/godot" --version 2>/dev/null | head -1) is ready."
