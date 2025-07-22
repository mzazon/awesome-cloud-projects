#!/bin/bash

# AWS Redshift Data Warehousing Solution - Deployment Script
# This script deploys a complete Amazon Redshift Serverless data warehouse solution
# including IAM roles, namespaces, workgroups, and sample data

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        log "Please run 'aws configure' or set AWS environment variables"
        exit 1
    fi
    log_success "AWS credentials validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Validate AWS credentials
    validate_aws_credentials
    
    # Check required permissions (basic check)
    log "Checking AWS permissions..."
    if ! aws iam get-user >/dev/null 2>&1 && ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "Unable to verify AWS identity"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_warn "AWS region not set in configuration, using us-east-1"
        export AWS_REGION="us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export NAMESPACE_NAME="data-warehouse-ns-${RANDOM_SUFFIX}"
    export WORKGROUP_NAME="data-warehouse-wg-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="redshift-data-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="RedshiftServerlessRole-${RANDOM_SUFFIX}"
    export IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
    
    log "Environment variables set:"
    log "  AWS_REGION: $AWS_REGION"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  NAMESPACE_NAME: $NAMESPACE_NAME"
    log "  WORKGROUP_NAME: $WORKGROUP_NAME"
    log "  S3_BUCKET_NAME: $S3_BUCKET_NAME"
    log "  IAM_ROLE_NAME: $IAM_ROLE_NAME"
    
    # Save environment variables to file for cleanup script
    cat > .redshift-env << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export NAMESPACE_NAME="${NAMESPACE_NAME}"
export WORKGROUP_NAME="${WORKGROUP_NAME}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME}"
export IAM_ROLE_NAME="${IAM_ROLE_NAME}"
export IAM_ROLE_ARN="${IAM_ROLE_ARN}"
EOF
    
    log_success "Environment variables saved to .redshift-env"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for sample data..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        log_warn "S3 bucket ${S3_BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create bucket with appropriate region constraints
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    log_success "S3 bucket created: ${S3_BUCKET_NAME}"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Redshift Serverless..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        log_warn "IAM role ${IAM_ROLE_NAME} already exists"
        return 0
    fi
    
    # Create trust policy for Redshift service
    cat > redshift-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "redshift.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file://redshift-trust-policy.json \
        --description "IAM role for Redshift Serverless data warehouse"
    
    # Attach managed policy for S3 access
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    log_success "IAM role created: ${IAM_ROLE_ARN}"
}

# Function to create Redshift Serverless namespace
create_namespace() {
    log "Creating Redshift Serverless namespace..."
    
    # Check if namespace already exists
    if aws redshift-serverless get-namespace --namespace-name "$NAMESPACE_NAME" >/dev/null 2>&1; then
        log_warn "Namespace ${NAMESPACE_NAME} already exists"
        return 0
    fi
    
    # Create namespace for data warehouse
    aws redshift-serverless create-namespace \
        --namespace-name "$NAMESPACE_NAME" \
        --admin-username awsuser \
        --admin-user-password TempPassword123! \
        --default-iam-role-arn "$IAM_ROLE_ARN" \
        --db-name sampledb
    
    log_success "Namespace created: ${NAMESPACE_NAME}"
}

# Function to create Redshift Serverless workgroup
create_workgroup() {
    log "Creating Redshift Serverless workgroup..."
    
    # Check if workgroup already exists
    if aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP_NAME" >/dev/null 2>&1; then
        log_warn "Workgroup ${WORKGROUP_NAME} already exists"
        return 0
    fi
    
    # Create workgroup for compute resources
    aws redshift-serverless create-workgroup \
        --workgroup-name "$WORKGROUP_NAME" \
        --namespace-name "$NAMESPACE_NAME" \
        --base-capacity 128 \
        --publicly-accessible
    
    log_success "Workgroup created: ${WORKGROUP_NAME}"
}

