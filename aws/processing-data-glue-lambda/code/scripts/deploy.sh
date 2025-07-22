#!/bin/bash

# AWS Serverless ETL Pipeline Deployment Script
# Recipe: Processing Data with AWS Glue and Lambda
# Version: 1.0

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial deployment..."
    if [ "${CLEANUP_ON_ERROR:-true}" = "true" ]; then
        ./destroy.sh --force 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required tools
    for tool in jq zip; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    # Check AWS region
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            log_error "AWS region not set. Please set AWS_REGION environment variable or configure default region."
            exit 1
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Core AWS settings
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Resource names
    export BUCKET_NAME="serverless-etl-pipeline-${RANDOM_SUFFIX}"
    export GLUE_DATABASE="etl_database_${RANDOM_SUFFIX}"
    export GLUE_ROLE="GlueETLRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE="LambdaETLRole-${RANDOM_SUFFIX}"
    export JOB_NAME="etl_job_${RANDOM_SUFFIX}"
    export CRAWLER_NAME="etl_crawler_${RANDOM_SUFFIX}"
    export WORKFLOW_NAME="etl_workflow_${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="etl-orchestrator-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup
    cat > .env << EOF
BUCKET_NAME=${BUCKET_NAME}
GLUE_DATABASE=${GLUE_DATABASE}
GLUE_ROLE=${GLUE_ROLE}
LAMBDA_ROLE=${LAMBDA_ROLE}
JOB_NAME=${JOB_NAME}
CRAWLER_NAME=${CRAWLER_NAME}
WORKFLOW_NAME=${WORKFLOW_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log "Bucket: $BUCKET_NAME"
    log "Region: $AWS_REGION"
    log "Account: $AWS_ACCOUNT_ID"
}

# Create S3 bucket and structure
create_s3_resources() {
    log "Creating S3 bucket and directory structure..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warning "Bucket $BUCKET_NAME already exists"
    else
        # Create bucket with appropriate location constraint
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://${BUCKET_NAME}"
        else
            aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        # Enable server-side encryption
        aws s3api put-bucket-encryption \
            --bucket "$BUCKET_NAME" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }'
    fi
    
    # Create directory structure
    for dir in "raw-data" "processed-data" "scripts" "temp" "query-results"; do
        aws s3api put-object --bucket "$BUCKET_NAME" --key "${dir}/"
    done
    
    log_success "S3 bucket and directory structure created"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create Glue service role
    log "Creating Glue service role..."
    if aws iam get-role --role-name "$GLUE_ROLE" &>/dev/null; then
        log_warning "Glue role $GLUE_ROLE already exists"
    else
        aws iam create-role \
            --role-name "$GLUE_ROLE" \
            --assume-role-policy-document '{
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
            }' \
            --tags Key=Purpose,Value=ETLPipeline Key=Environment,Value=Demo
        
        # Attach AWS managed policy
        aws iam attach-role-policy \
            --role-name "$GLUE_ROLE" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
        
        # Wait for role to be available
        aws iam wait role-exists --role-name "$GLUE_ROLE"
    fi
    
    # Create custom S3 access policy for Glue
    GLUE_S3_POLICY_NAME="GlueS3AccessPolicy-${RANDOM_SUFFIX}"
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${GLUE_S3_POLICY_NAME}" &>/dev/null; then
        aws iam create-policy \
            --policy-name "$GLUE_S3_POLICY_NAME" \
            --policy-document '{
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
                            "arn:aws:s3:::'"$BUCKET_NAME"'",
                            "arn:aws:s3:::'"$BUCKET_NAME"'/*"
                        ]
                    }
                ]
            }'
        
        aws iam attach-role-policy \
            --role-name "$GLUE_ROLE" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${GLUE_S3_POLICY_NAME}"
    fi
    
    # Create Lambda service role
    log "Creating Lambda service role..."
    if aws iam get-role --role-name "$LAMBDA_ROLE" &>/dev/null; then
        log_warning "Lambda role $LAMBDA_ROLE already exists"
    else
        aws iam create-role \
            --role-name "$LAMBDA_ROLE" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "lambda.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' \
            --tags Key=Purpose,Value=ETLPipeline Key=Environment,Value=Demo
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Wait for role to be available
        aws iam wait role-exists --role-name "$LAMBDA_ROLE"
    fi
    
    # Create custom Lambda policy for Glue interactions
    LAMBDA_GLUE_POLICY_NAME="LambdaGlueAccessPolicy-${RANDOM_SUFFIX}"
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_GLUE_POLICY_NAME}" &>/dev/null; then
        aws iam create-policy \
            --policy-name "$LAMBDA_GLUE_POLICY_NAME" \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "glue:StartJobRun",
                            "glue:GetJobRun",
                            "glue:GetJobRuns",
                            "glue:StartCrawler",
                            "glue:GetCrawler",
                            "glue:StartWorkflowRun",
                            "s3:GetObject",
                            "s3:PutObject",
                            "s3:ListBucket"
                        ],
                        "Resource": "*"
                    }
                ]
            }'
        
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_GLUE_POLICY_NAME}"
    fi
    
    log_success "IAM roles created successfully"
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
}

