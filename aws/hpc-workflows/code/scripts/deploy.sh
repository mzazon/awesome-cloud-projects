#!/bin/bash

# Fault-Tolerant HPC Workflows Deployment Script
# This script deploys the complete fault-tolerant HPC workflow infrastructure
# including Step Functions, Lambda functions, IAM roles, and monitoring

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="hpc-workflow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_DIR="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false
FORCE_DEPLOY=false

# Functions
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

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy fault-tolerant HPC workflows infrastructure

OPTIONS:
    -n, --dry-run           Show what would be deployed without actually deploying
    -f, --force            Force deployment even if resources exist
    -p, --project-name     Custom project name (default: hpc-workflow)
    -h, --help             Show this help message

EXAMPLES:
    $0                     # Deploy with default settings
    $0 --dry-run           # Show deployment plan without executing
    $0 --force             # Force deployment, overwriting existing resources
    $0 --project-name my-hpc   # Deploy with custom project name

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -p|--project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("jq" "zip")
    for tool in "${required_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

set_environment_variables() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not set, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="${PROJECT_NAME}-${RANDOM_SUFFIX}"
    export STATE_MACHINE_NAME="hpc-workflow-orchestrator-${RANDOM_SUFFIX}"
    export SPOT_FLEET_NAME="hpc-spot-fleet-${RANDOM_SUFFIX}"
    export BATCH_QUEUE_NAME="hpc-queue-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="hpc-checkpoints-${RANDOM_SUFFIX}-${AWS_ACCOUNT_ID}"
    export DDB_TABLE_NAME="hpc-workflow-state-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log_info "Project Name: $PROJECT_NAME"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
}

