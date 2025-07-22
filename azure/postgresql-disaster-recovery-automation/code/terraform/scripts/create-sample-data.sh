#!/bin/bash

# Script to create sample database and populate with test data
# This script is templated by Terraform and executed during deployment

set -e

# Template variables (populated by Terraform)
SERVER_FQDN="${server_fqdn}"
ADMIN_USERNAME="${admin_username}"
ADMIN_PASSWORD="${admin_password}"
DATABASE_NAME="${database_name}"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to execute SQL with error handling
execute_sql() {
    local sql_command="$1"
    local description="$2"
    
    log_message "Executing: $description"
    
    if psql "postgresql://$ADMIN_USERNAME:$ADMIN_PASSWORD@$SERVER_FQDN:5432/$DATABASE_NAME" -c "$sql_command"; then
        log_message "✅ Successfully executed: $description"
        return 0
    else
        log_message "❌ Failed to execute: $description"
        return 1
    fi
}

# Function to wait for database to be ready
wait_for_database() {
    local max_attempts=30
    local attempt=1
    
    log_message "Waiting for database to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if psql "postgresql://$ADMIN_USERNAME:$ADMIN_PASSWORD@$SERVER_FQDN:5432/postgres" -c "SELECT 1;" > /dev/null 2>&1; then
            log_message "✅ Database is ready"
            return 0
        else
            log_message "⏳ Database not ready yet (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        fi
    done
    
    log_message "❌ Database failed to become ready after $max_attempts attempts"
    return 1
}

