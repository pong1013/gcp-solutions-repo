data "google_compute_network" "datastream_vpc" {
  name    = var.datastream_vpc_network
  project = var.project_id
}

resource "google_datastream_private_connection" "default_vpc" {
  count = var.enable_datastream_resources ? 1 : 0

  project               = var.project_id
  location              = var.region
  private_connection_id = "default-vpc-private-connection"
  display_name          = "Default VPC private connection"
  labels                = local.common_labels

  vpc_peering_config {
    vpc    = data.google_compute_network.datastream_vpc.id
    subnet = var.datastream_private_connection_subnet
  }

  depends_on = [
    google_project_service_identity.datastream,
  ]
}

resource "google_datastream_connection_profile" "oracle_source" {
  count = var.enable_datastream_resources ? 1 : 0

  project                   = var.project_id
  location                  = var.region
  connection_profile_id     = "oracle-user-raw-source"
  display_name              = "Oracle user_raw source"
  labels                    = local.common_labels
  create_without_validation = var.datastream_connection_profile_create_without_validation

  oracle_profile {
    hostname                       = var.oracle_host
    port                           = var.oracle_port
    username                       = var.oracle_username
    database_service               = var.oracle_service_name
    secret_manager_stored_password = "${google_secret_manager_secret.oracle["oracle-password"].id}/versions/latest"
  }

  private_connectivity {
    private_connection = google_datastream_private_connection.default_vpc[0].id
  }

  lifecycle {
    precondition {
      condition     = length(var.oracle_host) > 0
      error_message = "oracle_host must be set when enable_datastream_resources is true."
    }
  }

  depends_on = [
    google_compute_firewall.allow_datastream_to_oracle_vm,
    google_secret_manager_secret_iam_member.datastream_oracle_password_reader,
  ]
}

resource "google_datastream_connection_profile" "bigquery_destination" {
  count = var.enable_datastream_resources ? 1 : 0

  project               = var.project_id
  location              = var.region
  connection_profile_id = "bigquery-raw-destination"
  display_name          = "BigQuery raw destination"
  labels                = local.common_labels

  bigquery_profile {}

  depends_on = [google_bigquery_dataset.raw]
}

resource "google_datastream_stream" "oracle_user_raw_to_bigquery" {
  count = var.enable_datastream_resources ? 1 : 0

  project                   = var.project_id
  location                  = var.region
  stream_id                 = "oracle-user-raw-to-bq"
  display_name              = "Oracle user_raw to BigQuery"
  labels                    = local.common_labels
  desired_state             = var.datastream_desired_state
  create_without_validation = var.datastream_stream_create_without_validation

  source_config {
    source_connection_profile = google_datastream_connection_profile.oracle_source[0].id

    oracle_source_config {
      include_objects {
        oracle_schemas {
          schema = var.oracle_schema

          oracle_tables {
            table = var.oracle_table
          }
        }
      }

      drop_large_objects {}
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bigquery_destination[0].id

    bigquery_destination_config {
      data_freshness = var.datastream_data_freshness

      single_target_dataset {
        dataset_id = "${var.project_id}:${google_bigquery_dataset.raw.dataset_id}"
      }

      merge {}
    }
  }

  backfill_all {}
}