create_s3_bucket() {
    log_info "Creating S3 bucket for checkpoints..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create S3 bucket: $S3_BUCKET_NAME"
        return
    fi
    
    # Create bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${S3_BUCKET_NAME}
    else
        aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Create folder structure
    aws s3api put-object --bucket ${S3_BUCKET_NAME} --key checkpoints/
    aws s3api put-object --bucket ${S3_BUCKET_NAME} --key workflows/
    aws s3api put-object --bucket ${S3_BUCKET_NAME} --key results/
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${S3_BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    log_success "S3 bucket created: $S3_BUCKET_NAME"
}

create_dynamodb_table() {
    log_info "Creating DynamoDB table for workflow state..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create DynamoDB table: $DDB_TABLE_NAME"
        return
    fi
    
    aws dynamodb create-table \
        --table-name ${DDB_TABLE_NAME} \
        --attribute-definitions \
            AttributeName=WorkflowId,AttributeType=S \
            AttributeName=TaskId,AttributeType=S \
        --key-schema \
            AttributeName=WorkflowId,KeyType=HASH \
            AttributeName=TaskId,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=${PROJECT_NAME}
    
    # Wait for table to be active
    aws dynamodb wait table-exists --table-name ${DDB_TABLE_NAME}
    
    log_success "DynamoDB table created: $DDB_TABLE_NAME"
}

create_iam_roles() {
    log_info "Creating IAM roles..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create IAM roles for Step Functions and Lambda"
        return
    fi
    
    # Create Step Functions execution role
    cat > /tmp/stepfunctions-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "states.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    aws iam create-role \
        --role-name ${PROJECT_NAME}-stepfunctions-role \
        --assume-role-policy-document file:///tmp/stepfunctions-trust-policy.json
    
    # Create comprehensive policy for Step Functions
    cat > /tmp/stepfunctions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction",
                "batch:SubmitJob",
                "batch:DescribeJobs",
                "batch:TerminateJob",
                "ec2:DescribeSpotFleetRequests",
                "ec2:ModifySpotFleetRequest",
                "ec2:CancelSpotFleetRequests",
                "ec2:CreateSpotFleetRequest",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket",
                "cloudwatch:PutMetricData",
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name ${PROJECT_NAME}-stepfunctions-role \
        --policy-name StepFunctionsExecutionPolicy \
        --policy-document file:///tmp/stepfunctions-policy.json
    
    # Create Lambda execution role
    cat > /tmp/lambda-trust-policy.json << EOF
{
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
}
EOF
    
    aws iam create-role \
        --role-name ${PROJECT_NAME}-lambda-role \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json
    
    # Attach managed policies
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/AWSBatchFullAccess
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    # Wait for roles to be available
    sleep 10
    
    log_success "IAM roles created successfully"
}

deploy_lambda_functions() {
    log_info "Deploying Lambda functions..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would deploy Lambda functions from terraform/lambda_code/"
        return
    fi
    
    # Create temp directory for Lambda packages
    mkdir -p /tmp/lambda-packages
    
    # Package and deploy each Lambda function
    local functions=("spot_fleet_manager" "checkpoint_manager" "workflow_parser" "spot_interruption_handler")
    
    for func in "${functions[@]}"; do
        log_info "Deploying Lambda function: $func"
        
        # Copy source code
        cp "${CODE_DIR}/terraform/lambda_code/${func}.py" /tmp/lambda-packages/
        
        # Create deployment package
        cd /tmp/lambda-packages
        zip ${func}.zip ${func}.py
        
        # Deploy function
        aws lambda create-function \
            --function-name ${PROJECT_NAME}-${func//_/-} \
            --runtime python3.9 \
            --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role \
            --handler ${func}.lambda_handler \
            --zip-file fileb://${func}.zip \
            --timeout 300 \
            --memory-size 512 \
            --tags Project=${PROJECT_NAME}
        
        log_success "Lambda function deployed: ${PROJECT_NAME}-${func//_/-}"
    done
    
    cd "$SCRIPT_DIR"
}

create_step_functions_state_machine() {
    log_info "Creating Step Functions state machine..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create Step Functions state machine: $STATE_MACHINE_NAME"
        return
    fi
    
    # Create comprehensive Step Functions state machine definition
    cat > /tmp/stepfunctions-definition.json << EOF
{
  "Comment": "Fault-tolerant HPC workflow orchestrator with Spot Fleet management",
  "StartAt": "ParseWorkflow",
  "States": {
    "ParseWorkflow": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-workflow-parser",
      "ResultPath": "$.parsed_workflow",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "WorkflowFailed",
          "ResultPath": "$.error"
        }
      ],
      "Next": "InitializeResources"
    },
    "InitializeResources": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "CreateSpotFleet",
          "States": {
            "CreateSpotFleet": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-spot-fleet-manager",
              "Parameters": {
                "action": "create",
                "target_capacity": 4,
                "ami_id": "ami-0abcdef1234567890",
                "security_group_id": "sg-placeholder",
                "subnet_id": "subnet-placeholder",
                "fleet_role_arn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/aws-ec2-spot-fleet-tagging-role"
              },
              "ResultPath": "$.spot_fleet",
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 10,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "InitializeBatchQueue",
          "States": {
            "InitializeBatchQueue": {
              "Type": "Pass",
              "Parameters": {
                "queue_name": "${BATCH_QUEUE_NAME}",
                "status": "initialized"
              },
              "ResultPath": "$.batch_queue",
              "End": true
            }
          }
        }
      ],
      "ResultPath": "$.resources",
      "Next": "WorkflowCompleted"
    },
    "WorkflowCompleted": {
      "Type": "Pass",
      "Parameters": {
        "status": "completed",
        "completion_time.$": "$$.State.EnteredTime"
      },
      "End": true
    },
    "WorkflowFailed": {
      "Type": "Fail",
      "Cause": "Workflow execution failed"
    }
  }
}
EOF
    
    # Create the Step Functions state machine
    aws stepfunctions create-state-machine \
        --name ${STATE_MACHINE_NAME} \
        --definition file:///tmp/stepfunctions-definition.json \
        --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-stepfunctions-role \
        --type STANDARD \
        --tags Key=Project,Value=${PROJECT_NAME}
    
    log_success "Step Functions state machine created: $STATE_MACHINE_NAME"
}

setup_event_bridge() {
    log_info "Setting up EventBridge rules for Spot interruptions..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create EventBridge rules for Spot interruption handling"
        return
    fi
    
    # Create EventBridge rule for Spot interruption warnings
    aws events put-rule \
        --name ${PROJECT_NAME}-spot-interruption-warning \
        --event-pattern '{
          "source": ["aws.ec2"],
          "detail-type": ["EC2 Spot Instance Interruption Warning"],
          "detail": {
            "instance-action": ["terminate"]
          }
        }' \
        --description "Detect Spot instance interruption warnings"
    
    # Add Lambda as target for EventBridge rule
    aws events put-targets \
        --rule ${PROJECT_NAME}-spot-interruption-warning \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-spot-interruption-handler"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name ${PROJECT_NAME}-spot-interruption-handler \
        --statement-id allow-eventbridge \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-spot-interruption-warning
    
    log_success "EventBridge rules configured"
}

create_monitoring() {
    log_info "Setting up CloudWatch monitoring and alerting..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create CloudWatch dashboards and alarms"
        return
    fi
    
    # Create CloudWatch dashboard
    cat > /tmp/dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/StepFunctions", "ExecutionTime", "StateMachineArn", "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"],
                    [".", "ExecutionsFailed", ".", "."],
                    [".", "ExecutionsSucceeded", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "HPC Workflow Metrics"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name ${PROJECT_NAME}-monitoring \
        --dashboard-body file:///tmp/dashboard.json
    
    # Create SNS topic for alerts
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name ${PROJECT_NAME}-alerts \
        --query 'TopicArn' --output text)
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-workflow-failures" \
        --alarm-description "Alert when workflows fail" \
        --metric-name ExecutionsFailed \
        --namespace AWS/StepFunctions \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions Name=StateMachineArn,Value=arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME} \
        --evaluation-periods 1 \
        --alarm-actions ${SNS_TOPIC_ARN}
    
    log_success "Monitoring and alerting configured"
}

