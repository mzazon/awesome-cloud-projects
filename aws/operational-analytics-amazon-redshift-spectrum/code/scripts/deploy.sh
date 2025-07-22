#!/bin/bash

# Deployment script for Operational Analytics with Amazon Redshift Spectrum
# This script automates the deployment of a complete analytics solution using Redshift Spectrum

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    # Note: Full cleanup logic is in destroy.sh
    if [[ -n "${REDSHIFT_CLUSTER:-}" ]]; then
        aws redshift delete-cluster \
            --cluster-identifier "${REDSHIFT_CLUSTER}" \
            --skip-final-cluster-snapshot 2>/dev/null || true
    fi
    if [[ -n "${DATA_LAKE_BUCKET:-}" ]]; then
        aws s3 rm "s3://${DATA_LAKE_BUCKET}" --recursive 2>/dev/null || true
        aws s3 rb "s3://${DATA_LAKE_BUCKET}" 2>/dev/null || true
    fi
}

# Trap for cleanup on error
trap cleanup_on_error ERR

# Banner
echo "=================================================="
echo "Redshift Spectrum Analytics Deployment Script"
echo "=================================================="

# Prerequisites check
log_info "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed. Please install AWS CLI v2."
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
if [[ $(echo "${AWS_CLI_VERSION}" | cut -d. -f1) -lt 2 ]]; then
    error_exit "AWS CLI v2 is required. Current version: ${AWS_CLI_VERSION}"
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error_exit "AWS credentials not configured. Run 'aws configure' first."
fi

