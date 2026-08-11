# GitHub Label Workflows Design

## Goal

Make the shared GitHub skills apply appropriate existing repository labels when they create a pull request, create an issue, or begin work on an issue that has no labels.

## Current Behavior

- `create-pr` creates a pull request without label discovery, label arguments, or label verification.
- There is no shared skill for creating a GitHub issue.
- `complete-github-issue` reads issue labels but does not add labels when they are absent.
- The dotfiles test suite does not check label behavior in these skills.

## Approved Design

Use a short, direct label contract in each affected skill. Do not add a shared sub-skill or an automated label-classification script.

The contract is:

1. Run `gh label list --limit 200 --json name,description` before creating or updating the GitHub item.
2. Select all clearly applicable existing labels from the item title, body, linked issue, and changed files.
3. Prefer labels that describe work type and affected area when those labels exist.
4. Use exact existing label names. Never create, rename, or guess a label.
5. Do not remove a label that a person already applied.
6. If no existing label clearly applies, continue without a label and report that no match exists.
7. Verify the saved labels with `gh pr view ... --json labels` or `gh issue view ... --json labels`.

## Skill Changes

### Create Pull Request

Add label discovery after PR context collection. Add one `--label` argument for each selected label to `gh pr create`. Verify the labels after creation and include them in the success report.

### Create GitHub Issue

Add a new user-invoked skill. It will collect issue requirements, search for duplicates, build a structured issue body, discover existing labels, create the issue with all clear labels, and verify the saved labels.

### Complete GitHub Issue

Read the issue as JSON so labels can be checked exactly. If the issue has no labels, discover repository labels and add all clear matches before implementation reconnaissance. If it has labels, retain them and add only clearly missing labels. Verify the final label list.

## Test Design

1. Run baseline agent evaluations against the current skills for PR creation, issue creation, and completion of an unlabeled issue. Record the exact label omissions.
2. Add static dotfiles tests that require label discovery, label application, and label verification commands in each skill.
3. Run the static tests and confirm they fail before the skill changes.
4. Apply the minimal skill changes.
5. Run fresh agent evaluations with the changed skills and confirm each workflow applies labels correctly.
6. Run the complete dotfiles validation suite.

## Safety

- The workflows use only labels that already exist in the target repository.
- The workflows do not delete labels.
- The workflows do not create repository labels.
- Existing unrelated dotfiles changes are not staged or committed.
