# Step 2 - Oracle CDC With Datastream

Step 2 的目標是用 Datastream CDC 把 Oracle `APP.USER_RAW` 同步到 BigQuery `raw.APP_USER_RAW`。Complete 方案保留 Datastream，是因為 Oracle migration 要有持續同步、backfill、CDC、audit 和 schema evolution path，不把 Oracle 降級成手動 CSV export。

這份 runbook 使用 production-like path：在 GCE VM 上跑 Oracle XE，Datastream 透過 private connectivity 連 VM private IP。這比本機 Oracle + SSH tunnel 更接近 production，因為你會真的練到 VPC、firewall、Secret Manager、private connection、Datastream profiles 和 stream validation。

## 這一步在哪裡做

- Terraform resources：`complete/terraform/`
- Oracle VM bootstrap script：`complete/terraform/scripts/oracle-xe-startup.sh.tftpl`
- BigQuery raw dataset：`complete-498806.raw`
- GCP Console 驗證：Compute Engine、Secret Manager、Datastream、BigQuery、Cloud Logging

## 這一步會建立/設定什麼

- Secret Manager secret containers：
  - `oracle-host`
  - `oracle-port`
  - `oracle-service-name`
  - `oracle-username`
  - `oracle-password`
  - `oracle-sys-password`
  - `oracle-app-password`
- GCE Oracle source VM：`complete-oracle-xe-source`
- VM service account：讀 Oracle bootstrap secrets。
- Firewall：
  - IAP SSH：`35.235.240.0/20` to TCP `22`
  - Datastream private CIDR to Oracle TCP `1521`
- Docker Oracle XE：`gvenzl/oracle-xe:21-slim`
- Oracle CDC setup：ARCHIVELOG、supplemental logging、replication user、`APP.USER_RAW`
- BigQuery dataset：`raw`
- Datastream private connection、Oracle source profile、BigQuery destination profile、stream。

## Step 2 的元件關係與實作方式

```text
GCE VM: complete-oracle-xe-source
  Docker Oracle XE
  APP.USER_RAW
  C##DATASTREAM replication user
        |
        | private IP:1521
        v
Datastream private connection
        |
        v
Datastream stream: oracle-user-raw-to-bq
        |
        v
BigQuery: complete-498806.raw.APP_USER_RAW
```

各元件怎麼建立：

```text
Terraform:
  建 APIs、Secret Manager containers、BigQuery raw dataset、Oracle VM、
  firewall、Datastream private connection、connection profiles、stream。

gcloud secrets:
  只寫 secret values。密碼不要放進 Terraform variables、tfstate、repo。

Oracle bootstrap script:
  VM 開機後從 Secret Manager 讀密碼，啟動 Docker Oracle XE，
  建 table、replication user、CDC logging 設定。
```

為什麼要這樣做：

```text
本機 localhost 不是 production network。
GCE VM private IP + Datastream private connection 更接近真實 on-prem/private source。
Terraform 管 resource shape，Secret Manager 管 sensitive values。
Datastream 初始 NOT_STARTED，驗證通過後再改 RUNNING。
```

## Step 2A - 確認目前 Terraform scaffold

從 workspace root 執行：

```bash
ls gcp-solutions-repo/complete/terraform
ls gcp-solutions-repo/complete/terraform/scripts
```

你應該看到這些 Step 2 相關檔案：

```text
bigquery.tf
datastream.tf
oracle_source_vm.tf
secret_manager.tf
scripts/oracle-xe-startup.sh.tftpl
```

這一步只是確認 repo 已經有 production-like Oracle source scaffold，不會建立 GCP resource。

## Step 2B - 確認 APIs 和 base Terraform plan

`complete/terraform/apis.tf` 會管理這些 API：

```text
bigquery.googleapis.com
compute.googleapis.com
datastream.googleapis.com
secretmanager.googleapis.com
```

先 plan，不要直接 apply：

```bash
cd gcp-solutions-repo/complete/terraform

terraform plan \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_oracle_source_vm=false \
  -var enable_datastream_resources=false \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED
```

`enable_oracle_source_vm=false` 和 `enable_datastream_resources=false` 是安全預設，避免還沒準備 secrets 時就建立 VM 或 stream。

## Step 2C - 建立 secret containers

