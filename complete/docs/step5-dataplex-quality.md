# Step 5 - Data Quality Gate With Dataplex

Step 5 的目標是在資料進入 ML scoring 和 Salesforce activation 前，用 Dataplex 建立集中式 quality gate。Complete 方案需要 governance，所以 quality rules 不能只藏在 Python if/else 或個人工具裡；它們要可 review、可 audit、可重跑，並且能阻擋錯誤 campaign activation。

目前 `complete/dataplex/` 和 `complete/terraform/` 仍是 scaffold。這份文件先定義 Dataplex scan、rules、Composer gate 和 manager notification contract。

## 這一步在哪裡做

- Dataplex quality YAML/rules：`complete/dataplex/`
- Terraform resources：`complete/terraform/`
- Composer DAG gate：`complete/composer/dags/`
- BigQuery targets：`staging`、`curated`、`mart`
- Console 驗證：Dataplex、BigQuery、Monitoring、Pub/Sub、Composer/Airflow UI

## 這一步會建立/設定什麼

Production resources：

- Dataplex lake / zone / asset 或 BigQuery quality scan resources。
- Data quality rules stored in repo。
- Dataplex service account / IAM。
- Quality result output table：

```text
audit.dataplex_quality_results
```

- Monitoring alert policy。
- Pub/Sub topic for quality failure notification。
- Composer task：trigger quality scan、wait result、branch pass/fail。

最低 quality checks：

- row count 大於 0。
- required fields 不可為 null。
- email format 合理。
- duplicate business key 不超過門檻。
- CRM to Oracle join coverage 達標。
- source freshness 符合 `run_date`。
- Salesforce audience 不包含未 consent user/lead。

## Step 5 的元件關係與實作方式

這一步把 Dataform 產出的 tables 變成有 gate 的 production data：

```text
BigQuery staging / curated / mart tables
        |
        v
Dataplex data quality rules
  定義 row count、required fields、join coverage、freshness、consent checks
        |
        v
Dataplex quality scan
  實際執行 rules，產生 pass/fail result
        |
        v
Composer quality gate
  pass 才進 Step 6
  fail 就停住並通知 manager
```

各元件怎麼建立：

```text
Terraform:
  建 Dataplex scan resources、service account、Monitoring alert、Pub/Sub topic。

Repo YAML:
  寫 quality rules，讓規則可以 PR review。

gcloud dataplex datascans run 或 Composer task:
  觸發 quality scan。

BigQuery / Dataplex result:
  查 pass/fail、failed rule、failed count。
```

為什麼要這樣做：

```text
Quality gate 是 Salesforce activation 前的煞車。
它不是單純報表，而是用來阻止壞資料進 campaign。
```

## Step 5A - 確認目前 scaffold

從 repo root 執行：

```bash
ls complete/dataplex
ls complete/terraform
ls complete/composer/dags
```

目前預期是 `.gitkeep`。Dataplex YAML 和 Terraform resources 還沒補齊，所以本文件中的 Dataplex deploy 指令是後續 scaffold 的 contract。

## Step 5B - 定義 quality rule 檔案結構

已在 `complete/dataplex/` 建立三個 quality rule 檔案：

```text
complete/dataplex/
  curated_user_360_quality.yaml
  mart_salesforce_campaign_audience_quality.yaml
  staging_crm_quality.yaml
```

### 各檔案的 rules 摘要

#### `curated_user_360_quality.yaml`

| rule_id | 欄位 | 類型 | 門檻 | severity | 失敗動作 |
|---|---|---|---|---|---|
| `user_360_row_count_gt_zero` | (table) | tableCondition | COUNT > 0 | CRITICAL | BLOCK_DOWNSTREAM |
| `user_360_user_id_not_null` | user_id | nonNull | - | CRITICAL | BLOCK_DOWNSTREAM |
| `user_360_email_not_null` | email | nonNull | - | CRITICAL | BLOCK_DOWNSTREAM |
| `user_360_email_format_valid` | email | rowCondition | regex `@` + domain | HIGH | ALERT_ONLY |
| `user_360_user_id_unique` | user_id | uniqueness | - | CRITICAL | BLOCK_DOWNSTREAM |
| `user_360_consent_email_is_bool` | consent_email | rowCondition | true/false/null | HIGH | BLOCK_DOWNSTREAM |
| `user_360_deal_count_non_negative` | deal_count | rowCondition | >= 0 | MEDIUM | ALERT_ONLY |
| `user_360_won_revenue_non_negative` | won_revenue | rowCondition | >= 0 | MEDIUM | ALERT_ONLY |
| `user_360_transformed_at_fresh` | (table) | tableCondition | MAX < 25h ago | HIGH | ALERT_ONLY |

