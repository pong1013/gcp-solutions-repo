variable "enable_storage_transfer_job" {
  description = "Create the scheduled Storage Transfer Service job for the simplest CRM ingestion path. Keep false until the on-prem agent pool is installed and registered."
  type        = bool
  default     = false
}

variable "crm_transfer_agent_pool_id" {
  description = "Storage Transfer Service agent pool id used by on-prem agents for CRM CSV transfer."
  type        = string
  default     = "simplest-crm-onprem-agent-pool"
}

variable "crm_transfer_source_root_directory" {
  description = "On-prem export root visible to the Storage Transfer agent. Expected to contain dated folders such as crm/2026-05-26/*.csv."
  type        = string
  default     = "/opt/companyx/crm_exports"
}

variable "crm_transfer_start_date" {
  description = "First scheduled transfer date in YYYY-MM-DD format."
  type        = string
  default     = "2026-05-26"

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.crm_transfer_start_date))
    error_message = "crm_transfer_start_date must use YYYY-MM-DD format."
  }
}

variable "crm_transfer_start_hour" {
  description = "Daily transfer start hour in UTC."
  type        = number
  default     = 18

  validation {
    condition     = var.crm_transfer_start_hour >= 0 && var.crm_transfer_start_hour <= 23
    error_message = "crm_transfer_start_hour must be between 0 and 23."
  }
}

locals {
  crm_transfer_start_date_parts = split("-", var.crm_transfer_start_date)
}

data "google_storage_transfer_project_service_account" "crm_transfer" {
  count = var.enable_storage_transfer_job ? 1 : 0

  project = var.project_id

  depends_on = [google_project_service.simplest_required]
}

# Simplest production baseline: use managed Storage Transfer Service instead of a
# custom on-prem upload script. The on-prem agent installation still happens on
# the customer side and is documented in docs/step2-crm-upload.md.
resource "google_storage_transfer_agent_pool" "crm_onprem" {
  count = var.enable_storage_transfer_job ? 1 : 0

  name         = var.crm_transfer_agent_pool_id
  display_name = "Simplest CRM on-prem transfer agents"

  bandwidth_limit {
    limit_mbps = "100"
  }

  depends_on = [
    google_project_iam_member.crm_transfer_pubsub_editor,
  ]
}

resource "google_project_iam_member" "crm_transfer_pubsub_editor" {
  count = var.enable_storage_transfer_job ? 1 : 0

  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${data.google_storage_transfer_project_service_account.crm_transfer[0].email}"

  depends_on = [google_project_service.simplest_required]
}

resource "google_storage_bucket_iam_member" "crm_raw_storage_transfer_writer" {
  count = var.enable_storage_transfer_job ? 1 : 0

  bucket = google_storage_bucket.crm["raw"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.crm_transfer[0].email}"

  depends_on = [google_project_service.simplest_required]
}

resource "google_storage_transfer_job" "crm_nightly_posix_to_gcs" {
  count = var.enable_storage_transfer_job ? 1 : 0

  description = "Nightly CRM CSV transfer from on-prem export folder to simplest raw CRM bucket"
  project     = var.project_id

  transfer_spec {
    source_agent_pool_name = google_storage_transfer_agent_pool.crm_onprem[0].name

    posix_data_source {
      root_directory = var.crm_transfer_source_root_directory
    }

    gcs_data_sink {
      bucket_name = google_storage_bucket.crm["raw"].name
      path        = "crm/"
    }

    transfer_options {
      overwrite_objects_already_existing_in_sink = true
      delete_objects_unique_in_sink              = false
      delete_objects_from_source_after_transfer  = false
    }
  }

  schedule {
    schedule_start_date {
      year  = tonumber(local.crm_transfer_start_date_parts[0])
      month = tonumber(local.crm_transfer_start_date_parts[1])
      day   = tonumber(local.crm_transfer_start_date_parts[2])
    }

    start_time_of_day {
      hours   = var.crm_transfer_start_hour
      minutes = 0
      seconds = 0
      nanos   = 0
    }
  }

  depends_on = [
    google_project_service.simplest_required,
    google_storage_transfer_agent_pool.crm_onprem,
    google_storage_bucket_iam_member.crm_raw_storage_transfer_writer,
  ]
}

output "crm_transfer_agent_pool_name" {
  description = "Storage Transfer Service agent pool name when enabled."
  value       = var.enable_storage_transfer_job ? google_storage_transfer_agent_pool.crm_onprem[0].name : null
}

output "crm_transfer_job_name" {
  description = "Storage Transfer Service nightly CRM transfer job name when enabled."
  value       = var.enable_storage_transfer_job ? google_storage_transfer_job.crm_nightly_posix_to_gcs[0].name : null
}
