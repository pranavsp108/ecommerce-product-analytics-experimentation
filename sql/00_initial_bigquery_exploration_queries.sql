-- 00_initial_bigquery_exploration_queries.sql
-- E-Commerce Product Analytics & Experimentation Platform
-- Initial GA4 BigQuery exploration queries.
-- Save this file in the sql/ folder of your GitHub repo.

-- 1. Preview events
SELECT
  event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  device.category AS device_category,
  traffic_source.source AS traffic_source,
  traffic_source.medium AS traffic_medium,
  geo.country AS country,
  ecommerce.purchase_revenue AS purchase_revenue
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
LIMIT 100;

-- 2. Count events by event name
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
GROUP BY
  event_name
ORDER BY
  event_count DESC;

-- 3. Check date range
SELECT
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS min_event_date,
  MAX(PARSE_DATE('%Y%m%d', event_date)) AS max_event_date,
  COUNT(*) AS total_events,
  COUNT(DISTINCT user_pseudo_id) AS total_users
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`;

-- 4. Inspect purchase events
SELECT
  event_date,
  event_timestamp,
  user_pseudo_id,
  ecommerce.transaction_id,
  ecommerce.purchase_revenue,
  ecommerce.total_item_quantity,
  ecommerce.unique_items
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE
  event_name = 'purchase'
LIMIT 100;

-- 5. Unnest item-level data
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  item.item_id,
  item.item_name,
  item.item_category,
  item.price,
  item.quantity
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(items) AS item
LIMIT 100;