# Tableau Calculated Fields & Dashboard Logic

<!--
===============================================================================
Project: Tableau Calculated Fields & Dashboard Logic
Author: Vineeth Inturi

Purpose:
This portfolio project showcases Tableau calculation patterns used for dashboard
interactivity, KPI highlighting, business-rule logic, date-range analysis,
visual classifications, ranking, margin review, inventory risk detection, and
stakeholder-ready reporting.

===============================================================================
-->

---

## Project Overview

This portfolio file demonstrates how Tableau can be used for dashboard-level calculations that support dynamic filtering, visual KPI logic, ranking, color rules, date-range analysis, margin review, inventory risk detection, return tracking, store activation analysis, and operational reporting.

The goal is to separate database preparation from dashboard interactivity:

- **SQL** prepares trusted, validated, reusable datasets.
- **Tableau** handles user-driven logic, visual classification, dashboard interactivity, ranking, and KPI highlighting.

---
<!-- ======================================================================= -->
<!-- SECTION 1: TABLEAU DATA MODELING APPROACH                               -->
<!-- ======================================================================= -->

## Tableau Data Modeling Approach

When combining datasets with different levels of detail, Tableau relationships are often better than physical joins.

Relationships help Tableau query each table at its own level of detail and reduce the risk of duplicate rows or inflated measures.

### Example Data Grain

```text
Sales History       → Product + Store + Date grain
Inventory Snapshot  → Product + Store + Snapshot Date grain
Product Master      → Product grain
Store Master        → Store grain
Pricing History     → Product + Effective Date grain
Budget Data         → Store + Month grain
Returns Data        → Product + Store + Return Event grain
```

### Why Relationships Are Useful

Using relationships instead of forcing every table into one physical join helps prevent:

- Inflated sales
- Duplicated inventory quantities
- Repeated budget values
- Incorrect return counts
- Overstated margin calculations
- Incorrect dashboard totals

---

<!-- ======================================================================= -->
<!-- SECTION 2: RETURNS TRACKING LOGIC                                       -->
<!-- ======================================================================= -->

## 1. Return Status Color Logic

### Business Use Case

This calculation visually identifies return status based on expected return date, completed return date, returned quantity, and expected return quantity.

This type of logic is helpful when business teams need to quickly identify which returns are overdue, due soon, completed, partially completed, or still open.

### Tableau Calculated Field: Return Status

```tableau
IF ISNULL([Return Completed Date])
   AND TODAY() > [Expected Return Date] THEN "Overdue"

ELSEIF ISNULL([Return Completed Date])
   AND DATEDIFF('day', TODAY(), [Expected Return Date]) <= 7 THEN "Due Soon"

ELSEIF NOT ISNULL([Return Completed Date])
   AND [Returned Quantity] >= [Expected Return Quantity] THEN "Completed"

ELSEIF NOT ISNULL([Return Completed Date])
   AND [Returned Quantity] < [Expected Return Quantity] THEN "Partially Completed"

ELSE "Open"
END
```


### Dashboard Usage

- Return tracking table
- Store/product return status
- Return aging dashboard
- Operational exception reporting
- Vendor return monitoring

---

## 2. Return Aging Bucket

### Business Use Case

Groups open returns based on how long they have been pending or overdue.

This helps stakeholders prioritize older return items instead of reviewing every open return manually.

### Tableau Calculated Field: Return Aging Bucket

```tableau
IF ISNULL([Return Completed Date]) THEN

    IF DATEDIFF('day', [Expected Return Date], TODAY()) <= 0 THEN "Not Due"

    ELSEIF DATEDIFF('day', [Expected Return Date], TODAY()) <= 7 THEN "1-7 Days Overdue"

    ELSEIF DATEDIFF('day', [Expected Return Date], TODAY()) <= 30 THEN "8-30 Days Overdue"

    ELSE "30+ Days Overdue"
    END

ELSE "Closed"
END
```

### Dashboard Usage

- Color shelf
- Filter shelf
- Return summary cards
- Aging exception view
- Open return prioritization

---

<!-- ======================================================================= -->
<!-- SECTION 3: INVENTORY AND SALES PERFORMANCE LOGIC                         -->
<!-- ======================================================================= -->

## 3. High Sales / Low Inventory Flag