# Check required permissions
log_info "Validating AWS permissions..."
CALLER_IDENTITY=$(aws sts get-caller-identity 2>/dev/null) || error_exit "Cannot retrieve caller identity"
ACCOUNT_ID=$(echo "${CALLER_IDENTITY}" | grep -o '"Account": *"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
USER_ARN=$(echo "${CALLER_IDENTITY}" | grep -o '"Arn": *"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')

log_info "Deploying as: ${USER_ARN}"
log_info "Account ID: ${ACCOUNT_ID}"

# Validate region
AWS_REGION=$(aws configure get region 2>/dev/null)
if [[ -z "${AWS_REGION}" ]]; then
    error_exit "AWS region not configured. Set default region with 'aws configure'"
fi
log_info "Deploying to region: ${AWS_REGION}"

# Check for existing resources to prevent conflicts
log_info "Checking for existing resources..."

# Generate unique identifiers
log_info "Generating unique resource identifiers..."
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export AWS_REGION
export AWS_ACCOUNT_ID="${ACCOUNT_ID}"
export DATA_LAKE_BUCKET="spectrum-data-lake-${RANDOM_SUFFIX}"
export REDSHIFT_CLUSTER="spectrum-cluster-${RANDOM_SUFFIX}"
export GLUE_DATABASE="spectrum_db_${RANDOM_SUFFIX}"
export REDSHIFT_ROLE_NAME="RedshiftSpectrumRole-${RANDOM_SUFFIX}"
export GLUE_ROLE_NAME="GlueSpectrumRole-${RANDOM_SUFFIX}"
export MASTER_USERNAME="admin"
export MASTER_PASSWORD="TempPassword123!"

log_info "Resource identifiers:"
log_info "  Data Lake Bucket: ${DATA_LAKE_BUCKET}"
log_info "  Redshift Cluster: ${REDSHIFT_CLUSTER}"
log_info "  Glue Database: ${GLUE_DATABASE}"

# Check for bucket name conflicts
if aws s3 ls "s3://${DATA_LAKE_BUCKET}" &> /dev/null; then
    error_exit "S3 bucket ${DATA_LAKE_BUCKET} already exists. Please run script again to generate new names."
fi

# Check for cluster name conflicts
if aws redshift describe-clusters --cluster-identifier "${REDSHIFT_CLUSTER}" &> /dev/null; then
    error_exit "Redshift cluster ${REDSHIFT_CLUSTER} already exists. Please run script again to generate new names."
fi

# Start deployment
log_info "Starting deployment..."

# Step 1: Create S3 data lake with sample operational data
log_info "Step 1/6: Creating S3 data lake..."

aws s3 mb "s3://${DATA_LAKE_BUCKET}" --region "${AWS_REGION}" || error_exit "Failed to create S3 bucket"

# Create sample data files
log_info "Creating sample operational data..."

cat > sales_transactions.csv << 'EOF'
transaction_id,customer_id,product_id,quantity,unit_price,transaction_date,store_id,region,payment_method
TXN001,CUST001,PROD001,2,29.99,2024-01-15,STORE001,North,credit_card
TXN002,CUST002,PROD002,1,199.99,2024-01-15,STORE002,South,debit_card
TXN003,CUST003,PROD003,3,15.50,2024-01-16,STORE001,North,cash
TXN004,CUST001,PROD004,1,89.99,2024-01-16,STORE003,East,credit_card
TXN005,CUST004,PROD001,2,29.99,2024-01-17,STORE002,South,credit_card
TXN006,CUST005,PROD005,1,45.00,2024-01-17,STORE001,North,credit_card
TXN007,CUST002,PROD003,2,15.50,2024-01-18,STORE002,South,debit_card
TXN008,CUST003,PROD004,1,89.99,2024-01-18,STORE003,East,cash
TXN009,CUST006,PROD002,1,199.99,2024-01-19,STORE001,North,credit_card
TXN010,CUST004,PROD005,3,45.00,2024-01-19,STORE002,South,credit_card
EOF

cat > customers.csv << 'EOF'
customer_id,first_name,last_name,email,phone,registration_date,tier,city,state
CUST001,John,Doe,john.doe@email.com,555-0101,2023-01-15,premium,New York,NY
CUST002,Jane,Smith,jane.smith@email.com,555-0102,2023-02-20,standard,Los Angeles,CA
CUST003,Bob,Johnson,bob.johnson@email.com,555-0103,2023-03-10,standard,Chicago,IL
CUST004,Alice,Brown,alice.brown@email.com,555-0104,2023-04-05,premium,Miami,FL
CUST005,Charlie,Wilson,charlie.wilson@email.com,555-0105,2023-05-12,standard,Seattle,WA
CUST006,Diana,Lee,diana.lee@email.com,555-0106,2023-06-18,premium,Boston,MA
EOF

cat > products.csv << 'EOF'
product_id,product_name,category,brand,cost,retail_price,supplier_id
PROD001,Wireless Headphones,Electronics,TechBrand,20.00,29.99,SUP001
PROD002,Smart Watch,Electronics,TechBrand,120.00,199.99,SUP001
PROD003,Coffee Mug,Home,HomeBrand,8.00,15.50,SUP002
PROD004,Bluetooth Speaker,Electronics,AudioMax,50.00,89.99,SUP003
PROD005,Desk Lamp,Home,HomeBrand,25.00,45.00,SUP002
EOF

# Upload data with partitioning structure
aws s3 cp sales_transactions.csv \
    "s3://${DATA_LAKE_BUCKET}/operational-data/sales/year=2024/month=01/" || error_exit "Failed to upload sales data"

aws s3 cp customers.csv \
    "s3://${DATA_LAKE_BUCKET}/operational-data/customers/" || error_exit "Failed to upload customer data"

aws s3 cp products.csv \
    "s3://${DATA_LAKE_BUCKET}/operational-data/products/" || error_exit "Failed to upload product data"

log_success "Created S3 data lake with sample data"

# Step 2: Create IAM roles for Redshift Spectrum
log_info "Step 2/6: Creating IAM roles..."

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

# Create comprehensive permissions for Spectrum
cat > redshift-spectrum-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::${DATA_LAKE_BUCKET}",
                "arn:aws:s3:::${DATA_LAKE_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "glue:GetDatabase",
                "glue:GetDatabases",
                "glue:GetTable",
                "glue:GetTables",
                "glue:GetPartition",
                "glue:GetPartitions"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create Redshift IAM role
aws iam create-role \
    --role-name "${REDSHIFT_ROLE_NAME}" \
    --assume-role-policy-document file://redshift-trust-policy.json || error_exit "Failed to create Redshift IAM role"

# Create and attach custom policy
aws iam create-policy \
    --policy-name "${REDSHIFT_ROLE_NAME}-Policy" \
    --policy-document file://redshift-spectrum-policy.json || error_exit "Failed to create Redshift IAM policy"

SPECTRUM_POLICY_ARN=$(aws iam list-policies \
    --query "Policies[?PolicyName=='${REDSHIFT_ROLE_NAME}-Policy'].Arn" \
    --output text)

aws iam attach-role-policy \
    --role-name "${REDSHIFT_ROLE_NAME}" \
    --policy-arn "${SPECTRUM_POLICY_ARN}" || error_exit "Failed to attach policy to Redshift role"

# Wait for role propagation
log_info "Waiting for IAM role propagation..."
sleep 30

REDSHIFT_ROLE_ARN=$(aws iam get-role \
    --role-name "${REDSHIFT_ROLE_NAME}" \
    --query 'Role.Arn' --output text)

log_success "Created IAM role: ${REDSHIFT_ROLE_ARN}"

# Step 3: Create Redshift cluster
log_info "Step 3/6: Creating Redshift cluster..."

aws redshift create-cluster \
    --cluster-identifier "${REDSHIFT_CLUSTER}" \
    --node-type dc2.large \
    --master-username "${MASTER_USERNAME}" \
    --master-user-password "${MASTER_PASSWORD}" \
    --db-name analytics \
    --cluster-type single-node \
    --publicly-accessible \
    --iam-roles "${REDSHIFT_ROLE_ARN}" || error_exit "Failed to create Redshift cluster"

log_info "Waiting for Redshift cluster to become available (this may take 10-15 minutes)..."

# Wait for cluster with timeout
TIMEOUT=1200 # 20 minutes
ELAPSED=0
INTERVAL=30

while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
    CLUSTER_STATUS=$(aws redshift describe-clusters \
        --cluster-identifier "${REDSHIFT_CLUSTER}" \
        --query 'Clusters[0].ClusterStatus' --output text 2>/dev/null || echo "creating")
    
    if [[ "${CLUSTER_STATUS}" == "available" ]]; then
        break
    elif [[ "${CLUSTER_STATUS}" == "creating" || "${CLUSTER_STATUS}" == "modifying" ]]; then
        log_info "Cluster status: ${CLUSTER_STATUS}. Waiting..."
        sleep ${INTERVAL}
        ELAPSED=$((ELAPSED + INTERVAL))
    else
        error_exit "Cluster creation failed with status: ${CLUSTER_STATUS}"
    fi
done

if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
    error_exit "Timeout waiting for cluster to become available"
fi

CLUSTER_ENDPOINT=$(aws redshift describe-clusters \
    --cluster-identifier "${REDSHIFT_CLUSTER}" \
    --query 'Clusters[0].Endpoint.Address' --output text)

log_success "Redshift cluster created: ${CLUSTER_ENDPOINT}"

# Step 4: Set up Glue Data Catalog
log_info "Step 4/6: Setting up Glue Data Catalog..."

# Create Glue database
aws glue create-database \
    --database-input '{
        "Name": "'${GLUE_DATABASE}'",
        "Description": "Database for Redshift Spectrum operational analytics"
    }' || error_exit "Failed to create Glue database"

