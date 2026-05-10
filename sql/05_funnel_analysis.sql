-- 05_funnel_analysis.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create dashboard-ready funnel analysis tables from the session and item staging layers.
--
-- Outputs:
-- 1. your_project_id.ecommerce_analytics.mart_funnel_sessions
--    Grain: one row per date, device, source, medium, campaign, and session user type.
--
-- 2. your_project_id.ecommerce_analytics.mart_funnel_categories
--    Grain: one row per date, device, source, medium, and product category.
--
-- These tables support:
-- 1. Session-level funnel analysis
-- 2. Drop-off analysis by device and traffic source
-- 3. New vs returning user funnel comparison
-- 4. Product/category funnel analysis
-- 5. Tableau dashboard funnel visuals
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run 01_stg_events.sql
-- 3. Run 02_stg_items.sql
-- 4. Run 03_int_sessions.sql
-- 5. Run 04_mart_product_kpis.sql

--------------------------------------------------------------------------------
-- 1. SESSION-LEVEL FUNNEL MART
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.mart_funnel_sessions`
PARTITION BY funnel_date
CLUSTER BY device_category, traffic_source, traffic_medium, session_user_type
AS

WITH funnel_base AS (
  SELECT
    session_start_date AS funnel_date,
    device_category,
    traffic_source,
    traffic_medium,
    traffic_campaign,
    session_user_type,

    COUNT(*) AS sessions,

    -- Funnel step counts
    SUM(CASE WHEN had_session_start = 1 OR had_page_view = 1 THEN 1 ELSE 0 END) AS step_1_sessions_or_page_views,
    SUM(had_view_item) AS step_2_product_view_sessions,
    SUM(had_add_to_cart) AS step_3_add_to_cart_sessions,
    SUM(had_begin_checkout) AS step_4_checkout_sessions,
    SUM(had_purchase) AS step_5_purchase_sessions,

    -- Drop-off / abandonment counts
    SUM(CASE WHEN (had_session_start = 1 OR had_page_view = 1) AND had_view_item = 0 THEN 1 ELSE 0 END) AS drop_after_session_or_page_view,
    SUM(CASE WHEN had_view_item = 1 AND had_add_to_cart = 0 THEN 1 ELSE 0 END) AS drop_after_product_view,
    SUM(CASE WHEN had_add_to_cart = 1 AND had_begin_checkout = 0 THEN 1 ELSE 0 END) AS drop_after_add_to_cart,
    SUM(CASE WHEN had_begin_checkout = 1 AND had_purchase = 0 THEN 1 ELSE 0 END) AS drop_after_checkout,

    -- Supporting behavior metrics
    -- Supporting behavior metrics
    SUM(item_views) AS product_view_events,     -- Changed from product_views
    SUM(add_to_carts) AS add_to_cart_events,    -- This one looks correct in your list
    SUM(checkouts_started) AS checkout_events,
    SUM(purchases) AS purchase_events,
    SUM(transactions) AS transactions,
    ROUND(SUM(session_revenue), 2) AS revenue,

    -- Engagement context
    SUM(total_events) AS total_events,
    ROUND(AVG(session_duration_seconds), 2) AS avg_session_duration_seconds,
    ROUND(AVG(total_engagement_time_seconds), 2) AS avg_engagement_time_seconds,
    SUM(is_bounce_like_session) AS bounce_like_sessions,
    SUM(is_cart_abandoned_session) AS cart_abandoned_sessions,
    SUM(is_checkout_abandoned_session) AS checkout_abandoned_sessions

  FROM
    `ecommerce-product-analytics.ecommerce_analytics.int_sessions`
  GROUP BY
    funnel_date,
    device_category,
    traffic_source,
    traffic_medium,
    traffic_campaign,
    session_user_type
),

funnel_rates AS (
  SELECT
    *,

    -- Step conversion rates
    ROUND(SAFE_DIVIDE(step_2_product_view_sessions, step_1_sessions_or_page_views) * 100, 2) AS session_to_product_view_rate,
    ROUND(SAFE_DIVIDE(step_3_add_to_cart_sessions, step_2_product_view_sessions) * 100, 2) AS product_view_to_cart_rate,
    ROUND(SAFE_DIVIDE(step_4_checkout_sessions, step_3_add_to_cart_sessions) * 100, 2) AS cart_to_checkout_rate,
    ROUND(SAFE_DIVIDE(step_5_purchase_sessions, step_4_checkout_sessions) * 100, 2) AS checkout_to_purchase_rate,

    -- Overall conversion rates
    ROUND(SAFE_DIVIDE(step_5_purchase_sessions, sessions) * 100, 2) AS session_to_purchase_rate,
    ROUND(SAFE_DIVIDE(step_5_purchase_sessions, step_2_product_view_sessions) * 100, 2) AS product_view_to_purchase_rate,

    -- Drop-off rates
    ROUND(SAFE_DIVIDE(drop_after_session_or_page_view, step_1_sessions_or_page_views) * 100, 2) AS drop_rate_after_session_or_page_view,
    ROUND(SAFE_DIVIDE(drop_after_product_view, step_2_product_view_sessions) * 100, 2) AS drop_rate_after_product_view,
    ROUND(SAFE_DIVIDE(drop_after_add_to_cart, step_3_add_to_cart_sessions) * 100, 2) AS drop_rate_after_add_to_cart,
    ROUND(SAFE_DIVIDE(drop_after_checkout, step_4_checkout_sessions) * 100, 2) AS drop_rate_after_checkout,

    -- Business efficiency metrics
    ROUND(SAFE_DIVIDE(revenue, step_5_purchase_sessions), 2) AS revenue_per_purchasing_session,
    ROUND(SAFE_DIVIDE(revenue, sessions), 2) AS revenue_per_session,
    ROUND(SAFE_DIVIDE(revenue, transactions), 2) AS average_order_value,

    -- Abandonment rates
    ROUND(SAFE_DIVIDE(cart_abandoned_sessions, step_3_add_to_cart_sessions) * 100, 2) AS cart_abandonment_rate,
    ROUND(SAFE_DIVIDE(checkout_abandoned_sessions, step_4_checkout_sessions) * 100, 2) AS checkout_abandonment_rate,
    ROUND(SAFE_DIVIDE(bounce_like_sessions, sessions) * 100, 2) AS bounce_like_rate,

    -- Date helper fields for Tableau
    FORMAT_DATE('%Y-%m', funnel_date) AS funnel_month,
    EXTRACT(WEEK FROM funnel_date) AS funnel_week,
    EXTRACT(DAYOFWEEK FROM funnel_date) AS funnel_day_of_week

  FROM funnel_base
)

SELECT
  *
FROM funnel_rates;


--------------------------------------------------------------------------------
-- 2. PRODUCT CATEGORY FUNNEL MART
--------------------------------------------------------------------------------
-- Note:
-- Category-level funnel analysis is event/item based, not true user journey attribution.
-- It answers: "For item interactions in a category, how often do we observe views,
-- carts, checkouts, and purchases?" This is useful for merchandising and category
-- performance, but should be interpreted separately from session-level funnel conversion.

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.mart_funnel_categories`
PARTITION BY funnel_date
CLUSTER BY item_category, device_category, traffic_source, traffic_medium
AS