### Business Use Case

Highlights products with strong sales but low inventory availability.

This is useful for identifying potential stockout risk, replenishment opportunities, and products where demand is stronger than available supply.

### Tableau Calculated Field: High Sales / Low Inventory Flag

```tableau
IF [Sales Units] >= [High Sales Threshold]
   AND [BOH Quantity] <= [Low Inventory Threshold]
THEN "High Sales / Low Inventory"

ELSEIF [Sales Units] >= [High Sales Threshold]
   AND [BOH Quantity] > [Low Inventory Threshold]
THEN "High Sales / Healthy Inventory"

ELSEIF [Sales Units] < [High Sales Threshold]
   AND [BOH Quantity] > [Excess Inventory Threshold]
THEN "Slow Sales / High Inventory"

ELSE "Normal"
END
```

### Dashboard Usage

- Stockout monitoring
- Replenishment review
- Overstock identification
- Product/store exception reporting
- Inventory availability dashboard

---

## 4. Sales Performance Color Logic

### Business Use Case

Classifies product, store, or category performance based on sales growth percentage.

This allows business users to quickly identify strong growth, stable performance, slight declines, and significant declines.

### Tableau Calculated Field: Sales Performance Status

```tableau
IF [Sales Growth %] >= 0.15 THEN "Strong Growth"

ELSEIF [Sales Growth %] >= 0
   AND [Sales Growth %] < 0.15 THEN "Stable / Positive"

ELSEIF [Sales Growth %] >= -0.10
   AND [Sales Growth %] < 0 THEN "Slight Decline"

ELSE "Significant Decline"
END
```

### Recommended Color Assignment

```text
Strong Growth        → Green
Stable / Positive    → Blue
Slight Decline       → Orange
Significant Decline  → Red
```

### Dashboard Usage

- Category trend dashboard
- Store performance view
- Executive KPI cards
- Product movement analysis
- National sales performance dashboard

---

<!-- ======================================================================= -->
<!-- SECTION 4: DATE RANGE AND TIME-BASED DASHBOARD LOGIC                    -->
<!-- ======================================================================= -->

## 5. Dynamic Date Range Selector

### Business Use Case

Allows users to switch between multiple date ranges without changing SQL or rebuilding the dashboard.

This is useful when business users want to compare short-term and long-term performance from the same dashboard.

### Tableau Parameter

```text
Parameter Name: Date Range Selector

Parameter Values:
- Last 7 Days
- Last 30 Days
- Last 13 Weeks
- Year to Date
- Last 12 Months
```

### Tableau Calculated Field: Date Range Filter

```tableau
CASE [Date Range Selector]

WHEN "Last 7 Days" THEN
    [Transaction Date] >= DATEADD('day', -7, TODAY())

WHEN "Last 30 Days" THEN
    [Transaction Date] >= DATEADD('day', -30, TODAY())

WHEN "Last 13 Weeks" THEN
    [Transaction Date] >= DATEADD('week', -13, TODAY())

WHEN "Year to Date" THEN
    DATETRUNC('year', [Transaction Date]) = DATETRUNC('year', TODAY())

WHEN "Last 12 Months" THEN
    [Transaction Date] >= DATEADD('month', -12, TODAY())

END
```

### Dashboard Usage

Drag this calculated field to Filters and keep:

```text
True
```

### Use Cases

- Sales trend dashboard
- Return tracking dashboard
- Inventory movement analysis
- Product performance view
- Store-level reporting

---

## 6. Rolling 13-Week Sales

### Business Use Case

Used for dashboards where weekly sales movement is more useful than daily transaction-level reporting.

Rolling views help smooth short-term variation and make performance trends easier to interpret.

### Tableau Calculated Field: Rolling 13-Week Sales

```tableau
WINDOW_SUM(SUM([Sales Amount]), -12, 0)
```

### Notes

This is a Tableau table calculation. It should be computed across week-level dates.

### Dashboard Usage

- Weekly sales trend
- Product movement analysis
- Category trend dashboard
- Performance smoothing
- 13-week business review reporting

---

<!-- ======================================================================= -->
<!-- SECTION 5: RANKING AND PERFORMANCE PRIORITIZATION                       -->
<!-- ======================================================================= -->

## 7. Rank Products by Sales Within Category

