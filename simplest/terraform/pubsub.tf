locals {
  data_quality_alert_topic_name        = "crm-data-quality-alerts"
  data_quality_alert_subscription_name = "crm-data-quality-alerts-debug"
}

resource "google_pubsub_topic" "data_quality_alerts" {
  project = var.project_id
  name    = local.data_quality_alert_topic_name
  labels  = local.common_labels

  depends_on = [
    google_project_service.simplest_required,
  ]
}

resource "google_pubsub_subscription" "data_quality_alerts_debug" {
  project = var.project_id
  name    = local.data_quality_alert_subscription_name
  topic   = google_pubsub_topic.data_quality_alerts.id
  labels  = local.common_labels

  ack_deadline_seconds       = 20
  message_retention_duration = "604800s"
}

resource "google_pubsub_topic_iam_member" "composer_data_quality_alert_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.data_quality_alerts.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.composer.email}"
}

output "data_quality_alert_topic" {
  description = "Pub/Sub topic used for data quality manager notifications."
  value       = google_pubsub_topic.data_quality_alerts.id
}

output "data_quality_alert_debug_subscription" {
  description = "Debug subscription for pulling data quality alert messages in the lab."
  value       = google_pubsub_subscription.data_quality_alerts_debug.id
}