WITH category_base AS (
  SELECT
    event_date AS funnel_date,
    clean_item_category AS item_category,
    device_category,
    traffic_source,
    traffic_medium,

    COUNT(*) AS item_event_rows,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT session_key) AS sessions,
    COUNT(DISTINCT clean_item_id) AS unique_items,

    -- Item event funnel counts
    COUNTIF(event_name = 'view_item') AS item_views,
    COUNTIF(event_name = 'select_item') AS item_selects,
    COUNTIF(event_name = 'add_to_cart') AS item_add_to_carts,
    COUNTIF(event_name = 'remove_from_cart') AS item_removes_from_cart,
    COUNTIF(event_name = 'begin_checkout') AS item_checkout_events,
    COUNTIF(event_name = 'purchase') AS item_purchase_events,

    -- Users/sessions reaching item-level category stages
    COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN user_pseudo_id END) AS users_viewed_category,
    COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN user_pseudo_id END) AS users_added_category_to_cart,
    COUNT(DISTINCT CASE WHEN event_name = 'begin_checkout' THEN user_pseudo_id END) AS users_started_checkout_with_category,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END) AS users_purchased_category,

    COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN session_key END) AS sessions_viewed_category,
    COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_key END) AS sessions_added_category_to_cart,
    COUNT(DISTINCT CASE WHEN event_name = 'begin_checkout' THEN session_key END) AS sessions_started_checkout_with_category,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_key END) AS sessions_purchased_category,

    -- Revenue
    ROUND(SUM(CASE WHEN event_name = 'purchase' THEN estimated_item_revenue ELSE 0 END), 2) AS category_item_revenue,
    SUM(CASE WHEN event_name = 'purchase' THEN item_quantity ELSE 0 END) AS category_quantity_purchased

  FROM
    `ecommerce-product-analytics.ecommerce_analytics.stg_items`
  GROUP BY
    funnel_date,
    item_category,
    device_category,
    traffic_source,
    traffic_medium
),

category_rates AS (
  SELECT
    *,

    -- Event-level category rates
    ROUND(SAFE_DIVIDE(item_add_to_carts, item_views) * 100, 2) AS item_view_to_cart_rate,
    ROUND(SAFE_DIVIDE(item_checkout_events, item_add_to_carts) * 100, 2) AS item_cart_to_checkout_rate,
    ROUND(SAFE_DIVIDE(item_purchase_events, item_checkout_events) * 100, 2) AS item_checkout_to_purchase_rate,
    ROUND(SAFE_DIVIDE(item_purchase_events, item_views) * 100, 2) AS item_view_to_purchase_rate,

    -- User-level category rates
    ROUND(SAFE_DIVIDE(users_added_category_to_cart, users_viewed_category) * 100, 2) AS user_category_view_to_cart_rate,
    ROUND(SAFE_DIVIDE(users_started_checkout_with_category, users_added_category_to_cart) * 100, 2) AS user_category_cart_to_checkout_rate,
    ROUND(SAFE_DIVIDE(users_purchased_category, users_started_checkout_with_category) * 100, 2) AS user_category_checkout_to_purchase_rate,
    ROUND(SAFE_DIVIDE(users_purchased_category, users_viewed_category) * 100, 2) AS user_category_view_to_purchase_rate,

    -- Revenue efficiency
    ROUND(SAFE_DIVIDE(category_item_revenue, users_purchased_category), 2) AS revenue_per_category_buyer,
    ROUND(SAFE_DIVIDE(category_item_revenue, sessions_purchased_category), 2) AS revenue_per_purchasing_category_session,
    ROUND(SAFE_DIVIDE(category_item_revenue, item_purchase_events), 2) AS revenue_per_item_purchase_event,

    -- Date helper fields for Tableau
    FORMAT_DATE('%Y-%m', funnel_date) AS funnel_month,
    EXTRACT(WEEK FROM funnel_date) AS funnel_week,
    EXTRACT(DAYOFWEEK FROM funnel_date) AS funnel_day_of_week

  FROM category_base
)

SELECT
  *
FROM category_rates;