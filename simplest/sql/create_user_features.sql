CREATE OR REPLACE TABLE `simplest-497710.mart.user_features` AS
WITH raw_users AS (
  SELECT * EXCEPT(row_num)
  FROM (
    SELECT
      CAST(USER_ID AS STRING) AS user_id,
      LOWER(TRIM(CAST(EMAIL AS STRING))) AS email,
      FIRST_NAME AS first_name,
      LAST_NAME AS last_name,
      CITY AS city,
      COUNTRY AS country,
      INCOME_BAND AS income_band,
      SOURCE_SYSTEM AS source_system,
      UPPER(TRIM(CAST(CONSENT_EMAIL AS STRING))) AS consent_email,
      SAFE_CAST(SIGNUP_DATE AS TIMESTAMP) AS signup_at,
      SAFE_CAST(LAST_LOGIN_AT AS TIMESTAMP) AS last_login_at,
      SAFE_CAST(UPDATED_AT AS TIMESTAMP) AS updated_at,
      ROW_NUMBER() OVER (
        PARTITION BY CAST(USER_ID AS STRING)
        ORDER BY SAFE_CAST(UPDATED_AT AS TIMESTAMP) DESC
      ) AS row_num
    FROM `simplest-497710.raw.user_raw`
    WHERE USER_ID IS NOT NULL
      AND TRIM(CAST(USER_ID AS STRING)) != ''
  )
  WHERE row_num = 1
),

sales_raw AS (
  SELECT * EXCEPT(row_num)
  FROM (
    SELECT
      customer_id,
      user_id,
      deal_id,
      deal_stage,
      deal_amount,
      currency,
      closed_date,
      owner_region,
      ROW_NUMBER() OVER (
        PARTITION BY CAST(deal_id AS STRING)
        ORDER BY CAST(deal_id AS STRING)
      ) AS row_num
    FROM `simplest-497710.raw.crm_sales`
    WHERE deal_id IS NOT NULL
      AND TRIM(CAST(deal_id AS STRING)) != ''
  )
  WHERE row_num = 1
),

support_raw AS (
  SELECT * EXCEPT(row_num)
  FROM (
    SELECT
      ticket_id,
      user_id,
      priority,
      status,
      category,
      csat_score,
      ROW_NUMBER() OVER (
        PARTITION BY CAST(ticket_id AS STRING)
        ORDER BY CAST(ticket_id AS STRING)
      ) AS row_num
    FROM `simplest-497710.raw.crm_support`
    WHERE ticket_id IS NOT NULL
      AND TRIM(CAST(ticket_id AS STRING)) != ''
  )
  WHERE row_num = 1
),

campaign_raw AS (
  SELECT * EXCEPT(row_num)
  FROM (
    SELECT
      event_id,
      user_id,
      campaign_id,
      channel,
      event_type,
      event_ts,
      ROW_NUMBER() OVER (
        PARTITION BY CAST(event_id AS STRING)
        ORDER BY CAST(event_id AS STRING)
      ) AS row_num
    FROM `simplest-497710.raw.crm_campaign_events`
    WHERE event_id IS NOT NULL
      AND TRIM(CAST(event_id AS STRING)) != ''
  )
  WHERE row_num = 1
),

users AS (
  SELECT
    user_id,
    email,
    first_name,
    last_name,
    city,
    country,
    income_band,
    source_system,
    consent_email,
    signup_at,
    last_login_at,
    updated_at
  FROM raw_users
),

sales AS (
  SELECT
    CAST(user_id AS STRING) AS user_id,
    COUNT(*) AS sales_deal_count,
    COUNTIF(LOWER(deal_stage) IN ('closed_won', 'won')) AS won_deal_count,
    SUM(SAFE_CAST(deal_amount AS NUMERIC)) AS total_deal_amount,
    AVG(SAFE_CAST(deal_amount AS NUMERIC)) AS avg_deal_amount
  FROM sales_raw
  GROUP BY user_id
),

support AS (
  SELECT
    CAST(user_id AS STRING) AS user_id,
    COUNT(*) AS support_ticket_count,
    AVG(SAFE_CAST(csat_score AS NUMERIC)) AS avg_csat_score
  FROM support_raw
  GROUP BY user_id
),

campaign AS (
  SELECT
    CAST(user_id AS STRING) AS user_id,
    COUNT(*) AS campaign_event_count,
    COUNTIF(LOWER(event_type) IN ('click', 'clicked')) AS campaign_click_count,
    COUNTIF(LOWER(event_type) IN ('open', 'opened')) AS campaign_open_count
  FROM campaign_raw
  GROUP BY user_id
)

SELECT
  users.user_id,
  users.email,
  users.first_name,
  users.last_name,
  users.city,
  users.country,
  users.income_band,
  users.source_system,
  users.consent_email,
  users.signup_at,
  users.last_login_at,
  users.updated_at,

  IFNULL(sales.sales_deal_count, 0) AS sales_deal_count,
  IFNULL(sales.won_deal_count, 0) AS won_deal_count,
  IFNULL(sales.total_deal_amount, 0) AS total_deal_amount,
  IFNULL(sales.avg_deal_amount, 0) AS avg_deal_amount,

  IFNULL(support.support_ticket_count, 0) AS support_ticket_count,
  IFNULL(support.avg_csat_score, 0) AS avg_csat_score,

  IFNULL(campaign.campaign_event_count, 0) AS campaign_event_count,
  IFNULL(campaign.campaign_click_count, 0) AS campaign_click_count,
  IFNULL(campaign.campaign_open_count, 0) AS campaign_open_count,

  DATE_DIFF(CURRENT_DATE(), DATE(users.signup_at), DAY) AS days_since_signup,
  DATE_DIFF(CURRENT_DATE(), DATE(users.last_login_at), DAY) AS days_since_last_login,

  users.consent_email = 'Y' AS can_email
FROM users
LEFT JOIN sales
  ON users.user_id = sales.user_id
LEFT JOIN support
  ON users.user_id = support.user_id
LEFT JOIN campaign
  ON users.user_id = campaign.user_id
WHERE users.user_id IS NOT NULL
  AND users.user_id != '';