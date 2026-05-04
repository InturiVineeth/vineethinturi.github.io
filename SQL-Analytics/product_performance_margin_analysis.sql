/* 
===============================================================================
Project: Product Performance, Pricing & Margin Analysis
Author: Vineeth Inturi
Purpose:
    This SQL example demonstrates how to combine sales, inventory, cost, retail
    price, package price, and product hierarchy data to analyze category-level
    profitability, gross margin, and product performance.

Notes:
    - This is a recreated portfolio example using generic table and column names.
    - No confidential company data, table names, pricing, or product identifiers
      are included.
    - Logic is designed in a Snowflake-style SQL format.
===============================================================================
*/

WITH sales_summary AS (
    SELECT
        s.product_id,
        s.store_id,
        DATE_TRUNC('month', s.sales_date) AS sales_month,

        SUM(s.sales_units) AS total_units_sold,
        SUM(s.sales_amount) AS total_sales_amount,

        CASE
            WHEN SUM(s.sales_units) = 0 THEN 0
            ELSE SUM(s.sales_amount) / NULLIF(SUM(s.sales_units), 0)
        END AS avg_selling_price

    FROM analytics_sample.fact_sales s
    WHERE s.sales_date >= DATEADD(month, -12, CURRENT_DATE)
    GROUP BY
        s.product_id,
        s.store_id,
        DATE_TRUNC('month', s.sales_date)
),

cost_summary AS (
    SELECT
        c.product_id,
        c.store_id,

        AVG(c.unit_cost) AS avg_unit_cost,
        MAX(c.effective_date) AS latest_cost_effective_date

    FROM analytics_sample.product_cost c
    WHERE c.effective_date <= CURRENT_DATE
    GROUP BY
        c.product_id,
        c.store_id
),

retail_price_summary AS (
    SELECT
        r.product_id,
        r.store_id,

        r.retail_price,
        r.effective_start_date,
        r.effective_end_date

    FROM analytics_sample.product_retail_price r
    WHERE CURRENT_DATE BETWEEN r.effective_start_date 
                           AND COALESCE(r.effective_end_date, '9999-12-31')
),

package_price_summary AS (
    SELECT
        p.package_id,
        p.product_id,
        p.package_type,
        p.package_price,
        p.effective_start_date,
        p.effective_end_date

    FROM analytics_sample.product_package_price p
    WHERE CURRENT_DATE BETWEEN p.effective_start_date 
                           AND COALESCE(p.effective_end_date, '9999-12-31')
),

product_master AS (
    SELECT
        pm.product_id,
        pm.product_description,
        pm.category,
        pm.sub_category,
        pm.vendor_name,
        pm.product_status

    FROM analytics_sample.dim_product pm
),

inventory_summary AS (
    SELECT
        i.product_id,
        i.store_id,

        SUM(i.on_hand_qty) AS current_boh,
        SUM(i.on_order_qty) AS on_order_qty,
        SUM(i.inventory_value) AS inventory_value

    FROM analytics_sample.fact_inventory_snapshot i
    WHERE i.snapshot_date = (
        SELECT MAX(snapshot_date)
        FROM analytics_sample.fact_inventory_snapshot
    )
    GROUP BY
        i.product_id,
        i.store_id
),

final_margin_analysis AS (
    SELECT
        ss.sales_month,
        ss.store_id,
        ss.product_id,

        pm.product_description,
        pm.category,
        pm.sub_category,
        pm.vendor_name,
        pm.product_status,

        ss.total_units_sold,
        ss.total_sales_amount,
        ss.avg_selling_price,

        cs.avg_unit_cost,
        rps.retail_price,
        pps.package_type,
        pps.package_price,

        inv.current_boh,
        inv.on_order_qty,
        inv.inventory_value,

        /* Cost and profitability calculations */
        ss.total_units_sold * cs.avg_unit_cost AS estimated_total_cost,

        ss.total_sales_amount 
            - (ss.total_units_sold * cs.avg_unit_cost) AS gross_profit,

        CASE
            WHEN ss.total_sales_amount = 0 THEN 0
            ELSE (
                ss.total_sales_amount 
                - (ss.total_units_sold * cs.avg_unit_cost)
            ) / NULLIF(ss.total_sales_amount, 0)
        END AS gross_margin_pct,

        /* Retail price variance */
        ss.avg_selling_price - rps.retail_price AS avg_price_vs_retail_price,

        CASE
            WHEN rps.retail_price = 0 THEN 0
            ELSE (ss.avg_selling_price - rps.retail_price) 
                 / NULLIF(rps.retail_price, 0)
        END AS avg_price_vs_retail_pct,

        /* Package price variance */
        ss.avg_selling_price - pps.package_price AS avg_price_vs_package_price,

        CASE
            WHEN pps.package_price = 0 THEN 0
            ELSE (ss.avg_selling_price - pps.package_price) 
                 / NULLIF(pps.package_price, 0)
        END AS avg_price_vs_package_pct,

        /* P/L indicator */
        CASE
            WHEN ss.total_sales_amount 
                 - (ss.total_units_sold * cs.avg_unit_cost) > 0 
                THEN 'Profit'
            WHEN ss.total_sales_amount 
                 - (ss.total_units_sold * cs.avg_unit_cost) < 0 
                THEN 'Loss'
            ELSE 'Break Even'
        END AS profit_loss_status,

        /* Business performance classification */
        CASE
            WHEN ss.total_units_sold >= 100 
                 AND (
                    ss.total_sales_amount 
                    - (ss.total_units_sold * cs.avg_unit_cost)
                 ) > 0
                THEN 'High Sales / Profitable'

            WHEN ss.total_units_sold >= 100 
                 AND (
                    ss.total_sales_amount 
                    - (ss.total_units_sold * cs.avg_unit_cost)
                 ) <= 0
                THEN 'High Sales / Low Margin'

            WHEN ss.total_units_sold < 25 
                 AND inv.current_boh > 0
                THEN 'Slow Moving Inventory'

            WHEN inv.current_boh = 0 
                 AND ss.total_units_sold > 0
                THEN 'Potential Stockout Risk'

            ELSE 'Monitor'
        END AS product_performance_flag

    FROM sales_summary ss

    LEFT JOIN product_master pm
        ON ss.product_id = pm.product_id

    LEFT JOIN cost_summary cs
        ON ss.product_id = cs.product_id
       AND ss.store_id = cs.store_id

    LEFT JOIN retail_price_summary rps
        ON ss.product_id = rps.product_id
       AND ss.store_id = rps.store_id

    LEFT JOIN package_price_summary pps
        ON ss.product_id = pps.product_id

    LEFT JOIN inventory_summary inv
        ON ss.product_id = inv.product_id
       AND ss.store_id = inv.store_id
)

SELECT
    sales_month,
    category,
    sub_category,
    vendor_name,
    product_id,
    product_description,
    product_status,
    store_id,

    total_units_sold,
    total_sales_amount,
    avg_selling_price,
    avg_unit_cost,
    retail_price,
    package_type,
    package_price,

    current_boh,
    on_order_qty,
    inventory_value,

    estimated_total_cost,
    gross_profit,
    ROUND(gross_margin_pct * 100, 2) AS gross_margin_percent,

    avg_price_vs_retail_price,
    ROUND(avg_price_vs_retail_pct * 100, 2) AS avg_price_vs_retail_percent,

    avg_price_vs_package_price,
    ROUND(avg_price_vs_package_pct * 100, 2) AS avg_price_vs_package_percent,

    profit_loss_status,
    product_performance_flag

FROM final_margin_analysis
ORDER BY
    sales_month DESC,
    category,
    gross_profit DESC;
