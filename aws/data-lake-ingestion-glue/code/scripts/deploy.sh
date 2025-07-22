#!/bin/bash

# =============================================================================
# AWS Data Lake Ingestion Pipeline Deployment Script
# =============================================================================
# This script deploys a complete data lake ingestion pipeline using:
# - AWS Glue for ETL processing and data cataloging
# - S3 for data lake storage (Bronze, Silver, Gold layers)
# - IAM for secure access management
# - CloudWatch for monitoring and alerting
# - SNS for notifications
# - Athena for SQL analytics
# =============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
VERBOSE=false

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
    log "INFO" "${BLUE}$*${NC}"
}

success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

fatal() {
    error "$*"
    exit 1
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Data Lake Ingestion Pipeline with Glue and Data Catalog

OPTIONS:
    -d, --dry-run       Show what would be deployed without making changes
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message
    -r, --region        Specify AWS region (default: from AWS CLI config)
    -p, --prefix        Resource name prefix (default: auto-generated)
    -e, --email         Email address for SNS notifications

EXAMPLES:
    $0 --dry-run
    $0 --verbose --email user@example.com
    $0 --region us-west-2 --prefix mycompany

EOF
}

# =============================================================================
# Prerequisites Checking
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI is not installed. Please install it first."
    fi

    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: ${aws_version}"

    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS credentials not configured. Please run 'aws configure' first."
    fi

    # Get current user info
    local caller_identity=$(aws sts get-caller-identity)
    local account_id=$(echo "${caller_identity}" | jq -r '.Account')
    local user_arn=$(echo "${caller_identity}" | jq -r '.Arn')
    
    info "AWS Account ID: ${account_id}"
    info "User ARN: ${user_arn}"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        fatal "jq is not installed. Please install it for JSON processing."
    fi

    # Verify required permissions
    check_permissions

    success "Prerequisites check completed"
}

