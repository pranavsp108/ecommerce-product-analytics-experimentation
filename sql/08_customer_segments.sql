-- 08_customer_segments.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create business-readable customer segments from the modeling-ready user_features table.
--
-- Grain:
-- One row per user_pseudo_id.
--
-- This table supports:
-- 1. Customer segmentation dashboard
-- 2. High-intent non-buyer targeting
-- 3. Cart abandonment strategy
-- 4. Buyer lifecycle analysis
-- 5. Revenue/value tiering
-- 6. Business recommendation memo
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run 07_user_features.sql first.
--
-- Output tables:
-- 1. your_project_id.ecommerce_analytics.customer_segments
-- 2. your_project_id.ecommerce_analytics.mart_customer_segment_summary

--------------------------------------------------------------------------------
-- 1. USER-LEVEL CUSTOMER SEGMENTS
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.customer_segments`
PARTITION BY first_session_date
CLUSTER BY primary_customer_segment, value_tier, intent_tier, first_traffic_source
AS

WITH base AS (
  SELECT
    uf.*,

    -- Percentile thresholds used for value/engagement tiering.
    PERCENTILE_CONT(total_revenue, 0.90) OVER () AS p90_revenue,
    PERCENTILE_CONT(total_revenue, 0.75) OVER () AS p75_revenue,
    PERCENTILE_CONT(total_sessions, 0.75) OVER () AS p75_sessions,
    PERCENTILE_CONT(total_item_views, 0.75) OVER () AS p75_item_views,
    PERCENTILE_CONT(total_add_to_carts, 0.75) OVER () AS p75_add_to_carts,
    PERCENTILE_CONT(total_engagement_time_seconds, 0.75) OVER () AS p75_engagement_seconds

  FROM
    `ecommerce-product-analytics.ecommerce_analytics.user_features` AS uf
),

segmented AS (
  SELECT
    *,

    --------------------------------------------------------------------------
    -- Primary customer segment
    --------------------------------------------------------------------------
    CASE
      WHEN has_ever_purchased = 1
        AND total_revenue >= p90_revenue
        AND total_revenue > 0
      THEN 'high_value_customer'

      WHEN is_repeat_buyer = 1
      THEN 'repeat_buyer'

      WHEN has_ever_purchased = 1
        AND is_repeat_buyer = 0
      THEN 'one_time_buyer'

      WHEN has_ever_purchased = 0
        AND is_checkout_abandoner_non_buyer = 1
      THEN 'checkout_abandoner_non_buyer'

      WHEN has_ever_purchased = 0
        AND is_cart_abandoner_non_buyer = 1
      THEN 'cart_abandoner_non_buyer'

      WHEN has_ever_purchased = 0
        AND is_high_intent_non_buyer = 1
      THEN 'high_intent_non_buyer'

      WHEN has_ever_purchased = 0
        AND total_item_views >= p75_item_views
        AND total_item_views > 0
      THEN 'engaged_browser_non_buyer'

      WHEN has_ever_purchased = 0
        AND total_sessions >= 2
      THEN 'repeat_visitor_non_buyer'

      ELSE 'low_activity_user'
    END AS primary_customer_segment,

    --------------------------------------------------------------------------
    -- Intent tier
    --------------------------------------------------------------------------
    CASE
      WHEN has_ever_purchased = 1 THEN 'converted'
      WHEN total_checkouts_started > 0 THEN 'very_high_intent'
      WHEN total_add_to_carts > 0 THEN 'high_intent'
      WHEN total_item_views >= p75_item_views AND total_item_views > 0 THEN 'medium_intent'
      WHEN total_item_views > 0 THEN 'low_intent'
      ELSE 'minimal_intent'
    END AS intent_tier,

    --------------------------------------------------------------------------
    -- Value tier
    --------------------------------------------------------------------------
    CASE
      WHEN total_revenue >= p90_revenue AND total_revenue > 0 THEN 'top_10pct_value'
      WHEN total_revenue >= p75_revenue AND total_revenue > 0 THEN 'top_25pct_value'
      WHEN total_revenue > 0 THEN 'buyer_value'
      ELSE 'no_revenue'
    END AS value_tier,

    --------------------------------------------------------------------------
    -- Engagement tier
    --------------------------------------------------------------------------
    CASE
      WHEN total_sessions >= p75_sessions
        OR total_engagement_time_seconds >= p75_engagement_seconds
      THEN 'high_engagement'
      WHEN total_sessions >= 2
        OR total_item_views > 0
      THEN 'medium_engagement'
      ELSE 'low_engagement'
    END AS engagement_tier,

    --------------------------------------------------------------------------
    -- Recency tier
    -- Uses days_since_last_session relative to current date.
    -- Since this is demo data from 2020-2021, absolute recency is not business-realistic,
    -- but the field is still useful for demonstrating recency logic.
    --------------------------------------------------------------------------
    CASE
      WHEN days_since_last_session <= 30 THEN 'active_last_30_days'
      WHEN days_since_last_session <= 90 THEN 'active_last_90_days'
      WHEN days_since_last_session <= 180 THEN 'active_last_180_days'
      ELSE 'inactive_long_term'
    END AS recency_tier,

    --------------------------------------------------------------------------
    -- Buyer lifecycle tier
    --------------------------------------------------------------------------
    CASE
      WHEN total_transactions >= 3 THEN 'loyal_multi_buyer'
      WHEN total_transactions = 2 THEN 'early_repeat_buyer'
      WHEN total_transactions = 1 THEN 'one_time_buyer'
      ELSE 'non_buyer'
    END AS buyer_lifecycle_tier,

    --------------------------------------------------------------------------
    -- Recommended business action
    --------------------------------------------------------------------------
    CASE
      WHEN has_ever_purchased = 1
        AND total_revenue >= p90_revenue
        AND total_revenue > 0
      THEN 'protect_and_retain_vip_customers'

      WHEN is_repeat_buyer = 1
      THEN 'promote_loyalty_and_cross_sell'

      WHEN has_ever_purchased = 1
        AND is_repeat_buyer = 0
      THEN 'drive_second_purchase'

      WHEN has_ever_purchased = 0
        AND total_checkouts_started > 0
      THEN 'recover_checkout_abandonment'

      WHEN has_ever_purchased = 0
        AND total_add_to_carts > 0
      THEN 'recover_cart_abandonment'

      WHEN has_ever_purchased = 0
        AND total_item_views >= p75_item_views
        AND total_item_views > 0
      THEN 'personalize_product_recommendations'

      WHEN has_ever_purchased = 0
        AND total_sessions >= 2
      THEN 'nurture_repeat_visitors'

      ELSE 'low_priority_generic_awareness'
    END AS recommended_action,

    --------------------------------------------------------------------------
    -- Campaign targeting priority
    --------------------------------------------------------------------------
    CASE
      WHEN has_ever_purchased = 0
        AND total_checkouts_started > 0
      THEN 1

      WHEN has_ever_purchased = 0
        AND total_add_to_carts > 0
      THEN 2

      WHEN has_ever_purchased = 1
        AND is_repeat_buyer = 0
      THEN 3

      WHEN is_repeat_buyer = 1
      THEN 4

      WHEN has_ever_purchased = 0
        AND total_item_views >= p75_item_views
        AND total_item_views > 0
      THEN 5

      ELSE 9
    END AS targeting_priority_rank

  FROM base
),

final AS (
  SELECT
    user_pseudo_id,

    -- Time/cohort
    first_session_date,
    first_session_month,
    first_purchase_date,
    first_purchase_month,
    last_session_date,
    last_purchase_date,
    days_since_last_session,
    days_since_last_purchase,
    observed_lifespan_days,

    -- Acquisition/source/device
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country,
    last_device_category,
    last_traffic_source,
    last_traffic_medium,

    -- Product preferences
    first_primary_item_category,
    favorite_session_category,
    favorite_view_category,
    favorite_cart_category,
    favorite_purchase_category,
    last_primary_item_category,
    most_common_session_category,

    -- Original lifecycle
    lifecycle_segment,

    -- New segmentation
    primary_customer_segment,
    intent_tier,
    value_tier,
    engagement_tier,
    recency_tier,
    buyer_lifecycle_tier,
    recommended_action,
    targeting_priority_rank,

    -- Core behavior metrics
    total_sessions,
    active_days,
    total_events,
    total_page_views,
    total_item_views,
    total_add_to_carts,
    total_cart_views,
    total_checkouts_started,
    total_purchase_events,
    total_transactions,
    total_revenue,

    sessions_with_product_view,
    sessions_with_add_to_cart,
    sessions_with_checkout,
    purchasing_sessions,
    cart_abandoned_sessions,
    checkout_abandoned_sessions,
    bounce_like_sessions,

    -- Product breadth
    distinct_item_categories_interacted,
    distinct_items_interacted,
    total_distinct_item_interactions,
    total_distinct_category_interactions,

    -- Engagement / rate metrics
    total_engagement_time_seconds,
    avg_engagement_time_seconds_per_session,
    avg_session_duration_seconds,
    events_per_session,
    page_views_per_session,
    item_views_per_session,
    add_to_carts_per_session,
    checkouts_per_session,

    pct_sessions_with_product_view,
    user_view_to_cart_session_rate,
    user_cart_to_checkout_session_rate,
    user_checkout_to_purchase_session_rate,
    user_session_purchase_rate,
    user_cart_abandonment_rate,
    user_checkout_abandonment_rate,
    user_bounce_like_rate,

    -- Monetary metrics
    avg_order_value,
    revenue_per_session,
    revenue_per_active_day,
    transactions_per_session,

    -- Flags
    has_ever_purchased,
    is_repeat_buyer,
    is_repeat_visitor,
    is_high_intent_non_buyer,
    is_cart_abandoner_non_buyer,
    is_checkout_abandoner_non_buyer,
    is_top_10pct_revenue_customer,

    -- Labels for later modeling
    label_ever_purchased,
    label_repeat_buyer

  FROM segmented
)

SELECT
  *
FROM final;


--------------------------------------------------------------------------------
-- 2. SEGMENT SUMMARY MART
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.mart_customer_segment_summary`
CLUSTER BY primary_customer_segment, recommended_action, intent_tier, value_tier
AS

