# Select validation commands

Use this procedure from the test, review, and test-writing skills.

1. Read project instructions and validation wrappers first. Inspect Makefile
   targets, package scripts, and CI configuration. A documented project wrapper
   takes precedence over the examples below. Honor working directories,
   environment setup, and test database rules.
2. Identify the requested scope and affected workspaces. Include staged,
   unstaged, and relevant untracked files when selecting checks for a change.
3. Select one command per distinct suite. Record command, workspace, and scope
   before execution. Do not run aliases of the same suite or repeat a broad
   suite through a second skill.
4. Use the project's package manager and installed tools. Do not download a
   runner just because its config exists. A missing selected tool or required
   service is a failure with the exact missing item.

## Runner evidence

| Evidence | Runner | Selection |
|----------|--------|-----------|
| Documented wrapper or Makefile target | Project command | Use the relevant target, including shell regression tests such as `make test-hooks`. |
| pytest configuration or existing pytest tests | pytest | Use configured test paths. Split unit and integration by project markers or directories. Use `uv run` when the project uses uv. |
| Existing unittest suite | unittest | Use the project's discovery command and actual test directory. |
| `package.json` scripts | Project package manager | Inspect script bodies and select the script for the requested scope once. |
| Installed Jest and its configuration | Jest | Use the configured project and requested test paths. |
| Installed Vitest and its configuration | Vitest | Use `vitest run` with the project's package manager. |
| `Cargo.toml` | cargo | Use `cargo test` for the requested package or test. |
| `go.mod` | go | Use `go test` for the requested packages. |
| Playwright or Cypress configuration | Browser tests | Use the project wrapper, service setup, and test environment. |

A `tests/` directory or a `pyproject.toml` without test configuration does not
prove that pytest is the runner. Shell changes can affect hook, bootstrap, or
command regression tests. Inspect the project before excluding them.

## Scope and execution

- Unit: select unit suites only. Do not treat a mixed suite as unit-only unless
  the project defines it that way.
- Integration: select the configured marker, directory, or script. These are
  alternatives, not consecutive attempts. An empty collection does not pass.
- Browser: select the applicable script once. Do not automatically run a broader
  suite after a restricted suite. Use test services unless another target is
  explicitly authorized.
- Full gate: include applicable format checks, lint, type checks, unit tests,
  and integration tests. Prefer a project quality-gate wrapper. Inspect what it
  runs so child workflows do not repeat those suites.

Do not use `--if-present` for selected scripts. Do not try another runner or
broader suite because the selected command failed. Diagnose that failure.

Run checks without editing or staging files by default. Complete authorized
auto-fixes before launching checks that read those files. Parallelize only
checks with independent inputs and services. Respect available agent slots and
project resource limits. Use batches or sequential execution when needed.

Report commands, workspaces, and observed results. Use PASS, FAIL, or NOT
APPLICABLE. NOT APPLICABLE requires evidence that a scope has no suite or tool
requirement. A missing selected tool, skipped required check, empty collection,
or unrun command is not PASS. Do not repeat a passing suite unless a later
change affects its inputs or new evidence requires another run.