Terraform 只建立 secret containers，不寫 secret values。這一步的實際行為是建立「空的保管箱」。

預期 resources：

```text
google_secret_manager_secret.oracle["oracle-host"]
google_secret_manager_secret.oracle["oracle-port"]
google_secret_manager_secret.oracle["oracle-service-name"]
google_secret_manager_secret.oracle["oracle-username"]
google_secret_manager_secret.oracle["oracle-password"]
google_secret_manager_secret.oracle["oracle-sys-password"]
google_secret_manager_secret.oracle["oracle-app-password"]
```

如果 plan 看起來正確，由你手動 apply：

```bash
terraform apply \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_oracle_source_vm=false \
  -var enable_datastream_resources=false \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED
```

驗證 containers：

```bash
gcloud secrets list \
  --project=complete-498806 \
  --filter='name:oracle-' \
  --format='value(name)'
```

如果 secret 已經手動建過但不在 Terraform state，請先 import，不要直接 apply 重建。

## Step 2D - 寫入 Oracle VM bootstrap secrets

這一步的實際行為是寫入 VM 開機需要的密碼版本。不要把密碼寫進 `.tf`、`.md`、shell history 或 Terraform state。

請自己在 terminal 輸入：

```bash
read -rs ORACLE_SYS_PASSWORD
echo
read -rs ORACLE_APP_PASSWORD
echo
read -rs ORACLE_REPLICATION_PASSWORD
echo

printf '%s' "$ORACLE_SYS_PASSWORD" \
  | gcloud secrets versions add oracle-sys-password --data-file=- --project=complete-498806

printf '%s' "$ORACLE_APP_PASSWORD" \
  | gcloud secrets versions add oracle-app-password --data-file=- --project=complete-498806

printf '%s' "$ORACLE_REPLICATION_PASSWORD" \
  | gcloud secrets versions add oracle-password --data-file=- --project=complete-498806

unset ORACLE_SYS_PASSWORD ORACLE_APP_PASSWORD ORACLE_REPLICATION_PASSWORD
```

建議密碼先用英數字和安全符號，避免 Oracle quoted password 和 shell escaping 問題。`oracle-password` 是 Datastream replication user 的密碼。

## Step 2E - 建立 Oracle XE source VM

這一步會建立真實 GCE VM，所以先 plan：

這一步會建立的資源和原因：

```text
google_service_account.oracle_source_vm
  VM 專用 service account。
  用來讀 Secret Manager 的 oracle-sys-password、oracle-app-password、oracle-password。
  原因：密碼不寫進 Terraform、startup script 或 Git。

google_compute_instance.oracle_source
  GCE VM: complete-oracle-xe-source。
  Debian 12 + e2-standard-2 + 50GB pd-balanced disk。
  用 Docker 跑 gvenzl/oracle-xe:21-slim。
  原因：Oracle source 改放在 GCP VPC private IP，不再用 laptop localhost 或 SSH tunnel。

VM access_config
  給 VM ephemeral external IP。
  用途：VM 開機時可以 outbound apt-get install 和 docker pull。
  注意：這不是開放全世界進 VM；inbound 還是由 firewall 控制。

google_compute_firewall.allow_iap_ssh_to_oracle_vm
  source_ranges = ["35.235.240.0/20"]
  ports = ["22"]
  用途：只允許 Google IAP TCP forwarding SSH 進 VM debug。
  原因：不要開 0.0.0.0/0 public SSH。

google_compute_firewall.allow_datastream_to_oracle_vm
  source_ranges = ["172.31.255.0/29"]
  ports = ["1521"]
  用途：只允許 Datastream private connection CIDR 連 Oracle listener。
  原因：不要把 Oracle 1521 開給整個 internet 或整個 VPC。
```

CIDR 簡單理解：

```text
0.0.0.0/0        = 全世界任何 IPv4，不要用在 SSH 或 Oracle ingress。
35.235.240.0/20  = Google IAP TCP forwarding 來源，用來安全 SSH debug。
172.31.255.0/29  = Datastream private connection 小範圍，只用來連 Oracle 1521。
```

```bash
terraform plan \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=false \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED
```

確認只會新增 Oracle VM、VM service account、firewall、secret IAM、BigQuery `raw` dataset 等預期 resources 後，由你手動 apply 同一組變數。

