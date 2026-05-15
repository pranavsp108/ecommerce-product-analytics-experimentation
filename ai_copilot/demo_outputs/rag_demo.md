## 1. Answer

Leakage was avoided in the purchase propensity model by using only pre-cutoff user behavior to generate features and excluding fields that would reveal future purchase outcomes.

## 2. Supporting Definition or Methodology

The model target was `label_future_purchase`. Features were generated from behavior observed before the prediction window.

Excluded leakage-prone fields included:

- Future revenue fields
- Future purchase dates
- Buyer labels derived after the cutoff
- Any post-cutoff purchase behavior

## 3. Source Context Used

Source: `modeling_methodology.md`

## 4. Caveats

The documentation describes the leakage-prevention approach at a methodology level. The exact cutoff implementation should be reviewed in the SQL feature export file for full reproducibility.