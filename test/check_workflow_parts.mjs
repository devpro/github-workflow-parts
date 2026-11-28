#!/usr/bin/env node
// Checks the composite actions and reusable workflows against the conventions of this repository.
// Adds to actionlint, which reads only the workflows and does not know the conventions of this repository.
// Runs from test/run_static_checks.sh, which installs the yaml package and shellcheck.

import { execFileSync, spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, extname, join, relative as relativePath, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parse } from 'yaml'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const SELF_REPOSITORY = 'devpro/github-workflow-parts'

// Lists the parts that no CI job can test, with the reason, so that the coverage check accepts them.
const UNTESTED_PARTS = {
  'actions/fossa/analyze': 'needs a FOSSA API key',
  'actions/mongodb-atlas/add-runner-ip': 'needs MongoDB Atlas credentials',
  '.github/workflows/reusable-helm-publication.yml': 'creates GitHub releases and pushes to the Pages branch of the repository',
  '.github/workflows/reusable-terraform-deployment.yml': 'needs MongoDB Atlas credentials and a Terraform backend',
}

// Lists the inputs that are kept but not used, because a caller fails when it passes an input that is not declared.
const RESERVED_INPUTS = {}

const TEXT_SUFFIXES = new Set(['.cs', '.csproj', '.hcl', '.js', '.json', '.mjs', '.md', '.pp', '.rb', '.sh', '.tf', '.yaml', '.yml', ''])
const DASHES = [String.fromCodePoint(0x2013), String.fromCodePoint(0x2014)]
const SECOND_PERSON = /\b(you|your|yours|yourself)\b/i
const EXPRESSION = /\$\{\{\s*(.*?)\s*\}\}/g
const UNSAFE_IN_RUN = /^(inputs|secrets|env|steps|vars|matrix|needs|github\.event|github\.head_ref)\b/
const INPUT_REFERENCE = /\binputs\.([A-Za-z0-9_-]+)/g
const SECRET_REFERENCE = /\bsecrets\.([A-Za-z0-9_-]+)/g
const ACTION_REFERENCE = /^actions\/[a-z0-9-]+@[0-9a-f]{40}$/
// Requires a commit SHA, because a tag can move to another commit.
// The comment gives the release of that commit.
const PINNED_LINE = /uses: actions\/[a-z0-9-]+@[0-9a-f]{40} {2,}# v\d+\.\d+\.\d+$/

const failures = []

const fail = (path, message) => failures.push(`${path}: ${message}`)

const relative = (path) => relativePath(ROOT, path).split('\\').join('/')

const read = (path) => readFileSync(path, 'utf8')

// Uses the failsafe schema, which reads all values as strings, so that the "on" key does not become true.
const load = (path) => parse(read(path), { schema: 'failsafe' }) ?? {}

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)

// Returns an object for a mapping, and an empty object for an empty value or a missing key.
const mapping = (value) => (isObject(value) ? value : {})

const list = (value) => (Array.isArray(value) ? value : [])

const text = (value) => (typeof value === 'string' ? value : '')

const git = (...args) => execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })

// Maps each file that git does not ignore to its mode, and uses the mode in the index when there is one.
function trackedFiles() {
  const modes = new Map()
  for (const line of git('ls-files', '-s').split('\n').filter(Boolean)) {
    const [meta, name] = line.split('\t')
    modes.set(name, meta.split(' ')[0])
  }
  const files = new Map()
  for (const name of git('ls-files', '--cached', '--others', '--exclude-standard').split('\n').filter(Boolean)) {
    const path = join(ROOT, name)
    if (existsSync(path) && statSync(path).isFile()) {
      files.set(name, modes.get(name) ?? (statSync(path).mode & 0o100 ? '100755' : '100644'))
    }
  }
  return files
}

function actionPaths() {
  const paths = []
  const actions = join(ROOT, 'actions')
  for (const tool of readdirSync(actions).sort()) {
    if (!statSync(join(actions, tool)).isDirectory()) continue
    for (const verb of readdirSync(join(actions, tool)).sort()) {
      if (existsSync(join(actions, tool, verb, 'action.yml'))) paths.push(join(actions, tool, verb))
    }
  }
  return paths
}

function workflowPaths() {
  const directory = join(ROOT, '.github/workflows')
  return readdirSync(directory).filter((name) => name.endsWith('.yml')).sort().map((name) => join(directory, name))
}

