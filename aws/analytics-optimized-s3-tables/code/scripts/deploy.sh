#!/bin/bash

# AWS S3 Tables Analytics Solution Deployment Script
# This script deploys the complete analytics-optimized data storage solution
# using S3 Tables, Athena, Glue, and QuickSight integration

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
        error "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check if region is set
    if [ -z "${AWS_DEFAULT_REGION:-}" ] && [ -z "$(aws configure get region)" ]; then
        error "AWS region is not configured. Please set AWS_DEFAULT_REGION or run 'aws configure'."
        exit 1
    fi
    
    # Check S3 Tables availability in region
    AWS_REGION=$(aws configure get region || echo $AWS_DEFAULT_REGION)
    log "Checking S3 Tables availability in region: $AWS_REGION"
    
    # Note: S3 Tables is available in limited regions - this would need to be updated based on current availability
    case "$AWS_REGION" in
        us-east-1|us-west-2|eu-west-1)
            log "S3 Tables is supported in region $AWS_REGION"
            ;;
        *)
            warning "S3 Tables availability in region $AWS_REGION should be verified."
            warning "Please check AWS documentation for current regional availability."
            ;;
    esac
    
    success "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set basic AWS environment
    export AWS_REGION=$(aws configure get region || echo ${AWS_DEFAULT_REGION:-us-east-1})
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    log "Generating unique resource identifiers..."
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7 | tr -d '\n')$(shuf -i 100-999 -n 1)")
    
    # Set resource names
    export TABLE_BUCKET_NAME="analytics-tables-${RANDOM_SUFFIX}"
    export NAMESPACE_NAME="sales_analytics"
    export TABLE_NAME="transaction_data"
    export GLUE_DATABASE_NAME="s3_tables_analytics"
    export WORKGROUP_NAME="s3-tables-workgroup"
    export ETL_BUCKET_NAME="glue-etl-data-${RANDOM_SUFFIX}"
    export ATHENA_RESULTS_BUCKET="aws-athena-query-results-${AWS_ACCOUNT_ID}-${AWS_REGION}"
    
    # Save environment to file for later cleanup
    cat > .env_deploy << EOF
# S3 Tables Analytics Deployment Environment
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
TABLE_BUCKET_NAME=${TABLE_BUCKET_NAME}
NAMESPACE_NAME=${NAMESPACE_NAME}
TABLE_NAME=${TABLE_NAME}
GLUE_DATABASE_NAME=${GLUE_DATABASE_NAME}
WORKGROUP_NAME=${WORKGROUP_NAME}
ETL_BUCKET_NAME=${ETL_BUCKET_NAME}
ATHENA_RESULTS_BUCKET=${ATHENA_RESULTS_BUCKET}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    success "Environment configured with unique suffix: ${RANDOM_SUFFIX}"
    log "Table bucket name: ${TABLE_BUCKET_NAME}"
    log "Environment saved to .env_deploy for cleanup reference"
}

# Function to create S3 table bucket
create_table_bucket() {
    log "Creating S3 table bucket for analytics workloads..."
    
    # Create S3 table bucket
    if aws s3tables create-table-bucket --name ${TABLE_BUCKET_NAME} &> /dev/null; then
        success "S3 table bucket created: ${TABLE_BUCKET_NAME}"
    else
        error "Failed to create S3 table bucket. Check if S3 Tables is available in your region."
        exit 1
    fi
    
    # Store table bucket ARN
    export TABLE_BUCKET_ARN=$(aws s3tables list-table-buckets \
        --query "tableBuckets[?name=='${TABLE_BUCKET_NAME}'].arn" \
        --output text)
    
    if [ -z "$TABLE_BUCKET_ARN" ]; then
        error "Failed to retrieve table bucket ARN"
        exit 1
    fi
    
    log "Table bucket ARN: ${TABLE_BUCKET_ARN}"
    
    # Update environment file
    echo "TABLE_BUCKET_ARN=${TABLE_BUCKET_ARN}" >> .env_deploy
}