### Business Use Case

Ranks products dynamically within each category based on dashboard filters.

This is useful when stakeholders want to review top-selling products by category, store type, time period, or region.

### Tableau Calculated Field: Product Sales Rank

```tableau
RANK_DENSE(SUM([Sales Amount]), 'desc')
```

### Dashboard Usage

- Top products by category
- Category performance table
- Product prioritization view
- Sales contribution analysis
- Executive product performance summary

### Why Use Tableau Instead of SQL

Using Tableau ranking allows the rank to change dynamically based on filters such as:

- Date range
- Category
- Region
- Store type
- Product status
- Dashboard-level selections

---

## 8. Rank Stores by Sales Within State

### Business Use Case

Ranks stores dynamically within each state or region based on sales performance.

This is useful for national sales footprint dashboards and store-level performance reporting.

### Tableau Calculated Field: Store Sales Rank

```tableau
RANK_DENSE(SUM([Sales Amount]), 'desc')
```

### Dashboard Usage

- State-level sales dashboard
- Store performance ranking
- Regional sales review
- Network-level performance analysis

---

<!-- ======================================================================= -->
<!-- SECTION 6: MARGIN AND PRICING LOGIC                                     -->
<!-- ======================================================================= -->

## 9. Margin Performance Label

### Business Use Case

Classifies profitability performance based on gross margin percentage.

This helps identify high-margin, healthy-margin, low-margin, and negative-margin products.

### Tableau Calculated Field: Margin Performance Label

```tableau
IF [Gross Margin %] >= 0.35 THEN "High Margin"

ELSEIF [Gross Margin %] >= 0.20 THEN "Healthy Margin"

ELSEIF [Gross Margin %] >= 0.05 THEN "Low Margin"

ELSEIF [Gross Margin %] < 0 THEN "Negative Margin"

ELSE "Review"
END
```

### Dashboard Usage

- Product-level margin table
- Pricing review dashboard
- Package price analysis
- Low-margin product identification
- Category profitability review

---

## 10. Package Pricing Review Flag

### Business Use Case

Identifies products where average selling price is below package benchmark, retail benchmark, or cost threshold.

This helps identify pricing alignment issues and possible margin leakage.

### Tableau Calculated Field: Package Pricing Review Flag

```tableau
IF [Average Selling Price] < [Package Price] THEN "Below Package Price"

ELSEIF [Average Selling Price] < [Retail Price] THEN "Below Retail Price"

ELSEIF [Average Selling Price] >= [Retail Price] THEN "At / Above Retail"

ELSE "Review"
END
```

### Dashboard Usage

- Package pricing review
- Profitability analysis
- Margin leakage detection
- Product pricing exception reporting
- PM package pricing analysis

---

## 11. Gross Margin %

### Business Use Case

Calculates gross margin percentage for product, category, store, or package-level profitability analysis.

### Tableau Calculated Field: Gross Margin %

```tableau
IF SUM([Sales Amount]) = 0 THEN 0
ELSE
    (SUM([Sales Amount]) - SUM([Cost Amount]))
    /
    SUM([Sales Amount])
END
```

### Dashboard Usage

- Margin KPI cards
- Product profitability table
- Category margin trend
- Pricing review dashboard

---

## 12. Price Variance vs Retail %

### Business Use Case

Measures how far average selling price is above or below retail benchmark.

### Tableau Calculated Field: Price Variance vs Retail %

```tableau
IF AVG([Retail Price]) = 0 THEN 0
ELSE
    (AVG([Average Selling Price]) - AVG([Retail Price]))
    /
    AVG([Retail Price])
END
```

### Dashboard Usage

- Pricing exception reporting
- Retail price alignment review
- Product pricing analysis
- Margin leakage detection

---

<!-- ======================================================================= -->
<!-- SECTION 7: BUDGET AND FINANCIAL PERFORMANCE LOGIC                       -->
<!-- ======================================================================= -->

## 13. Store-Level Budget Variance Status

### Business Use Case

Classifies store-level actual performance against budget.

This supports operational and finance review by quickly identifying stores that are above budget, on track, slightly below budget, or below budget.

### Tableau Calculated Field: Budget Variance Status

