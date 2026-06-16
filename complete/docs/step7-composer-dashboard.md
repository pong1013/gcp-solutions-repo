# Step 7 - Composer Dashboard And Task Rerun

Step 7 的目標是用 Cloud Composer 管理完整 pipeline dependency、dashboard、logs 和 task-level rerun。Complete 方案選 Composer，是因為客戶需要看得到整條 DAG、能定位 failed task、能只重跑單一步驟，而不是只能重跑整條 nightly job。

本 repo 已補齊 Step 7 必要資源定義，但本文件不會替你建立 GCP 資源。請依照下面指令自行 `terraform plan`、確認沒有意外 destroy 後再 `terraform apply`。

## 這一步在哪裡做

- Composer Terraform：`complete/terraform/composer.tf`
- Terraform variables：`complete/terraform/variables.tf`
- Terraform outputs：`complete/terraform/outputs.tf`
- Production DAG：`complete/composer/dags/complete_crm_nightly_pipeline.py`
- Console 驗證：Composer / Airflow UI、Cloud Logging、BigQuery audit tables

## 這一步會建立/設定什麼

Terraform 會建立：

- Cloud Composer environment：`complete-crm-composer`
- Composer worker service account：`complete-composer-worker`
- Composer service agent extension IAM
- Composer worker IAM：
  - Dataflow developer
  - Dataform editor
  - Dataplex editor
  - Cloud Run developer/invoker
  - BigQuery job user
  - Storage object viewer
  - Logging writer
- Service account user bindings：
  - Composer 可使用 Dataflow worker service account
  - Composer 可使用 Salesforce Cloud Run Job service account
- BigQuery audit tables：
  - `audit.pipeline_step_status`
  - `audit.rerun_history`
- Composer environment variables for DAG execution

Composer 是高固定成本服務。Production 才建立；lab 若只是閱讀方案，不需要開。

## Step 7 的 DAG graph

`complete_crm_nightly_pipeline` 會提供以下 task-level dashboard：

```text
start
-> validate_crm_arrival
-> ingest_crm_sales
-> ingest_crm_support
-> ingest_crm_campaign_events
-> ingest_crm_new_partner_leads
-> wait_for_oracle_datastream_freshness
-> run_dataform_transformations
-> run_user_360_quality_scan
-> run_salesforce_audience_quality_scan
-> quality_gate
-> salesforce_dry_run
-> branch_on_salesforce_write
-> salesforce_push 或 salesforce_push_skipped
-> end
```

預設 Salesforce production write 會被跳過。要真的寫 Salesforce，必須在 DAG trigger conf 裡明確設定：

```json
{
  "skip_salesforce_write": false,
  "salesforce_campaign_id": "701gK000018hdjOQAQ",
  "salesforce_limit": 1
}
```

## Step 7A - 確認前置資源已完成

Step 7 依賴 Step 1-6 的資源。先確認：

```bash
cd gcp-solutions-repo/complete/terraform

terraform output crm_bucket_names
terraform output dataflow_template_bucket_url
terraform output dataform_repository_name
terraform output dataplex_lake_name
terraform output salesforce_cloud_run_job_name
```

必要條件：

```text
Step 1 Storage Transfer / manifest bucket 已建立
Step 2 Oracle Datastream 已可提供 raw.APP_USER_RAW
Step 3 Dataflow Flex Template image/template 已 build
Step 4 Dataform SQLX 已上傳並可執行
Step 5 Dataplex DataScans 已建立
Step 6 Salesforce Cloud Run Job image 已 build，dry-run 與 1 筆 production smoke test 已通過
```

## Step 7B - Terraform plan Composer resources

行為：檢查 Composer environment、IAM、audit tables 的新增計畫。

原因：Composer 會新增昂貴資源，且這次 plan 必須保留 Step 1-6 既有變數，避免 Terraform 把前面資源改回預設值。

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
  -var enable_ml_salesforce_push=true \
  -var enable_composer_orchestration=true
```

Plan 預期應新增或確認：

```text
google_service_account.composer
google_composer_environment.complete
google_bigquery_table.pipeline_step_status
google_bigquery_table.rerun_history
Composer IAM bindings
```

如果 plan 顯示會 destroy Oracle VM、BigQuery datasets、Dataform repository、Datastream stream、Salesforce job，先停下來，不要 apply。

## Step 7C - Apply Composer resources

確認 plan 只有 Step 7 相關新增/更新後，由你手動 apply：

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
  -var enable_ml_salesforce_push=true \
  -var enable_composer_orchestration=true
```

