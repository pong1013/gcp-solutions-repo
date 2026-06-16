# Step 4 - Transform Data With Dataform

Step 4 的目標是用 Dataform 把 Step 2/3 已經進 BigQuery `raw` dataset 的資料，轉成 `staging`、`curated`、`mart` 三層 business tables。這一步不是把 SQL 貼在 BigQuery Console 跑一次，而是把 transformation code 放進 repo，讓 SQL 可以被 PR review、版本控管、重跑、加 assertions，後面 Step 5 Dataplex quality gate 和 Step 6 ML/Salesforce activation 才有穩定輸入。

這一步目前已補 Terraform scaffold 和 Dataform SQLX scaffold。Terraform 會建立 GCP resources；Dataform SQLX code 仍需要你匯入/commit 到 Dataform repository 後，才會由 Dataform workflow 真正執行。

## 這一步在哪裡做

- Dataform project code：`complete/dataform/`
- Terraform resources：`complete/terraform/dataform.tf`
- Terraform variables：`complete/terraform/variables.tf`
- Terraform APIs/service identity：`complete/terraform/apis.tf`、`complete/terraform/service_identity.tf`
- Raw inputs：
  - `complete-498806.raw.crm_sales`
  - `complete-498806.raw.crm_support`
  - `complete-498806.raw.crm_campaign_events`
  - `complete-498806.raw.crm_new_partner_leads`
  - `complete-498806.raw.APP_USER_RAW`
- Outputs：
  - `complete-498806.staging`
  - `complete-498806.curated`
  - `complete-498806.mart`
  - assertions/audit evidence in `complete-498806.audit`

## 這一步會建立/設定什麼

Terraform 會建立：

- `dataform.googleapis.com` API。
- Dataform service identity，讓 Dataform 服務可以代表 workflow runner 執行。
- Dataform repository：`crm-complete`。
  - Terraform 對這個 repository 設了 `prevent_destroy`，避免誤刪已 commit 的 transformation code。
- Dataform runner service account：`complete-dataform-runner@complete-498806.iam.gserviceaccount.com`。
- BigQuery datasets：
  - `staging`
  - `curated`
  - `mart`
- IAM：
  - Dataform runner 可讀 `raw`。
  - Dataform runner 可寫 `staging`、`curated`、`mart`。
  - Dataform runner 可寫 `audit`，用來放 assertions。
  - Dataform runner 可送 BigQuery jobs。

Repo 會新增：

- `complete/dataform/workflow_settings.yaml`
- `complete/dataform/package.json`
- `complete/dataform/definitions/staging/*.sqlx`
- `complete/dataform/definitions/curated/*.sqlx`
- `complete/dataform/definitions/mart/*.sqlx`
- `complete/dataform/definitions/assertions/*.sqlx`

## Step 4 的元件關係與原因

```text
raw tables
  Step 2 Datastream Oracle + Step 3 Dataflow CRM CSV
        |
        v
Dataform SQLX
  type casting、cleaning、join、dedupe、business logic、assertions
        |
        v
staging / curated / mart
  staging: 標準化中間層
  curated: user/customer 360 和 partner identity matching
  mart: ML features 和 Salesforce audience
```

為什麼這一步用 Terraform：

- Terraform 適合建立長期存在的 resource：Dataform repository、service account、datasets、IAM。
- 這些東西需要可 review、可重建、可知道誰有權限。

為什麼 Dataform SQL 不是 Terraform 自動上傳：

- Terraform 的 Dataform repository resource 只建立 repository，不會把本機 `complete/dataform/` 的 SQLX 檔自動 commit 進 Dataform repository。
- SQLX code 要透過 Dataform Console workspace、Git remote，或 Dataform repository workflow 匯入/commit。
- 所以 Step 4 先建立基礎設施，再把 `complete/dataform/` 的 code 放進 Dataform repository，最後才執行 workflow。

## Step 4A - 確認 Step 2/3 input tables

行為：確認 Dataform 的 input 都已經存在。

