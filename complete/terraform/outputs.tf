output "crm_bucket_names" {
  description = "Complete CRM bucket names by purpose."
  value = {
    for purpose, bucket in google_storage_bucket.crm : purpose => bucket.name
  }
}

output "crm_bucket_urls" {
  description = "Complete CRM bucket URLs by purpose."
  value = {
    for purpose, bucket in google_storage_bucket.crm : purpose => bucket.url
  }
}

output "crm_transfer_agent_pool_name" {
  description = "Storage Transfer Service agent pool name when enabled."
  value       = var.enable_storage_transfer_job ? google_storage_transfer_agent_pool.crm_onprem[0].name : null
}

output "crm_transfer_job_name" {
  description = "Storage Transfer Service nightly CRM transfer job name when enabled."
  value       = var.enable_storage_transfer_job ? google_storage_transfer_job.crm_nightly_posix_to_gcs[0].name : null
}

output "oracle_secret_ids" {
  description = "Oracle Secret Manager container ids. Values are written later with gcloud secrets versions add."
  value       = sort(keys(google_secret_manager_secret.oracle))
}

output "bigquery_raw_dataset" {
  description = "BigQuery raw dataset used by Datastream and governed ingestion."
  value       = google_bigquery_dataset.raw.dataset_id
}

output "oracle_source_vm_private_ip" {
  description = "Private IP of the production-like Oracle XE source VM when enabled."
  value       = var.enable_oracle_source_vm ? google_compute_instance.oracle_source[0].network_interface[0].network_ip : null
}

output "oracle_source_vm_name" {
  description = "Name of the production-like Oracle XE source VM when enabled."
  value       = var.enable_oracle_source_vm ? google_compute_instance.oracle_source[0].name : null
}

output "datastream_private_connection" {
  description = "Datastream private connection resource name when enabled."
  value       = var.enable_datastream_resources ? google_datastream_private_connection.default_vpc[0].id : null
}

output "datastream_connection_profiles" {
  description = "Datastream connection profile resource names when enabled."
  value = var.enable_datastream_resources ? {
    oracle_source        = google_datastream_connection_profile.oracle_source[0].id
    bigquery_destination = google_datastream_connection_profile.bigquery_destination[0].id
  } : null
}

output "datastream_stream_name" {
  description = "Datastream stream resource name when enabled."
  value       = var.enable_datastream_resources ? google_datastream_stream.oracle_user_raw_to_bigquery[0].id : null
}

output "dataflow_worker_service_account_email" {
  description = "Dataflow worker service account email when CRM ingestion is enabled."
  value       = var.enable_dataflow_crm_ingestion ? google_service_account.dataflow_worker[0].email : null
}

output "dataflow_template_bucket_url" {
  description = "GCS bucket URL for Dataflow Flex Template specs when CRM ingestion is enabled."
  value       = var.enable_dataflow_crm_ingestion ? google_storage_bucket.dataflow_templates[0].url : null
}

output "dataflow_temp_bucket_url" {
  description = "GCS bucket URL for Dataflow staging/temp files when CRM ingestion is enabled."
  value       = var.enable_dataflow_crm_ingestion ? google_storage_bucket.dataflow_temp[0].url : null
}

output "config_bucket_url" {
  description = "GCS bucket URL for governed schema configs when CRM ingestion is enabled."
  value       = var.enable_dataflow_crm_ingestion ? google_storage_bucket.config[0].url : null
}

output "dataflow_artifact_registry_repository" {
  description = "Artifact Registry repository id for Dataflow Flex Template images when enabled."
  value       = var.enable_dataflow_crm_ingestion ? google_artifact_registry_repository.dataflow_templates[0].id : null
}

output "dataform_repository_name" {
  description = "Dataform repository name when transformation resources are enabled."
  value       = var.enable_dataform_transform ? google_dataform_repository.crm[0].name : null
}

output "dataform_runner_service_account_email" {
  description = "Service account email used by Dataform workflow invocations."
  value       = var.enable_dataform_transform ? google_service_account.dataform_runner[0].email : null
}

output "dataform_output_datasets" {
  description = "BigQuery datasets created for Dataform outputs."
  value       = var.enable_dataform_transform ? sort([for dataset in google_bigquery_dataset.dataform_output : dataset.dataset_id]) : []
}

output "dataplex_lake_name" {
  description = "Dataplex Lake name when quality resources are enabled."
  value       = var.enable_dataplex_quality ? google_dataplex_lake.crm[0].name : null
}

output "dataplex_zone_name" {
  description = "Dataplex Zone name when quality resources are enabled."
  value       = var.enable_dataplex_quality ? google_dataplex_zone.curated[0].name : null
}

output "dataplex_quality_service_account_email" {
  description = "Service account email used by Dataplex DataScans."
  value       = var.enable_dataplex_quality ? google_service_account.dataplex_quality[0].email : null
}

output "dataplex_quality_alerts_topic" {
  description = "Pub/Sub topic for Dataplex quality alerts."
  value       = var.enable_dataplex_quality ? google_pubsub_topic.quality_alerts[0].id : null
}

output "salesforce_job_artifact_registry_repository" {
  description = "Artifact Registry repository for Salesforce job images."
  value       = var.enable_ml_salesforce_push ? google_artifact_registry_repository.jobs[0].id : null
}

output "salesforce_cloud_run_job_name" {
  description = "Name of the Salesforce campaign push Cloud Run Job."
  value       = var.enable_ml_salesforce_push ? google_cloud_run_v2_job.salesforce_campaign_push[0].name : null
}

output "salesforce_job_service_account_email" {
  description = "Service account email used by the Salesforce Cloud Run Job."
  value       = var.enable_ml_salesforce_push ? google_service_account.salesforce_job[0].email : null
}

output "composer_environment_name" {
  description = "Cloud Composer environment name when orchestration is enabled."
  value       = var.enable_composer_orchestration ? google_composer_environment.complete[0].name : null
}

output "composer_service_account_email" {
  description = "Service account email used by Composer workers."
  value       = var.enable_composer_orchestration ? google_service_account.composer[0].email : null
}

output "composer_dag_gcs_prefix" {
  description = "Composer DAG GCS prefix for manual DAG import checks."
  value       = var.enable_composer_orchestration ? google_composer_environment.complete[0].config[0].dag_gcs_prefix : null
}

output "composer_airflow_uri" {
  description = "Airflow web UI URI for the Composer environment."
  value       = var.enable_composer_orchestration ? google_composer_environment.complete[0].config[0].airflow_uri : null
}