```tableau
IF [Budget Variance %] >= 0.10 THEN "Above Budget"

ELSEIF [Budget Variance %] >= 0
   AND [Budget Variance %] < 0.10 THEN "On Track"

ELSEIF [Budget Variance %] >= -0.10
   AND [Budget Variance %] < 0 THEN "Slightly Below Budget"

ELSE "Below Budget"
END
```

### Recommended Color Assignment

```text
Above Budget            → Green
On Track                → Blue
Slightly Below Budget   → Orange
Below Budget            → Red
```

### Dashboard Usage

- Store-level budget summary
- Budget vs actual dashboard
- Finance review
- Operational performance reporting
- Monthly business review

---

## 14. Budget Variance %

### Business Use Case

Calculates the percentage difference between actual performance and budget.

### Tableau Calculated Field: Budget Variance %

```tableau
IF SUM([Budget Amount]) = 0 THEN 0
ELSE
    (SUM([Actual Amount]) - SUM([Budget Amount]))
    /
    SUM([Budget Amount])
END
```

### Dashboard Usage

- Budget summary dashboard
- Finance variance reporting
- Store-level performance review
- Executive KPI cards

---

<!-- ======================================================================= -->
<!-- SECTION 8: INVENTORY RISK SCORING                                       -->
<!-- ======================================================================= -->

## 15. Inventory Risk Score

### Business Use Case

Creates a weighted risk score to prioritize product/store combinations needing attention.

This can help business teams identify stockout risk, replenishment gaps, and high-demand products with low availability.

### Tableau Calculated Field: Inventory Risk Score

```tableau
(
    IF [BOH Quantity] = 0 THEN 40 ELSE 0 END
)
+
(
    IF [Sales Units] >= [High Sales Threshold] THEN 30 ELSE 0 END
)
+
(
    IF [On Order Quantity] = 0 THEN 20 ELSE 0 END
)
+
(
    IF [Days Since Last Sale] <= 30 THEN 10 ELSE 0 END
)
```

### Tableau Calculated Field: Inventory Risk Classification

```tableau
IF [Inventory Risk Score] >= 70 THEN "High Risk"

ELSEIF [Inventory Risk Score] >= 40 THEN "Medium Risk"

ELSE "Low Risk"
END
```

### Dashboard Usage

- Stockout monitoring
- Replenishment prioritization
- Inventory review queue
- Product/store exception reporting
- Inventory outs dashboard

---

## 16. Days Since Last Sale

### Business Use Case

Calculates how many days have passed since the last sale date.

This helps identify slow movement, stockout risk, and inactive product/store combinations.

### Tableau Calculated Field: Days Since Last Sale

```tableau
DATEDIFF('day', [Last Sale Date], TODAY())
```

### Dashboard Usage

- Inventory outs dashboard
- Product movement analysis
- Slow-moving inventory review
- Stockout monitoring

---

<!-- ======================================================================= -->
<!-- SECTION 9: NEW ITEM ROLLOUT AND STORE ACTIVATION LOGIC                 -->
<!-- ======================================================================= -->

## 17. New Item Rollout Status

### Business Use Case

Classifies new items based on rollout date, active stores, sales movement, and inventory position.

This is useful for monitoring new item adoption, store activation, and post-launch performance.

### Tableau Calculated Field: New Item Rollout Status

```tableau
IF DATEDIFF('day', [Rollout Date], TODAY()) <= 30
   AND [Active Store Count] > 0
   AND [Sales Units] > 0
THEN "New Item Gaining Traction"

ELSEIF DATEDIFF('day', [Rollout Date], TODAY()) <= 30
   AND [Active Store Count] > 0
   AND [Sales Units] = 0
THEN "Rolled Out / No Sales Yet"

ELSEIF DATEDIFF('day', [Rollout Date], TODAY()) > 30
   AND [Sales Units] > 0
THEN "Established Selling Item"

ELSEIF DATEDIFF('day', [Rollout Date], TODAY()) > 30
   AND [BOH Quantity] > 0
   AND [Sales Units] = 0
THEN "Inventory Without Movement"

ELSE "Review"
END
```

### Dashboard Usage

- New item rollout dashboard
- Store activation tracking
- Product launch monitoring
- Inventory and sales adoption review

---

## 18. Active Store Coverage %

### Business Use Case

