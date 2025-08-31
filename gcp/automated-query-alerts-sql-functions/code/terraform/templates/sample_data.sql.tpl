-- Sample data SQL template for testing query performance alerts
-- This script creates tables with sufficient data to generate meaningful performance metrics

-- Create sample tables for performance testing
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active',
    profile_data JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    product_name VARCHAR(100) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending',
    shipping_address TEXT,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price DECIMAL(10,2) NOT NULL,
    discount_percent DECIMAL(5,2) DEFAULT 0.00
);

-- Insert sample users (${users_count} users)
INSERT INTO users (username, email, created_at, status, profile_data) 
SELECT 
    'user' || generate_series,
    'user' || generate_series || '@example.com',
    CURRENT_TIMESTAMP - (random() * interval '365 days'),
    CASE 
        WHEN random() < 0.1 THEN 'inactive'
        WHEN random() < 0.05 THEN 'suspended' 
        ELSE 'active'
    END,
    jsonb_build_object(
        'age', (random() * 50 + 18)::integer,
        'city', (ARRAY['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix'])[ceil(random() * 5)],
        'preferences', jsonb_build_array((random() * 100)::text, (random() * 200)::text)
    )
FROM generate_series(1, ${users_count})
ON CONFLICT (username) DO NOTHING;

-- Insert sample orders (${orders_count} orders)
INSERT INTO orders (user_id, product_name, amount, order_date, status, shipping_address, metadata)
SELECT 
    (random() * (${users_count} - 1) + 1)::INTEGER,
    'Product ' || (random() * 100 + 1)::INTEGER,
    (random() * 1000 + 10)::DECIMAL(10,2),
    CURRENT_TIMESTAMP - (random() * interval '90 days'),
    CASE 
        WHEN random() < 0.7 THEN 'completed'
        WHEN random() < 0.1 THEN 'cancelled'
        WHEN random() < 0.05 THEN 'refunded'
        ELSE 'pending'
    END,
    (random() * 1000)::text || ' Main St, City, State',
    jsonb_build_object(
        'source', (ARRAY['web', 'mobile', 'api'])[ceil(random() * 3)],
        'payment_method', (ARRAY['credit_card', 'paypal', 'bank_transfer'])[ceil(random() * 3)],
        'priority', (random() < 0.2)::boolean
    )
FROM generate_series(1, ${orders_count});

-- Insert sample order items (2-5 items per order)
INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_percent)
SELECT 
    o.id,
    (random() * 500 + 1)::INTEGER,
    (random() * 4 + 1)::INTEGER,
    (random() * 200 + 5)::DECIMAL(10,2),
    CASE WHEN random() < 0.3 THEN (random() * 20)::DECIMAL(5,2) ELSE 0.00 END
FROM orders o
CROSS JOIN generate_series(1, (random() * 4 + 2)::INTEGER);

-- Create indexes for better performance on normal queries
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_date ON orders(order_date);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);

-- Create some intentionally missing indexes to demonstrate slow queries
-- These are commented out to create performance issues:
-- CREATE INDEX idx_orders_amount ON orders(amount);
-- CREATE INDEX idx_users_profile_data_gin ON users USING gin(profile_data);
-- CREATE INDEX idx_orders_metadata_gin ON orders USING gin(metadata);

-- Create functions for testing slow queries and alerts
CREATE OR REPLACE FUNCTION slow_query_test() 
RETURNS TABLE(user_count INTEGER, total_orders INTEGER, avg_amount DECIMAL) AS $$
BEGIN
    -- Intentionally slow query with cartesian join
    RETURN QUERY
    SELECT 
        COUNT(DISTINCT u.id)::INTEGER as user_count,
        COUNT(DISTINCT o.id)::INTEGER as total_orders,
        AVG(o.amount)::DECIMAL as avg_amount
    FROM users u 
    CROSS JOIN orders o 
    WHERE u.id = o.user_id 
    AND u.created_at > CURRENT_DATE - interval '30 days'
    AND o.status = 'completed';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION complex_analytics_query()
RETURNS TABLE(
    username VARCHAR,
    total_orders INTEGER,
    total_spent DECIMAL,
    avg_order_value DECIMAL,
    last_order_date TIMESTAMP,
    order_frequency_days DECIMAL
) AS $$
BEGIN
    -- Complex analytical query that will likely exceed threshold
    RETURN QUERY
    SELECT 
        u.username,
        COUNT(o.id)::INTEGER as total_orders,
        COALESCE(SUM(o.amount), 0)::DECIMAL as total_spent,
        COALESCE(AVG(o.amount), 0)::DECIMAL as avg_order_value,
        MAX(o.order_date) as last_order_date,
        CASE 
            WHEN COUNT(o.id) > 1 THEN 
                EXTRACT(epoch FROM (MAX(o.order_date) - MIN(o.order_date))) / (COUNT(o.id) - 1) / 86400
            ELSE 0 
        END::DECIMAL as order_frequency_days
    FROM users u
    LEFT JOIN orders o ON u.id = o.user_id
    WHERE u.status = 'active'
    GROUP BY u.id, u.username
    HAVING COUNT(o.id) > 0
    ORDER BY total_spent DESC, avg_order_value DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trigger_timeout_query()
RETURNS TABLE(result_count INTEGER) AS $$
BEGIN
    -- Query designed to trigger timeout/slow performance alerts
    RETURN QUERY
    SELECT COUNT(*)::INTEGER
    FROM (
        SELECT DISTINCT u1.id, u2.id, o1.id, o2.id
        FROM users u1, users u2, orders o1, orders o2
        WHERE u1.id != u2.id 
        AND o1.user_id = u1.id 
        AND o2.user_id = u2.id
        AND u1.created_at > CURRENT_DATE - interval '7 days'
        AND u2.created_at > CURRENT_DATE - interval '7 days'
        LIMIT 1000
    ) subq;
END;
$$ LANGUAGE plpgsql;

-- Create test queries that can be executed to trigger alerts
CREATE OR REPLACE FUNCTION generate_test_load()
RETURNS TEXT AS $$
DECLARE
    result_text TEXT;
    i INTEGER;
BEGIN
    result_text := 'Test load generation completed:' || chr(10);
    
    -- Execute multiple slow queries to trigger alerts
    FOR i IN 1..3 LOOP
        PERFORM slow_query_test();
        result_text := result_text || 'Executed slow_query_test iteration ' || i || chr(10);
        
        -- Add delay between queries
        PERFORM pg_sleep(1);
    END LOOP;
    
    PERFORM complex_analytics_query();
    result_text := result_text || 'Executed complex_analytics_query' || chr(10);
    
    RETURN result_text;
END;
$$ LANGUAGE plpgsql;

-- Update table statistics to ensure query planner has accurate information
ANALYZE users;
ANALYZE orders;
ANALYZE order_items;

-- Create a view for easy monitoring of database performance
CREATE OR REPLACE VIEW query_performance_summary AS
SELECT 
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public';

-- Grant permissions to monitor user
GRANT CONNECT ON DATABASE ${database_name} TO monitor_user;
GRANT USAGE ON SCHEMA public TO monitor_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO monitor_user;
GRANT SELECT ON query_performance_summary TO monitor_user;

-- Print completion message
SELECT 'Sample data creation completed successfully!' as status,
       'Users created: ${users_count}' as users_info,
       'Orders created: ${orders_count}' as orders_info,
       'Ready for performance testing' as next_steps;