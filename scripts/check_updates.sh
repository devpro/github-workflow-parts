#!/usr/bin/env bash
# Lists the pinned versions of the catalog that have a newer upstream release.
# The current versions are read from the repository, so the script stays right after every bump,
# and only where to look for a release is kept here.
# Exits with 1 when an update is available or a source is unknown.
set -euo pipefail

cd "$(dirname "$0")/.."

# Where each version input finds its latest release.
# A GitHub source is owner/repo, followed by the prefix of its tags when they have one.
# "skip" marks a channel chosen on purpose, such as an LTS major version.
declare -A SOURCES=(
  [chart-releaser-version]="github helm/chart-releaser"
  [chart-testing-version]="github helm/chart-testing"
  [codeql-version]="github github/codeql-action codeql-bundle-"
  [cosign-version]="github sigstore/cosign"
  [dotnet-version]="skip"
  [fossa-version]="github fossas/fossa-cli"
  [goreleaser-version]="github goreleaser/goreleaser"
  [govulncheck-version]="github golang/vuln"
  [helm-repo-html-version]="github halkeye/helm-repo-html"
  [helm-unittest-version]="github helm-unittest/helm-unittest"
  [helm-version]="github helm/helm"
  [java-version]="skip"
  [kind-version]="github kubernetes-sigs/kind"
  [kube-linter-version]="github stackrox/kube-linter"
  [kubeconform-version]="github yannh/kubeconform"
  [kubectl-version]="kubectl"
  [mongodb-server-version]="mongodb"
  [mongosh-version]="github mongodb-js/mongosh"
  [opengrep-version]="github opengrep/opengrep"
  [reportgenerator-version]="nuget dotnet-reportgenerator-globaltool"
  [scanner-version]="github SonarSource/sonar-scanner-cli"
  [sonarscanner-version]="nuget dotnet-sonarscanner"
  [syft-version]="github anchore/syft"
  [task-version]="github go-task/task"
  [terraform-version]="github hashicorp/terraform"
  [tflint-version]="github terraform-linters/tflint"
  [trivy-version]="github aquasecurity/trivy"
  [yamale-version]="pypi yamale"
  [yamllint-version]="pypi yamllint"
  [actionlint-version]="github rhysd/actionlint"
)

# Pre-releases are left out, since a default is only ever moved to a stable release.
latest_github() {
  local repo=$1 prefix=${2:-}
  git ls-remote --tags --refs "https://github.com/${repo}" | sed 's#.*refs/tags/##' \
    | grep -E "^${prefix}v?[0-9]+(\.[0-9]+)*$" | sed "s#^${prefix}##" | sort -V | tail -1
}

latest() {
  local kind=$1; shift
  case "$kind" in
    github) latest_github "$@" ;;
    nuget) curl -fsSL "https://api.nuget.org/v3-flatcontainer/$1/index.json" | jq -r '[.versions[] | select(test("-") | not)] | last' ;;
    pypi) curl -fsSL "https://pypi.org/pypi/$1/json" | jq -r .info.version ;;
    kubectl) curl -fsSL https://dl.k8s.io/release/stable.txt ;;
    mongodb) curl -fsSL https://downloads.mongodb.org/full.json | jq -r '[.versions[] | select(.production_release) | .version] | first' ;;
  esac
}

status=0

# Compares without the leading v, which some pins keep and some tags lack.
report() {
  local name=$1 current=$2 found=$3 where=$4
  if [[ -z "$found" ]]; then
    printf '%-28s %-16s %-16s %s\n' "$name" "$current" "NOT FOUND" "$where"
    status=1
  elif [[ "${current#v}" != "${found#v}" && "$(printf '%s\n%s\n' "${current#v}" "${found#v}" | sort -V | tail -1)" == "${found#v}" ]]; then
    printf '%-28s %-16s %-16s %s\n' "$name" "$current" "$found" "$where"
    status=1
  fi
}

# Each row: name, current version, file.
pins() {
  # Version inputs of the composite actions, with a non-empty default.
  for file in actions/*/*/action.yml actions/*/*/*/action.yml; do
    [[ -f "$file" ]] || continue
    awk -v f="$file" '
      /^  [a-z0-9-]+-version:$/ { name = substr($1, 1, length($1) - 1); next }
      /^  [a-z0-9-]+:/ { name = "" }
      name && /^    default:/ { gsub(/["'\'']/, "", $2); if ($2 != "") print name, $2, f; name = "" }
    ' "$file"
  done
  # The MongoDB server version sits in an expression, so that workflows can pass an empty input.
  sed -nE "s/.*inputs\.mongodb-version \|\| '([0-9.]+)'.*/mongodb-server-version \1 actions\/mongodb\/start\/action.yml/p" actions/mongodb/start/action.yml
  # Literal versions in the reusable workflows, ci.yml being left out since its older versions test the inputs.
  grep -HnoE '^\s+[a-z0-9-]+-version: v?[0-9][0-9.]*$' .github/workflows/reusable-*.yml \
    | awk -F: '{ gsub(/ /, "", $3); print $3, $4 ? $4 : "", $1 }' | sed 's/  */ /g'
  sed -nE 's/^ACTIONLINT_VERSION=(.*)/actionlint-version \1 test\/run_static_checks.sh/p' test/run_static_checks.sh
  sed -nE 's/^([A-Za-z0-9_.-]+)==([^ ]+).*/pypi:\1 \2 test\/requirements.txt/p' test/requirements.txt
}

printf '%-28s %-16s %-16s %s\n' NAME CURRENT LATEST FILE

declare -A seen=()
while read -r name current file; do
  key="${name} ${current}"
  [[ -n "${seen[$key]:-}" ]] && continue
  seen[$key]=1
  if [[ "$name" == pypi:* ]]; then
    source="pypi ${name#pypi:}"
  else
    source="${SOURCES[$name]:-}"
  fi
  if [[ -z "$source" ]]; then
    printf '%-28s %-16s %-16s %s\n' "$name" "$current" "UNKNOWN SOURCE" "$file"
    status=1
    continue
  fi
  [[ "$source" == skip ]] && continue
  # shellcheck disable=SC2086 # The source is split into its kind and arguments on purpose.
  report "$name" "$current" "$(latest $source || true)" "$file"
done < <(pins)

# GitHub Actions pinned by SHA, with their version in the trailing comment.
while read -r action version; do
  repo=$(cut -d/ -f1-2 <<< "$action")
  report "$action" "$version" "$(latest_github "$repo" || true)" "uses"
done < <(grep -rhoE 'uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} +# v?[0-9.]+' .github actions \
  | sed -E 's/uses: ([^@]+)@[0-9a-f]+ +# (.*)/\1 \2/' | sort -u)

exit "$status"
