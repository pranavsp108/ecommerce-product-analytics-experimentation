-- 04_mart_product_kpis.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create a daily product KPI mart for executive dashboarding and business reporting.
--
-- Grain:
-- One row per date, device category, traffic source, traffic medium, and user type.
--
-- This table supports:
-- 1. Product KPI dashboard
-- 2. Revenue and conversion trend analysis
-- 3. Device performance analysis
-- 4. Traffic source performance analysis
-- 5. New vs returning session comparison
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run 01_stg_events.sql
-- 3. Run 02_stg_items.sql
-- 4. Run 03_int_sessions.sql
--
-- Output table:
-- your_project_id.ecommerce_analytics.mart_product_kpis

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.mart_product_kpis`
PARTITION BY metric_date
CLUSTER BY device_category, traffic_source, traffic_medium, session_user_type
AS

WITH session_kpis AS (
  SELECT
    session_start_date AS metric_date,
    device_category,
    traffic_source,
    traffic_medium,
    traffic_campaign,
    session_user_type,

    -- Volume metrics
    COUNT(*) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS active_users,

    -- Engagement metrics
    SUM(total_events) AS total_events,
    SUM(page_views) AS page_views,
    SUM(item_views) AS product_views,
    SUM(add_to_carts) AS add_to_cart_events,
    SUM(cart_views) AS cart_views,
    SUM(checkouts_started) AS checkout_starts,
    SUM(payment_info_events) AS payment_info_events,
    SUM(purchases) AS purchase_events,

    -- Session-level funnel counts
    SUM(had_view_item) AS sessions_with_product_view,
    SUM(had_add_to_cart) AS sessions_with_add_to_cart,
    SUM(had_begin_checkout) AS sessions_with_checkout,
    SUM(had_purchase) AS purchasing_sessions,

    -- Abandonment counts
    SUM(is_cart_abandoned_session) AS cart_abandoned_sessions,
    SUM(is_checkout_abandoned_session) AS checkout_abandoned_sessions,
    SUM(is_bounce_like_session) AS bounce_like_sessions,

    -- Revenue metrics
    SUM(transactions) AS transactions,
    ROUND(SUM(session_revenue), 2) AS revenue,
    SUM(purchased_item_quantity) AS purchased_item_quantity,
    SUM(purchased_unique_items) AS purchased_unique_items,

    -- Item interaction metrics from session table
    SUM(distinct_items_interacted) AS total_distinct_item_interactions,
    SUM(distinct_categories_interacted) AS total_distinct_category_interactions,

    -- Engagement time
    ROUND(SUM(total_engagement_time_seconds), 2) AS total_engagement_time_seconds,
    ROUND(AVG(total_engagement_time_seconds), 2) AS avg_engagement_time_seconds_per_session,
    ROUND(AVG(session_duration_seconds), 2) AS avg_session_duration_seconds,

    -- Segment-ish useful counts
    COUNTIF(max_funnel_stage = '01_session_or_page_view') AS sessions_ending_at_session_or_page_view,
    COUNTIF(max_funnel_stage = '02_view_item') AS sessions_ending_at_view_item,
    COUNTIF(max_funnel_stage = '03_add_to_cart') AS sessions_ending_at_add_to_cart,
    COUNTIF(max_funnel_stage = '04_begin_checkout') AS sessions_ending_at_begin_checkout,
    COUNTIF(max_funnel_stage = '05_purchase') AS sessions_ending_at_purchase

  FROM
    `ecommerce-product-analytics.ecommerce_analytics.int_sessions`
  GROUP BY
    metric_date,
    device_category,
    traffic_source,
    traffic_medium,
    traffic_campaign,
    session_user_type
),

final AS (
  SELECT
    *,

    -- Conversion rates
    ROUND(SAFE_DIVIDE(purchasing_sessions, sessions) * 100, 2) AS session_purchase_conversion_rate,
    ROUND(SAFE_DIVIDE(sessions_with_product_view, sessions) * 100, 2) AS product_view_session_rate,
    ROUND(SAFE_DIVIDE(sessions_with_add_to_cart, sessions_with_product_view) * 100, 2) AS view_to_cart_session_rate,
    ROUND(SAFE_DIVIDE(sessions_with_checkout, sessions_with_add_to_cart) * 100, 2) AS cart_to_checkout_session_rate,
    ROUND(SAFE_DIVIDE(purchasing_sessions, sessions_with_checkout) * 100, 2) AS checkout_to_purchase_session_rate,
    ROUND(SAFE_DIVIDE(purchasing_sessions, sessions_with_product_view) * 100, 2) AS view_to_purchase_session_rate,

    -- Abandonment rates
    ROUND(SAFE_DIVIDE(cart_abandoned_sessions, sessions_with_add_to_cart) * 100, 2) AS cart_abandonment_rate,
    ROUND(SAFE_DIVIDE(checkout_abandoned_sessions, sessions_with_checkout) * 100, 2) AS checkout_abandonment_rate,
    ROUND(SAFE_DIVIDE(bounce_like_sessions, sessions) * 100, 2) AS bounce_like_session_rate,

    -- Revenue efficiency
    ROUND(SAFE_DIVIDE(revenue, transactions), 2) AS average_order_value,
    ROUND(SAFE_DIVIDE(revenue, active_users), 2) AS revenue_per_active_user,
    ROUND(SAFE_DIVIDE(revenue, sessions), 2) AS revenue_per_session,
    ROUND(SAFE_DIVIDE(transactions, active_users), 2) AS transactions_per_active_user,

    -- Engagement efficiency
    ROUND(SAFE_DIVIDE(total_events, sessions), 2) AS events_per_session,
    ROUND(SAFE_DIVIDE(product_views, sessions), 2) AS product_views_per_session,
    ROUND(SAFE_DIVIDE(add_to_cart_events, sessions), 2) AS add_to_cart_events_per_session,
    ROUND(SAFE_DIVIDE(checkout_starts, sessions), 2) AS checkout_starts_per_session,

    -- Dashboard helper fields
    FORMAT_DATE('%Y-%m', metric_date) AS metric_month,
    EXTRACT(DAYOFWEEK FROM metric_date) AS metric_day_of_week,
    EXTRACT(WEEK FROM metric_date) AS metric_week

  FROM session_kpis
)

SELECT
  *
FROM final;