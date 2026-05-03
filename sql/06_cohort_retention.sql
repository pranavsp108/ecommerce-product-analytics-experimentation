-- 06_cohort_retention.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create cohort and retention analysis marts from session-level behavior.
--
-- Outputs:
-- 1. your_project_id.ecommerce_analytics.mart_cohort_retention_weekly
--    Grain: acquisition cohort month x activity week number x acquisition dimensions.
--
-- 2. your_project_id.ecommerce_analytics.mart_first_purchase_cohort_revenue
--    Grain: first-purchase cohort month x purchase month x acquisition dimensions.
--
-- 3. your_project_id.ecommerce_analytics.mart_user_lifecycle_summary
--    Grain: one row per user.
--
-- These tables support:
-- 1. First-visit cohort retention
-- 2. First-purchase cohort revenue retention
-- 3. Repeat purchase behavior
-- 4. Acquisition quality by traffic source/device
-- 5. Tableau retention heatmaps
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run 01_stg_events.sql
-- 3. Run 02_stg_items.sql
-- 4. Run 03_int_sessions.sql
-- 5. Run 04_mart_product_kpis.sql
-- 6. Run 05_funnel_analysis.sql

--------------------------------------------------------------------------------
-- 1. USER LIFECYCLE SUMMARY
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.mart_user_lifecycle_summary`
PARTITION BY first_session_date
CLUSTER BY first_device_category, first_traffic_source, first_traffic_medium
AS

WITH user_sessions AS (
  SELECT
    user_pseudo_id,
    session_key,
    session_start_date,
    session_start_ts,
    device_category,
    traffic_source,
    traffic_medium,
    traffic_campaign,
    country,
    session_user_type,

    total_events,
    page_views,
    item_views,
    add_to_carts,
    checkouts_started,
    purchases,
    had_purchase,
    transactions,
    session_revenue,
    total_engagement_time_seconds,
    primary_item_category
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.int_sessions`
  WHERE
    user_pseudo_id IS NOT NULL
),

first_touch AS (
  SELECT
    user_pseudo_id,
    ARRAY_AGG(session_start_date ORDER BY session_start_ts LIMIT 1)[SAFE_OFFSET(0)] AS first_session_date,
    ARRAY_AGG(session_start_ts ORDER BY session_start_ts LIMIT 1)[SAFE_OFFSET(0)] AS first_session_ts,
    ARRAY_AGG(device_category ORDER BY session_start_ts LIMIT 1)[SAFE_OFFSET(0)] AS first_device_category,
    ARRAY_AGG(traffic_source ORDER BY session_start_ts LIMIT 1)[SAFE_OFFSET(0)] AS first_traffic_source,
    ARRAY_AGG(traffic_medium ORDER BY session_start_ts LIMIT 1)[SAFE_OFFSET(0)] AS first_traffic_medium,
    ARRAY_AGG(traffic_campaign ORDER BY session_start_ts LIMIT 1)[SAFE_OFFSET(0)] AS first_traffic_campaign,
    ARRAY_AGG(country ORDER BY session_start_ts LIMIT 1)[SAFE_OFFSET(0)] AS first_country,
    ARRAY_AGG(primary_item_category ORDER BY session_start_ts LIMIT 1)[SAFE_OFFSET(0)] AS first_primary_item_category
  FROM
    user_sessions
  GROUP BY
    user_pseudo_id
),

first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(session_start_date) AS first_purchase_date,
    MIN(session_start_ts) AS first_purchase_ts
  FROM
    user_sessions
  WHERE
    had_purchase = 1
  GROUP BY
    user_pseudo_id
),

favorite_category AS (
  SELECT
    user_pseudo_id,
    ARRAY_AGG(primary_item_category ORDER BY category_session_count DESC, primary_item_category LIMIT 1)[SAFE_OFFSET(0)] AS favorite_session_category
  FROM (
    SELECT
      user_pseudo_id,
      primary_item_category,
      COUNT(*) AS category_session_count
    FROM
      user_sessions
    WHERE
      primary_item_category IS NOT NULL
      AND primary_item_category != 'unknown'
    GROUP BY
      user_pseudo_id,
      primary_item_category
  )
  GROUP BY
    user_pseudo_id
),

user_agg AS (
  SELECT
    user_pseudo_id,

    COUNT(DISTINCT session_key) AS lifetime_sessions,
    COUNT(DISTINCT session_start_date) AS active_days,

    SUM(total_events) AS lifetime_events,
    SUM(page_views) AS lifetime_page_views,
    SUM(item_views) AS lifetime_item_views,
    SUM(add_to_carts) AS lifetime_add_to_carts,
    SUM(checkouts_started) AS lifetime_checkout_starts,
    SUM(purchases) AS lifetime_purchase_events,

    SUM(had_purchase) AS purchasing_sessions,
    SUM(transactions) AS lifetime_transactions,
    ROUND(SUM(session_revenue), 2) AS lifetime_revenue,
    ROUND(AVG(session_revenue), 2) AS avg_revenue_per_session,
    ROUND(SUM(total_engagement_time_seconds), 2) AS lifetime_engagement_seconds,

    MAX(session_start_date) AS last_session_date,
    MAX(CASE WHEN had_purchase = 1 THEN session_start_date END) AS last_purchase_date
  FROM
    user_sessions
  GROUP BY
    user_pseudo_id
)

