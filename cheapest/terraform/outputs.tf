output "crm_lake_bucket_name" {
  description = "Single low-cost CRM lake bucket used by the cheapest solution."
  value       = google_storage_bucket.crm_lake.name
}

output "crm_lake_bucket_url" {
  description = "GCS URL for the CRM lake bucket."
  value       = google_storage_bucket.crm_lake.url
}

output "crm_lake_prefixes" {
  description = "Standard object prefixes used by the cheapest CRM pipeline."
  value = {
    raw      = "raw/crm/<run_date>/"
    archive  = "archive/crm/<run_date>/"
    rejected = "rejected/crm/<run_date>/"
  }
}

output "oracle_secret_ids" {
  description = "Oracle Secret Manager containers created by Terraform. Values are added outside Terraform."
  value       = sort(tolist(local.oracle_secret_ids))
}

output "bigquery_dataset_ids" {
  description = "BigQuery datasets created by Terraform."
  value = {
    for key, dataset in google_bigquery_dataset.crm : key => "${var.project_id}.${dataset.dataset_id}"
  }
}

output "datastream_connection_profiles" {
  description = "Datastream connection profile resource names."
  value = {
    oracle_source        = google_datastream_connection_profile.oracle_source.id
    bigquery_destination = google_datastream_connection_profile.bigquery_destination.id
  }
}

output "datastream_private_connection" {
  description = "Datastream private connection resource name."
  value       = google_datastream_private_connection.default_vpc.id
}

output "datastream_stream_name" {
  description = "Datastream stream resource name."
  value       = google_datastream_stream.oracle_user_raw_to_bigquery.id
}

output "workflow_name" {
  description = "Nightly CRM Workflow resource name."
  value       = google_workflows_workflow.nightly_crm_pipeline.id
}

output "scheduler_job_name" {
  description = "Nightly CRM Scheduler job resource name."
  value       = google_cloud_scheduler_job.nightly_crm_pipeline.id
}

output "orchestration_service_accounts" {
  description = "Service accounts used by Step 3 orchestration."
  value = {
    workflow  = google_service_account.workflow.email
    scheduler = google_service_account.scheduler.email
  }
}

output "salesforce_secret_ids" {
  description = "Salesforce Secret Manager containers created by Terraform. Values are added outside Terraform."
  value       = sort(tolist(local.salesforce_secret_ids))
}

output "artifact_registry_jobs_repository" {
  description = "Artifact Registry Docker repository for cheapest job images."
  value       = google_artifact_registry_repository.jobs.name
}

output "salesforce_job_service_account" {
  description = "Service account used by the Salesforce Cloud Run Job."
  value       = google_service_account.salesforce_job.email
}

output "salesforce_cloud_run_job_name" {
  description = "Cloud Run Job name when enable_salesforce_cloud_run_job is true."
  value       = var.enable_salesforce_cloud_run_job ? google_cloud_run_v2_job.salesforce_campaign_push[0].name : null
}
