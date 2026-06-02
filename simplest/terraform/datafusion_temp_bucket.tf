data "google_project" "current" {
  project_id = var.project_id
}

resource "google_storage_bucket" "datafusion_temp" {
  name                        = "${var.project_id}-datafusion-temp"
  project                     = var.project_id
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy_buckets
  labels                      = local.common_labels

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      age = 7
    }
  }

  depends_on = [google_project_service.storage]
}

# Data Fusion runs the pipeline on Dataproc. In this lab, the Dataproc workers
# use the Compute Engine default service account, so it needs object access to
# the pre-created temporary bucket used by the BigQuery sink.
resource "google_storage_bucket_iam_member" "datafusion_temp_compute_object_admin" {
  bucket = google_storage_bucket.datafusion_temp.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

output "datafusion_temp_bucket_name" {
  description = "Temporary GCS bucket for Data Fusion BigQuery sink staging files."
  value       = google_storage_bucket.datafusion_temp.name
}
