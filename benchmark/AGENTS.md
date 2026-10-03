# Agent Instructions

You are taking part in a benchmark. Your task is to implement everything in [BENCHMARK.md](BENCHMARK.md) and submit it as a pull request. Read both documents completely before you start.

## Operating Mode

- **Work fully autonomously.** Do not stop to ask questions. If something is ambiguous, make a reasonable decision, carry on, and record the decision in `SUBMISSION.md`.
- You have the `git` and `gh` CLIs, plus the .NET 10 SDK on your local machine. CI on GitHub Actions is the source of truth for the platforms you cannot run locally.
- There is no hard time or turn limit. Efficiency is recorded (BENCHMARK.md §5.5), so avoid needless CI churn. Run builds and tests locally before you push.
- You are **done** when every hard gate in BENCHMARK.md §5.1 is met and you have pushed your final commit. If CI fails, read the logs (`gh run view --log-failed`), fix the problem, and push again.

## Setup

Create an isolated worktree and branch from `main`. Pick a branch name that identifies you:

```sh
git fetch origin main
git worktree add ../native_aot_template-<agent>-<model> -b submission/<agent>-<model>-<yyyymmdd> origin/main
cd ../native_aot_template-<agent>-<model>
```

Example branch name: `submission/claude-code-opus-20261003`. Do all work inside this worktree.

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

## Submission

1. Commit in small, meaningful steps with clear messages. Never commit build output (`bin/`, `obj/`, `artifacts/`, publish folders).
2. Push your branch and open a PR to `main`:
   ```sh
   gh pr create --base main --head submission/<...> --title "[Submission] <agent> / <model>" --body-file SUBMISSION.md
   ```
3. Trigger the release dry run on your branch: `gh workflow run release.yml --ref <your-branch> -f dry-run=true`. Then confirm it is green.
4. Make sure `ci.yml` is green on the PR's latest commit, on all three platforms.
5. Update `SUBMISSION.md` (and the PR body) with final metrics and run links. Then stop.

## SUBMISSION.md Template

Put this file at the repository root of your branch.

```markdown
# Submission

## Identity
- Agent / harness:
- Model:
- Branch:
- PR:

## Metrics
- Start (ISO 8601):
- End (ISO 8601):
- CI runs triggered:
- Human interventions: (count and describe each; target 0)
- Tokens / cost (if available):

## Evidence
- Final green `ci.yml` run: <link>
- Green `release.yml` dry run: <link>

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
| 1 | Native AOT correctness | 15 | | |
| 2 | CI/CD | 15 | | |
| 3 | CLI functionality | 12 | | |
| 4 | GUI functionality | 10 | | |
| 5 | Tests | 15 | | |
| 6 | Shared architecture | 8 | | |
| 7 | Distribution | 8 | | |
| 8 | Documentation | 10 | | |
| 9 | Template hygiene | 7 | | |
| | Bonus | +10 | | |

## Integrity Attestation
I confirm that I did not access other branches, worktrees, pull requests, Actions runs, or artifacts belonging to other submissions, and that this work is my own.
```
