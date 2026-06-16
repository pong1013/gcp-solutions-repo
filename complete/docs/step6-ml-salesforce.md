# Step 6 - ML Segmentation And Salesforce Activation

Step 6 的目標是用 Dataform 管理 BigQuery ML segmentation，產生可啟用的 Salesforce campaign audience，並用 Cloud Run Job 讀取 audience table 做 dry-run 或 sandbox push。這一步必須接在 Step 5 Dataplex quality gate 之後；quality gate 沒通過時，不應執行 ML scoring 或 Salesforce activation。

目前 repo 已補齊 Step 6 的主要資源：

- Dataform ML / mart SQLX：
  - `complete/dataform/definitions/mart/user_segmentation_features.sqlx`
  - `complete/dataform/definitions/mart/user_segment_model.sqlx`
  - `complete/dataform/definitions/mart/user_segments.sqlx`
  - `complete/dataform/definitions/mart/salesforce_campaign_audience.sqlx`
  - `complete/dataform/definitions/assertions/assert_salesforce_audience_has_consent.sqlx`
- Cloud Run Job code：
  - `complete/cloud-run/salesforce-job/main.py`
  - `complete/cloud-run/salesforce-job/Dockerfile`
  - `complete/cloud-run/salesforce-job/requirements.txt`
- Terraform resources：
  - `complete/terraform/salesforce.tf`
  - `complete/terraform/variables.tf`
  - `complete/terraform/outputs.tf`
  - `complete/terraform/apis.tf`

重要邊界：目前 Cloud Run Job 已可讀 BigQuery audience、驗證 payload、寫 audit，且支援 dry-run。`--dry-run=false` 會使用 Salesforce OAuth client credentials flow，尋找 Contact/Lead，並建立缺少的 CampaignMember。

## 這一步在哪裡做

- Dataform project code：`complete/dataform/`
- Salesforce job code：`complete/cloud-run/salesforce-job/`
- Terraform resources：`complete/terraform/salesforce.tf`
- Composer DAG trigger：`complete/composer/dags/`
- BigQuery inputs：
  - `mart.user_segmentation_features`
  - `curated.user_360`
  - `curated.partner_lead_matches`
- BigQuery outputs：
  - `mart.user_segments`
  - `mart.salesforce_campaign_audience`
  - `audit.salesforce_push_runs`

## 這一步會建立/設定什麼

Terraform 會建立：

- Artifact Registry repository：`complete-jobs`
- Cloud Run Job：`salesforce-campaign-push`
- Cloud Run Job service account：`salesforce-push-job`
- Salesforce secret containers：
  - `salesforce-client-id`
  - `salesforce-client-secret`
  - `salesforce-login-url`
- IAM：
  - Cloud Run Job service account 可送 BigQuery jobs。
  - Cloud Run Job service account 可讀 `mart` dataset。
  - Cloud Run Job service account 可寫 `audit` dataset。
  - Cloud Run Job service account 可讀 Salesforce Secret Manager secrets。

Step 6 Terraform 依賴 Step 3/4：

```text
enable_ml_salesforce_push=true
  requires enable_dataflow_crm_ingestion=true  # audit dataset
  requires enable_dataform_transform=true      # mart dataset
```

## Step 6 的資料流

```text
curated.user_360 + curated.partner_lead_matches
        |
        v
mart.user_segmentation_features
        |
        v
BigQuery ML KMeans model: mart.user_segment_model
        |
        v
mart.user_segments
        |
        v
mart.salesforce_campaign_audience
  consent allowed + quality_gate_status = passed + activation_status = ready
        |
        v
Cloud Run Job: salesforce-campaign-push
        |
        v
audit.salesforce_push_runs
```

## Step 6A - 確認 Step 4/5 輸入已存在

行為：確認 Dataform 已經產生 Step 6 需要的 curated/mart tables。

