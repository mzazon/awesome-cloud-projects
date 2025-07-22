#!/bin/bash

# AWS Glue DataBrew Data Quality Monitoring - Deployment Script
# This script deploys the complete data quality monitoring solution
# including DataBrew datasets, profile jobs, rulesets, and monitoring

set -e  # Exit on any error

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

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode - no resources will be created"
fi

execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log "$description"
    eval "$cmd"
    return $?
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        error "AWS CLI version 2.x required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions
    log "Validating AWS permissions..."
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
        error "Unable to verify AWS identity. Please check your credentials."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Environment setup
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export resource names
    export DATABREW_ROLE_NAME="DataBrewServiceRole-${RANDOM_SUFFIX}"
    export DATASET_NAME="customer-data-${RANDOM_SUFFIX}"
    export PROFILE_JOB_NAME="customer-profile-job-${RANDOM_SUFFIX}"
    export RULESET_NAME="customer-quality-rules-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="databrew-results-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="data-quality-alerts-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="DataBrewQualityValidation-${RANDOM_SUFFIX}"
    
    # Store environment variables for cleanup
    cat > .env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
DATABREW_ROLE_NAME=$DATABREW_ROLE_NAME
DATASET_NAME=$DATASET_NAME
PROFILE_JOB_NAME=$PROFILE_JOB_NAME
RULESET_NAME=$RULESET_NAME
S3_BUCKET_NAME=$S3_BUCKET_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
EVENTBRIDGE_RULE_NAME=$EVENTBRIDGE_RULE_NAME
EOF
    
    success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "S3 Bucket: $S3_BUCKET_NAME"
}

# Create S3 bucket and sample data
create_s3_resources() {
    log "Creating S3 bucket and sample data..."
    
    # Create S3 bucket
    execute_command "aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}" \
        "Creating S3 bucket: ${S3_BUCKET_NAME}"
    
    # Create sample customer data
    cat > customer_data.csv << 'EOF'
customer_id,name,email,age,registration_date,account_balance
1,John Smith,john.smith@example.com,25,2023-01-15,1500.00
2,Jane Doe,jane.doe@example.com,32,2023-02-20,2300.50
3,Bob Johnson,,28,2023-03-10,750.25
4,Alice Brown,alice.brown@example.com,45,2023-04-05,3200.75
5,Charlie Wilson,charlie.wilson@example.com,-5,2023-05-12,1800.00
6,Diana Lee,diana.lee@example.com,67,invalid-date,2500.00
7,Frank Miller,frank.miller@example.com,33,2023-07-18,
8,Grace Taylor,grace.taylor@example.com,29,2023-08-25,1200.50
9,Henry Davis,henry.davis@example.com,41,2023-09-30,1750.25
10,Ivy Chen,ivy.chen@example.com,38,2023-10-15,2100.00
EOF
    
    # Upload sample data to S3
    execute_command "aws s3 cp customer_data.csv s3://${S3_BUCKET_NAME}/raw-data/" \
        "Uploading sample data to S3"
    
    success "S3 resources created successfully"
}

# Create IAM role for DataBrew
create_iam_role() {
    log "Creating IAM role for DataBrew..."
    
    # Create trust policy
    cat > databrew-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "databrew.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    execute_command "aws iam create-role \
        --role-name ${DATABREW_ROLE_NAME} \
        --assume-role-policy-document file://databrew-trust-policy.json" \
        "Creating IAM role: ${DATABREW_ROLE_NAME}"
    
    # Attach AWS managed policy
    execute_command "aws iam attach-role-policy \
        --role-name ${DATABREW_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueDataBrewServiceRole" \
        "Attaching DataBrew service policy"
    
    # Create custom S3 policy
    cat > databrew-s3-policy.json << EOF
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
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}"
        }
    ]
}
EOF
    
    # Attach custom S3 policy
    execute_command "aws iam put-role-policy \
        --role-name ${DATABREW_ROLE_NAME} \
        --policy-name S3Access \
        --policy-document file://databrew-s3-policy.json" \
        "Attaching S3 access policy"
    
    export DATABREW_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${DATABREW_ROLE_NAME}"
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    success "IAM role created: ${DATABREW_ROLE_ARN}"
}

