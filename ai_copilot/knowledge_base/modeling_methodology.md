# Purchase Propensity Modeling Methodology

The purchase propensity model predicts future purchase likelihood using pre-cutoff user behavior.

The target is label_future_purchase.

Leakage prevention:
- Future revenue fields were excluded
- Future purchase dates were excluded
- Buyer labels derived after the cutoff were excluded
- Features were generated only from behavior before the prediction window

Evaluation:
- ROC-AUC
- PR-AUC
- Threshold tuning
- Decile lift
- Top-percentile lift

Because the positive class is rare, PR-AUC and lift are more informative than accuracy.