# Function to enable AWS analytics services integration
enable_analytics_integration() {
    log "Enabling AWS analytics services integration..."
    
    # Create policy for AWS analytics services integration
    cat > /tmp/table_bucket_policy.json << EOF
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
                "s3tables:GetTableMetadataLocation"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Apply the policy
    if aws s3tables put-table-bucket-policy \
        --table-bucket-arn ${TABLE_BUCKET_ARN} \
        --resource-policy file:///tmp/table_bucket_policy.json; then
        success "AWS analytics services integration enabled"
    else
        error "Failed to enable analytics services integration"
        exit 1
    fi
    
    # Clean up temporary policy file
    rm -f /tmp/table_bucket_policy.json
}

# Function to create namespace
create_namespace() {
    log "Creating table namespace for data organization..."
    
    # Create namespace
    if aws s3tables create-namespace \
        --table-bucket-arn ${TABLE_BUCKET_ARN} \
        --namespace ${NAMESPACE_NAME}; then
        success "Namespace created: ${NAMESPACE_NAME}"
    else
        error "Failed to create namespace"
        exit 1
    fi
    
    # Verify namespace creation
    log "Verifying namespace creation..."
    if aws s3tables list-namespaces \
        --table-bucket-arn ${TABLE_BUCKET_ARN} \
        --query "namespaces[?namespace=='${NAMESPACE_NAME}']" | grep -q "${NAMESPACE_NAME}"; then
        success "Namespace verification completed"
    else
        warning "Namespace created but verification failed"
    fi
}

# Function to create Iceberg table
create_iceberg_table() {
    log "Creating Apache Iceberg table with optimized schema..."
    
    # Create Iceberg table
    if aws s3tables create-table \
        --table-bucket-arn ${TABLE_BUCKET_ARN} \
        --namespace ${NAMESPACE_NAME} \
        --name ${TABLE_NAME} \
        --format ICEBERG; then
        success "Iceberg table created: ${TABLE_NAME}"
    else
        error "Failed to create Iceberg table"
        exit 1
    fi
    
    # Store table ARN
    export TABLE_ARN=$(aws s3tables get-table \
        --table-bucket-arn ${TABLE_BUCKET_ARN} \
        --namespace ${NAMESPACE_NAME} \
        --name ${TABLE_NAME} \
        --query "arn" --output text)
    
    log "Table ARN: ${TABLE_ARN}"
    echo "TABLE_ARN=${TABLE_ARN}" >> .env_deploy
}

# Function to configure Glue Data Catalog
configure_glue_catalog() {
    log "Configuring AWS Glue Data Catalog integration..."
    
    # Create Glue database
    if aws glue create-database \
        --database-input Name=${GLUE_DATABASE_NAME} \
        --query "Database.Name" --output text &> /dev/null; then
        success "Glue database created: ${GLUE_DATABASE_NAME}"
    else
        # Check if database already exists
        if aws glue get-database --name ${GLUE_DATABASE_NAME} &> /dev/null; then
            warning "Glue database already exists: ${GLUE_DATABASE_NAME}"
        else
            error "Failed to create Glue database"
            exit 1
        fi
    fi
    
    # Enable S3 Tables maintenance configuration
    log "Enabling automated maintenance for S3 Tables..."
    if aws s3tables put-table-bucket-maintenance-configuration \
        --table-bucket-arn ${TABLE_BUCKET_ARN} \
        --type autoMaintenance \
        --value enabled; then
        success "Automated maintenance enabled for S3 Tables"
    else
        warning "Failed to enable automated maintenance (this may not be available in all regions)"
    fi
}

