-- 08b_fix_customer_segments_and_segment_summary.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Fix customer segmentation so revenue-generating buyers are not all collapsed
-- into High-Value Customer.
--
-- BEFORE RUNNING:
-- Replace your_project_id with your actual GCP project ID.

--------------------------------------------------------------------------------
-- 1. CREATE FIXED CUSTOMER SEGMENTS
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `your_project_id.ecommerce_analytics.customer_segments_fixed` AS

WITH base AS (
  SELECT *
  FROM `your_project_id.ecommerce_analytics.customer_segments`
),

revenue_positive_buyers AS (
  SELECT
    user_pseudo_id,
    NTILE(10) OVER (ORDER BY total_revenue DESC) AS revenue_decile
  FROM base
  WHERE COALESCE(total_revenue, 0) > 0
),

scored AS (
  SELECT
    b.*,
    r.revenue_decile,
    CASE
      WHEN r.revenue_decile = 1 THEN 1
      ELSE 0
    END AS fixed_is_top_10pct_revenue_customer
  FROM base AS b
  LEFT JOIN revenue_positive_buyers AS r
  USING (user_pseudo_id)
),

fixed AS (
  SELECT
    *,

    CASE
      WHEN fixed_is_top_10pct_revenue_customer = 1
        THEN 'high_value_customer'

      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) > 0
        AND (is_repeat_buyer = 1 OR total_transactions >= 2)
        THEN 'repeat_buyer'

      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) > 0
        THEN 'one_time_buyer'

      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) = 0
        THEN 'purchase_recorded_revenue_missing'

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
        AND total_item_views > 0
        THEN 'engaged_browser_non_buyer'

      WHEN has_ever_purchased = 0
        AND is_repeat_visitor = 1
        THEN 'repeat_visitor_non_buyer'

      ELSE 'low_activity_user'
    END AS fixed_primary_customer_segment,

    CASE
      WHEN fixed_is_top_10pct_revenue_customer = 1
        THEN 'protect_and_retain_vip_customers'

      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) > 0
        AND (is_repeat_buyer = 1 OR total_transactions >= 2)
        THEN 'promote_loyalty_and_cross_sell'

      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) > 0
        THEN 'drive_second_purchase'

      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) = 0
        THEN 'audit_purchase_revenue_tracking'

      WHEN has_ever_purchased = 0
        AND is_checkout_abandoner_non_buyer = 1
        THEN 'recover_checkout_abandonment'

      WHEN has_ever_purchased = 0
        AND is_cart_abandoner_non_buyer = 1
        THEN 'recover_cart_abandonment'

      WHEN has_ever_purchased = 0
        AND is_high_intent_non_buyer = 1
        THEN 'personalize_product_recommendations'

      WHEN has_ever_purchased = 0
        AND total_item_views > 0
        THEN 'personalize_product_recommendations'

      WHEN has_ever_purchased = 0
        AND is_repeat_visitor = 1
        THEN 'nurture_repeat_visitors'

      ELSE 'low_priority_generic_awareness'
    END AS fixed_recommended_action,

    CASE
      WHEN fixed_is_top_10pct_revenue_customer = 1 THEN 1
      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) > 0
        AND (is_repeat_buyer = 1 OR total_transactions >= 2) THEN 2
      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) > 0 THEN 3
      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) = 0 THEN 4
      WHEN has_ever_purchased = 0
        AND is_checkout_abandoner_non_buyer = 1 THEN 5
      WHEN has_ever_purchased = 0
        AND is_cart_abandoner_non_buyer = 1 THEN 6
      WHEN has_ever_purchased = 0
        AND is_high_intent_non_buyer = 1 THEN 7
      WHEN has_ever_purchased = 0
        AND total_item_views > 0 THEN 8
      WHEN has_ever_purchased = 0
        AND is_repeat_visitor = 1 THEN 9
      ELSE 10
    END AS fixed_targeting_priority_rank,

    CASE
      WHEN fixed_is_top_10pct_revenue_customer = 1 THEN 'top_revenue_decile'
      WHEN COALESCE(total_revenue, 0) > 0 THEN 'revenue_positive'
      WHEN has_ever_purchased = 1 AND COALESCE(total_revenue, 0) = 0 THEN 'purchase_recorded_revenue_missing'
      ELSE 'non_buyer'
    END AS fixed_value_tier,

    CASE
      WHEN fixed_is_top_10pct_revenue_customer = 1 THEN 'high_value_buyer'
      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) > 0
        AND (is_repeat_buyer = 1 OR total_transactions >= 2) THEN 'repeat_buyer'
      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) > 0 THEN 'one_time_buyer'
      WHEN has_ever_purchased = 1
        AND COALESCE(total_revenue, 0) = 0 THEN 'purchase_recorded_revenue_missing'
      ELSE 'non_buyer'
    END AS fixed_buyer_lifecycle_tier

  FROM scored
)

