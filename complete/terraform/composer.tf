resource "google_service_account" "composer" {
  count = var.enable_composer_orchestration ? 1 : 0

  project      = var.project_id
  account_id   = var.composer_service_account_id
  display_name = "Complete CRM Composer worker"
  description  = "Runs Airflow DAGs that orchestrate the complete CRM pipeline."

  depends_on = [google_project_service.required["iam.googleapis.com"]]
}

resource "google_service_account_iam_member" "composer_service_agent_v2_ext" {
  count = var.enable_composer_orchestration ? 1 : 0

  service_account_id = google_service_account.composer[0].name
  role               = "roles/composer.ServiceAgentV2Ext"
  member             = "serviceAccount:service-${data.google_project.current.number}@cloudcomposer-accounts.iam.gserviceaccount.com"

  depends_on = [google_project_service.required["composer.googleapis.com"]]
}

resource "google_project_iam_member" "composer_worker_project_roles" {
  for_each = var.enable_composer_orchestration ? toset([
    "roles/composer.worker",
    "roles/dataflow.developer",
    "roles/dataform.editor",
    "roles/dataplex.editor",
    "roles/run.developer",
    "roles/run.invoker",
    "roles/bigquery.jobUser",
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
  ]) : []

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_service_account_iam_member" "composer_dataflow_worker_user" {
  count = var.enable_composer_orchestration && var.enable_dataflow_crm_ingestion ? 1 : 0

  service_account_id = google_service_account.dataflow_worker[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_service_account_iam_member" "composer_dataform_runner_user" {
  count = var.enable_composer_orchestration && var.enable_dataform_transform ? 1 : 0

  service_account_id = google_service_account.dataform_runner[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_service_account_iam_member" "composer_salesforce_job_user" {
  count = var.enable_composer_orchestration && var.enable_ml_salesforce_push ? 1 : 0

  service_account_id = google_service_account.salesforce_job[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_bigquery_dataset_iam_member" "composer_audit_editor" {
  count = var.enable_composer_orchestration ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.audit[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_bigquery_dataset_iam_member" "composer_raw_viewer" {
  count = var.enable_composer_orchestration ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_bigquery_dataset_iam_member" "composer_mart_viewer" {
  count = var.enable_composer_orchestration && var.enable_dataform_transform ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.dataform_output["mart"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_bigquery_table" "pipeline_step_status" {
  count = var.enable_composer_orchestration ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.audit[0].dataset_id
  table_id            = "pipeline_step_status"
  description         = "Airflow task-level status history for the complete CRM pipeline."
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "run_date", type = "DATE", mode = "NULLABLE" },
    { name = "dag_id", type = "STRING", mode = "NULLABLE" },
    { name = "dag_run_id", type = "STRING", mode = "NULLABLE" },
    { name = "task_id", type = "STRING", mode = "NULLABLE" },
    { name = "try_number", type = "INTEGER", mode = "NULLABLE" },
    { name = "status", type = "STRING", mode = "NULLABLE" },
    { name = "started_at", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "ended_at", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "message", type = "STRING", mode = "NULLABLE" },
  ])

  time_partitioning {
    type  = "DAY"
    field = "run_date"
  }
}

resource "google_bigquery_table" "rerun_history" {
  count = var.enable_composer_orchestration ? 1 : 0

  project             = var.project_id
  dataset_id          = google_bigquery_dataset.audit[0].dataset_id
  table_id            = "rerun_history"
  description         = "Airflow task rerun evidence for failed-task recovery."
  deletion_protection = false
  labels              = local.common_labels

  schema = jsonencode([
    { name = "run_date", type = "DATE", mode = "NULLABLE" },
    { name = "dag_id", type = "STRING", mode = "NULLABLE" },
    { name = "dag_run_id", type = "STRING", mode = "NULLABLE" },
    { name = "task_id", type = "STRING", mode = "NULLABLE" },
    { name = "try_number", type = "INTEGER", mode = "NULLABLE" },
    { name = "rerun_of_dag_run_id", type = "STRING", mode = "NULLABLE" },
    { name = "operator", type = "STRING", mode = "NULLABLE" },
    { name = "started_at", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "ended_at", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "status", type = "STRING", mode = "NULLABLE" },
    { name = "message", type = "STRING", mode = "NULLABLE" },
  ])

  time_partitioning {
    type  = "DAY"
    field = "run_date"
  }
}

resource "google_composer_environment" "complete" {
  count = var.enable_composer_orchestration ? 1 : 0

  provider = google-beta

  project = var.project_id
  name    = var.composer_environment_name
  region  = var.region
  labels  = local.common_labels

  config {
    environment_size = var.composer_environment_size

    node_config {
      network         = "projects/${var.project_id}/global/networks/${var.composer_network}"
      service_account = google_service_account.composer[0].email
    }

    software_config {
      image_version = var.composer_image_version

      env_variables = {
        COMPLETE_PROJECT_ID       = var.project_id
        COMPLETE_REGION           = var.region
        CRM_RAW_BUCKET            = google_storage_bucket.crm["raw"].name
        CRM_MANIFEST_BUCKET       = google_storage_bucket.crm["manifest"].name
        DATAFLOW_TEMPLATE_PATH    = var.enable_dataflow_crm_ingestion ? "gs://${google_storage_bucket.dataflow_templates[0].name}/crm-csv-ingestion/template.json" : ""
        DATAFLOW_TEMP_BUCKET      = var.enable_dataflow_crm_ingestion ? google_storage_bucket.dataflow_temp[0].name : ""
        DATAFLOW_CONFIG_BUCKET    = var.enable_dataflow_crm_ingestion ? google_storage_bucket.config[0].name : ""
        DATAFLOW_WORKER_SA_EMAIL  = var.enable_dataflow_crm_ingestion ? google_service_account.dataflow_worker[0].email : ""
        DATAFORM_REPOSITORY       = var.enable_dataform_transform ? google_dataform_repository.crm[0].name : ""
        SALESFORCE_CLOUD_RUN_JOB  = var.enable_ml_salesforce_push ? google_cloud_run_v2_job.salesforce_campaign_push[0].name : ""
        SALESFORCE_DEFAULT_DRYRUN = "true"
      }
    }

    workloads_config {
      scheduler {
        cpu        = 0.5
        memory_gb  = 1
        storage_gb = 1
        count      = 1
      }

      web_server {
        cpu        = 0.5
        memory_gb  = 2
        storage_gb = 1
      }

      worker {
        cpu        = 1
        memory_gb  = 4
        storage_gb = 10
        min_count  = 1
        max_count  = 3
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.enable_dataflow_crm_ingestion && var.enable_dataform_transform && var.enable_dataplex_quality && var.enable_ml_salesforce_push
      error_message = "enable_composer_orchestration requires Step 3 Dataflow, Step 4 Dataform, Step 5 Dataplex, and Step 6 Salesforce resources to be enabled."
    }
  }

  depends_on = [
    google_project_service.required["composer.googleapis.com"],
    google_project_service.required["container.googleapis.com"],
    google_service_account_iam_member.composer_service_agent_v2_ext,
    google_project_iam_member.composer_worker_project_roles,
    google_service_account_iam_member.composer_dataflow_worker_user,
    google_service_account_iam_member.composer_dataform_runner_user,
    google_service_account_iam_member.composer_salesforce_job_user,
    google_bigquery_table.pipeline_step_status,
    google_bigquery_table.rerun_history,
  ]
}