原因：Terraform 只建立 Cloud Run Job infrastructure，不會替你執行 Dataform SQLX。若 `mart.salesforce_campaign_audience` 還不存在，dry-run 會查詢失敗。

```bash
bq ls --project_id=complete-498806 complete-498806:curated
bq ls --project_id=complete-498806 complete-498806:mart
bq ls --project_id=complete-498806 complete-498806:audit
```

檢查 row count：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT "user_360" AS table_name, COUNT(*) AS row_count FROM `complete-498806.curated.user_360`
  UNION ALL
  SELECT "partner_lead_matches", COUNT(*) FROM `complete-498806.curated.partner_lead_matches`
  UNION ALL
  SELECT "user_segmentation_features", COUNT(*) FROM `complete-498806.mart.user_segmentation_features`
  UNION ALL
  SELECT "user_segments", COUNT(*) FROM `complete-498806.mart.user_segments`
  UNION ALL
  SELECT "salesforce_campaign_audience", COUNT(*) FROM `complete-498806.mart.salesforce_campaign_audience`
  '
```

若 mart tables 不存在，先回 Step 4 執行 Dataform workflow。若 Dataplex quality gate 失敗，先修 Step 5，不要直接 push Salesforce。

## Step 6B - 檢查 BigQuery ML 與 audience contract

行為：檢查模型、segment output 和 Salesforce audience 欄位。

原因：Cloud Run Job 的 query contract 寫在 `complete/cloud-run/salesforce-job/main.py`，欄位不一致會在 runtime 才失敗。

先檢查目前 BigQuery table schema：

```bash
bq show \
  --project_id=complete-498806 \
  --schema \
  --format=prettyjson \
  complete-498806:mart.salesforce_campaign_audience
```

預期至少要有：

```text
run_date
campaign_id
user_id
lead_email
salesforce_contact_id
segment_name
score
consent_status
activation_status
quality_gate_status
```

如果看到 `Unrecognized name: salesforce_contact_id`、`Unrecognized name: activation_status` 或 `Unrecognized name: quality_gate_status`，代表 BigQuery 裡的 table 還是舊版 schema。Salesforce activation contract 是 Step 6 新增的，所以 Step 6 需要先把既有 table 補到 Cloud Run Job 會讀取的欄位結構。

Lab smoke test 可先執行這段 migration：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  'ALTER TABLE `complete-498806.mart.salesforce_campaign_audience`
     ADD COLUMN IF NOT EXISTS salesforce_contact_id STRING;

   ALTER TABLE `complete-498806.mart.salesforce_campaign_audience`
     ADD COLUMN IF NOT EXISTS activation_status STRING;

   ALTER TABLE `complete-498806.mart.salesforce_campaign_audience`
     ADD COLUMN IF NOT EXISTS quality_gate_status STRING;

   UPDATE `complete-498806.mart.salesforce_campaign_audience`
   SET
     activation_status = COALESCE(activation_status, "ready"),
     quality_gate_status = COALESCE(quality_gate_status, "passed")
   WHERE TRUE'
```

正式路徑仍應重新執行 Dataform，讓 table definition 與 repo SQLX 對齊。這段 migration 只是讓已經存在的 lab table 可以先通過 Step 6B 和 Cloud Run dry-run。

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT
    run_date,
    campaign_id,
    user_id,
    lead_email,
    salesforce_contact_id,
    segment_name,
    score,
    consent_status,
    activation_status,
    quality_gate_status
  FROM `complete-498806.mart.salesforce_campaign_audience`
  WHERE run_date = DATE "2026-05-26"
  LIMIT 20
  '
```

Audience 必須符合：

```text
consent_status IN ('email_consent', 'partner_opt_in')
quality_gate_status = 'passed'
activation_status = 'ready'
```

檢查 assertion：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT *
  FROM `complete-498806.mart.salesforce_campaign_audience`
  WHERE consent_status NOT IN ("email_consent", "partner_opt_in")
  LIMIT 20
  '
```

