variable "project_id" {
  description = "GCP project id for the complete CRM migration solution."
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

variable "raw_retention_days" {
  description = "Retention period for raw CRM source objects."
  type        = number
  default     = 730
}

variable "archive_retention_days" {
  description = "Retention period for archived CRM source objects."
  type        = number
  default     = 2555
}

variable "rejected_retention_days" {
  description = "Retention period for rejected CRM source objects and records."
  type        = number
  default     = 2555
}

variable "manifest_retention_days" {
  description = "Retention period for transfer manifest and audit evidence objects."
  type        = number
  default     = 2555
}

variable "enable_storage_transfer_job" {
  description = "Create the scheduled Storage Transfer Service job. Keep false until the on-prem agent is installed and the source path is approved."
  type        = bool
  default     = false
}

variable "crm_transfer_agent_pool_id" {
  description = "Storage Transfer Service agent pool id used by on-prem agents for CRM CSV transfer."
  type        = string
  default     = "complete-crm-onprem-agent-pool"
}

variable "crm_transfer_source_root_directory" {
  description = "On-prem export root visible to the Storage Transfer agent. Expected to contain dated folders such as crm/2026-05-26/*.csv."
  type        = string
  default     = "/opt/companyx/crm_exports"
}

variable "crm_transfer_sink_path" {
  description = "Destination path inside the raw CRM bucket. Use crm/YYYY-MM-DD/ for one lab run, or crm/ when the source root already contains dated folders."
  type        = string
  default     = "crm/"
}

variable "crm_transfer_job_status" {
  description = "Storage Transfer job status. Keep DISABLED in lab after manual test; use ENABLED only for production nightly scheduling."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED", "DELETED"], var.crm_transfer_job_status)
    error_message = "crm_transfer_job_status must be ENABLED, DISABLED, or DELETED."
  }
}

variable "crm_transfer_start_date" {
  description = "First scheduled transfer date in YYYY-MM-DD format."
  type        = string
  default     = "2026-05-26"

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.crm_transfer_start_date))
    error_message = "crm_transfer_start_date must use YYYY-MM-DD format."
  }
}

variable "crm_transfer_start_hour" {
  description = "Daily transfer start hour in UTC."
  type        = number
  default     = 18

  validation {
    condition     = var.crm_transfer_start_hour >= 0 && var.crm_transfer_start_hour <= 23
    error_message = "crm_transfer_start_hour must be between 0 and 23."
  }
}

variable "crm_transfer_bandwidth_limit_mbps" {
  description = "Bandwidth limit for on-prem Storage Transfer agents."
  type        = number
  default     = 100
}

variable "storage_transfer_notification_channel_ids" {
  description = "Monitoring notification channel ids for Storage Transfer failures. Leave empty in lab."
  type        = list(string)
  default     = []
}

variable "enable_oracle_source_vm" {
  description = "Create a production-like Oracle XE source VM for Datastream validation. Keep false until Oracle bootstrap secrets are ready."
  type        = bool
  default     = false
}

variable "oracle_vm_name" {
  description = "Name of the GCE VM that runs Oracle XE for the production-like source."
  type        = string
  default     = "complete-oracle-xe-source"
}

variable "oracle_vm_zone" {
  description = "Zone for the Oracle XE source VM."
  type        = string
  default     = "us-central1-a"
}

variable "oracle_vm_machine_type" {
  description = "Machine type for the Oracle XE source VM."
  type        = string
  default     = "e2-standard-2"
}

variable "oracle_vm_boot_disk_size_gb" {
  description = "Boot disk size for the Oracle XE source VM."
  type        = number
  default     = 50
}

variable "oracle_vm_boot_disk_type" {
  description = "Boot disk type for the Oracle XE source VM."
  type        = string
  default     = "pd-balanced"
}

variable "oracle_vm_network" {
  description = "VPC network name for the Oracle XE source VM."
  type        = string
  default     = "default"
}

variable "oracle_docker_image" {
  description = "Oracle XE Docker image used by the source VM."
  type        = string
  default     = "gvenzl/oracle-xe:21-slim"
}

variable "oracle_port" {
  description = "Oracle listener port."
  type        = number
  default     = 1521
}

variable "oracle_host" {
  description = "Oracle host or private IP that Datastream can reach. Use the Oracle VM private IP for the production-like path."
  type        = string
  default     = ""
}

variable "oracle_service_name" {
  description = "Oracle service name."
  type        = string
  default     = "XEPDB1"
}

