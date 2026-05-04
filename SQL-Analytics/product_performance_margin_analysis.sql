/* 
===============================================================================
Project: Product Performance, Pricing & Margin Analysis
Purpose:
    This SQL example demonstrates how to combine sales, inventory, cost, retail
    price, package price, and product hierarchy data to analyze category-level
    profitability, gross margin, and product performance.
Notes:
    - This is a recreated portfolio example using generic table and column names.
    - No confidential company data, table names, pricing, or product identifiers
      are included.
===============================================================================
*/

WITH raw_sales AS (
    SELECT
        s.sales_id,
        s.product_id,
        s.store_id,
        s.sales_date,
        s.sales_units,
        s.sales_amount,
        s.transaction_type,
        s.updated_at,

        ROW_NUMBER() OVER (
            PARTITION BY s.sales_id
            ORDER BY s.updated_at DESC
        ) AS sales_record_rank

    FROM analytics_sample.fact_sales_raw s
    WHERE s.sales_date >= DATEADD(month, -18, CURRENT_DATE)
      AND s.transaction_type IN ('SALE', 'RETURN')
),

clean_sales AS (
    SELECT
        product_id,
        store_id,
        sales_date,

        CASE
            WHEN transaction_type = 'RETURN' THEN -1 * ABS(sales_units)
            ELSE sales_units
        END AS sales_units,

        CASE
            WHEN transaction_type = 'RETURN' THEN -1 * ABS(sales_amount)
            ELSE sales_amount
        END AS sales_amount

    FROM raw_sales
    WHERE sales_record_rank = 1
),

monthly_sales AS (
    SELECT
        product_id,
        store_id,
        DATE_TRUNC('month', sales_date) AS sales_month,

        SUM(sales_units) AS total_units_sold,
        SUM(sales_amount) AS total_sales_amount,

        CASE
            WHEN SUM(sales_units) = 0 THEN 0
            ELSE SUM(sales_amount) / NULLIF(SUM(sales_units), 0)
        END AS avg_selling_price

    FROM clean_sales
    GROUP BY
        product_id,
        store_id,
        DATE_TRUNC('month', sales_date)
),

deduped_cost AS (
    SELECT
        c.product_id,
        c.store_id,
        c.unit_cost,
        c.effective_start_date,
        c.effective_end_date,
        c.updated_at,

        ROW_NUMBER() OVER (
            PARTITION BY c.product_id, c.store_id, c.effective_start_date
            ORDER BY c.updated_at DESC
        ) AS cost_rank

    FROM analytics_sample.product_cost_history c
),

active_cost_by_month AS (
    SELECT
        ms.product_id,
        ms.store_id,
        ms.sales_month,
        dc.unit_cost,

        ROW_NUMBER() OVER (
            PARTITION BY ms.product_id, ms.store_id, ms.sales_month
            ORDER BY dc.effective_start_date DESC
        ) AS active_cost_rank

    FROM monthly_sales ms
    LEFT JOIN deduped_cost dc
        ON ms.product_id = dc.product_id
       AND ms.store_id = dc.store_id
       AND ms.sales_month >= DATE_TRUNC('month', dc.effective_start_date)
       AND ms.sales_month < DATE_TRUNC(
            'month',
            COALESCE(dc.effective_end_date, '9999-12-31')
       )
       AND dc.cost_rank = 1
),

monthly_cost AS (
    SELECT
        product_id,
        store_id,
        sales_month,
        unit_cost
    FROM active_cost_by_month
    WHERE active_cost_rank = 1
),

deduped_retail_price AS (
    SELECT
        r.product_id,
        r.store_id,
        r.retail_price,
        r.effective_start_date,
        r.effective_end_date,
        r.updated_at,

        ROW_NUMBER() OVER (
            PARTITION BY r.product_id, r.store_id, r.effective_start_date
            ORDER BY r.updated_at DESC
        ) AS retail_price_rank

    FROM analytics_sample.product_retail_price_history r
),

active_retail_price_by_month AS (
    SELECT
        ms.product_id,
        ms.store_id,
        ms.sales_month,
        rp.retail_price,

        ROW_NUMBER() OVER (
            PARTITION BY ms.product_id, ms.store_id, ms.sales_month
            ORDER BY rp.effective_start_date DESC
        ) AS active_retail_rank

    FROM monthly_sales ms
    LEFT JOIN deduped_retail_price rp
        ON ms.product_id = rp.product_id
       AND ms.store_id = rp.store_id
       AND ms.sales_month >= DATE_TRUNC('month', rp.effective_start_date)
       AND ms.sales_month < DATE_TRUNC(
            'month',
            COALESCE(rp.effective_end_date, '9999-12-31')
       )
       AND rp.retail_price_rank = 1
),

monthly_retail_price AS (
    SELECT
        product_id,
        store_id,
        sales_month,
        retail_price
    FROM active_retail_price_by_month
    WHERE active_retail_rank = 1
),

