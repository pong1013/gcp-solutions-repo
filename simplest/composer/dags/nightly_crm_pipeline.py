from __future__ import annotations

from datetime import datetime, timedelta
import json
import os
from pathlib import Path
import time

from airflow import DAG
from airflow.operators.python import PythonOperator


CRM_RUN_DATE = "2026-05-26"
CRM_FILE_NAMES = [
    "crm_sales_2026_05_26.csv",
    "crm_support_2026_05_26.csv",
    "crm_campaign_events_2026_05_26.csv",
    "crm_new_partner_leads_2026_05_26.csv",
]
RAW_TABLES_TO_VALIDATE = [
    "user_raw",
    "crm_sales",
    "crm_support",
    "crm_campaign_events",
    "crm_new_partner_leads",
]
DATA_FUSION_NAMESPACE = "default"
DATA_FUSION_WORKFLOW = "DataPipelineWorkflow"
DATA_FUSION_POLL_SECONDS = 30
DATA_FUSION_TIMEOUT_SECONDS = 7200
DATA_FUSION_RUN_DISCOVERY_SECONDS = 120
VALIDATE_CRM_QUALITY_SQL = "validate_crm_quality.sql"
WRITE_CRM_REJECTED_RECORDS_SQL = "write_crm_rejected_records.sql"
REJECTED_RECORDS_TABLE = "simplest-497710.raw.crm_rejected_records"


DEFAULT_ARGS = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "retries": 0,
}


def check_required_crm_files() -> None:
    from google.cloud import storage

    bucket_name = os.environ.get("RAW_BUCKET", "simplest-497710-raw-crm")
    prefix = f"crm/{CRM_RUN_DATE}"
    client = storage.Client()
    bucket = client.bucket(bucket_name)

    missing_files = []
    for file_name in CRM_FILE_NAMES:
        object_name = f"{prefix}/{file_name}"
        if not bucket.blob(object_name).exists(client):
            missing_files.append(f"gs://{bucket_name}/{object_name}")

    if missing_files:
        missing_list = "\n".join(missing_files)
        raise FileNotFoundError(f"Missing CRM source files:\n{missing_list}")

    found_files = [f"gs://{bucket_name}/{prefix}/{file_name}" for file_name in CRM_FILE_NAMES]
    print("All required CRM files exist:")
    for found_file in found_files:
        print(found_file)


def get_datafusion_api_endpoint(session) -> str:
    project_id = os.environ.get("GCP_PROJECT_ID", "simplest-497710")
    region = os.environ.get("GCP_REGION", "us-central1")
    instance = os.environ.get("DATA_FUSION_INSTANCE", "crm-simplest-datafusion")
    instance_url = (
        "https://datafusion.googleapis.com/v1/"
        f"projects/{project_id}/locations/{region}/instances/{instance}"
    )

    response = session.get(instance_url, timeout=60)
    response.raise_for_status()
    instance_config = response.json()
    endpoint = instance_config.get("apiEndpoint")
    if not endpoint:
        raise RuntimeError(f"Data Fusion instance response has no apiEndpoint: {instance_config}")
    return endpoint.rstrip("/")


def extract_datafusion_run_id(response) -> str | None:
    if not response.text:
        return None

    try:
        payload = response.json()
    except ValueError:
        return response.text.strip().strip('"')

    if isinstance(payload, str):
        return payload
    if isinstance(payload, dict):
        for key in ("runid", "runId", "id"):
            if payload.get(key):
                return payload[key]

    raise RuntimeError(f"Could not parse Data Fusion run id from response: {payload}")