# Create trust policy for Glue service
cat > glue-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "glue.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create IAM role for Glue crawlers
aws iam create-role \
    --role-name "${GLUE_ROLE_NAME}" \
    --assume-role-policy-document file://glue-trust-policy.json || error_exit "Failed to create Glue IAM role"

# Attach AWS managed policy for Glue service
aws iam attach-role-policy \
    --role-name "${GLUE_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole || error_exit "Failed to attach Glue service policy"

# Attach S3 access policy for data discovery
aws iam attach-role-policy \
    --role-name "${GLUE_ROLE_NAME}" \
    --policy-arn "${SPECTRUM_POLICY_ARN}" || error_exit "Failed to attach S3 policy to Glue role"

# Wait for role propagation
log_info "Waiting for Glue IAM role propagation..."
sleep 30

GLUE_ROLE_ARN=$(aws iam get-role \
    --role-name "${GLUE_ROLE_NAME}" \
    --query 'Role.Arn' --output text)

# Create crawlers for data discovery
aws glue create-crawler \
    --name "sales-crawler-${RANDOM_SUFFIX}" \
    --role "${GLUE_ROLE_ARN}" \
    --database-name "${GLUE_DATABASE}" \
    --targets '{
        "S3Targets": [
            {
                "Path": "s3://'${DATA_LAKE_BUCKET}'/operational-data/sales/"
            }
        ]
    }' || error_exit "Failed to create sales crawler"

