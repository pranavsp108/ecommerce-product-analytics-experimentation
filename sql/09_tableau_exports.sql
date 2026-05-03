-- 09_tableau_exports.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create simplified Tableau-ready export tables from the product analytics marts.
--
-- Why this file exists:
-- The previous SQL files create detailed analytics marts. Tableau Public works best when
-- each dashboard page has a clean, relatively flat table. These export tables reduce
-- complexity and make dashboard building faster.
--
-- Outputs:
-- 1. tableau_kpi_daily
-- 2. tableau_funnel_daily
-- 3. tableau_category_performance
-- 4. tableau_cohort_retention_weekly
-- 5. tableau_customer_segments
-- 6. tableau_segment_summary
-- 7. tableau_executive_scorecard
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run SQL files 01 through 08 first.
--
-- Recommended Tableau workflow:
-- Export each table as CSV from BigQuery, then load CSVs into Tableau Public.

--------------------------------------------------------------------------------
-- 1. DAILY KPI EXPORT
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.tableau_kpi_daily`
PARTITION BY metric_date
CLUSTER BY device_category, traffic_source, traffic_medium, session_user_type
AS

SELECT
  metric_date,
  metric_month,
  metric_week,
  metric_day_of_week,

  device_category,
  traffic_source,
  traffic_medium,
  traffic_campaign,
  session_user_type,

  SUM(sessions) AS sessions,
  SUM(active_users) AS active_users,
  SUM(total_events) AS total_events,
  SUM(page_views) AS page_views,
  SUM(product_views) AS product_views,
  SUM(add_to_cart_events) AS add_to_cart_events,
  SUM(cart_views) AS cart_views,
  SUM(checkout_starts) AS checkout_starts,
  SUM(payment_info_events) AS payment_info_events,
  SUM(purchase_events) AS purchase_events,

  SUM(sessions_with_product_view) AS sessions_with_product_view,
  SUM(sessions_with_add_to_cart) AS sessions_with_add_to_cart,
  SUM(sessions_with_checkout) AS sessions_with_checkout,
  SUM(purchasing_sessions) AS purchasing_sessions,

  SUM(cart_abandoned_sessions) AS cart_abandoned_sessions,
  SUM(checkout_abandoned_sessions) AS checkout_abandoned_sessions,
  SUM(bounce_like_sessions) AS bounce_like_sessions,

  SUM(transactions) AS transactions,
  ROUND(SUM(revenue), 2) AS revenue,
  SUM(purchased_item_quantity) AS purchased_item_quantity,
  SUM(purchased_unique_items) AS purchased_unique_items,

  ROUND(SAFE_DIVIDE(SUM(purchasing_sessions), SUM(sessions)) * 100, 2) AS session_purchase_conversion_rate,
  ROUND(SAFE_DIVIDE(SUM(sessions_with_product_view), SUM(sessions)) * 100, 2) AS product_view_session_rate,
  ROUND(SAFE_DIVIDE(SUM(sessions_with_add_to_cart), SUM(sessions_with_product_view)) * 100, 2) AS view_to_cart_session_rate,
  ROUND(SAFE_DIVIDE(SUM(sessions_with_checkout), SUM(sessions_with_add_to_cart)) * 100, 2) AS cart_to_checkout_session_rate,
  ROUND(SAFE_DIVIDE(SUM(purchasing_sessions), SUM(sessions_with_checkout)) * 100, 2) AS checkout_to_purchase_session_rate,
  ROUND(SAFE_DIVIDE(SUM(purchasing_sessions), SUM(sessions_with_product_view)) * 100, 2) AS view_to_purchase_session_rate,

  ROUND(SAFE_DIVIDE(SUM(cart_abandoned_sessions), SUM(sessions_with_add_to_cart)) * 100, 2) AS cart_abandonment_rate,
  ROUND(SAFE_DIVIDE(SUM(checkout_abandoned_sessions), SUM(sessions_with_checkout)) * 100, 2) AS checkout_abandonment_rate,
  ROUND(SAFE_DIVIDE(SUM(bounce_like_sessions), SUM(sessions)) * 100, 2) AS bounce_like_session_rate,

  ROUND(SAFE_DIVIDE(SUM(revenue), SUM(transactions)), 2) AS average_order_value,
  ROUND(SAFE_DIVIDE(SUM(revenue), SUM(active_users)), 2) AS revenue_per_active_user,
  ROUND(SAFE_DIVIDE(SUM(revenue), SUM(sessions)), 2) AS revenue_per_session,
  ROUND(SAFE_DIVIDE(SUM(transactions), SUM(active_users)), 2) AS transactions_per_active_user,

  ROUND(SAFE_DIVIDE(SUM(product_views), SUM(sessions)), 2) AS product_views_per_session,
  ROUND(SAFE_DIVIDE(SUM(add_to_cart_events), SUM(sessions)), 2) AS add_to_cart_events_per_session,
  ROUND(SAFE_DIVIDE(SUM(checkout_starts), SUM(sessions)), 2) AS checkout_starts_per_session

FROM
  `ecommerce-product-analytics.ecommerce_analytics.mart_product_kpis`
GROUP BY
  metric_date,
  metric_month,
  metric_week,
  metric_day_of_week,
  device_category,
  traffic_source,
  traffic_medium,
  traffic_campaign,
  session_user_type;


--------------------------------------------------------------------------------
-- 2. FUNNEL DAILY EXPORT
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.tableau_funnel_daily`
PARTITION BY funnel_date
CLUSTER BY device_category, traffic_source, traffic_medium, session_user_type
AS