# Create DataBrew dataset
create_databrew_dataset() {
    log "Creating DataBrew dataset..."
    
    execute_command "aws databrew create-dataset \
        --name ${DATASET_NAME} \
        --format CSV \
        --format-options '{\"Csv\": {\"Delimiter\": \",\"}}' \
        --input '{
            \"S3InputDefinition\": {
                \"Bucket\": \"${S3_BUCKET_NAME}\",
                \"Key\": \"raw-data/\"
            }
        }'" \
        "Creating DataBrew dataset: ${DATASET_NAME}"
    
    success "DataBrew dataset created successfully"
}

# Create data quality ruleset
create_quality_ruleset() {
    log "Creating data quality ruleset..."
    
    execute_command "aws databrew create-ruleset \
        --name ${RULESET_NAME} \
        --target-arn \"arn:aws:databrew:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/${DATASET_NAME}\" \
        --rules '[
            {
                \"Name\": \"customer_id_not_null\",
                \"CheckExpression\": \"COLUMN_COMPLETENESS(customer_id) > 0.95\",
                \"SubstitutionMap\": {},
                \"Disabled\": false
            },
            {
                \"Name\": \"email_format_valid\",
                \"CheckExpression\": \"COLUMN_DATA_TYPE(email) = STRING AND COLUMN_MATCHES_REGEX(email, \\\"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\\\.[a-zA-Z]{2,}$\\\") > 0.8\",
                \"SubstitutionMap\": {},
                \"Disabled\": false
            },
            {
                \"Name\": \"age_range_valid\",
                \"CheckExpression\": \"COLUMN_MIN(age) >= 0 AND COLUMN_MAX(age) <= 120\",
                \"SubstitutionMap\": {},
                \"Disabled\": false
            },
            {
                \"Name\": \"balance_positive\",
                \"CheckExpression\": \"COLUMN_MIN(account_balance) >= 0\",
                \"SubstitutionMap\": {},
                \"Disabled\": false
            },
            {
                \"Name\": \"registration_date_valid\",
                \"CheckExpression\": \"COLUMN_DATA_TYPE(registration_date) = DATE\",
                \"SubstitutionMap\": {},
                \"Disabled\": false
            }
        ]'" \
        "Creating data quality ruleset: ${RULESET_NAME}"
    
    success "Data quality ruleset created successfully"
}

# Create SNS topic for alerts
create_sns_topic() {
    log "Creating SNS topic for alerts..."
    
    execute_command "aws sns create-topic --name ${SNS_TOPIC_NAME}" \
        "Creating SNS topic: ${SNS_TOPIC_NAME}"
    
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
    
    # Prompt for email subscription
    read -p "Enter email address for data quality alerts (optional): " EMAIL_ADDRESS
    if [[ -n "$EMAIL_ADDRESS" ]]; then
        execute_command "aws sns subscribe \
            --topic-arn ${SNS_TOPIC_ARN} \
            --protocol email \
            --notification-endpoint ${EMAIL_ADDRESS}" \
            "Subscribing email to SNS topic"
        
        warning "Please check your email and confirm the subscription"
    fi
}

# Create profile job
create_profile_job() {
    log "Creating DataBrew profile job..."
    
    execute_command "aws databrew create-profile-job \
        --name ${PROFILE_JOB_NAME} \
        --dataset-name ${DATASET_NAME} \
        --role-arn ${DATABREW_ROLE_ARN} \
        --output-location '{
            \"Bucket\": \"${S3_BUCKET_NAME}\",
            \"Key\": \"profile-results/\"
        }' \
        --configuration '{
            \"DatasetStatisticsConfiguration\": {
                \"IncludedStatistics\": [\"ALL\"]
            },
            \"ProfileColumns\": [
                {
                    \"Name\": \"*\",
                    \"StatisticsConfiguration\": {
                        \"IncludedStatistics\": [\"ALL\"]
                    }
                }
            ]
        }' \
        --validation-configurations '[
            {
                \"RulesetArn\": \"arn:aws:databrew:${AWS_REGION}:${AWS_ACCOUNT_ID}:ruleset/${RULESET_NAME}\",
                \"ValidationMode\": \"CHECK_ALL\"
            }
        ]'" \
        "Creating profile job: ${PROFILE_JOB_NAME}"
    
    success "Profile job created successfully"
}

