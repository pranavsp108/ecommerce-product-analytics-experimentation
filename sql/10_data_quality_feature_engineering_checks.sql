-- 10_data_quality_feature_engineering_checks.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Document and validate data quality, null handling, placeholder handling,
-- revenue sanity, feature engineering logic, and segmentation readiness.
--
-- This file is intentionally written as an audit/check script rather than a table-building script.
-- Run each section in BigQuery and copy important findings into:
-- reports/data_quality_and_feature_engineering_notes.md
--
-- BEFORE RUNNING:
-- 1. Replace project-id with your actual Google Cloud project ID.
-- 2. Run SQL files 01 through 09 first.

--------------------------------------------------------------------------------
-- 1. STAGED EVENT TABLE OVERVIEW
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS total_events,
  COUNT(DISTINCT event_key) AS unique_event_keys,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,
  COUNT(DISTINCT session_key) AS unique_sessions,
  MIN(event_date) AS min_event_date,
  MAX(event_date) AS max_event_date
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_events`;


--------------------------------------------------------------------------------
-- 2. EVENT KEY AND SESSION KEY QUALITY
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS total_events,
  COUNT(DISTINCT event_key) AS unique_event_keys,
  COUNT(*) - COUNT(DISTINCT event_key) AS duplicate_event_key_count,
  COUNTIF(event_key IS NULL) AS missing_event_key_count,
  COUNTIF(session_key IS NULL) AS missing_session_key_count,
  ROUND(COUNTIF(session_key IS NULL) / COUNT(*) * 100, 2) AS pct_missing_session_key,
  COUNTIF(user_pseudo_id IS NULL) AS missing_user_pseudo_id_count,
  ROUND(COUNTIF(user_pseudo_id IS NULL) / COUNT(*) * 100, 2) AS pct_missing_user_pseudo_id
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_events`;


--------------------------------------------------------------------------------
-- 3. EVENT DISTRIBUTION CHECK
--------------------------------------------------------------------------------

SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct_of_events
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_events`
GROUP BY
  event_name
ORDER BY
  event_count DESC;


--------------------------------------------------------------------------------
-- 4. CATEGORICAL NULL / UNKNOWN CHECKS IN STG_EVENTS
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS total_events,

  COUNTIF(device_category IS NULL OR device_category = 'unknown') AS unknown_device_category,
  ROUND(COUNTIF(device_category IS NULL OR device_category = 'unknown') / COUNT(*) * 100, 2) AS pct_unknown_device_category,

  COUNTIF(traffic_source IS NULL OR traffic_source = 'unknown' OR traffic_source = '(not set)') AS unknown_or_placeholder_traffic_source,
  ROUND(COUNTIF(traffic_source IS NULL OR traffic_source = 'unknown' OR traffic_source = '(not set)') / COUNT(*) * 100, 2) AS pct_unknown_or_placeholder_traffic_source,

  COUNTIF(traffic_medium IS NULL OR traffic_medium = 'unknown' OR traffic_medium = '(not set)') AS unknown_or_placeholder_traffic_medium,
  ROUND(COUNTIF(traffic_medium IS NULL OR traffic_medium = 'unknown' OR traffic_medium = '(not set)') / COUNT(*) * 100, 2) AS pct_unknown_or_placeholder_traffic_medium,

  COUNTIF(country IS NULL OR country = 'unknown') AS unknown_country,
  ROUND(COUNTIF(country IS NULL OR country = 'unknown') / COUNT(*) * 100, 2) AS pct_unknown_country,

  COUNTIF(browser IS NULL OR browser = 'unknown') AS unknown_browser,
  ROUND(COUNTIF(browser IS NULL OR browser = 'unknown') / COUNT(*) * 100, 2) AS pct_unknown_browser
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_events`;


--------------------------------------------------------------------------------
-- 5. TRAFFIC SOURCE QUALITY CHECK
--------------------------------------------------------------------------------

