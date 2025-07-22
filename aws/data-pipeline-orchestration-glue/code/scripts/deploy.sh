#!/bin/bash

# AWS Glue Workflows Data Pipeline Orchestration - Deployment Script
# This script deploys the complete AWS Glue Workflows infrastructure
# for data pipeline orchestration as described in the recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Cleanup function for script interruption
cleanup() {
    log_warning "Deployment script interrupted. Cleaning up..."
    exit 1
}

# Trap cleanup function
trap cleanup SIGINT SIGTERM

# Function to check if a command exists
check_command() {
    local command="$1"
    if ! command -v "$command" &> /dev/null; then
        log_error "Command '$command' not found. Please install it and try again."
        exit 1
    fi
}

# Function to check AWS CLI configuration
check_aws_cli() {
    log_info "Checking AWS CLI configuration..."
    
    # Check if AWS CLI is installed
    check_command "aws"
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        log_error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Get account and region information
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region is not configured. Please set a default region."
        exit 1
    fi
    
    log_success "AWS CLI configured - Account: ${AWS_ACCOUNT_ID}, Region: ${AWS_REGION}"
}

# Function to check IAM permissions
check_permissions() {
    log_info "Checking IAM permissions..."
    
    local required_permissions=(
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "iam:PutRolePolicy"
        "iam:PassRole"
        "glue:CreateDatabase"
        "glue:CreateCrawler"
        "glue:CreateJob"
        "glue:CreateWorkflow"
        "glue:CreateTrigger"
        "s3:CreateBucket"
        "s3:PutObject"
        "s3:GetObject"
        "s3:ListBucket"
        "secretsmanager:GetRandomPassword"
    )
    
    log_info "Required permissions: ${required_permissions[*]}"
    log_warning "This script assumes you have the necessary permissions. Please verify manually if needed."
}

# Function to generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix for resource names
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export WORKFLOW_NAME="data-pipeline-workflow-${RANDOM_SUFFIX}"
    export S3_BUCKET_RAW="raw-data-${RANDOM_SUFFIX}"
    export S3_BUCKET_PROCESSED="processed-data-${RANDOM_SUFFIX}"
    export GLUE_ROLE_NAME="GlueWorkflowRole-${RANDOM_SUFFIX}"
    export DATABASE_NAME="workflow_database_${RANDOM_SUFFIX}"
    export SOURCE_CRAWLER_NAME="source-crawler-${RANDOM_SUFFIX}"
    export TARGET_CRAWLER_NAME="target-crawler-${RANDOM_SUFFIX}"
    export ETL_JOB_NAME="data-processing-job-${RANDOM_SUFFIX}"
    export SCHEDULE_TRIGGER_NAME="schedule-trigger-${RANDOM_SUFFIX}"
    export CRAWLER_SUCCESS_TRIGGER_NAME="crawler-success-trigger-${RANDOM_SUFFIX}"
    export JOB_SUCCESS_TRIGGER_NAME="job-success-trigger-${RANDOM_SUFFIX}"
    
    log_success "Generated resource names with suffix: ${RANDOM_SUFFIX}"
}

# Function to save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
# Deployment State File
# Generated on: $(date)
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
AWS_REGION=${AWS_REGION}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
WORKFLOW_NAME=${WORKFLOW_NAME}
S3_BUCKET_RAW=${S3_BUCKET_RAW}
S3_BUCKET_PROCESSED=${S3_BUCKET_PROCESSED}
GLUE_ROLE_NAME=${GLUE_ROLE_NAME}
DATABASE_NAME=${DATABASE_NAME}
SOURCE_CRAWLER_NAME=${SOURCE_CRAWLER_NAME}
TARGET_CRAWLER_NAME=${TARGET_CRAWLER_NAME}
ETL_JOB_NAME=${ETL_JOB_NAME}
SCHEDULE_TRIGGER_NAME=${SCHEDULE_TRIGGER_NAME}
CRAWLER_SUCCESS_TRIGGER_NAME=${CRAWLER_SUCCESS_TRIGGER_NAME}
JOB_SUCCESS_TRIGGER_NAME=${JOB_SUCCESS_TRIGGER_NAME}
GLUE_ROLE_ARN=${GLUE_ROLE_ARN}
EOF
    log_success "Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"
}