SELECT
  funnel_date,
  funnel_month,
  funnel_week,
  funnel_day_of_week,

  device_category,
  traffic_source,
  traffic_medium,
  traffic_campaign,
  session_user_type,

  SUM(sessions) AS sessions,
  SUM(step_1_sessions_or_page_views) AS step_1_sessions_or_page_views,
  SUM(step_2_product_view_sessions) AS step_2_product_view_sessions,
  SUM(step_3_add_to_cart_sessions) AS step_3_add_to_cart_sessions,
  SUM(step_4_checkout_sessions) AS step_4_checkout_sessions,
  SUM(step_5_purchase_sessions) AS step_5_purchase_sessions,

  SUM(drop_after_session_or_page_view) AS drop_after_session_or_page_view,
  SUM(drop_after_product_view) AS drop_after_product_view,
  SUM(drop_after_add_to_cart) AS drop_after_add_to_cart,
  SUM(drop_after_checkout) AS drop_after_checkout,

  SUM(product_view_events) AS product_view_events,
  SUM(add_to_cart_events) AS add_to_cart_events,
  SUM(checkout_events) AS checkout_events,
  SUM(purchase_events) AS purchase_events,
  SUM(transactions) AS transactions,
  ROUND(SUM(revenue), 2) AS revenue,

  ROUND(SAFE_DIVIDE(SUM(step_2_product_view_sessions), SUM(step_1_sessions_or_page_views)) * 100, 2) AS session_to_product_view_rate,
  ROUND(SAFE_DIVIDE(SUM(step_3_add_to_cart_sessions), SUM(step_2_product_view_sessions)) * 100, 2) AS product_view_to_cart_rate,
  ROUND(SAFE_DIVIDE(SUM(step_4_checkout_sessions), SUM(step_3_add_to_cart_sessions)) * 100, 2) AS cart_to_checkout_rate,
  ROUND(SAFE_DIVIDE(SUM(step_5_purchase_sessions), SUM(step_4_checkout_sessions)) * 100, 2) AS checkout_to_purchase_rate,

  ROUND(SAFE_DIVIDE(SUM(step_5_purchase_sessions), SUM(sessions)) * 100, 2) AS session_to_purchase_rate,
  ROUND(SAFE_DIVIDE(SUM(step_5_purchase_sessions), SUM(step_2_product_view_sessions)) * 100, 2) AS product_view_to_purchase_rate,

  ROUND(SAFE_DIVIDE(SUM(drop_after_session_or_page_view), SUM(step_1_sessions_or_page_views)) * 100, 2) AS drop_rate_after_session_or_page_view,
  ROUND(SAFE_DIVIDE(SUM(drop_after_product_view), SUM(step_2_product_view_sessions)) * 100, 2) AS drop_rate_after_product_view,
  ROUND(SAFE_DIVIDE(SUM(drop_after_add_to_cart), SUM(step_3_add_to_cart_sessions)) * 100, 2) AS drop_rate_after_add_to_cart,
  ROUND(SAFE_DIVIDE(SUM(drop_after_checkout), SUM(step_4_checkout_sessions)) * 100, 2) AS drop_rate_after_checkout,

  ROUND(SAFE_DIVIDE(SUM(revenue), SUM(step_5_purchase_sessions)), 2) AS revenue_per_purchasing_session,
  ROUND(SAFE_DIVIDE(SUM(revenue), SUM(sessions)), 2) AS revenue_per_session,
  ROUND(SAFE_DIVIDE(SUM(revenue), SUM(transactions)), 2) AS average_order_value

