locals {
  oracle_secret_ids = toset([
    "oracle-host",
    "oracle-port",
    "oracle-service-name",
    "oracle-username",
    "oracle-password",
    "oracle-sys-password",
    "oracle-app-password",
  ])
}

resource "google_secret_manager_secret" "oracle" {
  for_each = local.oracle_secret_ids

  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.required["secretmanager.googleapis.com"]]
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_secret_manager_secret_iam_member" "datastream_oracle_password_reader" {
  count = var.enable_datastream_resources ? 1 : 0

  project   = var.project_id
  secret_id = google_secret_manager_secret.oracle["oracle-password"].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_project_service_identity.datastream[0].email}"
}

resource "google_secret_manager_secret_iam_member" "oracle_vm_secret_reader" {
  for_each = var.enable_oracle_source_vm ? toset([
    "oracle-sys-password",
    "oracle-app-password",
    "oracle-password",
  ]) : toset([])

  project   = var.project_id
  secret_id = google_secret_manager_secret.oracle[each.value].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.oracle_source_vm[0].email}"
}