// Gives every step of a composite action or of the jobs of a workflow.
function stepsOf(document) {
  const steps = [...list(mapping(document.runs).steps)]
  for (const job of Object.values(mapping(document.jobs))) steps.push(...list(mapping(job).steps))
  return steps.filter(isObject)
}

const lines = (value) => value.split(/\r?\n/)

function checkTextHygiene(files) {
  for (const [name, mode] of files) {
    const path = join(ROOT, name)
    const suffix = extname(name)
    if (!TEXT_SUFFIXES.has(suffix) || basename(name) === 'LICENSE') continue
    const raw = readFileSync(path)
    if (raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf) fail(name, 'starts with a byte order mark')
    if (raw.includes('\r\n')) fail(name, 'has CRLF line endings, but .editorconfig requires LF')
    if (raw.length > 0 && raw.at(-1) !== 0x0a) fail(name, 'does not end with a new line')
    const content = raw.toString('utf8')
    lines(content).forEach((line, index) => {
      const number = index + 1
      if (DASHES.some((dash) => line.includes(dash))) {
        fail(`${name}:${number}`, 'contains an en or em dash: use a colon, a comma or a full stop')
      }
      // Skips quotations, because they keep the words of their source.
      const prose = ['.md', '.yml', '.yaml'].includes(suffix) && !['AGENTS.md', 'CLAUDE.md'].includes(name)
      if (prose && !line.trimStart().startsWith('>') && SECOND_PERSON.test(line)) {
        fail(`${name}:${number}`, 'uses the second person')
      }
    })
    // Checks the scripts of the repository, not the files of the test fixtures, which keep the names of their ecosystem.
    const script = suffix === '.sh' || (['.js', '.mjs'].includes(suffix) && !name.startsWith('test/fixtures/'))
    if (script) {
      if (!/^[a-z0-9_]+$/.test(basename(name, suffix))) fail(name, 'script name is not snake_case')
      if (mode !== '100755') fail(name, 'script does not have the executable bit')
    }
    if (suffix === '.yml' || suffix === '.yaml') {
      try {
        parse(content, { schema: 'failsafe' })
      } catch (error) {
        fail(name, `is not valid YAML: ${error.message}`)
      }
    }
  }
}

function checkInputsAreUsed(name, content, declared, kind, pattern) {
  // Removes the comments, because a step in a comment does not use an input.
  const code = lines(content).filter((line) => !line.trimStart().startsWith('#')).join('\n')
  const used = new Set([...code.matchAll(pattern)].map((match) => match[1]))
  const names = new Set(Object.keys(declared))
  const reserved = kind === 'input' ? new Set(RESERVED_INPUTS[name] ?? []) : new Set()
  for (const missing of [...used].filter((input) => !names.has(input)).sort()) {
    fail(name, `references the ${kind} '${missing}', but does not declare it`)
  }
  for (const unused of [...names].filter((input) => !used.has(input) && !reserved.has(input)).sort()) {
    fail(name, `declares the ${kind} '${unused}', but does not use it`)
  }
  for (const stale of [...reserved].filter((input) => used.has(input)).sort()) {
    fail(name, `lists the input '${stale}' in RESERVED_INPUTS, but uses it`)
  }
}

function checkAction(directory) {
  const path = join(directory, 'action.yml')
  const name = relative(path)
  const document = load(path)
  for (const key of ['name', 'description']) {
    if (!text(document[key]).trim()) fail(name, `has no ${key}`)
  }
  const runs = mapping(document.runs)
  if (runs.using !== 'composite') fail(name, 'is not a composite action')
  const inputs = mapping(document.inputs)
  for (const [inputName, spec] of Object.entries(inputs).map(([key, value]) => [key, mapping(value)])) {
    if (!text(spec.description).trim()) fail(name, `input '${inputName}' has no description`)
    if (spec.required === 'true' && 'default' in spec) {
      fail(name, `input '${inputName}' is required and has a default, but GitHub never uses that default`)
    }
  }
  checkInputsAreUsed(name, read(path), inputs, 'input', INPUT_REFERENCE)
  list(runs.steps).filter(isObject).forEach((step, index) => {
    if (!step.name) fail(name, `step ${index + 1} has no name`)
    // Accepts PowerShell, because Windows does not include bash.
    if ('run' in step && !['bash', 'pwsh'].includes(step.shell)) {
      fail(name, `step '${step.name ?? index + 1}' runs a script without 'shell: bash' or 'shell: pwsh', but a composite action requires a shell`)
    }
  })
}

