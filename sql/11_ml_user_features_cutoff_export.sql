-- 11_ml_user_features_cutoff_export.sql
-- Purchase propensity modeling using pre-cutoff behavior only.
-- Objective: predict whether a user purchases AFTER cutoff date
-- using only behavior observed BEFORE cutoff date.

DECLARE cutoff_date DATE DEFAULT DATE '2020-12-15';
DECLARE feature_start_date DATE DEFAULT DATE '2020-11-01';
DECLARE label_end_date DATE DEFAULT DATE '2021-01-31';

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.ml_user_features_cutoff` AS

WITH events_base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_dt,
    user_pseudo_id,
    event_timestamp,
    event_name,

    COALESCE(
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING),
      CONCAT(user_pseudo_id, '_', CAST(event_timestamp AS STRING))
    ) AS session_id,

    COALESCE(device.category, 'unknown') AS device_category,
    COALESCE(traffic_source.source, '(not set)') AS traffic_source,
    COALESCE(traffic_source.medium, '(not set)') AS traffic_medium,
    COALESCE(traffic_source.name, '(not set)') AS traffic_campaign,
    COALESCE(geo.country, '(not set)') AS country

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    PARSE_DATE('%Y%m%d', event_date)
      BETWEEN feature_start_date AND label_end_date
),

pre_cutoff_events AS (
  SELECT *
  FROM events_base
  WHERE event_dt < cutoff_date
),

post_cutoff_events AS (
  SELECT *
  FROM events_base
  WHERE event_dt >= cutoff_date
    AND event_dt <= label_end_date
),

pre_purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM pre_cutoff_events
  WHERE event_name = 'purchase'
),

eligible_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM pre_cutoff_events
  WHERE user_pseudo_id NOT IN (
    SELECT user_pseudo_id FROM pre_purchase_users
  )
),

future_labels AS (
  SELECT
    e.user_pseudo_id,
    MAX(CASE WHEN p.event_name = 'purchase' THEN 1 ELSE 0 END) AS label_future_purchase
  FROM eligible_users e
  LEFT JOIN post_cutoff_events p
    ON e.user_pseudo_id = p.user_pseudo_id
  GROUP BY e.user_pseudo_id
),

first_touch AS (
  SELECT
    user_pseudo_id,
    ARRAY_AGG(device_category ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS first_device_category,
    ARRAY_AGG(traffic_source ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS first_traffic_source,
    ARRAY_AGG(traffic_medium ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS first_traffic_medium,
    ARRAY_AGG(traffic_campaign ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS first_traffic_campaign,
    ARRAY_AGG(country ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS first_country
  FROM pre_cutoff_events
  WHERE user_pseudo_id IN (SELECT user_pseudo_id FROM eligible_users)
  GROUP BY user_pseudo_id
),

session_features AS (
  SELECT
    user_pseudo_id,
    session_id,

    MIN(event_dt) AS session_date,

    COUNT(*) AS session_events,
    COUNTIF(event_name = 'page_view') AS page_views,
    COUNTIF(event_name = 'view_item') AS item_views,
    COUNTIF(event_name = 'add_to_cart') AS add_to_carts,
    COUNTIF(event_name = 'view_cart') AS cart_views,
    COUNTIF(event_name = 'begin_checkout') AS checkouts_started,
    COUNTIF(event_name = 'select_item') AS item_selects,

    MAX(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END) AS session_has_page_view,
    MAX(CASE WHEN event_name = 'view_item' THEN 1 ELSE 0 END) AS session_has_product_view,
    MAX(CASE WHEN event_name = 'add_to_cart' THEN 1 ELSE 0 END) AS session_has_add_to_cart,
    MAX(CASE WHEN event_name = 'view_cart' THEN 1 ELSE 0 END) AS session_has_cart_view,
    MAX(CASE WHEN event_name = 'begin_checkout' THEN 1 ELSE 0 END) AS session_has_checkout

  FROM pre_cutoff_events
  WHERE user_pseudo_id IN (SELECT user_pseudo_id FROM eligible_users)
  GROUP BY user_pseudo_id, session_id
),

user_features AS (
  SELECT
    user_pseudo_id,

    MIN(session_date) AS first_session_date,
    MAX(session_date) AS last_session_date,

    DATE_DIFF(cutoff_date, MAX(session_date), DAY) AS days_since_last_session,
    DATE_DIFF(MAX(session_date), MIN(session_date), DAY) AS observed_lifespan_days,

    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT session_date) AS active_days,

    SUM(session_events) AS total_events,
    SUM(page_views) AS total_page_views,
    SUM(item_views) AS total_item_views,
    SUM(add_to_carts) AS total_add_to_carts,
    SUM(cart_views) AS total_cart_views,
    SUM(checkouts_started) AS total_checkouts_started,
    SUM(item_selects) AS total_item_selects,

    SUM(session_has_product_view) AS sessions_with_product_view,
    SUM(session_has_add_to_cart) AS sessions_with_add_to_cart,
    SUM(session_has_cart_view) AS sessions_with_cart_view,
    SUM(session_has_checkout) AS sessions_with_checkout,

    SUM(
      CASE
        WHEN session_has_add_to_cart = 1
         AND session_has_checkout = 0
        THEN 1 ELSE 0
      END
    ) AS cart_abandoned_sessions,

    SUM(
      CASE
        WHEN session_has_product_view = 0
         AND session_has_add_to_cart = 0
         AND session_has_checkout = 0
        THEN 1 ELSE 0
      END
    ) AS low_intent_sessions,

    ROUND(SAFE_DIVIDE(SUM(page_views), COUNT(DISTINCT session_id)), 4) AS page_views_per_session,
    ROUND(SAFE_DIVIDE(SUM(item_views), COUNT(DISTINCT session_id)), 4) AS item_views_per_session,
    ROUND(SAFE_DIVIDE(SUM(add_to_carts), COUNT(DISTINCT session_id)), 4) AS add_to_carts_per_session,
    ROUND(SAFE_DIVIDE(SUM(checkouts_started), COUNT(DISTINCT session_id)), 4) AS checkouts_per_session,
    ROUND(SAFE_DIVIDE(SUM(session_events), COUNT(DISTINCT session_id)), 4) AS events_per_session,

    ROUND(SAFE_DIVIDE(SUM(session_has_product_view), COUNT(DISTINCT session_id)), 4) AS pct_sessions_with_product_view,
    ROUND(SAFE_DIVIDE(SUM(session_has_add_to_cart), COUNT(DISTINCT session_id)), 4) AS pct_sessions_with_add_to_cart,
    ROUND(SAFE_DIVIDE(SUM(session_has_checkout), COUNT(DISTINCT session_id)), 4) AS pct_sessions_with_checkout,

    ROUND(SAFE_DIVIDE(SUM(session_has_add_to_cart), SUM(session_has_product_view)), 4) AS user_view_to_cart_session_rate,
    ROUND(SAFE_DIVIDE(SUM(session_has_checkout), SUM(session_has_add_to_cart)), 4) AS user_cart_to_checkout_session_rate,
    ROUND(SAFE_DIVIDE(
      SUM(CASE WHEN session_has_add_to_cart = 1 AND session_has_checkout = 0 THEN 1 ELSE 0 END),
      SUM(session_has_add_to_cart)
    ), 4) AS user_cart_abandonment_rate

  FROM session_features
  GROUP BY user_pseudo_id
),

item_events AS (
  SELECT
    e.user_pseudo_id,
    COALESCE(i.item_category, '(not set)') AS item_category,
    e.event_name,
    COUNT(*) AS item_event_count
  FROM pre_cutoff_events e,
    UNNEST(items) AS i
  WHERE e.user_pseudo_id IN (SELECT user_pseudo_id FROM eligible_users)
    AND e.event_name IN ('view_item', 'add_to_cart', 'begin_checkout')
  GROUP BY
    e.user_pseudo_id,
    item_category,
    e.event_name
),

favorite_categories AS (
  SELECT
    user_pseudo_id,

    ARRAY_AGG(
      IF(event_name = 'view_item', item_category, NULL)
      IGNORE NULLS
      ORDER BY item_event_count DESC
      LIMIT 1
    )[SAFE_OFFSET(0)] AS favorite_view_category,

    ARRAY_AGG(
      IF(event_name = 'add_to_cart', item_category, NULL)
      IGNORE NULLS
      ORDER BY item_event_count DESC
      LIMIT 1
    )[SAFE_OFFSET(0)] AS favorite_cart_category,

    COUNT(DISTINCT item_category) AS distinct_item_categories_interacted

  FROM item_events
  GROUP BY user_pseudo_id
)

SELECT
  u.user_pseudo_id,

  -- Target
  l.label_future_purchase,

  -- Dates
  u.first_session_date,
  u.last_session_date,
  u.days_since_last_session,
  u.observed_lifespan_days,

  -- First-touch dimensions
  f.first_device_category,
  f.first_traffic_source,
  f.first_traffic_medium,
  f.first_traffic_campaign,
  f.first_country,

  -- Category features
  COALESCE(c.favorite_view_category, '(not set)') AS favorite_view_category,
  COALESCE(c.favorite_cart_category, '(not set)') AS favorite_cart_category,
  COALESCE(c.distinct_item_categories_interacted, 0) AS distinct_item_categories_interacted,

  -- Numeric pre-cutoff behavior
  u.total_sessions,
  u.active_days,
  u.total_events,
  u.total_page_views,
  u.total_item_views,
  u.total_add_to_carts,
  u.total_cart_views,
  u.total_checkouts_started,
  u.total_item_selects,

  u.sessions_with_product_view,
  u.sessions_with_add_to_cart,
  u.sessions_with_cart_view,
  u.sessions_with_checkout,

  u.cart_abandoned_sessions,
  u.low_intent_sessions,

  u.page_views_per_session,
  u.item_views_per_session,
  u.add_to_carts_per_session,
  u.checkouts_per_session,
  u.events_per_session,

  u.pct_sessions_with_product_view,
  u.pct_sessions_with_add_to_cart,
  u.pct_sessions_with_checkout,
  u.user_view_to_cart_session_rate,
  u.user_cart_to_checkout_session_rate,
  u.user_cart_abandonment_rate

FROM user_features u
LEFT JOIN future_labels l
  ON u.user_pseudo_id = l.user_pseudo_id
LEFT JOIN first_touch f
  ON u.user_pseudo_id = f.user_pseudo_id
LEFT JOIN favorite_categories c
  ON u.user_pseudo_id = c.user_pseudo_id;