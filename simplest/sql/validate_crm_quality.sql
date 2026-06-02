WITH rule_results AS (
  SELECT
    'raw_user_count_positive' AS rule_id,
    'ERROR' AS severity,
    'raw.user_raw' AS source_table,
    COUNTIF(row_count <= 0) AS failed_row_count,
    'raw.user_raw must contain at least one row' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.user_raw`
  )

  UNION ALL
  SELECT
    'crm_sales_count_positive' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_sales' AS source_table,
    COUNTIF(row_count <= 0) AS failed_row_count,
    'raw.crm_sales must contain at least one row' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.crm_sales`
  )

  UNION ALL
  SELECT
    'crm_support_count_positive' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_support' AS source_table,
    COUNTIF(row_count <= 0) AS failed_row_count,
    'raw.crm_support must contain at least one row' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.crm_support`
  )

  UNION ALL
  SELECT
    'crm_campaign_events_count_positive' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_campaign_events' AS source_table,
    COUNTIF(row_count <= 0) AS failed_row_count,
    'raw.crm_campaign_events must contain at least one row' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.crm_campaign_events`
  )

  UNION ALL
  SELECT
    'crm_partner_leads_count_positive' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_new_partner_leads' AS source_table,
    COUNTIF(row_count <= 0) AS failed_row_count,
    'raw.crm_new_partner_leads must contain at least one row' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.crm_new_partner_leads`
  )

  UNION ALL
  SELECT
    'raw_user_count_floor' AS rule_id,
    'WARNING' AS severity,
    'raw.user_raw' AS source_table,
    COUNTIF(row_count < 10000) AS failed_row_count,
    'raw.user_raw is below the 2026-05-26 lab count floor of 10000 rows' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.user_raw`
  )

  UNION ALL
  SELECT
    'crm_sales_count_floor' AS rule_id,
    'WARNING' AS severity,
    'raw.crm_sales' AS source_table,
    COUNTIF(row_count < 20000) AS failed_row_count,
    'raw.crm_sales is below the 2026-05-26 lab count floor of 20000 rows' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.crm_sales`
  )

  UNION ALL
  SELECT
    'crm_support_count_floor' AS rule_id,
    'WARNING' AS severity,
    'raw.crm_support' AS source_table,
    COUNTIF(row_count < 8000) AS failed_row_count,
    'raw.crm_support is below the 2026-05-26 lab count floor of 8000 rows' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.crm_support`
  )

  UNION ALL
  SELECT
    'crm_campaign_events_count_floor' AS rule_id,
    'WARNING' AS severity,
    'raw.crm_campaign_events' AS source_table,
    COUNTIF(row_count < 50000) AS failed_row_count,
    'raw.crm_campaign_events is below the 2026-05-26 lab count floor of 50000 rows' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.crm_campaign_events`
  )

  UNION ALL
  SELECT
    'crm_partner_leads_count_floor' AS rule_id,
    'WARNING' AS severity,
    'raw.crm_new_partner_leads' AS source_table,
    COUNTIF(row_count < 5000) AS failed_row_count,
    'raw.crm_new_partner_leads is below the 2026-05-26 lab count floor of 5000 rows' AS sample_error
  FROM (
    SELECT COUNT(*) AS row_count
    FROM `simplest-497710.raw.crm_new_partner_leads`
  )

  UNION ALL
  SELECT
    'user_raw_user_id_required' AS rule_id,
    'ERROR' AS severity,
    'raw.user_raw' AS source_table,
    COUNTIF(USER_ID IS NULL OR TRIM(CAST(USER_ID AS STRING)) = '') AS failed_row_count,
    'raw.user_raw.USER_ID is required' AS sample_error
  FROM `simplest-497710.raw.user_raw`

  UNION ALL
  SELECT
    'crm_sales_user_id_required' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_sales' AS source_table,
    COUNTIF(user_id IS NULL OR TRIM(CAST(user_id AS STRING)) = '') AS failed_row_count,
    'raw.crm_sales.user_id is required' AS sample_error
  FROM `simplest-497710.raw.crm_sales`

  UNION ALL
  SELECT
    'crm_sales_deal_id_required' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_sales' AS source_table,
    COUNTIF(deal_id IS NULL OR TRIM(CAST(deal_id AS STRING)) = '') AS failed_row_count,
    'raw.crm_sales.deal_id is required' AS sample_error
  FROM `simplest-497710.raw.crm_sales`

  UNION ALL
  SELECT
    'crm_support_user_id_required' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_support' AS source_table,
    COUNTIF(user_id IS NULL OR TRIM(CAST(user_id AS STRING)) = '') AS failed_row_count,
    'raw.crm_support.user_id is required' AS sample_error
  FROM `simplest-497710.raw.crm_support`

  UNION ALL
  SELECT
    'crm_support_ticket_id_required' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_support' AS source_table,
    COUNTIF(ticket_id IS NULL OR TRIM(CAST(ticket_id AS STRING)) = '') AS failed_row_count,
    'raw.crm_support.ticket_id is required' AS sample_error
  FROM `simplest-497710.raw.crm_support`

  UNION ALL
  SELECT
    'crm_campaign_user_id_required' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_campaign_events' AS source_table,
    COUNTIF(user_id IS NULL OR TRIM(CAST(user_id AS STRING)) = '') AS failed_row_count,
    'raw.crm_campaign_events.user_id is required' AS sample_error
  FROM `simplest-497710.raw.crm_campaign_events`

  UNION ALL
  SELECT
    'crm_campaign_event_id_required' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_campaign_events' AS source_table,
    COUNTIF(event_id IS NULL OR TRIM(CAST(event_id AS STRING)) = '') AS failed_row_count,
    'raw.crm_campaign_events.event_id is required' AS sample_error
  FROM `simplest-497710.raw.crm_campaign_events`

  UNION ALL
  SELECT
    'crm_partner_lead_id_required' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_new_partner_leads' AS source_table,
    COUNTIF(external_lead_id IS NULL OR TRIM(CAST(external_lead_id AS STRING)) = '') AS failed_row_count,
    'raw.crm_new_partner_leads.external_lead_id is required' AS sample_error
  FROM `simplest-497710.raw.crm_new_partner_leads`

  UNION ALL
  SELECT
    'crm_partner_email_required' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_new_partner_leads' AS source_table,
    COUNTIF(email IS NULL OR TRIM(CAST(email AS STRING)) = '') AS failed_row_count,
    'raw.crm_new_partner_leads.email is required' AS sample_error
  FROM `simplest-497710.raw.crm_new_partner_leads`

  UNION ALL
  SELECT
    'crm_sales_user_exists_in_oracle' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_sales' AS source_table,
    COUNT(*) AS failed_row_count,
    'raw.crm_sales.user_id must exist in raw.user_raw.USER_ID' AS sample_error
  FROM `simplest-497710.raw.crm_sales` sales
  LEFT JOIN `simplest-497710.raw.user_raw` users
    ON TRIM(CAST(sales.user_id AS STRING)) = TRIM(CAST(users.USER_ID AS STRING))
  WHERE sales.user_id IS NOT NULL
    AND TRIM(CAST(sales.user_id AS STRING)) != ''
    AND users.USER_ID IS NULL

  UNION ALL
  SELECT
    'crm_support_user_exists_in_oracle' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_support' AS source_table,
    COUNT(*) AS failed_row_count,
    'raw.crm_support.user_id must exist in raw.user_raw.USER_ID' AS sample_error
  FROM `simplest-497710.raw.crm_support` support
  LEFT JOIN `simplest-497710.raw.user_raw` users
    ON TRIM(CAST(support.user_id AS STRING)) = TRIM(CAST(users.USER_ID AS STRING))
  WHERE support.user_id IS NOT NULL
    AND TRIM(CAST(support.user_id AS STRING)) != ''
    AND users.USER_ID IS NULL

  UNION ALL
  SELECT
    'crm_campaign_user_exists_in_oracle' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_campaign_events' AS source_table,
    COUNT(*) AS failed_row_count,
    'raw.crm_campaign_events.user_id must exist in raw.user_raw.USER_ID' AS sample_error
  FROM `simplest-497710.raw.crm_campaign_events` events
  LEFT JOIN `simplest-497710.raw.user_raw` users
    ON TRIM(CAST(events.user_id AS STRING)) = TRIM(CAST(users.USER_ID AS STRING))
  WHERE events.user_id IS NOT NULL
    AND TRIM(CAST(events.user_id AS STRING)) != ''
    AND users.USER_ID IS NULL

  UNION ALL
  SELECT
    'user_raw_email_format_valid' AS rule_id,
    'ERROR' AS severity,
    'raw.user_raw' AS source_table,
    COUNTIF(
      EMAIL IS NOT NULL
      AND TRIM(CAST(EMAIL AS STRING)) != ''
      AND NOT REGEXP_CONTAINS(
        TRIM(CAST(EMAIL AS STRING)),
        r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
      )
    ) AS failed_row_count,
    'raw.user_raw.EMAIL must be a valid email when present' AS sample_error
  FROM `simplest-497710.raw.user_raw`

  UNION ALL
  SELECT
    'user_raw_consent_email_valid' AS rule_id,
    'ERROR' AS severity,
    'raw.user_raw' AS source_table,
    COUNTIF(
      CONSENT_EMAIL IS NOT NULL
      AND TRIM(CAST(CONSENT_EMAIL AS STRING)) != ''
      AND UPPER(TRIM(CAST(CONSENT_EMAIL AS STRING))) NOT IN ('Y', 'N')
    ) AS failed_row_count,
    'raw.user_raw.CONSENT_EMAIL must be Y, N, or null' AS sample_error
  FROM `simplest-497710.raw.user_raw`

  UNION ALL
  SELECT
    'crm_partner_email_format_valid' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_new_partner_leads' AS source_table,
    COUNTIF(
      email IS NOT NULL
      AND TRIM(CAST(email AS STRING)) != ''
      AND NOT REGEXP_CONTAINS(
        TRIM(CAST(email AS STRING)),
        r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
      )
    ) AS failed_row_count,
    'raw.crm_new_partner_leads.email must be a valid email' AS sample_error
  FROM `simplest-497710.raw.crm_new_partner_leads`

  UNION ALL
  SELECT
    'crm_partner_opt_in_true' AS rule_id,
    'WARNING' AS severity,
    'raw.crm_new_partner_leads' AS source_table,
    COUNTIF(opt_in IS NOT TRUE) AS failed_row_count,
    'raw.crm_new_partner_leads.opt_in should be TRUE for activation eligibility' AS sample_error
  FROM `simplest-497710.raw.crm_new_partner_leads`

  UNION ALL
  SELECT
    'crm_sales_deal_amount_non_negative' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_sales' AS source_table,
    COUNTIF(SAFE_CAST(deal_amount AS NUMERIC) < 0) AS failed_row_count,
    'raw.crm_sales.deal_amount must be non-negative' AS sample_error
  FROM `simplest-497710.raw.crm_sales`

  UNION ALL
  SELECT
    'crm_support_csat_score_range' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_support' AS source_table,
    COUNTIF(
      csat_score IS NOT NULL
      AND (
        SAFE_CAST(csat_score AS INT64) < 1
        OR SAFE_CAST(csat_score AS INT64) > 5
      )
    ) AS failed_row_count,
    'raw.crm_support.csat_score must be null or between 1 and 5' AS sample_error
  FROM `simplest-497710.raw.crm_support`

  UNION ALL
  SELECT
    'crm_partner_lead_score_range' AS rule_id,
    'ERROR' AS severity,
    'raw.crm_new_partner_leads' AS source_table,
    COUNTIF(
      lead_score IS NOT NULL
      AND (
        SAFE_CAST(lead_score AS INT64) < 0
        OR SAFE_CAST(lead_score AS INT64) > 100
      )
    ) AS failed_row_count,
    'raw.crm_new_partner_leads.lead_score must be null or between 0 and 100' AS sample_error
  FROM `simplest-497710.raw.crm_new_partner_leads`

  UNION ALL
  SELECT
    'crm_sales_currency_known' AS rule_id,
    'WARNING' AS severity,
    'raw.crm_sales' AS source_table,
    COUNTIF(
      currency IS NOT NULL
      AND TRIM(CAST(currency AS STRING)) != ''
      AND UPPER(TRIM(CAST(currency AS STRING))) NOT IN ('USD', 'TWD', 'EUR', 'JPY')
    ) AS failed_row_count,
    'raw.crm_sales.currency should be USD, TWD, EUR, or JPY' AS sample_error
  FROM `simplest-497710.raw.crm_sales`

  UNION ALL
  SELECT
    'crm_campaign_channel_present' AS rule_id,
    'WARNING' AS severity,
    'raw.crm_campaign_events' AS source_table,
    COUNTIF(channel IS NULL OR TRIM(CAST(channel AS STRING)) = '') AS failed_row_count,
    'raw.crm_campaign_events.channel should be present' AS sample_error
  FROM `simplest-497710.raw.crm_campaign_events`
)
SELECT
  rule_id,
  severity,
  source_table,
  failed_row_count,
  sample_error
FROM rule_results
ORDER BY
  CASE severity
    WHEN 'ERROR' THEN 1
    WHEN 'WARNING' THEN 2
    ELSE 3
  END,
  rule_id;