FROM
  `ecommerce-product-analytics.ecommerce_analytics.mart_funnel_sessions`
GROUP BY
  funnel_date,
  funnel_month,
  funnel_week,
  funnel_day_of_week,
  device_category,
  traffic_source,
  traffic_medium,
  traffic_campaign,
  session_user_type;


--------------------------------------------------------------------------------
-- 3. CATEGORY PERFORMANCE EXPORT
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.tableau_category_performance`
PARTITION BY funnel_date
CLUSTER BY item_category, device_category, traffic_source, traffic_medium
AS

SELECT
  funnel_date,
  funnel_month,
  funnel_week,
  funnel_day_of_week,

  item_category,
  device_category,
  traffic_source,
  traffic_medium,

  SUM(item_event_rows) AS item_event_rows,
  SUM(users) AS users,
  SUM(sessions) AS sessions,
  SUM(unique_items) AS unique_items,

  SUM(item_views) AS item_views,
  SUM(item_selects) AS item_selects,
  SUM(item_add_to_carts) AS item_add_to_carts,
  SUM(item_removes_from_cart) AS item_removes_from_cart,
  SUM(item_checkout_events) AS item_checkout_events,
  SUM(item_purchase_events) AS item_purchase_events,

  SUM(users_viewed_category) AS users_viewed_category,
  SUM(users_added_category_to_cart) AS users_added_category_to_cart,
  SUM(users_started_checkout_with_category) AS users_started_checkout_with_category,
  SUM(users_purchased_category) AS users_purchased_category,

  SUM(sessions_viewed_category) AS sessions_viewed_category,
  SUM(sessions_added_category_to_cart) AS sessions_added_category_to_cart,
  SUM(sessions_started_checkout_with_category) AS sessions_started_checkout_with_category,
  SUM(sessions_purchased_category) AS sessions_purchased_category,

  ROUND(SUM(category_item_revenue), 2) AS category_item_revenue,
  SUM(category_quantity_purchased) AS category_quantity_purchased,

  ROUND(SAFE_DIVIDE(SUM(item_add_to_carts), SUM(item_views)) * 100, 2) AS item_view_to_cart_rate,
  ROUND(SAFE_DIVIDE(SUM(item_checkout_events), SUM(item_add_to_carts)) * 100, 2) AS item_cart_to_checkout_rate,
  ROUND(SAFE_DIVIDE(SUM(item_purchase_events), SUM(item_checkout_events)) * 100, 2) AS item_checkout_to_purchase_rate,
  ROUND(SAFE_DIVIDE(SUM(item_purchase_events), SUM(item_views)) * 100, 2) AS item_view_to_purchase_rate,

  ROUND(SAFE_DIVIDE(SUM(users_added_category_to_cart), SUM(users_viewed_category)) * 100, 2) AS user_category_view_to_cart_rate,
  ROUND(SAFE_DIVIDE(SUM(users_started_checkout_with_category), SUM(users_added_category_to_cart)) * 100, 2) AS user_category_cart_to_checkout_rate,
  ROUND(SAFE_DIVIDE(SUM(users_purchased_category), SUM(users_started_checkout_with_category)) * 100, 2) AS user_category_checkout_to_purchase_rate,
  ROUND(SAFE_DIVIDE(SUM(users_purchased_category), SUM(users_viewed_category)) * 100, 2) AS user_category_view_to_purchase_rate,

  ROUND(SAFE_DIVIDE(SUM(category_item_revenue), SUM(users_purchased_category)), 2) AS revenue_per_category_buyer,
  ROUND(SAFE_DIVIDE(SUM(category_item_revenue), SUM(sessions_purchased_category)), 2) AS revenue_per_purchasing_category_session,
  ROUND(SAFE_DIVIDE(SUM(category_item_revenue), SUM(item_purchase_events)), 2) AS revenue_per_item_purchase_event

FROM
  `ecommerce-product-analytics.ecommerce_analytics.mart_funnel_categories`
GROUP BY
  funnel_date,
  funnel_month,
  funnel_week,
  funnel_day_of_week,
  item_category,
  device_category,
  traffic_source,
  traffic_medium;


--------------------------------------------------------------------------------
-- 4. WEEKLY COHORT RETENTION EXPORT
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.tableau_cohort_retention_weekly`
PARTITION BY cohort_month
CLUSTER BY week_number, first_traffic_source, first_device_category, first_traffic_medium
AS

