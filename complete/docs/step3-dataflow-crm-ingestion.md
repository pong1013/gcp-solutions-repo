# Step 3 - CRM CSV Ingestion With Dataflow Flex Template

Step 3 的目標是把 Step 1 傳進 GCS raw bucket 的四種 CRM CSV，透過同一套 Dataflow Flex Template 寫進 BigQuery `raw` tables。Complete 方案用 Dataflow，不是因為它比較便宜，而是因為它能支援 schema-driven parsing、row-level rejection、audit metadata、可重跑與 production 等級的權限分離。

目前這一步已補上可 build 的 scaffold：Terraform 會建立 Dataflow 基礎資源與 BigQuery tables，repo 內也有 Python Flex Template 程式和四份 schema config。Codex 不會替你直接跑 production job；下面指令由你手動執行。

## 這一步在哪裡做

- Dataflow template code：`complete/dataflow/crm-csv-ingestion/`
- CRM schema configs：`complete/schemas/`
- Terraform resources：`complete/terraform/dataflow.tf`
- Composer DAG trigger：`complete/composer/dags/complete_crm_nightly_pipeline.py`
- Step 1 raw files：`gs://complete-498806-complete-crm-raw/crm/2026-05-26/`
- Console 驗證：Dataflow、BigQuery、Cloud Storage、Cloud Logging

## 這一步會建立/設定什麼

Terraform 會建立或設定：

- `gs://complete-498806-complete-dataflow-templates`
  - 放 Dataflow Flex Template spec JSON。
- `gs://complete-498806-complete-dataflow-temp`
  - Dataflow staging/temp 檔案。
- `gs://complete-498806-complete-config`
  - 放 schema config，例如 `schemas/crm_sales.json`。
- Artifact Registry repository：
  - `us-central1-docker.pkg.dev/complete-498806/complete-dataflow`
- Dataflow worker service account：
  - `complete-dataflow-worker@complete-498806.iam.gserviceaccount.com`
- BigQuery：
  - `raw.crm_sales`
  - `raw.crm_support`
  - `raw.crm_campaign_events`
  - `raw.crm_new_partner_leads`
  - `audit.ingestion_runs`
- IAM：
  - worker 可讀 raw bucket。
  - worker 可寫 rejected bucket。
  - worker 可寫 BigQuery raw/audit tables。
  - worker 可讀 config bucket。
  - worker 可讀 Artifact Registry image。

Repo 會提供：

- `complete/dataflow/crm-csv-ingestion/main.py`
  - 讀 schema config。
  - 找 `input_prefix + file_pattern` 的 CSV。
  - 依欄位型別轉換。
  - valid rows 寫 BigQuery。
  - invalid rows 寫 rejected JSONL。
  - 寫入 `audit.ingestion_runs`。
- `complete/dataflow/crm-csv-ingestion/metadata.json`
  - Flex Template parameters 定義。
- `complete/dataflow/crm-csv-ingestion/requirements.txt`
  - Apache Beam dependency。
- `complete/schemas/*.json`
  - 四種 CRM source type 的 schema contract。

## Step 3 的元件關係與實作方式

```text
GCS raw bucket
  crm/<run_date>/*.csv
        |
        v
Schema config in config bucket
  source_type、file_pattern、欄位、型別、required policy
        |
        v
Dataflow Flex Template
  同一份 Python Beam pipeline 依參數處理不同 CRM CSV
        |
        v
BigQuery raw tables + rejected bucket + audit table
  valid rows -> raw.<source_type>
  invalid rows -> rejected bucket JSONL
  job counts -> audit.ingestion_runs
```

為什麼要這樣做：

```text
新增 CRM file type 時，主要新增 schema config 和 raw table definition。
Rejected output 是 production 必要證據，不能讓壞資料安靜消失。
Dataflow worker 使用獨立 service account，不使用 project-wide owner/editor。
```

## Step 3A - 確認 repo scaffold

從 repo root 執行：

```bash
ls complete/dataflow/crm-csv-ingestion
ls complete/schemas
ls complete/terraform/dataflow.tf
```

預期看到：