原因：如果 `raw` tables 還沒出現，Dataform SQL 會 compile/run 失敗。Step 4 不負責重新跑 Datastream 或 Dataflow。

```bash
bq ls --project_id=complete-498806 complete-498806:raw

bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT "crm_sales" AS table_name, COUNT(*) AS row_count FROM `complete-498806.raw.crm_sales`
  UNION ALL
  SELECT "crm_support", COUNT(*) FROM `complete-498806.raw.crm_support`
  UNION ALL
  SELECT "crm_campaign_events", COUNT(*) FROM `complete-498806.raw.crm_campaign_events`
  UNION ALL
  SELECT "crm_new_partner_leads", COUNT(*) FROM `complete-498806.raw.crm_new_partner_leads`
  UNION ALL
  SELECT "APP_USER_RAW", COUNT(*) FROM `complete-498806.raw.APP_USER_RAW`
  '
```

如果 `APP_USER_RAW` 還沒有 row，先回 Step 2 檢查 Datastream stream 是否 `RUNNING`。如果 CRM tables 沒有 row，先回 Step 3 跑 Dataflow ingestion。

## Step 4B - 檢查本機 Dataform scaffold

行為：確認 SQLX scaffold 已在 repo 內。

原因：這些檔案是你要匯入 Dataform repository 的 transformation code。

```bash
find complete/dataform -maxdepth 4 -type f | sort
```

預期至少看到：

```text
complete/dataform/workflow_settings.yaml
complete/dataform/package.json
complete/dataform/definitions/staging/stg_crm_sales.sqlx
complete/dataform/definitions/staging/stg_oracle_users.sqlx
complete/dataform/definitions/curated/user_360.sqlx
complete/dataform/definitions/curated/partner_lead_matches.sqlx
complete/dataform/definitions/mart/user_segmentation_features.sqlx
complete/dataform/definitions/mart/salesforce_campaign_audience.sqlx
```

## Step 4C - Terraform plan Dataform resources

行為：用 Terraform 檢查要新增的 Dataform resources、datasets 和 IAM。

原因：Step 4 會新增 GCP resources，但不應該意外刪改 Step 1/2/3 已完成的資源。

```bash
cd gcp-solutions-repo/complete/terraform

terraform plan \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=true \
  -var oracle_host=10.128.0.2 \
  -var oracle_service_name=XEPDB1 \
  -var oracle_username=C##DATASTREAM \
  -var datastream_desired_state=RUNNING \
  -var enable_dataflow_crm_ingestion=true \
  -var enable_dataform_transform=true \
  -var enable_dataform_release_config=false
```

這裡 `enable_dataform_release_config=false` 是刻意的。因為 release/workflow config 需要 Dataform repository 裡已經有 committed SQLX code；剛建立 repository 時先不要開。

## Step 4D - Apply Dataform base resources

行為：在 plan 確認沒有意外 destroy/change Step 1/2/3 resources 後，由你手動 apply。

原因：先建立 Dataform repository、runner service account、datasets 和 IAM，讓後面 repository code 匯入後可以被執行。

```bash
terraform apply \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=true \
  -var oracle_host=10.128.0.2 \
  -var oracle_service_name=XEPDB1 \
  -var oracle_username=C##DATASTREAM \
  -var datastream_desired_state=RUNNING \
  -var enable_dataflow_crm_ingestion=true \
  -var enable_dataform_transform=true \
  -var enable_dataform_release_config=false
```

## Step 4E - 驗證 Terraform 建出的 resources

行為：確認 Dataform repository、service account 和 BigQuery datasets 存在。

原因：這是開始匯入/執行 SQLX 前的硬性 gate。

```bash
gcloud services list \
  --enabled \
  --project=complete-498806 \
  --filter='config.name:dataform.googleapis.com'

gcloud iam service-accounts describe \
  complete-dataform-runner@complete-498806.iam.gserviceaccount.com \
  --project=complete-498806

bq ls --project_id=complete-498806
```