# Function to create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create raw data bucket
    if aws s3api head-bucket --bucket "${S3_BUCKET_RAW}" 2>/dev/null; then
        log_warning "S3 bucket ${S3_BUCKET_RAW} already exists"
    else
        aws s3 mb "s3://${S3_BUCKET_RAW}" --region "${AWS_REGION}"
        log_success "Created S3 bucket: ${S3_BUCKET_RAW}"
    fi
    
    # Create processed data bucket
    if aws s3api head-bucket --bucket "${S3_BUCKET_PROCESSED}" 2>/dev/null; then
        log_warning "S3 bucket ${S3_BUCKET_PROCESSED} already exists"
    else
        aws s3 mb "s3://${S3_BUCKET_PROCESSED}" --region "${AWS_REGION}"
        log_success "Created S3 bucket: ${S3_BUCKET_PROCESSED}"
    fi
    
    # Create and upload sample data
    log_info "Creating sample data..."
    cat > "${SCRIPT_DIR}/sample-data.csv" << 'EOF'
customer_id,name,email,purchase_amount,purchase_date
1,John Doe,john@example.com,150.00,2024-01-15
2,Jane Smith,jane@example.com,200.00,2024-01-16
3,Bob Johnson,bob@example.com,75.00,2024-01-17
4,Alice Brown,alice@example.com,300.00,2024-01-18
5,Charlie Wilson,charlie@example.com,125.00,2024-01-19
EOF
    
    aws s3 cp "${SCRIPT_DIR}/sample-data.csv" "s3://${S3_BUCKET_RAW}/input/"
    log_success "Uploaded sample data to S3"
    
    # Cleanup local sample data
    rm -f "${SCRIPT_DIR}/sample-data.csv"
}

# Function to create IAM role
create_iam_role() {
    log_info "Creating IAM role for Glue workflow..."
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/glue-trust-policy.json" << 'EOF'
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
    
    # Check if role already exists
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" 2>/dev/null; then
        log_warning "IAM role ${GLUE_ROLE_NAME} already exists"
    else
        # Create the IAM role
        aws iam create-role \
            --role-name "${GLUE_ROLE_NAME}" \
            --assume-role-policy-document file://"${SCRIPT_DIR}/glue-trust-policy.json"
        log_success "Created IAM role: ${GLUE_ROLE_NAME}"
    fi
    
    # Attach AWS managed policy
    aws iam attach-role-policy \
        --role-name "${GLUE_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
    
    # Create custom S3 access policy
    cat > "${SCRIPT_DIR}/s3-access-policy.json" << EOF
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
                "arn:aws:s3:::${S3_BUCKET_RAW}",
                "arn:aws:s3:::${S3_BUCKET_RAW}/*",
                "arn:aws:s3:::${S3_BUCKET_PROCESSED}",
                "arn:aws:s3:::${S3_BUCKET_PROCESSED}/*"
            ]
        }
    ]
}
EOF
    
    # Attach custom S3 policy
    aws iam put-role-policy \
        --role-name "${GLUE_ROLE_NAME}" \
        --policy-name S3AccessPolicy \
        --policy-document file://"${SCRIPT_DIR}/s3-access-policy.json"
    
    # Get role ARN
    export GLUE_ROLE_ARN=$(aws iam get-role \
        --role-name "${GLUE_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    log_success "IAM role configured with ARN: ${GLUE_ROLE_ARN}"
    
    # Wait for role to be available
    log_info "Waiting for IAM role to propagate..."
    sleep 10
    
    # Cleanup temporary files
    rm -f "${SCRIPT_DIR}/glue-trust-policy.json" "${SCRIPT_DIR}/s3-access-policy.json"
}

# Function to create Glue database
create_glue_database() {
    log_info "Creating Glue database..."
    
    # Check if database already exists
    if aws glue get-database --name "${DATABASE_NAME}" 2>/dev/null; then
        log_warning "Glue database ${DATABASE_NAME} already exists"
    else
        aws glue create-database \
            --database-input Name="${DATABASE_NAME}",Description="Database for workflow data catalog"
        log_success "Created Glue database: ${DATABASE_NAME}"
    fi
}

# Function to create Glue crawlers
create_glue_crawlers() {
    log_info "Creating Glue crawlers..."
    
    # Create source crawler
    if aws glue get-crawler --name "${SOURCE_CRAWLER_NAME}" 2>/dev/null; then
        log_warning "Source crawler ${SOURCE_CRAWLER_NAME} already exists"
    else
        aws glue create-crawler \
            --name "${SOURCE_CRAWLER_NAME}" \
            --role "${GLUE_ROLE_ARN}" \
            --database-name "${DATABASE_NAME}" \
            --targets "S3Targets=[{Path=s3://${S3_BUCKET_RAW}/input/}]" \
            --description "Crawler to discover source data schema"
        log_success "Created source crawler: ${SOURCE_CRAWLER_NAME}"
    fi
    
    # Create target crawler
    if aws glue get-crawler --name "${TARGET_CRAWLER_NAME}" 2>/dev/null; then
        log_warning "Target crawler ${TARGET_CRAWLER_NAME} already exists"
    else
        aws glue create-crawler \
            --name "${TARGET_CRAWLER_NAME}" \
            --role "${GLUE_ROLE_ARN}" \
            --database-name "${DATABASE_NAME}" \
            --targets "S3Targets=[{Path=s3://${S3_BUCKET_PROCESSED}/output/}]" \
            --description "Crawler to discover processed data schema"
        log_success "Created target crawler: ${TARGET_CRAWLER_NAME}"
    fi
}