SELECT
  u.user_pseudo_id,

  f.first_session_date,
  DATE_TRUNC(f.first_session_date, MONTH) AS first_session_month,
  f.first_session_ts,
  f.first_device_category,
  f.first_traffic_source,
  f.first_traffic_medium,
  f.first_traffic_campaign,
  f.first_country,
  f.first_primary_item_category,

  p.first_purchase_date,
  DATE_TRUNC(p.first_purchase_date, MONTH) AS first_purchase_month,
  p.first_purchase_ts,

  c.favorite_session_category,

  u.lifetime_sessions,
  u.active_days,
  u.lifetime_events,
  u.lifetime_page_views,
  u.lifetime_item_views,
  u.lifetime_add_to_carts,
  u.lifetime_checkout_starts,
  u.lifetime_purchase_events,
  u.purchasing_sessions,
  u.lifetime_transactions,
  u.lifetime_revenue,
  u.avg_revenue_per_session,
  ROUND(SAFE_DIVIDE(u.lifetime_revenue, u.lifetime_transactions), 2) AS lifetime_average_order_value,
  u.lifetime_engagement_seconds,

  u.last_session_date,
  u.last_purchase_date,

  DATE_DIFF(u.last_session_date, f.first_session_date, DAY) AS customer_lifespan_days,
  DATE_DIFF(CURRENT_DATE(), u.last_session_date, DAY) AS days_since_last_session,
  DATE_DIFF(CURRENT_DATE(), u.last_purchase_date, DAY) AS days_since_last_purchase,

  CASE WHEN u.lifetime_transactions > 0 THEN 1 ELSE 0 END AS has_ever_purchased,
  CASE WHEN u.lifetime_transactions >= 2 THEN 1 ELSE 0 END AS is_repeat_buyer,
  CASE WHEN u.lifetime_sessions >= 2 THEN 1 ELSE 0 END AS is_repeat_visitor,

  CASE
    WHEN u.lifetime_transactions >= 2 THEN 'repeat_buyer'
    WHEN u.lifetime_transactions = 1 THEN 'one_time_buyer'
    WHEN u.lifetime_add_to_carts > 0 THEN 'cart_intent_non_buyer'
    WHEN u.lifetime_item_views > 0 THEN 'browser_non_buyer'
    ELSE 'low_activity_user'
  END AS lifecycle_segment

FROM
  user_agg AS u
JOIN
  first_touch AS f
USING
  (user_pseudo_id)
LEFT JOIN
  first_purchase AS p
USING
  (user_pseudo_id)
LEFT JOIN
  favorite_category AS c
USING
  (user_pseudo_id);


--------------------------------------------------------------------------------
-- 2. WEEKLY FIRST-VISIT COHORT RETENTION
--------------------------------------------------------------------------------
-- Cohort definition:
-- A user's first observed session month.
--
-- Retention definition:
-- User had at least one session in week N after first session date.
--
-- Notes:
-- Week 0 = acquisition/first activity week.
-- Week 1 = 7 to 13 days after first session date, etc.

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.mart_cohort_retention_weekly`
PARTITION BY cohort_month
CLUSTER BY first_device_category, first_traffic_source, first_traffic_medium, week_number
AS

WITH users AS (
  SELECT
    user_pseudo_id,
    first_session_date,
    DATE_TRUNC(first_session_date, MONTH) AS cohort_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.mart_user_lifecycle_summary`
),