# Function to prepare sample data
prepare_sample_data() {
    log "Creating sample dataset and preparing data source..."
    
    # Create sample data file
    cat > /tmp/sample_transactions.csv << 'EOF'
transaction_id,customer_id,product_id,quantity,price,transaction_date,region
1,101,501,2,29.99,2024-01-15,us-east-1
2,102,502,1,149.99,2024-01-15,us-west-2
3,103,503,3,19.99,2024-01-16,eu-west-1
4,104,501,1,29.99,2024-01-16,us-east-1
5,105,504,2,79.99,2024-01-17,ap-southeast-1
6,106,505,4,99.99,2024-01-17,us-east-1
7,107,506,1,199.99,2024-01-18,eu-central-1
8,108,507,2,49.99,2024-01-18,ap-northeast-1
9,109,508,3,39.99,2024-01-19,us-west-1
10,110,509,1,89.99,2024-01-19,us-east-2
EOF
    
    # Create temporary S3 bucket for data ingestion
    log "Creating S3 bucket for ETL data..."
    if aws s3 mb s3://${ETL_BUCKET_NAME} --region ${AWS_REGION}; then
        success "ETL data bucket created: ${ETL_BUCKET_NAME}"
    else
        # Check if bucket already exists
        if aws s3 ls s3://${ETL_BUCKET_NAME} &> /dev/null; then
            warning "ETL bucket already exists: ${ETL_BUCKET_NAME}"
        else
            error "Failed to create ETL bucket"
            exit 1
        fi
    fi
    
    # Upload sample data to S3
    if aws s3 cp /tmp/sample_transactions.csv s3://${ETL_BUCKET_NAME}/input/; then
        success "Sample dataset uploaded to S3"
    else
        error "Failed to upload sample dataset"
        exit 1
    fi
    
    # Clean up local sample file
    rm -f /tmp/sample_transactions.csv
}

# Function to configure Athena
configure_athena() {
    log "Setting up Amazon Athena for interactive querying..."
    
    # Create Athena results bucket if it doesn't exist
    log "Creating Athena results bucket..."
    if aws s3 mb s3://${ATHENA_RESULTS_BUCKET} --region ${AWS_REGION} 2>/dev/null; then
        success "Athena results bucket created: ${ATHENA_RESULTS_BUCKET}"
    else
        if aws s3 ls s3://${ATHENA_RESULTS_BUCKET} &> /dev/null; then
            warning "Athena results bucket already exists: ${ATHENA_RESULTS_BUCKET}"
        else
            error "Failed to create Athena results bucket"
            exit 1
        fi
    fi
    
    # Create Athena work group
    log "Creating Athena workgroup..."
    cat > /tmp/workgroup_config.json << EOF
{
    "ResultConfiguration": {
        "OutputLocation": "s3://${ATHENA_RESULTS_BUCKET}"
    },
    "EnforceWorkGroupConfiguration": true,
    "PublishCloudWatchMetrics": true
}
EOF
    
    if aws athena create-work-group \
        --name ${WORKGROUP_NAME} \
        --configuration file:///tmp/workgroup_config.json \
        --description "S3 Tables analytics workgroup"; then
        success "Athena workgroup created: ${WORKGROUP_NAME}"
    else
        # Check if workgroup already exists
        if aws athena get-work-group --work-group ${WORKGROUP_NAME} &> /dev/null; then
            warning "Athena workgroup already exists: ${WORKGROUP_NAME}"
        else
            error "Failed to create Athena workgroup"
            exit 1
        fi
    fi
    
    # Clean up temporary config file
    rm -f /tmp/workgroup_config.json
}

# Function to prepare QuickSight configuration
prepare_quicksight() {
    log "Preparing Amazon QuickSight configuration..."
    
    # Check QuickSight account status
    log "Checking QuickSight account status..."
    if aws quicksight describe-account-settings \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --region ${AWS_REGION} &> /dev/null; then
        success "QuickSight account is configured"
        log "QuickSight data source can be connected to Athena workgroup: ${WORKGROUP_NAME}"
    else
        warning "QuickSight is not configured in this account"
        warning "Manual setup required in AWS Console to complete QuickSight integration"
    fi
    
    log "QuickSight configuration notes:"
    log "  - Connect QuickSight to Athena workgroup: ${WORKGROUP_NAME}"
    log "  - Use database: ${GLUE_DATABASE_NAME}"
    log "  - Use table: ${TABLE_NAME}"
}

