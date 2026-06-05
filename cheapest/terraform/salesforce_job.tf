locals {
  salesforce_secret_ids = toset([
    "salesforce-client-id",
    "salesforce-client-secret",
    "salesforce-username",
    "salesforce-password",
    "salesforce-security-token",
    "salesforce-instance-url",
  ])

  salesforce_cloud_run_secret_ids = toset([
    "salesforce-client-id",
    "salesforce-client-secret",
    "salesforce-instance-url",
  ])

  cloud_build_compute_service_account = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_artifact_registry_repository" "jobs" {
  project       = var.project_id
  location      = var.region
  repository_id = "cheapest-jobs"
  description   = "Container images for cheapest CRM migration jobs."
  format        = "DOCKER"
  labels        = local.common_labels

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret" "salesforce" {
  for_each = local.salesforce_secret_ids

  project   = var.project_id
  secret_id = each.value
  labels    = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_service_account" "salesforce_job" {
  project      = var.project_id
  account_id   = "cheapest-salesforce-job-sa"
  display_name = "Cheapest Salesforce job service account"
  description  = "Runs the Cloud Run Job that pushes approved CRM audiences to Salesforce."
}

resource "google_project_iam_member" "salesforce_job_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.salesforce_job.email}"
}

resource "google_artifact_registry_repository_iam_member" "cloud_build_jobs_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.jobs.location
  repository = google_artifact_registry_repository.jobs.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${local.cloud_build_compute_service_account}"
}

resource "google_bigquery_dataset_iam_member" "salesforce_job_mart_viewer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.crm["mart"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.salesforce_job.email}"
}

resource "google_bigquery_dataset_iam_member" "salesforce_job_audit_editor" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.crm["audit"].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.salesforce_job.email}"
}

resource "google_secret_manager_secret_iam_member" "salesforce_job_secret_reader" {
  for_each = google_secret_manager_secret.salesforce

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.salesforce_job.email}"
}

resource "google_project_iam_member" "workflow_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_service_account_iam_member" "workflow_salesforce_job_sa_user" {
  service_account_id = google_service_account.salesforce_job.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_cloud_run_v2_job" "salesforce_campaign_push" {
  count = var.enable_salesforce_cloud_run_job ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = "salesforce-campaign-push"
  labels   = local.common_labels

  deletion_protection = false

  template {
    template {
      service_account = google_service_account.salesforce_job.email
      timeout         = "${var.salesforce_job_task_timeout_seconds}s"
      max_retries     = var.salesforce_job_max_retries

      containers {
        image = var.salesforce_job_image

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "BQ_DATASET"
          value = "mart"
        }

        env {
          name  = "BQ_TABLE"
          value = "salesforce_campaign_audience"
        }

        env {
          name  = "SALESFORCE_DRY_RUN"
          value = "true"
        }

        dynamic "env" {
          for_each = {
            for secret_id in local.salesforce_cloud_run_secret_ids :
            secret_id => google_secret_manager_secret.salesforce[secret_id]
          }

          content {
            name = upper(replace(env.key, "-", "_"))

            value_source {
              secret_key_ref {
                secret  = env.value.secret_id
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_artifact_registry_repository.jobs,
    google_bigquery_dataset_iam_member.salesforce_job_audit_editor,
    google_bigquery_dataset_iam_member.salesforce_job_mart_viewer,
    google_project_iam_member.salesforce_job_bigquery_job_user,
    google_secret_manager_secret_iam_member.salesforce_job_secret_reader,
  ]
}
