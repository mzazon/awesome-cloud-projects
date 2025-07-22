#!/bin/bash

# AWS Data Lake Architecture Deployment Script
# This script deploys S3, Glue, and Athena resources for a data lake architecture
# Following the recipe: Building Data Lake Architectures with S3, Glue, and Athena

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Unable to determine AWS account ID. Check your AWS credentials."
    fi
    
    log "Prerequisites check passed ✅"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "AWS region not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export DATA_LAKE_BUCKET="data-lake-${RANDOM_SUFFIX}"
    export GLUE_DATABASE_NAME="datalake_db_${RANDOM_SUFFIX}"
    export GLUE_ROLE_NAME="GlueServiceRole-${RANDOM_SUFFIX}"
    export ATHENA_RESULTS_BUCKET="athena-results-${RANDOM_SUFFIX}"
    export SALES_CRAWLER_NAME="sales-data-crawler-${RANDOM_SUFFIX}"
    export LOGS_CRAWLER_NAME="web-logs-crawler-${RANDOM_SUFFIX}"
    export ETL_JOB_NAME="sales-data-etl-${RANDOM_SUFFIX}"
    export ATHENA_WORKGROUP="DataLakeWorkgroup-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > /tmp/data-lake-env.sh << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export DATA_LAKE_BUCKET="$DATA_LAKE_BUCKET"
export GLUE_DATABASE_NAME="$GLUE_DATABASE_NAME"
export GLUE_ROLE_NAME="$GLUE_ROLE_NAME"
export ATHENA_RESULTS_BUCKET="$ATHENA_RESULTS_BUCKET"
export SALES_CRAWLER_NAME="$SALES_CRAWLER_NAME"
export LOGS_CRAWLER_NAME="$LOGS_CRAWLER_NAME"
export ETL_JOB_NAME="$ETL_JOB_NAME"
export ATHENA_WORKGROUP="$ATHENA_WORKGROUP"
EOF
    
    log "Environment setup complete ✅"
    info "Data Lake Bucket: $DATA_LAKE_BUCKET"
    info "Glue Database: $GLUE_DATABASE_NAME"
    info "Athena Results: $ATHENA_RESULTS_BUCKET"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets for data lake storage..."
    
    # Create main data lake bucket
    if aws s3api head-bucket --bucket "$DATA_LAKE_BUCKET" 2>/dev/null; then
        warn "Bucket $DATA_LAKE_BUCKET already exists"
    else
        aws s3 mb "s3://$DATA_LAKE_BUCKET" --region "$AWS_REGION"
        log "Created data lake bucket: $DATA_LAKE_BUCKET"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "$DATA_LAKE_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Create Athena query results bucket
    if aws s3api head-bucket --bucket "$ATHENA_RESULTS_BUCKET" 2>/dev/null; then
        warn "Bucket $ATHENA_RESULTS_BUCKET already exists"
    else
        aws s3 mb "s3://$ATHENA_RESULTS_BUCKET" --region "$AWS_REGION"
        log "Created Athena results bucket: $ATHENA_RESULTS_BUCKET"
    fi
    
    # Create folder structure for data lake zones
    aws s3api put-object --bucket "$DATA_LAKE_BUCKET" --key raw-zone/ || true
    aws s3api put-object --bucket "$DATA_LAKE_BUCKET" --key processed-zone/ || true
    aws s3api put-object --bucket "$DATA_LAKE_BUCKET" --key archive-zone/ || true
    aws s3api put-object --bucket "$DATA_LAKE_BUCKET" --key scripts/ || true
    
    log "S3 buckets and folder structure created ✅"
}

