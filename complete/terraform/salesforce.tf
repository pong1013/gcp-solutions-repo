resource "google_artifact_registry_repository" "jobs" {
  count = var.enable_ml_salesforce_push ? 1 : 0

  project       = var.project_id
  location      = var.region
  repository_id = "complete-jobs"
  description   = "Docker images for Salesforce campaign push job."
  format        = "DOCKER"
  labels        = local.common_labels

  lifecycle {
    precondition {
      condition     = var.enable_dataform_transform && var.enable_dataflow_crm_ingestion
      error_message = "enable_ml_salesforce_push requires enable_dataform_transform=true and enable_dataflow_crm_ingestion=true so mart and audit datasets exist."
    }
  }

  depends_on = [google_project_service.required["artifactregistry.googleapis.com"]]
}

resource "google_secret_manager_secret" "salesforce" {
  for_each = var.enable_ml_salesforce_push ? toset([
    "salesforce-client-id",
    "salesforce-client-secret",
    "salesforce-login-url"
  ]) : []

  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

resource "google_service_account" "salesforce_job" {
  count = var.enable_ml_salesforce_push ? 1 : 0

  project      = var.project_id
  account_id   = "salesforce-push-job"
  display_name = "Salesforce Campaign Activation Push Job Service Account"
  description  = "Service account used by Cloud Run Job to read audience table and push to Salesforce."
}

resource "google_project_iam_member" "salesforce_job_user" {
  count = var.enable_ml_salesforce_push ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.salesforce_job[0].email}"
}

resource "google_bigquery_dataset_iam_member" "salesforce_job_mart_viewer" {
  count = var.enable_ml_salesforce_push ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.dataform_output["mart"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.salesforce_job[0].email}"
}

resource "google_bigquery_dataset_iam_member" "salesforce_job_audit_editor" {
  count = var.enable_ml_salesforce_push ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.audit[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.salesforce_job[0].email}"
}

resource "google_secret_manager_secret_iam_member" "salesforce_job_secret_reader" {
  for_each = var.enable_ml_salesforce_push ? toset([
    "salesforce-client-id",
    "salesforce-client-secret",
    "salesforce-login-url"
  ]) : []

  project   = var.project_id
  secret_id = google_secret_manager_secret.salesforce[each.value].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.salesforce_job[0].email}"
}

resource "google_cloud_run_v2_job" "salesforce_campaign_push" {
  count = var.enable_ml_salesforce_push ? 1 : 0

  name                = "salesforce-campaign-push"
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.salesforce_job[0].email
      timeout         = "1800s"
      max_retries     = 0
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.jobs[0].repository_id}/salesforce-job:latest"

        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.project_id
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image
    ]
  }

  depends_on = [
    google_project_service.required["run.googleapis.com"],
    google_artifact_registry_repository.jobs
  ]
}
