locals {
  crm_buckets = {
    raw = {
      name           = "${var.project_id}-complete-crm-raw"
      description    = "Governed landing zone for unprocessed CRM CSV files and raw transfer evidence."
      retention_days = var.raw_retention_days
    }
    archive = {
      name           = "${var.project_id}-complete-crm-archive"
      description    = "Archive bucket for CRM source files after successful ingestion and quality checks."
      retention_days = var.archive_retention_days
    }
    rejected = {
      name           = "${var.project_id}-complete-crm-rejected"
      description    = "Rejected bucket for invalid CRM files, rejected rows, and schema validation evidence."
      retention_days = var.rejected_retention_days
    }
    manifest = {
      name           = "${var.project_id}-complete-crm-manifest"
      description    = "Audit bucket for Storage Transfer manifests and completion evidence."
      retention_days = var.manifest_retention_days
    }
  }

  common_labels = {
    app         = "crm-migration"
    solution    = "complete"
    managed_by  = "terraform"
    environment = "lab"
  }
}

resource "google_storage_bucket" "crm" {
  for_each = local.crm_buckets

  name                        = each.value.name
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
      age = each.value.retention_days
    }
  }

  depends_on = [google_project_service.required]
}