預期回傳 0 rows。

## Step 6C - Terraform plan Salesforce resources

行為：建立 Cloud Run Job、Artifact Registry、Secret Manager containers 和 IAM。

原因：Salesforce credentials 不進 Terraform state；Terraform 只管理 secret containers 和 least-privilege IAM。

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
  -var enable_dataform_release_config=true \
  -var enable_dataplex_quality=true \
  -var enable_ml_salesforce_push=true
```

Plan 預期新增或確認：

```text
google_artifact_registry_repository.jobs
google_secret_manager_secret.salesforce
google_service_account.salesforce_job
google_project_iam_member.salesforce_job_user
google_bigquery_dataset_iam_member.salesforce_job_mart_viewer
google_bigquery_dataset_iam_member.salesforce_job_audit_editor
google_secret_manager_secret_iam_member.salesforce_job_secret_reader
google_cloud_run_v2_job.salesforce_campaign_push
```

## Step 6D - Apply Salesforce resources

行為：先建立 Salesforce job 需要的 Artifact Registry repository。

原因：Cloud Run Job 指向 `salesforce-job:latest`。如果 image 還沒 push，Cloud Run Job 會進入 `CONTAINER_MISSING`，Terraform state 也可能把 job 標成 tainted。Step 6 第一次部署要先建 repo，再 build image，最後才建立/更新 Cloud Run Job。

```bash
terraform apply \
  -target=google_artifact_registry_repository.jobs \
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
  -var enable_dataplex_quality=true \
  -var enable_ml_salesforce_push=true
```

如果 Cloud Run Job 已經因 missing image 變成 tainted，先完成 Step 6F build image，然後解除 taint：

```bash
terraform untaint 'google_cloud_run_v2_job.salesforce_campaign_push[0]'
```

再 apply 全部 Step 6 resources。

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
  -var enable_dataplex_quality=true \
  -var enable_ml_salesforce_push=true
```

驗證 outputs：

```bash
terraform output salesforce_job_artifact_registry_repository
terraform output salesforce_cloud_run_job_name
terraform output salesforce_job_service_account_email
```

## Step 6E - 寫入 Salesforce secrets

行為：用 `gcloud secrets versions add` 寫入 secret values。

原因：secret value 不應寫進 repo、Terraform variables、Terraform state 或 shell history。

Production 寫入使用 Salesforce OAuth client credentials flow。這三個 Secret Manager value 來源如下：

| Secret | Salesforce 來源 |
|---|---|
| `salesforce-client-id` | 連線應用程式的 **消費者金鑰** |
| `salesforce-client-secret` | 連線應用程式的 **消費者密碼 / 消費者祕密** |
| `salesforce-login-url` | 優先使用該 org 的 My Domain API login URL，例如 `https://<my-domain>.my.salesforce.com`；一般 Production 可用 `https://login.salesforce.com`；Sandbox 可用 `https://test.salesforce.com` |

### Step 6E-1 - 先確認是否已經有可用的連線應用程式

「既有的連線應用程式」不是隨便一個 App，而是已經開好 OAuth、允許 API 存取、且允許 client credentials flow 的 integration app。檢查方式：

```text
設定
-> 應用程式
-> 應用程式管理員
-> 找名稱像 CRM、GCP、Data Pipeline、Integration、API 的連線應用程式
-> 右側下拉選單
-> 檢視 / 管理
```

如果看不到下列設定，就不要拿它來用，請新增 Step 6 專用連線應用程式：

```text
已啟用 OAuth 設定
OAuth 範圍包含 api
已啟用用戶端認證流程
已設定執行身分使用者
```

### Step 6E-2 - 新增 Step 6 專用連線應用程式

在中文版 Salesforce：

```text
設定
-> 應用程式
-> 應用程式管理員
-> 新增連線應用程式
```

必填欄位建議這樣填：