```text
complete/dataflow/crm-csv-ingestion/main.py
complete/dataflow/crm-csv-ingestion/metadata.json
complete/dataflow/crm-csv-ingestion/requirements.txt
complete/schemas/crm_sales.json
complete/schemas/crm_support.json
complete/schemas/crm_campaign_events.json
complete/schemas/crm_new_partner_leads.json
```

這一步的行為：

```text
只是檢查本機 repo 檔案，不會建立 GCP resource。
```

## Step 3B - Terraform plan Dataflow 基礎資源

這一步的行為是讓 Terraform 準備 Step 3 所需的 Dataflow/BigQuery/GCS/IAM resources。因為你現在 Step 1 和 Step 2 已經有真實資源，所以 plan 指令要帶上目前狀態相關變數，避免 Terraform 誤判要改回預設值。

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo/complete/terraform

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
  -var enable_dataflow_crm_ingestion=true
```

你要確認 plan 主要是新增：

```text
google_storage_bucket.dataflow_templates
google_storage_bucket.dataflow_temp
google_storage_bucket.config
google_storage_bucket_object.crm_schema_configs
google_artifact_registry_repository.dataflow_templates
google_service_account.dataflow_worker
google_bigquery_dataset.audit
google_bigquery_table.crm_raw
google_bigquery_table.ingestion_runs
Dataflow worker IAM bindings
```

不要看到 Step 1 buckets、Storage Transfer job、Oracle VM、Datastream stream 被刪除或重建。

## Step 3C - Apply Dataflow 基礎資源

確認 Step 3B plan 沒有意外刪改後，由你手動 apply 同一組變數：

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo/complete/terraform

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
  -var enable_dataflow_crm_ingestion=true
```

這一步完成後確認：

```bash
gsutil ls gs://complete-498806-complete-config/schemas/

bq ls --project_id=complete-498806 complete-498806:raw
bq ls --project_id=complete-498806 complete-498806:audit

gcloud artifacts repositories describe complete-dataflow \
  --project=complete-498806 \
  --location=us-central1
```

## Step 3D - Build Dataflow Flex Template

這一步的行為是把 `complete/dataflow/crm-csv-ingestion/main.py` build 成 container image，推到 Artifact Registry，並產生 Flex Template spec JSON 到 GCS。

為什麼這裡用 `gcloud`，不是 Terraform：

```text
Terraform 管「長期存在的基礎設施」：bucket、service account、IAM、BigQuery table、Artifact Registry repo。
Flex Template build 是「把目前本機程式碼打包成 container image + template spec」的 build 動作。
這種動作會隨每次程式碼改版重新執行，production 通常交給 Cloud Build/CI，不適合用 Terraform state 管。

簡單說：
  Terraform apply -> 建可以放 template/image/job output 的地方。
  gcloud dataflow flex-template build -> 把這一版程式碼 build 成可跑的 template artifact。
```

先確認你在正確目錄。`metadata.json` 是相對路徑，如果你還站在 `complete/terraform` 執行，就會看到 `No such file or directory: metadata.json`。

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo/complete/dataflow/crm-csv-ingestion

pwd
ls -lh main.py metadata.json requirements.txt
test -f metadata.json
test -f main.py
test -f requirements.txt
```

確認檔案存在後再 build：

```bash
gcloud dataflow flex-template build \
  gs://complete-498806-complete-dataflow-templates/crm-csv-ingestion/template.json \
  --project=complete-498806 \
  --sdk-language=PYTHON \
  --flex-template-base-image=PYTHON3 \
  --image-gcr-path=us-central1-docker.pkg.dev/complete-498806/complete-dataflow/crm-csv-ingestion:latest \
  --metadata-file=metadata.json \
  --py-path=. \
  --env=FLEX_TEMPLATE_PYTHON_PY_FILE=main.py \
  --env=FLEX_TEMPLATE_PYTHON_REQUIREMENTS_FILE=requirements.txt \
  --staging-location=gs://complete-498806-complete-dataflow-temp/build-staging \
  --temp-location=gs://complete-498806-complete-dataflow-temp/build-temp \
  --gcs-log-dir=gs://complete-498806-complete-dataflow-temp/build-logs