目前你的本機 `gcloud` 可能沒有 `gcloud dataform` 指令群，所以 Dataform repository 可以先從 Console 檢查：

```text
Google Cloud Console > Dataform > region us-central1 > crm-complete
```

## Step 4F - 把本機 SQLX 匯入 Dataform repository

行為：把 `complete/dataform/` 內容放進 Dataform repository 的 workspace，並 commit 到 `main`。

原因：Terraform 只建立 Dataform repository，不會把本機 SQLX 自動 commit 進 repository。Dataform release/workflow 只能執行 repository 裡已 commit 的 code。

### 做法：Dataform REST API（不需要 gcloud dataform 指令）

本機的 `gcloud` 版本可能沒有 `dataform` 子指令群，改用 REST API 直接操作。

**Step 1：先在 Dataform Console 建立 workspace**

```text
Cloud Console > Dataform > crm-complete > Workspaces > Create workspace
Workspace name: dev-step4
```

**Step 2：用腳本把所有 SQLX 上傳到 workspace**

```bash
bash gcp-solutions-repo/complete/scripts/upload_to_dataform.sh
```

這個腳本會對每個 SQLX 呼叫 Dataform `writeFile` API，把 base64 編碼的內容上傳到 workspace。

**Step 3：Commit workspace 到 main**

```bash
TOKEN=$(gcloud auth print-access-token)
WS_BASE="https://dataform.googleapis.com/v1beta1/projects/complete-498806/locations/us-central1/repositories/crm-complete/workspaces/dev-step4"

# Commit
curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${WS_BASE}:commit" \
  -d '{
    "author": {"name": "step4-deploy", "emailAddress": "deploy@example.com"},
    "commitMessage": "feat: initial SQLX upload step4F",
    "paths": [
      "workflow_settings.yaml", "package.json",
      "definitions/staging/stg_crm_campaign_events.sqlx",
      "definitions/staging/stg_crm_new_partner_leads.sqlx",
      "definitions/staging/stg_crm_sales.sqlx",
      "definitions/staging/stg_crm_support.sqlx",
      "definitions/staging/stg_oracle_users.sqlx",
      "definitions/curated/partner_lead_matches.sqlx",
      "definitions/curated/user_360.sqlx",
      "definitions/mart/salesforce_campaign_audience.sqlx",
      "definitions/mart/user_segmentation_features.sqlx",
      "definitions/assertions/assert_salesforce_audience_has_consent.sqlx",
      "definitions/assertions/assert_user_360_unique.sqlx"
    ]
  }'

# Push 到 main
curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${WS_BASE}:push" \
  -d '{}'
```

### ⚠️ Dataform Core 3.x 的已知踩坑

執行上面步驟時，會遇到幾個 compile error，依序修正：

**踩坑 1：`assertionDataset` property 不存在**

```text
Unexpected property "assertionDataset"
```

Dataform Core 3.0 breaking change：`assertionDataset` → `defaultAssertionDataset`

```yaml
# workflow_settings.yaml 修正前
assertionDataset: audit

# 修正後
defaultAssertionDataset: audit
```

**踩坑 2：版本不符**

```text
Version mismatch: workflow settings specifies version 3.0.0, but 3.0.52 was found
```

`workflow_settings.yaml` 和 `package.json` 的版本要對齊 GCP 環境實際安裝的版本：

```yaml
# workflow_settings.yaml — 直接移除此行（見踩坑 3）
# dataformCoreVersion: 3.0.52
```

```json
// package.json
{ "dependencies": { "@dataform/core": "3.0.52" } }
```

**踩坑 3：`dataformCoreVersion` 和 `package.json` 不能共存**

```text
dataformCoreVersion cannot be defined in workflow_settings.yaml when a package.json is present
```

有 `package.json` 時，版本由 `package.json` 管，`workflow_settings.yaml` 裡不能再寫 `dataformCoreVersion`。直接刪除那一行。

