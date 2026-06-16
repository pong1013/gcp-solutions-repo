locals {
  dataflow_template_bucket_name = var.dataflow_template_bucket_name != "" ? var.dataflow_template_bucket_name : "${var.project_id}-complete-dataflow-templates"
  dataflow_temp_bucket_name     = var.dataflow_temp_bucket_name != "" ? var.dataflow_temp_bucket_name : "${var.project_id}-complete-dataflow-temp"
  config_bucket_name            = var.config_bucket_name != "" ? var.config_bucket_name : "${var.project_id}-complete-config"

  crm_raw_tables = {
    crm_sales = {
      description = "Raw CRM sales deals ingested by the governed Dataflow Flex Template."
      clustering  = ["user_id", "deal_id"]
      columns = [
        { name = "customer_id", type = "STRING", mode = "NULLABLE" },
        { name = "user_id", type = "STRING", mode = "NULLABLE" },
        { name = "deal_id", type = "STRING", mode = "NULLABLE" },
        { name = "deal_stage", type = "STRING", mode = "NULLABLE" },
        { name = "deal_amount", type = "FLOAT", mode = "NULLABLE" },
        { name = "currency", type = "STRING", mode = "NULLABLE" },
        { name = "closed_date", type = "DATE", mode = "NULLABLE" },
        { name = "owner_region", type = "STRING", mode = "NULLABLE" },
      ]
    }
    crm_support = {
      description = "Raw CRM support tickets ingested by the governed Dataflow Flex Template."
      clustering  = ["user_id", "ticket_id"]
      columns = [
        { name = "ticket_id", type = "STRING", mode = "NULLABLE" },
        { name = "user_id", type = "STRING", mode = "NULLABLE" },
        { name = "priority", type = "STRING", mode = "NULLABLE" },
        { name = "status", type = "STRING", mode = "NULLABLE" },
        { name = "category", type = "STRING", mode = "NULLABLE" },
        { name = "csat_score", type = "FLOAT", mode = "NULLABLE" },
      ]
    }
    crm_campaign_events = {
      description = "Raw CRM campaign events ingested by the governed Dataflow Flex Template."
      clustering  = ["user_id", "campaign_id"]
      columns = [
        { name = "event_id", type = "STRING", mode = "NULLABLE" },
        { name = "user_id", type = "STRING", mode = "NULLABLE" },
        { name = "campaign_id", type = "STRING", mode = "NULLABLE" },
        { name = "channel", type = "STRING", mode = "NULLABLE" },
        { name = "event_type", type = "STRING", mode = "NULLABLE" },
        { name = "event_ts", type = "TIMESTAMP", mode = "NULLABLE" },
      ]
    }
    crm_new_partner_leads = {
      description = "Raw partner leads ingested by the governed Dataflow Flex Template."
      clustering  = ["external_lead_id", "email"]
      columns = [
        { name = "external_lead_id", type = "STRING", mode = "NULLABLE" },
        { name = "email", type = "STRING", mode = "NULLABLE" },
        { name = "partner_name", type = "STRING", mode = "NULLABLE" },
        { name = "lead_score", type = "INTEGER", mode = "NULLABLE" },
        { name = "utm_source", type = "STRING", mode = "NULLABLE" },
        { name = "created_at", type = "TIMESTAMP", mode = "NULLABLE" },
        { name = "opt_in", type = "BOOL", mode = "NULLABLE" },
      ]
    }
  }

  crm_raw_metadata_columns = [
    { name = "run_date", type = "DATE", mode = "NULLABLE" },
    { name = "source_type", type = "STRING", mode = "NULLABLE" },
    { name = "source_file", type = "STRING", mode = "NULLABLE" },
    { name = "ingestion_ts", type = "TIMESTAMP", mode = "NULLABLE" },
  ]

  crm_raw_table_schemas = {
    for table_id, table in local.crm_raw_tables :
    table_id => jsonencode(concat(table.columns, local.crm_raw_metadata_columns))
  }
}

resource "google_storage_bucket" "dataflow_templates" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  name                        = local.dataflow_template_bucket_name
  project                     = var.project_id
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy_buckets
  labels                      = local.common_labels

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket" "dataflow_temp" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  name                        = local.dataflow_temp_bucket_name
  project                     = var.project_id
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy_buckets
  labels                      = local.common_labels

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      age = 14
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket" "config" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  name                        = local.config_bucket_name
  project                     = var.project_id
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy_buckets
  labels                      = local.common_labels

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_object" "crm_schema_configs" {
  for_each = var.enable_dataflow_crm_ingestion ? fileset("${path.module}/../schemas", "*.json") : []

  bucket       = google_storage_bucket.config[0].name
  name         = "schemas/${each.value}"
  source       = "${path.module}/../schemas/${each.value}"
  content_type = "application/json"
}

