# Step 8 - Template Deployment With Terraform And Cloud Build

Step 8 的目標是把 Complete 方案從「本機手動部署」整理成「可 review、可重跑、可稽核的 deployment template」。這一步不新增新的資料處理邏輯；它補齊 Terraform remote state、Cloud Build CI/CD config、部署順序、approval gate 和 smoke test 指令。

本 repo 已新增 Step 8 必要檔案：

- `complete/cloudbuild.yaml`：CI，做格式檢查、語法檢查、Dataform compile、Docker build，不改 GCP production resource。
- `complete/cloudbuild-deploy.yaml`：CD，build/push artifacts、Terraform plan/apply、部署 Composer DAG。
- `complete/terraform/backend.tf.gcs.example`：GCS remote backend scaffold。
- `complete/terraform/terraform.tfvars.complete.example`：完整變數範例。
- `.gcloudignore` / `complete/.gcloudignore`：避免 state、plan、cache 進 Cloud Build context。

以下指令只提供給你逐步執行；不要在沒有看 plan 的情況下 apply。

## Step 8A - 確認 repo 不含 secrets

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo

grep -RInEi 'password|secret|token|client_secret|private_key|BEGIN PRIVATE KEY' complete \
  --exclude-dir=.terraform \
  --exclude='*.tfstate' \
  --exclude='*.tfstate.*' \
  --exclude='terraform.tfvars'

find complete -type f \( -name '*.key' -o -name '*.pem' \) -print
```

可接受的是 secret 名稱、placeholder 或文件說明；不可接受的是實際 credential。

## Step 8B - 建立 Terraform remote state bucket

Terraform backend 不能自己先建立自己，所以 state bucket 要先手動建立一次：

```bash
gcloud storage buckets create gs://complete-498806-complete-tfstate \
  --project=complete-498806 \
  --location=US \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update gs://complete-498806-complete-tfstate \
  --versioning
```

驗證：

```bash
gcloud storage buckets describe gs://complete-498806-complete-tfstate \
  --format='value(name,location,versioning.enabled)'
```

## Step 8C - 啟用 GCS backend 並遷移本機 state

這一步是 CD 前的必要步驟。前面 Step 1-7 都是用本機 `terraform.tfstate` 建立資源；如果沒有先遷移到 GCS backend，Cloud Build 會看到空 state，然後嘗試重新建立 raw dataset、buckets、service accounts、Composer、Dataplex 等既有資源，最後出現大量 `409 Already Exists`。

先複製 backend scaffold：

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo/complete/terraform

cp backend.tf.gcs.example backend.tf
```

把目前本機 state 遷移到 GCS backend：

```bash
terraform init -migrate-state \
  -backend-config='bucket=complete-498806-complete-tfstate' \
  -backend-config='prefix=complete/terraform'
```

驗證 Terraform 還能讀到既有資源：

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo/complete/terraform

terraform state list | head
terraform validate
```

如果 Terraform 要求確認 migration，確認來源是目前本機 `terraform.tfstate`，目的地是上面的 GCS bucket 後再輸入 `yes`。

如果你已經不小心跑過 CD，remote backend 可能有一份不完整 state。請先備份本機 state，再用本機完整 state 覆蓋 remote state：

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo/complete/terraform

cp terraform.tfstate terraform.tfstate.before-remote-migration

cp backend.tf.gcs.example backend.tf

terraform init -reconfigure \
  -backend-config='bucket=complete-498806-complete-tfstate' \
  -backend-config='prefix=complete/terraform'

terraform state push -force terraform.tfstate.before-remote-migration

terraform state list | head
```

只有在本機 state 是前面 Step 1-7 的完整 state 時才使用 `terraform state push -force`。如果不確定，先停下來比較 local/remote state。

## Step 8D - 建立 tfvars 檔

先從範例複製：

```bash
cp terraform.tfvars.complete.example terraform.tfvars
```

確認 `terraform.tfvars` 裡的值符合目前環境，尤其是：

- `project_id = "complete-498806"`
- `oracle_host = "10.128.0.2"`
- `datastream_desired_state = "RUNNING"`
- `enable_composer_orchestration = true`
- `crm_transfer_job_status = "DISABLED"`

本機 plan：

```bash
terraform fmt -check
terraform validate
terraform plan -var-file=terraform.tfvars
```

如果 plan 顯示要 destroy 或 replace 已成功的 Datastream、Composer、BigQuery datasets、Dataform repository、Cloud Run job，先停下來。