function checkReusableWorkflow(path) {
  const name = relative(path)
  const document = load(path)
  if (!text(document.name).startsWith('Reusable - ')) fail(name, "name does not start with 'Reusable - '")
  const on = mapping(document.on)
  if (!('workflow_call' in on)) {
    fail(name, 'is not triggered by workflow_call')
    return
  }
  const call = mapping(on.workflow_call)
  const content = read(path)
  const inputs = mapping(call.inputs)
  for (const [inputName, spec] of Object.entries(inputs).map(([key, value]) => [key, mapping(value)])) {
    if (!text(spec.description).trim()) fail(name, `input '${inputName}' has no description`)
    if (!spec.type) fail(name, `input '${inputName}' has no type`)
  }
  checkInputsAreUsed(name, content, inputs, 'input', INPUT_REFERENCE)
  checkInputsAreUsed(name, content, mapping(call.secrets), 'secret', SECRET_REFERENCE)
  for (const step of stepsOf(document)) {
    const options = mapping(step.with)
    if (options.repository === SELF_REPOSITORY) {
      // Requires this ref, because without it the CI tests the workflow parts of the default branch instead of the commit.
      const expected = `github.repository == '${SELF_REPOSITORY}' && github.sha || inputs.workflow-parts-version`
      if (!text(options.ref).includes(expected)) fail(name, `checks out the workflow parts without '${expected}' as ref`)
    }
  }
}

function checkRunScripts(path, document) {
  const name = relative(path)
  for (const step of stepsOf(document)) {
    const script = step.run
    if (typeof script !== 'string') continue
    const label = `step '${step.name ?? '?'}'`
    for (const [, expression] of script.matchAll(EXPRESSION)) {
      // Applies also to inputs that contain shell code, because a script must run them from a variable with eval.
      if (UNSAFE_IN_RUN.test(expression)) {
        fail(name, `${label} writes '\${{ ${expression} }}' into its script: use an env variable, so that the value does not run as code`)
      }
    }
    if (/\$\?\s+-(eq|ne)/.test(script)) fail(name, `${label} tests $? after a command, but bash -e stops when the command fails`)
    // Removes the comments, because a command in a comment does not run.
    const code = lines(script).filter((line) => !line.trimStart().startsWith('#')).join('\n')
    const joined = code.replaceAll('\\\n', ' ')
    for (const [command] of joined.matchAll(/\bcurl\b[^\n|;&)]*/g)) {
      const flags = command.split(/\s+/).filter((token) => token.startsWith('-')).join(' ')
      if (!/(^|\s)(-[a-zA-Z]*[fw][a-zA-Z]*|--fail|--write-out)\b/.test(flags)) {
        fail(name, `${label} calls curl without --fail or --write-out, so curl can save an HTTP error page as the download`)
      }
    }
    if (code.includes('curl') && joined.includes(' -O ') && !script.includes('sha256sum --check')) {
      fail(name, `${label} downloads a file, but does not verify its SHA256 checksum`)
    }
  }
}