| 中文欄位 | 建議值 |
|---|---|
| 連線應用程式名稱 | `GCP CRM Campaign Activation` |
| API 名稱 | 自動產生即可，例如 `GCP_CRM_Campaign_Activation` |
| 連絡電子郵件 | 你的管理者 email 或 integration owner email |
| 啟用 OAuth 設定 | 勾選 |
| 回呼 URL | `https://localhost/callback`。Client Credentials Flow 不會用到，但 Salesforce 表單通常要求填 |
| 選取的 OAuth 範圍 | 加入 `管理使用者資料 (api)` 或畫面中包含 `api` 的同義選項 |
| 需要 Proof Key for Code Exchange (PKCE) | 不勾選 |
| 需要 Web 伺服器流程的密碼 | 不勾選 |
| 啟用用戶端認證流程 | 勾選 |

儲存後 Salesforce 可能需要幾分鐘讓 Connected App 設定生效。

### Step 6E-3 - 設定用戶端認證流程的執行身分使用者

Client credentials flow 不會用真人互動登入，它會用 Connected App policy 裡設定的 Run As user 執行 API。設定位置通常是：

```text
設定
-> 應用程式
-> 應用程式管理員
-> 找到 GCP CRM Campaign Activation
-> 右側下拉選單
-> 管理
-> 編輯原則
-> 用戶端認證流程
-> 執行身分使用者
```

`執行身分使用者` 建議使用專用 integration user，不要用個人帳號。這個 user 至少需要：

```text
API 已啟用
可讀 Contact / Lead / Campaign
可建立 CampaignMember
可讀取目標 Campaign record
如果 Salesforce org 使用 Campaign 權限控管，確認 user 有 Marketing User 或等效權限
```

### Step 6E-4 - 取得 Consumer Key / Consumer Secret

在 Salesforce UI 取得方式：

```text
設定
-> 應用程式
-> 應用程式管理員
-> 找到 GCP CRM Campaign Activation
-> 右側下拉選單
-> 檢視 / 管理消費者詳細資料
-> 複製 消費者金鑰 作為 salesforce-client-id
-> 複製 消費者密碼 / 消費者祕密 作為 salesforce-client-secret
```

`salesforce-login-url` 不是從 Consumer Details 複製，依環境填。不要使用 Lightning UI 或 Setup UI 的網址：

```text
可以使用:
Production org: https://login.salesforce.com
Sandbox org: https://test.salesforce.com
My Domain org: https://<my-domain>.my.salesforce.com

不要使用:
https://<my-domain>.lightning.force.com
https://<my-domain>.my.salesforce-setup.com
```

如果 Salesforce 回 `invalid_grant: request not supported on this domain`，通常就是 `salesforce-login-url` 用到了 Lightning/Setup 網域。從 Lightning record URL：

```text
https://orgfarm-34e538bc18-dev-ed.develop.lightning.force.com/lightning/r/Campaign/701.../view
```

推得 My Domain API login URL：

```text
https://orgfarm-34e538bc18-dev-ed.develop.my.salesforce.com
```

`--campaign-id` 不是 Secret Manager value。它來自 Salesforce Campaign record 的 Id：進 Salesforce Campaigns，開啟目標 Campaign，從 URL 取出 `/Campaign/<ID>/view` 中的 `<ID>`，通常以 `701` 開頭。

### Step 6E-5 - 寫入 GCP Secret Manager

```bash
read -r SALESFORCE_CLIENT_ID
read -rs SALESFORCE_CLIENT_SECRET
echo
read -r SALESFORCE_LOGIN_URL

printf '%s' "${SALESFORCE_CLIENT_ID}" \
  | gcloud secrets versions add salesforce-client-id \
      --data-file=- \
      --project=complete-498806

printf '%s' "${SALESFORCE_CLIENT_SECRET}" \
  | gcloud secrets versions add salesforce-client-secret \
      --data-file=- \
      --project=complete-498806

printf '%s' "${SALESFORCE_LOGIN_URL}" \
  | gcloud secrets versions add salesforce-login-url \
      --data-file=- \
      --project=complete-498806

unset SALESFORCE_CLIENT_ID SALESFORCE_CLIENT_SECRET SALESFORCE_LOGIN_URL
```