create_sample_workflow() {
    log_info "Creating sample workflow definition..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create sample workflow definition in S3"
        return
    fi
    
    # Create sample HPC workflow definition
    cat > /tmp/sample-workflow.json << EOF
{
    "name": "Molecular Dynamics Simulation",
    "description": "Multi-stage molecular dynamics workflow with checkpointing",
    "global_config": {
        "checkpoint_interval": 600,
        "max_retry_attempts": 3,
        "spot_strategy": "diversified"
    },
    "tasks": [
        {
            "id": "data-preprocessing",
            "name": "Data Preprocessing",
            "type": "batch",
            "container_image": "scientific-computing:preprocessing",
            "command": ["python", "/app/preprocess.py"],
            "vcpus": 2,
            "memory": 4096,
            "nodes": 1,
            "environment": {
                "INPUT_PATH": "/mnt/efs/raw_data",
                "OUTPUT_PATH": "/mnt/efs/processed_data"
            },
            "checkpoint_enabled": true,
            "spot_enabled": true
        }
    ]
}
EOF
    
    # Upload sample workflow to S3
    aws s3 cp /tmp/sample-workflow.json \
        s3://${S3_BUCKET_NAME}/workflows/molecular-dynamics-sample.json
    
    log_success "Sample workflow definition created"
}

save_deployment_info() {
    log_info "Saving deployment information..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would save deployment information to deployment-info.json"
        return
    fi
    
    cat > "${CODE_DIR}/deployment-info.json" << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project_name": "${PROJECT_NAME}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "resources": {
        "state_machine_name": "${STATE_MACHINE_NAME}",
        "s3_bucket_name": "${S3_BUCKET_NAME}",
        "dynamodb_table_name": "${DDB_TABLE_NAME}",
        "lambda_functions": [
            "${PROJECT_NAME}-spot-fleet-manager",
            "${PROJECT_NAME}-checkpoint-manager",
            "${PROJECT_NAME}-workflow-parser",
            "${PROJECT_NAME}-spot-interruption-handler"
        ],
        "iam_roles": [
            "${PROJECT_NAME}-stepfunctions-role",
            "${PROJECT_NAME}-lambda-role"
        ]
    }
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    rm -f /tmp/stepfunctions-trust-policy.json
    rm -f /tmp/stepfunctions-policy.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/stepfunctions-definition.json
    rm -f /tmp/dashboard.json
    rm -f /tmp/sample-workflow.json
    rm -rf /tmp/lambda-packages
    
    log_success "Temporary files cleaned up"
}

print_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "==== DEPLOYMENT SUMMARY ===="
    echo "Project Name: $PROJECT_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo
    echo "==== RESOURCES CREATED ===="
    echo "Step Functions State Machine: $STATE_MACHINE_NAME"
    echo "S3 Bucket: $S3_BUCKET_NAME"
    echo "DynamoDB Table: $DDB_TABLE_NAME"
    echo "Lambda Functions: 4 functions deployed"
    echo "IAM Roles: 2 roles created"
    echo "EventBridge Rules: 1 rule for Spot interruptions"
    echo "CloudWatch Dashboard: ${PROJECT_NAME}-monitoring"
    echo
    echo "==== NEXT STEPS ===="
    echo "1. Configure AWS Batch compute environment and job queue"
    echo "2. Create container images for your HPC applications"
    echo "3. Update the Step Functions state machine with your specific AMI and VPC settings"
    echo "4. Test workflow execution with sample workflow"
    echo
    echo "==== MONITORING ===="
    echo "CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${PROJECT_NAME}-monitoring"
    echo "Step Functions Console: https://console.aws.amazon.com/states/home?region=${AWS_REGION}#/statemachines"
    echo
    echo "==== CLEANUP ===="
    echo "To remove all resources: ./destroy.sh"
    echo
}

main() {
    log_info "Starting fault-tolerant HPC workflows deployment..."
    
    parse_arguments "$@"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN MODE: No resources will be created"
        echo
    fi
    
    check_prerequisites
    set_environment_variables
    
    create_s3_bucket
    create_dynamodb_table
    create_iam_roles
    deploy_lambda_functions
    create_step_functions_state_machine
    setup_event_bridge
    create_monitoring
    create_sample_workflow
    save_deployment_info
    cleanup_temp_files
    
    if [ "$DRY_RUN" = false ]; then
        print_summary
    else
        log_info "DRY-RUN completed - no resources were created"
    fi
}

# Run main function with all arguments
main "$@"