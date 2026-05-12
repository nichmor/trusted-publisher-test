# trusted-publisher-test

A throwaway Python package used to exercise prefix.dev's trusted-publishing
(OIDC) flow end-to-end from GitHub Actions.

## What's here

- `src/hello_trusted/` — a tiny Python module with a `hello-trusted` CLI.
- `pyproject.toml` — hatch-based build config (so `pip install .` works).
- `recipe/recipe.yaml` — rattler-build recipe producing a `noarch: python` conda package.
- `.github/workflows/publish.yml` — builds the conda package and uploads it
  via `rattler-build upload prefix`, relying on GitHub's OIDC token instead of
  an API key.

## One-time setup

1. **Push this repo to GitHub** under some `OWNER/REPO`.
2. **Register the trusted publisher** on the prefix.dev instance you're testing:
   - Channel settings → *Repository access* (the new name introduced in commit
     `395666a6`, was previously *Trusted publishers*).
   - Add a GitHub publisher with:
     - `repository_owner` = `OWNER`
     - `repository_name`  = `REPO`
     - `workflow_filename` = `publish.yml`
   - Save it against the channel you want to upload to.
3. **Edit `.github/workflows/publish.yml`** and replace the two env vars at
   the top:
   - `PREFIX_SERVER_URL` → `https://<your-staging-host>`
   - `PREFIX_CHANNEL`    → `<your-channel>`
4. Commit + push to `main` (or trigger the workflow manually via the Actions
   tab). The job should:
   - build `output/noarch/hello-trusted-0.1.0-pyh<hash>_0.conda`
   - mint a publisher token via `/api/oidc/mint_token`
   - upload the artifact and exit `0`.

## How it works (high level)

```
GitHub Actions runner
   │
   │ 1. GET $ACTIONS_ID_TOKEN_REQUEST_URL?audience=prefix.dev
   ▼
GitHub OIDC issuer ── signed JWT (aud=prefix.dev) ──┐
                                                    │
   2. POST {token: <jwt>} ──────────────────────────┘
   ▼
$PREFIX_SERVER_URL/api/oidc/mint_token
   │  validates issuer + audience + (owner, repo, workflow)
   │  looks up the registered publisher
   ▼  returns a short-lived JWT (aud=https://prefix.dev/upload)
GitHub Actions runner
   │ 3. POST .conda with Authorization: Bearer <minted jwt>
   ▼
$PREFIX_SERVER_URL/api/v1/upload/<channel>
```

If step 2 fails with `OIDCPublisherNotFound`, the `(owner, repo, workflow)`
triple sent by the runner doesn't match what's registered in the channel
settings — re-check the workflow filename especially (it must be exactly
`publish.yml`, not the full path).

## Local sanity checks (no upload)

```bash
# Build the wheel locally
pip install hatchling build
python -m build

# Build the conda package locally with rattler-build
rattler-build build --recipe recipe/recipe.yaml --output-dir output
```

## Tweaking the test surface

To test specific paths in the scoped-API-keys PR:

- **Bad workflow name**: temporarily rename `publish.yml` → `release.yml` and
  push without updating the publisher registration → expect `401 Failed to find
  OIDC publisher`.
- **Wrong channel**: change `PREFIX_CHANNEL` to a channel the publisher is
  NOT registered for → expect 403 from the upload endpoint (channel-scope
  rejection — exercises the scoping logic in `auth/src/permissions/`).
- **Re-upload same artifact**: run the workflow twice → second run should
  409 unless `--skip-existing` is added to the upload step.
