locals {
  # Step 4 data layers. Step 3 already needs the raw dataset because the
  # Oracle Data Fusion pipeline writes APP.user_raw into raw.user_raw.
  bigquery_datasets = {
    raw = {
      dataset_id                  = "raw"
      description                 = "Raw source data from CRM CSV files and Oracle user tables."
      default_table_expiration_ms = 63072000000 # 730 days
    }
    staging = {
      dataset_id                  = "staging"
      description                 = "Standardized and type-cast intermediate CRM and user data."
      default_table_expiration_ms = 63072000000 # 730 days
    }
    curated = {
      dataset_id                  = "curated"
      description                 = "Reusable cleaned user and customer 360 entities."
      default_table_expiration_ms = null
    }
    mart = {
      dataset_id                  = "mart"
      description                 = "Segmentation outputs and Salesforce campaign audience tables."
      default_table_expiration_ms = null
    }
  }
}

# BigQuery datasets define the data layers used by the pipeline.
# Raw and staging get a 730-day default expiration to satisfy the cleanup requirement.
# Tables created by Data Fusion, such as raw.user_raw, are not defined here yet.
# If a table already exists from a pipeline run, importing it is required before
# Terraform can manage it directly.
resource "google_bigquery_dataset" "crm" {
  for_each = local.bigquery_datasets

  project     = var.project_id
  dataset_id  = each.value.dataset_id
  location    = var.bucket_location
  description = each.value.description
  labels      = local.common_labels

  default_table_expiration_ms = each.value.default_table_expiration_ms

  depends_on = [
    google_project_service.simplest_required,
  ]
}

resource "google_bigquery_table" "crm_rejected_records" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.crm["raw"].dataset_id
  table_id   = "crm_rejected_records"

  description = "Rejected CRM rows captured by data quality checks."
  labels      = local.common_labels

  schema = jsonencode([
    {
      name        = "run_date"
      type        = "DATE"
      mode        = "REQUIRED"
      description = "Pipeline logical run date for the rejected record."
    },
    {
      name        = "dag_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Airflow DAG that produced the rejected evidence."
    },
    {
      name        = "task_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Airflow task that produced the rejected evidence."
    },
    {
      name        = "rule_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Data quality rule that rejected the record."
    },
    {
      name        = "source_table"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Source BigQuery table containing the bad row."
    },
    {
      name        = "source_key"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Best available source identifier for the bad row."
    },
    {
      name        = "error_reason"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Human-readable reason the row was rejected."
    },
    {
      name        = "record_json"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "JSON snapshot of the rejected source row."
    },
    {
      name        = "created_at"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the rejected evidence was written."
    },
  ])

  depends_on = [
    google_project_service.simplest_required,
  ]
}

# Data Fusion runs this lab pipeline on Dataproc. The Dataproc workers use the
# Compute Engine default service account, which needs dataset metadata and table
# write access for the BigQuery sink.
resource "google_bigquery_dataset_iam_member" "compute_data_editor" {
  for_each = google_bigquery_dataset.crm

  project    = var.project_id
  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "compute_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

output "bigquery_dataset_full_names" {
  description = "Fully-qualified BigQuery dataset names."
  value = {
    for name, dataset in google_bigquery_dataset.crm : name => "${var.project_id}.${dataset.dataset_id}"
  }
}

output "bigquery_dataset_ids" {
  description = "BigQuery datasets used by the simplest solution."
  value = {
    for name, dataset in google_bigquery_dataset.crm : name => dataset.dataset_id
  }
}