deduped_package_price AS (
    SELECT
        p.product_id,
        p.package_type,
        p.package_price,
        p.effective_start_date,
        p.effective_end_date,
        p.updated_at,

        ROW_NUMBER() OVER (
            PARTITION BY p.product_id, p.package_type, p.effective_start_date
            ORDER BY p.updated_at DESC
        ) AS package_price_rank

    FROM analytics_sample.product_package_price_history p
),

active_package_price_by_month AS (
    SELECT
        ms.product_id,
        ms.sales_month,
        pp.package_type,
        pp.package_price,

        ROW_NUMBER() OVER (
            PARTITION BY ms.product_id, ms.sales_month
            ORDER BY pp.effective_start_date DESC
        ) AS active_package_rank

    FROM monthly_sales ms
    LEFT JOIN deduped_package_price pp
        ON ms.product_id = pp.product_id
       AND ms.sales_month >= DATE_TRUNC('month', pp.effective_start_date)
       AND ms.sales_month < DATE_TRUNC(
            'month',
            COALESCE(pp.effective_end_date, '9999-12-31')
       )
       AND pp.package_price_rank = 1
),

monthly_package_price AS (
    SELECT
        product_id,
        sales_month,
        package_type,
        package_price
    FROM active_package_price_by_month
    WHERE active_package_rank = 1
),

product_master AS (
    SELECT
        product_id,
        product_description,
        category,
        sub_category,
        product_status,
        vendor_group
    FROM analytics_sample.dim_product
),

inventory_snapshot AS (
    SELECT
        product_id,
        store_id,
        snapshot_date,
        on_hand_qty,
        on_order_qty,
        inventory_value,

        ROW_NUMBER() OVER (
            PARTITION BY product_id, store_id
            ORDER BY snapshot_date DESC
        ) AS inventory_rank

    FROM analytics_sample.fact_inventory_snapshot
),

latest_inventory AS (
    SELECT
        product_id,
        store_id,
        on_hand_qty AS current_boh,
        on_order_qty,
        inventory_value
    FROM inventory_snapshot
    WHERE inventory_rank = 1
),

base_margin AS (
    SELECT
        ms.sales_month,
        ms.store_id,
        ms.product_id,

        pm.product_description,
        pm.category,
        pm.sub_category,
        pm.product_status,
        pm.vendor_group,

        ms.total_units_sold,
        ms.total_sales_amount,
        ms.avg_selling_price,

        mc.unit_cost,
        mrp.retail_price,
        mpp.package_type,
        mpp.package_price,

        li.current_boh,
        li.on_order_qty,
        li.inventory_value,

        ms.total_units_sold * mc.unit_cost AS estimated_total_cost,

        ms.total_sales_amount
            - (ms.total_units_sold * mc.unit_cost) AS gross_profit,

        CASE
            WHEN ms.total_sales_amount = 0 THEN 0
            ELSE (
                ms.total_sales_amount
                - (ms.total_units_sold * mc.unit_cost)
            ) / NULLIF(ms.total_sales_amount, 0)
        END AS gross_margin_pct,

        CASE
            WHEN mrp.retail_price = 0 THEN 0
            ELSE (ms.avg_selling_price - mrp.retail_price)
                 / NULLIF(mrp.retail_price, 0)
        END AS selling_price_vs_retail_pct,

        CASE
            WHEN mpp.package_price = 0 THEN 0
            ELSE (ms.avg_selling_price - mpp.package_price)
                 / NULLIF(mpp.package_price, 0)
        END AS selling_price_vs_package_pct,

        CASE
            WHEN mc.unit_cost = 0 THEN 0
            ELSE (ms.avg_selling_price - mc.unit_cost)
                 / NULLIF(mc.unit_cost, 0)
        END AS selling_price_vs_cost_pct

    FROM monthly_sales ms

    LEFT JOIN product_master pm
        ON ms.product_id = pm.product_id

    LEFT JOIN monthly_cost mc
        ON ms.product_id = mc.product_id
       AND ms.store_id = mc.store_id
       AND ms.sales_month = mc.sales_month

    LEFT JOIN monthly_retail_price mrp
        ON ms.product_id = mrp.product_id
       AND ms.store_id = mrp.store_id
       AND ms.sales_month = mrp.sales_month

    LEFT JOIN monthly_package_price mpp
        ON ms.product_id = mpp.product_id
       AND ms.sales_month = mpp.sales_month

    LEFT JOIN latest_inventory li
        ON ms.product_id = li.product_id
       AND ms.store_id = li.store_id
),

margin_with_history AS (
    SELECT
        bm.*,

        LAG(gross_margin_pct) OVER (
            PARTITION BY product_id, store_id
            ORDER BY sales_month
        ) AS prior_month_gross_margin_pct,

        LAG(total_sales_amount) OVER (
            PARTITION BY product_id, store_id
            ORDER BY sales_month
        ) AS prior_month_sales_amount,

        LAG(total_units_sold) OVER (
            PARTITION BY product_id, store_id
            ORDER BY sales_month
        ) AS prior_month_units_sold,

        gross_margin_pct
            - LAG(gross_margin_pct) OVER (
                PARTITION BY product_id, store_id
                ORDER BY sales_month
            ) AS margin_pct_change_mom,

        total_sales_amount
            - LAG(total_sales_amount) OVER (
                PARTITION BY product_id, store_id
                ORDER BY sales_month
            ) AS sales_amount_change_mom,

        total_units_sold
            - LAG(total_units_sold) OVER (
                PARTITION BY product_id, store_id
                ORDER BY sales_month
            ) AS units_change_mom

    FROM base_margin bm
),