```

如果你不想依賴目前 shell 所在目錄，也可以用這個絕對路徑版本：

```bash
DATAFLOW_SRC=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo/complete/dataflow/crm-csv-ingestion

gcloud dataflow flex-template build \
  gs://complete-498806-complete-dataflow-templates/crm-csv-ingestion/template.json \
  --project=complete-498806 \
  --sdk-language=PYTHON \
  --flex-template-base-image=PYTHON3 \
  --image-gcr-path=us-central1-docker.pkg.dev/complete-498806/complete-dataflow/crm-csv-ingestion:latest \
  --metadata-file="${DATAFLOW_SRC}/metadata.json" \
  --py-path="${DATAFLOW_SRC}" \
  --env=FLEX_TEMPLATE_PYTHON_PY_FILE=main.py \
  --env=FLEX_TEMPLATE_PYTHON_REQUIREMENTS_FILE=requirements.txt \
  --staging-location=gs://complete-498806-complete-dataflow-temp/build-staging \
  --temp-location=gs://complete-498806-complete-dataflow-temp/build-temp \
  --gcs-log-dir=gs://complete-498806-complete-dataflow-temp/build-logs
```

完成後確認：

```bash
gsutil ls gs://complete-498806-complete-dataflow-templates/crm-csv-ingestion/template.json

gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/complete-498806/complete-dataflow \
  --project=complete-498806
```

如果 build 失敗且錯誤是 Cloud Build service account 無法讀取 `gs://complete-498806_cloudbuild/source/...`、`complete-dataflow-temp`，或無法 push Artifact Registry image，例如：

```bash
875659388420-compute@developer.gserviceaccount.com does not have storage.objects.get access
service account 875659388420-compute@developer.gserviceaccount.com does not have access to the bucket
```

代表這次 Cloud Build 實際使用 Compute Engine default service account 來 build image。一次補齊 build 階段需要的權限：

```bash
BUILD_SA=875659388420-compute@developer.gserviceaccount.com

gcloud storage buckets add-iam-policy-binding gs://complete-498806_cloudbuild \
  --member=serviceAccount:${BUILD_SA} \
  --role=roles/storage.objectAdmin \
  --project=complete-498806

gcloud storage buckets add-iam-policy-binding gs://complete-498806-complete-dataflow-temp \
  --member=serviceAccount:${BUILD_SA} \
  --role=roles/storage.objectAdmin \
  --project=complete-498806

gcloud storage buckets add-iam-policy-binding gs://complete-498806-complete-dataflow-templates \
  --member=serviceAccount:${BUILD_SA} \
  --role=roles/storage.objectAdmin \
  --project=complete-498806

gcloud artifacts repositories add-iam-policy-binding complete-dataflow \
  --project=complete-498806 \
  --location=us-central1 \
  --member=serviceAccount:${BUILD_SA} \
  --role=roles/artifactregistry.writer
```

如果錯誤訊息列出的是另一個 service account，就把上面 `--member` 換成錯誤訊息中的實際執行身分。不要在不知道實際執行身分時亂猜；新舊專案的 Cloud Build default identity 可能不同。

## Step 3E - 手動執行單一 source type

先跑 `crm_sales`，因為它有數字、日期和常見 CRM deal 欄位，適合驗證型別轉換。

這一步的行為是啟動一個 Dataflow batch job：

```bash
gcloud dataflow flex-template run crm-ingest-crm-sales-20260526-r3 \
  --project=complete-498806 \
  --region=us-east1 \
  --worker-zone=us-east1-b \
  --template-file-gcs-location=gs://complete-498806-complete-dataflow-templates/crm-csv-ingestion/template.json \
  --service-account-email=complete-dataflow-worker@complete-498806.iam.gserviceaccount.com \
  --staging-location=gs://complete-498806-complete-dataflow-temp/job-staging \
  --temp-location=gs://complete-498806-complete-dataflow-temp/job-temp \
  --parameters=run_date=2026-05-26,source_type=crm_sales,input_prefix=gs://complete-498806-complete-crm-raw/crm/2026-05-26/,schema_config_path=gs://complete-498806-complete-config/schemas/crm_sales.json,output_table=complete-498806:raw.crm_sales,rejected_output_prefix=gs://complete-498806-complete-crm-rejected/crm/2026-05-26/crm_sales/,audit_table=complete-498806:audit.ingestion_runs
```

