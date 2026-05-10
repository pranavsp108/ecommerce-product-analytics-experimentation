-- 09b_fix_executive_scorecard_unique_users.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Fix the executive scorecard active user calculation.
--
-- Issue:
-- In the earlier tableau_executive_scorecard export, active_users was calculated as:
-- SUM(active_users) from mart_product_kpis.
--
-- Because mart_product_kpis is grouped by date/device/source/medium/campaign/user_type,
-- summing distinct-user counts across groups double-counts users.
--
-- Correct approach:
-- Recalculate active_users directly from int_sessions using COUNT(DISTINCT user_pseudo_id).
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run this after sql/09_tableau_exports.sql.
--
-- Output:
-- Replaces your_project_id.ecommerce_analytics.tableau_executive_scorecard
-- Creates your_project_id.ecommerce_analytics.tableau_kpi_daily_overall

--------------------------------------------------------------------------------
-- 1. CORRECTED EXECUTIVE SCORECARD
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `your_project_id.ecommerce_analytics.tableau_executive_scorecard`
AS

WITH session_kpis AS (
  SELECT
    COUNT(DISTINCT session_start_date) AS active_days,

    COUNT(DISTINCT session_key) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS active_users,

    SUM(item_views) AS product_views,
    SUM(add_to_carts) AS add_to_cart_events,
    SUM(checkouts_started) AS checkout_starts,
    SUM(had_purchase) AS purchasing_sessions,
    SUM(transactions) AS transactions,
    ROUND(SUM(session_revenue), 2) AS revenue,

    SUM(is_cart_abandoned_session) AS cart_abandoned_sessions,
    SUM(is_checkout_abandoned_session) AS checkout_abandoned_sessions,
    SUM(is_bounce_like_session) AS bounce_like_sessions
  FROM
    `your_project_id.ecommerce_analytics.int_sessions`
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
    `your_project_id.ecommerce_analytics.customer_segments`
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
  session_kpis AS k
CROSS JOIN
  segments AS s;


--------------------------------------------------------------------------------
-- 2. DAILY OVERALL KPI TABLE FOR TREND CHARTS
--------------------------------------------------------------------------------
-- Use this for overall daily trends when you do not need device/source breakdowns.
-- This avoids double-counting daily active users across source/device groups.

CREATE OR REPLACE TABLE `your_project_id.ecommerce_analytics.tableau_kpi_daily_overall`
PARTITION BY metric_date
AS

SELECT
  session_start_date AS metric_date,
  FORMAT_DATE('%Y-%m', session_start_date) AS metric_month,
  EXTRACT(WEEK FROM session_start_date) AS metric_week,
  EXTRACT(DAYOFWEEK FROM session_start_date) AS metric_day_of_week,

  COUNT(DISTINCT session_key) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS active_users,

  SUM(total_events) AS total_events,
  SUM(page_views) AS page_views,
  SUM(item_views) AS product_views,
  SUM(add_to_carts) AS add_to_cart_events,
  SUM(cart_views) AS cart_views,
  SUM(checkouts_started) AS checkout_starts,
  SUM(payment_info_events) AS payment_info_events,
  SUM(purchases) AS purchase_events,

  SUM(had_view_item) AS sessions_with_product_view,
  SUM(had_add_to_cart) AS sessions_with_add_to_cart,
  SUM(had_begin_checkout) AS sessions_with_checkout,
  SUM(had_purchase) AS purchasing_sessions,

  SUM(is_cart_abandoned_session) AS cart_abandoned_sessions,
  SUM(is_checkout_abandoned_session) AS checkout_abandoned_sessions,
  SUM(is_bounce_like_session) AS bounce_like_sessions,

  SUM(transactions) AS transactions,
  ROUND(SUM(session_revenue), 2) AS revenue,

  ROUND(SAFE_DIVIDE(SUM(had_purchase), COUNT(DISTINCT session_key)) * 100, 2) AS session_purchase_conversion_rate,
  ROUND(SAFE_DIVIDE(SUM(had_view_item), COUNT(DISTINCT session_key)) * 100, 2) AS product_view_session_rate,
  ROUND(SAFE_DIVIDE(SUM(had_add_to_cart), SUM(had_view_item)) * 100, 2) AS view_to_cart_session_rate,
  ROUND(SAFE_DIVIDE(SUM(had_begin_checkout), SUM(had_add_to_cart)) * 100, 2) AS cart_to_checkout_session_rate,
  ROUND(SAFE_DIVIDE(SUM(had_purchase), SUM(had_begin_checkout)) * 100, 2) AS checkout_to_purchase_session_rate,
  ROUND(SAFE_DIVIDE(SUM(had_purchase), SUM(had_view_item)) * 100, 2) AS view_to_purchase_session_rate,

  ROUND(SAFE_DIVIDE(SUM(is_cart_abandoned_session), SUM(had_add_to_cart)) * 100, 2) AS cart_abandonment_rate,
  ROUND(SAFE_DIVIDE(SUM(is_checkout_abandoned_session), SUM(had_begin_checkout)) * 100, 2) AS checkout_abandonment_rate,
  ROUND(SAFE_DIVIDE(SUM(is_bounce_like_session), COUNT(DISTINCT session_key)) * 100, 2) AS bounce_like_session_rate,

  ROUND(SAFE_DIVIDE(SUM(session_revenue), SUM(transactions)), 2) AS average_order_value,
  ROUND(SAFE_DIVIDE(SUM(session_revenue), COUNT(DISTINCT user_pseudo_id)), 2) AS revenue_per_active_user,
  ROUND(SAFE_DIVIDE(SUM(session_revenue), COUNT(DISTINCT session_key)), 2) AS revenue_per_session

FROM
  `your_project_id.ecommerce_analytics.int_sessions`
GROUP BY
  metric_date,
  metric_month,
  metric_week,
  metric_day_of_week;