VM 建好後查 private IP：

```bash
gcloud compute instances describe complete-oracle-xe-source \
  --project=complete-498806 \
  --zone=us-central1-a \
  --format='value(networkInterfaces[0].networkIP)'
```

如果要看 VM bootstrap log：

```bash
gcloud compute ssh complete-oracle-xe-source \
  --project=complete-498806 \
  --zone=us-central1-a \
  --tunnel-through-iap

sudo tail -f /var/log/complete-oracle-xe-bootstrap.log
```

### Step 2E-A - Oracle bootstrap gate

不要在 bootstrap 還沒完成時進 Step 2G。你必須先看到：

```text
Complete Oracle XE bootstrap finished.
```

如果你已經跑過 Step 2G 且 Terraform state 裡有部分 Datastream resources，修 startup script 時不要直接用 `enable_datastream_resources=false` 做一般 apply，因為 Terraform 可能會想刪掉那些 Datastream resources。這種 recovery 請用 targeted apply，只更新 VM metadata 和 VM log writer IAM：

```bash
terraform plan \
  -target='google_compute_instance.oracle_source[0]' \
  -target='google_project_iam_member.oracle_source_vm_log_writer[0]' \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=false \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED
```

確認 plan 只會更新 `google_compute_instance.oracle_source[0]` metadata，或新增 `google_project_iam_member.oracle_source_vm_log_writer[0]` 後，再由你手動 apply 同一組 `-target` 和變數。

如果要在 VM 上重跑 bootstrap，只修復現有 DB，不清掉 Oracle data files：

```bash
sudo rm -f /opt/complete-oracle-bootstrap/bootstrap.complete
sudo truncate -s 0 /var/log/complete-oracle-xe-bootstrap.log
sudo google_metadata_script_runner startup
```

重跑後先確認 metadata 是新版 script：

```bash
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/startup-script \
  | grep -E "ORACLE_DATABASE|54321|sqlplus -s / as sysdba|Complete Oracle XE bootstrap finished"
```

新版 script 不應該出現 `ORACLE_DATABASE`，因為 `gvenzl/oracle-xe` 已經內建 `XEPDB1`。如果看到 `ORACLE_DATABASE`，代表 VM metadata 還沒更新，要先回本機 Terraform apply 更新 metadata。

完成後跑 Oracle smoke check：

```bash
sudo docker exec complete-oracle-xe bash -lc "sqlplus -s / as sysdba <<'SQL'
SET PAGESIZE 200
SET LINESIZE 200

SELECT log_mode, supplemental_log_data_min, supplemental_log_data_all
FROM v\$database;

SELECT username, account_status, common
FROM dba_users
WHERE username = 'C##DATASTREAM';

ALTER SESSION SET CONTAINER=XEPDB1;

SELECT grantee, owner, table_name, privilege
FROM dba_tab_privs
WHERE grantee = 'C##DATASTREAM'
  AND owner = 'SYS'
  AND table_name IN (
    'V_\$DATABASE',
    'V_\$ARCHIVED_LOG',
    'DBA_SUPPLEMENTAL_LOGGING',
    'V_\$LOGMNR_CONTENTS',
    'DBMS_LOGMNR',
    'DBMS_LOGMNR_D'
  );

SELECT grantee, granted_role
FROM dba_role_privs
WHERE grantee = 'C##DATASTREAM'
  AND granted_role = 'EXECUTE_CATALOG_ROLE';

SELECT COUNT(*) AS user_raw_rows
FROM APP.USER_RAW;

SELECT owner, table_name, log_group_type
FROM dba_log_groups
WHERE owner = 'APP'
  AND table_name = 'USER_RAW';

EXIT;
SQL"
```

預期結果：

```text
LOG_MODE = ARCHIVELOG
SUPPLEMENTAL_LOG_DATA_MIN = YES
SUPPLEMENTAL_LOG_DATA_ALL = YES
C##DATASTREAM exists and ACCOUNT_STATUS = OPEN
C##DATASTREAM has SELECT/EXECUTE on Datastream-required SYS views and LogMiner packages inside XEPDB1
C##DATASTREAM has EXECUTE_CATALOG_ROLE inside XEPDB1
APP.USER_RAW row count >= 1
APP.USER_RAW has supplemental log group
```

