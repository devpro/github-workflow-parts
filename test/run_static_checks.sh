#!/usr/bin/env bash
# Runs the static checks of the workflow parts, the same way on a workstation and in the CI.
# The tools are pinned and verified like the binaries the actions download, and kept between two local runs.
# Linux x64 only.

set -euo pipefail

ACTIONLINT_VERSION=1.7.12

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="${RUNNER_TEMP:-${XDG_CACHE_HOME:-$HOME/.cache}}/github-workflow-parts-checks"
requirements="${repo_root}/test/requirements.txt"
requirements_hash="$(sha256sum "$requirements" | cut -d ' ' -f 1)"

# The virtual environment is built again whenever the requirements change.
if [ ! -f "${tools_dir}/venv/${requirements_hash}" ]; then
  echo "Installing PyYAML and shellcheck..."
  rm -rf "${tools_dir}/venv"
  python3 -m venv "${tools_dir}/venv"
  "${tools_dir}/venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes --only-binary :all: -r "$requirements"
  touch "${tools_dir}/venv/${requirements_hash}"
fi

actionlint="${tools_dir}/actionlint-${ACTIONLINT_VERSION}"
if [ ! -x "$actionlint" ]; then
  echo "Installing actionlint ${ACTIONLINT_VERSION}..."
  download_dir="$(mktemp -d)"
  tarball="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
  base_url="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}"
  curl -fsSL -o "${download_dir}/${tarball}" "${base_url}/${tarball}"
  curl -fsSL -o "${download_dir}/checksums.txt" "${base_url}/actionlint_${ACTIONLINT_VERSION}_checksums.txt"
  if ! (cd "$download_dir" && grep " ${tarball}$" checksums.txt | sha256sum --check --status); then
    echo "ERROR: Checksum verification failed for ${tarball}" >&2
    exit 1
  fi
  tar -xzf "${download_dir}/${tarball}" -C "$download_dir" actionlint
  mkdir -p "$tools_dir"
  mv "${download_dir}/actionlint" "$actionlint"
  rm -rf "$download_dir"
fi

export PATH="${tools_dir}/venv/bin:$PATH"
cd "$repo_root"

status=0
echo "Running actionlint on the workflows..."
"$actionlint" -shellcheck "$(command -v shellcheck)" || status=1
echo "Checking the conventions of the actions and workflows..."
python3 test/check_workflow_parts.py || status=1
exit "$status"
