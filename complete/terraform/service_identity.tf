resource "google_project_service_identity" "datastream" {
  count = var.enable_datastream_resources ? 1 : 0

  provider = google-beta

  project = var.project_id
  service = "datastream.googleapis.com"

  depends_on = [google_project_service.required["datastream.googleapis.com"]]
}

resource "google_project_service_identity" "dataform" {
  count = var.enable_dataform_transform ? 1 : 0

  provider = google-beta

  project = var.project_id
  service = "dataform.googleapis.com"

  depends_on = [google_project_service.required["dataform.googleapis.com"]]
}