如果這個 gate 沒過，不要做 Datastream validation。

## Step 2F - 寫入 Oracle connection secrets

這一步的實際行為是把 Datastream source profile 後面要讀的連線資訊寫進 Secret Manager。

用 Step 2E 查到的 VM private IP：

```bash
read -r ORACLE_HOST

printf '%s' "$ORACLE_HOST" \
  | gcloud secrets versions add oracle-host --data-file=- --project=complete-498806

printf '%s' '1521' \
  | gcloud secrets versions add oracle-port --data-file=- --project=complete-498806

printf '%s' 'XEPDB1' \
  | gcloud secrets versions add oracle-service-name --data-file=- --project=complete-498806

printf '%s' 'C##DATASTREAM' \
  | gcloud secrets versions add oracle-username --data-file=- --project=complete-498806

unset ORACLE_HOST
```

如果你之前誤寫過本機 lab version 1，例如 `localhost`、`APP`、`AppUser123`，確認 version 後停用舊版本：

```bash
gcloud secrets versions list oracle-host --project=complete-498806
gcloud secrets versions list oracle-port --project=complete-498806
gcloud secrets versions list oracle-service-name --project=complete-498806
gcloud secrets versions list oracle-username --project=complete-498806
gcloud secrets versions list oracle-password --project=complete-498806

gcloud secrets versions disable 1 --secret=oracle-host --project=complete-498806
gcloud secrets versions disable 1 --secret=oracle-port --project=complete-498806
gcloud secrets versions disable 1 --secret=oracle-service-name --project=complete-498806
gcloud secrets versions disable 1 --secret=oracle-username --project=complete-498806
gcloud secrets versions disable 1 --secret=oracle-password --project=complete-498806
```

不要用 `gcloud secrets versions access` 檢查 password。

## Step 2G - 建立 Datastream profiles 和 stream

這一步會建立 Datastream private connection、Oracle source profile、BigQuery destination profile 和 stream。初次建立保持 `NOT_STARTED`。

先 plan，不要直接 apply：

```bash
ORACLE_VM_PRIVATE_IP="$(gcloud compute instances describe complete-oracle-xe-source \
  --project=complete-498806 \
  --zone=us-central1-a \
  --format='value(networkInterfaces[0].networkIP)')"

terraform plan \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=true \
  -var oracle_host="${ORACLE_VM_PRIVATE_IP}" \
  -var oracle_service_name=XEPDB1 \
  -var oracle_username=C##DATASTREAM \
  -var datastream_desired_state=NOT_STARTED \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED
```

### Step 2G-A - 先確認 plan 的意義

這個 plan 應該只新增 Datastream 相關 resources，不應該刪改 Step 1 已經建立的 Storage Transfer resources。

你希望看到的新增項目：

```text
google_datastream_private_connection.default_vpc[0]
google_datastream_connection_profile.oracle_source[0]
google_datastream_connection_profile.bigquery_destination[0]
google_datastream_stream.oracle_user_raw_to_bigquery[0]
google_secret_manager_secret_iam_member.datastream_oracle_password_reader[0]
```

你不希望看到的動作：

```text
- destroy google_storage_transfer_agent_pool.crm_onprem[0]
- destroy google_storage_transfer_job.crm_nightly_posix_to_gcs[0]
- replace google_storage_transfer_job.crm_nightly_posix_to_gcs[0]
- delete any google_storage_bucket.crm resources
```

如果 plan 出現 Step 1 resources 要被刪除或 replace，通常代表你漏帶了 Step 1 的變數，例如：

```text
enable_storage_transfer_job=true
crm_transfer_source_root_directory=...
crm_transfer_sink_path=...
crm_transfer_job_status=DISABLED
```

### Step 2G-B - 初次 apply 只建立 stream shell，不啟動 CDC

如果 plan 看起來正確，由你手動 apply 同一組變數。這次 apply 的重點是建立 Datastream resource shape：

```text
private connection
source connection profile
destination connection profile
stream object
```

此時 `datastream_desired_state=NOT_STARTED`，意思是：

```text
Datastream resource 會建立。
Oracle CDC 不會開始跑。
BigQuery raw table 可能還不會出現資料。
```

為什麼不直接設 `RUNNING`：