resource "google_artifact_registry_repository" "dataflow_templates" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  project       = var.project_id
  location      = var.region
  repository_id = var.dataflow_artifact_repository_id
  description   = "Docker images for Complete CRM Dataflow Flex Templates."
  format        = "DOCKER"
  labels        = local.common_labels

  depends_on = [google_project_service.required["artifactregistry.googleapis.com"]]
}

resource "google_service_account" "dataflow_worker" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  project      = var.project_id
  account_id   = var.dataflow_worker_service_account_id
  display_name = "Complete Dataflow CRM ingestion worker"
  description  = "Runs Dataflow Flex Template jobs that ingest governed CRM CSV files."
}

resource "google_bigquery_dataset" "audit" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  project    = var.project_id
  dataset_id = "audit"
  location   = var.bucket_location
  labels     = local.common_labels

  description                 = "Pipeline audit, rerun, and quality check history."
  delete_contents_on_destroy  = false
  default_table_expiration_ms = null

  depends_on = [google_project_service.required["bigquery.googleapis.com"]]
}

resource "google_bigquery_table" "crm_raw" {
  for_each = var.enable_dataflow_crm_ingestion ? local.crm_raw_tables : {}

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = each.key
  description         = each.value.description
  deletion_protection = false
  schema              = local.crm_raw_table_schemas[each.key]
  labels              = local.common_labels
  clustering          = each.value.clustering

  time_partitioning {
    type  = "DAY"
    field = "run_date"
  }
}

resource "google_bigquery_table" "ingestion_runs" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.audit[0].dataset_id
  table_id            = "ingestion_runs"
  description         = "Audit rows emitted by CRM Dataflow ingestion jobs."
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "run_date", type = "DATE", mode = "NULLABLE" },
    { name = "source_type", type = "STRING", mode = "NULLABLE" },
    { name = "input_prefix", type = "STRING", mode = "NULLABLE" },
    { name = "schema_config_path", type = "STRING", mode = "NULLABLE" },
    { name = "output_table", type = "STRING", mode = "NULLABLE" },
    { name = "rejected_output_prefix", type = "STRING", mode = "NULLABLE" },
    { name = "input_count", type = "INTEGER", mode = "NULLABLE" },
    { name = "valid_count", type = "INTEGER", mode = "NULLABLE" },
    { name = "rejected_count", type = "INTEGER", mode = "NULLABLE" },
    { name = "audit_ts", type = "TIMESTAMP", mode = "NULLABLE" },
  ])

  time_partitioning {
    type  = "DAY"
    field = "run_date"
  }
}

resource "google_project_iam_member" "dataflow_worker_project_roles" {
  for_each = var.enable_dataflow_crm_ingestion ? toset([
    "roles/dataflow.worker",
    "roles/bigquery.jobUser",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/artifactregistry.reader",
  ]) : []

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dataflow_worker[0].email}"
}

resource "google_bigquery_dataset_iam_member" "dataflow_raw_data_editor" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataflow_worker[0].email}"
}

resource "google_bigquery_dataset_iam_member" "dataflow_audit_data_editor" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.audit[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataflow_worker[0].email}"
}

resource "google_storage_bucket_iam_member" "dataflow_raw_reader" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  bucket = google_storage_bucket.crm["raw"].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataflow_worker[0].email}"
}

resource "google_storage_bucket_iam_member" "dataflow_rejected_writer" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  bucket = google_storage_bucket.crm["rejected"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_worker[0].email}"
}

resource "google_storage_bucket_iam_member" "dataflow_template_object_admin" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  bucket = google_storage_bucket.dataflow_templates[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_worker[0].email}"
}

resource "google_storage_bucket_iam_member" "dataflow_temp_object_admin" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  bucket = google_storage_bucket.dataflow_temp[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataflow_worker[0].email}"
}

resource "google_storage_bucket_iam_member" "dataflow_config_reader" {
  count = var.enable_dataflow_crm_ingestion ? 1 : 0

  bucket = google_storage_bucket.config[0].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataflow_worker[0].email}"
}