# Function to run validation tests
run_validation() {
    log "Running validation and testing..."
    
    # Test 1: Verify table bucket and resources
    log "Validating S3 table bucket and resources..."
    if aws s3tables get-table-bucket --name ${TABLE_BUCKET_NAME} &> /dev/null; then
        success "Table bucket validation passed"
    else
        error "Table bucket validation failed"
        exit 1
    fi
    
    # Test 2: List namespaces and tables
    log "Validating namespaces and tables..."
    if aws s3tables list-namespaces --table-bucket-arn ${TABLE_BUCKET_ARN} | grep -q "${NAMESPACE_NAME}"; then
        success "Namespace validation passed"
    else
        error "Namespace validation failed"
        exit 1
    fi
    
    if aws s3tables list-tables \
        --table-bucket-arn ${TABLE_BUCKET_ARN} \
        --namespace ${NAMESPACE_NAME} | grep -q "${TABLE_NAME}"; then
        success "Table validation passed"
    else
        error "Table validation failed"
        exit 1
    fi
    
    # Test 3: Validate Glue catalog integration
    log "Validating Glue Data Catalog integration..."
    if aws glue get-database --name ${GLUE_DATABASE_NAME} &> /dev/null; then
        success "Glue database validation passed"
    else
        warning "Glue database validation failed - manual verification may be required"
    fi
    
    # Test 4: Validate maintenance configuration
    log "Validating maintenance configuration..."
    if aws s3tables get-table-bucket-maintenance-configuration \
        --table-bucket-arn ${TABLE_BUCKET_ARN} &> /dev/null; then
        success "Maintenance configuration validation passed"
    else
        warning "Maintenance configuration validation failed - this may not be available in all regions"
    fi
    
    success "Validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "==================="
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "S3 Tables Resources:"
    echo "  - Table Bucket: ${TABLE_BUCKET_NAME}"
    echo "  - Table Bucket ARN: ${TABLE_BUCKET_ARN}"
    echo "  - Namespace: ${NAMESPACE_NAME}"
    echo "  - Table: ${TABLE_NAME}"
    echo ""
    echo "Analytics Services:"
    echo "  - Glue Database: ${GLUE_DATABASE_NAME}"
    echo "  - Athena Workgroup: ${WORKGROUP_NAME}"
    echo "  - Athena Results Bucket: ${ATHENA_RESULTS_BUCKET}"
    echo ""
    echo "Data Sources:"
    echo "  - ETL Bucket: ${ETL_BUCKET_NAME}"
    echo "  - Sample Data: s3://${ETL_BUCKET_NAME}/input/sample_transactions.csv"
    echo ""
    echo "Next Steps:"
    echo "  1. Use Athena to query your S3 Tables through workgroup: ${WORKGROUP_NAME}"
    echo "  2. Connect QuickSight to Athena for data visualization"
    echo "  3. Use AWS Glue for ETL processing with database: ${GLUE_DATABASE_NAME}"
    echo ""
    echo "Cleanup:"
    echo "  - Run './destroy.sh' to remove all resources"
    echo "  - Environment file '.env_deploy' contains all resource identifiers"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting AWS S3 Tables Analytics Solution deployment..."
    log "This script will deploy S3 Tables, Athena, Glue, and QuickSight integration"
    
    # Check if running in dry-run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log "Running in DRY-RUN mode - no resources will be created"
        warning "Set DRY_RUN=false to perform actual deployment"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_table_bucket
    enable_analytics_integration
    create_namespace
    create_iceberg_table
    configure_glue_catalog
    prepare_sample_data
    configure_athena
    prepare_quicksight
    run_validation
    display_summary
    
    log "Deployment completed in $(date)"
}

# Error handling function
cleanup_on_error() {
    error "Deployment failed. Attempting partial cleanup..."
    
    # Source environment if it exists
    if [ -f .env_deploy ]; then
        source .env_deploy
        warning "Running destroy script to clean up partial deployment..."
        if [ -f "./destroy.sh" ]; then
            chmod +x ./destroy.sh
            ./destroy.sh
        fi
    fi
    
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Execute main function
main "$@"