#!/usr/bin/env python3
"""Checks the composite actions and reusable workflows against the conventions of this repository.

Adds to actionlint, which reads only the workflows and does not know the conventions of this repository.
Runs from test/run_static_checks.sh, which installs PyYAML and shellcheck.
"""

import fnmatch
import pathlib
import re
import subprocess
import sys
import tempfile

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
SELF_REPOSITORY = "devpro/github-workflow-parts"

# Lists the parts that no CI job can test, with the reason, so that the coverage check accepts them.
UNTESTED_PARTS = {
    "actions/fossa/analyze": "needs a FOSSA API key",
    "actions/mongodb-atlas/add-runner-ip": "needs MongoDB Atlas credentials",
    ".github/workflows/reusable-helm-publication.yml": "creates GitHub releases and pushes to the Pages branch of the repository",
    ".github/workflows/reusable-terraform-deployment.yml": "needs MongoDB Atlas credentials and a Terraform backend",
}

# Lists the inputs that are kept but not used, because a caller fails when it passes an input that is not declared.
RESERVED_INPUTS = {}

TEXT_SUFFIXES = {".cs", ".csproj", ".hcl", ".json", ".md", ".py", ".sh", ".tf", ".yaml", ".yml", ""}
DASHES = (chr(0x2013), chr(0x2014))
SECOND_PERSON = re.compile(r"\b(you|your|yours|yourself)\b", re.IGNORECASE)
EXPRESSION = re.compile(r"\$\{\{\s*(.*?)\s*\}\}")
UNSAFE_IN_RUN = re.compile(r"^(inputs|secrets|env|steps|vars|matrix|needs|github\.event|github\.head_ref)\b")
INPUT_REFERENCE = re.compile(r"\binputs\.([A-Za-z0-9_-]+)")
SECRET_REFERENCE = re.compile(r"\bsecrets\.([A-Za-z0-9_-]+)")
ACTION_REFERENCE = re.compile(r"^actions/[a-z0-9-]+@[0-9a-f]{40}$")
# Requires a commit SHA, because a tag can move to another commit.
# The comment gives the release of that commit.
PINNED_LINE = re.compile(r"uses: actions/[a-z0-9-]+@[0-9a-f]{40} {2,}# v\d+\.\d+\.\d+$")

failures = []


def fail(path, message):
    failures.append(f"{path}: {message}")


def relative(path):
    return path.relative_to(ROOT).as_posix()


def load(path):
    # Uses the base loader, which reads all values as strings, so that the "on" key does not become true.
    return yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)