Measures how widely a product is active across eligible stores or shops.

### Tableau Calculated Field: Active Store Coverage %

```tableau
COUNTD(IF [Active Item Flag] = "Y" THEN [Store ID] END)
/
COUNTD([Eligible Store ID])
```

### Dashboard Usage

- Store activation tracking
- Product rollout coverage
- Item adoption analysis
- Network-level product visibility

---

## 19. Average Sales Per Active Store

### Business Use Case

Shows product performance only across stores where the item is active.

### Tableau Calculated Field: Average Sales Per Active Store

```tableau
SUM([Sales Amount])
/
COUNTD(IF [Active Item Flag] = "Y" THEN [Store ID] END)
```

### Dashboard Usage

- New item rollout analysis
- Product adoption performance
- Store-level sales comparison
- Network sales productivity

---

## 20. Active Store Count

### Business Use Case

Counts the number of stores where an item is active.

### Tableau Calculated Field: Active Store Count

```tableau
COUNTD(
    IF [Active Item Flag] = "Y" THEN [Store ID] END
)
```

### Dashboard Usage

- New item rollout dashboard
- Store activation tracking
- Network coverage reporting
- Product adoption analysis

---

<!-- ======================================================================= -->
<!-- SECTION 10: STOCKOUT AND INVENTORY AVAILABILITY LOGIC                   -->
<!-- ======================================================================= -->

## 21. Stockout Status

### Business Use Case

Classifies product/store combinations based on inventory availability and recent sales movement.

### Tableau Calculated Field: Stockout Status

```tableau
IF [BOH Quantity] = 0
   AND [Sales Units] > 0
THEN "Stockout Risk"

ELSEIF [BOH Quantity] = 0
   AND [On Order Quantity] > 0
THEN "Out of Stock / On Order"

ELSEIF [BOH Quantity] = 0
   AND [On Order Quantity] = 0
THEN "Out of Stock / No Order"

ELSE "In Stock"
END
```

### Dashboard Usage

- Inventory outs dashboard
- Store/product availability review
- Replenishment monitoring
- Stockout exception reporting

---

## 22. Inventory Availability %

### Business Use Case

Measures percentage of eligible stores with available inventory.

### Tableau Calculated Field: Inventory Availability %

```tableau
COUNTD(
    IF [BOH Quantity] > 0 THEN [Store ID] END
)
/
COUNTD([Eligible Store ID])
```

### Dashboard Usage

- Inventory availability dashboard
- Product rollout tracking
- Store coverage reporting
- Network inventory health

---

<!-- ======================================================================= -->
<!-- SECTION 11: TABLEAU VS SQL DECISION GUIDE                               -->
<!-- ======================================================================= -->

## Tableau vs SQL Decision Guide

### Use SQL When

- Data needs to be cleaned before reporting
- Duplicate records need to be removed
- Historical tables need effective-date logic
- Source-to-target reconciliation is required
- Joins and transformations must be reusable
- Large datasets need to be reduced before Tableau
- Reporting tables need to be standardized
- Business logic must be shared across multiple dashboards
- Dashboard extracts need to be optimized
- Data quality checks need to happen before reporting

### Use Tableau Calculations When

- Business users need dynamic filters
- Color logic changes based on dashboard use
- Ranking should respond to filters
- Date range should be parameter-driven
- Visual labels are dashboard-specific
- Table calculations are needed
- KPI status needs to be shown differently across views
- Users need dashboard interactivity
- Metrics should respond to dashboard-level filters
- Business rules are specific to one dashboard view

---

<!-- ======================================================================= -->
<!-- SECTION 12: PORTFOLIO SUMMARY                                           -->
<!-- ======================================================================= -->

## Portfolio Summary

These Tableau calculated fields demonstrate dashboard-level logic for:

- Returns tracking
- Return aging analysis
- Date-range analysis
- Sales performance classification
- Inventory risk detection
- Stockout monitoring
- Margin review
- Package pricing analysis
- Budget variance reporting
- New item rollout tracking
- Store activation analysis
- Dynamic ranking
- Visual KPI highlighting
- Executive-ready dashboard logic

This approach reflects a practical analytics workflow where SQL prepares trusted, validated, reusable data, while Tableau supports user-driven logic, visual classification, and interactive business reporting.

---

