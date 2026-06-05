resource "google_service_account" "workflow" {
  project      = var.project_id
  account_id   = "cheapest-workflow-sa"
  display_name = "Cheapest Workflow service account"
  description  = "Runs the cheapest nightly CRM pipeline workflow."

  depends_on = [google_project_service.required]
}

resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "cheapest-scheduler-sa"
  display_name = "Cheapest Scheduler service account"
  description  = "Invokes the cheapest nightly CRM pipeline workflow."

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "workflow_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_project_iam_member" "workflow_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_project_iam_member" "scheduler_workflows_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_storage_bucket_iam_member" "workflow_crm_lake_object_viewer" {
  bucket = google_storage_bucket.crm_lake.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_workflows_workflow" "nightly_crm_pipeline" {
  project                 = var.project_id
  region                  = var.region
  name                    = "nightly-crm-pipeline"
  description             = "Serverless orchestration for the cheapest nightly CRM pipeline."
  service_account         = google_service_account.workflow.email
  source_contents         = file("${path.module}/../workflows/nightly-crm-pipeline.yaml")
  labels                  = local.common_labels
  call_log_level          = "LOG_ALL_CALLS"
  execution_history_level = "EXECUTION_HISTORY_BASIC"
  deletion_protection     = false

  depends_on = [
    google_bigquery_dataset_iam_member.workflow_pipeline_data_editor,
    google_bigquery_dataset_iam_member.workflow_raw_data_editor,
    google_project_iam_member.workflow_bigquery_job_user,
    google_project_iam_member.workflow_log_writer,
    google_storage_bucket_iam_member.workflow_crm_lake_object_viewer,
  ]
}

resource "google_cloud_scheduler_job" "nightly_crm_pipeline" {
  project     = var.project_id
  region      = var.region
  name        = "nightly-crm-pipeline-schedule"
  description = "Runs the cheapest CRM pipeline nightly through Workflows."
  schedule    = var.scheduler_cron
  time_zone   = var.scheduler_time_zone
  paused      = var.scheduler_paused

  http_target {
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.nightly_crm_pipeline.name}/executions"
    http_method = "POST"
    headers = {
      "Content-Type" = "application/json"
    }
    body = base64encode(jsonencode({
      argument = jsonencode({
        step_name = "all"
      })
    }))

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [
    google_project_iam_member.scheduler_workflows_invoker,
    google_workflows_workflow.nightly_crm_pipeline,
  ]
}
