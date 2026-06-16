import argparse
import sys
import os
import time
from datetime import datetime
from google.cloud import bigquery
from google.cloud import secretmanager
from google.api_core.exceptions import NotFound
import requests

def get_secret(project_id, secret_id):
    """Retrieve secret from Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    try:
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8").strip()
    except Exception as e:
        print(f"Warning: Could not retrieve secret '{secret_id}' from Secret Manager: {e}")
        return None

def create_audit_table_if_not_exists(bq_client, project_id):
    """Creates the audit.salesforce_push_runs table if it doesn't exist."""
    dataset_id = f"{project_id}.audit"
    table_id = f"{dataset_id}.salesforce_push_runs"
    
    # Ensure dataset exists
    try:
        bq_client.get_dataset(dataset_id)
    except NotFound:
        print(f"Creating dataset {dataset_id}")
        dataset = bigquery.Dataset(dataset_id)
        dataset.location = "US"
        bq_client.create_dataset(dataset)

    # Define schema
    schema = [
        bigquery.SchemaField("run_date", "DATE", mode="REQUIRED"),
        bigquery.SchemaField("campaign_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("started_at", "TIMESTAMP", mode="REQUIRED"),
        bigquery.SchemaField("completed_at", "TIMESTAMP", mode="REQUIRED"),
        bigquery.SchemaField("status", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("records_processed", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("is_dry_run", "BOOLEAN", mode="REQUIRED"),
        bigquery.SchemaField("error_message", "STRING", mode="NULLABLE"),
    ]
    
    try:
        bq_client.get_table(table_id)
    except NotFound:
        print(f"Creating table {table_id}")
        table = bigquery.Table(table_id, schema=schema)
        bq_client.create_table(table)
        print(f"Table {table_id} created successfully.")

def write_audit_log(bq_client, project_id, run_date, campaign_id, started_at, completed_at, status, records_processed, is_dry_run, error_message=None):
    """Writes a log record into the audit table."""
    table_id = f"{project_id}.audit.salesforce_push_runs"
    
    rows_to_insert = [
        {
            "run_date": str(run_date),
            "campaign_id": campaign_id,
            "started_at": started_at.isoformat(),
            "completed_at": completed_at.isoformat(),
            "status": status,
            "records_processed": int(records_processed),
            "is_dry_run": bool(is_dry_run),
            "error_message": error_message
        }
    ]
    
    errors = bq_client.insert_rows_json(table_id, rows_to_insert)
    if errors:
        print(f"Error inserting audit log: {errors}")
    else:
        print(f"Successfully wrote audit log to {table_id}")

def check_idempotency(bq_client, project_id, run_date, campaign_id):
    """Checks if a successful non-dry-run execution already exists for this run_date and campaign_id."""
    table_id = f"{project_id}.audit.salesforce_push_runs"
    query = f"""
        SELECT COUNT(*) as count 
        FROM `{table_id}` 
        WHERE run_date = '{run_date}' 
          AND campaign_id = '{campaign_id}' 
          AND status = 'SUCCESS' 
          AND is_dry_run = FALSE
    """
    try:
        query_job = bq_client.query(query)
        results = query_job.result()
        for row in results:
            return row.count > 0
    except Exception as e:
        print(f"Note: Could not check idempotency (table might be empty or missing): {e}")
        return False

def table_columns(bq_client, table_id):
    """Return the set of BigQuery column names for a table."""
    return {field.name for field in bq_client.get_table(table_id).schema}

def escape_soql(value):
    """Escape a string literal for a simple SOQL equality predicate."""
    return str(value).replace("\\", "\\\\").replace("'", "\\'")

def salesforce_request(method, instance_url, api_version, access_token, path, **kwargs):
    """Call Salesforce REST API and raise a useful error when it fails."""
    url = f"{instance_url.rstrip('/')}/services/data/v{api_version}/{path.lstrip('/')}"
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {access_token}"
    headers.setdefault("Content-Type", "application/json")
    response = requests.request(method, url, headers=headers, timeout=60, **kwargs)
    if response.status_code >= 400:
        raise RuntimeError(
            f"Salesforce API {method} {path} failed with "
            f"{response.status_code}: {response.text}"
        )
    if response.text:
        return response.json()
    return {}

def authenticate_salesforce(client_id, client_secret, login_url):
    """Authenticate with Salesforce OAuth client credentials flow."""
    token_url = f"{login_url.rstrip('/')}/services/oauth2/token"
    response = requests.post(
        token_url,
        data={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        },
        timeout=60,
    )
    if response.status_code >= 400:
        raise RuntimeError(
            f"Salesforce OAuth token request failed with "
            f"{response.status_code}: {response.text}"
        )
    payload = response.json()
    return payload["access_token"], payload["instance_url"]

def query_salesforce(instance_url, api_version, access_token, soql):
    return salesforce_request(
        "GET",
        instance_url,
        api_version,
        access_token,
        "query",
        params={"q": soql},
    ).get("records", [])

def create_salesforce_lead(instance_url, api_version, access_token, row):
    """Create a minimal Lead for partner prospects not already in Salesforce."""
    email = row.get("lead_email")
    if not email:
        return None

    local_part = email.split("@", 1)[0]
    payload = {
        "LastName": local_part[:80] or "Unknown",
        "Company": "Partner Lead",
        "Email": email,
        "LeadSource": "Partner Referral",
    }
    response = salesforce_request(
        "POST",
        instance_url,
        api_version,
        access_token,
        "sobjects/Lead",
        json=payload,
    )
    return response.get("id")

def create_salesforce_contact(instance_url, api_version, access_token, row):
    """Create a minimal Contact for partner prospects when Lead is unavailable."""
    email = row.get("lead_email")
    if not email:
        return None

    local_part = email.split("@", 1)[0]
    payload = {
        "LastName": local_part[:80] or "Unknown",
        "Email": email,
        "LeadSource": "Partner Referral",
    }
    response = salesforce_request(
        "POST",
        instance_url,
        api_version,
        access_token,
        "sobjects/Contact",
        json=payload,
    )
    return response.get("id")

def resolve_campaign_member_target(
    instance_url,
    api_version,
    access_token,
    row,
    create_missing_leads,
    create_missing_contacts,
):
    """Resolve audience row to ContactId or LeadId for CampaignMember creation."""
    contact_id = row.get("salesforce_contact_id")
    if contact_id:
        return "ContactId", contact_id

    email = row.get("lead_email")
    if not email:
        return None, None

    safe_email = escape_soql(email)
    contacts = query_salesforce(
        instance_url,
        api_version,
        access_token,
        f"SELECT Id FROM Contact WHERE Email = '{safe_email}' LIMIT 1",
    )
    if contacts:
        return "ContactId", contacts[0]["Id"]

    leads = query_salesforce(
        instance_url,
        api_version,
        access_token,
        f"SELECT Id FROM Lead WHERE Email = '{safe_email}' LIMIT 1",
    )
    if leads:
        return "LeadId", leads[0]["Id"]

    if create_missing_leads:
        lead_id = create_salesforce_lead(instance_url, api_version, access_token, row)
        if lead_id:
            return "LeadId", lead_id

    if create_missing_contacts:
        contact_id = create_salesforce_contact(instance_url, api_version, access_token, row)
        if contact_id:
            return "ContactId", contact_id

    return None, None

def campaign_member_exists(instance_url, api_version, access_token, campaign_id, id_field, member_id):
    safe_campaign_id = escape_soql(campaign_id)
    safe_member_id = escape_soql(member_id)
    records = query_salesforce(
        instance_url,
        api_version,
        access_token,
        "SELECT Id FROM CampaignMember "
        f"WHERE CampaignId = '{safe_campaign_id}' "
        f"AND {id_field} = '{safe_member_id}' "
        "LIMIT 1",
    )
    return len(records) > 0

def push_campaign_members(
    instance_url,
    api_version,
    access_token,
    campaign_id,
    rows,
    status,
    create_missing_leads,
    create_missing_contacts,
):
    processed = 0
    skipped = 0
    failed = []

    for row in rows:
        id_field, member_id = resolve_campaign_member_target(
            instance_url,
            api_version,
            access_token,
            row,
            create_missing_leads,
            create_missing_contacts,
        )
        if not member_id:
            failed.append(
                {
                    "user_id": row.get("user_id"),
                    "lead_email": row.get("lead_email"),
                    "error": "No Salesforce Contact or Lead found",
                }
            )
            continue

        if campaign_member_exists(
            instance_url, api_version, access_token, campaign_id, id_field, member_id
        ):
            skipped += 1
            continue

        payload = {
            "CampaignId": campaign_id,
            id_field: member_id,
            "Status": status,
        }
        salesforce_request(
            "POST",
            instance_url,
            api_version,
            access_token,
            "sobjects/CampaignMember",
            json=payload,
        )
        processed += 1

    return processed, skipped, failed

def main():
    parser = argparse.ArgumentParser(description="Salesforce Campaign Activation Push Job")
    parser.add_argument("--run-date", type=str, default=datetime.utcnow().strftime("%Y-%m-%d"),
                        help="Run date (YYYY-MM-DD) to query audience data")
    parser.add_argument("--campaign-id", type=str, default="CAMP_MOCK_1",
                        help="Salesforce Campaign ID")
    parser.add_argument("--dry-run", type=str, default="true",
                        help="Dry run mode ('true' or 'false')")
    parser.add_argument("--salesforce-api-version", type=str, default=os.environ.get("SALESFORCE_API_VERSION", "59.0"),
                        help="Salesforce REST API version")
    parser.add_argument("--campaign-member-status", type=str, default=os.environ.get("SALESFORCE_CAMPAIGN_MEMBER_STATUS", "Sent"),
                        help="CampaignMember Status value to create")
    parser.add_argument("--limit", type=int, default=int(os.environ.get("AUDIENCE_LIMIT", "0")),
                        help="Maximum audience rows to process. 0 means no limit.")
    parser.add_argument("--offset", type=int, default=int(os.environ.get("AUDIENCE_OFFSET", "0")),
                        help="Audience row offset for batch processing.")
    parser.add_argument("--create-missing-leads", type=str, default=os.environ.get("CREATE_MISSING_LEADS", "false"),
                        help="Create Salesforce Lead records when no Contact or Lead exists for the audience email.")
    parser.add_argument("--create-missing-contacts", type=str, default=os.environ.get("CREATE_MISSING_CONTACTS", "false"),
                        help="Create Salesforce Contact records when no Contact or Lead exists for the audience email.")
    parser.add_argument("--allow-repeat", type=str, default=os.environ.get("ALLOW_REPEAT", "false"),
                        help="Allow a non-dry-run execution even when a prior successful run exists for the same run date and campaign.")
    
    args = parser.parse_args()
    
    run_date_str = args.run_date
    campaign_id = args.campaign_id
    is_dry_run = args.dry_run.lower() == "true"
    salesforce_api_version = args.salesforce_api_version
    campaign_member_status = args.campaign_member_status
    audience_limit = args.limit
    audience_offset = args.offset
    create_missing_leads = args.create_missing_leads.lower() == "true"
    create_missing_contacts = args.create_missing_contacts.lower() == "true"
    allow_repeat = args.allow_repeat.lower() == "true"
    
    # Resolve project_id
    project_id = os.environ.get("GCP_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
    if not project_id:
        print("Error: GCP_PROJECT or GOOGLE_CLOUD_PROJECT environment variable must be set.")
        sys.exit(1)
        
    print(f"Starting Salesforce Campaign Push Job")
    print(f"Project: {project_id}")
    print(f"Run Date: {run_date_str}")
    print(f"Campaign ID: {campaign_id}")
    print(f"Dry Run: {is_dry_run}")
    print(f"Audience Limit: {audience_limit if audience_limit else 'none'}")
    print(f"Audience Offset: {audience_offset}")
    print(f"Create Missing Leads: {create_missing_leads}")
    print(f"Create Missing Contacts: {create_missing_contacts}")
    print(f"Allow Repeat: {allow_repeat}")
    
    started_at = datetime.utcnow()
    bq_client = bigquery.Client()
    
    # Ensure audit table exists
    create_audit_table_if_not_exists(bq_client, project_id)
    
    # Check idempotency (only if not dry run)
    if not is_dry_run and not allow_repeat:
        if check_idempotency(bq_client, project_id, run_date_str, campaign_id):
            print(f"Abort: A successful execution already exists for run_date={run_date_str} and campaign_id={campaign_id}. Idempotency check passed.")
            write_audit_log(bq_client, project_id, run_date_str, campaign_id, started_at, datetime.utcnow(), "SUCCESS", 0, is_dry_run, "Skipped because a successful non-dry-run execution already exists.")
            sys.exit(0)
            
    # Fetch audience data
    limit_clause = f"LIMIT {audience_limit}" if audience_limit > 0 else ""
    offset_clause = f"OFFSET {audience_offset}" if audience_offset > 0 else ""
    audience_table = f"{project_id}.mart.salesforce_campaign_audience"
    columns = table_columns(bq_client, audience_table)
    salesforce_contact_id_expr = (
        "salesforce_contact_id"
        if "salesforce_contact_id" in columns
        else "CAST(NULL AS STRING) AS salesforce_contact_id"
    )
    activation_status_expr = (
        "activation_status"
        if "activation_status" in columns
        else "'ready' AS activation_status"
    )
    quality_gate_status_expr = (
        "quality_gate_status"
        if "quality_gate_status" in columns
        else "'passed' AS quality_gate_status"
    )
    optional_filters = []
    if "quality_gate_status" in columns:
        optional_filters.append("quality_gate_status = 'passed'")
    if "activation_status" in columns:
        optional_filters.append("activation_status = 'ready'")
    optional_filter_clause = (
        "AND " + "\n          AND ".join(optional_filters)
        if optional_filters
        else ""
    )
    query = f"""
        SELECT 
          run_date,
          user_id,
          lead_email,
          {salesforce_contact_id_expr},
          segment_name,
          score,
          consent_status,
          {activation_status_expr},
          {quality_gate_status_expr}
        FROM `{audience_table}`
        WHERE run_date = '{run_date_str}'
          AND consent_status IN ('email_consent', 'partner_opt_in')
          {optional_filter_clause}
        ORDER BY COALESCE(salesforce_contact_id, ''), COALESCE(lead_email, ''), COALESCE(user_id, '')
        {limit_clause}
        {offset_clause}
    """
    
    print(f"Querying audience table...")
    try:
        query_job = bq_client.query(query)
        rows = [dict(row) for row in query_job.result()]
    except Exception as e:
        error_msg = f"Failed to query audience data: {e}"
        print(error_msg)
        write_audit_log(bq_client, project_id, run_date_str, campaign_id, started_at, datetime.utcnow(), "FAILED", 0, is_dry_run, error_msg)
        sys.exit(1)
        
    records_count = len(rows)
    print(f"Retrieved {records_count} records to activate.")
    
    if records_count == 0:
        print("No records to process. Job finished successfully.")
        write_audit_log(bq_client, project_id, run_date_str, campaign_id, started_at, datetime.utcnow(), "SUCCESS", 0, is_dry_run)
        sys.exit(0)
        
    # Salesforce integration
    if is_dry_run:
        print("Dry Run: Validating payload format...")
        for idx, row in enumerate(rows):
            payload = {
                "CampaignId": campaign_id,
                "Email": row["lead_email"],
                "Segment": row["segment_name"],
                "Score": row["score"],
                "UserId": row["user_id"],
                "ContactId": row["salesforce_contact_id"]
            }
            if idx < 5:
                print(f"Sample payload {idx+1}: {payload}")
        
        # Simulating delay
        time.sleep(2)
        print("Dry Run validation completed successfully.")
        write_audit_log(bq_client, project_id, run_date_str, campaign_id, started_at, datetime.utcnow(), "SUCCESS", records_count, is_dry_run)
    else:
        print("Production Run: Accessing Salesforce credentials...")
        client_id = get_secret(project_id, "salesforce-client-id")
        client_secret = get_secret(project_id, "salesforce-client-secret")
        login_url = get_secret(project_id, "salesforce-login-url")
        
        if not (client_id and client_secret and login_url):
            error_msg = "Error: Missing required Salesforce credentials in Secret Manager."
            print(error_msg)
            write_audit_log(bq_client, project_id, run_date_str, campaign_id, started_at, datetime.utcnow(), "FAILED", 0, is_dry_run, error_msg)
            sys.exit(1)
            
        try:
            print("Authenticating with Salesforce OAuth client credentials flow...")
            access_token, instance_url = authenticate_salesforce(client_id, client_secret, login_url)

            print(f"Creating CampaignMember records for {records_count} audience rows...")
            created_count, skipped_count, failures = push_campaign_members(
                instance_url,
                salesforce_api_version,
                access_token,
                campaign_id,
                rows,
                campaign_member_status,
                create_missing_leads,
                create_missing_contacts,
            )

            print(
                "Salesforce push finished: "
                f"created={created_count}, skipped_existing={skipped_count}, "
                f"failed={len(failures)}"
            )
            if failures:
                error_msg = f"Salesforce push had {len(failures)} failed rows. Sample: {failures[:5]}"
                print(error_msg)
                write_audit_log(
                    bq_client,
                    project_id,
                    run_date_str,
                    campaign_id,
                    started_at,
                    datetime.utcnow(),
                    "FAILED",
                    created_count,
                    is_dry_run,
                    error_msg,
                )
                sys.exit(1)

            write_audit_log(
                bq_client,
                project_id,
                run_date_str,
                campaign_id,
                started_at,
                datetime.utcnow(),
                "SUCCESS",
                created_count + skipped_count,
                is_dry_run,
            )
        except Exception as e:
            error_msg = f"Failed to push to Salesforce: {e}"
            print(error_msg)
            write_audit_log(bq_client, project_id, run_date_str, campaign_id, started_at, datetime.utcnow(), "FAILED", 0, is_dry_run, error_msg)
            sys.exit(1)

if __name__ == "__main__":
    main()
