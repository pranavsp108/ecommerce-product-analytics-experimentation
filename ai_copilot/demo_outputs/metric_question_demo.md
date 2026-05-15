## 1. Direct Answer

The purchase propensity model performed well as a ranking model for identifying likely future buyers.

## 2. Supporting Numbers

- Random Forest ROC-AUC: 0.847
- Random Forest PR-AUC: 0.040
- Baseline future-purchase rate: 0.254%
- PR-AUC lift vs baseline: 15.8x
- Top 1% scored users purchase rate: 6.27%
- Top 1% lift vs baseline: 24.7x

## 3. Business Interpretation

Because future purchases are rare, PR-AUC and lift are more useful than accuracy. The model is not meant to perfectly classify every buyer. It is more useful for ranking users so marketing teams can prioritize high-propensity audiences.

## 4. Recommended Next Step

Use the Random Forest model to prioritize the top 1% to 10% of users for retargeting and personalized campaigns, then validate performance through a controlled campaign test.