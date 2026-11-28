#!/usr/bin/env bash
# Lists the pinned versions of the catalog that have a newer release.
# Reads the current versions from the repository, so that the script stays correct after each update.
# Contains only the location of the releases.
# Exits with 1 when an update is available, or when a release or its source is unknown.
set -euo pipefail

cd "$(dirname "$0")/.."

# Gives the source of the latest release for each version input.
# A GitHub source is owner/repo, then the tag prefix if the tags have one.
# Use "github-tag" for a repository that publishes tags without releases.
# Use "skip" for a version that is selected on purpose, such as an LTS major version.
declare -A SOURCES=(
  [chart-releaser-version]="github helm/chart-releaser"
  [chart-testing-version]="github helm/chart-testing"
  [codeql-version]="github github/codeql-action codeql-bundle-"
  [cosign-version]="github sigstore/cosign"
  [dotnet-version]="skip"
  [fossa-version]="github fossas/fossa-cli"
  [goreleaser-version]="github goreleaser/goreleaser"
  [govulncheck-version]="github-tag golang/vuln"
  [grype-version]="github anchore/grype"
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
  [shellcheck-version]="github koalaman/shellcheck"
  [sonarscanner-version]="nuget dotnet-sonarscanner"
  [syft-version]="github anchore/syft"
  [task-version]="github go-task/task"
  [terraform-version]="github hashicorp/terraform"
  [tflint-version]="github terraform-linters/tflint"
  [trivy-version]="github aquasecurity/trivy"
  [yamale-version]="pypi yamale"
  [yamllint-version]="pypi yamllint"
  [actionlint-version]="github rhysd/actionlint"
  [bundler-version]="rubygems bundler"
)

# Excludes prereleases, because a default version must be stable.
# Lists the tags from the newest to the oldest.
github_tags() {
  local repo=$1 prefix=${2:-}
  git ls-remote --tags --refs "https://github.com/${repo}" | sed 's#.*refs/tags/##' \
    | grep -E "^${prefix}v?[0-9]+(\.[0-9]+)*$" | sed "s#^${prefix}##" | sort -rV
}

# Succeeds when the second version is newer than the first.
# Compares without the v prefix, because only some pins and some tags have it.
is_newer() {
  [[ "${1#v}" != "${2#v}" && "$(printf '%s\n%s\n' "${1#v}" "${2#v}" | sort -V | tail -1)" == "${2#v}" ]]
}

# Ignores a newer tag that has no release, because its files are not available.
# Calls the API only for newer tags, because GitHub limits the calls without a token.
latest_github() {
  local current=$1 repo=$2 prefix=${3:-} tag code
  while read -r tag; do
    if is_newer "$current" "$tag"; then
      code=$(curl -sS -o /dev/null -w '%{http_code}' "https://api.github.com/repos/${repo}/releases/tags/${prefix}${tag}")
      [[ "$code" == 404 ]] && continue
    fi
    echo "$tag"
    return
  done < <(github_tags "$repo" "$prefix")
}

latest() {
  local current=$1 kind=$2; shift 2
  case "$kind" in
    github) latest_github "$current" "$@" ;;
    github-tag) github_tags "$@" | sed -n 1p ;;
    nuget) curl -fsSL "https://api.nuget.org/v3-flatcontainer/$1/index.json" | jq -r '[.versions[] | select(test("-") | not)] | last' ;;
    npm) curl -fsSL "https://registry.npmjs.org/$1/latest" | jq -r .version ;;
    pypi) curl -fsSL "https://pypi.org/pypi/$1/json" | jq -r .info.version ;;
    rubygems) curl -fsSL "https://rubygems.org/api/v1/versions/$1/latest.json" | jq -r .version ;;
    kubectl) curl -fsSL https://dl.k8s.io/release/stable.txt ;;
    terraform) curl -fsSL "https://registry.terraform.io/v1/providers/$1/versions" | jq -r '[.versions[].version | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] | sort_by(split(".") | map(tonumber)) | last' ;;
    mongodb) curl -fsSL https://downloads.mongodb.org/full.json | jq -r '[.versions[] | select(.production_release) | .version] | first' ;;
  esac
}

status=0

report() {
  local name=$1 current=$2 found=$3 where=$4
  if [[ -z "$found" ]]; then
    printf '%-28s %-16s %-16s %s\n' "$name" "$current" "NOT FOUND" "$where"
    status=1
  elif is_newer "$current" "$found"; then
    printf '%-28s %-16s %-16s %s\n' "$name" "$current" "$found" "$where"
    status=1
  fi
}

