CREATE OR REPLACE TABLE `simplest-497710.mart.salesforce_campaign_audience` AS
WITH selected_segments AS (
  SELECT
    1 AS segment_id,
    'campaign_engaged_growth' AS campaign_code,
    'Campaign Engaged Growth' AS campaign_name,
    'High campaign engagement with meaningful purchase activity' AS audience_reason
  UNION ALL
  SELECT
    2 AS segment_id,
    'high_value_sales_growth' AS campaign_code,
    'High Value Sales Growth' AS campaign_name,
    'High sales activity and deal value' AS audience_reason
),

eligible_users AS (
  SELECT
    segments.user_id,
    segments.email,
    segments.segment_id,
    segments.segment_name,
    selected_segments.campaign_code,
    selected_segments.campaign_name,
    selected_segments.audience_reason,
    segments.city,
    segments.country,
    segments.income_band,
    segments.total_deal_amount,
    segments.sales_deal_count,
    segments.won_deal_count,
    segments.campaign_event_count,
    segments.campaign_click_count,
    segments.days_since_last_login,
    segments.segmented_at
  FROM `simplest-497710.mart.user_segments` segments
  JOIN selected_segments
    ON segments.segment_id = selected_segments.segment_id
  WHERE segments.can_email = TRUE
    AND segments.email IS NOT NULL
    AND TRIM(segments.email) != ''
)

SELECT
  user_id,
  email,
  campaign_code,
  campaign_name,
  segment_id,
  segment_name,
  audience_reason,
  city,
  country,
  income_band,
  total_deal_amount,
  sales_deal_count,
  won_deal_count,
  campaign_event_count,
  campaign_click_count,
  days_since_last_login,
  segmented_at,
  CURRENT_TIMESTAMP() AS audience_created_at,
  'READY_TO_SEND' AS activation_status
FROM eligible_users;