修正後 `workflow_settings.yaml` 最終內容：

```yaml
defaultProject: complete-498806
defaultLocation: US
defaultDataset: staging
defaultAssertionDataset: audit
```

每次修正後都要重新 upload → commit → push。

## Step 4G - 建立 release/workflow config

行為：SQLX code 已 commit 到 `main` 後，再讓 Terraform 建 Dataform release/workflow config。

原因：release config 會抓 `main` 的 code 產生 compilation result；如果 repository 還沒有 code，這一步可能建立了也不能跑。

```bash
terraform plan \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=true \
  -var oracle_host=10.128.0.2 \
  -var oracle_service_name=XEPDB1 \
  -var oracle_username=C##DATASTREAM \
  -var datastream_desired_state=RUNNING \
  -var enable_dataflow_crm_ingestion=true \
  -var enable_dataform_transform=true \
  -var enable_dataform_release_config=true \
  -var dataform_release_git_commitish=main
```

確認 plan 只新增/更新 Dataform release/workflow config 後再 apply：

```bash
terraform apply \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=true \
  -var oracle_host=10.128.0.2 \
  -var oracle_service_name=XEPDB1 \
  -var oracle_username=C##DATASTREAM \
  -var datastream_desired_state=RUNNING \
  -var enable_dataflow_crm_ingestion=true \
  -var enable_dataform_transform=true \
  -var enable_dataform_release_config=true \
  -var dataform_release_git_commitish=main
```

## Step 4H - 執行 Dataform workflow

行為：執行 Dataform workflow，把 raw 轉成 staging/curated/mart。

原因：這一步才是真的跑 SQL transformation。

### 為什麼不能直接從 Console 點「Run workflow」

Terraform 建立的 `workflowConfig: nightly-all` 會參照 `releaseConfig: nightly`。而 release config 必須有一筆 `release_compilation_result`（代表「從 main 編譯過的結果」）才能執行。

因為這是第一次，release config 從來沒有自動排程跑過，所以沒有這筆記錄，Console 上點 Run 會出現：

```text
Release config nightly does not have a release_compilation_result set
```

### 正確的執行順序（用 REST API）

**Step 1：透過 release config 建立 compilationResult**

這和直接 `gitCommitish: main` 不同——必須帶 `releaseConfig` 參數，Dataform 才會把這個結果關聯到 release config。

```bash
TOKEN=$(gcloud auth print-access-token)
REPO_BASE="https://dataform.googleapis.com/v1beta1/projects/complete-498806/locations/us-central1/repositories/crm-complete"

curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${REPO_BASE}/compilationResults" \
  -d '{
    "releaseConfig": "projects/complete-498806/locations/us-central1/repositories/crm-complete/releaseConfigs/nightly"
  }'
```

回傳範例（記下 `name`）：

```json
{
  "name": "projects/complete-498806/.../compilationResults/f606c9b0-...",
  "releaseConfig": "projects/.../releaseConfigs/nightly",
  "dataformCoreVersion": "3.0.52",
  "resolvedGitCommitSha": "e332296..."
}
```

**Step 2：建立 workflow invocation（執行 SQL transformation）**

```bash
COMPILATION_RESULT="projects/complete-498806/locations/us-central1/repositories/crm-complete/compilationResults/f606c9b0-4c6d-4e07-a696-785cedb11a65"

curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${REPO_BASE}/workflowInvocations" \
  -d "{
    \"compilationResult\": \"${COMPILATION_RESULT}\",
    \"invocationConfig\": {
      \"transitiveDependenciesIncluded\": true,
      \"transitiveDependentsIncluded\": false,
      \"fullyRefreshIncrementalTablesEnabled\": false
    }
  }"
```

**Step 3：確認執行結果**

