locals {
  # Step 3 needs these APIs before Terraform can create Data Fusion,
  # BigQuery-related sinks, or Secret Manager secret containers.
  simplest_required_services = toset([
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "composer.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "datafusion.googleapis.com",
    "iam.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "storagetransfer.googleapis.com",
  ])
}

# Keep API enablement in Terraform so production setup is repeatable and reviewable.
resource "google_project_service" "simplest_required" {
  for_each = local.simplest_required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