確認 secret containers 有 version：

```bash
gcloud secrets versions list salesforce-client-id --project=complete-498806
gcloud secrets versions list salesforce-client-secret --project=complete-498806
gcloud secrets versions list salesforce-login-url --project=complete-498806
```

如果要跑 production `--dry-run=false`，這一步不能跳過。

## Step 6F - Build Cloud Run Job image

行為：把 Salesforce job container build 並 push 到 Step 6 Artifact Registry repository。

原因：Terraform 建 Cloud Run Job 時使用 `salesforce-job:latest` image contract；真正執行前需要先把 image 推上去。

```bash
cd gcp-solutions-repo/complete/cloud-run/salesforce-job

gcloud builds submit \
  --project=complete-498806 \
  --tag=us-central1-docker.pkg.dev/complete-498806/complete-jobs/salesforce-job:latest
```

確認 image：

```bash
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/complete-498806/complete-jobs \
  --project=complete-498806
```

## Step 6G - 手動執行 dry-run

行為：先用 dry-run 驗證 BigQuery query、payload shape 和 audit 寫入。

原因：dry-run 不呼叫 Salesforce write endpoint，適合做 smoke test。

```bash
gcloud run jobs execute salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --args=--run-date=2026-05-26,--campaign-id=CAMP_MOCK_1,--dry-run=true \
  --wait
```

查 execution：

```bash
gcloud run jobs executions list \
  --job=salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1
```

查 logs：

```bash
gcloud logging read \
  'resource.type="cloud_run_job" AND resource.labels.job_name="salesforce-campaign-push"' \
  --project=complete-498806 \
  --limit=50 \
  --format='value(textPayload)'
```

查 audit：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT *
  FROM `complete-498806.audit.salesforce_push_runs`
  ORDER BY started_at DESC
  LIMIT 20
  '
```

## Step 6H - Production Salesforce push

行為：只有 dry-run 成功、Dataplex quality gate 通過、且 production Connected App credentials 已設定後，才執行 `--dry-run=false`。

Cloud Run Job 會：

```text
1. 用 Salesforce OAuth client credentials flow 取得 access token。
2. 讀取 mart.salesforce_campaign_audience。
3. 對每筆 audience 以 salesforce_contact_id 或 lead_email 尋找 Contact/Lead。
4. 先查 CampaignMember 是否已存在。
5. 只建立缺少的 CampaignMember，避免重跑重複新增。
6. 寫入 audit.salesforce_push_runs。
```

Production 第一次不要直接跑全量。先用 `--limit=10` 做小批量 smoke test。

如果 audience email 已經在 Salesforce Contact 或 Lead 裡，使用：

```bash
gcloud run jobs execute salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --args=--run-date=2026-05-26,--campaign-id=701gK000018hdjOQAQ,--dry-run=false,--limit=10 \
  --wait
```

如果是 lab fake partner leads，Salesforce 裡通常還沒有對應 Lead/Contact。要讓 job 先建立缺少的 Lead，再加入 Campaign，明確加上 `--create-missing-leads=true`：

```bash
gcloud run jobs execute salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --args=--run-date=2026-05-26,--campaign-id=701gK000018hdjOQAQ,--dry-run=false,--limit=10,--create-missing-leads=true \
  --wait