`terraform.tfvars` 是本機或部署環境設定檔，不應送進 Cloud Build context；repo 的 `.gcloudignore` 已排除它。CI 只檢查 `.tf` resource 檔格式。

## Step 8E - 授權 Cloud Build service account

查 Cloud Build 可能使用的 service accounts：

```bash
PROJECT_NUMBER="$(gcloud projects describe complete-498806 --format='value(projectNumber)')"
COMPUTE_BUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
LEGACY_CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

echo "${COMPUTE_BUILD_SA}"
echo "${LEGACY_CLOUDBUILD_SA}"
```

`gcloud builds submit` 在這個 project 目前使用的是 compute default service account：

```text
875659388420-compute@developer.gserviceaccount.com
```

Cloud Build Trigger 可能使用 legacy Cloud Build service account 或你在 UI 指定的 deploy service account。Lab 可先同時授權上面兩個 service account；Production 應改成更細的 least privilege 或部署專用 service account。

```bash
for SA in "${COMPUTE_BUILD_SA}" "${LEGACY_CLOUDBUILD_SA}"
do
  for ROLE in \
    roles/serviceusage.serviceUsageAdmin \
    roles/serviceusage.serviceUsageConsumer \
    roles/storage.admin \
    roles/storagetransfer.admin \
    roles/artifactregistry.admin \
    roles/cloudbuild.builds.editor \
    roles/logging.logWriter \
    roles/logging.admin \
    roles/resourcemanager.projectIamAdmin \
    roles/iam.serviceAccountAdmin \
    roles/iam.serviceAccountUser \
    roles/bigquery.admin \
    roles/datastream.admin \
    roles/dataflow.developer \
    roles/dataform.admin \
    roles/dataplex.admin \
    roles/composer.admin \
    roles/run.admin \
    roles/secretmanager.admin \
    roles/monitoring.admin \
    roles/pubsub.admin \
    roles/compute.admin
  do
    gcloud projects add-iam-policy-binding complete-498806 \
      --member="serviceAccount:${SA}" \
      --role="${ROLE}" \
      --condition=None
  done
done
```

Dataflow Flex Template build 會在 Cloud Build 裡呼叫 Cloud Build/Cloud Storage 產生 template artifact，因此還需要確認幾個 bucket-level 權限。先確認 bucket 存在：

```bash
gcloud storage buckets describe gs://complete-498806_cloudbuild
gcloud storage buckets describe gs://complete-498806-complete-tfstate
gcloud storage buckets describe gs://complete-498806-complete-dataflow-templates
```

授權實際 build service accounts 讀寫 Cloud Build source bucket、Terraform state bucket、Dataflow template bucket：

```bash
for SA in "${COMPUTE_BUILD_SA}" "${LEGACY_CLOUDBUILD_SA}"
do
  for BUCKET in \
    complete-498806_cloudbuild \
    complete-498806-complete-tfstate \
    complete-498806-complete-dataflow-templates
  do
    gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
      --member="serviceAccount:${SA}" \
      --role="roles/storage.objectAdmin"
  done
done
```

如果 `gcloud dataflow flex-template build` 回：

```text
The user is forbidden from accessing the bucket [complete-498806_cloudbuild]
serviceusage.services.use
```

代表實際 build service account 少了 `roles/serviceusage.serviceUsageConsumer` 或 `complete-498806_cloudbuild` bucket 權限，重跑上面兩段 IAM 指令。

Artifact Registry push 也需要 Docker auth：

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev
```

## Step 8F - 跑 CI Cloud Build

CI 不會 apply，只做檢查與 build：

```bash
cd /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/gcp-solutions-repo

gcloud builds submit . \
  --project=complete-498806 \
  --config=complete/cloudbuild.yaml \
  --substitutions=_REGION=us-central1
```

預期通過：

- Terraform fmt / validate
- Python compile
- JSON / Dataplex YAML parse
- Dataform compile
- Salesforce job Docker build

## Step 8G - 跑 CD Cloud Build plan/apply

CD 會 build/push artifacts、跑 Terraform plan/apply、上傳 Composer DAG。Production 建議用 Cloud Build Trigger 的 approval gate；lab 可手動 submit。

```bash
gcloud builds submit . \
  --project=complete-498806 \
  --config=complete/cloudbuild-deploy.yaml \
  --substitutions=_REGION=us-central1,_BUCKET_LOCATION=US,_TF_STATE_BUCKET=complete-498806-complete-tfstate,_TF_STATE_PREFIX=complete/terraform,_ORACLE_HOST=10.128.0.2,_ORACLE_SERVICE_NAME=XEPDB1,_ORACLE_USERNAME=C##DATASTREAM,_DATASTREAM_DESIRED_STATE=RUNNING,_CRM_TRANSFER_JOB_STATUS=DISABLED
