locals {
  dataform_output_datasets = toset([
    "staging",
    "curated",
    "mart",
  ])
}

resource "google_bigquery_dataset" "dataform_output" {
  for_each = var.enable_dataform_transform ? local.dataform_output_datasets : []

  project    = var.project_id
  dataset_id = each.value
  location   = var.bucket_location
  labels     = local.common_labels

  description                 = "Complete CRM ${each.value} dataset managed by Dataform transformations."
  delete_contents_on_destroy  = false
  default_table_expiration_ms = null

  depends_on = [google_project_service.required["bigquery.googleapis.com"]]
}

resource "google_service_account" "dataform_runner" {
  count = var.enable_dataform_transform ? 1 : 0

  project      = var.project_id
  account_id   = var.dataform_service_account_id
  display_name = "Complete Dataform transformation runner"
  description  = "Runs Dataform SQL workflows that transform raw CRM and Oracle data into staging, curated, and mart datasets."
}

resource "google_project_iam_member" "dataform_runner_job_user" {
  count = var.enable_dataform_transform ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataform_runner[0].email}"
}

resource "google_bigquery_dataset_iam_member" "dataform_raw_viewer" {
  count = var.enable_dataform_transform ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform_runner[0].email}"
}

resource "google_bigquery_dataset_iam_member" "dataform_audit_editor" {
  count = var.enable_dataform_transform && var.enable_dataflow_crm_ingestion ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.audit[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform_runner[0].email}"
}

resource "google_bigquery_dataset_iam_member" "dataform_output_editor" {
  for_each = var.enable_dataform_transform ? google_bigquery_dataset.dataform_output : {}

  project    = var.project_id
  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform_runner[0].email}"
}

resource "google_service_account_iam_member" "dataform_service_agent_user" {
  count = var.enable_dataform_transform ? 1 : 0

  service_account_id = google_service_account.dataform_runner[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_project_service_identity.dataform[0].email}"
}

resource "google_service_account_iam_member" "dataform_service_agent_token_creator" {
  count = var.enable_dataform_transform ? 1 : 0

  service_account_id = google_service_account.dataform_runner[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_project_service_identity.dataform[0].email}"
}

resource "google_dataform_repository" "crm" {
  count = var.enable_dataform_transform ? 1 : 0

  provider = google-beta

  project         = var.project_id
  region          = var.region
  name            = var.dataform_repository_name
  display_name    = "Complete CRM Dataform"
  service_account = google_service_account.dataform_runner[0].email
  labels          = local.common_labels

  workspace_compilation_overrides {
    default_database = var.project_id
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    google_project_service.required["dataform.googleapis.com"],
    google_service_account_iam_member.dataform_service_agent_user,
    google_service_account_iam_member.dataform_service_agent_token_creator,
  ]
}

resource "google_dataform_repository_release_config" "nightly" {
  count = var.enable_dataform_transform && var.enable_dataform_release_config ? 1 : 0

  provider = google-beta

  project       = var.project_id
  region        = var.region
  repository    = google_dataform_repository.crm[0].name
  name          = "nightly"
  git_commitish = var.dataform_release_git_commitish
  cron_schedule = var.dataform_workflow_cron_schedule != "" ? var.dataform_workflow_cron_schedule : null
  time_zone     = "Asia/Taipei"

  code_compilation_config {
    default_database = var.project_id
    default_location = var.bucket_location
    default_schema   = "staging"
    assertion_schema = "audit"
  }
}

resource "google_dataform_repository_workflow_config" "nightly" {
  count = var.enable_dataform_transform && var.enable_dataform_release_config ? 1 : 0

  provider = google-beta

  project        = var.project_id
  region         = var.region
  repository     = google_dataform_repository.crm[0].name
  name           = "nightly-all"
  release_config = google_dataform_repository_release_config.nightly[0].id
  cron_schedule  = var.dataform_workflow_cron_schedule != "" ? var.dataform_workflow_cron_schedule : null
  time_zone      = "Asia/Taipei"

  invocation_config {
    service_account                  = google_service_account.dataform_runner[0].email
    transitive_dependencies_included = true
    included_tags                    = ["daily"]
  }
}