def run_datafusion_pipeline(pipeline_name: str) -> None:
    import google.auth
    from google.auth.transport.requests import AuthorizedSession

    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    session = AuthorizedSession(credentials)
    endpoint = get_datafusion_api_endpoint(session)

    workflow_base_url = (
        f"{endpoint}/v3/namespaces/{DATA_FUSION_NAMESPACE}/apps/{pipeline_name}/"
        f"workflows/{DATA_FUSION_WORKFLOW}"
    )

    existing_run_ids = list_datafusion_run_ids(session, workflow_base_url)
    print(f"Starting Data Fusion pipeline: {pipeline_name}")
    start_response = session.post(f"{workflow_base_url}/start", timeout=60)
    start_response.raise_for_status()
    run_id = extract_datafusion_run_id(start_response)
    if not run_id:
        print("Data Fusion start response did not include a run id. Looking up the new run.")
        run_id = wait_for_new_datafusion_run(session, workflow_base_url, existing_run_ids, pipeline_name)
    print(f"Started Data Fusion pipeline {pipeline_name}, run id: {run_id}")

    deadline = time.monotonic() + DATA_FUSION_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        run_response = session.get(f"{workflow_base_url}/runs/{run_id}", timeout=60)
        run_response.raise_for_status()
        run_status = run_response.json().get("status")
        print(f"Data Fusion pipeline {pipeline_name} run {run_id} status: {run_status}")

        if run_status == "COMPLETED":
            return
        if run_status in {"FAILED", "KILLED", "REJECTED"}:
            raise RuntimeError(
                f"Data Fusion pipeline {pipeline_name} run {run_id} ended with status {run_status}."
            )

        time.sleep(DATA_FUSION_POLL_SECONDS)

    raise TimeoutError(
        f"Timed out after {DATA_FUSION_TIMEOUT_SECONDS} seconds waiting for "
        f"Data Fusion pipeline {pipeline_name}."
    )


def extract_run_id_from_run(run: dict) -> str | None:
    for key in ("runid", "runId", "id"):
        if run.get(key):
            return run[key]
    return None


def list_datafusion_runs(session, workflow_base_url: str) -> list[dict]:
    response = session.get(f"{workflow_base_url}/runs?limit=20", timeout=60)
    response.raise_for_status()
    runs = response.json()
    if not isinstance(runs, list):
        raise RuntimeError(f"Unexpected Data Fusion runs response: {runs}")
    return runs


def list_datafusion_run_ids(session, workflow_base_url: str) -> set[str]:
    return {
        run_id
        for run_id in (extract_run_id_from_run(run) for run in list_datafusion_runs(session, workflow_base_url))
        if run_id
    }


def wait_for_new_datafusion_run(
    session,
    workflow_base_url: str,
    existing_run_ids: set[str],
    pipeline_name: str,
) -> str:
    deadline = time.monotonic() + DATA_FUSION_RUN_DISCOVERY_SECONDS
    while time.monotonic() < deadline:
        runs = list_datafusion_runs(session, workflow_base_url)
        for run in runs:
            run_id = extract_run_id_from_run(run)
            if run_id and run_id not in existing_run_ids:
                return run_id
        time.sleep(5)

    raise RuntimeError(
        f"Data Fusion accepted start request for {pipeline_name}, but no new run appeared "
        f"within {DATA_FUSION_RUN_DISCOVERY_SECONDS} seconds."
    )


def validate_raw_table_counts() -> None:
    from google.cloud import bigquery

    project_id = os.environ.get("GCP_PROJECT_ID", "simplest-497710")
    raw_dataset = os.environ.get("BIGQUERY_RAW_DATASET", "raw")
    client = bigquery.Client(project=project_id)

    table_queries = []
    for table_name in RAW_TABLES_TO_VALIDATE:
        table_queries.append(
            f"""
            SELECT
              '{raw_dataset}.{table_name}' AS table_name,
              COUNT(*) AS row_count
            FROM `{project_id}.{raw_dataset}.{table_name}`
            """
        )

    query = "\nUNION ALL\n".join(table_queries)
    rows = list(client.query(query).result())
    empty_tables = []

    print("Raw table row counts:")
    for row in rows:
        print(f"{row.table_name}: {row.row_count}")
        if row.row_count <= 0:
            empty_tables.append(row.table_name)

    if empty_tables:
        raise RuntimeError(f"Raw validation failed. Empty tables: {', '.join(empty_tables)}")