為什麼先只跑一個：

```text
先確認 template image、worker IAM、raw bucket read、BigQuery write、rejected write 都通。
一個 source type 成功後，再平行跑其他三個，debug 成本比較低。
```

如果 job 很快失敗並出現：

```text
ZONE_RESOURCE_POOL_EXHAUSTED
```

這不是 pipeline code 錯，而是 Dataflow launcher VM 被排到的 zone 暫時沒有足夠資源。重跑時換另一個 zone，例如 `--worker-zone=us-central1-a`、`us-central1-b` 或 `us-central1-f`。重跑 job name 建議加尾碼，例如 `-r1`，避免和失敗 job 混淆。

## Step 3F - 驗證單一 source type

Dataflow job 完成後查 raw count：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  'SELECT COUNT(*) AS row_count FROM `complete-498806.raw.crm_sales` WHERE run_date = DATE "2026-05-26"'
```

查 rejected output：

```bash
gsutil ls gs://complete-498806-complete-crm-rejected/crm/2026-05-26/crm_sales/
```

如果沒有 rejected file，不一定是錯；代表這次沒有壞資料。真正要確認的是 Dataflow job 沒有因 rejected write 權限失敗。

查 audit：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  'SELECT run_date, source_type, input_count, valid_count, rejected_count, audit_ts
   FROM `complete-498806.audit.ingestion_runs`
   WHERE run_date = DATE "2026-05-26"
     AND source_type = "crm_sales"
   ORDER BY audit_ts DESC
   LIMIT 5'
```

如果 Dataflow 在 `Write valid rows` 失敗，並且 log 顯示：

```text
Provided Schema does not match Table complete-498806:raw.crm_sales.
Field run_date has changed mode from REQUIRED to NULLABLE
```

原因是 Beam 的 BigQuery load schema 會把簡短 schema string 視為 `NULLABLE`，但 Terraform 先前建立的 BigQuery table 把 metadata 欄位設為 `REQUIRED`。這不是資料內容錯；修法是套用新版 Terraform，將 raw/audit table metadata 欄位放寬為 `NULLABLE`，required policy 由 Dataflow validation 控制。

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo/complete/terraform

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
  -var enable_dataflow_crm_ingestion=true
```

套用後用新的 job name 重跑，例如 `crm-ingest-crm-sales-20260526-r3`。

## Step 3G - 跑完其他三個 source type

`crm_support`：

```bash
gcloud dataflow flex-template run crm-ingest-crm-support-20260526-r1 \
  --project=complete-498806 \
  --region=us-east1 \
  --worker-zone=us-east1-b \
  --template-file-gcs-location=gs://complete-498806-complete-dataflow-templates/crm-csv-ingestion/template.json \
  --service-account-email=complete-dataflow-worker@complete-498806.iam.gserviceaccount.com \
  --staging-location=gs://complete-498806-complete-dataflow-temp/job-staging \
  --temp-location=gs://complete-498806-complete-dataflow-temp/job-temp \
  --parameters=run_date=2026-05-26,source_type=crm_support,input_prefix=gs://complete-498806-complete-crm-raw/crm/2026-05-26/,schema_config_path=gs://complete-498806-complete-config/schemas/crm_support.json,output_table=complete-498806:raw.crm_support,rejected_output_prefix=gs://complete-498806-complete-crm-rejected/crm/2026-05-26/crm_support/,audit_table=complete-498806:audit.ingestion_runs