#### `mart_salesforce_campaign_audience_quality.yaml`

| rule_id | 欄位 | 類型 | 門檻 | severity | 失敗動作 |
|---|---|---|---|---|---|
| `sf_audience_row_count_gt_zero` | (table) | tableCondition | COUNT > 0 | CRITICAL | BLOCK_DOWNSTREAM |
| `sf_audience_consent_status_valid` | consent_status | rowCondition | 已知 enum | CRITICAL | BLOCK_DOWNSTREAM |
| `sf_audience_type_valid` | audience_type | rowCondition | 已知 enum | HIGH | ALERT_ONLY |
| `sf_audience_identifier_not_null` | (row) | rowCondition | user_id OR lead_email | CRITICAL | BLOCK_DOWNSTREAM |
| `sf_audience_lead_email_format` | lead_email | rowCondition | regex 或 NULL | HIGH | ALERT_ONLY |
| `sf_audience_score_in_range` | score | rowCondition | 0–100 | MEDIUM | ALERT_ONLY |
| `sf_audience_run_date_not_null` | run_date | nonNull | - | CRITICAL | BLOCK_DOWNSTREAM |
| `sf_audience_run_date_fresh` | (table) | tableCondition | MAX <= 7 days | HIGH | BLOCK_DOWNSTREAM |
| `sf_audience_segment_name_valid` | segment_name | rowCondition | 已知 enum | HIGH | ALERT_ONLY |
| `sf_audience_existing_user_not_duplicate` | (table) | tableCondition | 無重複 (run_date, user_id) | HIGH | BLOCK_DOWNSTREAM |

#### `staging_crm_quality.yaml`（以 stg_crm_sales 為主示範）

| rule_id | 欄位 | 類型 | 門檻 | severity | 失敗動作 |
|---|---|---|---|---|---|
| `stg_crm_sales_row_count_gt_zero` | (table) | tableCondition | COUNT > 0 | CRITICAL | BLOCK_DOWNSTREAM |
| `stg_crm_sales_deal_id_not_null` | deal_id | nonNull | - | CRITICAL | BLOCK_DOWNSTREAM |
| `stg_crm_sales_user_id_not_null` | user_id | nonNull | - | CRITICAL | BLOCK_DOWNSTREAM |
| `stg_crm_sales_deal_stage_valid` | deal_stage | rowCondition | 已知小寫 enum | HIGH | ALERT_ONLY |
| `stg_crm_sales_deal_amount_non_negative` | deal_amount | rowCondition | >= 0 或 NULL | MEDIUM | ALERT_ONLY |
| `stg_crm_sales_run_date_not_null` | run_date | nonNull | - | CRITICAL | BLOCK_DOWNSTREAM |
| `stg_crm_sales_ingestion_ts_fresh` | (table) | tableCondition | MAX < 25h ago | HIGH | ALERT_ONLY |

### `failureAction` 說明

```text
BLOCK_DOWNSTREAM  → Composer quality gate 遇到此 rule 失敗就停住，不繼續 Step 6
ALERT_ONLY        → 記錄到 audit table、送 Pub/Sub 通知，但不阻擋
```

> **注意**：`BLOCK_DOWNSTREAM` 是自定義慣例欄位，代表在 Composer DAG 裡的判斷邏輯。
> Dataplex datascan 本身不直接控制 DAG，Composer 需要讀取 audit 結果中 severity=CRITICAL 的 row 並決定是否繼續。



## Step 5C - 建議 quality rules

`curated.user_360`：

