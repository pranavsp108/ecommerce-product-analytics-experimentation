-- 01_stg_events.sql
-- E-Commerce Product Analytics & Experimentation Platform
--
-- Purpose:
-- Create a clean event-level staging table from the GA4 BigQuery public e-commerce demo dataset.
-- This table becomes the reusable base for KPI dashboards, funnel analysis, cohort retention,
-- customer segmentation, and purchase propensity modeling.
--
-- BEFORE RUNNING:
-- 1. Replace your_project_id with your actual Google Cloud project ID.
-- 2. Keep the dataset name ecommerce_analytics unless you prefer another name.
-- 3. Run this script in BigQuery using Standard SQL.
--
-- Output table:
-- your_project_id.ecommerce_analytics.stg_events

CREATE SCHEMA IF NOT EXISTS `ecommerce-product-analytics.ecommerce_analytics`
OPTIONS(location = "US");

CREATE OR REPLACE TABLE `ecommerce-product-analytics.ecommerce_analytics.stg_events`
PARTITION BY event_date
CLUSTER BY event_name, device_category, traffic_source, user_pseudo_id
AS

WITH base_events AS (
  SELECT
    _TABLE_SUFFIX AS source_table_suffix,
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    TIMESTAMP_MICROS(event_timestamp) AS event_timestamp_utc,
    DATETIME(TIMESTAMP_MICROS(event_timestamp), "UTC") AS event_datetime_utc,

    EXTRACT(DAYOFWEEK FROM TIMESTAMP_MICROS(event_timestamp)) AS event_day_of_week,
    EXTRACT(HOUR FROM TIMESTAMP_MICROS(event_timestamp)) AS event_hour_utc,

    event_timestamp,
    event_previous_timestamp,
    event_name,
    event_bundle_sequence_id,
    user_pseudo_id,
    user_id,

    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
      LIMIT 1
    ) AS ga_session_id,

    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_number'
      LIMIT 1
    ) AS ga_session_number,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'page_location'
      LIMIT 1
    ) AS page_location,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'page_title'
      LIMIT 1
    ) AS page_title,

    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'page_referrer'
      LIMIT 1
    ) AS page_referrer,

    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'engagement_time_msec'
      LIMIT 1
    ) AS engagement_time_msec,

    COALESCE(
      (
        SELECT ep.value.string_value
        FROM UNNEST(event_params) AS ep
        WHERE ep.key = 'session_engaged'
        LIMIT 1
      ),
      CAST((
        SELECT ep.value.int_value
        FROM UNNEST(event_params) AS ep
        WHERE ep.key = 'session_engaged'
        LIMIT 1
      ) AS STRING)
    ) AS session_engaged,

    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'entrances'
      LIMIT 1
    ) AS entrances,

    COALESCE(device.category, 'unknown') AS device_category,
    COALESCE(device.mobile_brand_name, 'unknown') AS mobile_brand_name,
    COALESCE(device.mobile_model_name, 'unknown') AS mobile_model_name,
    COALESCE(device.operating_system, 'unknown') AS operating_system,
    COALESCE(device.language, 'unknown') AS device_language,
    COALESCE(device.web_info.browser, 'unknown') AS browser,

    COALESCE(geo.continent, 'unknown') AS continent,
    COALESCE(geo.country, 'unknown') AS country,
    COALESCE(geo.region, 'unknown') AS region,
    COALESCE(geo.city, 'unknown') AS city,

    COALESCE(traffic_source.name, 'unknown') AS traffic_campaign,
    COALESCE(traffic_source.medium, 'unknown') AS traffic_medium,
    COALESCE(traffic_source.source, 'unknown') AS traffic_source,

    COALESCE(platform, 'unknown') AS platform,
    stream_id,

    ecommerce.transaction_id,
    ecommerce.total_item_quantity,
    ecommerce.unique_items,
    ecommerce.purchase_revenue,
    ecommerce.refund_value,
    ecommerce.shipping_value,
    ecommerce.tax_value,

    CASE WHEN event_name = 'session_start' THEN 1 ELSE 0 END AS is_session_start,
    CASE WHEN event_name = 'view_item' THEN 1 ELSE 0 END AS is_view_item,
    CASE WHEN event_name = 'add_to_cart' THEN 1 ELSE 0 END AS is_add_to_cart,
    CASE WHEN event_name = 'begin_checkout' THEN 1 ELSE 0 END AS is_begin_checkout,
    CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END AS is_purchase,

    ARRAY_LENGTH(items) AS item_array_length

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE
    _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

final AS (
  SELECT
    TO_HEX(SHA256(CONCAT(
      COALESCE(user_pseudo_id, 'missing_user'),
      '|',
      CAST(event_timestamp AS STRING),
      '|',
      COALESCE(event_name, 'missing_event'),
      '|',
      COALESCE(CAST(event_bundle_sequence_id AS STRING), 'missing_bundle')
    ))) AS event_key,

    CASE
      WHEN user_pseudo_id IS NOT NULL AND ga_session_id IS NOT NULL
        THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))
      ELSE NULL
    END AS session_key,

    *

  FROM base_events
)

SELECT
  *
FROM final;