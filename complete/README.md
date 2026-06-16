# GCP Complete CRM Migration Repo

這個 repo 對應最完整 production-grade 方案：Storage Transfer + Datastream + Composer + Dataflow + Dataform + Dataplex。重點是完整滿足 governance、dashboard、task-level rerun、schema evolution、quality gate、review 和 template deployment。

## Folder layout

- `terraform/`：所有 GCP infrastructure modules、IAM、Secret Manager。
- `composer/dags/`：production Airflow DAGs。
- `dataflow/crm-csv-ingestion/`：Dataflow Flex Template source code。
- `dataform/`：raw -> staging -> curated -> mart SQL workflows。
- `dataplex/`：data quality YAML rules。
- `schemas/`：CRM source schema configs。
- `cloud-run/salesforce-job/`：Salesforce Bulk API / campaign push job。
- `docs/`：architecture notes、runbook、deployment notes。

## Implementation steps

- [Step 1 - Controlled CRM CSV Transfer](docs/step1-crm-transfer.md)
- [Step 2 - Oracle CDC With Datastream](docs/step2-oracle-datastream.md)
- [Step 3 - CRM CSV Ingestion With Dataflow Flex Template](docs/step3-dataflow-crm-ingestion.md)
- [Step 4 - Transform Data With Dataform](docs/step4-dataform-transform.md)
- [Step 5 - Data Quality Gate With Dataplex](docs/step5-dataplex-quality.md)
- [Step 6 - ML Segmentation And Salesforce Activation](docs/step6-ml-salesforce.md)
- [Step 7 - Composer Dashboard And Task Rerun](docs/step7-composer-dashboard.md)
- [Step 8 - Template Deployment With Terraform And Cloud Build](docs/step8-template-deployment.md)

Production 變更應透過 Pull Request review，再由 Cloud Build approval gate 部署。