```text
user_id 不可為 null
email format 合理
每個 run_date + user_id 唯一
crm/oracle join coverage >= agreed threshold
latest source timestamp 不晚於 run_date 可接受範圍
```

`mart.salesforce_campaign_audience`：

```text
campaign_id 不可為 null
user_id 或 lead_email 至少一個存在
consent_status 必須允許 activation
run_date + campaign_id + user_id/lead_email 不可重複
audience row count 在預期上下限內
```

`staging` CRM tables：

```text
required business keys 不可為 null
numeric 欄位型別正確
date/timestamp 欄位可解析
source run_date 和 pipeline run_date 一致
```

## Step 5D - Terraform scaffold 補齊後建立 Dataplex 和 alert resources

預期 Terraform resources：

```text
google_dataplex_lake.crm
google_dataplex_zone.curated
google_dataplex_datascan.user_360_quality
google_dataplex_datascan.salesforce_audience_quality
google_pubsub_topic.quality_alerts
google_monitoring_alert_policy.quality_failure
google_service_account.dataplex_quality
```

部署：

```bash
cd gcp-solutions-repo/complete/terraform

terraform plan \
  -var oracle_host=10.128.0.2 \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_job_status=DISABLED \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=true \
  -var datastream_desired_state=RUNNING \
  -var enable_dataflow_crm_ingestion=true \
  -var enable_dataform_transform=true \
  -var enable_dataform_release_config=true \
  -var enable_dataplex_quality=true

terraform apply \
  -var oracle_host=10.128.0.2 \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_job_status=DISABLED \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=true \
  -var datastream_desired_state=RUNNING \
  -var enable_dataflow_crm_ingestion=true \
  -var enable_dataform_transform=true \
  -var enable_dataform_release_config=true \
  -var enable_dataplex_quality=true
```

如果 plan 會刪除既有 quality scan 或 alert policy，先停下來確認是不是 intentional migration。

## Step 5E - 手動觸發 quality scan

Dataplex scaffold 補齊後，先手動跑一個 scan：

```bash
gcloud dataplex datascans run user-360-quality \
  --project=complete-498806 \
  --location=us-central1
```

查看結果：

```bash
gcloud dataplex datascans jobs list \
  --project=complete-498806 \
  --location=us-central1 \
  --datascan=user-360-quality
```

再查 BigQuery result table：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  'SELECT * FROM `complete-498806.audit.dataplex_quality_results` ORDER BY job_start_time DESC LIMIT 20'
```

## Step 5F - Composer quality gate contract

Composer DAG 在 Step 4 Dataform 後、Step 6 ML/Salesforce 前執行 quality gate：

```text
Dataflow ingestion
-> Dataform transformation
-> Dataplex quality scans
-> quality result sensor
-> if pass: ML scoring / Salesforce activation
-> if fail: stop downstream and notify managers
```

Composer task 應將這些 metadata 寫入 audit：

```text
run_date
datascan id
job id
rule id
pass/fail
failed row count
threshold
failure message
```

Quality fail 時，不要繼續跑 Salesforce push。

## Step 5G - Manager notification contract

失敗通知至少包含：

```text
run_date
failed table
failed rule id
severity
failed count / threshold
Dataplex job URL
Airflow task URL
owner / next action
```

通知通道可以是 Monitoring email、Pub/Sub to Cloud Function、Chat webhook 或 ticketing integration。Production 由客戶通知政策決定，但通知內容必須讓 manager 能判斷是否 rerun、rollback 或 approve exception。

## 完成後確認

- Dataplex scans 可以手動執行。
- Quality rules 存在 repo，可 PR review。
- Scan results 寫到 audit table 或可由 Dataplex 查詢。
- Composer quality gate 會等待 scan 結果。
- Quality fail 會阻擋 Step 6。
- Manager notification 會包含 run date、rule、table、failed count 和 link。

## 常見風險

- 不要只在 SQL 裡做 quality check 卻沒有 audit evidence。
- 不要讓 quality fail 後仍推 Salesforce。
- 不要在 Console 手動改 production rules 而不回 repo。
- 不要用過寬 IAM 給 Dataplex 或 Composer service account。
