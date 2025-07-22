#!/bin/bash

# Deploy script for Analytics-Ready Data Storage with S3 Tables
# This script automates the deployment of S3 Tables infrastructure for analytics workloads

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    AWS_CLI_MAJOR=$(echo $AWS_CLI_VERSION | cut -d. -f1)
    if [ "$AWS_CLI_MAJOR" -lt 2 ]; then
        error "AWS CLI version 2.x is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Check if required AWS services are available in the region
    AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region is not configured. Please set a default region."
        exit 1
    fi
    
    # Verify S3 Tables service availability
    if ! aws s3tables list-table-buckets --region "$AWS_REGION" &> /dev/null; then
        error "S3 Tables service is not available in region $AWS_REGION or you lack permissions"
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export TABLE_BUCKET_NAME="analytics-data-${RANDOM_SUFFIX}"
    export NAMESPACE_NAME="analytics_data"
    export SAMPLE_TABLE_NAME="customer_events"
    export ATHENA_RESULTS_BUCKET="athena-results-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
TABLE_BUCKET_NAME=${TABLE_BUCKET_NAME}
NAMESPACE_NAME=${NAMESPACE_NAME}
SAMPLE_TABLE_NAME=${SAMPLE_TABLE_NAME}
ATHENA_RESULTS_BUCKET=${ATHENA_RESULTS_BUCKET}
EOF
    
    success "Environment configured with unique identifiers"
    log "Table bucket name: ${TABLE_BUCKET_NAME}"
    log "Namespace: ${NAMESPACE_NAME}"
    log "Sample table: ${SAMPLE_TABLE_NAME}"
}

# Function to create Athena results bucket
create_athena_bucket() {
    log "Creating Athena results bucket..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${ATHENA_RESULTS_BUCKET}" 2>/dev/null; then
        warning "Athena results bucket ${ATHENA_RESULTS_BUCKET} already exists"
        return 0
    fi
    
    # Create bucket
    aws s3 mb "s3://${ATHENA_RESULTS_BUCKET}" --region "${AWS_REGION}"
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "${ATHENA_RESULTS_BUCKET}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    success "Athena results bucket created and encrypted"
}

# Function to create S3 Table bucket
create_table_bucket() {
    log "Creating S3 Table bucket for analytics storage..."
    
    # Check if table bucket already exists
    if aws s3tables get-table-bucket --name "${TABLE_BUCKET_NAME}" 2>/dev/null; then
        warning "Table bucket ${TABLE_BUCKET_NAME} already exists"
        export TABLE_BUCKET_ARN=$(aws s3tables get-table-bucket \
            --name "${TABLE_BUCKET_NAME}" \
            --query 'arn' --output text)
        return 0
    fi
    
    # Create the table bucket
    aws s3tables create-table-bucket \
        --name "${TABLE_BUCKET_NAME}" \
        --region "${AWS_REGION}"
    
    # Store the table bucket ARN
    export TABLE_BUCKET_ARN=$(aws s3tables get-table-bucket \
        --name "${TABLE_BUCKET_NAME}" \
        --query 'arn' --output text)
    
    # Save ARN to environment file
    echo "TABLE_BUCKET_ARN=${TABLE_BUCKET_ARN}" >> .env
    
    success "Table bucket created: ${TABLE_BUCKET_ARN}"
}

# Function to create namespace
create_namespace() {
    log "Creating namespace for logical data organization..."
    
    # Check if namespace already exists
    if aws s3tables list-namespaces \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --query "namespaces[?namespace=='${NAMESPACE_NAME}']" \
        --output text | grep -q "${NAMESPACE_NAME}"; then
        warning "Namespace ${NAMESPACE_NAME} already exists"
        return 0
    fi
    
    # Create namespace
    aws s3tables create-namespace \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --namespace "${NAMESPACE_NAME}"
    
    # Verify namespace creation
    aws s3tables list-namespaces \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --query 'namespaces[].namespace' --output table
    
    success "Namespace '${NAMESPACE_NAME}' created successfully"
}

# Function to create Iceberg table
create_iceberg_table() {
    log "Creating Apache Iceberg table with optimized schema..."
    
    # Check if table already exists
    if aws s3tables get-table \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --namespace "${NAMESPACE_NAME}" \
        --name "${SAMPLE_TABLE_NAME}" 2>/dev/null; then
        warning "Table ${SAMPLE_TABLE_NAME} already exists"
        return 0
    fi
    
    # Create sample table for customer events
    aws s3tables create-table \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --namespace "${NAMESPACE_NAME}" \
        --name "${SAMPLE_TABLE_NAME}" \
        --format ICEBERG
    
    # Verify table creation
    TABLE_NAME=$(aws s3tables get-table \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --namespace "${NAMESPACE_NAME}" \
        --name "${SAMPLE_TABLE_NAME}" \
        --query 'name' --output text)
    
    success "Iceberg table '${TABLE_NAME}' created"
}

