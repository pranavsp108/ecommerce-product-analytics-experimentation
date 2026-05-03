-- 03_int_sessions.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create a session-level intermediate table from the cleaned GA4 event staging table.
--
-- Grain:
-- One row per session_key.
--
-- This table supports:
-- 1. Session-level funnel analysis
-- 2. Device/source conversion comparison
-- 3. Landing-page and engagement analysis
-- 4. Session quality scoring
-- 5. Feature engineering for customer segmentation and purchase propensity modeling
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run sql/01_stg_events.sql first.
-- 3. Run sql/02_stg_items.sql before product/category-specific session analysis.
--
-- Output table:
-- your_project_id.ecommerce_analytics.int_sessions

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.int_sessions`
PARTITION BY session_start_date
CLUSTER BY device_category, traffic_source, traffic_medium, user_pseudo_id
AS

WITH valid_events AS (
  SELECT
    *
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.stg_events`
  WHERE
    session_key IS NOT NULL
    AND user_pseudo_id IS NOT NULL
),

session_base AS (
  SELECT
    session_key,
    user_pseudo_id,

    -- Session timing
    MIN(event_timestamp_utc) AS session_start_ts,
    MAX(event_timestamp_utc) AS session_end_ts,
    DATE(MIN(event_timestamp_utc)) AS session_start_date,
    DATETIME(MIN(event_timestamp_utc), "UTC") AS session_start_datetime_utc,

    -- Session duration
    TIMESTAMP_DIFF(MAX(event_timestamp_utc), MIN(event_timestamp_utc), SECOND) AS session_duration_seconds,

    -- Date/time features
    EXTRACT(DAYOFWEEK FROM MIN(event_timestamp_utc)) AS session_day_of_week,
    EXTRACT(HOUR FROM MIN(event_timestamp_utc)) AS session_start_hour_utc,

    -- GA session fields
    ANY_VALUE(ga_session_id) AS ga_session_id,
    MIN(ga_session_number) AS ga_session_number,

    -- First-touch-ish session dimensions from staged event fields.
    -- These are mostly user acquisition dimensions in the GA4 export, but still useful for analysis.
    ARRAY_AGG(device_category IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS device_category,
    ARRAY_AGG(operating_system IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS operating_system,
    ARRAY_AGG(browser IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS browser,

    ARRAY_AGG(continent IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS continent,
    ARRAY_AGG(country IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS country,
    ARRAY_AGG(region IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS region,
    ARRAY_AGG(city IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS city,

    ARRAY_AGG(traffic_source IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS traffic_source,
    ARRAY_AGG(traffic_medium IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS traffic_medium,
    ARRAY_AGG(traffic_campaign IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS traffic_campaign,

    ARRAY_AGG(platform IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS platform,

    -- Landing and exit pages
    ARRAY_AGG(page_location IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS landing_page,
    ARRAY_AGG(page_title IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS landing_page_title,
    ARRAY_AGG(page_referrer IGNORE NULLS ORDER BY event_timestamp_utc LIMIT 1)[SAFE_OFFSET(0)] AS page_referrer,

    ARRAY_AGG(page_location IGNORE NULLS ORDER BY event_timestamp_utc DESC LIMIT 1)[SAFE_OFFSET(0)] AS exit_page,
    ARRAY_AGG(page_title IGNORE NULLS ORDER BY event_timestamp_utc DESC LIMIT 1)[SAFE_OFFSET(0)] AS exit_page_title,

    -- Event counts
    COUNT(*) AS total_events,
    COUNT(DISTINCT event_name) AS distinct_event_types,

    COUNTIF(event_name = 'page_view') AS page_views,
    COUNTIF(event_name = 'view_item') AS item_views,
    COUNTIF(event_name = 'select_item') AS item_selects,
    COUNTIF(event_name = 'add_to_cart') AS add_to_carts,
    COUNTIF(event_name = 'remove_from_cart') AS removes_from_cart,
    COUNTIF(event_name = 'view_cart') AS cart_views,
    COUNTIF(event_name = 'begin_checkout') AS checkouts_started,
    COUNTIF(event_name = 'add_shipping_info') AS shipping_info_events,
    COUNTIF(event_name = 'add_payment_info') AS payment_info_events,
    COUNTIF(event_name = 'purchase') AS purchases,

    -- Funnel flags
    MAX(CASE WHEN event_name = 'session_start' THEN 1 ELSE 0 END) AS had_session_start,
    MAX(CASE WHEN event_name = 'page_view' THEN 1 ELSE 0 END) AS had_page_view,
    MAX(CASE WHEN event_name = 'view_item' THEN 1 ELSE 0 END) AS had_view_item,
    MAX(CASE WHEN event_name = 'add_to_cart' THEN 1 ELSE 0 END) AS had_add_to_cart,
    MAX(CASE WHEN event_name = 'view_cart' THEN 1 ELSE 0 END) AS had_view_cart,
    MAX(CASE WHEN event_name = 'begin_checkout' THEN 1 ELSE 0 END) AS had_begin_checkout,
    MAX(CASE WHEN event_name = 'add_shipping_info' THEN 1 ELSE 0 END) AS had_add_shipping_info,
    MAX(CASE WHEN event_name = 'add_payment_info' THEN 1 ELSE 0 END) AS had_add_payment_info,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS had_purchase,

    -- Ecommerce metrics
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN transaction_id END) AS transactions,
    ROUND(SUM(CASE WHEN event_name = 'purchase' THEN COALESCE(purchase_revenue, 0) ELSE 0 END), 2) AS session_revenue,
    SUM(CASE WHEN event_name = 'purchase' THEN COALESCE(total_item_quantity, 0) ELSE 0 END) AS purchased_item_quantity,
    SUM(CASE WHEN event_name = 'purchase' THEN COALESCE(unique_items, 0) ELSE 0 END) AS purchased_unique_items,

    -- Engagement
    SUM(COALESCE(engagement_time_msec, 0)) AS total_engagement_time_msec,
    ROUND(SUM(COALESCE(engagement_time_msec, 0)) / 1000, 2) AS total_engagement_time_seconds,
    MAX(CASE WHEN session_engaged IN ('1', 'true', 'True') THEN 1 ELSE 0 END) AS is_engaged_session,

    -- Entrance indicator
    MAX(CASE WHEN entrances IS NOT NULL THEN 1 ELSE 0 END) AS had_entrance

  FROM
    valid_events
  GROUP BY
    session_key,
    user_pseudo_id
),

session_item_features AS (
  SELECT
    session_key,

    COUNT(*) AS item_event_rows,
    COUNT(DISTINCT clean_item_id) AS distinct_items_interacted,
    COUNT(DISTINCT clean_item_category) AS distinct_categories_interacted,

    COUNTIF(event_name = 'view_item') AS item_view_rows,
    COUNTIF(event_name = 'add_to_cart') AS item_add_to_cart_rows,
    COUNTIF(event_name = 'purchase') AS item_purchase_rows,

    ROUND(SUM(CASE WHEN event_name = 'purchase' THEN estimated_item_revenue ELSE 0 END), 2) AS estimated_item_revenue,

    -- Most viewed category in the session.
    ARRAY_AGG(clean_item_category ORDER BY category_event_count DESC, clean_item_category LIMIT 1)[SAFE_OFFSET(0)] AS primary_item_category

  FROM (
    SELECT
      session_key,
      event_name,
      clean_item_id,
      clean_item_category,
      estimated_item_revenue,
      COUNT(*) OVER (PARTITION BY session_key, clean_item_category) AS category_event_count
    FROM
      `ecommerce-product-analytics.ecommerce_analytics.stg_items`
    WHERE
      session_key IS NOT NULL
  )
  GROUP BY
    session_key
),

final AS (
  SELECT
    s.*,

    -- New vs returning session label.
    CASE
      WHEN s.ga_session_number = 1 THEN 'new_session'
      WHEN s.ga_session_number > 1 THEN 'returning_session'
      ELSE 'unknown'
    END AS session_user_type,

    -- Bounce proxy:
    -- GA4 bounce rate is not directly exported in the same way as Universal Analytics.
    -- This proxy flags sessions with very low interaction and no meaningful commerce activity.
    CASE
      WHEN s.page_views <= 1
        AND s.item_views = 0
        AND s.add_to_carts = 0
        AND s.checkouts_started = 0
        AND s.purchases = 0
      THEN 1
      ELSE 0
    END AS is_bounce_like_session,

    -- Funnel stage reached.
    CASE
      WHEN s.had_purchase = 1 THEN '05_purchase'
      WHEN s.had_begin_checkout = 1 THEN '04_begin_checkout'
      WHEN s.had_add_to_cart = 1 THEN '03_add_to_cart'
      WHEN s.had_view_item = 1 THEN '02_view_item'
      WHEN s.had_session_start = 1 OR s.had_page_view = 1 THEN '01_session_or_page_view'
      ELSE '00_other'
    END AS max_funnel_stage,

    -- Conversion indicators.
    CASE WHEN s.had_view_item = 1 AND s.had_add_to_cart = 1 THEN 1 ELSE 0 END AS converted_view_to_cart,
    CASE WHEN s.had_add_to_cart = 1 AND s.had_begin_checkout = 1 THEN 1 ELSE 0 END AS converted_cart_to_checkout,
    CASE WHEN s.had_begin_checkout = 1 AND s.had_purchase = 1 THEN 1 ELSE 0 END AS converted_checkout_to_purchase,
    CASE WHEN s.had_view_item = 1 AND s.had_purchase = 1 THEN 1 ELSE 0 END AS converted_view_to_purchase,

    -- Cart abandonment proxy.
    CASE
      WHEN s.had_add_to_cart = 1 AND s.had_purchase = 0 THEN 1
      ELSE 0
    END AS is_cart_abandoned_session,

    -- Checkout abandonment proxy.
    CASE
      WHEN s.had_begin_checkout = 1 AND s.had_purchase = 0 THEN 1
      ELSE 0
    END AS is_checkout_abandoned_session,

    -- Item-level features.
    COALESCE(i.item_event_rows, 0) AS item_event_rows,
    COALESCE(i.distinct_items_interacted, 0) AS distinct_items_interacted,
    COALESCE(i.distinct_categories_interacted, 0) AS distinct_categories_interacted,
    COALESCE(i.item_view_rows, 0) AS item_view_rows,
    COALESCE(i.item_add_to_cart_rows, 0) AS item_add_to_cart_rows,
    COALESCE(i.item_purchase_rows, 0) AS item_purchase_rows,
    COALESCE(i.estimated_item_revenue, 0) AS estimated_item_revenue,
    COALESCE(i.primary_item_category, 'unknown') AS primary_item_category

  FROM
    session_base AS s
  LEFT JOIN
    session_item_features AS i
  USING
    (session_key)
)

SELECT
  *
FROM final;