# Create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge rule for automation..."
    
    execute_command "aws events put-rule \
        --name ${EVENTBRIDGE_RULE_NAME} \
        --description \"Trigger actions on DataBrew validation results\" \
        --event-pattern '{
            \"source\": [\"aws.databrew\"],
            \"detail-type\": [\"DataBrew Ruleset Validation Result\"],
            \"detail\": {
                \"validationState\": [\"FAILED\"]
            }
        }'" \
        "Creating EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    
    # Add SNS topic as target
    execute_command "aws events put-targets \
        --rule ${EVENTBRIDGE_RULE_NAME} \
        --targets \"Id\"=\"1\",\"Arn\"=\"${SNS_TOPIC_ARN}\" \
        --input-transformer '{
            \"InputPathsMap\": {
                \"dataset\": \"$.detail.datasetName\",
                \"ruleset\": \"$.detail.rulesetName\",
                \"state\": \"$.detail.validationState\",
                \"report\": \"$.detail.validationReportLocation\"
            },
            \"InputTemplate\": \"Data quality validation FAILED for dataset: <dataset>, ruleset: <ruleset>. Status: <state>. Report: <report>\"
        }'" \
        "Adding SNS target to EventBridge rule"
    
    success "EventBridge rule configured successfully"
}

# Run profile job
run_profile_job() {
    log "Starting profile job execution..."
    
    execute_command "aws databrew start-job-run --name ${PROFILE_JOB_NAME}" \
        "Starting profile job: ${PROFILE_JOB_NAME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would monitor job execution"
        return 0
    fi
    
    # Get job run ID
    JOB_RUN_ID=$(aws databrew list-job-runs \
        --name ${PROFILE_JOB_NAME} \
        --query 'JobRuns[0].RunId' --output text)
    
    log "Job run ID: ${JOB_RUN_ID}"
    log "Monitoring job execution (this may take several minutes)..."
    
    # Monitor job status
    while true; do
        JOB_STATUS=$(aws databrew describe-job-run \
            --name ${PROFILE_JOB_NAME} \
            --run-id ${JOB_RUN_ID} \
            --query 'State' --output text)
        
        log "Job status: ${JOB_STATUS}"
        
        if [[ "${JOB_STATUS}" == "SUCCEEDED" ]]; then
            success "Profile job completed successfully"
            break
        elif [[ "${JOB_STATUS}" == "FAILED" ]]; then
            error "Profile job failed"
            
            # Get failure reason
            FAILURE_REASON=$(aws databrew describe-job-run \
                --name ${PROFILE_JOB_NAME} \
                --run-id ${JOB_RUN_ID} \
                --query 'ErrorMessage' --output text)
            
            if [[ "$FAILURE_REASON" != "None" ]]; then
                error "Failure reason: ${FAILURE_REASON}"
            fi
            break
        fi
        
        sleep 30
    done
}

# Display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "AWS Region: ${AWS_REGION}"
    echo "S3 Bucket: ${S3_BUCKET_NAME}"
    echo "DataBrew Dataset: ${DATASET_NAME}"
    echo "Profile Job: ${PROFILE_JOB_NAME}"
    echo "Quality Ruleset: ${RULESET_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo "EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "IAM Role: ${DATABREW_ROLE_ARN}"
    echo ""
    echo "Next Steps:"
    echo "1. Check S3 bucket ${S3_BUCKET_NAME} for profile results"
    echo "2. Monitor CloudWatch Events for data quality alerts"
    echo "3. Review validation reports in S3"
    echo "4. Set up additional email subscriptions if needed"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Cleanup temporary files
cleanup_temp_files() {
    rm -f customer_data.csv
    rm -f databrew-trust-policy.json
    rm -f databrew-s3-policy.json
}

# Main execution
main() {
    log "Starting AWS Glue DataBrew Data Quality Monitoring deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_resources
    create_iam_role
    create_databrew_dataset
    create_quality_ruleset
    create_sns_topic
    create_profile_job
    create_eventbridge_rule
    run_profile_job
    
    # Cleanup and summary
    cleanup_temp_files
    display_summary
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Run ./destroy.sh to clean up partial resources."; exit 1' INT TERM

# Run main function
main "$@"