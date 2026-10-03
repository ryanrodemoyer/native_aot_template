# Agent Instructions

You are taking part in a benchmark. Your task is to implement everything in [BENCHMARK.md](BENCHMARK.md) and submit it as a pull request. Read both documents completely before you start.

## Operating Mode

- **Work fully autonomously.** Do not stop to ask questions. If something is ambiguous, make a reasonable decision, carry on, and record it (in `THOUGHTS.md` as you go, and in `SUBMISSION.md` at the end).
- You have the `git` and `gh` CLIs, plus the .NET 10 SDK on your local machine. CI on GitHub Actions is the source of truth for the platforms you cannot run locally.
- There is no hard time or turn limit. Efficiency is recorded (BENCHMARK.md §5.5), so avoid needless CI churn. Run builds and tests locally before you push.
- You are **done** when every hard gate in BENCHMARK.md §5.1 is met and you have pushed your final commit. If CI fails, read the logs (`gh run view --log-failed`), fix the problem, and push again.

## Setup

Create an isolated worktree and branch from `main`. Pick a branch name that identifies you:

```sh
git fetch origin main
git worktree add ../native_aot_template-<agent>-<model> -b submission/<agent>-<model>-<yyyymmdd> origin/main
cd ../native_aot_template-<agent>-<model>
benchmark/scripts/thought.sh start "Read the benchmark docs; starting."
```

Example branch name: `submission/claude-code-opus-20261003`. Do all work inside this worktree.

## Process Artifacts

All process files live in `submission/` at the repository root, so template users can delete the whole folder.

### 1. `submission/PLAN.md` (before any code)

Your **first commit** on the branch must contain only `submission/PLAN.md` and `submission/THOUGHTS.md`. Evaluators check the commit order. The plan must include:

- **Understanding**: the requirements in your own words, and any ambiguities you found, with your resolution.
- **Architecture**: projects, their responsibilities, and how they depend on each other.
- **Risks**: the Native AOT, cryptography, and cross-platform pitfalls you expect, and how you will avoid or detect them.
- **Task breakdown**: a table of tasks, each with an ID, description, dependencies, and acceptance criteria.
- **Task DAG**: a Mermaid `flowchart` of the same tasks, showing dependencies and which tasks can run in parallel.
- **Test strategy**: what is tested at the unit, E2E, and headless UI levels.

Do not rewrite the original plan later. At the end, **append** a `## Plan vs. Actual` section: what changed, what took longer than expected, what you would do differently.

### 2. `submission/THOUGHTS.md` (throughout)

An append-only, timestamped log. **Every entry must be written with the provided script**, never by hand:

```sh
benchmark/scripts/thought.sh <category> "message"
printf 'multi-line\nmessage\n' | benchmark/scripts/thought.sh <category> -
benchmark/scripts/thought.sh --verify          # check the hash chain
# Windows / PowerShell: benchmark/scripts/thought.ps1 <category> "message"  (and -Verify)
```

The script records the real UTC time, your current commit, and a hash chain. Hand edits break the chain, and evaluators verify it.

Categories: `start`, `plan`, `decision`, `attempt`, `failure`, `fix`, `pivot`, `ci`, `note`, `end`.

**Log, at minimum:**
- `start`, once, right after setup. `end`, once, after your final push.
- Each significant `decision`, with the alternatives you considered.
- Each `failure` (local or CI) with the root cause, and the matching `fix`.
- Each `pivot`, when you abandon an approach.
- Each `ci` run you trigger, and its outcome.

Keep entries concise and genuine. Do not log routine steps. Commit `THOUGHTS.md` together with your regular commits.

### 3. `submission/SUBMISSION.md` (at the end)

Use the template at the bottom of this document. It is also the PR body.

## Integrity Rules (violation = disqualification)

Other agents are submitting to the same repository. **Your work must be your own.**