```bash
INVOCATION="projects/complete-498806/locations/us-central1/repositories/crm-complete/workflowInvocations/<invocation-id>"

curl -s -H "Authorization: Bearer ${TOKEN}" \
  "https://dataform.googleapis.com/v1beta1/${INVOCATION}" \
  | python3 -c "
import json,sys; d=json.load(sys.stdin)
print('State:', d.get('state'))
print('Start:', d.get('invocationTiming',{}).get('startTime'))
print('End:  ', d.get('invocationTiming',{}).get('endTime','still running'))
"
```

預期結果：

```text
State: SUCCEEDED
Start: 2026-06-09T16:24:51Z
End:   2026-06-09T16:25:11Z
```

### 兩個 Git 的區別（常見混淆）

| | Dataform Console commit | 本機 GitHub commit |
|---|---|---|
| 存在哪裡 | GCP 內部 Git（Dataform 自己管） | 你的 GitHub repo |
| 用途 | 讓 Dataform workflow 能執行 SQLX | 保存你的原始碼 |
| 誰需要它 | Dataform 執行引擎 | 你自己版本控管 |

兩個都要做。Dataform 的 commit 是透過 REST API 完成，本機 GitHub 的 commit 另外執行：

```bash
cd gcp-solutions-repo
git add complete/
git commit -m "feat: step4 dataform SQLX and config files"
git push origin main
```

## Step 4I - 驗證 BigQuery outputs

行為：確認 Dataform 已產出 staging、curated、mart tables。

原因：Step 5 Dataplex 和 Step 6 ML/Salesforce 都會依賴這些表。

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT "stg_crm_sales" AS table_name, COUNT(*) AS row_count FROM `complete-498806.staging.stg_crm_sales`
  UNION ALL
  SELECT "stg_oracle_users", COUNT(*) FROM `complete-498806.staging.stg_oracle_users`
  UNION ALL
  SELECT "user_360", COUNT(*) FROM `complete-498806.curated.user_360`
  UNION ALL
  SELECT "partner_lead_matches", COUNT(*) FROM `complete-498806.curated.partner_lead_matches`
  UNION ALL
  SELECT "user_segmentation_features", COUNT(*) FROM `complete-498806.mart.user_segmentation_features`
  UNION ALL
  SELECT "salesforce_campaign_audience", COUNT(*) FROM `complete-498806.mart.salesforce_campaign_audience`
  '
```

也可以確認 assertions 沒有失敗：

```text
Dataform Console > workflow invocation details > assertions
```

## 完成後確認

- `complete/dataform/` 已有 SQLX definitions。
- Terraform 已建立 `crm-complete` Dataform repository。
- Terraform 已建立 `complete-dataform-runner` service account。
- BigQuery `staging`、`curated`、`mart` datasets 已存在。
- Dataform SQLX 已匯入 repository 並 commit 到 `main`。
- Dataform workflow 可以成功執行。
- `curated.user_360` 可以 join CRM 和 Oracle user data。
- `curated.partner_lead_matches` 可區分 matched user 和 prospect。
- `mart.user_segmentation_features` 可供 Step 6 ML 使用。
- `mart.salesforce_campaign_audience` 已套用 consent filter。

## 常見風險

- 不要以為 Terraform 會自動把本機 SQLX 上傳到 Dataform repository；它只建 repository 和 IAM。
- 不要在 `raw.APP_USER_RAW` 尚未存在時跑 Dataform；Oracle user join 會失敗。
- 不要把 transformation SQL 只留在 BigQuery Console；這會失去 review 和重跑證據。
- 不要把 partner lead email matching 當成已驗證身份；它只是 activation candidate。
- 不要讓 Dataform runner 拿 project-wide Editor；目前只給 BigQuery jobUser 和 dataset-level read/write。
- 不要在 Step 5 quality gate 之前推 Salesforce。

## 參考

- Dataform REST API: https://docs.cloud.google.com/dataform/reference/rest
- Dataform workflow invocations create: https://docs.cloud.google.com/dataform/reference/rest/v1/projects.locations.repositories.workflowInvocations/create
- Dataform CLI / local project notes: https://docs.cloud.google.com/dataform/docs/use-dataform-cli