驗證 outputs：

```bash
terraform output composer_environment_name
terraform output composer_service_account_email
terraform output composer_dag_gcs_prefix
terraform output composer_airflow_uri
```

如果 Composer 已經在 GCP 上建立成功，但 `terraform apply` 因為斷線、中斷或 timeout 沒有把 state 寫回，下一次 plan 可能會出現：

```text
google_composer_environment.complete[0] will be created
Error 409: Environment already exists
```

這時不要刪 Composer，也不要重建。把既有 environment import 回 Terraform state：

```bash
terraform import \
  'google_composer_environment.complete[0]' \
  projects/complete-498806/locations/us-central1/environments/complete-crm-composer
```

然後重跑同一組 `terraform plan` / `terraform apply`。預期只會補 IAM 或 outputs，不應再建立 Composer environment。

## Step 7D - 驗證 Composer environment

```bash
gcloud composer environments describe complete-crm-composer \
  --project=complete-498806 \
  --location=us-central1 \
  --format='value(state)'
```

預期：

```text
RUNNING
```

列出 Airflow DAGs：

```bash
gcloud composer environments run complete-crm-composer \
  --project=complete-498806 \
  --location=us-central1 \
  dags list
```

## Step 7E - 部署 DAG

手動上傳 DAG：

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm

gcloud composer environments storage dags import \
  --project=complete-498806 \
  --location=us-central1 \
  --environment=complete-crm-composer \
  --source=gcp-solutions-repo/complete/composer/dags/complete_crm_nightly_pipeline.py
```

確認 DAG 出現：

```bash
gcloud composer environments run complete-crm-composer \
  --project=complete-498806 \
  --location=us-central1 \
  dags list -- | grep complete_crm_nightly_pipeline
```

如果 DAG import error，查看 Airflow import errors：

```bash
gcloud composer environments run complete-crm-composer \
  --project=complete-498806 \
  --location=us-central1 \
  dags list-import-errors
```

## Step 7F - 第一次手動觸發 DAG

第一次請跳過 Salesforce production write，只跑到 dry-run：

```bash
AIRFLOW_URI="$(gcloud composer environments describe complete-crm-composer \
  --project=complete-498806 \
  --location=us-central1 \
  --format='value(config.airflowUri)')"

curl -s -X POST \
  "${AIRFLOW_URI}/api/v1/dags/complete_crm_nightly_pipeline/dagRuns" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "dag_run_id": "dry-run-2026-05-26-'$(date +%Y%m%d%H%M%S)'",
    "conf": {
      "run_date": "2026-05-26",
      "mode": "full",
      "skip_salesforce_write": true,
      "salesforce_campaign_id": "701gK000018hdjOQAQ",
      "salesforce_limit": 1,
      "create_missing_contacts": false
    }
  }'
```

查 DAG run 請以 Airflow UI 為準：

```bash
open "${AIRFLOW_URI}"
```

`gcloud composer environments run ... dags trigger/list-runs` 會透過 Composer command runner 遠端執行 Airflow CLI。這層在新建 Composer 或控制面同步時可能回：

```text
Execution not found
```

如果 Airflow UI 和 REST API 正常，這通常不是 DAG 失敗。也可以用 BigQuery audit 查 task 狀態：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT run_date, dag_run_id, task_id, try_number, status, started_at, ended_at, message
  FROM `complete-498806.audit.pipeline_step_status`
  ORDER BY started_at DESC
  LIMIT 30
  '
```

## Step 7G - 觸發包含 Salesforce write 的 DAG

只有 Step 7F 成功、且 Step 6 的 1 筆 production smoke test 已成功時，才允許：

```bash
AIRFLOW_URI="$(gcloud composer environments describe complete-crm-composer \
  --project=complete-498806 \
  --location=us-central1 \
  --format='value(config.airflowUri)')"

curl -s -X POST \
  "${AIRFLOW_URI}/api/v1/dags/complete_crm_nightly_pipeline/dagRuns" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "dag_run_id": "salesforce-smoke-2026-05-26-'$(date +%Y%m%d%H%M%S)'",
    "conf": {
      "run_date": "2026-05-26",
      "mode": "salesforce-smoke",
      "skip_salesforce_write": false,
      "salesforce_campaign_id": "701gK000018hdjOQAQ",
      "salesforce_limit": 1,
      "create_missing_contacts": false,
      "salesforce_allow_repeat": true
    }
  }'
```