# Create sample data
create_sample_data() {
    log "Creating and uploading sample data..."
    
    # Create sales data
    cat > sales_data.csv << 'EOF'
order_id,customer_id,product_id,quantity,price,order_date,region
1001,C001,P001,2,29.99,2024-01-15,North
1002,C002,P002,1,49.99,2024-01-15,South
1003,C003,P001,3,29.99,2024-01-16,East
1004,C001,P003,1,19.99,2024-01-16,North
1005,C004,P002,2,49.99,2024-01-17,West
1006,C005,P001,1,29.99,2024-01-17,South
1007,C002,P003,4,19.99,2024-01-18,East
1008,C006,P004,1,99.99,2024-01-18,North
1009,C003,P004,2,99.99,2024-01-19,West
1010,C007,P002,1,49.99,2024-01-19,South
EOF
    
    # Create customer data
    cat > customer_data.csv << 'EOF'
customer_id,name,email,registration_date,status
C001,John Smith,john@example.com,2023-01-01,active
C002,Jane Doe,jane@example.com,2023-02-15,active
C003,Bob Johnson,bob@example.com,2023-03-20,inactive
C004,Alice Wilson,alice@example.com,2023-04-10,active
C005,Charlie Brown,charlie@example.com,2023-05-05,active
C006,Diana Prince,diana@example.com,2023-06-12,active
C007,Eve Adams,eve@example.com,2023-07-22,active
EOF
    
    # Upload to S3
    aws s3 cp sales_data.csv "s3://${BUCKET_NAME}/raw-data/sales_data.csv"
    aws s3 cp customer_data.csv "s3://${BUCKET_NAME}/raw-data/customer_data.csv"
    
    log_success "Sample data uploaded to S3"
}

# Create Glue database and crawler
create_glue_resources() {
    log "Creating Glue database and crawler..."
    
    # Create database
    if aws glue get-database --name "$GLUE_DATABASE" &>/dev/null; then
        log_warning "Glue database $GLUE_DATABASE already exists"
    else
        aws glue create-database \
            --database-input "{\"Name\":\"${GLUE_DATABASE}\",\"Description\":\"ETL Pipeline Database\"}"
        log_success "Glue database created"
    fi
    
    # Create crawler
    if aws glue get-crawler --name "$CRAWLER_NAME" &>/dev/null; then
        log_warning "Glue crawler $CRAWLER_NAME already exists"
    else
        aws glue create-crawler \
            --name "$CRAWLER_NAME" \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${GLUE_ROLE}" \
            --database-name "$GLUE_DATABASE" \
            --targets "{
                \"S3Targets\": [
                    {
                        \"Path\": \"s3://${BUCKET_NAME}/raw-data/\"
                    }
                ]
            }" \
            --description "ETL Pipeline Data Crawler"
        log_success "Glue crawler created"
    fi
    
    # Start crawler
    log "Starting crawler to catalog data..."
    aws glue start-crawler --name "$CRAWLER_NAME" || true
    
    # Wait for crawler to complete
    log "Waiting for crawler to complete..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        CRAWLER_STATE=$(aws glue get-crawler --name "$CRAWLER_NAME" --query 'Crawler.State' --output text)
        if [ "$CRAWLER_STATE" = "READY" ]; then
            log_success "Crawler completed successfully"
            break
        elif [ "$CRAWLER_STATE" = "STOPPING" ] || [ "$CRAWLER_STATE" = "RUNNING" ]; then
            log "Crawler state: $CRAWLER_STATE"
            sleep 10
            ((attempt++))
        else
            log_error "Crawler failed with state: $CRAWLER_STATE"
            exit 1
        fi
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_error "Crawler did not complete within expected time"
        exit 1
    fi
}

