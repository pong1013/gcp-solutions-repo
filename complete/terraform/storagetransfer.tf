locals {
  crm_transfer_start_date_parts = split("-", var.crm_transfer_start_date)
}

data "google_storage_transfer_project_service_account" "crm_transfer" {
  count = var.enable_storage_transfer_job ? 1 : 0

  project = var.project_id
}

resource "google_project_iam_member" "crm_transfer_pubsub_editor" {
  count = var.enable_storage_transfer_job ? 1 : 0

  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${data.google_storage_transfer_project_service_account.crm_transfer[0].email}"

  depends_on = [google_project_service.required["pubsub.googleapis.com"]]
}

resource "google_storage_transfer_agent_pool" "crm_onprem" {
  count = var.enable_storage_transfer_job ? 1 : 0

  name         = var.crm_transfer_agent_pool_id
  display_name = "Complete CRM on-prem transfer agents"

  bandwidth_limit {
    limit_mbps = tostring(var.crm_transfer_bandwidth_limit_mbps)
  }

  depends_on = [
    google_project_iam_member.crm_transfer_pubsub_editor,
  ]
}

resource "google_storage_bucket_iam_member" "crm_raw_storage_transfer_writer" {
  count = var.enable_storage_transfer_job ? 1 : 0

  bucket = google_storage_bucket.crm["raw"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.crm_transfer[0].email}"

  depends_on = [google_project_service.required["storage.googleapis.com"]]
}

resource "google_storage_bucket_iam_member" "crm_manifest_storage_transfer_writer" {
  count = var.enable_storage_transfer_job ? 1 : 0

  bucket = google_storage_bucket.crm["manifest"].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.crm_transfer[0].email}"

  depends_on = [google_project_service.required["storage.googleapis.com"]]
}

resource "google_storage_transfer_job" "crm_nightly_posix_to_gcs" {
  count = var.enable_storage_transfer_job ? 1 : 0

  description = "Nightly governed CRM CSV transfer from on-prem export folder to complete raw CRM bucket"
  project     = var.project_id
  status      = var.crm_transfer_job_status

  transfer_spec {
    source_agent_pool_name = google_storage_transfer_agent_pool.crm_onprem[0].id

    posix_data_source {
      root_directory = var.crm_transfer_source_root_directory
    }

    gcs_data_sink {
      bucket_name = google_storage_bucket.crm["raw"].name
      path        = var.crm_transfer_sink_path
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
    google_project_service.required["storagetransfer.googleapis.com"],
    google_storage_transfer_agent_pool.crm_onprem,
    google_storage_bucket_iam_member.crm_raw_storage_transfer_writer,
  ]
}