```text
先確認 network、secret、Oracle listener、replication user、ARCHIVELOG、
supplemental logging 都可用，再啟動 CDC。
這樣失敗時比較容易 debug，也避免建立後馬上開始重試和產生錯誤事件。
```

### Step 2G-C - 到 Datastream Console 驗證 connection profile

初次 apply 後，到 GCP Console：

```text
Datastream
  -> Connection profiles
  -> oracle-user-raw-source
  -> Test / Validate connection
```

你要確認：

```text
Oracle host 是 VM private IP
port 是 1521
service name 是 XEPDB1
username 是 C##DATASTREAM
password 來源是 Secret Manager oracle-password latest
private connectivity 指向 default-vpc-private-connection
```

如果 validation 失敗，優先檢查：

```text
Oracle VM bootstrap log:
  sudo tail -f /var/log/complete-oracle-xe-bootstrap.log

Firewall:
  172.31.255.0/29 -> VM tag complete-oracle-source -> tcp:1521

Secret versions:
  oracle-password latest 是否是 C##DATASTREAM 的密碼

Oracle CDC:
  ARCHIVELOG
  supplemental logging
  APP.USER_RAW table-level supplemental logging
```

已知錯誤對照：

```text
ORA-12541: TNS:no listener
  Oracle container/listener 沒起來，先查 sudo ss -lntp | grep 1521。

ORA-01017: invalid username/password
  C##DATASTREAM 不存在、沒 unlock，或 Secret Manager oracle-password latest 跟 Oracle 內密碼不一致。

ORA-00942: table or view does not exist
  APP.USER_RAW 還沒建立，bootstrap 沒跑完。

ORA-01917: user or role 'C##DATASTREAM' does not exist
  舊 bootstrap 可能只在 CDB root 留下半成品 replication user，XEPDB1 裡看不到它。
  套用新版 startup script 後重跑 bootstrap；新版會先修 root common user，
  再切到 XEPDB1 補齊同名 replication user/table grants，避免 APP.USER_RAW 授權失敗。

Datastream ORACLE_MISSING_PERMISSIONS: SELECT ON V_$DATABASE
  Datastream 已經連到 Oracle，但它登入 XEPDB1 後缺 metadata view 權限。
  套用新版 startup script 後重跑 bootstrap；新版會在 XEPDB1 內 grant
  SYS.V_$DATABASE / SYS.V_$PARAMETER / SYS.GV_$ARCHIVED_LOG 等必要讀取權限。

Datastream ORACLE_MISSING_PERMISSIONS: SELECT ON V_$ARCHIVED_LOG, SELECT ON DBA_SUPPLEMENTAL_LOGGING
  Datastream 已經通過 connectivity，但 Oracle user 還缺讀 archived redo log metadata
  和 supplemental logging metadata 的權限。套用新版 startup script 後重跑 bootstrap；
  新版會直接 grant SYS.V_$ARCHIVED_LOG 和 SYS.DBA_SUPPLEMENTAL_LOGGING。

Datastream ORACLE_MISSING_PERMISSIONS: EXECUTE_CATALOG_ROLE, SELECT ON V_$LOGMNR_CONTENTS, EXECUTE ON DBMS_LOGMNR, EXECUTE ON DBMS_LOGMNR_D
  Datastream 已經進到 LogMiner 權限驗證。套用新版 startup script 後重跑 bootstrap；
  新版會 grant EXECUTE_CATALOG_ROLE、SYS.V_$LOGMNR_CONTENTS、SYS.DBMS_LOGMNR、
  SYS.DBMS_LOGMNR_D，讓 Datastream 可以讀 CDC log mining metadata。

Datastream ORACLE_NO_LOG_FILES_FOUND
  ARCHIVELOG 已開，但 Oracle 還沒有 archived redo log 可以讀。新版 startup script
  會執行 ALTER SYSTEM SWITCH LOGFILE 和 ALTER SYSTEM ARCHIVE LOG CURRENT 先產生 log。

NOARCHIVELOG / supplemental logging = NO
  CDC bootstrap 沒完成，不要進 Datastream validation。

SP2-0310 unable to open /tmp/bootstrap.sql
  舊版 startup script 問題。新版 script 會用 stdin pipe 給 sqlplus，不會再 docker cp 到 /tmp。

ORA-65012: Pluggable database XEPDB1 already exists
  舊版 startup script 設了 ORACLE_DATABASE=XEPDB1。新版 script 會使用內建 XEPDB1，不再建立額外 PDB。
```