SELECT
  cohort_month,
  cohort_month_label,
  week_number,
  week_label,

  first_device_category,
  first_traffic_source,
  first_traffic_medium,
  first_traffic_campaign,
  first_country,

  SUM(cohort_users) AS cohort_users,
  SUM(retained_users) AS retained_users,
  ROUND(SAFE_DIVIDE(SUM(retained_users), SUM(cohort_users)) * 100, 2) AS retention_rate

FROM
  `ecommerce-product-analytics.ecommerce_analytics.mart_cohort_retention_weekly`
GROUP BY
  cohort_month,
  cohort_month_label,
  week_number,
  week_label,
  first_device_category,
  first_traffic_source,
  first_traffic_medium,
  first_traffic_campaign,
  first_country;


--------------------------------------------------------------------------------
-- 5. CUSTOMER SEGMENTS EXPORT
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.tableau_customer_segments`
PARTITION BY first_session_date
CLUSTER BY primary_customer_segment, recommended_action, value_tier, intent_tier
AS

SELECT
  user_pseudo_id,

  first_session_date,
  first_session_month,
  first_purchase_date,
  first_purchase_month,
  last_session_date,
  last_purchase_date,

  first_device_category,
  first_traffic_source,
  first_traffic_medium,
  first_traffic_campaign,
  first_country,

  favorite_session_category,
  favorite_view_category,
  favorite_cart_category,
  favorite_purchase_category,

  primary_customer_segment,
  recommended_action,
  targeting_priority_rank,
  intent_tier,
  value_tier,
  engagement_tier,
  recency_tier,
  buyer_lifecycle_tier,

  total_sessions,
  active_days,
  total_item_views,
  total_add_to_carts,
  total_checkouts_started,
  total_transactions,
  total_revenue,

  sessions_with_product_view,
  sessions_with_add_to_cart,
  sessions_with_checkout,
  purchasing_sessions,
  cart_abandoned_sessions,
  checkout_abandoned_sessions,
  bounce_like_sessions,

  user_view_to_cart_session_rate,
  user_cart_to_checkout_session_rate,
  user_checkout_to_purchase_session_rate,
  user_session_purchase_rate,
  user_cart_abandonment_rate,
  user_checkout_abandonment_rate,
  user_bounce_like_rate,

  avg_order_value,
  revenue_per_session,
  revenue_per_active_day,

  has_ever_purchased,
  is_repeat_buyer,
  is_repeat_visitor,
  is_high_intent_non_buyer,
  is_cart_abandoner_non_buyer,
  is_checkout_abandoner_non_buyer,
  is_top_10pct_revenue_customer

FROM
  `ecommerce-product-analytics.ecommerce_analytics.customer_segments`;


--------------------------------------------------------------------------------
-- 6. CUSTOMER SEGMENT SUMMARY EXPORT
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.tableau_segment_summary`
CLUSTER BY primary_customer_segment, recommended_action, intent_tier, value_tier
AS