def read_sql_file(file_name: str) -> str:
    dag_dir = Path(__file__).resolve().parent
    candidate_paths = [
        dag_dir / "sql" / file_name,
        dag_dir.parents[1] / "sql" / file_name,
    ]

    for candidate_path in candidate_paths:
        if candidate_path.exists():
            return candidate_path.read_text(encoding="utf-8")

    searched_paths = "\n".join(str(path) for path in candidate_paths)
    raise FileNotFoundError(f"Could not find SQL file {file_name}. Searched:\n{searched_paths}")


def publish_data_quality_failure_alert(context: dict) -> None:
    from google.cloud import pubsub_v1

    project_id = os.environ.get("GCP_PROJECT_ID", "simplest-497710")
    topic_name = os.environ.get("DQ_ALERT_TOPIC", "crm-data-quality-alerts")
    topic_path = topic_name if topic_name.startswith("projects/") else f"projects/{project_id}/topics/{topic_name}"

    task_instance = context.get("task_instance")
    dag_run = context.get("dag_run")
    logical_date = context.get("logical_date") or context.get("execution_date")
    exception = context.get("exception")

    payload = {
        "pipeline_name": getattr(task_instance, "dag_id", "nightly_crm_pipeline"),
        "task_id": getattr(task_instance, "task_id", "validate_data_quality"),
        "run_date": str(logical_date.date()) if logical_date else CRM_RUN_DATE,
        "run_id": getattr(dag_run, "run_id", None),
        "severity": "ERROR",
        "exception": str(exception) if exception else None,
        "rejected_table": REJECTED_RECORDS_TABLE,
        "airflow_log_url": getattr(task_instance, "log_url", None),
        "runbook": "gcp-solutions-repo/simplest/docs/step6-data-quality-notification.md",
    }

    publisher = pubsub_v1.PublisherClient()
    future = publisher.publish(
        topic_path,
        json.dumps(payload, sort_keys=True).encode("utf-8"),
        pipeline=payload["pipeline_name"],
        task_id=payload["task_id"],
        severity=payload["severity"],
    )
    message_id = future.result(timeout=30)
    print(f"Published data quality failure alert to {topic_path}, message_id={message_id}")


def validate_data_quality() -> None:
    from google.cloud import bigquery

    project_id = os.environ.get("GCP_PROJECT_ID", "simplest-497710")
    client = bigquery.Client(project=project_id)

    write_rejected_sql = read_sql_file(WRITE_CRM_REJECTED_RECORDS_SQL)
    validate_quality_sql = read_sql_file(VALIDATE_CRM_QUALITY_SQL)

    print(f"Writing rejected evidence with {WRITE_CRM_REJECTED_RECORDS_SQL}.")
    client.query(write_rejected_sql).result()
    print("Rejected evidence write completed.")

    print(f"Running data quality rules with {VALIDATE_CRM_QUALITY_SQL}.")
    rows = list(client.query(validate_quality_sql).result())

    failing_error_rules = []
    warning_rules = []

    print("Data quality rule results:")
    for row in rows:
        print(
            f"{row.rule_id} | {row.severity} | {row.source_table} | "
            f"failed_row_count={row.failed_row_count} | {row.sample_error}"
        )
        if row.failed_row_count > 0 and row.severity == "ERROR":
            failing_error_rules.append(row)
        elif row.failed_row_count > 0 and row.severity == "WARNING":
            warning_rules.append(row)

    if warning_rules:
        print("Data quality warnings:")
        for row in warning_rules:
            print(f"{row.rule_id}: {row.failed_row_count} rows. {row.sample_error}")

    if failing_error_rules:
        print("Rejected evidence table: simplest-497710.raw.crm_rejected_records")
        print("Failing data quality rules:")
        for row in failing_error_rules:
            print(f"{row.rule_id}: {row.failed_row_count} rows. {row.sample_error}")
        failing_rule_ids = ", ".join(row.rule_id for row in failing_error_rules)
        raise RuntimeError(f"Data quality validation failed. Failing ERROR rules: {failing_rule_ids}")

    print("Data quality validation passed. No ERROR rules failed.")