SELECT
  * EXCEPT (
    revenue_decile,
    fixed_is_top_10pct_revenue_customer,
    fixed_primary_customer_segment,
    fixed_recommended_action,
    fixed_targeting_priority_rank,
    fixed_value_tier,
    fixed_buyer_lifecycle_tier
  )
  REPLACE (
    fixed_is_top_10pct_revenue_customer AS is_top_10pct_revenue_customer,
    fixed_primary_customer_segment AS primary_customer_segment,
    fixed_recommended_action AS recommended_action,
    fixed_targeting_priority_rank AS targeting_priority_rank,
    fixed_value_tier AS value_tier,
    fixed_buyer_lifecycle_tier AS buyer_lifecycle_tier
  )
FROM fixed;


--------------------------------------------------------------------------------
-- 2. REBUILD ROW-LEVEL TABLEAU CUSTOMER SEGMENT EXPORT
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `your_project_id.ecommerce_analytics.tableau_customer_segments` AS
SELECT *
FROM `your_project_id.ecommerce_analytics.customer_segments_fixed`;


--------------------------------------------------------------------------------
-- 3. REBUILD TABLEAU SEGMENT SUMMARY EXPORT
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE `your_project_id.ecommerce_analytics.tableau_segment_summary` AS

WITH segment_summary AS (
  SELECT
    primary_customer_segment,
    recommended_action,
    value_tier,
    buyer_lifecycle_tier,
    targeting_priority_rank,

    COUNT(*) AS users,
    SUM(total_sessions) AS sessions,
    SUM(total_item_views) AS item_views,
    SUM(total_add_to_carts) AS add_to_carts,
    SUM(total_checkouts_started) AS checkout_starts,
    SUM(total_transactions) AS transactions,
    ROUND(SUM(total_revenue), 2) AS revenue,

    COUNTIF(has_ever_purchased = 1) AS buyers,
    SUM(is_repeat_buyer) AS repeat_buyers,
    SUM(is_high_intent_non_buyer) AS high_intent_non_buyers,
    SUM(is_cart_abandoner_non_buyer) AS cart_abandoner_non_buyers,
    SUM(is_checkout_abandoner_non_buyer) AS checkout_abandoner_non_buyers,

    ROUND(SAFE_DIVIDE(COUNTIF(has_ever_purchased = 1), COUNT(*)) * 100, 2) AS buyer_rate,
    ROUND(SAFE_DIVIDE(SUM(is_repeat_buyer), COUNTIF(has_ever_purchased = 1)) * 100, 2) AS repeat_buyer_rate,

    ROUND(SAFE_DIVIDE(SUM(total_revenue), COUNT(*)), 2) AS revenue_per_user,
    ROUND(SAFE_DIVIDE(SUM(total_revenue), SUM(total_transactions)), 2) AS avg_order_value,

    ROUND(AVG(total_sessions), 2) AS avg_sessions_per_user,
    ROUND(AVG(total_item_views), 2) AS avg_item_views_per_user,
    ROUND(AVG(total_add_to_carts), 2) AS avg_add_to_carts_per_user,
    ROUND(AVG(total_revenue), 2) AS avg_revenue_per_user,

    ROUND(SAFE_DIVIDE(SUM(total_transactions), COUNT(*)), 4) AS transactions_per_user,
    ROUND(SAFE_DIVIDE(SUM(total_revenue), SUM(total_sessions)), 2) AS revenue_per_session

  FROM `your_project_id.ecommerce_analytics.customer_segments_fixed`
  GROUP BY
    primary_customer_segment,
    recommended_action,
    value_tier,
    buyer_lifecycle_tier,
    targeting_priority_rank
)

SELECT
  *,
  ROUND(SAFE_DIVIDE(users, SUM(users) OVER ()) * 100, 2) AS pct_of_users,
  ROUND(SAFE_DIVIDE(revenue, SUM(revenue) OVER ()) * 100, 2) AS pct_of_revenue
FROM segment_summary
ORDER BY
  targeting_priority_rank,
  revenue DESC,
  users DESC;


--------------------------------------------------------------------------------
-- 4. VALIDATION QUERY
--------------------------------------------------------------------------------

SELECT
  primary_customer_segment,
  recommended_action,
  targeting_priority_rank,
  users,
  buyers,
  repeat_buyers,
  transactions,
  revenue,
  revenue_per_user,
  buyer_rate,
  pct_of_users,
  pct_of_revenue
FROM `your_project_id.ecommerce_analytics.tableau_segment_summary`
ORDER BY targeting_priority_rank;