# Function to create Glue ETL job
create_glue_job() {
    log_info "Creating Glue ETL job..."
    
    # Create ETL script
    cat > "${SCRIPT_DIR}/etl-script.py" << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'OUTPUT_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from the catalog
datasource0 = glueContext.create_dynamic_frame.from_catalog(
    database=args['DATABASE_NAME'],
    table_name="input"
)

# Apply transformations
mapped_data = ApplyMapping.apply(
    frame=datasource0,
    mappings=[
        ("customer_id", "string", "customer_id", "int"),
        ("name", "string", "customer_name", "string"),
        ("email", "string", "email", "string"),
        ("purchase_amount", "string", "purchase_amount", "double"),
        ("purchase_date", "string", "purchase_date", "string")
    ]
)

# Write to S3
glueContext.write_dynamic_frame.from_options(
    frame=mapped_data,
    connection_type="s3",
    connection_options={"path": f"s3://{args['OUTPUT_BUCKET']}/output/"},
    format="parquet"
)

job.commit()
EOF
    
    # Upload script to S3
    aws s3 cp "${SCRIPT_DIR}/etl-script.py" "s3://${S3_BUCKET_PROCESSED}/scripts/"
    log_success "Uploaded ETL script to S3"
    
    # Create Glue job
    if aws glue get-job --job-name "${ETL_JOB_NAME}" 2>/dev/null; then
        log_warning "Glue job ${ETL_JOB_NAME} already exists"
    else
        aws glue create-job \
            --name "${ETL_JOB_NAME}" \
            --role "${GLUE_ROLE_ARN}" \
            --command "Name=glueetl,ScriptLocation=s3://${S3_BUCKET_PROCESSED}/scripts/etl-script.py,PythonVersion=3" \
            --default-arguments "{\"--DATABASE_NAME\":\"${DATABASE_NAME}\",\"--OUTPUT_BUCKET\":\"${S3_BUCKET_PROCESSED}\"}" \
            --glue-version "4.0" \
            --max-retries 1 \
            --timeout 60 \
            --description "ETL job for data processing in workflow"
        log_success "Created Glue job: ${ETL_JOB_NAME}"
    fi
    
    # Cleanup local script
    rm -f "${SCRIPT_DIR}/etl-script.py"
}

# Function to create Glue workflow
create_glue_workflow() {
    log_info "Creating Glue workflow..."
    
    # Create workflow
    if aws glue get-workflow --name "${WORKFLOW_NAME}" 2>/dev/null; then
        log_warning "Glue workflow ${WORKFLOW_NAME} already exists"
    else
        aws glue create-workflow \
            --name "${WORKFLOW_NAME}" \
            --description "Data pipeline workflow orchestrating crawlers and ETL jobs" \
            --max-concurrent-runs 1 \
            --default-run-properties '{"environment":"production","pipeline_version":"1.0"}'
        log_success "Created Glue workflow: ${WORKFLOW_NAME}"
    fi
}

