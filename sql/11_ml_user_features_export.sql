-- 11_ml_user_features_export.sql
-- Purchase propensity modeling export

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.ml_user_features` AS

SELECT
  user_pseudo_id,

  -- Target
  label_ever_purchased,

  -- Optional secondary target
  label_repeat_buyer,

  -- User timing / recency
  first_session_date,
  last_session_date,
  days_since_last_session,
  observed_lifespan_days,

  -- First-touch attributes
  first_device_category,
  first_traffic_source,
  first_traffic_medium,
  first_traffic_campaign,
  first_country,

  -- Category behavior
  first_primary_item_category,
  favorite_session_category,
  favorite_view_category,
  favorite_cart_category,
  favorite_purchase_category,
  most_common_session_category,

  -- Existing behavior-derived segments / tiers
  lifecycle_segment,
  primary_customer_segment,
  intent_tier,
  value_tier,
  engagement_tier,
  recency_tier,
  buyer_lifecycle_tier,

  -- Volume features
  total_sessions,
  active_days,
  total_events,
  total_page_views,
  total_item_views,
  total_add_to_carts,
  total_cart_views,
  total_checkouts_started,
  sessions_with_product_view,
  sessions_with_add_to_cart,
  sessions_with_checkout,
  cart_abandoned_sessions,
  checkout_abandoned_sessions,
  bounce_like_sessions,

  -- Diversity / depth
  distinct_item_categories_interacted,
  distinct_items_interacted,
  total_distinct_item_interactions,
  total_distinct_category_interactions,

  -- Engagement features
  total_engagement_time_seconds,
  avg_engagement_time_seconds_per_session,
  avg_session_duration_seconds,
  events_per_session,
  page_views_per_session,
  item_views_per_session,
  add_to_carts_per_session,
  checkouts_per_session,

  -- Funnel/session rates
  pct_sessions_with_product_view,
  user_view_to_cart_session_rate,
  user_cart_to_checkout_session_rate,
  user_checkout_to_purchase_session_rate,
  user_cart_abandonment_rate,
  user_checkout_abandonment_rate,
  user_bounce_like_rate,

  -- Revenue features: keep for scoring/explainability, but exclude from first purchase model if leakage risk
  total_revenue,
  avg_order_value,
  revenue_per_session,
  revenue_per_active_day,
  total_transactions,
  transactions_per_session,

  -- Flags
  is_repeat_visitor,
  is_high_intent_non_buyer,
  is_cart_abandoner_non_buyer,
  is_checkout_abandoner_non_buyer,
  is_top_10pct_revenue_customer

FROM
  `ecommerce-product-analytics.ecommerce_analytics.customer_segments_fixed`;