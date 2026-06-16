# Step 1 - Governed CRM Transfer And Arrival Sensing

Step 1 的目標是用 production-grade 的方式，把 on-prem CRM CSV 穩定送進 GCS raw landing zone，並留下 Composer 可以判斷的 transfer completion evidence。Complete 方案不是只檢查「GCS 上有沒有四個 CSV」，而是要能回答：哪一次 transfer run 成功、檔案是否完整、失敗時誰會收到通知、後續 Dataflow ingestion 能不能根據同一個 `run_date` 重跑。

目前 `complete/terraform/`、`complete/composer/dags/`、`complete/schemas/` 和 `complete/dataflow/crm-csv-ingestion/` 還是 scaffold 目錄，所以這份文件先定義 production runbook 和未來要補的 Terraform/DAG contract。現在可以先用本機 lab CSV 驗證檔案命名和 run date 結構。

## 這一步在哪裡做

- Terraform resources：`complete/terraform/`
- Composer DAG / sensor：`complete/composer/dags/`
- CRM schema config：`complete/schemas/`
- Dataflow ingestion code：`complete/dataflow/crm-csv-ingestion/`
- Lab CRM CSV：`../local-data-lab-repo/data/crm/`
- Console 驗證：Storage Transfer、Cloud Storage、Cloud Logging、Composer/Airflow UI

## 這一步會建立/設定什麼

Complete 方案建議使用獨立 buckets，讓權限、retention、audit 邊界清楚：

```text
gs://complete-498806-complete-crm-raw
gs://complete-498806-complete-crm-archive
gs://complete-498806-complete-crm-rejected
```

raw bucket 裡保留 dated folder：

```text
crm/<run_date>/
manifest/<run_date>/
```

production 會管理：

- Storage Transfer Service agent pool。
- nightly transfer job。
- raw/archive/rejected buckets 和 lifecycle policy。
- transfer failure alert path。
- manifest/audit evidence，至少包含 run date、file name、file size、checksum 或 object generation、transfer job id、operation id、status。
- Composer transfer completion sensor，先確認 transfer run 成功，再確認必要 CSV 到齊。

## Step 1 的元件關係

Step 1 會用到四個核心元件。先理解它們的關係，後面的指令就不會像在背魔法字串。

```text
Transfer Job
  定義 source path、destination bucket、schedule、overwrite policy
  指定要使用哪個 Agent Pool
        |
        v
Agent Pool
  GCP 端的 agent 群組，讓 transfer job 知道要派工給哪一群 agents
        |
        v
Transfer Agent
  跑在 on-prem server 或 lab Mac 上的 Docker container
  實際讀本機 CRM folder，並把 CSV 上傳到 GCS
        |
        v
GCS raw bucket
  接收 CRM CSV，供後續 Composer / Dataflow 使用
```

白話來說：

```text
Transfer Job = 工單
Agent Pool = 工班
Transfer Agent = 工人
GCS raw bucket = 目的地倉庫
本機 CRM folder = 原料倉庫
```

所以 Step 1D 和 Step 1E 的差別是：

```text
Step 1D:
  用 Terraform 建 GCP 端資源，例如 buckets、agent pool、transfer job、IAM。

Step 1E:
  在真正放 CRM CSV 的機器上安裝 transfer agent。
  這一步不是 Terraform apply，因為 Terraform 不能進你的 on-prem server 或 Mac 幫你啟動 Docker container。
```

## Step 1A - 確認目前 scaffold 狀態

這一步做的是 repo 現況盤點。行為上只會列出 `complete/` 底下幾個實作目錄，不會建立或修改 GCP resource；原因是先確認哪些東西還只是 scaffold，避免誤以為 Terraform、Composer DAG 或 Dataflow template 已經可以直接部署。

從 repo root 執行：

```bash
ls complete/terraform
ls complete/composer/dags
ls complete/schemas
ls complete/dataflow/crm-csv-ingestion
```

目前預期只會看到 `.gitkeep` 或空 scaffold。這代表 Terraform、Composer DAG 和 Dataflow template 尚未實作，不要直接照 production command apply。文件中的 resource name 是要補 scaffold 時遵守的 contract。

## Step 1B - 確認 lab CRM CSV 命名