`salesforce_allow_repeat=true` 只建議用在 1 筆 smoke test。原因是 Step 6 可能已經對同一個 `run_date` / `campaign_id` 有成功紀錄；smoke test 需要允許重跑，實際 CampaignMember 仍會用 Salesforce 既有成員查詢避免重複建立。

不要直接全量 Salesforce write。你目前 Salesforce Run As user 不能自動建立 Lead/Contact；全量 2454 筆會因 fake emails 沒有對應 Contact/Lead 而失敗。

驗證 Salesforce 寫入結果：

- Airflow UI：看 `salesforce_dry_run` 和 `salesforce_push` task 是否成功，以及 task logs 裡 Cloud Run Job execution。
- BigQuery：查 `audit.salesforce_push_runs`，確認最新 production smoke test 是 `status = SUCCESS`、`is_dry_run = false`、`records_processed = 1`。
- Salesforce UI：打開 Campaign `701gK000018hdjOQAQ`，進入「相關」頁籤，查看「行銷活動成員 / Campaign Members」清單。Airflow UI 不會顯示 Salesforce 物件資料本身，只顯示 orchestrated task 狀態與 logs。

## Step 7H - Task-level rerun procedure

在 Airflow UI：

```text
1. 打開 complete_crm_nightly_pipeline。
2. 選定 dag run。
3. 找到 failed task。
4. 查看 logs 和 upstream/downstream 狀態。
5. 修正資料、權限或參數。
6. Clear failed task。
7. 只 rerun 該 task 和必要 downstream tasks。
```

CLI rerun 單一 failed task：

```bash
gcloud composer environments run complete-crm-composer \
  --project=complete-498806 \
  --location=us-central1 \
  tasks clear -- complete_crm_nightly_pipeline \
  --task-regex salesforce_dry_run \
  --start-date 2026-05-26 \
  --end-date 2026-05-26 \
  --only-failed \
  --yes
```

Salesforce write task rerun 前，先確認 CampaignMember dedupe、`salesforce_limit`、`salesforce_campaign_id` 都正確。

Cloud Run Job 的 task retry 應由 Airflow rerun 控制；Terraform 會把 `salesforce-campaign-push` 的 `max_retries` 設成 `0`。如果 Cloud Run 自己重試，Airflow 會等同一個錯誤重跑多次，debug 時間會被拉長。

## Step 7I - Dashboard 和 audit query

Airflow UI 是 task-level dashboard；BigQuery audit table 是 manager/reporting dashboard 來源。

查最近 pipeline status：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT
    run_date,
    dag_id,
    dag_run_id,
    task_id,
    try_number,
    status,
    started_at,
    ended_at,
    message
  FROM `complete-498806.audit.pipeline_step_status`
  ORDER BY started_at DESC
  LIMIT 50
  '
```

查 rerun history：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT *
  FROM `complete-498806.audit.rerun_history`
  ORDER BY started_at DESC
  LIMIT 50
  '
```

查 Dataplex quality gate 使用的 rule-level 結果：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT
    data_quality_scan.data_scan_id AS scan_id,
    rule_name,
    rule_column,
    rule_passed,
    rule_rows_evaluated,
    rule_rows_passed_percent,
    job_start_time
  FROM `complete-498806.audit.dataplex_quality_results`
  WHERE job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 12 HOUR)
  ORDER BY job_start_time DESC, scan_id, rule_name
  LIMIT 50
  '
```

注意：Dataplex results table 的 rule-level 欄位是 `rule_passed`，不是 `passed`。整體 job-level 結果在 `job_quality_result.passed`。

查 Salesforce push audit：

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

## 常見風險

- 不要在 plan 顯示 destroy 前面步驟資源時 apply。
- 不要把 Composer 當資料處理引擎；它只負責 orchestration。
- Dataflow task rerun 要確認同一 `run_date` 不會重複 append。
- Dataform task rerun 要確認 SQLX 已 commit 到 Dataform repository。
- Dataplex quality fail 時，不要繼續 Salesforce write。
- Salesforce write 預設應小批量驗證，不能直接全量。
