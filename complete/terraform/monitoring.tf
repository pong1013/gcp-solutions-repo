resource "google_monitoring_alert_policy" "storage_transfer_failure" {
  count = var.enable_storage_transfer_job && length(var.storage_transfer_notification_channel_ids) > 0 ? 1 : 0

  project      = var.project_id
  display_name = "Complete CRM Storage Transfer failures"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Storage Transfer reported transfer errors"

    condition_threshold {
      filter          = "resource.type=\"storage_transfer_job\" AND metric.type=\"storagetransfer.googleapis.com/transferjob/error_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = var.storage_transfer_notification_channel_ids

  depends_on = [google_project_service.required]
}
