variable "project_id" {
  description = "GCP project id for the cheapest CRM migration lab."
  type        = string
}

variable "region" {
  description = "Default region for regional GCP resources."
  type        = string
  default     = "us-central1"
}

variable "bucket_location" {
  description = "Cloud Storage bucket location. Keep it compatible with BigQuery datasets."
  type        = string
  default     = "US"
}

variable "force_destroy_buckets" {
  description = "Allow Terraform destroy to delete non-empty lab buckets. Keep false for production."
  type        = bool
  default     = false
}

variable "raw_prefix_retention_days" {
  description = "Retention period for raw CRM source objects."
  type        = number
  default     = 730
}

variable "archive_prefix_retention_days" {
  description = "Retention period for archived CRM source objects."
  type        = number
  default     = 730
}

variable "rejected_prefix_retention_days" {
  description = "Retention period for rejected CRM source objects."
  type        = number
  default     = 730
}

variable "oracle_host" {
  description = "Oracle host that Datastream can reach. For lab, pass the bastion internal IP from Step 2E."
  type        = string
}

variable "oracle_port" {
  description = "Oracle listener port."
  type        = number
  default     = 1521
}

variable "oracle_service_name" {
  description = "Oracle service name."
  type        = string
  default     = "XEPDB1"
}

variable "oracle_username" {
  description = "Oracle replication username for the lab source."
  type        = string
  default     = "C##DATASTREAM"
}

variable "oracle_schema" {
  description = "Oracle schema to include in the Datastream stream."
  type        = string
  default     = "APP"
}

variable "oracle_table" {
  description = "Oracle table to include in the Datastream stream."
  type        = string
  default     = "USER_RAW"
}

variable "datastream_vpc_network" {
  description = "VPC network name Datastream should peer with for private connectivity."
  type        = string
  default     = "default"
}

variable "datastream_private_connection_subnet" {
  description = "Unused /29 CIDR range for Datastream VPC peering. Must not overlap existing VPC subnets."
  type        = string
  default     = "172.31.255.0/29"
}

variable "datastream_desired_state" {
  description = "Initial Datastream stream state. Keep NOT_STARTED until connection validation is complete."
  type        = string
  default     = "NOT_STARTED"

  validation {
    condition     = contains(["NOT_STARTED", "RUNNING", "PAUSED"], var.datastream_desired_state)
    error_message = "datastream_desired_state must be NOT_STARTED, RUNNING, or PAUSED."
  }
}

variable "datastream_connection_profile_create_without_validation" {
  description = "Skip Oracle connection profile validation at creation time. Lab keeps this true so Terraform can create resources before the temporary tunnel is fully debugged."
  type        = bool
  default     = true
}

variable "datastream_stream_create_without_validation" {
  description = "Skip Datastream stream validation at creation time. Lab keeps this true because local Oracle CDC settings may not be production-ready yet."
  type        = bool
  default     = true
}

variable "scheduler_cron" {
  description = "Cron schedule for the nightly CRM workflow. Default is 02:00 every day."
  type        = string
  default     = "0 2 * * *"
}

variable "scheduler_time_zone" {
  description = "Time zone used by Cloud Scheduler."
  type        = string
  default     = "Asia/Taipei"
}

variable "scheduler_paused" {
  description = "Keep the Scheduler job paused by default for lab safety. Set false only when the pipeline is ready for automatic nightly runs."
  type        = bool
  default     = true
}

variable "enable_salesforce_cloud_run_job" {
  description = "Create the Salesforce Cloud Run Job. Keep false until the job image exists in Artifact Registry."
  type        = bool
  default     = false
}

variable "salesforce_job_image" {
  description = "Container image URI for the Salesforce Cloud Run Job. Required when enable_salesforce_cloud_run_job is true."
  type        = string
  default     = ""

  validation {
    condition     = var.enable_salesforce_cloud_run_job == false || length(var.salesforce_job_image) > 0
    error_message = "salesforce_job_image must be set when enable_salesforce_cloud_run_job is true."
  }
}

variable "salesforce_job_task_timeout_seconds" {
  description = "Cloud Run Job task timeout in seconds."
  type        = number
  default     = 3600
}

variable "salesforce_job_max_retries" {
  description = "Cloud Run Job max retries for the Salesforce push task."
  type        = number
  default     = 1
}
