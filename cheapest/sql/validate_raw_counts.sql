SELECT 'raw.crm_sales' AS table_name, COUNT(*) AS row_count
FROM `cheapest-497709.raw.crm_sales`

UNION ALL
SELECT 'raw.crm_support' AS table_name, COUNT(*) AS row_count
FROM `cheapest-497709.raw.crm_support`

UNION ALL
SELECT 'raw.crm_campaign_events' AS table_name, COUNT(*) AS row_count
FROM `cheapest-497709.raw.crm_campaign_events`

UNION ALL
SELECT 'raw.crm_new_partner_leads' AS table_name, COUNT(*) AS row_count
FROM `cheapest-497709.raw.crm_new_partner_leads`;