WITH segment_summary AS (
  SELECT
    primary_customer_segment,
    recommended_action,
    targeting_priority_rank,
    intent_tier,
    value_tier,
    engagement_tier,
    buyer_lifecycle_tier,

    COUNT(*) AS users,
    COUNTIF(has_ever_purchased = 1) AS buyers,
    COUNTIF(is_repeat_buyer = 1) AS repeat_buyers,
    COUNTIF(is_high_intent_non_buyer = 1) AS high_intent_non_buyers,
    COUNTIF(is_cart_abandoner_non_buyer = 1) AS cart_abandoner_non_buyers,
    COUNTIF(is_checkout_abandoner_non_buyer = 1) AS checkout_abandoner_non_buyers,

    SUM(total_sessions) AS sessions,
    SUM(total_item_views) AS item_views,
    SUM(total_add_to_carts) AS add_to_carts,
    SUM(total_checkouts_started) AS checkout_starts,
    SUM(total_transactions) AS transactions,
    ROUND(SUM(total_revenue), 2) AS revenue,

    ROUND(AVG(total_sessions), 2) AS avg_sessions_per_user,
    ROUND(AVG(total_item_views), 2) AS avg_item_views_per_user,
    ROUND(AVG(total_add_to_carts), 2) AS avg_add_to_carts_per_user,
    ROUND(AVG(total_revenue), 2) AS avg_revenue_per_user,
    ROUND(AVG(avg_order_value), 2) AS avg_order_value,

    ROUND(SAFE_DIVIDE(COUNTIF(has_ever_purchased = 1), COUNT(*)) * 100, 2) AS buyer_rate,
    ROUND(SAFE_DIVIDE(COUNTIF(is_repeat_buyer = 1), COUNTIF(has_ever_purchased = 1)) * 100, 2) AS repeat_buyer_rate,
    ROUND(SAFE_DIVIDE(SUM(total_revenue), COUNT(*)), 2) AS revenue_per_segment_user,
    ROUND(SAFE_DIVIDE(SUM(total_transactions), COUNT(*)), 2) AS transactions_per_segment_user

  FROM
    `ecommerce-product-analytics.ecommerce_analytics.customer_segments`
  GROUP BY
    primary_customer_segment,
    recommended_action,
    targeting_priority_rank,
    intent_tier,
    value_tier,
    engagement_tier,
    buyer_lifecycle_tier
),

overall AS (
  SELECT
    COUNT(*) AS total_users,
    ROUND(SUM(total_revenue), 2) AS total_revenue
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.customer_segments`
)

SELECT
  s.*,
  ROUND(SAFE_DIVIDE(s.users, o.total_users) * 100, 2) AS pct_of_users,
  ROUND(SAFE_DIVIDE(s.revenue, o.total_revenue) * 100, 2) AS pct_of_revenue
FROM
  segment_summary AS s
CROSS JOIN
  overall AS o
ORDER BY
  targeting_priority_rank,
  users DESC;