# Prints one row for each pin: name, current version, file.
pins() {
  # Reads the version inputs of the composite actions that have a default value.
  for file in actions/*/*/action.yml actions/*/*/*/action.yml; do
    [[ -f "$file" ]] || continue
    awk -v f="$file" '
      /^  [a-z0-9-]+-version:$/ { name = substr($1, 1, length($1) - 1); next }
      /^  [a-z0-9-]+:/ { name = "" }
      name && /^    default:/ { gsub(/["'\'']/, "", $2); if ($2 != "") print name, $2, f; name = "" }
    ' "$file"
  done
  # Reads the MongoDB server version from an expression, because the default is there and workflows can pass an empty input.
  sed -nE "s/.*inputs\.mongodb-version \|\| '([0-9.]+)'.*/mongodb-server-version \1 actions\/mongodb\/start\/action.yml/p" actions/mongodb/start/action.yml
  # Reads the literal versions in the reusable workflows.
  # Excludes ci.yml, because it uses older versions to test the inputs.
  grep -HnoE '^\s+[a-z0-9-]+-version: v?[0-9][0-9.]*$' .github/workflows/reusable-*.yml \
    | awk -F: '{ gsub(/ /, "", $3); print $3, $4 ? $4 : "", $1 }' | sed 's/  */ /g'
  # Reads the versions of the tools that workflows and scripts pin with pipx, npx, a variable or a requirements file.
  grep -HoE 'pipx run --spec [A-Za-z0-9_.-]+==[^ ]+' .github/workflows/reusable-*.yml \
    | sed -E 's/^([^:]+):pipx run --spec ([^=]+)==(.*)/pypi:\2 \3 \1/'
  grep -HoE 'npx --yes [@A-Za-z0-9_./-]+@[0-9][^ ]*' .github/workflows/reusable-*.yml \
    | sed -E 's/^([^:]+):npx --yes (.+)@([^@]+)$/npm:\2 \3 \1/'
  grep -HoE 'shellcheck_version="[^"]+"' .github/workflows/reusable-*.yml \
    | sed -E 's/^([^:]+):shellcheck_version="([^"]+)"/shellcheck-version \2 \1/'
  sed -nE 's/^ACTIONLINT_VERSION=(.*)/actionlint-version \1 test\/run_static_checks.sh/p' test/run_static_checks.sh
  sed -nE 's/^SHELLCHECK_VERSION=(.*)/shellcheck-version \1 test\/run_static_checks.sh/p' test/run_static_checks.sh
  jq -r '.dependencies // {} | to_entries[] | "npm:\(.key) \(.value) test/package.json"' test/package.json
  # Reads the packages of the test fixtures.
  # Excludes a go.mod file, because the fixture is untidy on purpose.
  git ls-files 'test/fixtures/**/package.json' | while read -r file; do
    jq -r --arg f "$file" '(.dependencies // {}) + (.devDependencies // {}) | to_entries[] | "npm:\(.key) \(.value) \($f)"' "$file"
  done
  git ls-files 'test/fixtures/**/*.csproj' | while read -r file; do
    sed -nE "s#.*<PackageReference Include=\"([^\"]+)\" Version=\"([^\"]+)\".*#nuget:\1 \2 ${file}#p" "$file"
  done
  git ls-files 'test/fixtures/**/packages.config' | while read -r file; do
    sed -nE "s#.*<package id=\"([^\"]+)\" version=\"([^\"]+)\".*#nuget:\1 \2 ${file}#p" "$file"
  done
  # Reads the providers in the lock files of the fixtures, because the provider scan reports vulnerabilities in old versions.
  git ls-files '*.terraform.lock.hcl' | while read -r lock; do
    awk -v f="$lock" '
      /^provider "/ { split($2, parts, "/"); provider = parts[2] "/" parts[3]; gsub(/"/, "", provider) }
      provider && /^  version *=/ { gsub(/"/, "", $3); print "terraform:" provider, $3, f; provider = "" }
    ' "$lock"
  done
}

printf '%-28s %-16s %-16s %s\n' NAME CURRENT LATEST FILE

declare -A seen=()
while read -r name current file; do
  key="${name} ${current}"
  [[ -n "${seen[$key]:-}" ]] && continue
  seen[$key]=1
  if [[ "$name" == pypi:* ]]; then
    source="pypi ${name#pypi:}"
  elif [[ "$name" == npm:* ]]; then
    source="npm ${name#npm:}"
  elif [[ "$name" == nuget:* ]]; then
    source="nuget $(tr '[:upper:]' '[:lower:]' <<< "${name#nuget:}")"
  elif [[ "$name" == terraform:* ]]; then
    source="terraform ${name#terraform:}"
  else
    source="${SOURCES[$name]:-}"
  fi
  if [[ -z "$source" ]]; then
    printf '%-28s %-16s %-16s %s\n' "$name" "$current" "UNKNOWN SOURCE" "$file"
    status=1
    continue
  fi
  [[ "$source" == skip ]] && continue
  # shellcheck disable=SC2086 # Splits the source into its kind and arguments on purpose.
  report "$name" "$current" "$(latest "$current" $source || true)" "$file"
done < <(pins)

# Checks the GitHub Actions that are pinned by SHA, with the version from the comment at the end of the line.
while read -r action version; do
  repo=$(cut -d/ -f1-2 <<< "$action")
  report "$action" "$version" "$(latest_github "$version" "$repo" || true)" "uses"
done < <(grep -rhoE 'uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} +# v?[0-9.]+' .github actions \
  | sed -E 's/uses: ([^@]+)@[0-9a-f]+ +# (.*)/\1 \2/' | sort -u)

exit "$status"
