# Data Quality and Feature Engineering Notes

## Null and Placeholder Handling

- Missing device, traffic source, traffic medium, geo, and product category values were standardized to `unknown`.
- Empty strings and placeholder values such as `(not set)` were treated as missing where relevant.
- `SAFE_DIVIDE()` was used for conversion rates to avoid divide-by-zero errors.
- Missing item price and quantity values were flagged instead of silently removed.

## Revenue Handling

- Transaction-level revenue uses `ecommerce.purchase_revenue`.
- Item-level revenue uses `item_revenue` when available, otherwise `price * quantity`.
- Revenue fields were checked for null, zero, negative, and extreme values.

## Session Features

- `session_key` was engineered using `user_pseudo_id` and `ga_session_id`.
- Session duration, engagement time, funnel flags, landing page, exit page, device, and traffic source were engineered at the session level.

## User Features

- User-level features include sessions, product views, carts, checkouts, purchases, revenue, recency, engagement, category preference, abandonment behavior, and lifecycle status.
- Business-readable segments were created for high-intent non-buyers, cart abandoners, checkout abandoners, one-time buyers, repeat buyers, and high-value customers.

## Modeling Considerations

- Extreme behavioral values should be winsorized or log-transformed during predictive modeling.
- Categorical values such as source, medium, device, and category should be one-hot encoded.
- Revenue-heavy features should not be used directly when predicting purchase if they create target leakage.