data "google_compute_network" "datastream_vpc" {
  name    = var.datastream_vpc_network
  project = var.project_id
}

resource "google_datastream_private_connection" "default_vpc" {
  project               = var.project_id
  location              = var.region
  private_connection_id = "default-vpc-private-connection"
  display_name          = "Default VPC private connection"
  labels                = local.common_labels

  vpc_peering_config {
    vpc    = data.google_compute_network.datastream_vpc.id
    subnet = var.datastream_private_connection_subnet
  }

  depends_on = [google_project_service.required]
}

resource "google_compute_firewall" "allow_datastream_to_oracle_tunnel" {
  project     = var.project_id
  name        = "allow-datastream-oracle-tunnel-1521"
  network     = data.google_compute_network.datastream_vpc.name
  description = "Allow Datastream private connection range to reach the Oracle tunnel bastion."
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["1521"]
  }

  source_ranges = [var.datastream_private_connection_subnet]
  target_tags   = ["oracle-tunnel"]

  depends_on = [google_project_service.required]
}

resource "google_datastream_connection_profile" "oracle_source" {
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
    private_connection = google_datastream_private_connection.default_vpc.id
  }

  depends_on = [
    google_compute_firewall.allow_datastream_to_oracle_tunnel,
    google_secret_manager_secret_iam_member.datastream_oracle_password_reader,
  ]
}

resource "google_datastream_connection_profile" "bigquery_destination" {
  project               = var.project_id
  location              = var.region
  connection_profile_id = "bigquery-raw-destination"
  display_name          = "BigQuery raw destination"
  labels                = local.common_labels

  bigquery_profile {}

  depends_on = [google_bigquery_dataset.crm]
}

resource "google_datastream_stream" "oracle_user_raw_to_bigquery" {
  project                   = var.project_id
  location                  = var.region
  stream_id                 = "oracle-user-raw-to-bq"
  display_name              = "Oracle user_raw to BigQuery"
  labels                    = local.common_labels
  desired_state             = var.datastream_desired_state
  create_without_validation = var.datastream_stream_create_without_validation

  source_config {
    source_connection_profile = google_datastream_connection_profile.oracle_source.id

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
    destination_connection_profile = google_datastream_connection_profile.bigquery_destination.id

    bigquery_destination_config {
      data_freshness = "900s"

      single_target_dataset {
        dataset_id = "${var.project_id}:raw"
      }

      merge {}
    }
  }

  backfill_all {}
}