check_permissions() {
    info "Checking AWS permissions..."

    local required_permissions=(
        "glue:CreateDatabase"
        "glue:CreateCrawler" 
        "glue:CreateJob"
        "glue:CreateWorkflow"
        "s3:CreateBucket"
        "s3:PutObject"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "sns:CreateTopic"
        "cloudwatch:PutMetricAlarm"
        "athena:CreateWorkGroup"
    )

    # Test key permissions by attempting dry-run operations
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        warning "Limited IAM permissions detected. Some operations may fail."
    fi

    if ! aws s3 ls &> /dev/null; then
        warning "Limited S3 permissions detected. Bucket operations may fail."
    fi

    success "Permissions check completed"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    info "Setting up environment variables..."

    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, defaulting to us-east-1"
        fi
    fi

    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Generate unique suffix if not provided
    if [[ -z "${RESOURCE_PREFIX:-}" ]]; then
        local random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
        export RESOURCE_PREFIX="datalake-${random_suffix}"
    fi

    # Set resource names
    export GLUE_DATABASE_NAME="${RESOURCE_PREFIX}-catalog"
    export S3_BUCKET_NAME="${RESOURCE_PREFIX}-pipeline"
    export GLUE_ROLE_NAME="GlueDataLakeRole-${RESOURCE_PREFIX}"
    export CRAWLER_NAME="${RESOURCE_PREFIX}-crawler"
    export ETL_JOB_NAME="${RESOURCE_PREFIX}-etl-job"
    export WORKFLOW_NAME="${RESOURCE_PREFIX}-workflow"
    export SNS_TOPIC_NAME="DataLakeAlerts-${RESOURCE_PREFIX}"

    info "Environment configured with prefix: ${RESOURCE_PREFIX}"
    success "Environment setup completed"
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

create_s3_bucket() {
    info "Creating S3 bucket for data lake..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would create S3 bucket: ${S3_BUCKET_NAME}"
        return 0
    fi

    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        warning "S3 bucket ${S3_BUCKET_NAME} already exists"
        return 0
    fi

    # Create bucket with appropriate location constraint
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
    fi

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled

    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${S3_BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'

    # Create folder structure
    local folders=("raw-data/" "processed-data/bronze/" "processed-data/silver/" 
                   "processed-data/gold/" "scripts/" "temp/" "athena-results/" "queries/")
    
    for folder in "${folders[@]}"; do
        aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key "${folder}"
    done

    success "S3 bucket created with folder structure"
}

create_iam_role() {
    info "Creating IAM role for AWS Glue..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would create IAM role: ${GLUE_ROLE_NAME}"
        return 0
    fi

    # Check if role already exists
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${GLUE_ROLE_NAME} already exists"
        export GLUE_ROLE_ARN=$(aws iam get-role --role-name "${GLUE_ROLE_NAME}" --query 'Role.Arn' --output text)
        return 0
    fi

    # Create trust policy
    local trust_policy=$(cat << EOF
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
)

    # Create IAM role
    aws iam create-role \
        --role-name "${GLUE_ROLE_NAME}" \
        --assume-role-policy-document "${trust_policy}" \
        --description "IAM role for AWS Glue data lake operations"

    # Attach managed policy
    aws iam attach-role-policy \
        --role-name "${GLUE_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"

    # Create custom S3 policy
    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:GetBucketAcl",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${S3_BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
)

    aws iam put-role-policy \
        --role-name "${GLUE_ROLE_NAME}" \
        --policy-name "GlueS3Access" \
        --policy-document "${s3_policy}"

    # Get role ARN
    export GLUE_ROLE_ARN=$(aws iam get-role --role-name "${GLUE_ROLE_NAME}" --query 'Role.Arn' --output text)

    success "IAM role created: ${GLUE_ROLE_NAME}"
}

upload_sample_data() {
    info "Creating and uploading sample data..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would upload sample data to S3"
        return 0
    fi

    # Create temporary directory for sample data
    local temp_dir=$(mktemp -d)
    
    # Create sample JSON events data
    cat > "${temp_dir}/sample-events.json" << 'EOF'
{"event_id": "evt001", "user_id": "user123", "event_type": "purchase", "product_id": "prod456", "amount": 89.99, "timestamp": "2024-01-15T10:30:00Z", "category": "electronics"}
{"event_id": "evt002", "user_id": "user456", "event_type": "view", "product_id": "prod789", "amount": 0.0, "timestamp": "2024-01-15T10:31:00Z", "category": "books"}
{"event_id": "evt003", "user_id": "user789", "event_type": "cart_add", "product_id": "prod123", "amount": 45.50, "timestamp": "2024-01-15T10:32:00Z", "category": "clothing"}
{"event_id": "evt004", "user_id": "user123", "event_type": "purchase", "product_id": "prod321", "amount": 129.00, "timestamp": "2024-01-15T10:33:00Z", "category": "home"}
{"event_id": "evt005", "user_id": "user654", "event_type": "view", "product_id": "prod555", "amount": 0.0, "timestamp": "2024-01-15T10:34:00Z", "category": "electronics"}
EOF

    # Create sample CSV customers data
    cat > "${temp_dir}/sample-customers.csv" << 'EOF'
customer_id,name,email,registration_date,country,age_group
user123,John Doe,john.doe@example.com,2023-05-15,US,25-34
user456,Jane Smith,jane.smith@example.com,2023-06-20,CA,35-44
user789,Bob Johnson,bob.johnson@example.com,2023-07-10,UK,45-54
user654,Alice Brown,alice.brown@example.com,2023-08-05,US,18-24
user321,Charlie Wilson,charlie.wilson@example.com,2023-09-12,AU,25-34
EOF

    # Upload to S3
    aws s3 cp "${temp_dir}/sample-events.json" "s3://${S3_BUCKET_NAME}/raw-data/events/"
    aws s3 cp "${temp_dir}/sample-customers.csv" "s3://${S3_BUCKET_NAME}/raw-data/customers/"

    # Create partitioned event data
    mkdir -p "${temp_dir}/events/year=2024/month=01/day=15"
    cp "${temp_dir}/sample-events.json" "${temp_dir}/events/year=2024/month=01/day=15/"
    aws s3 sync "${temp_dir}/events" "s3://${S3_BUCKET_NAME}/raw-data/events/"

    # Cleanup
    rm -rf "${temp_dir}"

    success "Sample data uploaded to S3"
}

create_glue_database() {
    info "Creating AWS Glue database..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would create Glue database: ${GLUE_DATABASE_NAME}"
        return 0
    fi

    # Check if database already exists
    if aws glue get-database --name "${GLUE_DATABASE_NAME}" &> /dev/null; then
        warning "Glue database ${GLUE_DATABASE_NAME} already exists"
        return 0
    fi

    aws glue create-database \
        --database-input "{
            \"Name\": \"${GLUE_DATABASE_NAME}\",
            \"Description\": \"Data lake catalog for analytics pipeline\"
        }"

    success "Glue database created: ${GLUE_DATABASE_NAME}"
}