```

如果要 production trigger，建議在 Cloud Build UI 建兩個 trigger：

```text
complete-ci-check:
  用途：PR / push 檢查，不 apply。
  Config file：complete/cloudbuild.yaml
  Approval：不需要。

complete-cd-deploy:
  用途：main branch 或手動 production deployment。
  Config file：complete/cloudbuild-deploy.yaml
  Approval：Required。
```

### Step 8G-1 - 連線 repository

如果 Cloud Build 還沒連到 GitHub/repo：

```text
1. 進入 Google Cloud Console。
2. 切到 project：complete-498806。
3. 打開 Cloud Build > Repositories。
4. 點 Connect repository。
5. Source provider 選 GitHub。
6. 授權 Google Cloud Build GitHub App。
7. 選 repository：gcp-solutions-repo。
8. 完成連線。
```

如果你不想接 GitHub，也可以先用前面的 `gcloud builds submit` 手動跑；Trigger 是 production deployment flow 的正式化版本。

### Step 8G-2 - 建立 CI trigger

CI trigger 只做檢查，不會 apply：

```text
1. 進入 Google Cloud Console。
2. 切到 project：complete-498806。
3. 打開 Cloud Build > Triggers。
4. 點 Create trigger。
5. Name 填：complete-ci-check。
6. Region 選：Global，或與 repo 連線相同的 region。
7. Event 選：Push to a branch。
8. Source 選你的 GitHub / Cloud Source Repositories 連線。
9. Repository 選：gcp-solutions-repo。
10. Branch 填：^main$。
11. Configuration 選：Cloud Build configuration file。
12. Location 選：Repository。
13. Cloud Build configuration file location 填：complete/cloudbuild.yaml。
14. Service account 選：875659388420-compute@developer.gserviceaccount.com。
15. 不要勾 Require approval before build executes。
16. Substitution variables 填：_REGION = us-central1。
17. 儲存 trigger。
```

### Step 8G-3 - 建立 CD trigger

CD trigger 會跑 `terraform apply`，必須開 approval：

```text
1. Cloud Build > Triggers > Create trigger。
2. Name 填：complete-cd-deploy。
3. Region 選：Global，或與 repo 連線相同的 region。
4. Event 建議先選：Manual invocation。
   若 production 流程已成熟，再改成 Push to a branch。
5. Source 選你的 repository 連線。
6. Repository 選：gcp-solutions-repo。
7. Branch 填：^main$。
8. Configuration 選：Cloud Build configuration file。
9. Location 選：Repository。
10. Cloud Build configuration file location 填：complete/cloudbuild-deploy.yaml。
11. Service account 選：875659388420-compute@developer.gserviceaccount.com，或 production 專用 deploy service account。
12. 勾選 Require approval before build executes。
13. Substitution variables 填下面這組值。
14. 儲存 trigger。
```

CD substitution variables：

```text
_REGION = us-central1
_BUCKET_LOCATION = US
_TF_STATE_BUCKET = complete-498806-complete-tfstate
_TF_STATE_PREFIX = complete/terraform
_CRM_TRANSFER_SOURCE_ROOT_DIRECTORY = /Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26
_CRM_TRANSFER_SINK_PATH = crm/2026-05-26/
_CRM_TRANSFER_JOB_STATUS = DISABLED
_ORACLE_HOST = 10.128.0.2
_ORACLE_SERVICE_NAME = XEPDB1
_ORACLE_USERNAME = C##DATASTREAM
_DATASTREAM_DESIRED_STATE = RUNNING
```

### Step 8G-4 - 手動執行 CD trigger

第一次不要靠 push 自動部署，請手動跑：

```text
1. Cloud Build > Triggers。
2. 找 complete-cd-deploy。
3. 點 Run。
4. 確認 substitutions 是上面那組值。
5. 點 Run trigger。
6. 進入 build detail。
7. 等待 approval 狀態。
8. 打開 terraform-plan step log。
9. 確認沒有非預期 destroy/replace。
10. 點 Approve。
```

注意事項：

- `Require approval before build executes` 是 production gate。不要省略。
- Trigger 建好後，第一次建議用 `Run trigger` 手動跑，不要直接靠 push 自動部署。
- Approval 前要打開 build detail 看 `terraform-plan` step log，確認沒有非預期 destroy/replace。
- 如果使用 production 專用 deploy service account，請把 Step 8E 的 IAM roles 綁到那個 service account，而不是預設 Cloud Build service account。
- Trigger 如果指定 service account，Cloud Build YAML 不能使用 legacy logs 設定；本 repo 的 `complete/cloudbuild.yaml` 和 `complete/cloudbuild-deploy.yaml` 已使用 `options.logging: CLOUD_LOGGING_ONLY`。若看到 `if 'build.service_account' is specified...`，代表 trigger 正在使用舊版 YAML，請先 push 最新 commit 後再重跑。
- 目前 `cloudbuild-deploy.yaml` 會執行 `terraform apply`。如果只是想測 trigger，不要用 CD trigger，請先跑 `complete/cloudbuild.yaml` 的 CI trigger。

## Step 8H - CD 後 smoke test

先確認 Composer DAG 還在：

```bash
AIRFLOW_URI="$(gcloud composer environments describe complete-crm-composer \
  --project=complete-498806 \
  --location=us-central1 \
  --format='value(config.airflowUri)')"

