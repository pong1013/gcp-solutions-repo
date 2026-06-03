# GCP Simplest CRM Migration Repo

這個 repo 對應最簡單方案：GCS + Cloud Data Fusion + Cloud Composer + BigQuery。重點是用 low-code pipeline 和接近原本 nightly batch 的流程，降低 migration 難度。

## Folder layout

- `terraform/`：GCS buckets、BigQuery datasets、Composer、Data Fusion、IAM、Secret Manager。
- `composer/dags/`：nightly orchestration DAG，負責觸發 pipeline、quality checks、archive、Salesforce push。
- `datafusion/pipelines/`：Data Fusion pipeline JSON exports。
- `sql/`：BigQuery transformation、quality check、BigQuery ML SQL。
- `dataplex/`：data quality rules。
- `docs/`：architecture notes、runbook、deployment notes。

## Implementation steps

- [Step 1 - Create GCS Buckets](docs/step1-gcs-buckets.md)
- [Step 2 - Configure Scheduled CRM Transfer To GCS](docs/step2-crm-upload.md)
- [Step 3 - Oracle Ingestion With Cloud Data Fusion](docs/step3-oracle-datafusion.md)
- [Step 4 - Create BigQuery Datasets And Tables](docs/step4-bigquery-datasets.md)
- [Step 5 - Orchestrate Pipeline With Cloud Composer](docs/step5-composer-orchestration.md)
- [Step 6 - Data Quality Checks And Manager Notification](docs/step6-data-quality-notification.md)
- [Step 7 - ML Segmentation And Salesforce Activation](docs/step7-ml-salesforce.md)
- [Step 8 - Archive Source Files And Cleanup Old Data](docs/step8-archive-cleanup.md)

Production 變更應透過 Pull Request review，再由 Cloud Build 或 CI/CD 部署。

注意：Simplest production baseline 使用 Storage Transfer Service scheduled transfer，把 on-prem CRM CSV 持續送到 GCS raw bucket。`gcloud storage cp` 只用於 lab bootstrap 或 emergency replay，不代表正式 ongoing ingestion。