variable "oracle_username" {
  description = "Oracle replication username used by Datastream."
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

variable "enable_datastream_resources" {
  description = "Create Datastream private connection, connection profiles, and stream. Keep false until Oracle VM and secrets are ready."
  type        = bool
  default     = false
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
  description = "Skip Oracle connection profile validation at creation time. Keep true until the Oracle VM CDC bootstrap is verified."
  type        = bool
  default     = true
}

variable "datastream_stream_create_without_validation" {
  description = "Skip Datastream stream validation at creation time. Keep true until connection profile validation is verified."
  type        = bool
  default     = true
}

variable "datastream_data_freshness" {
  description = "Maximum freshness target for Datastream writes to BigQuery."
  type        = string
  default     = "900s"
}

variable "enable_dataflow_crm_ingestion" {
  description = "Create Dataflow Flex Template infrastructure for governed CRM CSV ingestion."
  type        = bool
  default     = false
}

variable "dataflow_worker_service_account_id" {
  description = "Service account id for Dataflow CRM ingestion workers."
  type        = string
  default     = "complete-dataflow-worker"
}

variable "dataflow_artifact_repository_id" {
  description = "Artifact Registry repository id for Dataflow Flex Template images."
  type        = string
  default     = "complete-dataflow"
}

variable "dataflow_template_bucket_name" {
  description = "Optional override for the Dataflow Flex Template spec bucket name."
  type        = string
  default     = ""
}

variable "dataflow_temp_bucket_name" {
  description = "Optional override for the Dataflow staging/temp bucket name."
  type        = string
  default     = ""
}

variable "config_bucket_name" {
  description = "Optional override for the governed config bucket name that stores schema configs."
  type        = string
  default     = ""
}

variable "enable_dataform_transform" {
  description = "Create Dataform repository, service account, transformation datasets, and IAM for governed SQL transformations."
  type        = bool
  default     = false
}

variable "dataform_repository_name" {
  description = "Dataform repository id for Complete CRM transformations."
  type        = string
  default     = "crm-complete"
}

variable "dataform_service_account_id" {
  description = "Service account id used by Dataform workflow invocations."
  type        = string
  default     = "complete-dataform-runner"
}

variable "enable_dataform_release_config" {
  description = "Create Dataform release and workflow configs. Keep false until the Dataform repository has committed SQLX code on the target branch."
  type        = bool
  default     = false
}

variable "dataform_release_git_commitish" {
  description = "Git branch, tag, or commit used by the Dataform release config after code is committed."
  type        = string
  default     = "main"
}

variable "dataform_workflow_cron_schedule" {
  description = "Optional cron schedule for the Dataform workflow config. Leave empty when Composer will trigger the workflow."
  type        = string
  default     = ""
}

variable "enable_dataplex_quality" {
  description = "Create Dataplex Lake, Zone, and DataScans for data quality checks."
  type        = bool
  default     = false
}

variable "dataplex_lake_name" {
  description = "Name of the Dataplex Lake for CRM data."
  type        = string
  default     = "crm"
}

variable "dataplex_zone_name" {
  description = "Name of the Dataplex Zone for curated data."
  type        = string
  default     = "crm-curated"
}

variable "dataplex_service_account_id" {
  description = "Service account id used by Dataplex DataScans."
  type        = string
  default     = "dataplex-quality"
}

variable "enable_ml_salesforce_push" {
  description = "Enable BigQuery ML segment scoring and Salesforce Cloud Run Job resources."
  type        = bool
  default     = false
}

variable "enable_composer_orchestration" {
  description = "Create Cloud Composer environment, DAG orchestration IAM, and dashboard audit tables."
  type        = bool
  default     = false
}

variable "composer_environment_name" {
  description = "Cloud Composer environment name for the complete CRM pipeline."
  type        = string
  default     = "complete-crm-composer"
}

variable "composer_service_account_id" {
  description = "Service account id used by Cloud Composer workers."
  type        = string
  default     = "complete-composer-worker"
}

variable "composer_image_version" {
  description = "Cloud Composer image version. Pin this in production after validation."
  type        = string
  default     = "composer-2-airflow-2"
}

variable "composer_environment_size" {
  description = "Cloud Composer environment size."
  type        = string
  default     = "ENVIRONMENT_SIZE_SMALL"
}

variable "composer_network" {
  description = "VPC network name for the Composer environment."
  type        = string
  default     = "default"
}