如果 apply 時看到這個錯誤：

```text
Service account service-<project-number>@gcp-sa-datastream.iam.gserviceaccount.com does not exist
```

意思是 Datastream API 已啟用，但 Datastream service agent 還沒建立。Terraform 會用：

```text
google_project_service_identity.datastream[0]
```

先建立 service identity，再把 `oracle-password` 的 Secret Manager accessor IAM 授權給它。

如果 private connection 建立失敗並進入 `FAILED`：

```text
google_datastream_private_connection.default_vpc[0] is tainted
```

這代表 Terraform 下次 apply 會 replace 它。重跑 plan 時應該看到：

```text
google_datastream_private_connection.default_vpc[0] is tainted, so must be replaced
```

這是預期的修復路徑，不是要手動改 state。

### Step 2G-D - 驗證通過後才啟動 stream

Datastream connection profile validation 通過後，再把：

```text
datastream_desired_state=RUNNING
```

重新 plan：

```bash
terraform plan \
  -var project_id=complete-498806 \
  -var region=us-central1 \
  -var bucket_location=US \
  -var enable_oracle_source_vm=true \
  -var enable_datastream_resources=true \
  -var oracle_host=<oracle-vm-private-ip> \
  -var oracle_service_name=XEPDB1 \
  -var oracle_username=C##DATASTREAM \
  -var datastream_desired_state=RUNNING \
  -var enable_storage_transfer_job=true \
  -var crm_transfer_source_root_directory=/Users/chienpong/Documents/workspace/cloud-data-engineer/case-study-gcp-crm/local-data-lab-repo/data/crm/2026-05-26 \
  -var crm_transfer_sink_path=crm/2026-05-26/ \
  -var crm_transfer_job_status=DISABLED
```

這次 plan 應該主要是把 Datastream stream 從 `NOT_STARTED` 改成 `RUNNING`。確認沒有意外刪改 Step 1 resources 後，再由你手動 apply。

Apply 後才會開始：

```text
Datastream backfill APP.USER_RAW
Datastream 持續讀 Oracle redo/archive logs
BigQuery raw.APP_USER_RAW 出現資料
```

## Step 2H - 驗證 stream 和 BigQuery raw table

查 Datastream private connection：

```bash
gcloud datastream private-connections describe default-vpc-private-connection \
  --project=complete-498806 \
  --location=us-central1
```

查 stream 狀態：

```bash
gcloud datastream streams describe oracle-user-raw-to-bq \
  --project=complete-498806 \
  --location=us-central1 \
  --format='value(state)'
```

查 BigQuery raw table：

```bash
bq query \
  --use_legacy_sql=false \
  --project_id=complete-498806 \
  'SELECT COUNT(*) AS row_count FROM `complete-498806.raw.APP_USER_RAW`'
```

如果 `raw.APP_USER_RAW` 還不存在，先確認 stream 是否已 `RUNNING`、backfill 是否完成、Oracle include list 是否包含 `APP.USER_RAW`。

## 完成後確認

- Oracle VM 已建立，private IP 可查到。
- VM bootstrap log 顯示 Oracle container healthy、ARCHIVELOG、supplemental logging、`APP.USER_RAW` 建立成功。
- Oracle secret values 有 enabled versions，但 values 不在 repo、Terraform state 或 logs。
- Datastream private connection 和 connection profiles 建立成功。
- Stream 從 `NOT_STARTED` 改成 `RUNNING` 後，BigQuery `raw.APP_USER_RAW` 有資料。
- Oracle source 更新後，BigQuery 能看到 CDC 同步結果。

## 常見風險

- 不要把 production password 寫成 Terraform variable default。
- 不要讓 Terraform state 包含 secret payload。
- 不要使用 `localhost:1521`；Datastream 在 GCP managed service 裡，不在你的 laptop。
- 不要在 connection validation 前把 stream 直接設為 `RUNNING`。
- `datastream_private_connection_subnet` 必須是未使用、未重疊的 `/29` CIDR。
- Oracle XE VM 是 production-like lab，不是正式 HA / backup / license posture。
