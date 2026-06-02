# Cloud Data Fusion is the low-code ETL tool used by the simplest solution.
# The JDBC pipeline is designed in Data Fusion Studio, then exported as JSON
# into simplest/datafusion/pipelines/ for PR review.
resource "google_data_fusion_instance" "crm_simplest" {
  project = var.project_id
  region  = var.region
  name    = "crm-simplest-datafusion"
  type    = "BASIC"

  # Send pipeline logs and metrics to Cloud Logging/Monitoring for debugging.
  enable_stackdriver_logging    = true
  enable_stackdriver_monitoring = true
  labels                        = local.common_labels

  # Data Fusion API must be enabled before the instance can be created.
  depends_on = [
    google_project_service.simplest_required,
  ]
}

output "datafusion_instance_name" {
  description = "Cloud Data Fusion instance used by the simplest solution."
  value       = google_data_fusion_instance.crm_simplest.name
}
