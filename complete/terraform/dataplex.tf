locals {
  user_360_quality_yaml    = yamldecode(file("${path.module}/../dataplex/curated_user_360_quality.yaml"))
  sf_audience_quality_yaml = yamldecode(file("${path.module}/../dataplex/mart_salesforce_campaign_audience_quality.yaml"))
}

resource "google_service_account" "dataplex_quality" {
  count = var.enable_dataplex_quality ? 1 : 0

  project      = var.project_id
  account_id   = var.dataplex_service_account_id
  display_name = "Dataplex Quality Scan Service Account"
  description  = "Runs Dataplex data quality scans and writes results."
}

# Grant Dataplex service account BigQuery read/write access
resource "google_project_iam_member" "dataplex_bq_job_user" {
  count = var.enable_dataplex_quality ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataplex_quality[0].email}"
}

resource "google_project_iam_member" "dataplex_bq_data_viewer" {
  count = var.enable_dataplex_quality ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.dataplex_quality[0].email}"
}

resource "google_bigquery_dataset_iam_member" "dataplex_audit_editor" {
  count = var.enable_dataplex_quality ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.audit[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataplex_quality[0].email}"
}

# Pub/Sub Topic for Quality Failure Notifications
resource "google_pubsub_topic" "quality_alerts" {
  count = var.enable_dataplex_quality ? 1 : 0

  project = var.project_id
  name    = "dataplex-quality-alerts"
}

# Monitoring Alert Policy for Quality Failure (Optional, minimal implementation)
resource "google_monitoring_alert_policy" "quality_failure" {
  count = var.enable_dataplex_quality ? 1 : 0

  project      = var.project_id
  display_name = "Dataplex Quality Scan Failure"
  combiner     = "OR"
  conditions {
    display_name = "Log match condition"
    condition_matched_log {
      filter = "resource.type=\"dataplex.googleapis.com/DataScan\" AND severity>=ERROR"
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }

  notification_channels = var.storage_transfer_notification_channel_ids # Reusing notification channels from earlier, or can be empty

  depends_on = [google_project_service.required["monitoring.googleapis.com"]]
}

resource "google_project_service_identity" "dataplex_sa" {
  count = var.enable_dataplex_quality ? 1 : 0

  provider = google-beta

  project = var.project_id
  service = "dataplex.googleapis.com"

  depends_on = [google_project_service.required["dataplex.googleapis.com"]]
}

resource "google_dataplex_lake" "crm" {
  count = var.enable_dataplex_quality ? 1 : 0

  project      = var.project_id
  location     = var.region
  name         = var.dataplex_lake_name
  display_name = "CRM Lake"
  labels       = local.common_labels

  depends_on = [google_project_service.required["dataplex.googleapis.com"]]
}

resource "google_dataplex_zone" "curated" {
  count = var.enable_dataplex_quality ? 1 : 0

  project      = var.project_id
  location     = var.region
  lake         = google_dataplex_lake.crm[0].name
  name         = var.dataplex_zone_name
  display_name = "Curated Zone"
  type         = "CURATED"
  discovery_spec {
    enabled = false
  }
  resource_spec {
    location_type = "SINGLE_REGION"
  }
}

resource "google_dataplex_datascan" "user_360_quality" {
  count = var.enable_dataplex_quality ? 1 : 0

  project      = var.project_id
  location     = var.region
  data_scan_id = "user-360-quality"

  data {
    resource = "//bigquery.googleapis.com/projects/${var.project_id}/datasets/curated/tables/user_360"
  }

  execution_spec {
    trigger {
      on_demand {}
    }
  }

  data_quality_spec {
    sampling_percent = local.user_360_quality_yaml.dataQualitySpec.samplingPercent

    post_scan_actions {
      bigquery_export {
        results_table = "projects/${var.project_id}/datasets/audit/tables/dataplex_quality_results"
      }
    }

    dynamic "rules" {
      for_each = local.user_360_quality_yaml.dataQualitySpec.rules
      iterator = rule
      content {
        name        = try(replace(rule.value.ruleId, "_", "-"), null)
        description = try(rule.value.description, null)
        dimension   = try(rule.value.dimension, null)
        column      = try(rule.value.column, null)

        dynamic "non_null_expectation" {
          for_each = can(rule.value.nonNullExpectation) ? [1] : []
          content {}
        }
        dynamic "row_condition_expectation" {
          for_each = can(rule.value.rowConditionExpectation) ? [rule.value.rowConditionExpectation] : []
          content {
            sql_expression = row_condition_expectation.value.sqlExpression
          }
        }
        dynamic "table_condition_expectation" {
          for_each = can(rule.value.tableConditionExpectation) ? [rule.value.tableConditionExpectation] : []
          content {
            sql_expression = table_condition_expectation.value.sqlExpression
          }
        }
        dynamic "uniqueness_expectation" {
          for_each = can(rule.value.uniquenessExpectation) ? [1] : []
          content {}
        }
      }
    }
  }

  depends_on = [
    google_project_service.required["dataplex.googleapis.com"],
    google_project_service_identity.dataplex_sa,
  ]
}

resource "google_dataplex_datascan" "salesforce_audience_quality" {
  count = var.enable_dataplex_quality ? 1 : 0

  project      = var.project_id
  location     = var.region
  data_scan_id = "salesforce-audience-quality"

  data {
    resource = "//bigquery.googleapis.com/projects/${var.project_id}/datasets/mart/tables/salesforce_campaign_audience"
  }

  execution_spec {
    trigger {
      on_demand {}
    }
  }

  data_quality_spec {
    sampling_percent = local.sf_audience_quality_yaml.dataQualitySpec.samplingPercent

    post_scan_actions {
      bigquery_export {
        results_table = "projects/${var.project_id}/datasets/audit/tables/dataplex_quality_results"
      }
    }

    dynamic "rules" {
      for_each = local.sf_audience_quality_yaml.dataQualitySpec.rules
      iterator = rule
      content {
        name        = try(replace(rule.value.ruleId, "_", "-"), null)
        description = try(rule.value.description, null)
        dimension   = try(rule.value.dimension, null)
        column      = try(rule.value.column, null)

        dynamic "non_null_expectation" {
          for_each = can(rule.value.nonNullExpectation) ? [1] : []
          content {}
        }
        dynamic "row_condition_expectation" {
          for_each = can(rule.value.rowConditionExpectation) ? [rule.value.rowConditionExpectation] : []
          content {
            sql_expression = row_condition_expectation.value.sqlExpression
          }
        }
        dynamic "table_condition_expectation" {
          for_each = can(rule.value.tableConditionExpectation) ? [rule.value.tableConditionExpectation] : []
          content {
            sql_expression = table_condition_expectation.value.sqlExpression
          }
        }
        dynamic "uniqueness_expectation" {
          for_each = can(rule.value.uniquenessExpectation) ? [1] : []
          content {}
        }
      }
    }
  }

  depends_on = [
    google_project_service.required["dataplex.googleapis.com"],
    google_project_service_identity.dataplex_sa,
  ]
}
