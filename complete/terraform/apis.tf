locals {
  complete_required_services = toset([
    "bigquery.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "composer.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "datastream.googleapis.com",
    "dataform.googleapis.com",
    "dataflow.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "storagetransfer.googleapis.com",
    "dataplex.googleapis.com",
    "run.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.complete_required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