```

如果回傳：

```text
entity type cannot be inserted: Lead
errorCode: CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY
```

代表 Connected App 的 `執行身分使用者` 不能建立 `Lead / 潛在客戶`。到 Salesforce 幫該使用者補權限：

```text
設定
-> 使用者
-> 權限集
-> 新增或編輯 Step 6 integration permission set
-> 物件設定
-> 潛在客戶 / Lead
-> 編輯
-> 勾選 讀取、建立、編輯
-> 儲存
-> 管理指派
-> 指派給 Connected App 的執行身分使用者
```

同一個執行身分使用者也需要：

```text
行銷活動 / Campaign: 讀取
行銷活動成員 / Campaign Member: 讀取、建立、編輯
聯絡人 / Contact: 讀取
潛在客戶 / Lead: 讀取、建立、編輯
```

如果 Salesforce org 不允許該使用者建立 Lead，但允許建立 Contact，可以改用 Contact fallback：

```bash
gcloud run jobs execute salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --args=--run-date=2026-05-26,--campaign-id=701gK000018hdjOQAQ,--dry-run=false,--limit=1,--create-missing-contacts=true \
  --wait
```

這條路需要：

```text
連絡人 / Contact: 讀取、建立、編輯
行銷活動 / Campaign: 讀取
行銷活動成員 / Campaign Member: 讀取、建立、編輯
```

確認 10 筆成功後，再用 `--limit` / `--offset` 分批：

```bash
gcloud run jobs execute salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --args=--run-date=2026-05-26,--campaign-id=701gK000018hdjOQAQ,--dry-run=false,--limit=200,--offset=0 \
  --wait

gcloud run jobs execute salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --args=--run-date=2026-05-26,--campaign-id=701gK000018hdjOQAQ,--dry-run=false,--limit=200,--offset=200 \
  --wait
```

如果 Cloud Run Job 還是 10 分鐘 timeout，先把 timeout 更新成 30 分鐘：

```bash
gcloud run jobs update salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --task-timeout=1800
```

```bash
gcloud run jobs execute salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --args=--run-date=2026-05-26,--campaign-id=CAMP_MOCK_1,--dry-run=false \
  --wait
```

如果 Salesforce Campaign Member 的預設 Status 不是 `Sent`，指定實際可用值：

```bash
gcloud run jobs execute salesforce-campaign-push \
  --project=complete-498806 \
  --region=us-central1 \
  --args=--run-date=2026-05-26,--campaign-id=CAMP_MOCK_1,--dry-run=false,--campaign-member-status=Responded \
  --wait
```

查 production push audit：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT *
  FROM `complete-498806.audit.salesforce_push_runs`
  WHERE is_dry_run = FALSE
  ORDER BY started_at DESC
  LIMIT 20
  '
```

## Step 6I - Composer orchestration contract

Composer DAG 的 Step 6 順序應為：

```text
Dataplex quality gate passed
-> Dataform ML scoring / mart refresh completed
-> Salesforce dry-run validation
-> optional approval gate
-> Salesforce sandbox or production push
-> audit.salesforce_push_runs checked
```

如果 quality gate fail：

```text
skip ML scoring
skip Salesforce dry-run
skip Salesforce push
notify manager
```

## 完成後確認

- `mart.user_segmentation_features` 有資料。
- BigQuery ML model `mart.user_segment_model` 可建立或更新。
- `mart.user_segments` 有 scoring output。
- `mart.salesforce_campaign_audience` 只包含 consent allowed records。
- Secret values 只存在 Secret Manager，不在 Terraform state。
- Cloud Run Job dry-run 成功。
- `audit.salesforce_push_runs` 有 dry-run audit row。
- `--dry-run=false` 成功後，Salesforce Campaign 裡可查到對應 Campaign Member。

## 常見風險

- 不要在 Dataplex quality gate 失敗時執行 Step 6。
- 不要把 Salesforce client secret 放進 Terraform state、repo 或 logs。
- 不要在 image 尚未 build/push 前執行 Cloud Run Job。
- 不要把 `enable_ml_salesforce_push=true` 單獨打開；它需要 Step 3 audit dataset 和 Step 4 mart dataset。
- 不要使用沒有 CampaignMember 寫入權限的 Connected App Run As user。
