-- Federated analytics: Customer lifetime value analysis
-- This view combines cloud-native customer data from BigQuery with
-- transactional order data from AlloyDB Omni via federation

SELECT 
    c.customer_id,
    c.customer_name,
    c.region,
    c.signup_date,
    COALESCE(orders_summary.total_orders, 0) as total_orders,
    COALESCE(orders_summary.total_revenue, 0.0) as total_revenue,
    COALESCE(orders_summary.avg_order_value, 0.0) as avg_order_value,
    orders_summary.last_order_date,
    orders_summary.first_order_date,
    orders_summary.order_status_summary,
    
    -- Calculate customer lifetime value metrics
    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), c.signup_date, DAY) > 0 
        THEN ROUND(COALESCE(orders_summary.total_revenue, 0.0) / DATE_DIFF(CURRENT_DATE(), c.signup_date, DAY), 2)
        ELSE 0.0 
    END as daily_clv,
    
    CASE 
        WHEN orders_summary.last_order_date IS NOT NULL AND orders_summary.first_order_date IS NOT NULL
        AND DATE_DIFF(orders_summary.last_order_date, orders_summary.first_order_date, DAY) > 0
        THEN ROUND(orders_summary.total_orders / DATE_DIFF(orders_summary.last_order_date, orders_summary.first_order_date, DAY), 2)
        ELSE 0.0
    END as order_frequency_per_day,
    
    -- Customer segmentation
    CASE 
        WHEN COALESCE(orders_summary.total_revenue, 0) >= 50000 THEN 'High Value'
        WHEN COALESCE(orders_summary.total_revenue, 0) >= 20000 THEN 'Medium Value'
        WHEN COALESCE(orders_summary.total_revenue, 0) > 0 THEN 'Low Value'
        ELSE 'No Orders'
    END as customer_segment,
    
    -- Recency analysis
    CASE 
        WHEN orders_summary.last_order_date IS NULL THEN 'No Orders'
        WHEN DATE_DIFF(CURRENT_DATE(), orders_summary.last_order_date, DAY) <= 30 THEN 'Active'
        WHEN DATE_DIFF(CURRENT_DATE(), orders_summary.last_order_date, DAY) <= 90 THEN 'Recent'
        WHEN DATE_DIFF(CURRENT_DATE(), orders_summary.last_order_date, DAY) <= 365 THEN 'Dormant'
        ELSE 'Inactive'
    END as recency_status

FROM `${project_id}.cloud_analytics.customers` c
LEFT JOIN (
    SELECT 
        customer_id,
        COUNT(*) as total_orders,
        SUM(order_amount) as total_revenue,
        AVG(order_amount) as avg_order_value,
        MIN(order_date) as first_order_date,
        MAX(order_date) as last_order_date,
        
        -- Order status summary
        STRING_AGG(
            DISTINCT order_status, 
            ', ' 
            ORDER BY order_status
        ) as order_status_summary,
        
        -- Count of different order statuses
        COUNTIF(order_status = 'completed') as completed_orders,
        COUNTIF(order_status = 'pending') as pending_orders,
        COUNTIF(order_status = 'in_progress') as in_progress_orders
        
    FROM EXTERNAL_QUERY(
        '${project_id}.${region}.${connection_id}',
        'SELECT 
            customer_id, 
            order_amount, 
            order_date, 
            order_status,
            product_name
        FROM orders
        WHERE customer_id IS NOT NULL'
    )
    GROUP BY customer_id
) orders_summary ON c.customer_id = orders_summary.customer_id

ORDER BY 
    total_revenue DESC NULLS LAST,
    total_orders DESC NULLS LAST,
    c.customer_name