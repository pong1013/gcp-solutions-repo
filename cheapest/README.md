# GCP Cheapest CRM Migration Repo

這個 repo 對應最便宜方案：GCS + BigQuery load jobs + Workflows + Cloud Run Jobs。重點是避免 Composer、Data Fusion、Datastream 等較高固定成本服務，用 pay-per-use/serverless components 滿足需求。

## Folder layout

- `terraform/`：GCS、BigQuery、Scheduler、Workflows、Cloud Run Jobs、IAM、Secret Manager。
- `workflows/`：nightly pipeline Workflow YAML。
- `sql/`：BigQuery load/transform/quality/BigQuery ML SQL。
- `cloud-run/salesforce-job/`：Salesforce campaign push job。
- `schemas/`：CRM CSV schema 和 load config。
- `docs/`：architecture notes、rerun procedure、cost notes。

## Implementation steps

- [Step 1 - Low-Cost CRM CSV Upload](docs/step1-crm-upload.md)
- [Step 2 - Oracle CDC With Datastream](docs/step2-oracle-datastream.md)
- [Step 3 - Scheduler And Workflows Orchestration](docs/step3-scheduler-workflows.md)
- [Step 4 - BigQuery Load Jobs For CRM CSV](docs/step4-bigquery-load.md)
- [Step 5 - BigQuery SQL Transformation And Quality Checks](docs/step5-sql-quality.md)
- [Step 6 - Workflow Dashboard And Rerun Design](docs/step6-rerun-design.md)
- [Step 7 - Cloud Run Jobs For Long Tasks And Salesforce](docs/step7-cloud-run-salesforce.md)
- [Step 8 - Terraform, Cloud Build, And PR Review](docs/step8-template-deployment.md)

Production 變更應透過 Pull Request review，再由 Cloud Build 或 CI/CD 部署。