# Function to enable analytics services integration
enable_analytics_integration() {
    log "Enabling AWS analytics services integration..."
    
    # Create resource policy for analytics services integration
    POLICY_JSON=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "glue.amazonaws.com"
            },
            "Action": [
                "s3tables:GetTable",
                "s3tables:GetTableMetadata"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "athena.amazonaws.com"
            },
            "Action": [
                "s3tables:GetTable",
                "s3tables:GetTableMetadata"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    # Apply the resource policy
    aws s3tables put-table-bucket-policy \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --resource-policy "${POLICY_JSON}"
    
    # Wait for integration to complete
    sleep 30
    
    success "Analytics services integration enabled"
}

# Function to configure Athena workgroup
configure_athena_workgroup() {
    log "Configuring Athena workgroup for table queries..."
    
    local WORKGROUP_NAME="s3-tables-workgroup"
    
    # Check if workgroup already exists
    if aws athena get-work-group --work-group "${WORKGROUP_NAME}" 2>/dev/null; then
        warning "Athena workgroup ${WORKGROUP_NAME} already exists"
        return 0
    fi
    
    # Create Athena workgroup
    aws athena create-work-group \
        --name "${WORKGROUP_NAME}" \
        --configuration "ResultConfiguration={OutputLocation=s3://${ATHENA_RESULTS_BUCKET}/},EnforceWorkGroupConfiguration=true"
    
    # Set the workgroup as enabled
    aws athena update-work-group \
        --work-group "${WORKGROUP_NAME}" \
        --state ENABLED
    
    # Save workgroup name to environment
    echo "ATHENA_WORKGROUP=${WORKGROUP_NAME}" >> .env
    
    success "Athena workgroup configured for S3 Tables"
}

# Function to create DDL and sample data files
create_sql_files() {
    log "Creating sample data definition and insertion scripts..."
    
    # Create DDL file for customer events table
    cat > customer_events_ddl.sql << 'EOF'
CREATE TABLE IF NOT EXISTS s3tablescatalog.analytics_data.customer_events (
    event_id STRING,
    customer_id STRING,
    event_type STRING,
    event_timestamp TIMESTAMP,
    product_category STRING,
    amount DECIMAL(10,2),
    session_id STRING,
    user_agent STRING,
    event_date DATE
)
USING ICEBERG
PARTITIONED BY (event_date)
TBLPROPERTIES (
    'table_type'='ICEBERG',
    'format'='PARQUET',
    'write_compression'='SNAPPY'
);
EOF
    
    # Create sample data insertion script
    cat > insert_sample_data.sql << 'EOF'
INSERT INTO s3tablescatalog.analytics_data.customer_events VALUES
('evt_001', 'cust_12345', 'page_view', TIMESTAMP '2025-01-15 10:30:00', 'electronics', 0.00, 'sess_abc123', 'Mozilla/5.0', DATE '2025-01-15'),
('evt_002', 'cust_12345', 'add_to_cart', TIMESTAMP '2025-01-15 10:35:00', 'electronics', 299.99, 'sess_abc123', 'Mozilla/5.0', DATE '2025-01-15'),
('evt_003', 'cust_67890', 'purchase', TIMESTAMP '2025-01-15 11:00:00', 'clothing', 89.99, 'sess_def456', 'Chrome/100.0', DATE '2025-01-15'),
('evt_004', 'cust_54321', 'page_view', TIMESTAMP '2025-01-15 11:15:00', 'books', 0.00, 'sess_ghi789', 'Safari/14.0', DATE '2025-01-15'),
('evt_005', 'cust_54321', 'purchase', TIMESTAMP '2025-01-15 11:30:00', 'books', 24.99, 'sess_ghi789', 'Safari/14.0', DATE '2025-01-15');
EOF
    
    success "SQL files created successfully"
}