這一步做的是確認 source data 已經準備好。行為上會檢查本機 lab 是否有四種 CRM CSV；原因是後面的 Storage Transfer、Dataflow 和 Composer sensor 都會以這四種檔案當作最小完整資料批次。

先回 workspace root：

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm
```

確認四種 CRM CSV 都存在：

```bash
ls -lh local-data-lab-repo/data/crm/*.csv
```

預期至少有：

```text
crm_sales_2026_05_26.csv
crm_support_2026_05_26.csv
crm_campaign_events_2026_05_26.csv
crm_new_partner_leads_2026_05_26.csv
```

如果不存在，先產生 lab data：

```bash
cd local-data-lab-repo
python3 scripts/generate_fake_data.py
cd ..
```

## Step 1C - 定義 production folder contract

這一步做的是定義 on-prem export folder 的標準格式。行為上 production team 要把每日檔案放進 dated folder；原因是 Storage Transfer、manifest、Composer rerun 和 downstream Dataflow 都需要用同一個 `run_date` 找到同一批資料。

on-prem export folder 必須用固定日期結構，讓 Storage Transfer 和 Composer 用同一個 `run_date`：

```text
crm/YYYY-MM-DD/crm_sales_YYYY_MM_DD.csv
crm/YYYY-MM-DD/crm_support_YYYY_MM_DD.csv
crm/YYYY-MM-DD/crm_campaign_events_YYYY_MM_DD.csv
crm/YYYY-MM-DD/crm_new_partner_leads_YYYY_MM_DD.csv
```

最小完整檔案集合是四個 CSV。Production 不應讓 Composer 只看 wildcard 是否有檔案；它要確認四個 source type 都有，且檔案大小大於 0。

## Step 1D - Terraform scaffold 補齊後建立 landing buckets

這一步做的是建立 GCP 端的 landing zone 和 transfer 控制資源。行為上 Terraform 會建立 raw/archive/rejected/manifest buckets，並可選擇建立 Storage Transfer agent pool 和 transfer job；原因是這些 resource 要可重複部署、可 review、可被 Terraform state 追蹤。

這一步建立的是「GCP 端工具」，不是本機 agent：

```text
Buckets:
  儲存 raw CSV、archive CSV、rejected records、manifest evidence。

Agent Pool:
  GCP 端的 agent 群組，讓 transfer job 可以找到可用的 on-prem agents。

Transfer Job:
  GCP 端的搬檔任務定義，記錄 source path、destination path、schedule 和 overwrite policy。

IAM:
  讓 Storage Transfer service agent 可以寫入 raw/manifest buckets，並使用 Pub/Sub 協調 agent。
```

Terraform 補齊後，`complete/terraform/` 應管理：

```text
google_storage_bucket.crm_raw
google_storage_bucket.crm_archive
google_storage_bucket.crm_rejected
google_storage_bucket.crm_manifest
google_storage_transfer_agent_pool.crm_agent_pool
google_storage_transfer_job.crm_nightly_transfer
google_monitoring_alert_policy.storage_transfer_failure
```

預期部署流程：

```bash
cd gcp-solutions-repo/complete/terraform

terraform init

terraform plan \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US

terraform apply \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US
```

上面會先建立 Step 1 landing buckets。若要像 lab 一樣真實建立 Storage Transfer agent pool 和 transfer job，請明確打開 transfer job，並指定本機 source folder 和 GCS sink path：

```bash
terraform plan \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED
```

確認 plan 只會新增或更新預期 resource 後，再 apply：

```bash
terraform apply \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED
```

`crm_transfer_job_status=DISABLED` 是 lab safety default：job 可以被手動 run，但不會每天自動排程。Production 要 nightly schedule 時才改成 `ENABLED`。

如果 plan 顯示要 destroy raw/archive/rejected bucket，先停下來。這些 bucket 是資料 landing 和 audit resource，不應在一般文件步驟中重建。

## Step 1E - Production path：安裝 Storage Transfer agent

這一步做的是把 on-prem 或 lab machine 接到 GCP Storage Transfer Service。
- 本機啟動一個 Docker-based transfer agent
- agent 會加入 `complete-crm-onprem-agent-pool`，並被 transfer job 派工讀取本機 CRM folder；原因是 Storage Transfer Service 不能直接讀你的本機磁碟，必須透過 agent 代表它讀檔並上傳到 GCS。

這一步建立的是「本機/on-prem 端工具」：

```text
Transfer Agent Docker container:
  實際跑在你的 Mac 或 on-prem host。
  它會讀 `--mount-directories` 指定的 CRM folder。
  它會用目前 gcloud credential 或指定 credential 連到 GCP。
  它會加入 `--pool` 指定的 agent pool。
```

為什麼這裡不用 `terraform apply`：

```text
Terraform 管 GCP resources。
Transfer agent 跑在本機或 on-prem server。
所以 agent installation 要在那台機器上用 gcloud + Docker 執行。
```

`--pool` 要填短 agent pool id：

```text
complete-crm-onprem-agent-pool
```

Transfer job 裡使用的是 full resource name：

```text
projects/complete-498806/agentPools/complete-crm-onprem-agent-pool
```

這兩個看起來很像，但用錯會讓 agent 啟動失敗。

在客戶 on-prem export host 安裝 Storage Transfer agent，並加入 Terraform 建好的 agent pool。正式安裝指令要以 Console 產生的 agent pool command 為準，不把 token 或 credential 放進 repo。

Lab 可以把這台 Mac 當成 on-prem host。注意：`gcloud transfer agents install --pool` 要使用短 agent pool id，不是 `projects/.../agentPools/...` full resource name。

```bash
mkdir -p /tmp/gcp-sts-agent-logs

gcloud transfer agents install \
  --project=complete-498806 \
  --pool=complete-crm-onprem-agent-pool \
  --count=1 \
  --id-prefix=complete-crm-lab \
  --mount-directories=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  --logs-directory=/tmp/gcp-sts-agent-logs
```

如果 agent container 啟動後要看 logs：

```bash
docker logs --tail 80 CONTAINER_ID
```

安裝成功後，Docker 會出現一個正在跑的 transfer agent container：

```bash
docker ps --filter ancestor=gcr.io/cloud-ingest/tsop-agent:latest
```

這時候 GCP Console 的 agent pool 頁面應該能看到 agent connected。Agent connected 只代表「工人在線」，還不代表資料已經搬完；資料搬移要由手動 run transfer job 或 production schedule 觸發。

Production 檢查重點：

- agent 狀態是 online。
- agent host 可以讀 CRM export folder。
- GCP project 已授權 Storage Transfer service agent 寫入 raw bucket。
- firewall / proxy policy 允許 agent 連到 Storage Transfer endpoint。
- transfer job schedule 和 on-prem export 完成時間錯開，避免抓到半成品。

## Step 1F - Production path：建立 transfer completion evidence

這一步做的是留下 transfer 成功證據。行為上會把 Storage Transfer operation status、object count、file size、hash、generation 等資訊寫成 manifest JSON，存到 manifest bucket；原因是 Composer 之後不能只看「GCS 有檔案」，而要能證明這批 `run_date` 的 transfer job 確實成功且四個檔案完整。

每次 transfer 完成後，需要留下 manifest 或 audit evidence。建議存到：

```text
gs://complete-498806-complete-crm-manifest/manifest/<run_date>/transfer_manifest.json
```

manifest schema 建議至少包含：

```json
{
  "run_date": "2026-05-26",
  "transfer_job_name": "crm-nightly-transfer",
  "transfer_operation_id": "transferOperations/...",
  "status": "SUCCESS",
  "files": [
    {
      "source_type": "crm_sales",
      "object_uri": "gs://complete-498806-complete-crm-raw/crm/2026-05-26/crm_sales_2026_05_26.csv",
      "size_bytes": 123,
      "generation": "..."
    }
  ]
}
```

manifest 可以由 Cloud Function、Cloud Run Job、Composer task 或 transfer operation inspection 產生。重點是 Composer 的第一個 gate 要讀到同一個 `run_date` 的 success evidence。

### Step 1F manual lab：真的產生 manifest

在 lab 裡，Step 1F 不是只有概念；你要真的做這幾件事：

```text
1. 查 Storage Transfer operation 結果。
2. 查 GCS raw bucket 裡四個 CSV 的 object metadata。
3. 把 operation status、counters、file size、hash、generation 組成 manifest JSON。
4. 上傳 manifest JSON 到 manifest bucket。
5. 讀回 manifest，確認 status 和 files count。
```

先查 Step 1E 那次 transfer operation：

```bash
gcloud transfer operations describe transferJobs-OPI15272529588296586998-17432585817923540314 \
  --project=complete-498806 \
  --format=json
```

你要看到：

```text
metadata.status = SUCCESS
metadata.counters.objectsCopiedToSink = 4
metadata.counters.bytesCopiedToSink = 4608352
```

查每個 GCS object metadata。這些 metadata 會進 manifest，讓後續 sensor 可以確認檔案不是只「看起來存在」，而是有 size、hash、generation 可追蹤：

```bash
gcloud storage objects describe \
  gs://complete-498806-complete-crm-raw/crm/2026-05-26/crm_sales_2026_05_26.csv \
  --format=json
```

其他三個檔案也要查：

```text
crm_support_2026_05_26.csv
crm_campaign_events_2026_05_26.csv
crm_new_partner_leads_2026_05_26.csv
```

產生本機 manifest 暫存檔。這份 JSON 是 Step 1F 的實際產物，不是 repo code：

```bash
jq -n '{
  run_date: "2026-05-26",
  generated_at_utc: (now | todateiso8601),
  project_id: "complete-498806",
  transfer_job_name: "transferJobs/OPI15272529588296586998",
  transfer_operation_id: "transferOperations/transferJobs-OPI15272529588296586998-17432585817923540314",
  status: "SUCCESS",
  destination_prefix: "gs://complete-498806-complete-crm-raw/crm/2026-05-26/",
  counters: {
    objects_found_from_source: 4,
    objects_copied_to_sink: 4,
    bytes_found_from_source: 4608352,
    bytes_copied_to_sink: 4608352
  },
  files: [
    {
      source_type: "crm_sales",
      object_uri: "gs://complete-498806-complete-crm-raw/crm/2026-05-26/crm_sales_2026_05_26.csv",
      size_bytes: 1109548,
      generation: "1780906404947857"
    },
    {
      source_type: "crm_support",
      object_uri: "gs://complete-498806-complete-crm-raw/crm/2026-05-26/crm_support_2026_05_26.csv",
      size_bytes: 316373,
      generation: "1780906404305679"
    },
    {
      source_type: "crm_campaign_events",
      object_uri: "gs://complete-498806-complete-crm-raw/crm/2026-05-26/crm_campaign_events_2026_05_26.csv",
      size_bytes: 2762698,
      generation: "1780906405537333"
    },
    {
      source_type: "crm_new_partner_leads",
      object_uri: "gs://complete-498806-complete-crm-raw/crm/2026-05-26/crm_new_partner_leads_2026_05_26.csv",
      size_bytes: 419733,
      generation: "1780906404809125"
    }
  ]
}' > /tmp/complete-transfer-manifest-2026-05-26.json
```

上傳 manifest 到 manifest bucket：

```bash
gcloud storage cp \
  /tmp/complete-transfer-manifest-2026-05-26.json \
  gs://complete-498806-complete-crm-manifest/manifest/2026-05-26/transfer_manifest.json
```

讀回驗證：

```bash
gcloud storage cat \
  gs://complete-498806-complete-crm-manifest/manifest/2026-05-26/transfer_manifest.json \
  | jq '.status, .counters, (.files | length)'
```

預期看到：

```text
"SUCCESS"
objects_copied_to_sink = 4
4
```

Lab 真實跑完一次後，本次 manifest 實際位置是：

```text
gs://complete-498806-complete-crm-manifest/manifest/2026-05-26/transfer_manifest.json
```

## Step 1G - Composer arrival sensor contract

這一步做的是 **定義** Composer DAG 的第一道 gate，寫好安全規則，不會真的啟動composer service，實作會等到`step7`。行為上 Composer 會先讀 Step 1F 的 manifest，確認 transfer status 是 `SUCCESS`，再檢查四個必要 CSV 都存在且大小大於 0；原因是避免 pipeline 在半套檔案、舊檔案或失敗 transfer 的情況下啟動 Dataflow。

這一步建立的是 Composer DAG 的第一段檢查，不是搬資料：

```text
DAG file:
  complete/composer/dags/complete_crm_nightly_pipeline.py

Task:
  validate_crm_arrival

它會讀：
  gs://complete-498806-complete-crm-manifest/manifest/<run_date>/transfer_manifest.json

它會檢查：
  manifest.status == SUCCESS
  manifest 裡有四個 required source_type
  raw bucket 裡四個 CSV 都存在
  每個 CSV size > 0
  manifest object_uri 和實際 GCS object path 一致

它通過後：
  才進入 ready_for_dataflow。
  之後 Step 3 Dataflow ingestion task 會接在這個 task 後面。
```

Composer DAG 的第一段應做兩層檢查：

```text
1. transfer completion sensor:
   確認 run_date 對應的 Storage Transfer operation 是 SUCCESS。

2. required file sensor:
   確認四個 CRM CSV 都存在，大小大於 0，且 manifest 中有紀錄。
```

不要只做 `GCSObjectExistenceSensor` 看 wildcard，否則可能抓到上一次殘留檔案或半套資料。

目前 repo 已提供 Step 1G DAG scaffold：

```text
complete/composer/dags/complete_crm_nightly_pipeline.py
```

先做本機 syntax check：

```bash
python3 -m py_compile complete/composer/dags/complete_crm_nightly_pipeline.py
```

等 Step 7 建好 Composer environment 後，lab/debug 可以手動上傳 DAG：

```bash
gcloud composer environments storage dags import \
  --project=complete-498806 \
  --location=us-central1 \
  --environment=<composer-env-name> \
  --source=complete/composer/dags/complete_crm_nightly_pipeline.py
```

手動觸發 DAG 時傳入 `run_date`：

```bash
gcloud composer environments run <composer-env-name> \
  --project=complete-498806 \
  --location=us-central1 \
  dags trigger -- complete_crm_nightly_pipeline \
  --conf '{"run_date":"2026-05-26"}'
```

如果 `validate_crm_arrival` fail，代表 Step 1F manifest 或 Step 1E raw files 有問題；不要進 Step 3 Dataflow。

## Step 1H - Lab path：手動模擬 raw prefix

這一步做的是提供沒有 Storage Transfer 時的 lab fallback。行為上會用 `gcloud storage cp` 手動把 CSV 放到 raw bucket；原因是讓後續 Dataflow/Dataform 練習可以先繼續，但 production 仍應使用 Step 1E 的 Storage Transfer agent flow。

如果 Terraform 和 Storage Transfer 尚未補齊，但你想先讓後續文件理解資料路徑，可以手動模擬 GCS path。這只是 lab，不代表 production 用手動 upload 取代 Storage Transfer。

```bash
export RUN_DATE=2026-05-26
export PROJECT_ID=complete-498806

gcloud storage cp local-data-lab-repo/data/crm/*.csv \
  gs://${PROJECT_ID}-complete-crm-raw/crm/${RUN_DATE}/
```

驗證 object count：

```bash
gcloud storage ls gs://${PROJECT_ID}-complete-crm-raw/crm/${RUN_DATE}/ | wc -l
```

預期是 `4`。

如果 Step 1D 已建立 Storage Transfer job，也可以手動觸發一次真實 transfer：

這個指令做的是要求 GCP 立即執行 transfer job。行為上 GCP 會找到 job 指定的 agent pool，再派工作給 Step 1E 裝好的 local agent；原因是 lab 不想等 nightly schedule，但仍然想驗證真實 Storage Transfer path。

```bash
gcloud transfer jobs run transferJobs/OPI15272529588296586998 \
  --project=complete-498806 \
  --no-async
```

驗證 operation counters：

```bash
gcloud transfer operations describe transferJobs-OPI15272529588296586998-OPERATION_ID \
  --project=complete-498806 \
  --format='json(metadata.status,metadata.counters)'
```

## 完成後確認

- Storage Transfer agent pool 有 online agent。
- nightly transfer job 有 successful operation history。
- transfer failure alert path 已設定。
- raw bucket 有 `crm/<run_date>/` 四個必要 CSV。
- manifest/audit evidence 可以查到 run date、檔名、大小、status、operation id。
- Composer arrival sensor 對同一個 `run_date` pass。
- 下一步 Dataflow ingestion 只在 transfer success 和 required files 完整時才啟動。

## 常見風險

- 不要把 on-prem credential、agent token 或 service account key 放進 repo。
- 不要讓 transfer schedule 早於 on-prem CSV 產生完成時間。
- 不要讓 Composer 只用 wildcard 檢查檔案存在。
- 不要在 production 手動改 bucket lifecycle 或 IAM，避免 Terraform drift。
