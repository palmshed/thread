# CircleCI

CircleCI is kept for platform jobs that do not need to run on every local change.

The main repo checks live in GitHub Actions. CircleCI should stay quiet unless a job really needs it.

## Required Secrets

Set these in the CircleCI project if Docker or coverage jobs are enabled:

```bash
DOCKERHUB_USERNAME=<dockerhub-user>
DOCKERHUB_PASSWORD=<dockerhub-token>
CODECOV_TOKEN=<codecov-token>
```

## Validate The Config

Install the CircleCI CLI, then run:

```bash
circleci config validate .circleci/config.yml
```

The local helper does the same check when the CLI is installed:

```bash
bash scripts/validate-circleci.sh
```

If the CLI is missing locally, the helper prints a warning and exits cleanly. In CI, missing validation tooling should fail.