category_totals AS (
    SELECT
        sales_month,
        category,

        SUM(total_sales_amount) AS category_sales_amount,
        SUM(gross_profit) AS category_gross_profit,

        CASE
            WHEN SUM(total_sales_amount) = 0 THEN 0
            ELSE SUM(gross_profit) / NULLIF(SUM(total_sales_amount), 0)
        END AS category_gross_margin_pct

    FROM margin_with_history
    GROUP BY
        sales_month,
        category
),

ranked_margin AS (
    SELECT
        mwh.*,
        ct.category_sales_amount,
        ct.category_gross_profit,
        ct.category_gross_margin_pct,

        CASE
            WHEN ct.category_sales_amount = 0 THEN 0
            ELSE mwh.total_sales_amount / NULLIF(ct.category_sales_amount, 0)
        END AS sales_contribution_to_category_pct,

        DENSE_RANK() OVER (
            PARTITION BY mwh.sales_month, mwh.category
            ORDER BY mwh.total_sales_amount DESC
        ) AS product_sales_rank_in_category,

        DENSE_RANK() OVER (
            PARTITION BY mwh.sales_month, mwh.category
            ORDER BY mwh.gross_profit DESC
        ) AS product_profit_rank_in_category,

        DENSE_RANK() OVER (
            PARTITION BY mwh.sales_month, mwh.category
            ORDER BY mwh.gross_margin_pct DESC
        ) AS product_margin_rank_in_category,

        DENSE_RANK() OVER (
            PARTITION BY mwh.sales_month, mwh.store_id
            ORDER BY mwh.total_sales_amount DESC
        ) AS product_sales_rank_in_store

    FROM margin_with_history mwh
    LEFT JOIN category_totals ct
        ON mwh.sales_month = ct.sales_month
       AND mwh.category = ct.category
),

final_output AS (
    SELECT
        sales_month,
        store_id,
        product_id,
        product_description,
        category,
        sub_category,
        product_status,
        vendor_group,

        total_units_sold,
        prior_month_units_sold,
        units_change_mom,

        total_sales_amount,
        prior_month_sales_amount,
        sales_amount_change_mom,

        avg_selling_price,
        unit_cost,
        retail_price,
        package_type,
        package_price,

        current_boh,
        on_order_qty,
        inventory_value,

        estimated_total_cost,
        gross_profit,

        ROUND(gross_margin_pct * 100, 2) AS gross_margin_percent,
        ROUND(prior_month_gross_margin_pct * 100, 2) AS prior_month_gross_margin_percent,
        ROUND(margin_pct_change_mom * 100, 2) AS margin_percent_change_mom,

        ROUND(selling_price_vs_retail_pct * 100, 2) AS selling_price_vs_retail_percent,
        ROUND(selling_price_vs_package_pct * 100, 2) AS selling_price_vs_package_percent,
        ROUND(selling_price_vs_cost_pct * 100, 2) AS selling_price_vs_cost_percent,

        ROUND(category_gross_margin_pct * 100, 2) AS category_gross_margin_percent,
        ROUND(sales_contribution_to_category_pct * 100, 2) AS sales_contribution_to_category_percent,

        product_sales_rank_in_category,
        product_profit_rank_in_category,
        product_margin_rank_in_category,
        product_sales_rank_in_store,

        CASE
            WHEN gross_margin_pct >= 0.35
                 AND total_sales_amount >= prior_month_sales_amount
                THEN 'Profitable Growth'

            WHEN gross_margin_pct >= 0.20
                 AND margin_pct_change_mom >= 0
                THEN 'Stable Margin'

            WHEN gross_margin_pct BETWEEN 0.05 AND 0.20
                 AND total_sales_amount > 0
                THEN 'Low Margin / Review Pricing'

            WHEN gross_margin_pct < 0
                THEN 'Negative Margin / Immediate Review'

            WHEN current_boh > 0
                 AND total_units_sold <= 0
                THEN 'Inventory Carrying Risk'

            ELSE 'Monitor'
        END AS margin_performance_status,

        CASE
            WHEN selling_price_vs_package_pct < -0.10
                THEN 'Selling Below Package Benchmark'

            WHEN selling_price_vs_retail_pct < -0.10
                THEN 'Selling Below Retail Benchmark'

            WHEN selling_price_vs_cost_pct < 0.15
                THEN 'Low Spread vs Cost'

            ELSE 'Pricing Within Expected Range'
        END AS pricing_review_flag

    FROM ranked_margin
)

SELECT *
FROM final_output
ORDER BY
    sales_month DESC,
    category,
    product_sales_rank_in_category,
    store_id;
