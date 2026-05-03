-- 07_user_features.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create a modeling-ready and segmentation-ready user feature table.
--
-- Grain:
-- One row per user_pseudo_id.
--
-- This table supports:
-- 1. Customer segmentation
-- 2. RFM-style analysis
-- 3. Purchase propensity modeling
-- 4. High-intent non-buyer detection
-- 5. Cart abandonment targeting
-- 6. Product/category preference analysis
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run 01_stg_events.sql
-- 3. Run 02_stg_items.sql
-- 4. Run 03_int_sessions.sql
-- 5. Run 06_cohort_retention.sql
--
-- Output table:
-- your_project_id.ecommerce_analytics.user_features

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.user_features`
PARTITION BY first_session_date
CLUSTER BY lifecycle_segment, first_traffic_source, first_device_category, has_ever_purchased
AS

WITH sessions AS (
  SELECT
    *
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.int_sessions`
  WHERE
    user_pseudo_id IS NOT NULL
),

user_lifecycle AS (
  SELECT
    *
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.mart_user_lifecycle_summary`
),

session_agg AS (
  SELECT
    user_pseudo_id,

    -- Session and activity volume
    COUNT(DISTINCT session_key) AS total_sessions,
    COUNT(DISTINCT session_start_date) AS active_days,
    MIN(session_start_date) AS first_session_date,
    MAX(session_start_date) AS last_session_date,

    -- Time span
    DATE_DIFF(MAX(session_start_date), MIN(session_start_date), DAY) AS observed_lifespan_days,

    -- Activity/event totals
    SUM(total_events) AS total_events,
    SUM(page_views) AS total_page_views,
    SUM(item_views) AS total_item_views,
    SUM(item_selects) AS total_item_selects,
    SUM(add_to_carts) AS total_add_to_carts,
    SUM(removes_from_cart) AS total_removes_from_cart,
    SUM(cart_views) AS total_cart_views,
    SUM(checkouts_started) AS total_checkouts_started,
    SUM(shipping_info_events) AS total_shipping_info_events,
    SUM(payment_info_events) AS total_payment_info_events,
    SUM(purchases) AS total_purchase_events,

    -- Session-level funnel flags
    SUM(had_view_item) AS sessions_with_product_view,
    SUM(had_add_to_cart) AS sessions_with_add_to_cart,
    SUM(had_begin_checkout) AS sessions_with_checkout,
    SUM(had_purchase) AS purchasing_sessions,

    -- Abandonment behavior
    SUM(is_cart_abandoned_session) AS cart_abandoned_sessions,
    SUM(is_checkout_abandoned_session) AS checkout_abandoned_sessions,
    SUM(is_bounce_like_session) AS bounce_like_sessions,

    -- Revenue and transaction behavior
    SUM(transactions) AS total_transactions,
    ROUND(SUM(session_revenue), 2) AS total_revenue,
    SUM(purchased_item_quantity) AS total_purchased_item_quantity,
    SUM(purchased_unique_items) AS total_purchased_unique_items,

    -- Engagement behavior
    ROUND(SUM(total_engagement_time_seconds), 2) AS total_engagement_time_seconds,
    ROUND(AVG(total_engagement_time_seconds), 2) AS avg_engagement_time_seconds_per_session,
    ROUND(AVG(session_duration_seconds), 2) AS avg_session_duration_seconds,

    -- Product/category interaction
    SUM(item_event_rows) AS total_item_event_rows,
    SUM(distinct_items_interacted) AS total_distinct_item_interactions,
    SUM(distinct_categories_interacted) AS total_distinct_category_interactions,
    SUM(item_view_rows) AS total_item_view_rows,
    SUM(item_add_to_cart_rows) AS total_item_add_to_cart_rows,
    SUM(item_purchase_rows) AS total_item_purchase_rows,

    -- Device/source diversity
    COUNT(DISTINCT device_category) AS distinct_device_categories_used,
    COUNT(DISTINCT traffic_source) AS distinct_traffic_sources,
    COUNT(DISTINCT traffic_medium) AS distinct_traffic_mediums,

    -- Most recent session context
    ARRAY_AGG(device_category ORDER BY session_start_ts DESC LIMIT 1)[SAFE_OFFSET(0)] AS last_device_category,
    ARRAY_AGG(traffic_source ORDER BY session_start_ts DESC LIMIT 1)[SAFE_OFFSET(0)] AS last_traffic_source,
    ARRAY_AGG(traffic_medium ORDER BY session_start_ts DESC LIMIT 1)[SAFE_OFFSET(0)] AS last_traffic_medium,
    ARRAY_AGG(primary_item_category ORDER BY session_start_ts DESC LIMIT 1)[SAFE_OFFSET(0)] AS last_primary_item_category,

    -- Most common session category
    ARRAY_AGG(primary_item_category ORDER BY category_session_count DESC, primary_item_category LIMIT 1)[SAFE_OFFSET(0)] AS most_common_session_category

  FROM (
    SELECT
      s.*,
      COUNT(*) OVER (PARTITION BY user_pseudo_id, primary_item_category) AS category_session_count
    FROM
      sessions AS s
  )
  GROUP BY
    user_pseudo_id
),

item_category_agg AS (
  SELECT
    user_pseudo_id,

    -- Favorite category based on item views
    ARRAY_AGG(clean_item_category ORDER BY item_views DESC, clean_item_category LIMIT 1)[SAFE_OFFSET(0)] AS favorite_view_category,

    -- Favorite category based on carts
    ARRAY_AGG(clean_item_category ORDER BY add_to_carts DESC, clean_item_category LIMIT 1)[SAFE_OFFSET(0)] AS favorite_cart_category,

    -- Favorite category based on purchases/revenue
    ARRAY_AGG(clean_item_category ORDER BY purchase_revenue DESC, clean_item_category LIMIT 1)[SAFE_OFFSET(0)] AS favorite_purchase_category,

    COUNT(DISTINCT clean_item_category) AS distinct_item_categories_interacted,
    COUNT(DISTINCT clean_item_id) AS distinct_items_interacted,

    SUM(item_views) AS category_item_views,
    SUM(add_to_carts) AS category_add_to_carts,
    SUM(purchases) AS category_purchases,
    ROUND(SUM(purchase_revenue), 2) AS category_purchase_revenue

  FROM (
    SELECT
      user_pseudo_id,
      clean_item_category,
      clean_item_id,

      COUNTIF(event_name = 'view_item') AS item_views,
      COUNTIF(event_name = 'add_to_cart') AS add_to_carts,
      COUNTIF(event_name = 'purchase') AS purchases,
      ROUND(SUM(CASE WHEN event_name = 'purchase' THEN estimated_item_revenue ELSE 0 END), 2) AS purchase_revenue

    FROM
      `ecommerce-product-analytics.ecommerce_analytics.stg_items`
    WHERE
      user_pseudo_id IS NOT NULL
      AND clean_item_category IS NOT NULL
      AND clean_item_category != 'unknown'
    GROUP BY
      user_pseudo_id,
      clean_item_category,
      clean_item_id
  )
  GROUP BY
    user_pseudo_id
),

recent_30_day_features AS (
  SELECT
    user_pseudo_id,

    COUNT(DISTINCT session_key) AS sessions_last_30_observed_days,
    SUM(item_views) AS item_views_last_30_observed_days,
    SUM(add_to_carts) AS add_to_carts_last_30_observed_days,
    SUM(checkouts_started) AS checkouts_last_30_observed_days,
    SUM(had_purchase) AS purchasing_sessions_last_30_observed_days,
    ROUND(SUM(session_revenue), 2) AS revenue_last_30_observed_days

  FROM
    sessions
  WHERE
    session_start_date >= (
      SELECT DATE_SUB(MAX(session_start_date), INTERVAL 30 DAY)
      FROM sessions
    )
  GROUP BY
    user_pseudo_id
),

final AS (
  SELECT
    s.user_pseudo_id,

    -- Lifecycle fields from previously built summary table
    l.first_session_date,
    l.first_session_month,
    l.first_device_category,
    l.first_traffic_source,
    l.first_traffic_medium,
    l.first_traffic_campaign,
    l.first_country,
    l.first_primary_item_category,

    l.first_purchase_date,
    l.first_purchase_month,
    l.favorite_session_category,
    l.lifecycle_segment,

    -- Activity features
    s.total_sessions,
    s.active_days,
    s.last_session_date,
    s.observed_lifespan_days,
    DATE_DIFF(CURRENT_DATE(), s.last_session_date, DAY) AS days_since_last_session,
    DATE_DIFF(CURRENT_DATE(), l.first_session_date, DAY) AS days_since_first_session,

    -- Purchase recency
    l.last_purchase_date,
    DATE_DIFF(CURRENT_DATE(), l.last_purchase_date, DAY) AS days_since_last_purchase,

    -- Totals
    s.total_events,
    s.total_page_views,
    s.total_item_views,
    s.total_item_selects,
    s.total_add_to_carts,
    s.total_removes_from_cart,
    s.total_cart_views,
    s.total_checkouts_started,
    s.total_shipping_info_events,
    s.total_payment_info_events,
    s.total_purchase_events,

    -- Funnel/session counts
    s.sessions_with_product_view,
    s.sessions_with_add_to_cart,
    s.sessions_with_checkout,
    s.purchasing_sessions,
    s.cart_abandoned_sessions,
    s.checkout_abandoned_sessions,
    s.bounce_like_sessions,

    -- Revenue
    s.total_transactions,
    s.total_revenue,
    s.total_purchased_item_quantity,
    s.total_purchased_unique_items,

    -- Engagement
    s.total_engagement_time_seconds,
    s.avg_engagement_time_seconds_per_session,
    s.avg_session_duration_seconds,

    -- Product interest
    s.total_item_event_rows,
    s.total_distinct_item_interactions,
    s.total_distinct_category_interactions,
    s.total_item_view_rows,
    s.total_item_add_to_cart_rows,
    s.total_item_purchase_rows,

    COALESCE(i.favorite_view_category, 'unknown') AS favorite_view_category,
    COALESCE(i.favorite_cart_category, 'unknown') AS favorite_cart_category,
    COALESCE(i.favorite_purchase_category, 'unknown') AS favorite_purchase_category,
    COALESCE(i.distinct_item_categories_interacted, 0) AS distinct_item_categories_interacted,
    COALESCE(i.distinct_items_interacted, 0) AS distinct_items_interacted,
    COALESCE(i.category_item_views, 0) AS item_level_views,
    COALESCE(i.category_add_to_carts, 0) AS item_level_add_to_carts,
    COALESCE(i.category_purchases, 0) AS item_level_purchases,
    COALESCE(i.category_purchase_revenue, 0) AS item_level_revenue,

    -- Source/device behavior
    s.distinct_device_categories_used,
    s.distinct_traffic_sources,
    s.distinct_traffic_mediums,
    s.last_device_category,
    s.last_traffic_source,
    s.last_traffic_medium,
    COALESCE(s.last_primary_item_category, 'unknown') AS last_primary_item_category,
    COALESCE(s.most_common_session_category, 'unknown') AS most_common_session_category,

    -- Recent observed-period features
    COALESCE(r.sessions_last_30_observed_days, 0) AS sessions_last_30_observed_days,
    COALESCE(r.item_views_last_30_observed_days, 0) AS item_views_last_30_observed_days,
    COALESCE(r.add_to_carts_last_30_observed_days, 0) AS add_to_carts_last_30_observed_days,
    COALESCE(r.checkouts_last_30_observed_days, 0) AS checkouts_last_30_observed_days,
    COALESCE(r.purchasing_sessions_last_30_observed_days, 0) AS purchasing_sessions_last_30_observed_days,
    COALESCE(r.revenue_last_30_observed_days, 0) AS revenue_last_30_observed_days,

    -- Derived rates: user-level behavior
    ROUND(SAFE_DIVIDE(s.total_events, s.total_sessions), 2) AS events_per_session,
    ROUND(SAFE_DIVIDE(s.total_page_views, s.total_sessions), 2) AS page_views_per_session,
    ROUND(SAFE_DIVIDE(s.total_item_views, s.total_sessions), 2) AS item_views_per_session,
    ROUND(SAFE_DIVIDE(s.total_add_to_carts, s.total_sessions), 2) AS add_to_carts_per_session,
    ROUND(SAFE_DIVIDE(s.total_checkouts_started, s.total_sessions), 2) AS checkouts_per_session,

    ROUND(SAFE_DIVIDE(s.sessions_with_product_view, s.total_sessions) * 100, 2) AS pct_sessions_with_product_view,
    ROUND(SAFE_DIVIDE(s.sessions_with_add_to_cart, s.sessions_with_product_view) * 100, 2) AS user_view_to_cart_session_rate,
    ROUND(SAFE_DIVIDE(s.sessions_with_checkout, s.sessions_with_add_to_cart) * 100, 2) AS user_cart_to_checkout_session_rate,
    ROUND(SAFE_DIVIDE(s.purchasing_sessions, s.sessions_with_checkout) * 100, 2) AS user_checkout_to_purchase_session_rate,
    ROUND(SAFE_DIVIDE(s.purchasing_sessions, s.total_sessions) * 100, 2) AS user_session_purchase_rate,

    ROUND(SAFE_DIVIDE(s.cart_abandoned_sessions, s.sessions_with_add_to_cart) * 100, 2) AS user_cart_abandonment_rate,
    ROUND(SAFE_DIVIDE(s.checkout_abandoned_sessions, s.sessions_with_checkout) * 100, 2) AS user_checkout_abandonment_rate,
    ROUND(SAFE_DIVIDE(s.bounce_like_sessions, s.total_sessions) * 100, 2) AS user_bounce_like_rate,

    -- Monetary features
    ROUND(SAFE_DIVIDE(s.total_revenue, s.total_transactions), 2) AS avg_order_value,
    ROUND(SAFE_DIVIDE(s.total_revenue, s.total_sessions), 2) AS revenue_per_session,
    ROUND(SAFE_DIVIDE(s.total_revenue, s.active_days), 2) AS revenue_per_active_day,
    ROUND(SAFE_DIVIDE(s.total_transactions, s.total_sessions), 2) AS transactions_per_session,

    -- Business-readable flags
    CASE WHEN s.total_transactions > 0 THEN 1 ELSE 0 END AS has_ever_purchased,
    CASE WHEN s.total_transactions >= 2 THEN 1 ELSE 0 END AS is_repeat_buyer,
    CASE WHEN s.total_sessions >= 2 THEN 1 ELSE 0 END AS is_repeat_visitor,

    CASE
      WHEN s.total_transactions = 0 AND s.sessions_with_add_to_cart > 0 THEN 1
      ELSE 0
    END AS is_high_intent_non_buyer,

    CASE
      WHEN s.total_transactions = 0 AND s.cart_abandoned_sessions > 0 THEN 1
      ELSE 0
    END AS is_cart_abandoner_non_buyer,

    CASE
      WHEN s.total_transactions = 0 AND s.sessions_with_checkout > 0 THEN 1
      ELSE 0
    END AS is_checkout_abandoner_non_buyer,

    CASE
      WHEN s.total_transactions > 0
        AND s.total_revenue >= PERCENTILE_CONT(s.total_revenue, 0.90) OVER ()
      THEN 1
      ELSE 0
    END AS is_top_10pct_revenue_customer,

    -- Modeling label candidates
    -- Label 1: whether user ever purchased. Useful for broad propensity classification.
    CASE WHEN s.total_transactions > 0 THEN 1 ELSE 0 END AS label_ever_purchased,

    -- Label 2: repeat purchase. Useful among buyers.
    CASE WHEN s.total_transactions >= 2 THEN 1 ELSE 0 END AS label_repeat_buyer

  FROM
    session_agg AS s
  LEFT JOIN
    user_lifecycle AS l
  USING
    (user_pseudo_id)
  LEFT JOIN
    item_category_agg AS i
  USING
    (user_pseudo_id)
  LEFT JOIN
    recent_30_day_features AS r
  USING
    (user_pseudo_id)
)

SELECT
  *
FROM final;