# Function to wait for resources to become available
wait_for_resources() {
    log "Waiting for resources to become available..."
    
    # Wait for namespace to become available
    log "Waiting for namespace to become available..."
    local timeout=300  # 5 minutes
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if aws redshift-serverless get-namespace --namespace-name "$NAMESPACE_NAME" --query 'namespace.status' --output text 2>/dev/null | grep -q "AVAILABLE"; then
            log_success "Namespace is available"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log "Waiting... (${elapsed}s/${timeout}s)"
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for namespace to become available"
        exit 1
    fi
    
    # Wait for workgroup to become available
    log "Waiting for workgroup to become available..."
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP_NAME" --query 'workgroup.status' --output text 2>/dev/null | grep -q "AVAILABLE"; then
            log_success "Workgroup is available"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log "Waiting... (${elapsed}s/${timeout}s)"
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for workgroup to become available"
        exit 1
    fi
    
    log_success "All resources are now available and ready for use"
}

# Function to upload sample data
upload_sample_data() {
    log "Creating and uploading sample data..."
    
    # Create sample sales data
    cat > sales_data.csv << EOF
order_id,customer_id,product_id,quantity,price,order_date
1001,501,2001,2,29.99,2024-01-15
1002,502,2002,1,49.99,2024-01-15
1003,503,2001,3,29.99,2024-01-16
1004,501,2003,1,79.99,2024-01-16
1005,504,2002,2,49.99,2024-01-17
1006,505,2001,1,29.99,2024-01-18
1007,502,2003,2,79.99,2024-01-18
1008,506,2002,1,49.99,2024-01-19
1009,503,2001,4,29.99,2024-01-19
1010,507,2003,1,79.99,2024-01-20
EOF
    
    # Create sample customer data
    cat > customer_data.csv << EOF
customer_id,first_name,last_name,email,city,state
501,John,Doe,john.doe@email.com,Seattle,WA
502,Jane,Smith,jane.smith@email.com,Portland,OR
503,Mike,Johnson,mike.johnson@email.com,San Francisco,CA
504,Sarah,Wilson,sarah.wilson@email.com,Los Angeles,CA
505,Robert,Brown,robert.brown@email.com,Denver,CO
506,Emily,Davis,emily.davis@email.com,Phoenix,AZ
507,David,Miller,david.miller@email.com,Austin,TX
EOF
    
    # Create sample product data
    cat > product_data.csv << EOF
product_id,product_name,category,price
2001,Widget A,Electronics,29.99
2002,Gadget B,Electronics,49.99
2003,Tool C,Hardware,79.99
EOF
    
    # Upload data files to S3
    aws s3 cp sales_data.csv "s3://${S3_BUCKET_NAME}/data/"
    aws s3 cp customer_data.csv "s3://${S3_BUCKET_NAME}/data/"
    aws s3 cp product_data.csv "s3://${S3_BUCKET_NAME}/data/"
    
    log_success "Sample data uploaded to S3 bucket"
}

