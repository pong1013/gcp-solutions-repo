#!/bin/bash
# ============================================================
# Step 4F: 上傳本機 SQLX 到 Dataform workspace
# 使用 Dataform REST API 寫入檔案
# ============================================================

set -e

# ── 設定變數 ──────────────────────────────────────────────
PROJECT_ID="complete-498806"
LOCATION="us-central1"
REPOSITORY="crm-complete"
WORKSPACE="dev-step4"
DATAFORM_DIR="$(cd "$(dirname "$0")/../dataform" && pwd)"

BASE_URL="https://dataform.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${LOCATION}/repositories/${REPOSITORY}/workspaces/${WORKSPACE}"

# ── 取得 Access Token ─────────────────────────────────────
echo "🔐 取得 GCP Access Token..."
TOKEN=$(gcloud auth print-access-token)

# ── 函數：上傳單一檔案 ────────────────────────────────────
upload_file() {
  local local_path="$1"   # 本機完整路徑
  local remote_path="$2"  # Dataform workspace 內的路徑

  echo "  ⬆️  上傳: ${remote_path}"

  # Base64 encode 檔案內容
  local content
  content=$(base64 < "$local_path")

  # 呼叫 Dataform API: writeFile
  local response
  response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}:writeFile" \
    -d "{
      \"path\": \"${remote_path}\",
      \"contents\": \"${content}\"
    }")

  local http_status
  http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
  local body
  body=$(echo "$response" | grep -v "HTTP_STATUS:")

  if [[ "$http_status" == "200" ]]; then
    echo "     ✅ 成功"
  else
    echo "     ❌ 失敗 (HTTP ${http_status})"
    echo "     回應: ${body}"
    return 1
  fi
}

# ── 確認 workspace 存在 ───────────────────────────────────
echo ""
echo "📋 確認 workspace 存在: ${WORKSPACE}"
WS_CHECK=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}")
WS_STATUS=$(echo "$WS_CHECK" | grep "HTTP_STATUS:" | cut -d: -f2)

if [[ "$WS_STATUS" != "200" ]]; then
  echo "❌ Workspace '${WORKSPACE}' 不存在或無法存取"
  echo "   請先在 Dataform Console 建立 workspace"
  exit 1
fi
echo "✅ Workspace 存在"

# ── 開始上傳 ──────────────────────────────────────────────
echo ""
echo "📂 開始上傳檔案..."
echo "   本機來源: ${DATAFORM_DIR}"
echo "   目標 repo: ${REPOSITORY} / ${WORKSPACE}"
echo ""

# 1. workflow_settings.yaml
upload_file "${DATAFORM_DIR}/workflow_settings.yaml" "workflow_settings.yaml"

# 2. package.json
upload_file "${DATAFORM_DIR}/package.json" "package.json"

# 3. definitions/staging/
for f in "${DATAFORM_DIR}/definitions/staging/"*.sqlx; do
  filename=$(basename "$f")
  upload_file "$f" "definitions/staging/${filename}"
done

# 4. definitions/curated/
for f in "${DATAFORM_DIR}/definitions/curated/"*.sqlx; do
  filename=$(basename "$f")
  upload_file "$f" "definitions/curated/${filename}"
done

# 5. definitions/mart/
for f in "${DATAFORM_DIR}/definitions/mart/"*.sqlx; do
  filename=$(basename "$f")
  upload_file "$f" "definitions/mart/${filename}"
done

# 6. definitions/assertions/
for f in "${DATAFORM_DIR}/definitions/assertions/"*.sqlx; do
  filename=$(basename "$f")
  upload_file "$f" "definitions/assertions/${filename}"
done

echo ""
echo "🎉 所有檔案上傳完成！"
echo ""
echo "📌 下一步："
echo "   1. 前往 Dataform Console: https://console.cloud.google.com/bigquery/dataform"
echo "   2. 進入 repository '${REPOSITORY}' > workspace '${WORKSPACE}'"
echo "   3. 點選 'Compile' 確認無 SQLX 錯誤"
echo "   4. 點選 'Commit & Push' 提交到 main branch"