def archive_crm_source_files() -> None:
    from google.cloud import storage

    raw_bucket_name = os.environ.get("RAW_BUCKET", "simplest-497710-raw-crm")
    archive_bucket_name = os.environ.get("ARCHIVE_BUCKET", "simplest-497710-archive-crm")
    prefix = f"crm/{CRM_RUN_DATE}"
    client = storage.Client()
    raw_bucket = client.bucket(raw_bucket_name)
    archive_bucket = client.bucket(archive_bucket_name)

    archived_files = []
    missing_files = []
    for file_name in CRM_FILE_NAMES:
        object_name = f"{prefix}/{file_name}"
        raw_blob = raw_bucket.blob(object_name)
        if not raw_blob.exists(client):
            missing_files.append(f"gs://{raw_bucket_name}/{object_name}")
            continue

        raw_bucket.copy_blob(raw_blob, archive_bucket, object_name)
        raw_blob.delete()
        archived_files.append(f"gs://{archive_bucket_name}/{object_name}")

    if missing_files:
        missing_list = "\n".join(missing_files)
        raise FileNotFoundError(f"Cannot archive missing CRM source files:\n{missing_list}")

    print("Archived CRM source files:")
    for archived_file in archived_files:
        print(archived_file)


with DAG(
    dag_id="nightly_crm_pipeline",
    description="Orchestrates nightly CRM CSV and Oracle ingestion for the simplest GCP solution.",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2026, 5, 26),
    schedule_interval=None,
    catchup=False,
    max_active_runs=1,
    tags=["crm", "simplest", "lab"],
) as dag:
    check_crm_files = PythonOperator(
        task_id="check_crm_files",
        python_callable=check_required_crm_files,
    )

    run_oracle_user_raw_pipeline = PythonOperator(
        task_id="run_oracle_user_raw_pipeline",
        python_callable=run_datafusion_pipeline,
        op_kwargs={"pipeline_name": "user_raw_pipeline"},
        retries=0,
    )

    run_crm_sales_pipeline = PythonOperator(
        task_id="run_crm_sales_pipeline",
        python_callable=run_datafusion_pipeline,
        op_kwargs={"pipeline_name": "crm_sales_to_bigquery"},
        retries=0,
    )

    run_crm_support_pipeline = PythonOperator(
        task_id="run_crm_support_pipeline",
        python_callable=run_datafusion_pipeline,
        op_kwargs={"pipeline_name": "crm_support_to_bigquery"},
        retries=0,
    )

    run_crm_campaign_events_pipeline = PythonOperator(
        task_id="run_crm_campaign_events_pipeline",
        python_callable=run_datafusion_pipeline,
        op_kwargs={"pipeline_name": "crm_campaign_events_to_bigquery"},
        retries=0,
    )

    run_crm_partner_leads_pipeline = PythonOperator(
        task_id="run_crm_partner_leads_pipeline",
        python_callable=run_datafusion_pipeline,
        op_kwargs={"pipeline_name": "crm_partner_leads_to_bigquery"},
        retries=0,
    )

    validate_raw_counts = PythonOperator(
        task_id="validate_raw_counts",
        python_callable=validate_raw_table_counts,
    )

    validate_data_quality_task = PythonOperator(
        task_id="validate_data_quality",
        python_callable=validate_data_quality,
        on_failure_callback=publish_data_quality_failure_alert,
    )

    archive_source_files = PythonOperator(
        task_id="archive_source_files",
        python_callable=archive_crm_source_files,
    )

    (
        check_crm_files
        >> run_oracle_user_raw_pipeline
        >> run_crm_sales_pipeline
        >> run_crm_support_pipeline
        >> run_crm_campaign_events_pipeline
        >> run_crm_partner_leads_pipeline
        >> validate_raw_counts
        >> validate_data_quality_task
        >> archive_source_files
    )
