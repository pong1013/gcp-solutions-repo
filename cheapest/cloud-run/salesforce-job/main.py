import datetime as dt
import json
import os
import sys
import uuid
from typing import Optional

import requests
from google.cloud import bigquery


STEP_NAME = "push_salesforce"


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "t", "yes", "y"}


def get_salesforce_token(instance_url: str, client_id: str, client_secret: str) -> dict:
    response = requests.post(
        f"{instance_url.rstrip('/')}/services/oauth2/token",
        data={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        },
        timeout=30,
    )
    if response.status_code >= 400:
        raise RuntimeError(
            "Salesforce OAuth failed: "
            f"status={response.status_code}, body={response.text[:500]}"
        )
    return response.json()


def query_audience_count(
    client: bigquery.Client, project_id: str, dataset: str, table: str
) -> int:
    table_id = f"{project_id}.{dataset}.{table}"
    query = f"SELECT COUNT(*) AS row_count FROM `{table_id}`"
    rows = list(client.query(query).result())
    return int(rows[0]["row_count"])


def insert_audit_row(
    client: bigquery.Client,
    project_id: str,
    run_date: str,
    execution_id: str,
    status: str,
    started_at: dt.datetime,
    error_message: Optional[str] = None,
) -> None:
    query = f"""
    INSERT INTO `{project_id}.audit.pipeline_step_status`
      (run_date, execution_id, step_name, status, started_at, finished_at, error_message, rerun_of_execution_id)
    VALUES
      (@run_date, @execution_id, @step_name, @status, @started_at, @finished_at, @error_message, NULL)
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("run_date", "DATE", run_date),
            bigquery.ScalarQueryParameter("execution_id", "STRING", execution_id),
            bigquery.ScalarQueryParameter("step_name", "STRING", STEP_NAME),
            bigquery.ScalarQueryParameter("status", "STRING", status),
            bigquery.ScalarQueryParameter("started_at", "TIMESTAMP", started_at),
            bigquery.ScalarQueryParameter("finished_at", "TIMESTAMP", dt.datetime.now(dt.UTC)),
            bigquery.ScalarQueryParameter("error_message", "STRING", error_message),
        ]
    )
    client.query(query, job_config=job_config).result()


def main() -> int:
    started_at = dt.datetime.now(dt.UTC)
    execution_id = os.environ.get("CLOUD_RUN_EXECUTION", str(uuid.uuid4()))
    run_date = os.environ.get("RUN_DATE", dt.date.today().isoformat())

    project_id = require_env("PROJECT_ID")
    bq_dataset = os.environ.get("BQ_DATASET", "mart")
    bq_table = os.environ.get("BQ_TABLE", "salesforce_campaign_audience")
    dry_run = env_bool("SALESFORCE_DRY_RUN", True)

    bq_client = bigquery.Client(project=project_id)

    try:
        client_id = require_env("SALESFORCE_CLIENT_ID")
        client_secret = require_env("SALESFORCE_CLIENT_SECRET")
        instance_url = require_env("SALESFORCE_INSTANCE_URL")

        token = get_salesforce_token(instance_url, client_id, client_secret)
        audience_count = query_audience_count(bq_client, project_id, bq_dataset, bq_table)

        summary = {
            "execution_id": execution_id,
            "run_date": run_date,
            "step_name": STEP_NAME,
            "dry_run": dry_run,
            "salesforce_instance_url": token.get("instance_url"),
            "audience_table": f"{project_id}.{bq_dataset}.{bq_table}",
            "audience_count": audience_count,
        }
        print(json.dumps(summary, sort_keys=True))

        if not dry_run:
            raise RuntimeError(
                "SALESFORCE_DRY_RUN=false is not implemented yet. "
                "Add CampaignMember upsert mapping before enabling writes."
            )

        insert_audit_row(
            bq_client,
            project_id,
            run_date,
            execution_id,
            "SUCCESS",
            started_at,
        )
        return 0
    except Exception as exc:
        error_message = str(exc)
        print(json.dumps({"error": error_message, "step_name": STEP_NAME}), file=sys.stderr)
        try:
            insert_audit_row(
                bq_client,
                project_id,
                run_date,
                execution_id,
                "FAILED",
                started_at,
                error_message,
            )
        except Exception as audit_exc:
            print(
                json.dumps({"audit_error": str(audit_exc), "step_name": STEP_NAME}),
                file=sys.stderr,
            )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