```

`crm_campaign_events`：

```bash
gcloud dataflow flex-template run crm-ingest-crm-campaign-events-20260526-r1 \
  --project=complete-498806 \
  --region=us-east1 \
  --worker-zone=us-east1-b \
  --template-file-gcs-location=gs://complete-498806-complete-dataflow-templates/crm-csv-ingestion/template.json \
  --service-account-email=complete-dataflow-worker@complete-498806.iam.gserviceaccount.com \
  --staging-location=gs://complete-498806-complete-dataflow-temp/job-staging \
  --temp-location=gs://complete-498806-complete-dataflow-temp/job-temp \
  --parameters=run_date=2026-05-26,source_type=crm_campaign_events,input_prefix=gs://complete-498806-complete-crm-raw/crm/2026-05-26/,schema_config_path=gs://complete-498806-complete-config/schemas/crm_campaign_events.json,output_table=complete-498806:raw.crm_campaign_events,rejected_output_prefix=gs://complete-498806-complete-crm-rejected/crm/2026-05-26/crm_campaign_events/,audit_table=complete-498806:audit.ingestion_runs
```

`crm_new_partner_leads`：

```bash
gcloud dataflow flex-template run crm-ingest-crm-new-partner-leads-20260526-r1 \
  --project=complete-498806 \
  --region=us-east1 \
  --worker-zone=us-east1-b \
  --template-file-gcs-location=gs://complete-498806-complete-dataflow-templates/crm-csv-ingestion/template.json \
  --service-account-email=complete-dataflow-worker@complete-498806.iam.gserviceaccount.com \
  --staging-location=gs://complete-498806-complete-dataflow-temp/job-staging \
  --temp-location=gs://complete-498806-complete-dataflow-temp/job-temp \
  --parameters=run_date=2026-05-26,source_type=crm_new_partner_leads,input_prefix=gs://complete-498806-complete-crm-raw/crm/2026-05-26/,schema_config_path=gs://complete-498806-complete-config/schemas/crm_new_partner_leads.json,output_table=complete-498806:raw.crm_new_partner_leads,rejected_output_prefix=gs://complete-498806-complete-crm-rejected/crm/2026-05-26/crm_new_partner_leads/,audit_table=complete-498806:audit.ingestion_runs
```

## Step 3H - 完成後確認

確認四張 raw table 都有資料：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  'SELECT "crm_sales" AS table_name, COUNT(*) AS row_count FROM `complete-498806.raw.crm_sales` WHERE run_date = DATE "2026-05-26"
   UNION ALL
   SELECT "crm_support", COUNT(*) FROM `complete-498806.raw.crm_support` WHERE run_date = DATE "2026-05-26"
   UNION ALL
   SELECT "crm_campaign_events", COUNT(*) FROM `complete-498806.raw.crm_campaign_events` WHERE run_date = DATE "2026-05-26"
   UNION ALL
   SELECT "crm_new_partner_leads", COUNT(*) FROM `complete-498806.raw.crm_new_partner_leads` WHERE run_date = DATE "2026-05-26"'
```

確認 audit：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  'SELECT run_date, source_type, input_count, valid_count, rejected_count, audit_ts
   FROM `complete-498806.audit.ingestion_runs`
   WHERE run_date = DATE "2026-05-26"
   ORDER BY source_type, audit_ts DESC'
```

確認 Dataflow jobs：

```bash
gcloud dataflow jobs list \
  --project=complete-498806 \
  --region=us-central1 \
  --filter='name:crm-ingest AND state=Done'
```

## Step 3I - Composer trigger contract

目前 Composer DAG 還只做到 Step 1 arrival gate。Step 3 的 production 整合方式是：`validate_crm_arrival` 成功後，用同一份 source config list 產生四個 Dataflow tasks。

source list 應維持資料化，不要在 DAG 裡複製四段不同 ingestion code：

```text
crm_sales
crm_support
crm_campaign_events
crm_new_partner_leads
```

每個 task 都傳同一個 `run_date`，差異只在：

```text
source_type
schema_config_path
output_table
rejected_output_prefix
job_name
```

## 常見風險

- 不要把 schema mapping 寫死在 Composer DAG。
- 不要只把壞資料丟掉而不寫 rejected output。
- 不要讓同一天 rerun append 重複 rows；production 應在 Dataflow 前加 partition cleanup 或 staging swap。
- 不要讓 Dataflow worker service account 取得 project-wide owner/editor。
- Flex Template build 需要 Cloud Build 與 Artifact Registry 權限；如果 build 失敗，先看 Cloud Build log，不要先改 Dataflow pipeline。
