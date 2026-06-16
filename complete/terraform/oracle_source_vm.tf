data "google_compute_network" "oracle_vm_vpc" {
  name    = var.oracle_vm_network
  project = var.project_id
}

data "google_compute_image" "debian_12" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_service_account" "oracle_source_vm" {
  count = var.enable_oracle_source_vm ? 1 : 0

  project      = var.project_id
  account_id   = "complete-oracle-source-vm"
  display_name = "Complete Oracle XE source VM"

  depends_on = [google_project_service.required["iam.googleapis.com"]]
}

resource "google_project_iam_member" "oracle_source_vm_log_writer" {
  count = var.enable_oracle_source_vm ? 1 : 0

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.oracle_source_vm[0].email}"

  depends_on = [google_project_service.required["logging.googleapis.com"]]
}

resource "google_compute_firewall" "allow_iap_ssh_to_oracle_vm" {
  count = var.enable_oracle_source_vm ? 1 : 0

  project     = var.project_id
  name        = "complete-allow-iap-ssh-oracle-vm"
  network     = data.google_compute_network.oracle_vm_vpc.name
  description = "Allow IAP TCP forwarding to SSH into the Complete Oracle XE source VM."
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["complete-oracle-source"]

  depends_on = [google_project_service.required["compute.googleapis.com"]]
}

resource "google_compute_firewall" "allow_datastream_to_oracle_vm" {
  count = var.enable_oracle_source_vm ? 1 : 0

  project     = var.project_id
  name        = "complete-allow-datastream-oracle-1521"
  network     = data.google_compute_network.oracle_vm_vpc.name
  description = "Allow Datastream private connection range to reach Oracle XE on the source VM."
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = [tostring(var.oracle_port)]
  }

  source_ranges = [var.datastream_private_connection_subnet]
  target_tags   = ["complete-oracle-source"]

  depends_on = [google_project_service.required["compute.googleapis.com"]]
}

resource "google_compute_instance" "oracle_source" {
  count = var.enable_oracle_source_vm ? 1 : 0

  project      = var.project_id
  name         = var.oracle_vm_name
  zone         = var.oracle_vm_zone
  machine_type = var.oracle_vm_machine_type
  tags         = ["complete-oracle-source"]
  labels       = local.common_labels

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_12.self_link
      size  = var.oracle_vm_boot_disk_size_gb
      type  = var.oracle_vm_boot_disk_type
    }
  }

  network_interface {
    network = data.google_compute_network.oracle_vm_vpc.self_link

    access_config {}
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/scripts/oracle-xe-startup.sh.tftpl", {
      project_id          = var.project_id
      oracle_docker_image = var.oracle_docker_image
      oracle_port         = var.oracle_port
      oracle_service_name = var.oracle_service_name
      oracle_username     = var.oracle_username
    })
  }

  service_account {
    email  = google_service_account.oracle_source_vm[0].email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    ignore_changes = [
      boot_disk[0].initialize_params[0].image,
    ]
  }

  depends_on = [
    google_project_service.required["compute.googleapis.com"],
    google_secret_manager_secret_iam_member.oracle_vm_secret_reader,
  ]
}