# Create and upload Glue ETL script
create_glue_etl_script() {
    log "Creating Glue ETL script..."
    
    cat > glue_etl_script.py << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *

# Parse job arguments
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'database_name',
    'table_prefix',
    'output_path'
])

# Initialize contexts
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from Glue Data Catalog
sales_df = glueContext.create_dynamic_frame.from_catalog(
    database=args['database_name'],
    table_name=f"{args['table_prefix']}_sales_data_csv"
).toDF()

customer_df = glueContext.create_dynamic_frame.from_catalog(
    database=args['database_name'],
    table_name=f"{args['table_prefix']}_customer_data_csv"
).toDF()

# Data transformations
# 1. Convert price to numeric and calculate total
sales_df = sales_df.withColumn("price", F.col("price").cast("double"))
sales_df = sales_df.withColumn("total_amount", 
    F.col("quantity") * F.col("price"))

# 2. Convert order_date to proper date format
sales_df = sales_df.withColumn("order_date", 
    F.to_date(F.col("order_date"), "yyyy-MM-dd"))

# 3. Join sales with customer data
enriched_df = sales_df.join(customer_df, "customer_id", "inner")

# 4. Calculate aggregated metrics
daily_sales = enriched_df.groupBy("order_date", "region").agg(
    F.sum("total_amount").alias("daily_revenue"),
    F.count("order_id").alias("daily_orders"),
    F.countDistinct("customer_id").alias("unique_customers")
)

# 5. Calculate customer metrics
customer_metrics = enriched_df.groupBy("customer_id", "name", "status").agg(
    F.sum("total_amount").alias("total_spent"),
    F.count("order_id").alias("total_orders"),
    F.avg("total_amount").alias("avg_order_value")
)

# Write processed data to S3
# Convert back to DynamicFrame for writing
daily_sales_df = DynamicFrame.fromDF(daily_sales, glueContext, "daily_sales")
customer_metrics_df = DynamicFrame.fromDF(customer_metrics, glueContext, "customer_metrics")

# Write daily sales data
glueContext.write_dynamic_frame.from_options(
    frame=daily_sales_df,
    connection_type="s3",
    connection_options={
        "path": f"{args['output_path']}/daily_sales/",
        "partitionKeys": ["order_date"]
    },
    format="parquet"
)

# Write customer metrics
glueContext.write_dynamic_frame.from_options(
    frame=customer_metrics_df,
    connection_type="s3",
    connection_options={
        "path": f"{args['output_path']}/customer_metrics/"
    },
    format="parquet"
)

# Log processing statistics
print(f"Processed {sales_df.count()} sales records")
print(f"Processed {customer_df.count()} customer records")
print(f"Generated {daily_sales.count()} daily sales records")
print(f"Generated {customer_metrics.count()} customer metric records")

job.commit()
EOF
    
    # Upload script to S3
    aws s3 cp glue_etl_script.py "s3://${BUCKET_NAME}/scripts/glue_etl_script.py"
    
    log_success "Glue ETL script uploaded to S3"
}

