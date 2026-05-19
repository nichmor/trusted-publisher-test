#!/usr/bin/env bash
# Scope matrix for PR #2140 trusted-publisher tests.
# Runs inside a GitHub Actions workflow that has `id-token: write`.
# Expects env: ACTIONS_ID_TOKEN_REQUEST_URL, ACTIONS_ID_TOKEN_REQUEST_TOKEN, BACKEND.
set -uo pipefail

BACKEND=${BACKEND:-https://beta.prefix.dev}
IN_SCOPE_CHANNEL=${IN_SCOPE_CHANNEL:-a-channel}
OUT_OF_SCOPE_CHANNEL=${OUT_OF_SCOPE_CHANNEL:-graf}
IN_SUBDIR=${IN_SUBDIR:-linux-aarch64}
IN_FILE=${IN_FILE:-python-3.14.2-hb06a95a_102_cp314.conda}
OUT_SUBDIR=${OUT_SUBDIR:-noarch}
OUT_FILE=${OUT_FILE:-empty-0.1.0-h4616a5c_0.conda}
UPLOAD_NAME=${UPLOAD_NAME:-pixi-build-api-version-2-hc364b38_0.conda}

echo "=== Step 1: get GitHub OIDC token ==="
GH_OIDC=$(curl -sS "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=prefix.dev" \
  -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" | jq -r .value)
if [ -z "${GH_OIDC}" ] || [ "${GH_OIDC}" = "null" ]; then
  echo "FATAL: could not get GitHub OIDC token"; exit 1
fi
echo "::add-mask::${GH_OIDC}"
echo "got GH OIDC, ${#GH_OIDC} chars"

echo
echo "=== Step 2: exchange via ${BACKEND}/api/oidc/mint_token ==="
EX_BODY=$(jq -nc --arg t "${GH_OIDC}" '{token:$t}')
EX_RESP=$(curl -sS -o /tmp/mint.body -w "%{http_code}" \
  -X POST "${BACKEND}/api/oidc/mint_token" \
  -H "Content-Type: application/json" \
  -d "${EX_BODY}")
echo "mint_token http: ${EX_RESP}"
if [ "${EX_RESP}" != "200" ]; then
  echo "mint_token failed body:"
  cat /tmp/mint.body
  exit 1
fi
PFX_JWT=$(cat /tmp/mint.body)
echo "::add-mask::${PFX_JWT}"
if [[ "${PFX_JWT}" != pfx-jwt.* ]]; then
  echo "FATAL: minted token doesn't start with pfx-jwt.: ${PFX_JWT:0:30}..."; exit 1
fi
echo "got prefix-dev JWT, ${#PFX_JWT} chars"

probe() {
  local LABEL=$1 METHOD=$2 URL=$3
  shift 3
  local CODE
  CODE=$(curl -sS -o /tmp/last.body -w "%{http_code}" \
    -X "${METHOD}" "${URL}" \
    -H "Authorization: Bearer ${PFX_JWT}" "$@")
  local BODY
  BODY=$(head -c 200 /tmp/last.body | tr -d '\n')
  printf '[%-32s] %-6s %-90s -> %s | %s\n' "${LABEL}" "${METHOD}" "${URL#${BACKEND}}" "${CODE}" "${BODY:0:120}"
}

echo
echo "=== Step 3: download a tiny test package for upload tests ==="
curl -sSL -o /tmp/upload.conda \
  "https://conda.anaconda.org/conda-forge/noarch/${UPLOAD_NAME}"
SIZE=$(wc -c < /tmp/upload.conda)
SHA=$(sha256sum /tmp/upload.conda | awk '{print $1}')
echo "have ${UPLOAD_NAME}: ${SIZE} bytes, sha=${SHA:0:16}..."

echo
echo "=== Step 4: matrix ==="

echo "--- Reads (repodata) ---"
probe "read repodata IN-SCOPE"  GET "${BACKEND}/${IN_SCOPE_CHANNEL}/${IN_SUBDIR}/repodata.json"
probe "read repodata OUT-OF-SCOPE" GET "${BACKEND}/${OUT_OF_SCOPE_CHANNEL}/${OUT_SUBDIR}/repodata.json"

echo
echo "--- Reads (package download) ---"
probe "download pkg IN-SCOPE"   GET "${BACKEND}/${IN_SCOPE_CHANNEL}/${IN_SUBDIR}/${IN_FILE}"
probe "download pkg OUT-OF-SCOPE" GET "${BACKEND}/${OUT_OF_SCOPE_CHANNEL}/${OUT_SUBDIR}/${OUT_FILE}"

echo
echo "--- Upload ---"
probe "upload IN-SCOPE"  POST "${BACKEND}/api/v1/upload/${IN_SCOPE_CHANNEL}" \
  -H "Content-Type: application/octet-stream" \
  -H "Content-Length: ${SIZE}" \
  -H "X-File-Name: ${UPLOAD_NAME}" \
  -H "X-File-SHA256: ${SHA}" \
  --data-binary "@/tmp/upload.conda"
probe "upload OUT-OF-SCOPE" POST "${BACKEND}/api/v1/upload/${OUT_OF_SCOPE_CHANNEL}" \
  -H "Content-Type: application/octet-stream" \
  -H "Content-Length: ${SIZE}" \
  -H "X-File-Name: ${UPLOAD_NAME}" \
  -H "X-File-SHA256: ${SHA}" \
  --data-binary "@/tmp/upload.conda"

echo
echo "--- Yank / Unyank ---"
probe "yank IN-SCOPE"    POST "${BACKEND}/api/v1/yank/${IN_SCOPE_CHANNEL}/${IN_SUBDIR}/${IN_FILE}" \
  -H "Content-Type: application/json" -d '{"reason":"scope-matrix-test"}'
probe "unyank IN-SCOPE"  POST "${BACKEND}/api/v1/unyank/${IN_SCOPE_CHANNEL}/${IN_SUBDIR}/${IN_FILE}" \
  -H "Content-Type: application/json" -d '{}'
probe "yank OUT-OF-SCOPE" POST "${BACKEND}/api/v1/yank/${OUT_OF_SCOPE_CHANNEL}/${OUT_SUBDIR}/${OUT_FILE}" \
  -H "Content-Type: application/json" -d '{"reason":"scope-matrix-test"}'

echo
echo "--- Delete ---"
# Try deleting the uploaded test package on the in-scope channel. May or may not
# exist depending on whether upload above succeeded.
probe "delete IN-SCOPE"  DELETE "${BACKEND}/api/v1/delete/${IN_SCOPE_CHANNEL}/${OUT_SUBDIR}/${UPLOAD_NAME}"
probe "delete OUT-OF-SCOPE" DELETE "${BACKEND}/api/v1/delete/${OUT_OF_SCOPE_CHANNEL}/${OUT_SUBDIR}/${OUT_FILE}"

echo
echo "=== matrix done ==="
