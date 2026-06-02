terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "GCP project id for the simplest CRM migration lab."
  type        = string
}

variable "region" {
  description = "Default region for GCP resources."
  type        = string
  default     = "us-central1"
}

variable "bucket_location" {
  description = "Cloud Storage bucket location. Keep it close to BigQuery datasets."
  type        = string
  default     = "US"
}

variable "force_destroy_buckets" {
  description = "Allow Terraform destroy to delete non-empty lab buckets. Keep false for production."
  type        = bool
  default     = false
}

locals {
  crm_buckets = {
    raw = {
      name        = "${var.project_id}-raw-crm"
      description = "Landing zone for unprocessed CRM CSV files."
    }
    archive = {
      name        = "${var.project_id}-archive-crm"
      description = "Source files archived after successful ingestion."
    }
    rejected = {
      name        = "${var.project_id}-rejected-crm"
      description = "Files rejected by schema validation or data quality checks."
    }
  }

  common_labels = {
    app         = "crm-migration"
    solution    = "simplest"
    managed_by  = "terraform"
    environment = "lab"
  }
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "crm" {
  for_each = local.crm_buckets

  name                        = each.value.name
  project                     = var.project_id
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true       # 權限統一交給 IAM 
  public_access_prevention    = "enforced" # 禁止任何公開存取
  force_destroy               = var.force_destroy_buckets
  labels                      = local.common_labels

  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      age = 730
    }
  }

  depends_on = [google_project_service.storage]
}

output "crm_bucket_names" {
  description = "CRM landing zone bucket names by purpose."
  value = {
    for purpose, bucket in google_storage_bucket.crm : purpose => bucket.name
  }
}

output "crm_bucket_urls" {
  description = "CRM landing zone bucket URLs by purpose."
  value = {
    for purpose, bucket in google_storage_bucket.crm : purpose => bucket.url
  }
}