# Function to create SQL scripts
create_sql_scripts() {
    log "Creating SQL scripts for table creation and data loading..."
    
    # Get workgroup endpoint
    export WORKGROUP_ENDPOINT=$(aws redshift-serverless get-workgroup \
        --workgroup-name "$WORKGROUP_NAME" \
        --query 'workgroup.endpoint.address' \
        --output text)
    
    # Create SQL script for table creation
    cat > create_tables.sql << EOF
-- Create tables for data warehouse
CREATE TABLE IF NOT EXISTS sales (
    order_id INTEGER,
    customer_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    price DECIMAL(10,2),
    order_date DATE
);

CREATE TABLE IF NOT EXISTS customers (
    customer_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(2)
);

CREATE TABLE IF NOT EXISTS products (
    product_id INTEGER,
    product_name VARCHAR(100),
    category VARCHAR(50),
    price DECIMAL(10,2)
);
EOF
    
    # Create data loading script
    cat > load_data.sql << EOF
-- Load data into tables using COPY command
COPY sales FROM 's3://${S3_BUCKET_NAME}/data/sales_data.csv'
IAM_ROLE '${IAM_ROLE_ARN}'
CSV
IGNOREHEADER 1;

COPY customers FROM 's3://${S3_BUCKET_NAME}/data/customer_data.csv'
IAM_ROLE '${IAM_ROLE_ARN}'
CSV
IGNOREHEADER 1;

COPY products FROM 's3://${S3_BUCKET_NAME}/data/product_data.csv'
IAM_ROLE '${IAM_ROLE_ARN}'
CSV
IGNOREHEADER 1;
EOF
    
    # Create analytical queries
    cat > analytical_queries.sql << EOF
-- Analytical queries for business intelligence

-- Sales summary by customer
SELECT 
    c.first_name,
    c.last_name,
    c.city,
    c.state,
    COUNT(s.order_id) as total_orders,
    SUM(s.quantity * s.price) as total_revenue
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.city, c.state
ORDER BY total_revenue DESC;

-- Daily sales trend
SELECT 
    order_date,
    COUNT(order_id) as daily_orders,
    SUM(quantity * price) as daily_revenue,
    AVG(quantity * price) as avg_order_value
FROM sales
GROUP BY order_date
ORDER BY order_date;

-- Product performance analysis
SELECT 
    p.product_name,
    p.category,
    SUM(s.quantity) as total_quantity_sold,
    SUM(s.quantity * s.price) as total_revenue,
    AVG(s.price) as average_price
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC;

-- Customer segmentation by revenue
SELECT 
    CASE 
        WHEN total_revenue >= 200 THEN 'High Value'
        WHEN total_revenue >= 100 THEN 'Medium Value'
        ELSE 'Low Value'
    END as customer_segment,
    COUNT(*) as customer_count,
    AVG(total_revenue) as avg_revenue_per_customer
FROM (
    SELECT 
        c.customer_id,
        SUM(s.quantity * s.price) as total_revenue
    FROM sales s
    JOIN customers c ON s.customer_id = c.customer_id
    GROUP BY c.customer_id
) customer_totals
GROUP BY customer_segment
ORDER BY avg_revenue_per_customer DESC;
EOF
    
    log_success "SQL scripts created successfully"
    log "Workgroup endpoint: ${WORKGROUP_ENDPOINT}"
}

# Function to display next steps
display_next_steps() {
    log_success "Deployment completed successfully!"
    echo
    log "=== NEXT STEPS ==="
    log "1. Connect to your Redshift data warehouse using Query Editor v2:"
    log "   - Navigate to Amazon Redshift console"
    log "   - Select Query Editor v2"
    log "   - Connect to workgroup: ${WORKGROUP_NAME}"
    log "   - Database: sampledb"
    log "   - Username: awsuser"
    log "   - Password: TempPassword123!"
    echo
    log "2. Execute the SQL scripts in order:"
    log "   - Run create_tables.sql to create the table schemas"
    log "   - Run load_data.sql to load sample data"
    log "   - Run analytical_queries.sql to test analytics"
    echo
    log "3. Environment details:"
    log "   - AWS Region: ${AWS_REGION}"
    log "   - Namespace: ${NAMESPACE_NAME}"
    log "   - Workgroup: ${WORKGROUP_NAME}"
    log "   - S3 Bucket: ${S3_BUCKET_NAME}"
    log "   - Workgroup Endpoint: ${WORKGROUP_ENDPOINT}"
    echo
    log "4. To clean up resources later, run: ./destroy.sh"
    echo
    log_warn "Remember: Redshift Serverless charges only when actively processing queries"
    log_warn "Estimated cost: \$0.50-\$2.00 per hour when active"
}

# Main deployment function
main() {
    log "Starting AWS Redshift Data Warehousing Solution deployment..."
    echo
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "Running in dry-run mode - no resources will be created"
        export DRY_RUN=true
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        create_s3_bucket
        create_iam_role
        create_namespace
        create_workgroup
        wait_for_resources
        upload_sample_data
        create_sql_scripts
        display_next_steps
    else
        log "Dry-run completed - no resources were created"
    fi
}

# Error handling
trap 'log_error "Script failed at line $LINENO"' ERR

# Script usage
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--dry-run] [--help]"
    echo "  --dry-run    Run script without creating resources"
    echo "  --help       Show this help message"
    exit 0
fi

# Run main function
main "$@"

# Clean up temporary files
rm -f redshift-trust-policy.json sales_data.csv customer_data.csv product_data.csv