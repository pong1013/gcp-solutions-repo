CREATE OR REPLACE MODEL `simplest-497710.mart.user_segment_model`
OPTIONS (
  model_type = 'kmeans',
  num_clusters = 4,
  standardize_features = TRUE,
  max_iterations = 20
) AS
SELECT
  CAST(sales_deal_count AS FLOAT64) AS sales_deal_count,
  CAST(won_deal_count AS FLOAT64) AS won_deal_count,
  CAST(total_deal_amount AS FLOAT64) AS total_deal_amount,
  CAST(avg_deal_amount AS FLOAT64) AS avg_deal_amount,
  CAST(support_ticket_count AS FLOAT64) AS support_ticket_count,
  CAST(avg_csat_score AS FLOAT64) AS avg_csat_score,
  CAST(campaign_event_count AS FLOAT64) AS campaign_event_count,
  CAST(campaign_click_count AS FLOAT64) AS campaign_click_count,
  CAST(campaign_open_count AS FLOAT64) AS campaign_open_count,
  CAST(days_since_signup AS FLOAT64) AS days_since_signup,
  CAST(days_since_last_login AS FLOAT64) AS days_since_last_login
FROM `simplest-497710.mart.user_features`
WHERE user_id IS NOT NULL;

CREATE OR REPLACE TABLE `simplest-497710.mart.user_segments` AS
WITH scoring_input AS (
  SELECT
    user_id,
    email,
    can_email,
    city,
    country,
    income_band,
    sales_deal_count,
    won_deal_count,
    total_deal_amount,
    avg_deal_amount,
    support_ticket_count,
    avg_csat_score,
    campaign_event_count,
    campaign_click_count,
    campaign_open_count,
    days_since_signup,
    days_since_last_login
  FROM `simplest-497710.mart.user_features`
  WHERE user_id IS NOT NULL
)
SELECT
  user_id,
  email,
  can_email,
  city,
  country,
  income_band,
  CENTROID_ID AS segment_id,
  CONCAT('segment_', CAST(CENTROID_ID AS STRING)) AS segment_name,
  sales_deal_count,
  won_deal_count,
  total_deal_amount,
  avg_deal_amount,
  support_ticket_count,
  avg_csat_score,
  campaign_event_count,
  campaign_click_count,
  campaign_open_count,
  days_since_signup,
  days_since_last_login,
  CURRENT_TIMESTAMP() AS segmented_at
FROM ML.PREDICT(
  MODEL `simplest-497710.mart.user_segment_model`,
  (
    SELECT
      user_id,
      email,
      can_email,
      city,
      country,
      income_band,
      CAST(sales_deal_count AS FLOAT64) AS sales_deal_count,
      CAST(won_deal_count AS FLOAT64) AS won_deal_count,
      CAST(total_deal_amount AS FLOAT64) AS total_deal_amount,
      CAST(avg_deal_amount AS FLOAT64) AS avg_deal_amount,
      CAST(support_ticket_count AS FLOAT64) AS support_ticket_count,
      CAST(avg_csat_score AS FLOAT64) AS avg_csat_score,
      CAST(campaign_event_count AS FLOAT64) AS campaign_event_count,
      CAST(campaign_click_count AS FLOAT64) AS campaign_click_count,
      CAST(campaign_open_count AS FLOAT64) AS campaign_open_count,
      CAST(days_since_signup AS FLOAT64) AS days_since_signup,
      CAST(days_since_last_login AS FLOAT64) AS days_since_last_login
    FROM scoring_input
  )
);