#!/bin/bash

# AWS ETL Pipelines with Glue and Data Catalog Management - Deployment Script
# This script deploys the complete ETL pipeline infrastructure including
# S3 buckets, IAM roles, Glue database, crawlers, and ETL jobs

set -e  # Exit on any error

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version (minimum v2)
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
    if [ "$AWS_CLI_VERSION" -lt 2 ]; then
        error "AWS CLI version 2 or higher is required. Current version: $(aws --version)"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    log "Verifying AWS permissions..."
    aws iam get-user &> /dev/null || aws sts get-caller-identity &> /dev/null
    if [ $? -ne 0 ]; then
        error "Unable to verify AWS credentials. Please check your configuration."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        warning "AWS region not set. Using us-east-1 as default."
        export AWS_REGION="us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export GLUE_DATABASE_NAME="analytics-database-${RANDOM_SUFFIX}"
    export S3_RAW_BUCKET="raw-data-${RANDOM_SUFFIX}"
    export S3_PROCESSED_BUCKET="processed-data-${RANDOM_SUFFIX}"
    export GLUE_ROLE_NAME="GlueServiceRole-${RANDOM_SUFFIX}"
    export CRAWLER_NAME="data-discovery-crawler-${RANDOM_SUFFIX}"
    export PROCESSED_CRAWLER_NAME="processed-data-crawler-${RANDOM_SUFFIX}"
    export JOB_NAME="etl-transformation-job-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