create_glue_crawler() {
    info "Creating AWS Glue crawler..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would create Glue crawler: ${CRAWLER_NAME}"
        return 0
    fi

    # Check if crawler already exists
    if aws glue get-crawler --name "${CRAWLER_NAME}" &> /dev/null; then
        warning "Glue crawler ${CRAWLER_NAME} already exists"
        return 0
    fi

    # Create crawler configuration
    local crawler_config=$(cat << EOF
{
    "Name": "${CRAWLER_NAME}",
    "Role": "${GLUE_ROLE_ARN}",
    "DatabaseName": "${GLUE_DATABASE_NAME}",
    "Description": "Crawler for data lake raw data sources",
    "Targets": {
        "S3Targets": [
            {
                "Path": "s3://${S3_BUCKET_NAME}/raw-data/"
            }
        ]
    },
    "TablePrefix": "raw_",
    "SchemaChangePolicy": {
        "UpdateBehavior": "UPDATE_IN_DATABASE",
        "DeleteBehavior": "LOG"
    },
    "RecrawlPolicy": {
        "RecrawlBehavior": "CRAWL_EVERYTHING"
    },
    "LineageConfiguration": {
        "CrawlerLineageSettings": "ENABLE"
    }
}
EOF
)

    # Create crawler
    echo "${crawler_config}" | aws glue create-crawler --cli-input-json file:///dev/stdin

    success "Glue crawler created: ${CRAWLER_NAME}"
}