SELECT
  primary_customer_segment,
  recommended_action,
  targeting_priority_rank,
  intent_tier,
  value_tier,
  engagement_tier,
  buyer_lifecycle_tier,

  users,
  buyers,
  repeat_buyers,
  high_intent_non_buyers,
  cart_abandoner_non_buyers,
  checkout_abandoner_non_buyers,

  sessions,
  item_views,
  add_to_carts,
  checkout_starts,
  transactions,
  revenue,

  avg_sessions_per_user,
  avg_item_views_per_user,
  avg_add_to_carts_per_user,
  avg_revenue_per_user,
  avg_order_value,

  buyer_rate,
  repeat_buyer_rate,
  revenue_per_segment_user,
  transactions_per_segment_user,
  pct_of_users,
  pct_of_revenue

FROM
  `ecommerce-product-analytics.ecommerce_analytics.mart_customer_segment_summary`;


--------------------------------------------------------------------------------
-- 7. EXECUTIVE SCORECARD EXPORT
--------------------------------------------------------------------------------
-- This is a compact KPI table for the first dashboard page.

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.tableau_executive_scorecard`
AS

WITH kpi AS (
  SELECT
    COUNT(DISTINCT metric_date) AS active_days,

    SUM(sessions) AS sessions,
    SUM(active_users) AS active_users,
    SUM(product_views) AS product_views,
    SUM(add_to_cart_events) AS add_to_cart_events,
    SUM(checkout_starts) AS checkout_starts,
    SUM(purchasing_sessions) AS purchasing_sessions,
    SUM(transactions) AS transactions,
    ROUND(SUM(revenue), 2) AS revenue,

    SUM(cart_abandoned_sessions) AS cart_abandoned_sessions,
    SUM(checkout_abandoned_sessions) AS checkout_abandoned_sessions,
    SUM(bounce_like_sessions) AS bounce_like_sessions
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.mart_product_kpis`
),

segments AS (
  SELECT
    COUNT(*) AS users_in_segment_table,
    COUNTIF(has_ever_purchased = 1) AS buyers,
    COUNTIF(is_repeat_buyer = 1) AS repeat_buyers,
    COUNTIF(is_high_intent_non_buyer = 1) AS high_intent_non_buyers,
    COUNTIF(is_cart_abandoner_non_buyer = 1) AS cart_abandoner_non_buyers,
    COUNTIF(is_checkout_abandoner_non_buyer = 1) AS checkout_abandoner_non_buyers
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.customer_segments`
)

SELECT
  k.active_days,
  k.sessions,
  k.active_users,
  k.product_views,
  k.add_to_cart_events,
  k.checkout_starts,
  k.purchasing_sessions,
  k.transactions,
  k.revenue,

  ROUND(SAFE_DIVIDE(k.purchasing_sessions, k.sessions) * 100, 2) AS session_purchase_conversion_rate,
  ROUND(SAFE_DIVIDE(k.add_to_cart_events, k.product_views) * 100, 2) AS event_view_to_cart_rate,
  ROUND(SAFE_DIVIDE(k.checkout_starts, k.add_to_cart_events) * 100, 2) AS event_cart_to_checkout_rate,
  ROUND(SAFE_DIVIDE(k.purchasing_sessions, k.checkout_starts) * 100, 2) AS event_checkout_to_purchase_rate,

  ROUND(SAFE_DIVIDE(k.revenue, k.transactions), 2) AS average_order_value,
  ROUND(SAFE_DIVIDE(k.revenue, k.active_users), 2) AS revenue_per_active_user,
  ROUND(SAFE_DIVIDE(k.revenue, k.sessions), 2) AS revenue_per_session,

  ROUND(SAFE_DIVIDE(k.cart_abandoned_sessions, k.add_to_cart_events) * 100, 2) AS cart_abandonment_rate,
  ROUND(SAFE_DIVIDE(k.checkout_abandoned_sessions, k.checkout_starts) * 100, 2) AS checkout_abandonment_rate,

  s.buyers,
  s.repeat_buyers,
  s.high_intent_non_buyers,
  s.cart_abandoner_non_buyers,
  s.checkout_abandoner_non_buyers,
  ROUND(SAFE_DIVIDE(s.repeat_buyers, s.buyers) * 100, 2) AS repeat_buyer_rate

FROM
  kpi AS k
CROSS JOIN
  segments AS s;