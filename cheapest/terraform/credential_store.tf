locals {
  # These are Secret Manager containers only. Do not put real Oracle values in Terraform.
  # Secret versions are added separately with gcloud or CI/CD secret injection.
  oracle_secret_ids = toset([
    "oracle-jdbc-url",
    "oracle-host",
    "oracle-port",
    "oracle-service-name",
    "oracle-username",
    "oracle-password",
  ])
}

resource "google_secret_manager_secret" "oracle" {
  for_each = local.oracle_secret_ids

  project   = var.project_id
  secret_id = each.value
  labels    = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_secret_manager_secret_iam_member" "datastream_oracle_password_reader" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.oracle["oracle-password"].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-datastream.iam.gserviceaccount.com"
}
