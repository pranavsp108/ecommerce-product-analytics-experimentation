-- 02_stg_items.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create a clean item-level staging table from the GA4 BigQuery e-commerce demo dataset.
--
-- GA4 stores product information inside a repeated `items` array. This script uses
-- UNNEST(items) so each row represents one product/item associated with one GA4 event.
--
-- This table supports:
-- 1. Product/category performance analysis
-- 2. View-to-cart and view-to-purchase rates
-- 3. Item-level revenue estimates
-- 4. Product funnel analysis
-- 5. Merchandising recommendations
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Run this script in BigQuery using Standard SQL.
--
-- Output table:
-- your_project_id.ecommerce_analytics.stg_items

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.stg_items`
PARTITION BY event_date
CLUSTER BY event_name, item_category, item_id, user_pseudo_id
AS

WITH raw_item_events AS (
  SELECT
    -- Source table/date fields
    raw._TABLE_SUFFIX AS source_table_suffix,
    PARSE_DATE('%Y%m%d', raw.event_date) AS event_date,
    TIMESTAMP_MICROS(raw.event_timestamp) AS event_timestamp_utc,
    DATETIME(TIMESTAMP_MICROS(raw.event_timestamp), "UTC") AS event_datetime_utc,

    EXTRACT(DAYOFWEEK FROM TIMESTAMP_MICROS(raw.event_timestamp)) AS event_day_of_week,
    EXTRACT(HOUR FROM TIMESTAMP_MICROS(raw.event_timestamp)) AS event_hour_utc,

    -- Raw GA4 event identifiers
    raw.event_timestamp,
    raw.event_previous_timestamp,
    raw.event_name,
    raw.event_bundle_sequence_id,
    raw.user_pseudo_id,
    raw.user_id,

    -- Session fields extracted from event_params
    (
      SELECT ep.value.int_value
      FROM UNNEST(raw.event_params) AS ep
      WHERE ep.key = 'ga_session_id'
      LIMIT 1
    ) AS ga_session_id,

    (
      SELECT ep.value.int_value
      FROM UNNEST(raw.event_params) AS ep
      WHERE ep.key = 'ga_session_number'
      LIMIT 1
    ) AS ga_session_number,

    -- Device dimensions
    COALESCE(raw.device.category, 'unknown') AS device_category,
    COALESCE(raw.device.mobile_brand_name, 'unknown') AS mobile_brand_name,
    COALESCE(raw.device.mobile_model_name, 'unknown') AS mobile_model_name,
    COALESCE(raw.device.operating_system, 'unknown') AS operating_system,
    COALESCE(raw.device.web_info.browser, 'unknown') AS browser,

    -- Geo dimensions
    COALESCE(raw.geo.continent, 'unknown') AS continent,
    COALESCE(raw.geo.country, 'unknown') AS country,
    COALESCE(raw.geo.region, 'unknown') AS region,
    COALESCE(raw.geo.city, 'unknown') AS city,

    -- User acquisition source dimensions
    COALESCE(raw.traffic_source.name, 'unknown') AS traffic_campaign,
    COALESCE(raw.traffic_source.medium, 'unknown') AS traffic_medium,
    COALESCE(raw.traffic_source.source, 'unknown') AS traffic_source,

    -- Platform / stream
    COALESCE(raw.platform, 'unknown') AS platform,
    raw.stream_id,

    -- Transaction/ecommerce fields
    raw.ecommerce.transaction_id,
    raw.ecommerce.purchase_revenue,
    raw.ecommerce.shipping_value,
    raw.ecommerce.tax_value,

    -- Item position within the event
    item_offset AS item_position_in_event,

    -- Raw item fields
    item.item_id,
    item.item_name,
    item.item_brand,
    item.item_variant,
    item.item_category,
    item.item_category2,
    item.item_category3,
    item.item_category4,
    item.item_category5,
    item.price,
    item.quantity,
    item.item_revenue,
    item.item_refund,
    item.coupon,
    item.affiliation,
    item.location_id,
    item.item_list_id,
    item.item_list_name,
    item.item_list_index,
    item.promotion_id,
    item.promotion_name,
    item.creative_name,
    item.creative_slot

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS raw,
    UNNEST(raw.items) AS item WITH OFFSET AS item_offset

  WHERE
    raw._TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

cleaned AS (
  SELECT
    -- Stable event key. This logic matches 01_stg_events.sql.
    TO_HEX(SHA256(CONCAT(
      COALESCE(user_pseudo_id, 'missing_user'),
      '|',
      CAST(event_timestamp AS STRING),
      '|',
      COALESCE(event_name, 'missing_event'),
      '|',
      COALESCE(CAST(event_bundle_sequence_id AS STRING), 'missing_bundle')
    ))) AS event_key,

    -- Stable session key.
    CASE
      WHEN user_pseudo_id IS NOT NULL AND ga_session_id IS NOT NULL
        THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))
      ELSE NULL
    END AS session_key,

    -- Clean item fields.
    COALESCE(NULLIF(item_id, ''), 'unknown') AS clean_item_id,
    COALESCE(NULLIF(item_name, ''), 'unknown') AS clean_item_name,
    COALESCE(NULLIF(item_brand, ''), 'unknown') AS clean_item_brand,
    COALESCE(NULLIF(item_category, ''), 'unknown') AS clean_item_category,

    -- Numeric item measures.
    COALESCE(price, 0) AS item_price,
    COALESCE(quantity, 0) AS item_quantity,

    -- Item-level revenue logic:
    -- Prefer GA4 item_revenue when present.
    -- If missing, estimate as price * quantity.
    COALESCE(
      item_revenue,
      price * quantity,
      0
    ) AS estimated_item_revenue,

    -- Item/event flags.
    CASE WHEN event_name = 'view_item' THEN 1 ELSE 0 END AS is_item_view,
    CASE WHEN event_name = 'select_item' THEN 1 ELSE 0 END AS is_item_select,
    CASE WHEN event_name = 'add_to_cart' THEN 1 ELSE 0 END AS is_item_add_to_cart,
    CASE WHEN event_name = 'remove_from_cart' THEN 1 ELSE 0 END AS is_item_remove_from_cart,
    CASE WHEN event_name = 'begin_checkout' THEN 1 ELSE 0 END AS is_item_begin_checkout,
    CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END AS is_item_purchase,

    -- Data quality flags.
    CASE
      WHEN item_id IS NULL OR item_id = '' OR item_id = '(not set)' THEN 1
      ELSE 0
    END AS is_missing_or_placeholder_item_id,

    CASE
      WHEN item_name IS NULL OR item_name = '' OR item_name = '(not set)' THEN 1
      ELSE 0
    END AS is_missing_or_placeholder_item_name,

    CASE
      WHEN item_category IS NULL OR item_category = '' OR item_category = '(not set)' THEN 1
      ELSE 0
    END AS is_missing_or_placeholder_item_category,

    CASE WHEN price IS NULL THEN 1 ELSE 0 END AS is_missing_item_price,
    CASE WHEN quantity IS NULL THEN 1 ELSE 0 END AS is_missing_item_quantity,

    *

  FROM raw_item_events
)

SELECT
  -- Stable item-event key for item-level joins and QA.
  TO_HEX(SHA256(CONCAT(
    COALESCE(event_key, 'missing_event_key'),
    '|',
    CAST(item_position_in_event AS STRING),
    '|',
    COALESCE(clean_item_id, 'missing_item_id')
  ))) AS item_event_key,

  *
FROM cleaned;