# Main execution
main() {
    log_message "Starting sample data creation for PostgreSQL server: $SERVER_FQDN"
    
    # Check if required tools are available
    if ! command -v psql &> /dev/null; then
        log_message "❌ PostgreSQL client (psql) is not installed"
        exit 1
    fi
    
    # Wait for database to be ready
    if ! wait_for_database; then
        log_message "❌ Database is not ready, exiting"
        exit 1
    fi
    
    # Create database if it doesn't exist
    log_message "Creating database: $DATABASE_NAME"
    if psql "postgresql://$ADMIN_USERNAME:$ADMIN_PASSWORD@$SERVER_FQDN:5432/postgres" -c "CREATE DATABASE $DATABASE_NAME;" 2>/dev/null; then
        log_message "✅ Database created successfully"
    else
        log_message "⚠️ Database may already exist or creation failed"
    fi
    
    # Create customer_data table
    execute_sql "
        CREATE TABLE IF NOT EXISTS customer_data (
            id SERIAL PRIMARY KEY,
            customer_name VARCHAR(100) NOT NULL,
            email VARCHAR(100) UNIQUE NOT NULL,
            phone VARCHAR(20),
            address TEXT,
            city VARCHAR(50),
            country VARCHAR(50),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    " "Creating customer_data table"
    
    # Create order_history table
    execute_sql "
        CREATE TABLE IF NOT EXISTS order_history (
            order_id SERIAL PRIMARY KEY,
            customer_id INTEGER REFERENCES customer_data(id) ON DELETE CASCADE,
            order_amount DECIMAL(10,2) NOT NULL,
            order_status VARCHAR(20) DEFAULT 'pending',
            order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            shipping_address TEXT,
            notes TEXT
        );
    " "Creating order_history table"
    
    # Create product_catalog table
    execute_sql "
        CREATE TABLE IF NOT EXISTS product_catalog (
            product_id SERIAL PRIMARY KEY,
            product_name VARCHAR(100) NOT NULL,
            product_description TEXT,
            category VARCHAR(50),
            price DECIMAL(10,2) NOT NULL,
            stock_quantity INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    " "Creating product_catalog table"
    
    # Create order_items table
    execute_sql "
        CREATE TABLE IF NOT EXISTS order_items (
            item_id SERIAL PRIMARY KEY,
            order_id INTEGER REFERENCES order_history(order_id) ON DELETE CASCADE,
            product_id INTEGER REFERENCES product_catalog(product_id) ON DELETE CASCADE,
            quantity INTEGER NOT NULL,
            unit_price DECIMAL(10,2) NOT NULL,
            total_price DECIMAL(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED
        );
    " "Creating order_items table"
    
    # Insert sample customer data
    execute_sql "
        INSERT INTO customer_data (customer_name, email, phone, address, city, country) VALUES
        ('John Doe', 'john.doe@example.com', '+1-555-0101', '123 Main St', 'Seattle', 'USA'),
        ('Jane Smith', 'jane.smith@example.com', '+1-555-0102', '456 Oak Ave', 'Portland', 'USA'),
        ('Bob Johnson', 'bob.johnson@example.com', '+1-555-0103', '789 Pine Rd', 'San Francisco', 'USA'),
        ('Alice Brown', 'alice.brown@example.com', '+1-555-0104', '321 Elm St', 'Los Angeles', 'USA'),
        ('Charlie Wilson', 'charlie.wilson@example.com', '+1-555-0105', '654 Maple Dr', 'Denver', 'USA'),
        ('Diana Davis', 'diana.davis@example.com', '+1-555-0106', '987 Cedar Ln', 'Chicago', 'USA'),
        ('Frank Miller', 'frank.miller@example.com', '+1-555-0107', '147 Birch Blvd', 'Boston', 'USA'),
        ('Grace Lee', 'grace.lee@example.com', '+1-555-0108', '258 Spruce St', 'New York', 'USA'),
        ('Henry Taylor', 'henry.taylor@example.com', '+1-555-0109', '369 Willow Way', 'Miami', 'USA'),
        ('Ivy Chen', 'ivy.chen@example.com', '+1-555-0110', '741 Redwood Rd', 'Austin', 'USA')
        ON CONFLICT (email) DO NOTHING;
    " "Inserting sample customer data"
    
    # Insert sample product catalog data
    execute_sql "
        INSERT INTO product_catalog (product_name, product_description, category, price, stock_quantity) VALUES
        ('Laptop Pro 15', 'High-performance laptop with 15-inch display', 'Electronics', 1299.99, 50),
        ('Wireless Mouse', 'Ergonomic wireless mouse with precision tracking', 'Electronics', 29.99, 200),
        ('Mechanical Keyboard', 'RGB mechanical keyboard with blue switches', 'Electronics', 89.99, 75),
        ('Office Chair', 'Ergonomic office chair with lumbar support', 'Furniture', 249.99, 30),
        ('Standing Desk', 'Adjustable height standing desk', 'Furniture', 399.99, 15),
        ('Monitor 27inch', '4K UHD monitor with USB-C connectivity', 'Electronics', 349.99, 40),
        ('Desk Lamp', 'LED desk lamp with adjustable brightness', 'Lighting', 45.99, 80),
        ('Notebook Set', 'Set of 3 premium notebooks', 'Stationery', 19.99, 150),
        ('Pen Set', 'Professional pen set with case', 'Stationery', 34.99, 100),
        ('Coffee Mug', 'Ceramic coffee mug with company logo', 'Accessories', 12.99, 300)
        ON CONFLICT DO NOTHING;
    " "Inserting sample product catalog data"
    
    # Insert sample order history data
    execute_sql "
        INSERT INTO order_history (customer_id, order_amount, order_status, shipping_address, notes) VALUES
        (1, 150.00, 'completed', '123 Main St, Seattle, USA', 'Customer requested express delivery'),
        (2, 200.50, 'completed', '456 Oak Ave, Portland, USA', 'Gift wrapping requested'),
        (3, 75.25, 'pending', '789 Pine Rd, San Francisco, USA', 'Payment pending verification'),
        (1, 300.00, 'completed', '123 Main St, Seattle, USA', 'Repeat customer discount applied'),
        (4, 125.75, 'shipped', '321 Elm St, Los Angeles, USA', 'Expedited shipping'),
        (5, 450.00, 'completed', '654 Maple Dr, Denver, USA', 'Corporate purchase order'),
        (6, 89.99, 'processing', '987 Cedar Ln, Chicago, USA', 'Awaiting stock replenishment'),
        (7, 299.99, 'completed', '147 Birch Blvd, Boston, USA', 'Customer pickup'),
        (8, 175.50, 'cancelled', '258 Spruce St, New York, USA', 'Customer requested cancellation'),
        (9, 95.25, 'completed', '369 Willow Way, Miami, USA', 'Holiday special discount'),
        (10, 220.00, 'shipped', '741 Redwood Rd, Austin, USA', 'Bulk order discount'),
        (2, 67.50, 'processing', '456 Oak Ave, Portland, USA', 'Back-order item included'),
        (3, 189.99, 'completed', '789 Pine Rd, San Francisco, USA', 'Premium shipping'),
        (4, 45.00, 'completed', '321 Elm St, Los Angeles, USA', 'Quick reorder'),
        (5, 399.99, 'pending', '654 Maple Dr, Denver, USA', 'Awaiting approval')
        ON CONFLICT DO NOTHING;
    " "Inserting sample order history data"
    
    # Insert sample order items data
    execute_sql "
        INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
        (1, 2, 2, 29.99),
        (1, 8, 5, 19.99),
        (2, 1, 1, 1299.99),
        (2, 6, 1, 349.99),
        (3, 3, 1, 89.99),
        (4, 4, 1, 249.99),
        (4, 7, 1, 45.99),
        (5, 5, 1, 399.99),
        (6, 9, 1, 34.99),
        (6, 10, 4, 12.99),
        (7, 1, 1, 1299.99),
        (8, 2, 1, 29.99),
        (8, 3, 1, 89.99),
        (9, 7, 2, 45.99),
        (10, 8, 10, 19.99),
        (11, 6, 1, 349.99),
        (12, 4, 1, 249.99),
        (13, 5, 1, 399.99),
        (14, 10, 3, 12.99),
        (15, 1, 1, 1299.99)
        ON CONFLICT DO NOTHING;
    " "Inserting sample order items data"
    
    # Create indexes for performance optimization
    execute_sql "
        CREATE INDEX IF NOT EXISTS idx_customer_email ON customer_data(email);
        CREATE INDEX IF NOT EXISTS idx_customer_city ON customer_data(city);
        CREATE INDEX IF NOT EXISTS idx_order_date ON order_history(order_date);
        CREATE INDEX IF NOT EXISTS idx_order_status ON order_history(order_status);
        CREATE INDEX IF NOT EXISTS idx_order_customer ON order_history(customer_id);
        CREATE INDEX IF NOT EXISTS idx_product_category ON product_catalog(category);
        CREATE INDEX IF NOT EXISTS idx_product_name ON product_catalog(product_name);
        CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
        CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);
    " "Creating performance indexes"
    
    # Create a view for order summaries
    execute_sql "
        CREATE OR REPLACE VIEW order_summary AS
        SELECT 
            oh.order_id,
            cd.customer_name,
            cd.email,
            oh.order_date,
            oh.order_status,
            oh.order_amount,
            COUNT(oi.item_id) as item_count,
            SUM(oi.total_price) as calculated_total
        FROM order_history oh
        JOIN customer_data cd ON oh.customer_id = cd.id
        LEFT JOIN order_items oi ON oh.order_id = oi.order_id
        GROUP BY oh.order_id, cd.customer_name, cd.email, oh.order_date, oh.order_status, oh.order_amount
        ORDER BY oh.order_date DESC;
    " "Creating order summary view"
    
    # Create a function for updating last_updated timestamp
    execute_sql "
        CREATE OR REPLACE FUNCTION update_last_updated_column()
        RETURNS TRIGGER AS \$\$
        BEGIN
            NEW.last_updated = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        \$\$ LANGUAGE plpgsql;
    " "Creating update timestamp function"
    
    # Create triggers for automatic timestamp updates
    execute_sql "
        DROP TRIGGER IF EXISTS update_customer_data_timestamp ON customer_data;
        CREATE TRIGGER update_customer_data_timestamp
            BEFORE UPDATE ON customer_data
            FOR EACH ROW
            EXECUTE FUNCTION update_last_updated_column();
    " "Creating customer data timestamp trigger"
    
    execute_sql "
        DROP TRIGGER IF EXISTS update_product_catalog_timestamp ON product_catalog;
        CREATE TRIGGER update_product_catalog_timestamp
            BEFORE UPDATE ON product_catalog
            FOR EACH ROW
            EXECUTE FUNCTION update_last_updated_column();
    " "Creating product catalog timestamp trigger"
    
    # Verify data was inserted correctly
    execute_sql "
        SELECT 
            'Data verification' as check_type,
            (SELECT COUNT(*) FROM customer_data) as customer_count,
            (SELECT COUNT(*) FROM product_catalog) as product_count,
            (SELECT COUNT(*) FROM order_history) as order_count,
            (SELECT COUNT(*) FROM order_items) as order_item_count;
    " "Verifying sample data"
    
    # Create a simple test query to demonstrate functionality
    execute_sql "
        SELECT 
            'Sample query results' as description,
            customer_name,
            email,
            order_date,
            order_status,
            order_amount
        FROM order_summary
        WHERE order_status = 'completed'
        ORDER BY order_date DESC
        LIMIT 5;
    " "Running sample query to verify functionality"
    
    log_message "✅ Sample database and test data created successfully"
    log_message "Database: $DATABASE_NAME"
    log_message "Server: $SERVER_FQDN"
    log_message "Tables created: customer_data, order_history, product_catalog, order_items"
    log_message "Views created: order_summary"
    log_message "Functions created: update_last_updated_column()"
    log_message "Triggers created: automatic timestamp updates"
    log_message "Indexes created: performance optimization indexes"
    
    return 0
}

# Execute main function
if main; then
    log_message "✅ Sample data creation completed successfully"
    exit 0
else
    log_message "❌ Sample data creation failed"
    exit 1
fi