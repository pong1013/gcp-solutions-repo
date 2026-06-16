"""Complete CRM nightly pipeline DAG.

This DAG is the Step 7 orchestration surface: it gives operators an Airflow UI
for task status, logs, and failed-task reruns while keeping each downstream
service responsible for its own processing.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import time
from datetime import datetime
from typing import Any

from airflow import DAG
from airflow.exceptions import AirflowSkipException
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import BranchPythonOperator, PythonOperator


PROJECT_ID = os.environ.get("COMPLETE_PROJECT_ID", "complete-498806")
REGION = os.environ.get("COMPLETE_REGION", "us-central1")
DATAFLOW_REGION = os.environ.get("DATAFLOW_REGION", "us-east1")
DATAFLOW_WORKER_ZONE = os.environ.get("DATAFLOW_WORKER_ZONE", "us-east1-b")
RAW_BUCKET = os.environ.get("CRM_RAW_BUCKET", f"{PROJECT_ID}-complete-crm-raw")
MANIFEST_BUCKET = os.environ.get(
    "CRM_MANIFEST_BUCKET", f"{PROJECT_ID}-complete-crm-manifest"
)
REJECTED_BUCKET = os.environ.get(
    "CRM_REJECTED_BUCKET", f"{PROJECT_ID}-complete-crm-rejected"
)
DATAFLOW_TEMPLATE_PATH = os.environ.get(
    "DATAFLOW_TEMPLATE_PATH",
    f"gs://{PROJECT_ID}-complete-dataflow-templates/crm-csv-ingestion/template.json",
)
DATAFLOW_TEMP_BUCKET = os.environ.get(
    "DATAFLOW_TEMP_BUCKET", f"{PROJECT_ID}-complete-dataflow-temp"
)
DATAFLOW_CONFIG_BUCKET = os.environ.get(
    "DATAFLOW_CONFIG_BUCKET", f"{PROJECT_ID}-complete-config"
)
DATAFLOW_WORKER_SA_EMAIL = os.environ.get(
    "DATAFLOW_WORKER_SA_EMAIL",
    f"complete-dataflow-worker@{PROJECT_ID}.iam.gserviceaccount.com",
)
DATAFORM_REPOSITORY = os.environ.get("DATAFORM_REPOSITORY", "crm-complete")
DATAFORM_RELEASE_COMMITISH = os.environ.get("DATAFORM_RELEASE_COMMITISH", "main")
SALESFORCE_CLOUD_RUN_JOB = os.environ.get(
    "SALESFORCE_CLOUD_RUN_JOB", "salesforce-campaign-push"
)
DEFAULT_SALESFORCE_CAMPAIGN_ID = os.environ.get(
    "SALESFORCE_CAMPAIGN_ID", "CAMP_MOCK_1"
)

REQUIRED_CRM_FILES = {
    "crm_sales": "crm_sales_{date}.csv",
    "crm_support": "crm_support_{date}.csv",
    "crm_campaign_events": "crm_campaign_events_{date}.csv",
    "crm_new_partner_leads": "crm_new_partner_leads_{date}.csv",
}


def run_date_from_context(**context: object) -> str:
    dag_run = context.get("dag_run")
    conf = getattr(dag_run, "conf", None) or {}
    return conf.get("run_date", "2026-05-26")


def conf_value(context: dict[str, Any], name: str, default: Any = None) -> Any:
    dag_run = context.get("dag_run")
    conf = getattr(dag_run, "conf", None) or {}
    return conf.get(name, default)


def redact_secret_text(value: str) -> str:
    return re.sub(r"Bearer\s+[^'\"]+", "Bearer [REDACTED]", value)


def command_string(command: list[str]) -> str:
    return redact_secret_text(" ".join(shlex.quote(part) for part in command))


def run_command(command: list[str], log_output: bool = True) -> str:
    print(f"Running command: {command_string(command)}")
    completed = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if completed.stdout and log_output:
        print(redact_secret_text(completed.stdout))
    completed.check_returncode()
    return completed.stdout


def response_name(response: str, operation: str) -> str:
    try:
        payload = json.loads(response)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"{operation} returned non-JSON response: {response}"
        ) from exc

    name = payload.get("name")
    if not name:
        raise RuntimeError(f"{operation} failed: {json.dumps(payload, indent=2)}")
    return name


def response_payload(response: str, operation: str) -> dict[str, Any]:
    try:
        payload = json.loads(response)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"{operation} returned non-JSON response: {response}"
        ) from exc

    if "error" in payload:
        raise RuntimeError(f"{operation} failed: {json.dumps(payload, indent=2)}")
    return payload


def audit_step(
    context: dict[str, Any],
    status: str,
    started_at: datetime,
    message: str | None = None,
) -> None:
    from google.cloud import bigquery

    run_date = run_date_from_context(**context)
    task_instance = context["task_instance"]
    dag_run = context["dag_run"]
    row = {
        "run_date": run_date,
        "dag_id": context["dag"].dag_id,
        "dag_run_id": dag_run.run_id,
        "task_id": task_instance.task_id,
        "try_number": task_instance.try_number,
        "status": status,
        "started_at": started_at.isoformat(),
        "ended_at": datetime.utcnow().isoformat(),
        "message": message,
    }
    errors = bigquery.Client(project=PROJECT_ID).insert_rows_json(
        f"{PROJECT_ID}.audit.pipeline_step_status", [row]
    )
    if errors:
        print(f"Failed to write pipeline_step_status audit row: {errors}")


def audited_callable(fn):
    def wrapper(**context: Any) -> Any:
        started_at = datetime.utcnow()
        try:
            result = fn(**context)
            audit_step(context, "SUCCESS", started_at)
            return result
        except AirflowSkipException as exc:
            audit_step(context, "SKIPPED", started_at, str(exc))
            raise
        except Exception as exc:
            audit_step(context, "FAILED", started_at, str(exc))
            raise

    return wrapper


@audited_callable
def validate_crm_arrival(**context: object) -> dict[str, object]:
    from google.cloud import storage

    run_date = run_date_from_context(**context)
    run_date_file = run_date.replace("-", "_")
    manifest_name = f"manifest/{run_date}/transfer_manifest.json"
    client = storage.Client(project=PROJECT_ID)

    manifest_blob = client.bucket(MANIFEST_BUCKET).blob(manifest_name)
    if not manifest_blob.exists():
        raise FileNotFoundError(
            f"Missing transfer manifest: gs://{MANIFEST_BUCKET}/{manifest_name}"
        )

    manifest = json.loads(manifest_blob.download_as_text())
    if manifest.get("status") != "SUCCESS":
        raise ValueError(
            f"Transfer manifest status is not SUCCESS: {manifest.get('status')}"
        )

    files = manifest.get("files", [])
    files_by_type = {item.get("source_type"): item for item in files}
    missing_source_types = sorted(set(REQUIRED_CRM_FILES) - set(files_by_type))
    if missing_source_types:
        raise ValueError(
            f"Manifest is missing required source types: {missing_source_types}"
        )

    raw_bucket = client.bucket(RAW_BUCKET)
    checked_files = []
    for source_type, pattern in REQUIRED_CRM_FILES.items():
        file_name = pattern.format(date=run_date_file)
        object_name = f"crm/{run_date}/{file_name}"
        blob = raw_bucket.blob(object_name)
        if not blob.exists():
            raise FileNotFoundError(f"Missing raw CRM object: gs://{RAW_BUCKET}/{object_name}")

        blob.reload()
        if not blob.size or blob.size <= 0:
            raise ValueError(f"Raw CRM object is empty: gs://{RAW_BUCKET}/{object_name}")

        checked_files.append(
            {
                "source_type": source_type,
                "object_uri": f"gs://{RAW_BUCKET}/{object_name}",
                "size_bytes": blob.size,
                "generation": str(blob.generation),
            }
        )

    return {
        "run_date": run_date,
        "manifest_uri": f"gs://{MANIFEST_BUCKET}/{manifest_name}",
        "status": "READY_FOR_DATAFLOW",
        "checked_files": checked_files,
    }


@audited_callable
def run_dataflow_ingestion(source_type: str, **context: Any) -> str:
    run_date = run_date_from_context(**context)
    job_date = run_date.replace("-", "")
    job_name = f"crm-ingest-{source_type.replace('_', '-')}-{job_date}-composer"
    command = [
        "gcloud",
        "dataflow",
        "flex-template",
        "run",
        job_name,
        f"--project={PROJECT_ID}",
        f"--region={DATAFLOW_REGION}",
        f"--worker-zone={DATAFLOW_WORKER_ZONE}",
        f"--template-file-gcs-location={DATAFLOW_TEMPLATE_PATH}",
        f"--service-account-email={DATAFLOW_WORKER_SA_EMAIL}",
        f"--staging-location=gs://{DATAFLOW_TEMP_BUCKET}/job-staging",
        f"--temp-location=gs://{DATAFLOW_TEMP_BUCKET}/job-temp",
        "--parameters="
        f"run_date={run_date},"
        f"source_type={source_type},"
        f"input_prefix=gs://{RAW_BUCKET}/crm/{run_date}/,"
        f"schema_config_path=gs://{DATAFLOW_CONFIG_BUCKET}/schemas/{source_type}.json,"
        f"output_table={PROJECT_ID}:raw.{source_type},"
        f"rejected_output_prefix=gs://{REJECTED_BUCKET}/crm/{run_date}/{source_type}/,"
        f"audit_table={PROJECT_ID}:audit.ingestion_runs",
    ]
    return run_command(command)


@audited_callable
def wait_for_oracle_datastream_freshness(**context: Any) -> str:
    run_date = run_date_from_context(**context)
    query = (
        "SELECT COUNT(*) AS row_count "
        f"FROM `{PROJECT_ID}.raw.APP_USER_RAW` "
        "WHERE DATE(updated_at) <= DATE(@run_date)"
    )
    command = [
        "bq",
        "query",
        "--use_legacy_sql=false",
        f"--project_id={PROJECT_ID}",
        "--parameter",
        f"run_date:DATE:{run_date}",
        query,
    ]
    return run_command(command)


@audited_callable
def run_dataform_workflow(**context: Any) -> str:
    token = run_command(["gcloud", "auth", "print-access-token"], log_output=False).strip()
    repo_base = (
        f"https://dataform.googleapis.com/v1beta1/projects/{PROJECT_ID}"
        f"/locations/{REGION}/repositories/{DATAFORM_REPOSITORY}"
    )
    compilation_payload = json.dumps({"gitCommitish": DATAFORM_RELEASE_COMMITISH})
    compilation_result = run_command(
        [
            "curl",
            "-s",
            "-X",
            "POST",
            "-H",
            f"Authorization: Bearer {token}",
            "-H",
            "Content-Type: application/json",
            f"{repo_base}/compilationResults",
            "-d",
            compilation_payload,
        ]
    )
    compilation_name = response_name(
        compilation_result, "Dataform compilation result creation"
    )
    invocation_payload = json.dumps(
        {
            "compilationResult": compilation_name,
            "invocationConfig": {
                "includedTags": ["daily"],
                "transitiveDependenciesIncluded": True,
            },
        }
    )
    invocation = run_command(
        [
            "curl",
            "-s",
            "-X",
            "POST",
            "-H",
            f"Authorization: Bearer {token}",
            "-H",
            "Content-Type: application/json",
            f"{repo_base}/workflowInvocations",
            "-d",
            invocation_payload,
        ]
    )
    invocation_name = response_name(invocation, "Dataform workflow invocation creation")
    print(f"Started Dataform workflow invocation: {invocation_name}")

    invocation_url = f"https://dataform.googleapis.com/v1beta1/{invocation_name}"
    timeout_seconds = int(conf_value(context, "dataform_timeout_seconds", 1800))
    poll_interval_seconds = int(conf_value(context, "dataform_poll_interval_seconds", 20))
    deadline = time.time() + timeout_seconds

    while True:
        invocation_status = run_command(
            [
                "curl",
                "-s",
                "-X",
                "GET",
                "-H",
                f"Authorization: Bearer {token}",
                "-H",
                "Content-Type: application/json",
                invocation_url,
            ]
        )
        payload = response_payload(invocation_status, "Dataform workflow invocation status")
        state = payload.get("state")
        print(f"Dataform workflow invocation state: {state}")

        if state == "SUCCEEDED":
            return invocation_name
        if state in {"FAILED", "CANCELLED"}:
            raise RuntimeError(
                "Dataform workflow invocation did not succeed: "
                f"{json.dumps(payload, indent=2)}"
            )
        if time.time() >= deadline:
            raise TimeoutError(
                f"Dataform workflow invocation did not finish within {timeout_seconds} seconds: "
                f"{invocation_name}"
            )

        time.sleep(poll_interval_seconds)


@audited_callable
def run_dataplex_scan(scan_id: str, **context: Any) -> str:
    command = [
        "gcloud",
        "dataplex",
        "datascans",
        "run",
        scan_id,
        f"--project={PROJECT_ID}",
        f"--location={REGION}",
    ]
    return run_command(command)


@audited_callable
def quality_gate(**context: Any) -> str:
    from google.cloud import bigquery

    query = f"""
    SELECT COUNT(*) AS failed_count
    FROM `{PROJECT_ID}.audit.dataplex_quality_results`
    WHERE rule_passed = FALSE
      AND job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 12 HOUR)
    """
    rows = list(bigquery.Client(project=PROJECT_ID).query(query).result())
    failed_count = rows[0]["failed_count"] if rows else 0
    if failed_count:
        raise ValueError(f"Dataplex quality gate failed: {failed_count} failed rule rows")
    return "QUALITY_GATE_PASSED"


def branch_salesforce(**context: Any) -> str:
    skip_salesforce_write = conf_value(context, "skip_salesforce_write", True)
    return "salesforce_push_skipped" if skip_salesforce_write else "salesforce_push"


@audited_callable
def run_salesforce_job(dry_run: bool, **context: Any) -> str:
    run_date = run_date_from_context(**context)
    campaign_id = conf_value(context, "salesforce_campaign_id", DEFAULT_SALESFORCE_CAMPAIGN_ID)
    limit = conf_value(context, "salesforce_limit", 50)
    create_missing_contacts = conf_value(context, "create_missing_contacts", False)
    allow_repeat = conf_value(context, "salesforce_allow_repeat", False)
    args = [
        f"--run-date={run_date}",
        f"--campaign-id={campaign_id}",
        f"--dry-run={'true' if dry_run else 'false'}",
    ]
    if limit:
        args.append(f"--limit={limit}")
    if create_missing_contacts:
        args.append("--create-missing-contacts=true")
    if allow_repeat:
        args.append("--allow-repeat=true")

    command = [
        "gcloud",
        "run",
        "jobs",
        "execute",
        SALESFORCE_CLOUD_RUN_JOB,
        f"--project={PROJECT_ID}",
        f"--region={REGION}",
        f"--args={','.join(args)}",
        "--wait",
    ]
    return run_command(command)


with DAG(
    dag_id="complete_crm_nightly_pipeline",
    description="Complete CRM governed pipeline with dashboard and task rerun.",
    start_date=datetime(2026, 5, 26),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 0},
    tags=["complete", "crm", "step7", "composer"],
) as dag:
    start = EmptyOperator(task_id="start")

    validate_arrival = PythonOperator(
        task_id="validate_crm_arrival",
        python_callable=validate_crm_arrival,
    )

    ingestion_tasks = [
        PythonOperator(
            task_id=f"ingest_{source_type}",
            python_callable=run_dataflow_ingestion,
            op_kwargs={"source_type": source_type},
        )
        for source_type in REQUIRED_CRM_FILES
    ]

    wait_oracle = PythonOperator(
        task_id="wait_for_oracle_datastream_freshness",
        python_callable=wait_for_oracle_datastream_freshness,
    )

    dataform_transform = PythonOperator(
        task_id="run_dataform_transformations",
        python_callable=run_dataform_workflow,
    )

    user_360_quality = PythonOperator(
        task_id="run_user_360_quality_scan",
        python_callable=run_dataplex_scan,
        op_kwargs={"scan_id": "user-360-quality"},
    )

    salesforce_audience_quality = PythonOperator(
        task_id="run_salesforce_audience_quality_scan",
        python_callable=run_dataplex_scan,
        op_kwargs={"scan_id": "salesforce-audience-quality"},
    )

    check_quality = PythonOperator(
        task_id="quality_gate",
        python_callable=quality_gate,
    )

    salesforce_dry_run = PythonOperator(
        task_id="salesforce_dry_run",
        python_callable=run_salesforce_job,
        op_kwargs={"dry_run": True},
    )

    branch_on_salesforce = BranchPythonOperator(
        task_id="branch_on_salesforce_write",
        python_callable=branch_salesforce,
    )

    salesforce_push = PythonOperator(
        task_id="salesforce_push",
        python_callable=run_salesforce_job,
        op_kwargs={"dry_run": False},
    )

    salesforce_push_skipped = EmptyOperator(task_id="salesforce_push_skipped")
    end = EmptyOperator(task_id="end", trigger_rule="none_failed_min_one_success")

    start >> validate_arrival >> ingestion_tasks
    validate_arrival >> wait_oracle
    ingestion_tasks >> dataform_transform
    wait_oracle >> dataform_transform
    dataform_transform >> [user_360_quality, salesforce_audience_quality]
    [user_360_quality, salesforce_audience_quality] >> check_quality
    check_quality >> salesforce_dry_run >> branch_on_salesforce
    branch_on_salesforce >> [salesforce_push, salesforce_push_skipped] >> end