aws glue create-crawler \
    --name "customers-crawler-${RANDOM_SUFFIX}" \
    --role "${GLUE_ROLE_ARN}" \
    --database-name "${GLUE_DATABASE}" \
    --targets '{
        "S3Targets": [
            {
                "Path": "s3://'${DATA_LAKE_BUCKET}'/operational-data/customers/"
            }
        ]
    }' || error_exit "Failed to create customers crawler"

aws glue create-crawler \
    --name "products-crawler-${RANDOM_SUFFIX}" \
    --role "${GLUE_ROLE_ARN}" \
    --database-name "${GLUE_DATABASE}" \
    --targets '{
        "S3Targets": [
            {
                "Path": "s3://'${DATA_LAKE_BUCKET}'/operational-data/products/"
            }
        ]
    }' || error_exit "Failed to create products crawler"

# Start crawlers
log_info "Starting Glue crawlers for schema discovery..."
aws glue start-crawler --name "sales-crawler-${RANDOM_SUFFIX}"
aws glue start-crawler --name "customers-crawler-${RANDOM_SUFFIX}"
aws glue start-crawler --name "products-crawler-${RANDOM_SUFFIX}"

# Wait for crawlers to complete
log_info "Waiting for crawlers to complete..."
sleep 120

log_success "Set up Glue Data Catalog with crawlers"

# Step 5: Configure Redshift external schema
log_info "Step 5/6: Configuring Redshift external schema..."

# Create Spectrum configuration SQL
cat > setup-spectrum.sql << EOF
-- Create external schema pointing to Glue catalog
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE '${GLUE_DATABASE}'
IAM_ROLE '${REDSHIFT_ROLE_ARN}'
CREATE EXTERNAL DATABASE IF NOT EXISTS;

-- Create internal tables for frequently accessed data
CREATE TABLE internal_customers (
    customer_id VARCHAR(20),
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    tier VARCHAR(20),
    city VARCHAR(50),
    state VARCHAR(10)
);

-- Load sample internal data
INSERT INTO internal_customers VALUES
('CUST001', 'John', 'Doe', 'john.doe@email.com', 'premium', 'New York', 'NY'),
('CUST002', 'Jane', 'Smith', 'jane.smith@email.com', 'standard', 'Los Angeles', 'CA'),
('CUST003', 'Bob', 'Johnson', 'bob.johnson@email.com', 'standard', 'Chicago', 'IL'),
('CUST004', 'Alice', 'Brown', 'alice.brown@email.com', 'premium', 'Miami', 'FL'),
('CUST005', 'Charlie', 'Wilson', 'charlie.wilson@email.com', 'standard', 'Seattle', 'WA'),
('CUST006', 'Diana', 'Lee', 'diana.lee@email.com', 'premium', 'Boston', 'MA');

-- Create view combining internal and external data
CREATE VIEW operational_analytics AS
SELECT 
    s.transaction_id,
    s.customer_id,
    c.first_name,
    c.last_name,
    c.tier,
    s.product_id,
    s.quantity,
    s.unit_price,
    s.quantity * s.unit_price as total_amount,
    s.transaction_date,
    s.region,
    s.payment_method
FROM spectrum_schema.sales s
LEFT JOIN internal_customers c ON s.customer_id = c.customer_id;
EOF

log_success "Created Spectrum configuration SQL"

# Step 6: Create sample analytics queries
log_info "Step 6/6: Creating operational analytics queries..."

cat > operational-queries.sql << EOF
-- Query 1: Sales performance by region using Spectrum
SELECT 
    region,
    COUNT(*) as transaction_count,
    SUM(quantity * unit_price) as total_revenue,
    AVG(quantity * unit_price) as avg_transaction_value
FROM spectrum_schema.sales
GROUP BY region
ORDER BY total_revenue DESC;

-- Query 2: Customer tier analysis combining internal and external data
SELECT 
    c.tier,
    COUNT(DISTINCT s.customer_id) as active_customers,
    COUNT(s.transaction_id) as total_transactions,
    SUM(s.quantity * s.unit_price) as total_spent,
    AVG(s.quantity * s.unit_price) as avg_transaction