create_etl_script() {
    info "Creating and uploading ETL script..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would create and upload ETL script"
        return 0
    fi

    # Create ETL script
    local temp_dir=$(mktemp -d)
    cat > "${temp_dir}/etl-script.py" << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *
import boto3

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Get job parameters
args = getResolvedOptions(sys.argv, [
    'JOB_NAME', 
    'DATABASE_NAME', 
    'S3_BUCKET_NAME',
    'SOURCE_TABLE_EVENTS',
    'SOURCE_TABLE_CUSTOMERS'
])

job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from Data Catalog
events_df = glueContext.create_dynamic_frame.from_catalog(
    database=args['DATABASE_NAME'],
    table_name=args['SOURCE_TABLE_EVENTS']
).toDF()

customers_df = glueContext.create_dynamic_frame.from_catalog(
    database=args['DATABASE_NAME'],
    table_name=args['SOURCE_TABLE_CUSTOMERS']
).toDF()

# Bronze layer: Raw data with basic cleansing
print("Processing Bronze Layer...")

# Clean and standardize events data
events_bronze = events_df.withColumn(
    "timestamp", 
    to_timestamp(col("timestamp"))
).withColumn(
    "amount", 
    col("amount").cast("double")
).filter(
    col("event_id").isNotNull() & 
    col("user_id").isNotNull()
)

# Add processing metadata
events_bronze = events_bronze.withColumn(
    "processing_date", 
    current_date()
).withColumn(
    "processing_timestamp", 
    current_timestamp()
)

# Write to Bronze layer
events_bronze.write.mode("overwrite").parquet(
    f"s3://{args['S3_BUCKET_NAME']}/processed-data/bronze/events/"
)

# Silver layer: Business logic and data quality
print("Processing Silver Layer...")

# Enrich events with customer data
events_silver = events_bronze.join(
    customers_df,
    events_bronze.user_id == customers_df.customer_id,
    "left"
).select(
    events_bronze["*"],
    customers_df["name"].alias("customer_name"),
    customers_df["email"].alias("customer_email"),
    customers_df["country"],
    customers_df["age_group"]
)

# Add business metrics
events_silver = events_silver.withColumn(
    "is_purchase", 
    when(col("event_type") == "purchase", 1).otherwise(0)
).withColumn(
    "is_high_value", 
    when(col("amount") > 100, 1).otherwise(0)
).withColumn(
    "event_date", 
    to_date(col("timestamp"))
).withColumn(
    "event_hour", 
    hour(col("timestamp"))
)

# Write to Silver layer partitioned by date
events_silver.write.mode("overwrite").partitionBy("event_date").parquet(
    f"s3://{args['S3_BUCKET_NAME']}/processed-data/silver/events/"
)

# Gold layer: Analytics-ready aggregated data
print("Processing Gold Layer...")

# Daily sales summary
daily_sales = events_silver.filter(
    col("event_type") == "purchase"
).groupBy(
    "event_date", "category", "country"
).agg(
    count("*").alias("total_purchases"),
    sum("amount").alias("total_revenue"),
    avg("amount").alias("avg_order_value"),
    countDistinct("user_id").alias("unique_customers")
)

# Customer behavior summary
customer_behavior = events_silver.groupBy(
    "user_id", "customer_name", "country", "age_group"
).agg(
    count("*").alias("total_events"),
    sum("is_purchase").alias("total_purchases"),
    sum("amount").alias("total_spent"),
    countDistinct("category").alias("categories_engaged")
).withColumn(
    "avg_order_value",
    when(col("total_purchases") > 0, col("total_spent") / col("total_purchases")).otherwise(0)
)

# Write Gold layer data
daily_sales.write.mode("overwrite").parquet(
    f"s3://{args['S3_BUCKET_NAME']}/processed-data/gold/daily_sales/"
)

customer_behavior.write.mode("overwrite").parquet(
    f"s3://{args['S3_BUCKET_NAME']}/processed-data/gold/customer_behavior/"
)

print("ETL job completed successfully!")
job.commit()
EOF

    # Upload script to S3
    aws s3 cp "${temp_dir}/etl-script.py" "s3://${S3_BUCKET_NAME}/scripts/"

    # Cleanup
    rm -rf "${temp_dir}"

    success "ETL script uploaded to S3"
}