SELECT
  traffic_source,
  traffic_medium,
  COUNT(*) AS events,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT session_key) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchase_events,
  ROUND(SUM(CASE WHEN event_name = 'purchase' THEN COALESCE(purchase_revenue, 0) ELSE 0 END), 2) AS revenue
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_events`
GROUP BY
  traffic_source,
  traffic_medium
ORDER BY
  events DESC;


--------------------------------------------------------------------------------
-- 6. PURCHASE REVENUE SANITY CHECK
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS purchase_events,
  COUNT(DISTINCT transaction_id) AS unique_transactions,

  COUNTIF(transaction_id IS NULL OR transaction_id = '' OR transaction_id = '(not set)') AS missing_or_placeholder_transaction_id,
  COUNTIF(purchase_revenue IS NULL) AS missing_purchase_revenue,
  COUNTIF(purchase_revenue = 0) AS zero_purchase_revenue,
  COUNTIF(purchase_revenue < 0) AS negative_purchase_revenue,

  ROUND(MIN(purchase_revenue), 2) AS min_purchase_revenue,
  ROUND(APPROX_QUANTILES(purchase_revenue, 100)[OFFSET(25)], 2) AS p25_purchase_revenue,
  ROUND(APPROX_QUANTILES(purchase_revenue, 100)[OFFSET(50)], 2) AS median_purchase_revenue,
  ROUND(APPROX_QUANTILES(purchase_revenue, 100)[OFFSET(75)], 2) AS p75_purchase_revenue,
  ROUND(APPROX_QUANTILES(purchase_revenue, 100)[OFFSET(95)], 2) AS p95_purchase_revenue,
  ROUND(APPROX_QUANTILES(purchase_revenue, 100)[OFFSET(99)], 2) AS p99_purchase_revenue,
  ROUND(MAX(purchase_revenue), 2) AS max_purchase_revenue,

  ROUND(SUM(COALESCE(purchase_revenue, 0)), 2) AS total_purchase_revenue,
  ROUND(AVG(purchase_revenue), 2) AS avg_purchase_revenue
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_events`
WHERE
  event_name = 'purchase';


--------------------------------------------------------------------------------
-- 7. PURCHASE TRANSACTION DUPLICATE CHECK
--------------------------------------------------------------------------------

SELECT
  transaction_id,
  COUNT(*) AS purchase_event_rows,
  COUNT(DISTINCT user_pseudo_id) AS users,
  ROUND(SUM(COALESCE(purchase_revenue, 0)), 2) AS summed_revenue
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_events`
WHERE
  event_name = 'purchase'
  AND transaction_id IS NOT NULL
  AND transaction_id != '(not set)'
GROUP BY
  transaction_id
HAVING
  COUNT(*) > 1
ORDER BY
  purchase_event_rows DESC,
  summed_revenue DESC;


--------------------------------------------------------------------------------
-- 8. ITEM TABLE OVERVIEW
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS total_item_rows,
  COUNT(DISTINCT item_event_key) AS unique_item_event_keys,
  COUNT(DISTINCT event_key) AS unique_events_with_items,
  COUNT(DISTINCT user_pseudo_id) AS users_with_item_events,
  COUNT(DISTINCT session_key) AS sessions_with_item_events,
  COUNT(DISTINCT clean_item_id) AS unique_items,
  COUNT(DISTINCT clean_item_category) AS unique_categories,
  MIN(event_date) AS min_event_date,
  MAX(event_date) AS max_event_date
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_items`;


