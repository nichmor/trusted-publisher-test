# trusted-publisher-test

A throwaway pixi project used to exercise prefix.dev's trusted-publishing
(OIDC) flow end-to-end from GitHub Actions. Based on the
[`cpp-sdl` example](https://github.com/prefix-dev/pixi/tree/main/examples/cpp-sdl).

## What's here

- `pixi.toml` — pixi workspace + `[package]` section using the
  `pixi-build-cmake` backend, so `pixi build` / `pixi publish` produces
  a `.conda`.
- `CMakeLists.txt` + `src/main.cc` — minimal SDL2 executable.
- `.github/workflows/publish.yml` — runs `pixi publish` from GitHub
  Actions, relying on GitHub's OIDC token instead of an API key.

## One-time setup

1. **Push this repo to GitHub** under some `OWNER/REPO`
   (already: `nichmor/trusted-publisher-test`).
2. **Register the trusted publisher** on the prefix.dev instance you're
   testing. For the preview env this is
   `https://preview-pr-2140.prefix.dev` → channel `jora` → Repository
   access, with:
   - `repository_owner` = `nichmor`
   - `repository_name`  = `trusted-publisher-test`
   - `workflow_filename` = `publish.yml`
3. **Edit `PREFIX_CHANNEL_URL`** in `.github/workflows/publish.yml` if
   you want to point at a different env or channel.
4. Commit + push to `main` (or trigger the workflow manually). The job
   should build the `.conda` via `pixi build`, mint a publisher token,
   and upload it.

## How it works (high level)

Reference: [pixi deployment docs](https://pixi.prefix.dev/latest/deployment/prefix/).

```
GitHub Actions runner
   │
   │ 1. GET $ACTIONS_ID_TOKEN_REQUEST_URL?audience=prefix.dev
   ▼
GitHub OIDC issuer ── signed JWT (aud=prefix.dev) ──┐
                                                    │
   2. POST {token: <jwt>} ──────────────────────────┘
   ▼
<PREFIX_CHANNEL_URL host>/api/oidc/mint_token
   │  validates issuer + audience + (owner, repo, workflow)
   │  looks up the registered publisher
   ▼  returns a short-lived JWT (aud=https://prefix.dev/upload)
GitHub Actions runner
   │ 3. pixi publish uploads the built .conda using the minted JWT
   ▼
<PREFIX_CHANNEL_URL>/...
```

If step 2 fails with `OIDCPublisherNotFound`, the `(owner, repo, workflow)`
triple sent by the runner doesn't match what's registered in the channel
settings — re-check the workflow filename especially (must be exactly
`publish.yml`, not the full path).

## Local sanity checks

```bash
# Build the package locally with pixi (produces a .conda under ./output)
pixi build --output-dir ./output

# Or, publish locally using a stored API key instead of OIDC:
pixi auth login --token "$PREFIX_API_KEY" https://preview-pr-2140.prefix.dev
pixi publish https://preview-pr-2140.prefix.dev/nichmor/jora
```

## Tweaking the test surface

To exercise specific paths in the scoped-API-keys / trusted-publisher PR:

- **Bad workflow name**: rename `publish.yml` → `release.yml` and push
  without updating the publisher registration → expect
  `401 Failed to find OIDC publisher`.
- **Wrong channel**: change `PREFIX_CHANNEL_URL` to a channel the
  publisher is NOT registered for → expect 403 from the upload endpoint.
- **Re-upload same artifact**: run the workflow twice → second run
  should 409 unless `--skip-existing` is passed.
