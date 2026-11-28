#!/usr/bin/env bash
# Runs the static checks of the workflow parts in the same way on a workstation and in the CI.
# Pins and verifies the tools, and keeps them between local runs.
# Supports only Linux x64.

set -euo pipefail

ACTIONLINT_VERSION=1.7.12
# Pins the SHA256 of the archive, because ShellCheck publishes no checksum file.
SHELLCHECK_VERSION=v0.11.0
SHELLCHECK_SHA256=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="${RUNNER_TEMP:-${XDG_CACHE_HOME:-$HOME/.cache}}/github-workflow-parts-checks"
mkdir -p "$tools_dir"

# Installs the packages of the lock file again only when it changes, and npm verifies the integrity hash of each package.
lock_hash="$(sha256sum "${repo_root}/test/package-lock.json" | cut -d ' ' -f 1)"
if [ ! -f "${repo_root}/test/node_modules/.lock-${lock_hash}" ]; then
  echo "Installing the yaml package..."
  npm ci --prefix "${repo_root}/test" --ignore-scripts --no-audit --no-fund --silent
  touch "${repo_root}/test/node_modules/.lock-${lock_hash}"
fi

shellcheck="${tools_dir}/shellcheck-${SHELLCHECK_VERSION}"
if [ ! -x "$shellcheck" ]; then
  echo "Installing shellcheck ${SHELLCHECK_VERSION}..."
  download_dir="$(mktemp -d)"
  archive="shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.gz"
  curl -fsSL -o "${download_dir}/${archive}" "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${archive}"
  if ! echo "${SHELLCHECK_SHA256}  ${download_dir}/${archive}" | sha256sum --check --status; then
    echo "ERROR: Checksum verification failed for ${archive}" >&2
    exit 1
  fi
  tar -xzf "${download_dir}/${archive}" -C "$download_dir"
  mv "${download_dir}/shellcheck-${SHELLCHECK_VERSION}/shellcheck" "$shellcheck"
  rm -rf "$download_dir"
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
  mv "${download_dir}/actionlint" "$actionlint"
  rm -rf "$download_dir"
fi

# Puts the pinned shellcheck first on the PATH, because the conventions check calls shellcheck by name.
bin_dir="${tools_dir}/bin"
mkdir -p "$bin_dir"
ln -sf "$shellcheck" "${bin_dir}/shellcheck"
export PATH="${bin_dir}:$PATH"
cd "$repo_root"

status=0
echo "Running actionlint on the workflows..."
"$actionlint" -shellcheck "$shellcheck" || status=1
echo "Checking the conventions of the actions and workflows..."
node test/check_workflow_parts.js || status=1
exit "$status"