# Create Glue job
create_glue_job() {
    log "Creating Glue ETL job..."
    
    if aws glue get-job --job-name "$JOB_NAME" &>/dev/null; then
        log_warning "Glue job $JOB_NAME already exists"
    else
        aws glue create-job \
            --name "$JOB_NAME" \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${GLUE_ROLE}" \
            --command "{
                \"Name\": \"glueetl\",
                \"ScriptLocation\": \"s3://${BUCKET_NAME}/scripts/glue_etl_script.py\",
                \"PythonVersion\": \"3\"
            }" \
            --default-arguments "{
                \"--database_name\": \"${GLUE_DATABASE}\",
                \"--table_prefix\": \"raw_data\",
                \"--output_path\": \"s3://${BUCKET_NAME}/processed-data\",
                \"--TempDir\": \"s3://${BUCKET_NAME}/temp/\",
                \"--enable-metrics\": \"\",
                \"--enable-continuous-cloudwatch-log\": \"true\",
                \"--job-language\": \"python\"
            }" \
            --max-retries 1 \
            --timeout 60 \
            --glue-version "4.0" \
            --worker-type "G.1X" \
            --number-of-workers 2 \
            --description "Serverless ETL Pipeline Job"
        
        log_success "Glue ETL job created"
    fi
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
glue_client = boto3.client('glue')
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to orchestrate ETL pipeline
    """
    try:
        # Extract configuration from event
        job_name = event.get('job_name')
        database_name = event.get('database_name')
        
        if not job_name:
            raise ValueError("job_name is required in event")
        
        # Start Glue job
        response = glue_client.start_job_run(
            JobName=job_name,
            Arguments={
                '--database_name': database_name,
                '--table_prefix': 'raw_data',
                '--output_path': event.get('output_path', 's3://default-bucket/processed-data')
            }
        )
        
        job_run_id = response['JobRunId']
        logger.info(f"Started Glue job {job_name} with run ID: {job_run_id}")
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'ETL pipeline initiated successfully',
                'job_name': job_name,
                'job_run_id': job_run_id,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in ETL pipeline: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }

def check_job_status(job_name, job_run_id):
    """
    Check the status of a Glue job run
    """
    try:
        response = glue_client.get_job_run(
            JobName=job_name,
            RunId=job_run_id
        )
        
        job_run = response['JobRun']
        status = job_run['JobRunState']
        
        return {
            'status': status,
            'started_on': job_run.get('StartedOn'),
            'completed_on': job_run.get('CompletedOn'),
            'execution_time': job_run.get('ExecutionTime'),
            'error_message': job_run.get('ErrorMessage')
        }
        
    except Exception as e:
        logger.error(f"Error checking job status: {str(e)}")
        return {'error': str(e)}
EOF
    
    # Create deployment package
    zip -q lambda_function.zip lambda_function.py
    
    # Create Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME already exists"
    else
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE}" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda_function.zip \
            --timeout 300 \
            --memory-size 256 \
            --description "ETL Pipeline Orchestrator" \
            --tags Purpose=ETLPipeline,Environment=Demo
        
        log_success "Lambda function created"
    fi
}

# Create Glue workflow
create_glue_workflow() {
    log "Creating Glue workflow..."
    
    if aws glue get-workflow --name "$WORKFLOW_NAME" &>/dev/null; then
        log_warning "Glue workflow $WORKFLOW_NAME already exists"
    else
        aws glue create-workflow \
            --name "$WORKFLOW_NAME" \
            --description "Serverless ETL Pipeline Workflow"
        
        # Create scheduled trigger
        aws glue create-trigger \
            --name "start-etl-trigger-${RANDOM_SUFFIX}" \
            --workflow-name "$WORKFLOW_NAME" \
            --type SCHEDULED \
            --schedule "cron(0 2 * * ? *)" \
            --actions "[{
                \"JobName\": \"${JOB_NAME}\"
            }]" \
            --description "Daily ETL trigger at 2 AM UTC"
        
        log_success "Glue workflow and trigger created"
    fi
}

# Test the pipeline
test_pipeline() {
    log "Testing the ETL pipeline..."
    
    # Test Lambda function
    PAYLOAD="{\"job_name\":\"${JOB_NAME}\",\"database_name\":\"${GLUE_DATABASE}\",\"output_path\":\"s3://${BUCKET_NAME}/processed-data\"}"
    
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$PAYLOAD" \
        response.json > /dev/null
    
    # Check response
    if [ -f response.json ]; then
        STATUS_CODE=$(jq -r '.statusCode' response.json 2>/dev/null || echo "error")
        if [ "$STATUS_CODE" = "200" ]; then
            JOB_RUN_ID=$(jq -r '.body' response.json | jq -r '.job_run_id' 2>/dev/null)
            log_success "Pipeline test initiated successfully. Job Run ID: $JOB_RUN_ID"
            
            # Monitor job briefly
            log "Monitoring job status for 2 minutes..."
            local monitor_attempts=4
            local attempt=0
            
            while [ $attempt -lt $monitor_attempts ]; do
                sleep 30
                JOB_STATUS=$(aws glue get-job-run \
                    --job-name "$JOB_NAME" \
                    --run-id "$JOB_RUN_ID" \
                    --query 'JobRun.JobRunState' --output text 2>/dev/null || echo "UNKNOWN")
                
                log "Job Status: $JOB_STATUS"
                
                if [ "$JOB_STATUS" = "SUCCEEDED" ]; then
                    log_success "ETL job completed successfully"
                    break
                elif [ "$JOB_STATUS" = "FAILED" ]; then
                    log_warning "ETL job failed. Check CloudWatch logs for details."
                    break
                fi
                
                ((attempt++))
            done
            
            if [ $attempt -eq $monitor_attempts ]; then
                log "Job is still running. Check AWS Glue console for status updates."
            fi
        else
            log_error "Pipeline test failed. Response: $(cat response.json)"
        fi
    else
        log_error "Failed to get response from Lambda function"
    fi
}

# Main deployment function
main() {
    log "Starting AWS Serverless ETL Pipeline deployment..."
    
    # Parse command line arguments
    SKIP_TEST=false
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-test)
                SKIP_TEST=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--skip-test] [--dry-run] [--help]"
                echo "  --skip-test: Skip pipeline testing"
                echo "  --dry-run: Show what would be deployed without actually deploying"
                echo "  --help: Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN MODE - No resources will be created"
        log "Would create the following resources:"
        log "- S3 bucket for data storage and scripts"
        log "- IAM roles for Glue and Lambda"
        log "- Glue database, crawler, and ETL job"
        log "- Lambda function for orchestration"
        log "- Glue workflow with scheduled trigger"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_s3_resources
    create_iam_roles
    create_sample_data
    create_glue_resources
    create_glue_etl_script
    create_glue_job
    create_lambda_function
    create_glue_workflow
    
    if [ "$SKIP_TEST" = "false" ]; then
        test_pipeline
    fi
    
    # Display deployment summary
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "S3 Bucket: $BUCKET_NAME"
    echo "Glue Database: $GLUE_DATABASE"
    echo "Glue Job: $JOB_NAME"
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "Glue Workflow: $WORKFLOW_NAME"
    echo "AWS Region: $AWS_REGION"
    echo
    echo "=== Next Steps ==="
    echo "1. Check AWS Glue console for job execution status"
    echo "2. View processed data in S3 bucket: s3://$BUCKET_NAME/processed-data/"
    echo "3. Monitor CloudWatch logs for detailed execution information"
    echo "4. Use Athena to query the processed data"
    echo
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
    
    # Clean up temporary files
    rm -f sales_data.csv customer_data.csv glue_etl_script.py
    rm -f lambda_function.py lambda_function.zip response.json
}

# Run main function
main "$@"