echo "${AIRFLOW_URI}"
```

用 Airflow REST API 跑 dry-run DAG：

```bash
curl -s -X POST \
  "${AIRFLOW_URI}/api/v1/dags/complete_crm_nightly_pipeline/dagRuns" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "dag_run_id": "step8-dry-run-2026-05-26-'$(date +%Y%m%d%H%M%S)'",
    "conf": {
      "run_date": "2026-05-26",
      "mode": "step8-smoke",
      "skip_salesforce_write": true,
      "salesforce_campaign_id": "701gK000018hdjOQAQ",
      "salesforce_limit": 1,
      "create_missing_contacts": false
    }
  }'
```

查 audit：

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

如果要驗證 Salesforce production path，只跑 1 筆：

```bash
curl -s -X POST \
  "${AIRFLOW_URI}/api/v1/dags/complete_crm_nightly_pipeline/dagRuns" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "dag_run_id": "step8-salesforce-smoke-2026-05-26-'$(date +%Y%m%d%H%M%S)'",
    "conf": {
      "run_date": "2026-05-26",
      "mode": "step8-salesforce-smoke",
      "skip_salesforce_write": false,
      "salesforce_campaign_id": "701gK000018hdjOQAQ",
      "salesforce_limit": 1,
      "salesforce_allow_repeat": true,
      "create_missing_contacts": false
    }
  }'
```

驗證 Salesforce push audit：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  '
  SELECT *
  FROM `complete-498806.audit.salesforce_push_runs`
  ORDER BY started_at DESC
  LIMIT 10
  '
```

不要拿掉 `salesforce_limit` 做全量 production write，除非 Salesforce 已有對應 Contact/Lead 或你已完成權限與資料準備。

## Step 8I - Production approval checklist

Technical manager approve 前至少確認：

- `terraform plan` 沒有非預期 destroy/replace。
- Terraform state 已在 GCS backend，沒有把 `terraform.tfstate` commit。
- Secret Manager 只管理 secret containers，不把 secret payload 寫進 repo 或 state。
- Cloud Build logs 沒印出 token、client secret、private key。
- Composer DAG 預設 `skip_salesforce_write=true`。
- Salesforce production write 只能用 `salesforce_limit=1` smoke test，不能直接全量。
- Datastream desired state、Storage Transfer schedule、Composer schedule 都是明確 approval 後才啟用。

## Step 8J - Drift control

Production 不應在 Console 手動改資源。若 emergency hotfix 必須手動改：

```text
1. 記錄變更原因、時間、操作者。
2. 回補 Terraform / DAG / SQL / code。
3. 跑 terraform plan 確認 drift 被收斂。
4. 走 PR review 和 Cloud Build CI/CD。
```

## 完成條件

Step 8 完成時，你應該能證明：

- GCS remote backend 已啟用。
- CI Cloud Build 可以成功檢查 repo。
- CD Cloud Build 可以產生 deployment record。
- Terraform plan/apply 由同一套 template 驅動。
- Composer DAG 可由 REST API smoke test。
- Salesforce production path 只用 1 筆 smoke test 驗證。
- 後續 production 變更有 PR review、Cloud Build logs、Terraform state 可追溯。
