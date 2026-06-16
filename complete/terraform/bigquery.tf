resource "google_bigquery_dataset" "raw" {
  project    = var.project_id
  dataset_id = "raw"
  location   = var.bucket_location
  labels     = local.common_labels

  description                 = "Raw source tables from Oracle Datastream and governed CRM ingestion."
  delete_contents_on_destroy  = false
  default_table_expiration_ms = null

  depends_on = [google_project_service.required["bigquery.googleapis.com"]]
}