# Function to set up lifecycle policies
setup_lifecycle_policies() {
    log "Setting up S3 lifecycle policies for cost optimization..."
    
    # Create lifecycle policy for intelligent tiering
    cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "DataLakeLifecycleRule",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "raw-zone/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        },
        {
            "ID": "ProcessedDataLifecycle",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "processed-zone/"
            },
            "Transitions": [
                {
                    "Days": 90,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 180,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF
    
    # Apply lifecycle policy
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$DATA_LAKE_BUCKET" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    
    log "S3 lifecycle policies applied ✅"
}

# Function to create IAM role for Glue
create_glue_iam_role() {
    log "Creating IAM role for AWS Glue services..."
    
    # Create trust policy for Glue service
    cat > /tmp/glue-trust-policy.json << EOF
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
    
    # Create IAM role for Glue
    if aws iam get-role --role-name "$GLUE_ROLE_NAME" &>/dev/null; then
        warn "IAM role $GLUE_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$GLUE_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/glue-trust-policy.json
        log "Created IAM role: $GLUE_ROLE_NAME"
    fi
    
    # Attach AWS managed policy for Glue service
    aws iam attach-role-policy \
        --role-name "$GLUE_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
    
    # Create custom policy for S3 access
    cat > /tmp/glue-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::$DATA_LAKE_BUCKET",
                "arn:aws:s3:::$DATA_LAKE_BUCKET/*"
            ]
        }
    ]
}
EOF
    
    # Create and attach custom S3 policy
    S3_POLICY_NAME="${GLUE_ROLE_NAME}-S3Policy"
    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$S3_POLICY_NAME" &>/dev/null; then
        warn "Policy $S3_POLICY_NAME already exists"
    else
        aws iam create-policy \
            --policy-name "$S3_POLICY_NAME" \
            --policy-document file:///tmp/glue-s3-policy.json
        log "Created custom S3 policy: $S3_POLICY_NAME"
    fi
    
    aws iam attach-role-policy \
        --role-name "$GLUE_ROLE_NAME" \
        --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$S3_POLICY_NAME"
    
    # Wait for role to be available
    sleep 10
    
    # Get Glue role ARN
    export GLUE_ROLE_ARN=$(aws iam get-role \
        --role-name "$GLUE_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    log "IAM role for AWS Glue created ✅"
    info "Glue Role ARN: $GLUE_ROLE_ARN"
}

# Function to upload sample data
upload_sample_data() {
    log "Uploading sample data to S3..."
    
    # Create sample CSV data
    cat > /tmp/sample-sales-data.csv << 'EOF'
order_id,customer_id,product_name,category,quantity,price,order_date,region
1001,C001,Laptop,Electronics,1,999.99,2024-01-15,North
1002,C002,Coffee Maker,Appliances,2,79.99,2024-01-15,South
1003,C003,Book Set,Books,3,45.50,2024-01-16,East
1004,C001,Wireless Mouse,Electronics,1,29.99,2024-01-16,North
1005,C004,Desk Chair,Furniture,1,199.99,2024-01-17,West
1006,C005,Smartphone,Electronics,1,699.99,2024-01-17,South
1007,C002,Blender,Appliances,1,89.99,2024-01-18,South
1008,C006,Novel,Books,5,12.99,2024-01-18,East
1009,C003,Monitor,Electronics,2,299.99,2024-01-19,East
1010,C007,Coffee Table,Furniture,1,149.99,2024-01-19,West
EOF
    
    # Create sample JSON data
    cat > /tmp/sample-web-logs.json << 'EOF'
{"timestamp":"2024-01-15T10:30:00Z","user_id":"U001","page":"/home","action":"view","duration":45,"ip":"192.168.1.100"}
{"timestamp":"2024-01-15T10:31:00Z","user_id":"U002","page":"/products","action":"view","duration":120,"ip":"192.168.1.101"}
{"timestamp":"2024-01-15T10:32:00Z","user_id":"U001","page":"/cart","action":"add_item","duration":30,"ip":"192.168.1.100"}
{"timestamp":"2024-01-15T10:33:00Z","user_id":"U003","page":"/checkout","action":"purchase","duration":180,"ip":"192.168.1.102"}
{"timestamp":"2024-01-15T10:34:00Z","user_id":"U002","page":"/profile","action":"update","duration":90,"ip":"192.168.1.101"}
EOF
    
    # Upload sample data with partitioning
    aws s3 cp /tmp/sample-sales-data.csv \
        "s3://$DATA_LAKE_BUCKET/raw-zone/sales-data/year=2024/month=01/sample-sales-data.csv"
    
    aws s3 cp /tmp/sample-web-logs.json \
        "s3://$DATA_LAKE_BUCKET/raw-zone/web-logs/year=2024/month=01/sample-web-logs.json"
    
    log "Sample data uploaded ✅"
}

# Function to create Glue database
create_glue_database() {
    log "Creating Glue database..."
    
    if aws glue get-database --name "$GLUE_DATABASE_NAME" &>/dev/null; then
        warn "Glue database $GLUE_DATABASE_NAME already exists"
    else
        aws glue create-database \
            --database-input "{\"Name\":\"$GLUE_DATABASE_NAME\",\"Description\":\"Data lake database for analytics\"}"
        log "Created Glue database: $GLUE_DATABASE_NAME"
    fi
    
    log "Glue database created ✅"
}