**You must not:**
- Fetch, check out, diff, log, or read any branch other than `main` and your own. Do not run `git fetch --all`, `git fetch origin` without a refspec, `git branch -r`, `git log --all`, or `git ls-remote` on other refs.
- Open, list, or read other worktrees on disk (for example sibling `../native_aot_template-*` directories), or run `git worktree list`.
- List or view other pull requests, issues, Actions runs, or artifacts. Do not run unfiltered `gh pr list`, `gh run list`, or `gh api` calls against them, and do not browse the repo's GitHub web pages for them.
- Search the web for, or copy from, other submissions to this benchmark.

**You may:**
- Use `main` (`git fetch origin main`) and your own branch.
- Use `gh pr create`, `gh pr view <your-pr>`, `gh pr checks <your-pr>`, `gh run list --branch <your-branch>`, `gh run view <your-run-id>`, `gh run watch`, and `gh workflow run <workflow> --ref <your-branch>`.
- Read public documentation, package sources, and samples that have nothing to do with this benchmark (Microsoft Learn, Avalonia docs, GitHub repos of the libraries you use, and so on).

**You must also not:**
- Push to `main`, merge any PR, push tags, create releases, deploy GitHub Pages, or change repository settings, secrets, or branch protection.
- Modify anything under `benchmark/`, or the root `AGENTS.md` pointer file.
- Disable, skip, or delete tests, or add `continue-on-error`, to make CI pass.
- Write or edit `THOUGHTS.md` entries by hand, or fabricate timestamps.

## Submission

1. Commit in small, meaningful steps with clear messages. Never commit build output (`bin/`, `obj/`, `artifacts/`, publish folders).
2. Push your branch and open a PR to `main`:
   ```sh
   gh pr create --base main --head submission/<...> --title "[Submission] <agent> / <model>" --body-file submission/SUBMISSION.md
   ```
3. Trigger the release dry run on your branch: `gh workflow run release.yml --ref <your-branch> -f dry-run=true`. Then confirm it is green.
4. Make sure `ci.yml` is green on the PR's latest commit, on all three platforms.
5. Append `## Plan vs. Actual` to `PLAN.md`. Finalize `SUBMISSION.md`. Log the `end` entry and run `thought.sh --verify`. Then commit, push, update the PR body (`gh pr edit <pr> --body-file submission/SUBMISSION.md`), and stop.

## SUBMISSION.md Template

```markdown
# Submission

## Identity
- Agent / harness:
- Model:
- Branch:
- PR:

## Metrics
- Start (from THOUGHTS.md `start` entry):
- End (from THOUGHTS.md `end` entry):
- CI runs triggered:
- Human interventions: (count and describe each; target 0)
- Tokens / cost (if available):

## Evidence
- Final green `ci.yml` run: <link>
- Green `release.yml` dry run: <link>
- `thought.sh --verify` output:

## Decisions & Assumptions
<!-- Every ambiguity you resolved and why. Any deviations from the suggested layout. -->

## Dependencies
| Package | Version | Used by | Justification | AOT compatible? |
|---|---|---|---|---|

## Warning Suppressions
<!-- Every NoWarn / pragma / UnconditionalSuppressMessage, with justification. "None" if none. -->

## Bonus Items Attempted

## Known Issues & Gaps
<!-- Be honest. Undisclosed gaps found by evaluators are penalized more than disclosed ones. -->

## Self-Assessment
| # | Category | Max | Self-score | Notes |
|---|---|---|---|---|
| 1 | Core & security correctness | 15 | | |
| 2 | Native AOT correctness | 13 | | |
| 3 | Tests | 13 | | |
| 4 | CI/CD | 12 | | |
| 5 | CLI functionality | 10 | | |
| 6 | GUI functionality | 10 | | |
| 7 | Distribution | 7 | | |
| 8 | Documentation | 6 | | |
| 9 | Shared architecture | 5 | | |
| 10 | Process | 5 | | |
| 11 | Template hygiene | 4 | | |
| | Bonus | +10 | | |

## Integrity Attestation
I confirm that I did not access other branches, worktrees, pull requests, Actions runs, or artifacts belonging to other submissions, that every THOUGHTS.md entry was written by the provided script, and that this work is my own.
```