# Function to execute Athena queries
execute_athena_queries() {
    log "Executing Athena queries on S3 Tables..."
    
    local WORKGROUP_NAME="s3-tables-workgroup"
    
    # Execute DDL query to create table structure
    log "Creating table structure..."
    local DDL_QUERY_ID=$(aws athena start-query-execution \
        --query-string "$(cat customer_events_ddl.sql)" \
        --work-group "${WORKGROUP_NAME}" \
        --query 'QueryExecutionId' --output text)
    
    # Wait for DDL query completion
    log "Waiting for DDL query to complete..."
    local DDL_STATUS=""
    local RETRY_COUNT=0
    while [ "$DDL_STATUS" != "SUCCEEDED" ] && [ $RETRY_COUNT -lt 30 ]; do
        sleep 10
        DDL_STATUS=$(aws athena get-query-execution \
            --query-execution-id "${DDL_QUERY_ID}" \
            --query 'QueryExecution.Status.State' --output text)
        
        if [ "$DDL_STATUS" = "FAILED" ]; then
            error "DDL query failed"
            aws athena get-query-execution \
                --query-execution-id "${DDL_QUERY_ID}" \
                --query 'QueryExecution.Status.StateChangeReason'
            exit 1
        fi
        
        ((RETRY_COUNT++))
    done
    
    if [ "$DDL_STATUS" != "SUCCEEDED" ]; then
        error "DDL query timed out"
        exit 1
    fi
    
    success "Table structure created successfully"
    
    # Execute data insertion query
    log "Inserting sample data..."
    local INSERT_QUERY_ID=$(aws athena start-query-execution \
        --query-string "$(cat insert_sample_data.sql)" \
        --work-group "${WORKGROUP_NAME}" \
        --query 'QueryExecutionId' --output text)
    
    # Wait for insert query completion
    log "Waiting for data insertion to complete..."
    local INSERT_STATUS=""
    RETRY_COUNT=0
    while [ "$INSERT_STATUS" != "SUCCEEDED" ] && [ $RETRY_COUNT -lt 30 ]; do
        sleep 10
        INSERT_STATUS=$(aws athena get-query-execution \
            --query-execution-id "${INSERT_QUERY_ID}" \
            --query 'QueryExecution.Status.State' --output text)
        
        if [ "$INSERT_STATUS" = "FAILED" ]; then
            error "Data insertion query failed"
            aws athena get-query-execution \
                --query-execution-id "${INSERT_QUERY_ID}" \
                --query 'QueryExecution.Status.StateChangeReason'
            exit 1
        fi
        
        ((RETRY_COUNT++))
    done
    
    if [ "$INSERT_STATUS" != "SUCCEEDED" ]; then
        error "Data insertion query timed out"
        exit 1
    fi
    
    success "Sample data inserted successfully"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check table bucket status
    log "Verifying table bucket..."
    local BUCKET_DATE=$(aws s3tables get-table-bucket \
        --name "${TABLE_BUCKET_NAME}" \
        --query 'creationDate' --output text)
    success "Table bucket created on: ${BUCKET_DATE}"
    
    # Verify table exists in namespace
    log "Verifying table creation..."
    local TABLE_LIST=$(aws s3tables list-tables \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --namespace "${NAMESPACE_NAME}" \
        --query 'tables[].name' --output text)
    
    if echo "$TABLE_LIST" | grep -q "${SAMPLE_TABLE_NAME}"; then
        success "Table ${SAMPLE_TABLE_NAME} verified in namespace"
    else
        error "Table ${SAMPLE_TABLE_NAME} not found in namespace"
        exit 1
    fi
    
    # Test analytics query
    log "Testing analytics query performance..."
    local WORKGROUP_NAME="s3-tables-workgroup"
    local ANALYTICS_QUERY_ID=$(aws athena start-query-execution \
        --query-string "SELECT event_type, COUNT(*) as event_count, AVG(amount) as avg_amount FROM s3tablescatalog.analytics_data.customer_events WHERE event_date = DATE '2025-01-15' GROUP BY event_type" \
        --work-group "${WORKGROUP_NAME}" \
        --query 'QueryExecutionId' --output text)
    
    # Wait for query completion
    local QUERY_STATUS=""
    local RETRY_COUNT=0
    while [ "$QUERY_STATUS" != "SUCCEEDED" ] && [ $RETRY_COUNT -lt 20 ]; do
        sleep 5
        QUERY_STATUS=$(aws athena get-query-execution \
            --query-execution-id "${ANALYTICS_QUERY_ID}" \
            --query 'QueryExecution.Status.State' --output text)
        
        if [ "$QUERY_STATUS" = "FAILED" ]; then
            warning "Analytics query failed, but deployment is still valid"
            break
        fi
        
        ((RETRY_COUNT++))
    done
    
    if [ "$QUERY_STATUS" = "SUCCEEDED" ]; then
        success "Analytics query executed successfully"
        log "Query results:"
        aws athena get-query-results \
            --query-execution-id "${ANALYTICS_QUERY_ID}" \
            --query 'ResultSet.Rows' --output table
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "AWS Region: ${AWS_REGION}"
    echo "Table Bucket: ${TABLE_BUCKET_NAME}"
    echo "Table Bucket ARN: ${TABLE_BUCKET_ARN}"
    echo "Namespace: ${NAMESPACE_NAME}"
    echo "Sample Table: ${SAMPLE_TABLE_NAME}"
    echo "Athena Results Bucket: ${ATHENA_RESULTS_BUCKET}"
    echo "Athena Workgroup: s3-tables-workgroup"
    echo ""
    echo "Environment variables saved to: .env"
    echo "SQL files created: customer_events_ddl.sql, insert_sample_data.sql"
    echo ""
    success "S3 Tables analytics infrastructure deployed successfully!"
    warning "Remember to run ./destroy.sh when you're done to avoid ongoing charges"
}

# Main deployment function
main() {
    log "Starting S3 Tables Analytics Infrastructure Deployment"
    echo "======================================================="
    
    check_prerequisites
    setup_environment
    create_athena_bucket
    create_table_bucket
    create_namespace
    create_iceberg_table
    enable_analytics_integration
    configure_athena_workgroup
    create_sql_files
    execute_athena_queries
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"