create_glue_job() {
    info "Creating AWS Glue ETL job..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would create Glue ETL job: ${ETL_JOB_NAME}"
        return 0
    fi

    # Check if job already exists
    if aws glue get-job --job-name "${ETL_JOB_NAME}" &> /dev/null; then
        warning "Glue job ${ETL_JOB_NAME} already exists"
        return 0
    fi

    # First run crawler to get table names
    run_crawler_and_wait

    # Get source table names
    local source_table_events=$(aws glue get-tables --database-name "${GLUE_DATABASE_NAME}" \
        --query 'TableList[?contains(Name, `events`)].Name' --output text)
    local source_table_customers=$(aws glue get-tables --database-name "${GLUE_DATABASE_NAME}" \
        --query 'TableList[?contains(Name, `customers`)].Name' --output text)

    if [[ -z "${source_table_events}" ]] || [[ -z "${source_table_customers}" ]]; then
        warning "Source tables not found. Using default names."
        source_table_events="raw_events"
        source_table_customers="raw_customers"
    fi

    # Create ETL job configuration
    local job_config=$(cat << EOF
{
    "Name": "${ETL_JOB_NAME}",
    "Description": "Data lake ETL pipeline for multi-layer architecture",
    "Role": "${GLUE_ROLE_ARN}",
    "Command": {
        "Name": "glueetl",
        "ScriptLocation": "s3://${S3_BUCKET_NAME}/scripts/etl-script.py",
        "PythonVersion": "3"
    },
    "DefaultArguments": {
        "--job-bookmark-option": "job-bookmark-enable",
        "--enable-metrics": "",
        "--enable-continuous-cloudwatch-log": "true",
        "--DATABASE_NAME": "${GLUE_DATABASE_NAME}",
        "--S3_BUCKET_NAME": "${S3_BUCKET_NAME}",
        "--SOURCE_TABLE_EVENTS": "${source_table_events}",
        "--SOURCE_TABLE_CUSTOMERS": "${source_table_customers}"
    },
    "MaxRetries": 1,
    "Timeout": 60,
    "GlueVersion": "3.0",
    "MaxCapacity": 5,
    "WorkerType": "G.1X",
    "NumberOfWorkers": 5
}
EOF
)

    # Create ETL job
    echo "${job_config}" | aws glue create-job --cli-input-json file:///dev/stdin

    success "Glue ETL job created: ${ETL_JOB_NAME}"
}

run_crawler_and_wait() {
    info "Running crawler to discover data schema..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would run crawler: ${CRAWLER_NAME}"
        return 0
    fi

    # Start crawler
    aws glue start-crawler --name "${CRAWLER_NAME}"

    # Wait for crawler to complete
    local max_wait=1800  # 30 minutes
    local wait_time=0
    
    while [[ ${wait_time} -lt ${max_wait} ]]; do
        local crawler_state=$(aws glue get-crawler --name "${CRAWLER_NAME}" \
            --query 'Crawler.State' --output text)
        
        if [[ "${crawler_state}" == "READY" ]]; then
            success "Crawler completed successfully"
            return 0
        elif [[ "${crawler_state}" == "STOPPING" ]] || [[ "${crawler_state}" == "RUNNING" ]]; then
            info "Crawler state: ${crawler_state}. Waiting..."
            sleep 30
            wait_time=$((wait_time + 30))
        else
            error "Crawler failed with state: ${crawler_state}"
            return 1
        fi
    done

    error "Crawler timed out after ${max_wait} seconds"
    return 1
}