# Function to create Glue triggers
create_glue_triggers() {
    log_info "Creating Glue triggers..."
    
    # Create schedule trigger
    if aws glue get-trigger --name "${SCHEDULE_TRIGGER_NAME}" 2>/dev/null; then
        log_warning "Schedule trigger ${SCHEDULE_TRIGGER_NAME} already exists"
    else
        aws glue create-trigger \
            --name "${SCHEDULE_TRIGGER_NAME}" \
            --workflow-name "${WORKFLOW_NAME}" \
            --type SCHEDULED \
            --schedule "cron(0 2 * * ? *)" \
            --description "Daily trigger at 2 AM UTC" \
            --start-on-creation \
            --actions "Type=CRAWLER,CrawlerName=${SOURCE_CRAWLER_NAME}"
        log_success "Created schedule trigger: ${SCHEDULE_TRIGGER_NAME}"
    fi
    
    # Create crawler success trigger
    if aws glue get-trigger --name "${CRAWLER_SUCCESS_TRIGGER_NAME}" 2>/dev/null; then
        log_warning "Crawler success trigger ${CRAWLER_SUCCESS_TRIGGER_NAME} already exists"
    else
        aws glue create-trigger \
            --name "${CRAWLER_SUCCESS_TRIGGER_NAME}" \
            --workflow-name "${WORKFLOW_NAME}" \
            --type CONDITIONAL \
            --predicate "Logical=AND,Conditions=[{LogicalOperator=EQUALS,CrawlerName=${SOURCE_CRAWLER_NAME},CrawlState=SUCCEEDED}]" \
            --description "Trigger ETL job after successful crawler completion" \
            --start-on-creation \
            --actions "Type=JOB,JobName=${ETL_JOB_NAME}"
        log_success "Created crawler success trigger: ${CRAWLER_SUCCESS_TRIGGER_NAME}"
    fi
    
    # Create job success trigger
    if aws glue get-trigger --name "${JOB_SUCCESS_TRIGGER_NAME}" 2>/dev/null; then
        log_warning "Job success trigger ${JOB_SUCCESS_TRIGGER_NAME} already exists"
    else
        aws glue create-trigger \
            --name "${JOB_SUCCESS_TRIGGER_NAME}" \
            --workflow-name "${WORKFLOW_NAME}" \
            --type CONDITIONAL \
            --predicate "Logical=AND,Conditions=[{LogicalOperator=EQUALS,JobName=${ETL_JOB_NAME},State=SUCCEEDED}]" \
            --description "Trigger target crawler after successful job completion" \
            --start-on-creation \
            --actions "Type=CRAWLER,CrawlerName=${TARGET_CRAWLER_NAME}"
        log_success "Created job success trigger: ${JOB_SUCCESS_TRIGGER_NAME}"
    fi
}

# Function to start workflow for testing
start_workflow() {
    log_info "Starting workflow execution for validation..."
    
    # Start workflow
    local workflow_run_id=$(aws glue start-workflow-run \
        --name "${WORKFLOW_NAME}" \
        --query WorkflowRunId --output text)
    
    log_success "Started workflow with run ID: ${workflow_run_id}"
    log_info "Monitor workflow progress in the AWS Glue console or with: aws glue get-workflow-run --name ${WORKFLOW_NAME} --run-id ${workflow_run_id}"
}

# Function to display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    echo "Deployed Resources:"
    echo "  • Workflow Name: ${WORKFLOW_NAME}"
    echo "  • Raw Data S3 Bucket: ${S3_BUCKET_RAW}"
    echo "  • Processed Data S3 Bucket: ${S3_BUCKET_PROCESSED}"
    echo "  • IAM Role: ${GLUE_ROLE_NAME}"
    echo "  • Glue Database: ${DATABASE_NAME}"
    echo "  • Source Crawler: ${SOURCE_CRAWLER_NAME}"
    echo "  • Target Crawler: ${TARGET_CRAWLER_NAME}"
    echo "  • ETL Job: ${ETL_JOB_NAME}"
    echo "  • Schedule Trigger: ${SCHEDULE_TRIGGER_NAME}"
    echo "  • Crawler Success Trigger: ${CRAWLER_SUCCESS_TRIGGER_NAME}"
    echo "  • Job Success Trigger: ${JOB_SUCCESS_TRIGGER_NAME}"
    echo ""
    echo "AWS Console Links:"
    echo "  • Glue Console: https://console.aws.amazon.com/glue/home?region=${AWS_REGION}"
    echo "  • Workflow: https://console.aws.amazon.com/glue/home?region=${AWS_REGION}#etl:tab=workflows"
    echo "  • S3 Buckets: https://console.aws.amazon.com/s3/home?region=${AWS_REGION}"
    echo ""
    echo "Next Steps:"
    echo "  1. Monitor the workflow execution in the Glue console"
    echo "  2. Check CloudWatch logs for detailed execution information"
    echo "  3. Verify data processing results in the processed data bucket"
    echo "  4. Use the destroy.sh script to clean up resources when done"
    echo ""
    echo "Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"
    echo "Log file available at: ${LOG_FILE}"
}

# Main deployment function
main() {
    log_info "Starting AWS Glue Workflows deployment..."
    log_info "Script directory: ${SCRIPT_DIR}"
    log_info "Log file: ${LOG_FILE}"
    
    # Check prerequisites
    check_aws_cli
    check_permissions
    
    # Generate unique resource names
    generate_resource_names
    
    # Create resources
    create_s3_buckets
    create_iam_role
    create_glue_database
    create_glue_crawlers
    create_glue_job
    create_glue_workflow
    create_glue_triggers
    
    # Save deployment state
    save_deployment_state
    
    # Start workflow for testing
    start_workflow
    
    # Display summary
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"