FROM spectrum_schema.sales s
JOIN internal_customers c ON s.customer_id = c.customer_id
GROUP BY c.tier
ORDER BY total_spent DESC;

-- Query 3: Product performance analysis
SELECT 
    s.product_id,
    p.product_name,
    p.category,
    COUNT(*) as units_sold,
    SUM(s.quantity * s.unit_price) as revenue,
    AVG(s.unit_price) as avg_selling_price,
    p.cost,
    (AVG(s.unit_price) - p.cost) as avg_margin
FROM spectrum_schema.sales s
JOIN spectrum_schema.products p ON s.product_id = p.product_id
GROUP BY s.product_id, p.product_name, p.category, p.cost
ORDER BY revenue DESC;

-- Query 4: Time-based sales trends
SELECT 
    DATE_TRUNC('day', transaction_date) as sale_date,
    COUNT(*) as daily_transactions,
    SUM(quantity * unit_price) as daily_revenue,
    COUNT(DISTINCT customer_id) as unique_customers
FROM spectrum_schema.sales
GROUP BY DATE_TRUNC('day', transaction_date)
ORDER BY sale_date;
EOF

# Save environment variables for later use
cat > deployment-info.env << EOF
# Deployment Information for Redshift Spectrum Analytics
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export DATA_LAKE_BUCKET="${DATA_LAKE_BUCKET}"
export REDSHIFT_CLUSTER="${REDSHIFT_CLUSTER}"
export GLUE_DATABASE="${GLUE_DATABASE}"
export REDSHIFT_ROLE_NAME="${REDSHIFT_ROLE_NAME}"
export GLUE_ROLE_NAME="${GLUE_ROLE_NAME}"
export MASTER_USERNAME="${MASTER_USERNAME}"
export MASTER_PASSWORD="${MASTER_PASSWORD}"
export REDSHIFT_ROLE_ARN="${REDSHIFT_ROLE_ARN}"
export GLUE_ROLE_ARN="${GLUE_ROLE_ARN}"
export CLUSTER_ENDPOINT="${CLUSTER_ENDPOINT}"
export SPECTRUM_POLICY_ARN="${SPECTRUM_POLICY_ARN}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF

# Cleanup temporary files
rm -f sales_transactions.csv customers.csv products.csv
rm -f redshift-trust-policy.json redshift-spectrum-policy.json glue-trust-policy.json

log_success "Created operational analytics queries and saved deployment information"

# Final deployment summary
echo "=================================================="
echo "DEPLOYMENT COMPLETED SUCCESSFULLY!"
echo "=================================================="
echo ""
echo "📊 Redshift Spectrum Analytics Solution Deployed"
echo ""
echo "🔗 Connection Information:"
echo "   Cluster Endpoint: ${CLUSTER_ENDPOINT}"
echo "   Database Name: analytics"
echo "   Username: ${MASTER_USERNAME}"
echo "   Password: ${MASTER_PASSWORD}"
echo ""
echo "🗄️ Resources Created:"
echo "   ✅ S3 Data Lake: s3://${DATA_LAKE_BUCKET}"
echo "   ✅ Redshift Cluster: ${REDSHIFT_CLUSTER}"
echo "   ✅ Glue Database: ${GLUE_DATABASE}"
echo "   ✅ IAM Roles: ${REDSHIFT_ROLE_NAME}, ${GLUE_ROLE_NAME}"
echo ""
echo "📋 Next Steps:"
echo "   1. Connect to Redshift using AWS Query Editor v2 or psql"
echo "   2. Run setup-spectrum.sql to configure external schema"
echo "   3. Execute operational-queries.sql for analytics"
echo ""
echo "💡 Connection Commands:"
echo "   psql -h ${CLUSTER_ENDPOINT} -p 5439 -U ${MASTER_USERNAME} -d analytics"
echo "   Or use AWS Query Editor v2 in the Redshift console"
echo ""
echo "🔧 Management:"
echo "   Deployment info saved to: deployment-info.env"
echo "   To destroy resources, run: ./destroy.sh"
echo ""
echo "💰 Estimated Monthly Cost: \$200-500 (depending on usage)"
echo "   Remember to destroy resources when testing is complete!"
echo ""
echo "=================================================="

log_success "Deployment completed successfully!"