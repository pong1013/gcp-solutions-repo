locals {
  crm_lake_bucket_name = "${var.project_id}-crm-lake"

  common_labels = {
    app         = "crm-migration"
    solution    = "cheapest"
    managed_by  = "terraform"
    environment = "lab"
  }
}

resource "google_storage_bucket" "crm_lake" {
  name                        = local.crm_lake_bucket_name
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
      age            = var.raw_prefix_retention_days
      matches_prefix = ["raw/crm/"]
    }
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      age            = var.archive_prefix_retention_days
      matches_prefix = ["archive/crm/"]
    }
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      age            = var.rejected_prefix_retention_days
      matches_prefix = ["rejected/crm/"]
    }
  }

  depends_on = [google_project_service.required]
}