user_activity_weeks AS (
  SELECT DISTINCT
    s.user_pseudo_id,
    u.cohort_month,
    u.first_session_date,
    u.first_device_category,
    u.first_traffic_source,
    u.first_traffic_medium,
    u.first_traffic_campaign,
    u.first_country,

    DATE_DIFF(s.session_start_date, u.first_session_date, WEEK) AS week_number
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.int_sessions` AS s
  JOIN
    users AS u
  USING
    (user_pseudo_id)
  WHERE
    s.session_start_date >= u.first_session_date
),

cohort_sizes AS (
  SELECT
    cohort_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country,
    COUNT(DISTINCT user_pseudo_id) AS cohort_users
  FROM
    users
  GROUP BY
    cohort_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country
),

retention_counts AS (
  SELECT
    cohort_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country,
    week_number,
    COUNT(DISTINCT user_pseudo_id) AS retained_users
  FROM
    user_activity_weeks
  WHERE
    week_number >= 0
  GROUP BY
    cohort_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country,
    week_number
)

SELECT
  r.cohort_month,
  r.first_device_category,
  r.first_traffic_source,
  r.first_traffic_medium,
  r.first_traffic_campaign,
  r.first_country,
  r.week_number,

  c.cohort_users,
  r.retained_users,
  ROUND(SAFE_DIVIDE(r.retained_users, c.cohort_users) * 100, 2) AS retention_rate,

  -- Helpful labels for Tableau
  CONCAT('Week ', CAST(r.week_number AS STRING)) AS week_label,
  FORMAT_DATE('%Y-%m', r.cohort_month) AS cohort_month_label

FROM
  retention_counts AS r
JOIN
  cohort_sizes AS c
USING
  (
    cohort_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country
  );


--------------------------------------------------------------------------------
-- 3. FIRST-PURCHASE COHORT REVENUE RETENTION
--------------------------------------------------------------------------------
-- Cohort definition:
-- A user's first purchase month.
--
-- Revenue retention definition:
-- Revenue generated by users in later months after their first purchase month.

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.mart_first_purchase_cohort_revenue`
PARTITION BY first_purchase_month
CLUSTER BY first_device_category, first_traffic_source, first_traffic_medium, months_since_first_purchase
AS

WITH purchasing_users AS (
  SELECT
    user_pseudo_id,
    first_purchase_date,
    first_purchase_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.mart_user_lifecycle_summary`
  WHERE
    first_purchase_date IS NOT NULL
),

monthly_user_revenue AS (
  SELECT
    s.user_pseudo_id,
    DATE_TRUNC(s.session_start_date, MONTH) AS revenue_month,
    SUM(s.transactions) AS transactions,
    ROUND(SUM(s.session_revenue), 2) AS revenue
  FROM
    `ecommerce-product-analytics.ecommerce_analytics.int_sessions` AS s
  WHERE
    s.session_revenue > 0
  GROUP BY
    s.user_pseudo_id,
    revenue_month
),

cohort_revenue AS (
  SELECT
    p.first_purchase_month,
    p.first_device_category,
    p.first_traffic_source,
    p.first_traffic_medium,
    p.first_traffic_campaign,
    p.first_country,

    m.revenue_month,
    DATE_DIFF(m.revenue_month, p.first_purchase_month, MONTH) AS months_since_first_purchase,

    COUNT(DISTINCT p.user_pseudo_id) AS active_purchasers,
    SUM(m.transactions) AS transactions,
    ROUND(SUM(m.revenue), 2) AS revenue

  FROM
    purchasing_users AS p
  JOIN
    monthly_user_revenue AS m
  USING
    (user_pseudo_id)
  WHERE
    m.revenue_month >= p.first_purchase_month
  GROUP BY
    p.first_purchase_month,
    p.first_device_category,
    p.first_traffic_source,
    p.first_traffic_medium,
    p.first_traffic_campaign,
    p.first_country,
    m.revenue_month,
    months_since_first_purchase
),

cohort_sizes AS (
  SELECT
    first_purchase_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country,
    COUNT(DISTINCT user_pseudo_id) AS purchase_cohort_users
  FROM
    purchasing_users
  GROUP BY
    first_purchase_month,
    first_device_category,
    first_traffic_source,
    first_traffic_medium,
    first_traffic_campaign,
    first_country
),

final AS (
  SELECT
    r.first_purchase_month,
    r.first_device_category,
    r.first_traffic_source,
    r.first_traffic_medium,
    r.first_traffic_campaign,
    r.first_country,
    r.revenue_month,
    r.months_since_first_purchase,

    c.purchase_cohort_users,
    r.active_purchasers,
    r.transactions,
    r.revenue,

    ROUND(SAFE_DIVIDE(r.active_purchasers, c.purchase_cohort_users) * 100, 2) AS purchaser_retention_rate,
    ROUND(SAFE_DIVIDE(r.revenue, c.purchase_cohort_users), 2) AS revenue_per_original_purchaser,
    ROUND(SAFE_DIVIDE(r.revenue, r.active_purchasers), 2) AS revenue_per_active_purchaser,
    ROUND(SAFE_DIVIDE(r.revenue, r.transactions), 2) AS average_order_value,

    CONCAT('Month ', CAST(r.months_since_first_purchase AS STRING)) AS month_number_label,
    FORMAT_DATE('%Y-%m', r.first_purchase_month) AS first_purchase_month_label,
    FORMAT_DATE('%Y-%m', r.revenue_month) AS revenue_month_label

  FROM
    cohort_revenue AS r
  JOIN
    cohort_sizes AS c
  USING
    (
      first_purchase_month,
      first_device_category,
      first_traffic_source,
      first_traffic_medium,
      first_traffic_campaign,
      first_country
    )
)

SELECT
  *
FROM final;