create_workflow() {
    info "Creating Glue workflow for pipeline orchestration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would create Glue workflow: ${WORKFLOW_NAME}"
        return 0
    fi

    # Check if workflow already exists
    if aws glue get-workflow --name "${WORKFLOW_NAME}" &> /dev/null; then
        warning "Glue workflow ${WORKFLOW_NAME} already exists"
        return 0
    fi

    # Create workflow
    aws glue create-workflow \
        --name "${WORKFLOW_NAME}" \
        --description "Data lake ingestion workflow with crawler and ETL"

    # Create trigger for crawler (scheduled daily at 6 AM)
    aws glue create-trigger \
        --name "${WORKFLOW_NAME}-crawler-trigger" \
        --type SCHEDULED \
        --schedule "cron(0 6 * * ? *)" \
        --workflow-name "${WORKFLOW_NAME}" \
        --actions "[{\"CrawlerName\":\"${CRAWLER_NAME}\"}]" \
        --start-on-creation

    # Create trigger for ETL job (depends on crawler completion)
    aws glue create-trigger \
        --name "${WORKFLOW_NAME}-etl-trigger" \
        --type CONDITIONAL \
        --predicate "{
            \"Conditions\": [{
                \"LogicalOperator\": \"EQUALS\",
                \"CrawlerName\": \"${CRAWLER_NAME}\",
                \"CrawlState\": \"SUCCEEDED\"
            }]
        }" \
        --workflow-name "${WORKFLOW_NAME}" \
        --actions "[{\"JobName\":\"${ETL_JOB_NAME}\"}]"

    success "Workflow created with automated triggers"
}

setup_monitoring() {
    info "Setting up CloudWatch monitoring and SNS alerts..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would setup monitoring and alerts"
        return 0
    fi

    # Create SNS topic
    local sns_topic_arn=$(aws sns create-topic --name "${SNS_TOPIC_NAME}" \
        --query 'TopicArn' --output text)

    # Subscribe email if provided
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
        aws sns subscribe \
            --topic-arn "${sns_topic_arn}" \
            --protocol email \
            --notification-endpoint "${EMAIL_ADDRESS}"
        info "Email subscription created for ${EMAIL_ADDRESS}"
    fi

    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "GlueJobFailure-${ETL_JOB_NAME}" \
        --alarm-description "Alert when Glue job fails" \
        --metric-name "glue.driver.aggregate.numFailedTasks" \
        --namespace "AWS/Glue" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${sns_topic_arn}" \
        --dimensions Name=JobName,Value="${ETL_JOB_NAME}" Name=JobRunId,Value=ALL

    aws cloudwatch put-metric-alarm \
        --alarm-name "GlueCrawlerFailure-${CRAWLER_NAME}" \
        --alarm-description "Alert when Glue crawler fails" \
        --metric-name "glue.driver.aggregate.numFailedTasks" \
        --namespace "AWS/Glue" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${sns_topic_arn}" \
        --dimensions Name=CrawlerName,Value="${CRAWLER_NAME}"

    success "Monitoring and alerts configured"
}

setup_athena() {
    info "Setting up Amazon Athena integration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would setup Athena workgroup"
        return 0
    fi

    # Create Athena workgroup
    aws athena create-work-group \
        --name "DataLakeWorkgroup-${RESOURCE_PREFIX}" \
        --description "Workgroup for data lake analytics" \
        --configuration "ResultConfiguration={OutputLocation=s3://${S3_BUCKET_NAME}/athena-results/}" \
        2>/dev/null || warning "Athena workgroup may already exist"

    # Create sample queries
    local temp_dir=$(mktemp -d)
    cat > "${temp_dir}/sample-queries.sql" << EOF
-- Query 1: Daily sales by category
SELECT 
    event_date,
    category,
    total_purchases,
    total_revenue,
    avg_order_value
FROM "${GLUE_DATABASE_NAME}"."gold_daily_sales"
WHERE event_date >= date('2024-01-01')
ORDER BY event_date DESC, total_revenue DESC;

-- Query 2: Customer behavior analysis
SELECT 
    age_group,
    country,
    AVG(total_spent) as avg_customer_lifetime_value,
    AVG(total_purchases) as avg_purchases_per_customer,
    COUNT(*) as customer_count
FROM "${GLUE_DATABASE_NAME}"."gold_customer_behavior"
GROUP BY age_group, country
ORDER BY avg_customer_lifetime_value DESC;

-- Query 3: Real-time event analysis
SELECT 
    event_type,
    category,
    COUNT(*) as event_count,
    SUM(amount) as total_amount
FROM "${GLUE_DATABASE_NAME}"."silver_events"
WHERE event_date = CURRENT_DATE
GROUP BY event_type, category
ORDER BY event_count DESC;
EOF

    aws s3 cp "${temp_dir}/sample-queries.sql" "s3://${S3_BUCKET_NAME}/queries/"
    rm -rf "${temp_dir}"

    success "Athena integration configured"
}

run_initial_etl() {
    info "Running initial ETL job..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would run initial ETL job"
        return 0
    fi

    # Start ETL job
    local job_run_id=$(aws glue start-job-run \
        --job-name "${ETL_JOB_NAME}" \
        --query 'JobRunId' --output text)

    info "ETL job started with run ID: ${job_run_id}"

    # Monitor job progress
    local max_wait=3600  # 1 hour
    local wait_time=0
    
    while [[ ${wait_time} -lt ${max_wait} ]]; do
        local job_state=$(aws glue get-job-run \
            --job-name "${ETL_JOB_NAME}" \
            --run-id "${job_run_id}" \
            --query 'JobRun.JobRunState' --output text)
        
        info "Job state: ${job_state}"
        
        if [[ "${job_state}" == "SUCCEEDED" ]]; then
            success "ETL job completed successfully"
            return 0
        elif [[ "${job_state}" == "FAILED" ]]; then
            error "ETL job failed"
            # Get error details
            aws glue get-job-run \
                --job-name "${ETL_JOB_NAME}" \
                --run-id "${job_run_id}" \
                --query 'JobRun.ErrorMessage' --output text
            return 1
        elif [[ "${job_state}" == "RUNNING" ]]; then
            sleep 30
            wait_time=$((wait_time + 30))
        else
            warning "Job in state: ${job_state}. Continuing to wait..."
            sleep 30
            wait_time=$((wait_time + 30))
        fi
    done

    error "ETL job timed out after ${max_wait} seconds"
    return 1
}

# =============================================================================
# Main Deployment Function
# =============================================================================

deploy_pipeline() {
    info "Starting AWS Data Lake Ingestion Pipeline deployment..."

    # Setup environment
    setup_environment

    # Create resources in order
    create_s3_bucket
    create_iam_role
    upload_sample_data
    create_glue_database
    create_glue_crawler
    create_etl_script
    create_glue_job
    create_workflow
    setup_monitoring
    setup_athena
    
    # Run initial processing
    if [[ "${DRY_RUN}" != "true" ]]; then
        run_initial_etl
    fi

    success "Pipeline deployment completed successfully!"
    
    # Display summary
    cat << EOF

=============================================================================
AWS Data Lake Ingestion Pipeline - Deployment Summary
=============================================================================

Resources Created:
- S3 Bucket: ${S3_BUCKET_NAME}
- Glue Database: ${GLUE_DATABASE_NAME}
- Glue Crawler: ${CRAWLER_NAME}
- Glue ETL Job: ${ETL_JOB_NAME}
- Glue Workflow: ${WORKFLOW_NAME}
- IAM Role: ${GLUE_ROLE_NAME}
- SNS Topic: ${SNS_TOPIC_NAME}
- Athena Workgroup: DataLakeWorkgroup-${RESOURCE_PREFIX}

Data Lake Structure:
- Bronze Layer: s3://${S3_BUCKET_NAME}/processed-data/bronze/
- Silver Layer: s3://${S3_BUCKET_NAME}/processed-data/silver/
- Gold Layer: s3://${S3_BUCKET_NAME}/processed-data/gold/

Next Steps:
1. Check the Data Catalog in AWS Glue Console
2. Query data using Amazon Athena workgroup: DataLakeWorkgroup-${RESOURCE_PREFIX}
3. Monitor pipeline execution in CloudWatch
4. Set up additional data sources as needed

Log file: ${LOG_FILE}
=============================================================================

EOF
}

# =============================================================================
# Command Line Argument Parsing
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -r|--region)
                export AWS_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                export RESOURCE_PREFIX="$2"
                shift 2
                ;;
            -e|--email)
                export EMAIL_ADDRESS="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    info "AWS Data Lake Ingestion Pipeline Deployment Script"
    info "================================================"
    
    parse_arguments "$@"
    
    if [[ "${VERBOSE}" == "true" ]]; then
        set -x
    fi
    
    check_prerequisites
    deploy_pipeline
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "Dry-run completed. No resources were created."
    fi
}

# Execute main function with all arguments
main "$@"