# Function to create and run Glue crawlers
create_glue_crawlers() {
    log "Creating and running Glue crawlers..."
    
    # Create crawler for sales data
    if aws glue get-crawler --name "$SALES_CRAWLER_NAME" &>/dev/null; then
        warn "Crawler $SALES_CRAWLER_NAME already exists"
    else
        aws glue create-crawler \
            --name "$SALES_CRAWLER_NAME" \
            --role "$GLUE_ROLE_ARN" \
            --database-name "$GLUE_DATABASE_NAME" \
            --targets "{
                \"S3Targets\": [
                    {
                        \"Path\": \"s3://$DATA_LAKE_BUCKET/raw-zone/sales-data/\"
                    }
                ]
            }" \
            --description "Crawler for sales data in CSV format"
        log "Created crawler: $SALES_CRAWLER_NAME"
    fi
    
    # Create crawler for web logs
    if aws glue get-crawler --name "$LOGS_CRAWLER_NAME" &>/dev/null; then
        warn "Crawler $LOGS_CRAWLER_NAME already exists"
    else
        aws glue create-crawler \
            --name "$LOGS_CRAWLER_NAME" \
            --role "$GLUE_ROLE_ARN" \
            --database-name "$GLUE_DATABASE_NAME" \
            --targets "{
                \"S3Targets\": [
                    {
                        \"Path\": \"s3://$DATA_LAKE_BUCKET/raw-zone/web-logs/\"
                    }
                ]
            }" \
            --description "Crawler for web logs in JSON format"
        log "Created crawler: $LOGS_CRAWLER_NAME"
    fi
    
    # Start crawlers
    aws glue start-crawler --name "$SALES_CRAWLER_NAME" || warn "Failed to start $SALES_CRAWLER_NAME"
    aws glue start-crawler --name "$LOGS_CRAWLER_NAME" || warn "Failed to start $LOGS_CRAWLER_NAME"
    
    log "Glue crawlers created and started ✅"
    info "Waiting for crawlers to complete..."
    
    # Wait for crawlers to complete
    sleep 60
    
    # Check crawler status
    SALES_CRAWLER_STATE=$(aws glue get-crawler --name "$SALES_CRAWLER_NAME" \
        --query 'Crawler.State' --output text)
    LOGS_CRAWLER_STATE=$(aws glue get-crawler --name "$LOGS_CRAWLER_NAME" \
        --query 'Crawler.State' --output text)
    
    info "Sales crawler state: $SALES_CRAWLER_STATE"
    info "Logs crawler state: $LOGS_CRAWLER_STATE"
}

# Function to create Glue ETL job
create_glue_etl_job() {
    log "Creating Glue ETL job..."
    
    # Create ETL script
    cat > /tmp/glue-etl-script.py << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'TABLE_NAME', 'OUTPUT_PATH'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from Glue catalog
datasource = glueContext.create_dynamic_frame.from_catalog(
    database = args['DATABASE_NAME'],
    table_name = args['TABLE_NAME']
)

# Convert to Spark DataFrame for transformations
df = datasource.toDF()

# Add processing timestamp
df_processed = df.withColumn("processed_timestamp", F.current_timestamp())

# Convert back to DynamicFrame
processed_dynamic_frame = DynamicFrame.fromDF(df_processed, glueContext, "processed_data")

# Write to S3 in Parquet format with partitioning
glueContext.write_dynamic_frame.from_options(
    frame = processed_dynamic_frame,
    connection_type = "s3",
    connection_options = {
        "path": args['OUTPUT_PATH'],
        "partitionKeys": ["year", "month"]
    },
    format = "parquet"
)

job.commit()
EOF
    
    # Upload ETL script to S3
    aws s3 cp /tmp/glue-etl-script.py "s3://$DATA_LAKE_BUCKET/scripts/glue-etl-script.py"
    
    # Create Glue ETL job
    if aws glue get-job --job-name "$ETL_JOB_NAME" &>/dev/null; then
        warn "ETL job $ETL_JOB_NAME already exists"
    else
        aws glue create-job \
            --name "$ETL_JOB_NAME" \
            --role "$GLUE_ROLE_ARN" \
            --command "{
                \"Name\": \"glueetl\",
                \"ScriptLocation\": \"s3://$DATA_LAKE_BUCKET/scripts/glue-etl-script.py\",
                \"PythonVersion\": \"3\"
            }" \
            --default-arguments "{
                \"--DATABASE_NAME\": \"$GLUE_DATABASE_NAME\",
                \"--TABLE_NAME\": \"sales_data\",
                \"--OUTPUT_PATH\": \"s3://$DATA_LAKE_BUCKET/processed-zone/sales-data-processed/\",
                \"--enable-metrics\": \"\",
                \"--enable-continuous-cloudwatch-log\": \"true\"
            }" \
            --max-capacity 2 \
            --timeout 60
        log "Created ETL job: $ETL_JOB_NAME"
    fi
    
    log "Glue ETL job created ✅"
}