--------------------------------------------------------------------------------
-- 9. ITEM NULL / PLACEHOLDER / PRICE QUALITY CHECK
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS total_item_rows,

  SUM(is_missing_or_placeholder_item_id) AS missing_or_placeholder_item_ids,
  ROUND(SUM(is_missing_or_placeholder_item_id) / COUNT(*) * 100, 2) AS pct_missing_or_placeholder_item_ids,

  SUM(is_missing_or_placeholder_item_name) AS missing_or_placeholder_item_names,
  ROUND(SUM(is_missing_or_placeholder_item_name) / COUNT(*) * 100, 2) AS pct_missing_or_placeholder_item_names,

  SUM(is_missing_or_placeholder_item_category) AS missing_or_placeholder_item_categories,
  ROUND(SUM(is_missing_or_placeholder_item_category) / COUNT(*) * 100, 2) AS pct_missing_or_placeholder_item_categories,

  SUM(is_missing_item_price) AS missing_prices,
  ROUND(SUM(is_missing_item_price) / COUNT(*) * 100, 2) AS pct_missing_prices,

  SUM(is_missing_item_quantity) AS missing_quantities,
  ROUND(SUM(is_missing_item_quantity) / COUNT(*) * 100, 2) AS pct_missing_quantities,

  COUNTIF(price < 0) AS negative_price_rows,
  COUNTIF(quantity < 0) AS negative_quantity_rows,
  COUNTIF(estimated_item_revenue < 0) AS negative_estimated_item_revenue_rows
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_items`;


--------------------------------------------------------------------------------
-- 10. ITEM PRICE AND REVENUE OUTLIER CHECK
--------------------------------------------------------------------------------

SELECT
  ROUND(MIN(item_price), 2) AS min_item_price,
  ROUND(APPROX_QUANTILES(item_price, 100)[OFFSET(50)], 2) AS median_item_price,
  ROUND(APPROX_QUANTILES(item_price, 100)[OFFSET(95)], 2) AS p95_item_price,
  ROUND(APPROX_QUANTILES(item_price, 100)[OFFSET(99)], 2) AS p99_item_price,
  ROUND(MAX(item_price), 2) AS max_item_price,

  ROUND(MIN(estimated_item_revenue), 2) AS min_estimated_item_revenue,
  ROUND(APPROX_QUANTILES(estimated_item_revenue, 100)[OFFSET(50)], 2) AS median_estimated_item_revenue,
  ROUND(APPROX_QUANTILES(estimated_item_revenue, 100)[OFFSET(95)], 2) AS p95_estimated_item_revenue,
  ROUND(APPROX_QUANTILES(estimated_item_revenue, 100)[OFFSET(99)], 2) AS p99_estimated_item_revenue,
  ROUND(MAX(estimated_item_revenue), 2) AS max_estimated_item_revenue
FROM
  `ecommerce-product-analytics.ecommerce_analytics.stg_items`;


--------------------------------------------------------------------------------
-- 11. SESSION TABLE FEATURE SANITY CHECK
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS sessions,
  COUNT(DISTINCT session_key) AS unique_session_keys,
  COUNT(DISTINCT user_pseudo_id) AS users,

  COUNTIF(session_duration_seconds < 0) AS negative_duration_sessions,
  COUNTIF(session_duration_seconds = 0) AS zero_duration_sessions,
  COUNTIF(total_events <= 0) AS sessions_with_no_events,

  ROUND(MIN(session_duration_seconds), 2) AS min_session_duration_seconds,
  ROUND(APPROX_QUANTILES(session_duration_seconds, 100)[OFFSET(50)], 2) AS median_session_duration_seconds,
  ROUND(APPROX_QUANTILES(session_duration_seconds, 100)[OFFSET(95)], 2) AS p95_session_duration_seconds,
  ROUND(APPROX_QUANTILES(session_duration_seconds, 100)[OFFSET(99)], 2) AS p99_session_duration_seconds,
  ROUND(MAX(session_duration_seconds), 2) AS max_session_duration_seconds,

  ROUND(MIN(total_events), 2) AS min_events_per_session,
  ROUND(APPROX_QUANTILES(total_events, 100)[OFFSET(50)], 2) AS median_events_per_session,
  ROUND(APPROX_QUANTILES(total_events, 100)[OFFSET(95)], 2) AS p95_events_per_session,
  ROUND(MAX(total_events), 2) AS max_events_per_session
FROM
  `ecommerce-product-analytics.ecommerce_analytics.int_sessions`;


--------------------------------------------------------------------------------
-- 12. SESSION FUNNEL CONSISTENCY CHECK
--------------------------------------------------------------------------------
-- These are not necessarily "errors"; they identify unusual GA4 journey patterns.
-- For example, a purchase without a recorded view_item can happen due to attribution/windowing,
-- missing events, or tracking limitations.

SELECT
  COUNT(*) AS sessions,

  COUNTIF(had_purchase = 1 AND had_begin_checkout = 0) AS purchase_without_checkout_sessions,
  COUNTIF(had_begin_checkout = 1 AND had_add_to_cart = 0) AS checkout_without_cart_sessions,
  COUNTIF(had_add_to_cart = 1 AND had_view_item = 0) AS cart_without_product_view_sessions,
  COUNTIF(had_purchase = 1 AND had_view_item = 0) AS purchase_without_product_view_sessions,

  ROUND(COUNTIF(had_purchase = 1 AND had_begin_checkout = 0) / COUNT(*) * 100, 2) AS pct_purchase_without_checkout,
  ROUND(COUNTIF(had_begin_checkout = 1 AND had_add_to_cart = 0) / COUNT(*) * 100, 2) AS pct_checkout_without_cart,
  ROUND(COUNTIF(had_add_to_cart = 1 AND had_view_item = 0) / COUNT(*) * 100, 2) AS pct_cart_without_product_view,
  ROUND(COUNTIF(had_purchase = 1 AND had_view_item = 0) / COUNT(*) * 100, 2) AS pct_purchase_without_product_view
FROM
  `ecommerce-product-analytics.ecommerce_analytics.int_sessions`;


--------------------------------------------------------------------------------
-- 13. USER FEATURE OUTLIER CHECK
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS users,

  ROUND(APPROX_QUANTILES(total_sessions, 100)[OFFSET(50)], 2) AS median_sessions,
  ROUND(APPROX_QUANTILES(total_sessions, 100)[OFFSET(75)], 2) AS p75_sessions,
  ROUND(APPROX_QUANTILES(total_sessions, 100)[OFFSET(95)], 2) AS p95_sessions,
  ROUND(APPROX_QUANTILES(total_sessions, 100)[OFFSET(99)], 2) AS p99_sessions,
  MAX(total_sessions) AS max_sessions,

  ROUND(APPROX_QUANTILES(total_item_views, 100)[OFFSET(50)], 2) AS median_item_views,
  ROUND(APPROX_QUANTILES(total_item_views, 100)[OFFSET(75)], 2) AS p75_item_views,
  ROUND(APPROX_QUANTILES(total_item_views, 100)[OFFSET(95)], 2) AS p95_item_views,
  ROUND(APPROX_QUANTILES(total_item_views, 100)[OFFSET(99)], 2) AS p99_item_views,
  MAX(total_item_views) AS max_item_views,

  ROUND(APPROX_QUANTILES(total_add_to_carts, 100)[OFFSET(50)], 2) AS median_add_to_carts,
  ROUND(APPROX_QUANTILES(total_add_to_carts, 100)[OFFSET(95)], 2) AS p95_add_to_carts,
  ROUND(APPROX_QUANTILES(total_add_to_carts, 100)[OFFSET(99)], 2) AS p99_add_to_carts,
  MAX(total_add_to_carts) AS max_add_to_carts,

  ROUND(APPROX_QUANTILES(total_revenue, 100)[OFFSET(50)], 2) AS median_revenue,
  ROUND(APPROX_QUANTILES(total_revenue, 100)[OFFSET(75)], 2) AS p75_revenue,
  ROUND(APPROX_QUANTILES(total_revenue, 100)[OFFSET(95)], 2) AS p95_revenue,
  ROUND(APPROX_QUANTILES(total_revenue, 100)[OFFSET(99)], 2) AS p99_revenue,
  ROUND(MAX(total_revenue), 2) AS max_revenue
FROM
  `ecommerce-product-analytics.ecommerce_analytics.user_features`;


--------------------------------------------------------------------------------
-- 14. USER FEATURE NULL CHECK
--------------------------------------------------------------------------------

SELECT
  COUNT(*) AS users,

  COUNTIF(first_session_date IS NULL) AS missing_first_session_date,
  COUNTIF(first_device_category IS NULL OR first_device_category = 'unknown') AS missing_or_unknown_first_device,
  COUNTIF(first_traffic_source IS NULL OR first_traffic_source = 'unknown') AS missing_or_unknown_first_source,
  COUNTIF(favorite_view_category IS NULL OR favorite_view_category = 'unknown') AS missing_or_unknown_favorite_view_category,

  COUNTIF(total_sessions IS NULL) AS missing_total_sessions,
  COUNTIF(total_item_views IS NULL) AS missing_total_item_views,
  COUNTIF(total_add_to_carts IS NULL) AS missing_total_add_to_carts,
  COUNTIF(total_revenue IS NULL) AS missing_total_revenue,

  COUNTIF(user_session_purchase_rate IS NULL) AS missing_user_session_purchase_rate,
  COUNTIF(user_cart_abandonment_rate IS NULL) AS missing_user_cart_abandonment_rate,
  COUNTIF(avg_order_value IS NULL) AS missing_avg_order_value
FROM
  `ecommerce-product-analytics.ecommerce_analytics.user_features`;


--------------------------------------------------------------------------------
-- 15. SEGMENT DISTRIBUTION CHECK
--------------------------------------------------------------------------------

SELECT
  primary_customer_segment,
  COUNT(*) AS users,
  COUNTIF(has_ever_purchased = 1) AS buyers,
  COUNTIF(is_repeat_buyer = 1) AS repeat_buyers,
  ROUND(SUM(total_revenue), 2) AS revenue,
  ROUND(SAFE_DIVIDE(SUM(total_revenue), COUNT(*)), 2) AS revenue_per_user,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct_of_users
FROM
  `ecommerce-product-analytics.ecommerce_analytics.customer_segments`
GROUP BY
  primary_customer_segment
ORDER BY
  users DESC;


--------------------------------------------------------------------------------
-- 16. SEGMENT ACTION CHECK
--------------------------------------------------------------------------------

SELECT
  recommended_action,
  targeting_priority_rank,
  COUNT(*) AS users,
  ROUND(SUM(total_revenue), 2) AS revenue,
  ROUND(AVG(total_sessions), 2) AS avg_sessions,
  ROUND(AVG(total_item_views), 2) AS avg_item_views,
  ROUND(AVG(total_add_to_carts), 2) AS avg_add_to_carts,
  ROUND(SAFE_DIVIDE(SUM(total_revenue), COUNT(*)), 2) AS revenue_per_user
FROM
  `ecommerce-product-analytics.ecommerce_analytics.customer_segments`
GROUP BY
  recommended_action,
  targeting_priority_rank
ORDER BY
  targeting_priority_rank,
  users DESC;


--------------------------------------------------------------------------------
-- 17. TABLEAU EXPORT ROW COUNT CHECK
--------------------------------------------------------------------------------

SELECT 'tableau_kpi_daily' AS table_name, COUNT(*) AS rows
FROM `ecommerce-product-analytics.ecommerce_analytics.tableau_kpi_daily`

UNION ALL

SELECT 'tableau_funnel_daily' AS table_name, COUNT(*) AS rows
FROM `ecommerce-product-analytics.ecommerce_analytics.tableau_funnel_daily`

UNION ALL

SELECT 'tableau_category_performance' AS table_name, COUNT(*) AS rows
FROM `ecommerce-product-analytics.ecommerce_analytics.tableau_category_performance`

UNION ALL

SELECT 'tableau_cohort_retention_weekly' AS table_name, COUNT(*) AS rows
FROM `ecommerce-product-analytics.ecommerce_analytics.tableau_cohort_retention_weekly`

UNION ALL

SELECT 'tableau_customer_segments' AS table_name, COUNT(*) AS rows
FROM `ecommerce-product-analytics.ecommerce_analytics.tableau_customer_segments`

UNION ALL

SELECT 'tableau_segment_summary' AS table_name, COUNT(*) AS rows
FROM `ecommerce-product-analytics.ecommerce_analytics.tableau_segment_summary`

UNION ALL

SELECT 'tableau_executive_scorecard' AS table_name, COUNT(*) AS rows
FROM `ecommerce-product-analytics.ecommerce_analytics.tableau_executive_scorecard`;


--------------------------------------------------------------------------------
-- 18. FEATURE ENGINEERING SUMMARY FOR DOCUMENTATION
--------------------------------------------------------------------------------
-- Use this output to summarize engineered features in your report.

SELECT
  'session_features' AS feature_group,
  'session_key, session duration, funnel flags, engagement time, source/device fields, abandonment flags' AS engineered_features

UNION ALL

SELECT
  'item_features' AS feature_group,
  'clean item fields, item-level revenue estimate, item event flags, item data quality flags' AS engineered_features

UNION ALL

SELECT
  'user_features' AS feature_group,
  'lifetime sessions, views, carts, checkouts, purchases, revenue, recency, frequency, category preferences, behavioral rates' AS engineered_features

UNION ALL

SELECT
  'segmentation_features' AS feature_group,
  'primary segment, intent tier, value tier, engagement tier, buyer lifecycle tier, recommended action, targeting priority' AS engineered_features

UNION ALL

SELECT
  'tableau_exports' AS feature_group,
  'dashboard-ready KPI, funnel, category, cohort, segment, and executive scorecard tables' AS engineered_features;