function shellcheckActions() {
  const directory = mkdtempSync(join(tmpdir(), 'workflow-parts-'))
  try {
    const scripts = new Map()
    for (const action of actionPaths()) {
      const document = load(join(action, 'action.yml'))
      list(mapping(document.runs).steps).filter(isObject).forEach((step, index) => {
        if (typeof step.run !== 'string' || step.shell !== 'bash') return
        const script = `${relative(action).replaceAll('/', '_')}_${index + 1}.sh`
        // Replaces each expression with a plain word, because the runner replaces expressions before bash runs.
        const body = step.run.replaceAll(EXPRESSION, 'expression_value')
        writeFileSync(join(directory, script), `#!/usr/bin/env bash\nset -eo pipefail\n${body}\n`)
        scripts.set(script, `${relative(join(action, 'action.yml'))} step '${step.name ?? index + 1}'`)
      })
    }
    if (scripts.size === 0) return
    const result = spawnSync('shellcheck', ['--shell=bash', '--format=gcc', ...[...scripts.keys()].sort()], { cwd: directory, encoding: 'utf8' })
    if (result.error) {
      fail('shellcheck', result.error.message)
      return
    }
    for (const line of result.stdout.split('\n').filter(Boolean)) {
      const separator = line.indexOf(':')
      const script = line.slice(0, separator)
      fail(scripts.get(script) ?? script, `shellcheck line ${line.slice(separator + 1).trim()}`)
    }
    if (![0, 1].includes(result.status)) fail('shellcheck', result.stderr.trim())
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
}

// Converts a local reference to the path of the action or workflow in this repository.
function localTarget(uses) {
  for (const prefix of ['./workflow-parts/', './.workflow-parts/', './']) {
    if (uses.startsWith(prefix)) return uses.slice(prefix.length).replace(/\/+$/, '')
  }
  return null
}

const callers = (document) => [...stepsOf(document), ...Object.values(mapping(document.jobs)).filter(isObject)].filter((item) => 'uses' in item)

function checkReferences(path, document) {
  const name = relative(path)
  lines(read(path)).forEach((line, index) => {
    if (line.includes('uses: actions/') && !PINNED_LINE.test(line)) {
      fail(`${name}:${index + 1}`, "must pin a first-party action to a full commit SHA, followed by two spaces and '# vX.Y.Z'")
    }
  })
  for (const item of callers(document)) {
    const uses = text(item.uses)
    const target = localTarget(uses)
    if (target === null) {
      // Accepts only first-party actions, because the actions of this repository download other tools and verify their checksum.
      if (!ACTION_REFERENCE.test(uses)) fail(name, `uses '${uses}', but only local actions and first-party actions pinned to a commit SHA are permitted`)
      continue
    }
    const targetPath = join(ROOT, target)
    const given = new Set(Object.keys(mapping(item.with)))
    let declared
    if (target.endsWith('.yml')) {
      if (!existsSync(targetPath)) {
        fail(name, `calls '${uses}', but it does not exist`)
        continue
      }
      declared = mapping(mapping(mapping(load(targetPath).on).workflow_call).inputs)
    } else {
      if (!existsSync(join(targetPath, 'action.yml'))) {
        fail(name, `uses '${uses}', but it does not exist`)
        continue
      }
      declared = mapping(load(join(targetPath, 'action.yml')).inputs)
    }
    for (const unknown of [...given].filter((input) => !(input in declared)).sort()) {
      fail(name, `passes '${unknown}' to '${uses}', but the target does not declare it`)
    }
    for (const [inputName, spec] of Object.entries(declared).map(([key, value]) => [key, mapping(value)])) {
      if (spec.required === 'true' && !('default' in spec) && !given.has(inputName)) {
        fail(name, `does not pass the required input '${inputName}' to '${uses}'`)
      }
    }
  }
}

function checkTimeouts(path, document) {
  // Requires a timeout, because GitHub stops a blocked job only after six hours.
  for (const [jobId, job] of Object.entries(mapping(document.jobs)).map(([key, value]) => [key, mapping(value)])) {
    if ('steps' in job && !('timeout-minutes' in job)) fail(relative(path), `job '${jobId}' runs steps without timeout-minutes`)
  }
}

function checkActionVersions() {
  const versions = new Map()
  for (const path of [...workflowPaths(), ...actionPaths().map((action) => join(action, 'action.yml'))]) {
    for (const step of stepsOf(load(path))) {
      const uses = text(step.uses)
      if (!ACTION_REFERENCE.test(uses)) continue
      const [action, version] = uses.split('@')
      if (!versions.has(action)) versions.set(action, new Map())
      const byVersion = versions.get(action)
      if (!byVersion.has(version)) byVersion.set(version, new Set())
      byVersion.get(version).add(relative(path))
    }
  }
  for (const [action, byVersion] of versions) {
    if (byVersion.size > 1) {
      const pins = [...byVersion].sort(([a], [b]) => a.localeCompare(b)).map(([version, files]) => `${version} in ${[...files].sort().join(', ')}`)
      fail(action, `is pinned to several versions: ${pins.join('; ')}`)
    }
  }
}

const parts = () => [
  ...actionPaths().map(relative),
  ...workflowPaths().filter((path) => basename(path).startsWith('reusable-')).map(relative),
]

function checkReadme() {
  const readme = read(join(ROOT, 'README.md'))
  const links = new Set([...readme.matchAll(/\]\(([^)#]+)\)/g)].map((match) => match[1]))
  for (const link of [...links].sort()) {
    if (!link.startsWith('http') && !existsSync(join(ROOT, link))) fail('README.md', `links to '${link}', but it does not exist`)
  }
  const linked = new Set([...links].map((link) => link.replace(/\/+$/, '').replace(/\/action\.yml$/, '')))
  for (const part of parts()) {
    if (!linked.has(part)) fail('README.md', `does not list '${part}'`)
  }
}

// Gives the result of a condition for the given inputs, or null when the condition is not a test of one known input.
function runsWith(condition, values) {
  let test = condition.trim()
  if (test.startsWith('${{') && test.endsWith('}}')) test = test.slice(3, -2).trim()
  const match = /^(!\s*)?inputs\.([A-Za-z0-9_-]+)(?:\s*(==|!=)\s*'([^']*)')?$/.exec(test)
  if (!match || !(match[2] in values) || values[match[2]].includes('${{')) return null
  const [, negation, name, operator, expected] = match
  const value = values[name]
  if (operator) return (value === expected) === (operator === '==')
  return !['', 'false', '0'].includes(value) !== Boolean(negation)
}

function declaredInputs(path) {
  const document = load(path)
  if ('runs' in document) return mapping(document.inputs)
  return mapping(mapping(mapping(document.on).workflow_call).inputs)
}

// Collects the parts that the CI workflow runs, directly or through the parts that it calls.
function exercisedParts() {
  const exercised = new Set()
  const pending = [[join(ROOT, '.github/workflows/ci.yml'), null]]
  while (pending.length > 0) {
    const [path, values] = pending.pop()
    for (const item of callers(load(path))) {
      const target = localTarget(text(item.uses))
      if (target === null) continue
      // Accepts all steps of the CI workflow, but accepts a step of a called part only when the inputs enable it.
      if (values !== null && 'if' in item && !runsWith(text(item.if), values)) continue
      const targetPath = target.endsWith('.yml') ? join(ROOT, target) : join(ROOT, target, 'action.yml')
      const calledWith = Object.fromEntries(Object.entries(declaredInputs(targetPath)).map(([key, spec]) => [key, text(mapping(spec).default)]))
      Object.assign(calledWith, mapping(item.with))
      exercised.add(target)
      pending.push([targetPath, calledWith])
    }
  }
  return exercised
}

function checkCoverage() {
  const exercised = exercisedParts()
  const all = parts()
  for (const part of all) {
    if (exercised.has(part) && part in UNTESTED_PARTS) fail(part, 'is tested by the CI: remove it from UNTESTED_PARTS')
    else if (!exercised.has(part) && !(part in UNTESTED_PARTS)) fail(part, 'is not tested by a CI job: add a test, or add it to UNTESTED_PARTS with the reason')
  }
  for (const part of Object.keys(UNTESTED_PARTS).filter((name) => !all.includes(name)).sort()) {
    fail(part, 'is listed in UNTESTED_PARTS, but does not exist')
  }
}

// Converts a shell pattern to a regular expression, as fnmatch does.
function globToRegExp(pattern) {
  const source = [...pattern].map((character) => {
    if (character === '*') return '.*'
    if (character === '?') return '.'
    return character.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }).join('')
  return new RegExp(`^${source}$`)
}

function checkIstarci() {
  const path = join(ROOT, '.istarci.yml')
  if (!existsSync(path)) return
  const config = load(path)
  const runner = mapping(config.runner)
  const jobs = Object.keys(mapping(load(join(ROOT, '.github/workflows/ci.yml')).jobs))
  const patterns = [
    ...Object.keys(mapping(runner.images)),
    ...list(runner.docker),
    ...list(mapping(config.workflow).skipJobs),
  ]
  for (const pattern of patterns) {
    const regExp = globToRegExp(pattern)
    if (!jobs.some((job) => regExp.test(job))) fail('.istarci.yml', `pattern '${pattern}' matches no job of the CI workflow`)
  }
}

function main() {
  checkTextHygiene(trackedFiles())
  for (const action of actionPaths()) {
    checkAction(action)
    const document = load(join(action, 'action.yml'))
    checkRunScripts(join(action, 'action.yml'), document)
    checkReferences(join(action, 'action.yml'), document)
  }
  for (const path of workflowPaths()) {
    const document = load(path)
    if (basename(path).startsWith('reusable-')) checkReusableWorkflow(path)
    checkRunScripts(path, document)
    checkReferences(path, document)
    checkTimeouts(path, document)
  }
  shellcheckActions()
  checkActionVersions()
  checkReadme()
  checkCoverage()
  checkIstarci()
  for (const failure of failures) console.log(`FAIL ${failure}`)
  console.log(`${failures.length} failure(s)`)
  return failures.length > 0 ? 1 : 0
}

process.exitCode = main()
