locals {
  bigquery_datasets = {
    raw = {
      dataset_id                  = "raw"
      description                 = "Raw source tables from Oracle Datastream and CRM CSV load jobs."
      default_table_expiration_ms = 63072000000 # 730 days
    }
    staging = {
      dataset_id                  = "staging"
      description                 = "Standardized intermediate CRM and Oracle data."
      default_table_expiration_ms = 63072000000 # 730 days
    }
    curated = {
      dataset_id                  = "curated"
      description                 = "Reusable cleaned user and customer 360 entities."
      default_table_expiration_ms = null
    }
    mart = {
      dataset_id                  = "mart"
      description                 = "Segmentation outputs and Salesforce activation tables."
      default_table_expiration_ms = null
    }
    audit = {
      dataset_id                  = "audit"
      description                 = "Pipeline audit, rerun, and quality check history."
      default_table_expiration_ms = null
    }
  }
}

resource "google_bigquery_dataset" "crm" {
  for_each = local.bigquery_datasets

  project     = var.project_id
  dataset_id  = each.value.dataset_id
  description = each.value.description
  location    = var.bucket_location
  labels      = local.common_labels

  default_table_expiration_ms = each.value.default_table_expiration_ms

  depends_on = [google_project_service.required]
}

resource "google_bigquery_dataset_iam_member" "workflow_raw_data_editor" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.crm["raw"].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_bigquery_dataset_iam_member" "workflow_pipeline_data_editor" {
  for_each = toset(["staging", "curated", "mart", "audit"])

  project    = var.project_id
  dataset_id = google_bigquery_dataset.crm[each.key].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.workflow.email}"
}
