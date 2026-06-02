DECLARE v_run_date DATE DEFAULT DATE '2026-05-26';
DECLARE v_dag_id STRING DEFAULT 'nightly_crm_pipeline';
DECLARE v_task_id STRING DEFAULT 'validate_data_quality';
DECLARE v_evidence_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

DELETE FROM `simplest-497710.raw.crm_rejected_records`
WHERE run_date = v_run_date
  AND dag_id = v_dag_id
  AND task_id = v_task_id;

INSERT INTO `simplest-497710.raw.crm_rejected_records` (
  run_date,
  dag_id,
  task_id,
  rule_id,
  source_table,
  source_key,
  error_reason,
  record_json,
  created_at
)
WITH rejected_rows AS (
  SELECT
    'user_raw_user_id_required' AS rule_id,
    'raw.user_raw' AS source_table,
    TO_HEX(SHA256(TO_JSON_STRING(users))) AS source_key,
    'raw.user_raw.USER_ID is required' AS error_reason,
    TO_JSON_STRING(users) AS record_json
  FROM `simplest-497710.raw.user_raw` users
  WHERE USER_ID IS NULL
    OR TRIM(CAST(USER_ID AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_sales_user_id_required' AS rule_id,
    'raw.crm_sales' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(deal_id AS STRING)), ''),
      NULLIF(TRIM(CAST(customer_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(sales)))
    ) AS source_key,
    'raw.crm_sales.user_id is required' AS error_reason,
    TO_JSON_STRING(sales) AS record_json
  FROM `simplest-497710.raw.crm_sales` sales
  WHERE user_id IS NULL
    OR TRIM(CAST(user_id AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_sales_deal_id_required' AS rule_id,
    'raw.crm_sales' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(customer_id AS STRING)), ''),
      NULLIF(TRIM(CAST(user_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(sales)))
    ) AS source_key,
    'raw.crm_sales.deal_id is required' AS error_reason,
    TO_JSON_STRING(sales) AS record_json
  FROM `simplest-497710.raw.crm_sales` sales
  WHERE deal_id IS NULL
    OR TRIM(CAST(deal_id AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_support_user_id_required' AS rule_id,
    'raw.crm_support' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(ticket_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(support)))
    ) AS source_key,
    'raw.crm_support.user_id is required' AS error_reason,
    TO_JSON_STRING(support) AS record_json
  FROM `simplest-497710.raw.crm_support` support
  WHERE user_id IS NULL
    OR TRIM(CAST(user_id AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_support_ticket_id_required' AS rule_id,
    'raw.crm_support' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(user_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(support)))
    ) AS source_key,
    'raw.crm_support.ticket_id is required' AS error_reason,
    TO_JSON_STRING(support) AS record_json
  FROM `simplest-497710.raw.crm_support` support
  WHERE ticket_id IS NULL
    OR TRIM(CAST(ticket_id AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_campaign_user_id_required' AS rule_id,
    'raw.crm_campaign_events' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(event_id AS STRING)), ''),
      NULLIF(TRIM(CAST(campaign_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(events)))
    ) AS source_key,
    'raw.crm_campaign_events.user_id is required' AS error_reason,
    TO_JSON_STRING(events) AS record_json
  FROM `simplest-497710.raw.crm_campaign_events` events
  WHERE user_id IS NULL
    OR TRIM(CAST(user_id AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_campaign_event_id_required' AS rule_id,
    'raw.crm_campaign_events' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(campaign_id AS STRING)), ''),
      NULLIF(TRIM(CAST(user_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(events)))
    ) AS source_key,
    'raw.crm_campaign_events.event_id is required' AS error_reason,
    TO_JSON_STRING(events) AS record_json
  FROM `simplest-497710.raw.crm_campaign_events` events
  WHERE event_id IS NULL
    OR TRIM(CAST(event_id AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_partner_lead_id_required' AS rule_id,
    'raw.crm_new_partner_leads' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(email AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(leads)))
    ) AS source_key,
    'raw.crm_new_partner_leads.external_lead_id is required' AS error_reason,
    TO_JSON_STRING(leads) AS record_json
  FROM `simplest-497710.raw.crm_new_partner_leads` leads
  WHERE external_lead_id IS NULL
    OR TRIM(CAST(external_lead_id AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_partner_email_required' AS rule_id,
    'raw.crm_new_partner_leads' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(external_lead_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(leads)))
    ) AS source_key,
    'raw.crm_new_partner_leads.email is required' AS error_reason,
    TO_JSON_STRING(leads) AS record_json
  FROM `simplest-497710.raw.crm_new_partner_leads` leads
  WHERE email IS NULL
    OR TRIM(CAST(email AS STRING)) = ''

  UNION ALL
  SELECT
    'crm_sales_user_exists_in_oracle' AS rule_id,
    'raw.crm_sales' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(sales.deal_id AS STRING)), ''),
      NULLIF(TRIM(CAST(sales.customer_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(sales)))
    ) AS source_key,
    'raw.crm_sales.user_id must exist in raw.user_raw.USER_ID' AS error_reason,
    TO_JSON_STRING(sales) AS record_json
  FROM `simplest-497710.raw.crm_sales` sales
  LEFT JOIN `simplest-497710.raw.user_raw` users
    ON TRIM(CAST(sales.user_id AS STRING)) = TRIM(CAST(users.USER_ID AS STRING))
  WHERE sales.user_id IS NOT NULL
    AND TRIM(CAST(sales.user_id AS STRING)) != ''
    AND users.USER_ID IS NULL

  UNION ALL
  SELECT
    'crm_support_user_exists_in_oracle' AS rule_id,
    'raw.crm_support' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(support.ticket_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(support)))
    ) AS source_key,
    'raw.crm_support.user_id must exist in raw.user_raw.USER_ID' AS error_reason,
    TO_JSON_STRING(support) AS record_json
  FROM `simplest-497710.raw.crm_support` support
  LEFT JOIN `simplest-497710.raw.user_raw` users
    ON TRIM(CAST(support.user_id AS STRING)) = TRIM(CAST(users.USER_ID AS STRING))
  WHERE support.user_id IS NOT NULL
    AND TRIM(CAST(support.user_id AS STRING)) != ''
    AND users.USER_ID IS NULL

  UNION ALL
  SELECT
    'crm_campaign_user_exists_in_oracle' AS rule_id,
    'raw.crm_campaign_events' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(events.event_id AS STRING)), ''),
      NULLIF(TRIM(CAST(events.campaign_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(events)))
    ) AS source_key,
    'raw.crm_campaign_events.user_id must exist in raw.user_raw.USER_ID' AS error_reason,
    TO_JSON_STRING(events) AS record_json
  FROM `simplest-497710.raw.crm_campaign_events` events
  LEFT JOIN `simplest-497710.raw.user_raw` users
    ON TRIM(CAST(events.user_id AS STRING)) = TRIM(CAST(users.USER_ID AS STRING))
  WHERE events.user_id IS NOT NULL
    AND TRIM(CAST(events.user_id AS STRING)) != ''
    AND users.USER_ID IS NULL

  UNION ALL
  SELECT
    'user_raw_email_format_valid' AS rule_id,
    'raw.user_raw' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(USER_ID AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(users)))
    ) AS source_key,
    'raw.user_raw.EMAIL must be a valid email when present' AS error_reason,
    TO_JSON_STRING(users) AS record_json
  FROM `simplest-497710.raw.user_raw` users
  WHERE EMAIL IS NOT NULL
    AND TRIM(CAST(EMAIL AS STRING)) != ''
    AND NOT REGEXP_CONTAINS(
      TRIM(CAST(EMAIL AS STRING)),
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    )

  UNION ALL
  SELECT
    'user_raw_consent_email_valid' AS rule_id,
    'raw.user_raw' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(USER_ID AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(users)))
    ) AS source_key,
    'raw.user_raw.CONSENT_EMAIL must be Y, N, or null' AS error_reason,
    TO_JSON_STRING(users) AS record_json
  FROM `simplest-497710.raw.user_raw` users
  WHERE CONSENT_EMAIL IS NOT NULL
    AND TRIM(CAST(CONSENT_EMAIL AS STRING)) != ''
    AND UPPER(TRIM(CAST(CONSENT_EMAIL AS STRING))) NOT IN ('Y', 'N')

  UNION ALL
  SELECT
    'crm_partner_email_format_valid' AS rule_id,
    'raw.crm_new_partner_leads' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(external_lead_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(leads)))
    ) AS source_key,
    'raw.crm_new_partner_leads.email must be a valid email' AS error_reason,
    TO_JSON_STRING(leads) AS record_json
  FROM `simplest-497710.raw.crm_new_partner_leads` leads
  WHERE email IS NOT NULL
    AND TRIM(CAST(email AS STRING)) != ''
    AND NOT REGEXP_CONTAINS(
      TRIM(CAST(email AS STRING)),
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    )

  UNION ALL
  SELECT
    'crm_sales_deal_amount_non_negative' AS rule_id,
    'raw.crm_sales' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(deal_id AS STRING)), ''),
      NULLIF(TRIM(CAST(customer_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(sales)))
    ) AS source_key,
    'raw.crm_sales.deal_amount must be non-negative' AS error_reason,
    TO_JSON_STRING(sales) AS record_json
  FROM `simplest-497710.raw.crm_sales` sales
  WHERE SAFE_CAST(deal_amount AS NUMERIC) < 0

  UNION ALL
  SELECT
    'crm_support_csat_score_range' AS rule_id,
    'raw.crm_support' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(ticket_id AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(support)))
    ) AS source_key,
    'raw.crm_support.csat_score must be null or between 1 and 5' AS error_reason,
    TO_JSON_STRING(support) AS record_json
  FROM `simplest-497710.raw.crm_support` support
  WHERE csat_score IS NOT NULL
    AND (
      SAFE_CAST(csat_score AS INT64) < 1
      OR SAFE_CAST(csat_score AS INT64) > 5
    )

  UNION ALL
  SELECT
    'crm_partner_lead_score_range' AS rule_id,
    'raw.crm_new_partner_leads' AS source_table,
    COALESCE(
      NULLIF(TRIM(CAST(external_lead_id AS STRING)), ''),
      NULLIF(TRIM(CAST(email AS STRING)), ''),
      TO_HEX(SHA256(TO_JSON_STRING(leads)))
    ) AS source_key,
    'raw.crm_new_partner_leads.lead_score must be null or between 0 and 100' AS error_reason,
    TO_JSON_STRING(leads) AS record_json
  FROM `simplest-497710.raw.crm_new_partner_leads` leads
  WHERE lead_score IS NOT NULL
    AND (
      SAFE_CAST(lead_score AS INT64) < 0
      OR SAFE_CAST(lead_score AS INT64) > 100
    )
)
SELECT
  v_run_date AS run_date,
  v_dag_id AS dag_id,
  v_task_id AS task_id,
  rule_id,
  source_table,
  source_key,
  error_reason,
  record_json,
  v_evidence_created_at AS created_at
FROM rejected_rows;