def git(*arguments):
    return subprocess.run(["git", *arguments], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def tracked_files():
    """Maps each file that git does not ignore to its mode, and uses the mode in the index when there is one."""
    modes = {}
    for line in git("ls-files", "-s").splitlines():
        meta, name = line.split("\t", 1)
        modes[name] = meta.split()[0]
    files = {}
    for name in git("ls-files", "--cached", "--others", "--exclude-standard").splitlines():
        path = ROOT / name
        if path.is_file():
            files[name] = modes.get(name, "100755" if path.stat().st_mode & 0o100 else "100644")
    return files


def action_paths():
    return sorted(path.parent for path in (ROOT / "actions").glob("*/*/action.yml"))


def workflow_paths():
    return sorted((ROOT / ".github/workflows").glob("*.yml"))


def steps_of(document):
    """Yields every step of a composite action or of the jobs of a workflow."""
    if "runs" in document:
        yield from document["runs"].get("steps", [])
    for job in (document.get("jobs") or {}).values():
        yield from job.get("steps", [])


def check_text_hygiene(files):
    for name, mode in files.items():
        path = ROOT / name
        if path.suffix not in TEXT_SUFFIXES or path.name == "LICENSE":
            continue
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            fail(name, "starts with a byte order mark")
        if b"\r\n" in raw:
            fail(name, "has CRLF line endings, but .editorconfig requires LF")
        if raw and not raw.endswith(b"\n"):
            fail(name, "does not end with a new line")
        text = raw.decode("utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            if any(dash in line for dash in DASHES):
                fail(f"{name}:{number}", "contains an en or em dash: use a colon, a comma or a full stop")
            # Skips quotations, because they keep the words of their source.
            if path.suffix in {".md", ".yml", ".yaml"} and name not in {"AGENTS.md", "CLAUDE.md"} and not line.lstrip().startswith(">"):
                if SECOND_PERSON.search(line):
                    fail(f"{name}:{number}", "uses the second person")
        if path.suffix in {".sh", ".py"}:
            if not re.fullmatch(r"[a-z0-9_]+", path.stem):
                fail(name, "script name is not snake_case")
            if mode != "100755":
                fail(name, "script does not have the executable bit")
        if path.suffix in {".yml", ".yaml"}:
            try:
                load(path)
            except yaml.YAMLError as error:
                fail(name, f"is not valid YAML: {error}")


def check_inputs_are_used(name, text, declared, kind, pattern):
    # Removes the comments, because a step in a comment does not use an input.
    text = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    used = set(pattern.findall(text))
    reserved = RESERVED_INPUTS.get(name, set()) if kind == "input" else set()
    for missing in sorted(used - set(declared)):
        fail(name, f"references the {kind} '{missing}', but does not declare it")
    for unused in sorted(set(declared) - used - reserved):
        fail(name, f"declares the {kind} '{unused}', but does not use it")
    for stale in sorted(reserved & used):
        fail(name, f"lists the input '{stale}' in RESERVED_INPUTS, but uses it")


def check_action(directory):
    path = directory / "action.yml"
    name = relative(path)
    document = load(path)
    for key in ("name", "description"):
        if not str(document.get(key, "")).strip():
            fail(name, f"has no {key}")
    runs = document.get("runs") or {}
    if runs.get("using") != "composite":
        fail(name, "is not a composite action")
    inputs = document.get("inputs") or {}
    for input_name, spec in inputs.items():
        if not str(spec.get("description", "")).strip():
            fail(name, f"input '{input_name}' has no description")
        if spec.get("required") == "true" and "default" in spec:
            fail(name, f"input '{input_name}' is required and has a default, but GitHub never uses that default")
    check_inputs_are_used(name, path.read_text(encoding="utf-8"), inputs, "input", INPUT_REFERENCE)
    for index, step in enumerate(runs.get("steps", []), 1):
        if not step.get("name"):
            fail(name, f"step {index} has no name")
        # Accepts PowerShell, because Windows does not include bash.
        if "run" in step and step.get("shell") not in ("bash", "pwsh"):
            fail(name, f"step '{step.get('name', index)}' runs a script without 'shell: bash' or 'shell: pwsh', but a composite action requires a shell")


def check_reusable_workflow(path):
    name = relative(path)
    document = load(path)
    if not str(document.get("name", "")).startswith("Reusable - "):
        fail(name, "name does not start with 'Reusable - '")
    call = (document.get("on") or {}).get("workflow_call")
    if call is None:
        fail(name, "is not triggered by workflow_call")
        return
    call = call or {}
    text = path.read_text(encoding="utf-8")
    inputs = call.get("inputs") or {}
    for input_name, spec in inputs.items():
        if not str(spec.get("description", "")).strip():
            fail(name, f"input '{input_name}' has no description")
        if not spec.get("type"):
            fail(name, f"input '{input_name}' has no type")
    check_inputs_are_used(name, text, inputs, "input", INPUT_REFERENCE)
    check_inputs_are_used(name, text, call.get("secrets") or {}, "secret", SECRET_REFERENCE)
    for step in steps_of(document):
        if step.get("with", {}).get("repository") == SELF_REPOSITORY:
            # Requires this ref, because without it the CI tests the workflow parts of the default branch instead of the commit.
            expected = f"github.repository == '{SELF_REPOSITORY}' && github.sha || inputs.workflow-parts-version"
            if expected not in step["with"].get("ref", ""):
                fail(name, f"checks out the workflow parts without '{expected}' as ref")


def check_run_scripts(path, document):
    name = relative(path)
    for step in steps_of(document):
        script = step.get("run")
        if script is None:
            continue
        label = f"step '{step.get('name', '?')}'"
        for expression in EXPRESSION.findall(script):
            # Applies also to inputs that contain shell code, because a script must run them from a variable with eval.
            if UNSAFE_IN_RUN.match(expression):
                fail(name, f"{label} writes '${{{{ {expression} }}}}' into its script: use an env variable, so that the value does not run as code")
        if re.search(r"\$\?\s+-(eq|ne)", script):
            fail(name, f"{label} tests $? after a command, but bash -e stops when the command fails")
        # Removes the comments, because a command in a comment does not run.
        code = "\n".join(line for line in script.splitlines() if not line.lstrip().startswith("#"))
        joined = code.replace("\\\n", " ")
        for command in re.findall(r"\bcurl\b[^\n|;&)]*", joined):
            flags = " ".join(token for token in command.split() if token.startswith("-"))
            if not re.search(r"(^|\s)(-[a-zA-Z]*[fw][a-zA-Z]*|--fail|--write-out)\b", flags):
                fail(name, f"{label} calls curl without --fail or --write-out, so curl can save an HTTP error page as the download")
        if "curl" in code and " -O " in joined and "sha256sum --check" not in script:
            fail(name, f"{label} downloads a file, but does not verify its SHA256 checksum")


def shellcheck_actions():
    with tempfile.TemporaryDirectory() as directory:
        scripts = {}
        for action in action_paths():
            document = load(action / "action.yml")
            for index, step in enumerate(document["runs"].get("steps", []), 1):
                if "run" not in step or step.get("shell") != "bash":
                    continue
                script = pathlib.Path(directory) / f"{action.relative_to(ROOT).as_posix().replace('/', '_')}_{index}.sh"
                # Replaces each expression with a plain word, because the runner replaces expressions before bash runs.
                body = EXPRESSION.sub("expression_value", step["run"])
                script.write_text(f"#!/usr/bin/env bash\nset -eo pipefail\n{body}\n", encoding="utf-8")
                scripts[script.name] = f"{relative(action / 'action.yml')} step '{step.get('name', index)}'"
        if not scripts:
            return
        result = subprocess.run(
            ["shellcheck", "--shell=bash", "--format=gcc", *sorted(scripts)],
            cwd=directory,
            capture_output=True,
            text=True,
        )
        for line in result.stdout.splitlines():
            script, _, message = line.partition(":")
            fail(scripts.get(script, script), f"shellcheck line {message.strip()}")
        if result.returncode not in (0, 1):
            fail("shellcheck", result.stderr.strip())


def local_target(uses):
    """Converts a local reference to the path of the action or workflow in this repository."""
    for prefix in ("./workflow-parts/", "./"):
        if uses.startswith(prefix):
            return uses[len(prefix):].rstrip("/")
    return None


def check_references(path, document):
    name = relative(path)
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if "uses: actions/" in line and not PINNED_LINE.search(line):
            fail(f"{name}:{number}", "must pin a first-party action to a full commit SHA, followed by two spaces and '# vX.Y.Z'")
    references = [step for step in steps_of(document) if "uses" in step]
    references += [job for job in (document.get("jobs") or {}).values() if "uses" in job]
    for item in references:
        uses = item["uses"]
        target = local_target(uses)
        if target is None:
            # Accepts only first-party actions, because the actions of this repository download other tools and verify their checksum.
            if not ACTION_REFERENCE.match(uses):
                fail(name, f"uses '{uses}', but only local actions and first-party actions pinned to a commit SHA are permitted")
            continue
        target_path = ROOT / target
        given = set((item.get("with") or {}).keys())
        if target.endswith(".yml"):
            if not target_path.is_file():
                fail(name, f"calls '{uses}', but it does not exist")
                continue
            declared = (load(target_path)["on"]["workflow_call"] or {}).get("inputs") or {}
        else:
            if not (target_path / "action.yml").is_file():
                fail(name, f"uses '{uses}', but it does not exist")
                continue
            declared = load(target_path / "action.yml").get("inputs") or {}
        for unknown in sorted(given - set(declared)):
            fail(name, f"passes '{unknown}' to '{uses}', but the target does not declare it")
        for input_name, spec in declared.items():
            if spec.get("required") == "true" and "default" not in spec and input_name not in given:
                fail(name, f"does not pass the required input '{input_name}' to '{uses}'")


def check_timeouts(path, document):
    # Requires a timeout, because GitHub stops a blocked job only after six hours.
    for job_id, job in (document.get("jobs") or {}).items():
        if "steps" in job and "timeout-minutes" not in job:
            fail(relative(path), f"job '{job_id}' runs steps without timeout-minutes")


def check_action_versions():
    versions = {}
    for path in [*workflow_paths(), *(action / "action.yml" for action in action_paths())]:
        for step in steps_of(load(path)):
            uses = step.get("uses", "")
            if ACTION_REFERENCE.match(uses):
                action, version = uses.split("@")
                versions.setdefault(action, {}).setdefault(version, []).append(relative(path))
    for action, by_version in versions.items():
        if len(by_version) > 1:
            fail(action, f"is pinned to several versions: {', '.join(f'{v} in {sorted(set(f))}' for v, f in sorted(by_version.items()))}")


def check_readme():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    links = set(re.findall(r"\]\(([^)#]+)\)", readme))
    for link in sorted(links):
        if not link.startswith("http") and not (ROOT / link).exists():
            fail("README.md", f"links to '{link}', but it does not exist")
    linked = {link.rstrip("/").removesuffix("/action.yml") for link in links}
    parts = [relative(action) for action in action_paths()]
    parts += [relative(path) for path in workflow_paths() if path.name.startswith("reusable-")]
    for part in parts:
        if part not in linked:
            fail("README.md", f"does not list '{part}'")


def runs_with(condition, values):
    """Returns the result of a condition for the given inputs, or None when the condition is not a test of one known input."""
    condition = condition.strip()
    if condition.startswith("${{") and condition.endswith("}}"):
        condition = condition[3:-2].strip()
    match = re.fullmatch(r"(!\s*)?inputs\.([A-Za-z0-9_-]+)(?:\s*(==|!=)\s*'([^']*)')?", condition)
    if not match or match.group(2) not in values or "${{" in values[match.group(2)]:
        return None
    negation, name, operator, expected = match.groups()
    value = values[name]
    if operator:
        return (value == expected) == (operator == "==")
    return (value not in ("", "false", "0")) != bool(negation)


def declared_inputs(path):
    document = load(path)
    if "runs" in document:
        return document.get("inputs") or {}
    return (document["on"]["workflow_call"] or {}).get("inputs") or {}


def exercised_parts():
    """Collects the parts that the CI workflow runs, directly or through the parts that it calls."""
    exercised = set()
    pending = [(ROOT / ".github/workflows/ci.yml", None)]
    while pending:
        path, values = pending.pop()
        document = load(path)
        items = [job for job in (document.get("jobs") or {}).values() if "uses" in job]
        items += [step for step in steps_of(document) if "uses" in step]
        for item in items:
            target = local_target(item["uses"])
            if target is None:
                continue
            # Accepts all steps of the CI workflow, but accepts a step of a called part only when the inputs enable it.
            if values is not None and "if" in item and not runs_with(item["if"], values):
                continue
            target_path = ROOT / target if target.endswith(".yml") else ROOT / target / "action.yml"
            called_with = {name: spec.get("default", "") for name, spec in declared_inputs(target_path).items()}
            called_with.update(item.get("with") or {})
            exercised.add(target)
            pending.append((target_path, called_with))
    return exercised


def check_coverage():
    exercised = exercised_parts()
    parts = [relative(action) for action in action_paths()]
    parts += [relative(path) for path in workflow_paths() if path.name.startswith("reusable-")]
    for part in parts:
        if part in exercised and part in UNTESTED_PARTS:
            fail(part, "is tested by the CI: remove it from UNTESTED_PARTS")
        elif part not in exercised and part not in UNTESTED_PARTS:
            fail(part, "is not tested by a CI job: add a test, or add it to UNTESTED_PARTS with the reason")
    for part in sorted(set(UNTESTED_PARTS) - set(parts)):
        fail(part, "is listed in UNTESTED_PARTS, but does not exist")


def check_istarci():
    path = ROOT / ".istarci.yml"
    if not path.exists():
        return
    config = load(path)
    runner = config.get("runner") or {}
    jobs = list((load(ROOT / ".github/workflows/ci.yml").get("jobs") or {}).keys())
    patterns = list((runner.get("images") or {}).keys()) + list(runner.get("docker") or [])
    patterns += list((config.get("workflow") or {}).get("skipJobs") or [])
    for pattern in patterns:
        if not fnmatch.filter(jobs, pattern):
            fail(".istarci.yml", f"pattern '{pattern}' matches no job of the CI workflow")


def main():
    check_text_hygiene(tracked_files())
    for action in action_paths():
        check_action(action)
        document = load(action / "action.yml")
        check_run_scripts(action / "action.yml", document)
        check_references(action / "action.yml", document)
    for path in workflow_paths():
        document = load(path)
        if path.name.startswith("reusable-"):
            check_reusable_workflow(path)
        check_run_scripts(path, document)
        check_references(path, document)
        check_timeouts(path, document)
    shellcheck_actions()
    check_action_versions()
    check_readme()
    check_coverage()
    check_istarci()
    for failure in failures:
        print(f"FAIL {failure}")
    print(f"{len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
