variable "composer_image_version" {
  description = "Cloud Composer image version. Composer 2 keeps this lab aligned with the simplest-solution architecture."
  type        = string
  default     = "composer-2-airflow-2"
}

locals {
  composer_environment_name = "crm-simplest-composer"
  composer_service_agent    = "service-${data.google_project.current.number}@cloudcomposer-accounts.iam.gserviceaccount.com"
  gke_service_agent         = "service-${data.google_project.current.number}@container-engine-robot.iam.gserviceaccount.com"
  google_apis_service_agent = "${data.google_project.current.number}@cloudservices.gserviceaccount.com"
  compute_service_agent     = "service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com"

  composer_airflow_env_variables = {
    GCP_PROJECT_ID       = var.project_id
    GCP_REGION           = var.region
    RAW_BUCKET           = google_storage_bucket.crm["raw"].name
    ARCHIVE_BUCKET       = google_storage_bucket.crm["archive"].name
    REJECTED_BUCKET      = google_storage_bucket.crm["rejected"].name
    DATA_FUSION_REGION   = var.region
    DATA_FUSION_INSTANCE = google_data_fusion_instance.crm_simplest.name
    BIGQUERY_RAW_DATASET = google_bigquery_dataset.crm["raw"].dataset_id
    DQ_ALERT_TOPIC       = google_pubsub_topic.data_quality_alerts.name
  }
}

# Composer gets its own runtime identity. DAG code runs as this service account,
# so keep the permissions explicit instead of relying on a broad default account.
resource "google_service_account" "composer" {
  project      = var.project_id
  account_id   = "crm-simplest-composer"
  display_name = "CRM simplest Composer runtime service account"
  description  = "Runs Airflow DAGs for the simplest CRM migration solution."

  depends_on = [
    google_project_service.simplest_required,
  ]
}

# Composer environments require the Composer worker role on the environment
# service account so Airflow components can run inside the managed environment.
resource "google_project_iam_member" "composer_worker" {
  project = var.project_id
  role    = "roles/composer.worker"
  member  = "serviceAccount:${google_service_account.composer.email}"
}

# Cloud Composer v2 needs this role on the environment service account so the
# Composer service agent can configure Workload Identity bindings for the
# managed GKE-based Airflow environment.
resource "google_service_account_iam_member" "composer_service_agent_v2_extension" {
  service_account_id = google_service_account.composer.name
  role               = "roles/composer.ServiceAgentV2Ext"
  member             = "serviceAccount:${local.composer_service_agent}"
}

# Supporting service agents need to act as, or mint tokens for, the environment
# service account when Composer creates and manages its underlying resources.
resource "google_service_account_iam_member" "composer_gke_service_agent_user" {
  service_account_id = google_service_account.composer.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.gke_service_agent}"
}

resource "google_service_account_iam_member" "composer_google_apis_service_agent_user" {
  service_account_id = google_service_account.composer.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.google_apis_service_agent}"
}

resource "google_service_account_iam_member" "composer_compute_service_agent_token_creator" {
  service_account_id = google_service_account.composer.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.compute_service_agent}"
}

# The DAG checks CRM files, archives successful loads, and can write rejected
# evidence when data quality checks fail.
resource "google_storage_bucket_iam_member" "composer_crm_object_admin" {
  for_each = {
    raw      = google_storage_bucket.crm["raw"].name
    archive  = google_storage_bucket.crm["archive"].name
    rejected = google_storage_bucket.crm["rejected"].name
  }

  bucket = each.value
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.composer.email}"
}

# Composer will trigger Data Fusion pipelines from Airflow tasks.
resource "google_project_iam_member" "composer_datafusion_developer" {
  project = var.project_id
  role    = "roles/datafusion.developer"
  member  = "serviceAccount:${google_service_account.composer.email}"
}

# Composer will run BigQuery validation queries after raw ingestion completes.
resource "google_project_iam_member" "composer_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.composer.email}"
}

resource "google_bigquery_dataset_iam_member" "composer_raw_data_viewer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.crm["raw"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.composer.email}"
}

resource "google_bigquery_dataset_iam_member" "composer_raw_data_editor" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.crm["raw"].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.composer.email}"
}

resource "google_composer_environment" "crm_simplest" {
  project = var.project_id
  name    = local.composer_environment_name
  region  = var.region
  labels  = local.common_labels

  config {
    environment_size = "ENVIRONMENT_SIZE_SMALL"
    resilience_mode  = "STANDARD_RESILIENCE"

    software_config {
      image_version = var.composer_image_version

      # Keep new DAGs paused at creation so lab runs only happen when triggered.
      airflow_config_overrides = {
        core-dags_are_paused_at_creation = "True"
      }

      env_variables = local.composer_airflow_env_variables
    }

    # Small Composer 2 workloads keep the lab cost lower while still giving us
    # an Airflow dashboard, scheduler, worker, logs, and task-level rerun.
    workloads_config {
      scheduler {
        cpu        = 0.5
        memory_gb  = 1.875
        storage_gb = 1
        count      = 1
      }

      web_server {
        cpu        = 0.5
        memory_gb  = 1.875
        storage_gb = 1
      }

      worker {
        cpu        = 0.5
        memory_gb  = 1.875
        storage_gb = 1
        min_count  = 1
        max_count  = 2
      }
    }

    node_config {
      service_account = google_service_account.composer.name
    }
  }

  depends_on = [
    google_project_iam_member.composer_worker,
    google_service_account_iam_member.composer_service_agent_v2_extension,
    google_service_account_iam_member.composer_gke_service_agent_user,
    google_service_account_iam_member.composer_google_apis_service_agent_user,
    google_service_account_iam_member.composer_compute_service_agent_token_creator,
    google_project_iam_member.composer_datafusion_developer,
    google_project_iam_member.composer_bigquery_job_user,
    google_bigquery_dataset_iam_member.composer_raw_data_viewer,
    google_bigquery_dataset_iam_member.composer_raw_data_editor,
    google_storage_bucket_iam_member.composer_crm_object_admin,
    google_pubsub_topic_iam_member.composer_data_quality_alert_publisher,
  ]
}

output "composer_environment_name" {
  description = "Cloud Composer environment used by Step 5 orchestration."
  value       = google_composer_environment.crm_simplest.name
}

output "composer_dag_gcs_prefix" {
  description = "GCS prefix where Airflow DAG files should be uploaded."
  value       = google_composer_environment.crm_simplest.config[0].dag_gcs_prefix
}

output "composer_airflow_uri" {
  description = "Airflow web UI URL for dashboard, logs, and task reruns."
  value       = google_composer_environment.crm_simplest.config[0].airflow_uri
}