GLUE_DATABASE_NAME=${GLUE_DATABASE_NAME}
S3_RAW_BUCKET=${S3_RAW_BUCKET}
S3_PROCESSED_BUCKET=${S3_PROCESSED_BUCKET}
GLUE_ROLE_NAME=${GLUE_ROLE_NAME}
CRAWLER_NAME=${CRAWLER_NAME}
PROCESSED_CRAWLER_NAME=${PROCESSED_CRAWLER_NAME}
JOB_NAME=${JOB_NAME}
EOF
    
    success "Environment variables configured"
    log "Database: ${GLUE_DATABASE_NAME}"
    log "Raw bucket: ${S3_RAW_BUCKET}"
    log "Processed bucket: ${S3_PROCESSED_BUCKET}"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create bucket for raw incoming data
    if aws s3 ls "s3://${S3_RAW_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3 mb "s3://${S3_RAW_BUCKET}" --region "${AWS_REGION}"
        success "Raw data bucket created: s3://${S3_RAW_BUCKET}"
    else
        warning "Raw data bucket already exists: s3://${S3_RAW_BUCKET}"
    fi
    
    # Create bucket for processed/transformed data
    if aws s3 ls "s3://${S3_PROCESSED_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3 mb "s3://${S3_PROCESSED_BUCKET}" --region "${AWS_REGION}"
        success "Processed data bucket created: s3://${S3_PROCESSED_BUCKET}"
    else
        warning "Processed data bucket already exists: s3://${S3_PROCESSED_BUCKET}"
    fi
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM service role for AWS Glue..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${GLUE_ROLE_NAME} already exists"
        return 0
    fi
    
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
    
    # Create the IAM role
    aws iam create-role \
        --role-name "${GLUE_ROLE_NAME}" \
        --assume-role-policy-document file://glue-trust-policy.json
    
    # Attach AWS managed policy for Glue service
    aws iam attach-role-policy \
        --role-name "${GLUE_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
    
    # Create custom policy for S3 access
    cat > glue-s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_RAW_BUCKET}/*",
        "arn:aws:s3:::${S3_PROCESSED_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_RAW_BUCKET}",
        "arn:aws:s3:::${S3_PROCESSED_BUCKET}"
      ]
    }
  ]
}
EOF
    
    # Attach custom S3 policy
    aws iam put-role-policy \
        --role-name "${GLUE_ROLE_NAME}" \
        --policy-name GlueS3Access \
        --policy-document file://glue-s3-policy.json
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    success "IAM role created: ${GLUE_ROLE_NAME}"
}

# Function to create Glue database
create_glue_database() {
    log "Creating Glue database..."
    
    # Check if database already exists
    if aws glue get-database --name "${GLUE_DATABASE_NAME}" &> /dev/null; then
        warning "Glue database ${GLUE_DATABASE_NAME} already exists"
        return 0
    fi
    
    # Create Glue database
    aws glue create-database \
        --database-input "Name=${GLUE_DATABASE_NAME},Description=Analytics database for ETL pipeline"
    
    success "Glue database created: ${GLUE_DATABASE_NAME}"
}

# Function to upload sample data
upload_sample_data() {
    log "Creating and uploading sample data..."
    
    # Create sample CSV data
    cat > sample-sales.csv << EOF
order_id,customer_id,product_name,quantity,price,order_date
1001,C001,Laptop,1,999.99,2024-01-15
1002,C002,Mouse,2,25.50,2024-01-15
1003,C001,Keyboard,1,75.00,2024-01-16
1004,C003,Monitor,1,299.99,2024-01-16
1005,C002,Headphones,1,149.99,2024-01-17
1006,C004,Tablet,1,599.99,2024-01-17
1007,C001,Webcam,1,89.99,2024-01-18
1008,C003,Speaker,2,129.99,2024-01-18
EOF
    
    # Create sample JSON data
    cat > sample-customers.json << EOF
{"customer_id": "C001", "name": "John Smith", "email": "john@email.com", "region": "North"}
{"customer_id": "C002", "name": "Jane Doe", "email": "jane@email.com", "region": "South"}
{"customer_id": "C003", "name": "Bob Johnson", "email": "bob@email.com", "region": "East"}
{"customer_id": "C004", "name": "Alice Brown", "email": "alice@email.com", "region": "West"}
EOF
    
    # Upload data to S3
    aws s3 cp sample-sales.csv "s3://${S3_RAW_BUCKET}/sales/"
    aws s3 cp sample-customers.json "s3://${S3_RAW_BUCKET}/customers/"
    
    success "Sample data uploaded to S3"
}

# Function to create and run crawler
create_crawler() {
    log "Creating Glue crawler for data discovery..."
    
    # Get role ARN
    GLUE_ROLE_ARN=$(aws iam get-role --role-name "${GLUE_ROLE_NAME}" --query Role.Arn --output text)
    
    # Check if crawler already exists
    if aws glue get-crawler --name "${CRAWLER_NAME}" &> /dev/null; then
        warning "Crawler ${CRAWLER_NAME} already exists"
    else
        # Create Glue crawler
        aws glue create-crawler \
            --name "${CRAWLER_NAME}" \
            --role "${GLUE_ROLE_ARN}" \
            --database-name "${GLUE_DATABASE_NAME}" \
            --targets "S3Targets=[{Path=s3://${S3_RAW_BUCKET}/}]" \
            --description "Crawler to discover raw data schemas"
        
        success "Glue crawler created: ${CRAWLER_NAME}"
    fi
    
    # Start the crawler
    log "Starting crawler..."
    aws glue start-crawler --name "${CRAWLER_NAME}"
    
    # Wait for crawler to complete
    log "Waiting for crawler to complete... This may take 2-3 minutes"
    while true; do
        CRAWLER_STATE=$(aws glue get-crawler \
            --name "${CRAWLER_NAME}" \
            --query Crawler.State --output text)
        
        if [ "$CRAWLER_STATE" = "READY" ]; then
            success "Crawler completed successfully"
            break
        elif [ "$CRAWLER_STATE" = "STOPPING" ] || [ "$CRAWLER_STATE" = "RUNNING" ]; then
            log "Crawler status: $CRAWLER_STATE - waiting..."
            sleep 30
        else
            error "Crawler failed with state: $CRAWLER_STATE"
            exit 1
        fi
    done
    
    # List discovered tables
    log "Discovered tables:"
    aws glue get-tables \
        --database-name "${GLUE_DATABASE_NAME}" \
        --query 'TableList[].Name' --output table
}

# Function to create ETL job
create_etl_job() {
    log "Creating ETL job script..."
    
    # Create ETL job script
    cat > etl-script.py << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'OUTPUT_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read sales data from catalog
    sales_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database = args['DATABASE_NAME'],
        table_name = "sales"
    )
    
    # Read customer data from catalog
    customers_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database = args['DATABASE_NAME'],
        table_name = "customers"
    )
    
    # Convert to DataFrames for joins
    sales_df = sales_dynamic_frame.toDF()
    customers_df = customers_dynamic_frame.toDF()
    
    # Join sales with customer data
    enriched_sales = sales_df.join(customers_df, "customer_id", "left")
    
    # Calculate total amount per order
    from pyspark.sql.functions import col
    enriched_sales = enriched_sales.withColumn("total_amount", 
                                             col("quantity") * col("price"))
    
    # Convert back to DynamicFrame
    enriched_dynamic_frame = DynamicFrame.fromDF(enriched_sales, glueContext, "enriched_sales")
    
    # Write to S3 in Parquet format
    glueContext.write_dynamic_frame.from_options(
        frame = enriched_dynamic_frame,
        connection_type = "s3",
        connection_options = {"path": f"s3://{args['OUTPUT_BUCKET']}/enriched-sales/"},
        format = "parquet"
    )
    
    print("ETL job completed successfully")
    
except Exception as e:
    print(f"ETL job failed with error: {str(e)}")
    raise e

job.commit()
EOF
    
    # Upload script to S3
    aws s3 cp etl-script.py "s3://${S3_PROCESSED_BUCKET}/scripts/"
    
    log "Creating Glue ETL job..."
    
    # Get role ARN
    GLUE_ROLE_ARN=$(aws iam get-role --role-name "${GLUE_ROLE_NAME}" --query Role.Arn --output text)
    
    # Check if job already exists
    if aws glue get-job --job-name "${JOB_NAME}" &> /dev/null; then
        warning "ETL job ${JOB_NAME} already exists"
    else
        # Create Glue ETL job
        aws glue create-job \
            --name "${JOB_NAME}" \
            --role "${GLUE_ROLE_ARN}" \
            --command "{
                \"Name\": \"glueetl\",
                \"ScriptLocation\": \"s3://${S3_PROCESSED_BUCKET}/scripts/etl-script.py\"
            }" \
            --default-arguments "{
                \"--job-language\": \"python\",
                \"--DATABASE_NAME\": \"${GLUE_DATABASE_NAME}\",
                \"--OUTPUT_BUCKET\": \"${S3_PROCESSED_BUCKET}\"
            }" \
            --max-retries 1 \
            --timeout 60 \
            --glue-version "4.0"
        
        success "ETL job created: ${JOB_NAME}"
    fi
    
    # Start the ETL job
    log "Starting ETL job..."
    JOB_RUN_ID=$(aws glue start-job-run \
        --job-name "${JOB_NAME}" \
        --query JobRunId --output text)
    
    log "Job run ID: ${JOB_RUN_ID}"
    log "Job is processing... This may take 3-5 minutes"
    
    # Wait for job completion
    log "Monitoring job execution..."
    while true; do
        JOB_STATE=$(aws glue get-job-run \
            --job-name "${JOB_NAME}" \
            --run-id "${JOB_RUN_ID}" \
            --query JobRun.JobRunState --output text)
        
        if [ "$JOB_STATE" = "SUCCEEDED" ]; then
            success "ETL job completed successfully"
            break
        elif [ "$JOB_STATE" = "RUNNING" ]; then
            log "Job status: $JOB_STATE - waiting..."
            sleep 30
        elif [ "$JOB_STATE" = "FAILED" ]; then
            error "ETL job failed"
            aws glue get-job-run \
                --job-name "${JOB_NAME}" \
                --run-id "${JOB_RUN_ID}" \
                --query JobRun.ErrorMessage --output text
            exit 1
        else
            log "Job status: $JOB_STATE - continuing to monitor..."
            sleep 30
        fi
    done
    
    # Verify output data
    log "Verifying transformed data..."
    aws s3 ls "s3://${S3_PROCESSED_BUCKET}/enriched-sales/" --recursive
}

# Function to create processed data crawler
create_processed_crawler() {
    log "Creating crawler for processed data..."
    
    # Get role ARN
    GLUE_ROLE_ARN=$(aws iam get-role --role-name "${GLUE_ROLE_NAME}" --query Role.Arn --output text)
    
    # Check if crawler already exists
    if aws glue get-crawler --name "${PROCESSED_CRAWLER_NAME}" &> /dev/null; then
        warning "Processed data crawler ${PROCESSED_CRAWLER_NAME} already exists"
    else
        # Create crawler for processed data
        aws glue create-crawler \
            --name "${PROCESSED_CRAWLER_NAME}" \
            --role "${GLUE_ROLE_ARN}" \
            --database-name "${GLUE_DATABASE_NAME}" \
            --targets "S3Targets=[{Path=s3://${S3_PROCESSED_BUCKET}/enriched-sales/}]" \
            --description "Crawler for processed/transformed data"
        
        success "Processed data crawler created: ${PROCESSED_CRAWLER_NAME}"
    fi
    
    # Run the crawler
    log "Starting processed data crawler..."
    aws glue start-crawler --name "${PROCESSED_CRAWLER_NAME}"
    
    # Wait for completion
    log "Crawling processed data..."
    sleep 60
    
    # Wait for crawler to complete
    while true; do
        CRAWLER_STATE=$(aws glue get-crawler \
            --name "${PROCESSED_CRAWLER_NAME}" \
            --query Crawler.State --output text)
        
        if [ "$CRAWLER_STATE" = "READY" ]; then
            success "Processed data crawler completed successfully"
            break
        elif [ "$CRAWLER_STATE" = "STOPPING" ] || [ "$CRAWLER_STATE" = "RUNNING" ]; then
            log "Crawler status: $CRAWLER_STATE - waiting..."
            sleep 30
        else
            warning "Crawler completed with state: $CRAWLER_STATE"
            break
        fi
    done
    
    # Verify new table creation
    log "Final table list:"
    aws glue get-tables \
        --database-name "${GLUE_DATABASE_NAME}" \
        --query 'TableList[].Name' --output table
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check S3 buckets
    if aws s3 ls "s3://${S3_RAW_BUCKET}" &> /dev/null && aws s3 ls "s3://${S3_PROCESSED_BUCKET}" &> /dev/null; then
        success "S3 buckets are accessible"
    else
        error "S3 buckets validation failed"
        exit 1
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" &> /dev/null; then
        success "IAM role exists"
    else
        error "IAM role validation failed"
        exit 1
    fi
    
    # Check Glue database
    if aws glue get-database --name "${GLUE_DATABASE_NAME}" &> /dev/null; then
        success "Glue database exists"
    else
        error "Glue database validation failed"
        exit 1
    fi
    
    # Check crawlers
    if aws glue get-crawler --name "${CRAWLER_NAME}" &> /dev/null && \
       aws glue get-crawler --name "${PROCESSED_CRAWLER_NAME}" &> /dev/null; then
        success "Crawlers exist"
    else
        error "Crawlers validation failed"
        exit 1
    fi
    
    # Check ETL job
    if aws glue get-job --job-name "${JOB_NAME}" &> /dev/null; then
        success "ETL job exists"
    else
        error "ETL job validation failed"
        exit 1
    fi
    
    success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "  DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo ""
    echo "Resources Created:"
    echo "  • S3 Raw Data Bucket: ${S3_RAW_BUCKET}"
    echo "  • S3 Processed Data Bucket: ${S3_PROCESSED_BUCKET}"
    echo "  • IAM Role: ${GLUE_ROLE_NAME}"
    echo "  • Glue Database: ${GLUE_DATABASE_NAME}"
    echo "  • Raw Data Crawler: ${CRAWLER_NAME}"
    echo "  • Processed Data Crawler: ${PROCESSED_CRAWLER_NAME}"
    echo "  • ETL Job: ${JOB_NAME}"
    echo ""
    echo "Next Steps:"
    echo "  1. View tables in AWS Glue Console"
    echo "  2. Query data using Amazon Athena"
    echo "  3. Create visualizations in QuickSight"
    echo ""
    echo "Cost Monitoring:"
    echo "  • Monitor Glue DPU usage in CloudWatch"
    echo "  • Review S3 storage costs"
    echo "  • Use AWS Cost Explorer for detailed analysis"
    echo ""
    echo "Cleanup:"
    echo "  • Run ./destroy.sh to remove all resources"
    echo ""
    echo "Environment file saved as .env for cleanup script"
    echo "=========================================="
}

# Cleanup function for temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f glue-trust-policy.json glue-s3-policy.json etl-script.py sample-sales.csv sample-customers.json
}

# Main execution
main() {
    echo "=========================================="
    echo "  AWS ETL Pipelines Deployment Script"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_role
    create_glue_database
    upload_sample_data
    create_crawler
    create_etl_job
    create_processed_crawler
    validate_deployment
    cleanup_temp_files
    display_summary
}

# Execute main function
main "$@"