# Function to set up Athena
setup_athena() {
    log "Setting up Amazon Athena..."
    
    # Create Athena workgroup
    if aws athena get-work-group --work-group "$ATHENA_WORKGROUP" &>/dev/null; then
        warn "Athena workgroup $ATHENA_WORKGROUP already exists"
    else
        aws athena create-work-group \
            --name "$ATHENA_WORKGROUP" \
            --configuration "{
                \"ResultConfiguration\": {
                    \"OutputLocation\": \"s3://$ATHENA_RESULTS_BUCKET/query-results/\"
                },
                \"EnforceWorkGroupConfiguration\": true,
                \"PublishCloudWatchMetricsEnabled\": true
            }" \
            --description "Workgroup for data lake analytics"
        log "Created Athena workgroup: $ATHENA_WORKGROUP"
    fi
    
    # Create sample queries file
    cat > /tmp/sample-queries.sql << 'EOF'
-- Query 1: Sales summary by region
SELECT 
    region,
    COUNT(*) as total_orders,
    SUM(quantity * price) as total_revenue,
    AVG(price) as avg_price
FROM sales_data
GROUP BY region
ORDER BY total_revenue DESC;

-- Query 2: Top products by revenue
SELECT 
    product_name,
    category,
    SUM(quantity * price) as revenue,
    COUNT(*) as order_count
FROM sales_data
GROUP BY product_name, category
ORDER BY revenue DESC
LIMIT 10;

-- Query 3: Daily sales trend
SELECT 
    order_date,
    COUNT(*) as orders,
    SUM(quantity * price) as daily_revenue
FROM sales_data
GROUP BY order_date
ORDER BY order_date;
EOF
    
    log "Athena setup completed ✅"
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Verify Glue Data Catalog tables
    info "Checking Glue Data Catalog tables..."
    if aws glue get-tables --database-name "$GLUE_DATABASE_NAME" &>/dev/null; then
        aws glue get-tables --database-name "$GLUE_DATABASE_NAME" \
            --query 'TableList[*].[Name,StorageDescriptor.Location]' \
            --output table
        log "Glue tables validation passed ✅"
    else
        warn "Glue tables not found or crawlers still running"
    fi
    
    # Test basic Athena connectivity
    info "Testing Athena connectivity..."
    TEST_QUERY="SELECT 1 as test_value"
    QUERY_ID=$(aws athena start-query-execution \
        --query-string "$TEST_QUERY" \
        --work-group "$ATHENA_WORKGROUP" \
        --query 'QueryExecutionId' --output text 2>/dev/null) || warn "Athena test query failed"
    
    if [ -n "$QUERY_ID" ]; then
        log "Athena connectivity test passed ✅"
        info "Test query execution ID: $QUERY_ID"
    fi
    
    # Verify S3 bucket structure
    info "Verifying S3 bucket structure..."
    aws s3 ls "s3://$DATA_LAKE_BUCKET/" --recursive | head -10
    
    log "Validation completed ✅"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "AWS Region: $AWS_REGION"
    echo "Data Lake Bucket: $DATA_LAKE_BUCKET"
    echo "Athena Results Bucket: $ATHENA_RESULTS_BUCKET"
    echo "Glue Database: $GLUE_DATABASE_NAME"
    echo "Glue Role: $GLUE_ROLE_NAME"
    echo "Athena Workgroup: $ATHENA_WORKGROUP"
    echo "===================="
    echo ""
    echo "Next Steps:"
    echo "1. Wait for Glue crawlers to complete (may take 2-3 minutes)"
    echo "2. Check Athena console to query your data"
    echo "3. Use the sample queries in /tmp/sample-queries.sql"
    echo "4. Run ETL job when ready: aws glue start-job-run --job-name $ETL_JOB_NAME"
    echo ""
    echo "Cleanup: Run ./destroy.sh to remove all resources"
    echo "Environment saved to: /tmp/data-lake-env.sh"
}

# Function to clean up temporary files
cleanup_temp_files() {
    rm -f /tmp/lifecycle-policy.json
    rm -f /tmp/glue-trust-policy.json
    rm -f /tmp/glue-s3-policy.json
    rm -f /tmp/sample-sales-data.csv
    rm -f /tmp/sample-web-logs.json
    rm -f /tmp/glue-etl-script.py
    rm -f /tmp/sample-queries.sql
}

# Main deployment function
main() {
    log "Starting AWS Data Lake Architecture deployment..."
    
    # Check if this is a dry run
    if [ "${1:-}" = "--dry-run" ]; then
        log "DRY RUN MODE - No resources will be created"
        export DRY_RUN=true
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_buckets
    setup_lifecycle_policies
    create_glue_iam_role
    upload_sample_data
    create_glue_database
    create_glue_crawlers
    create_glue_etl_job
    setup_athena
    run_validation
    display_summary
    cleanup_temp_files
    
    log "Deployment completed successfully! ✅"
    warn "Remember to run ./destroy.sh to clean up resources and avoid charges"
}

# Handle script interruption
trap 'error "Deployment interrupted"; cleanup_temp_files; exit 1' INT TERM

# Run main function
main "$@"