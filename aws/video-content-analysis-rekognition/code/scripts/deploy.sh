#!/bin/bash

# Video Content Analysis with AWS Elemental MediaAnalyzer - Deployment Script
# This script deploys the complete video content analysis infrastructure

set -e  # Exit on any error

# Color codes for output
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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is not installed or not in PATH"
        exit 1
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    info "Validating AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [ -z "$region" ]; then
        error "AWS region not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "AWS Account ID: $account_id"
    log "AWS Region: $region"
}

# Function to check required permissions
check_permissions() {
    info "Checking required AWS permissions..."
    
    # Test permissions for key services
    local services=("s3" "lambda" "iam" "stepfunctions" "dynamodb" "rekognition" "sns" "sqs" "cloudwatch")
    
    for service in "${services[@]}"; do
        case $service in
            "s3")
                if ! aws s3 ls &> /dev/null; then
                    error "Missing S3 permissions. Please ensure you have s3:* permissions."
                    exit 1
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --max-items 1 &> /dev/null; then
                    error "Missing Lambda permissions. Please ensure you have lambda:* permissions."
                    exit 1
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    error "Missing IAM permissions. Please ensure you have iam:* permissions."
                    exit 1
                fi
                ;;
            "stepfunctions")
                if ! aws stepfunctions list-state-machines --max-items 1 &> /dev/null; then
                    error "Missing Step Functions permissions. Please ensure you have states:* permissions."
                    exit 1
                fi
                ;;
            "dynamodb")
                if ! aws dynamodb list-tables --max-items 1 &> /dev/null; then
                    error "Missing DynamoDB permissions. Please ensure you have dynamodb:* permissions."
                    exit 1
                fi
                ;;
            "rekognition")
                if ! aws rekognition list-collections --max-results 1 &> /dev/null; then
                    error "Missing Rekognition permissions. Please ensure you have rekognition:* permissions."
                    exit 1
                fi
                ;;
            "sns")
                if ! aws sns list-topics --max-items 1 &> /dev/null; then
                    error "Missing SNS permissions. Please ensure you have sns:* permissions."
                    exit 1
                fi
                ;;
            "sqs")
                if ! aws sqs list-queues --max-items 1 &> /dev/null; then
                    error "Missing SQS permissions. Please ensure you have sqs:* permissions."
                    exit 1
                fi
                ;;
            "cloudwatch")
                if ! aws cloudwatch list-metrics --max-records 1 &> /dev/null; then
                    error "Missing CloudWatch permissions. Please ensure you have cloudwatch:* permissions."
                    exit 1
                fi
                ;;
        esac
    done
    
    log "All required permissions validated successfully"
}

# Function to generate unique resource names
generate_resource_names() {
    info "Generating unique resource names..."
    
    # Generate random suffix for unique resource names
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export resource names as environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export VIDEO_ANALYSIS_STACK="video-analysis-${RANDOM_SUFFIX}"
    export SOURCE_BUCKET="video-source-${RANDOM_SUFFIX}"
    export RESULTS_BUCKET="video-results-${RANDOM_SUFFIX}"
    export TEMP_BUCKET="video-temp-${RANDOM_SUFFIX}"
    export ANALYSIS_TABLE="video-analysis-results-${RANDOM_SUFFIX}"
    export SNS_TOPIC="video-analysis-notifications-${RANDOM_SUFFIX}"
    export SQS_QUEUE="video-analysis-queue-${RANDOM_SUFFIX}"
    
    log "Generated resource names:"
    log "  - Stack: $VIDEO_ANALYSIS_STACK"
    log "  - Source Bucket: $SOURCE_BUCKET"
    log "  - Results Bucket: $RESULTS_BUCKET"
    log "  - Temp Bucket: $TEMP_BUCKET"
    log "  - DynamoDB Table: $ANALYSIS_TABLE"
    log "  - SNS Topic: $SNS_TOPIC"
    log "  - SQS Queue: $SQS_QUEUE"
    
    # Save resource names to file for cleanup script
    cat > /tmp/video-analysis-resources.env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
VIDEO_ANALYSIS_STACK=$VIDEO_ANALYSIS_STACK
SOURCE_BUCKET=$SOURCE_BUCKET
RESULTS_BUCKET=$RESULTS_BUCKET
TEMP_BUCKET=$TEMP_BUCKET
ANALYSIS_TABLE=$ANALYSIS_TABLE
SNS_TOPIC=$SNS_TOPIC
SQS_QUEUE=$SQS_QUEUE
EOF
    
    log "Resource names saved to /tmp/video-analysis-resources.env"
}

# Function to create S3 buckets
create_s3_buckets() {
    info "Creating S3 buckets..."
    
    # Create source bucket
    if aws s3api head-bucket --bucket "$SOURCE_BUCKET" 2>/dev/null; then
        warn "Source bucket $SOURCE_BUCKET already exists"
    else
        aws s3 mb "s3://$SOURCE_BUCKET" --region "$AWS_REGION"
        log "Created source bucket: $SOURCE_BUCKET"
    fi
    
    # Create results bucket
    if aws s3api head-bucket --bucket "$RESULTS_BUCKET" 2>/dev/null; then
        warn "Results bucket $RESULTS_BUCKET already exists"
    else
        aws s3 mb "s3://$RESULTS_BUCKET" --region "$AWS_REGION"
        log "Created results bucket: $RESULTS_BUCKET"
    fi
    
    # Create temp bucket
    if aws s3api head-bucket --bucket "$TEMP_BUCKET" 2>/dev/null; then
        warn "Temp bucket $TEMP_BUCKET already exists"
    else
        aws s3 mb "s3://$TEMP_BUCKET" --region "$AWS_REGION"
        log "Created temp bucket: $TEMP_BUCKET"
    fi
    
    # Apply bucket policies for security
    info "Applying bucket security policies..."
    
    for bucket in "$SOURCE_BUCKET" "$RESULTS_BUCKET" "$TEMP_BUCKET"; do
        aws s3api put-bucket-policy --bucket "$bucket" --policy "$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::$bucket",
                "arn:aws:s3:::$bucket/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
        )"
    done
    
    log "Applied security policies to all buckets"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    info "Creating DynamoDB table..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "$ANALYSIS_TABLE" &>/dev/null; then
        warn "DynamoDB table $ANALYSIS_TABLE already exists"
        return 0
    fi
    
    # Create table
    aws dynamodb create-table \
        --table-name "$ANALYSIS_TABLE" \
        --attribute-definitions \
            AttributeName=VideoId,AttributeType=S \
            AttributeName=Timestamp,AttributeType=N \
            AttributeName=JobStatus,AttributeType=S \
        --key-schema \
            AttributeName=VideoId,KeyType=HASH \
            AttributeName=Timestamp,KeyType=RANGE \
        --global-secondary-indexes \
            IndexName=JobStatusIndex,KeySchema=[{AttributeName=JobStatus,KeyType=HASH},{AttributeName=Timestamp,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
        --provisioned-throughput ReadCapacityUnits=10,WriteCapacityUnits=10 \
        --region "$AWS_REGION"
    
    # Wait for table to be created
    log "Waiting for DynamoDB table to be created..."
    aws dynamodb wait table-exists --table-name "$ANALYSIS_TABLE"
    
    log "Created DynamoDB table: $ANALYSIS_TABLE"
}

# Function to create SNS topic and SQS queue
create_messaging_infrastructure() {
    info "Creating SNS topic and SQS queue..."
    
    # Create SNS topic
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC" \
        --region "$AWS_REGION" \
        --query TopicArn --output text)
    
    log "Created SNS topic: $SNS_TOPIC_ARN"
    
    # Create SQS queue
    SQS_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$SQS_QUEUE" \
        --region "$AWS_REGION" \
        --query QueueUrl --output text)
    
    # Get SQS queue ARN
    SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$SQS_QUEUE_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    log "Created SQS queue: $SQS_QUEUE_URL"
    
    # Subscribe SQS queue to SNS topic
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol sqs \
        --notification-endpoint "$SQS_QUEUE_ARN"
    
    log "Subscribed SQS queue to SNS topic"
    
    # Export for use in other functions
    export SNS_TOPIC_ARN
    export SQS_QUEUE_URL
    export SQS_QUEUE_ARN
}

# Function to create IAM roles
create_iam_roles() {
    info "Creating IAM roles and policies..."
    
    # Create Lambda execution role
    if aws iam get-role --role-name VideoAnalysisLambdaRole &>/dev/null; then
        warn "Lambda role VideoAnalysisLambdaRole already exists"
    else
        aws iam create-role \
            --role-name VideoAnalysisLambdaRole \
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
            }'
        
        log "Created Lambda execution role"
    fi
    
    # Attach managed policies to Lambda role
    aws iam attach-role-policy \
        --role-name VideoAnalysisLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for video analysis
    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/VideoAnalysisPolicy" &>/dev/null; then
        warn "Custom policy VideoAnalysisPolicy already exists"
    else
        aws iam create-policy \
            --policy-name VideoAnalysisPolicy \
            --policy-document "$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rekognition:StartMediaAnalysisJob",
                "rekognition:GetMediaAnalysisJob",
                "rekognition:StartContentModeration",
                "rekognition:GetContentModeration",
                "rekognition:StartSegmentDetection",
                "rekognition:GetSegmentDetection",
                "rekognition:StartTextDetection",
                "rekognition:GetTextDetection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::$SOURCE_BUCKET/*",
                "arn:aws:s3:::$RESULTS_BUCKET/*",
                "arn:aws:s3:::$TEMP_BUCKET/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": [
                "arn:aws:dynamodb:$AWS_REGION:$AWS_ACCOUNT_ID:table/$ANALYSIS_TABLE",
                "arn:aws:dynamodb:$AWS_REGION:$AWS_ACCOUNT_ID:table/$ANALYSIS_TABLE/index/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "$SNS_TOPIC_ARN"
        },
        {
            "Effect": "Allow",
            "Action": [
                "states:StartExecution"
            ],
            "Resource": "arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:VideoAnalysisWorkflow"
        }
    ]
}
EOF
        )"
        
        log "Created custom policy: VideoAnalysisPolicy"
    fi
    
    # Attach custom policy to Lambda role
    aws iam attach-role-policy \
        --role-name VideoAnalysisLambdaRole \
        --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/VideoAnalysisPolicy"
    
    # Create Step Functions execution role
    if aws iam get-role --role-name VideoAnalysisStepFunctionsRole &>/dev/null; then
        warn "Step Functions role VideoAnalysisStepFunctionsRole already exists"
    else
        aws iam create-role \
            --role-name VideoAnalysisStepFunctionsRole \
            --assume-role-policy-document '{
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
            }'
        
        log "Created Step Functions execution role"
    fi
    
    # Create policy for Step Functions
    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/VideoAnalysisStepFunctionsPolicy" &>/dev/null; then
        warn "Step Functions policy VideoAnalysisStepFunctionsPolicy already exists"
    else
        aws iam create-policy \
            --policy-name VideoAnalysisStepFunctionsPolicy \
            --policy-document "$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:VideoAnalysis*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "rekognition:StartMediaAnalysisJob",
                "rekognition:GetMediaAnalysisJob",
                "rekognition:StartContentModeration",
                "rekognition:GetContentModeration",
                "rekognition:StartSegmentDetection",
                "rekognition:GetSegmentDetection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "$SNS_TOPIC_ARN"
        }
    ]
}
EOF
        )"
        
        log "Created Step Functions policy: VideoAnalysisStepFunctionsPolicy"
    fi
    
    # Attach policy to Step Functions role
    aws iam attach-role-policy \
        --role-name VideoAnalysisStepFunctionsRole \
        --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/VideoAnalysisStepFunctionsPolicy"
    
    log "IAM roles and policies created successfully"
}

# Function to create Lambda functions
create_lambda_functions() {
    info "Creating Lambda functions..."
    
    # Create temporary directory for Lambda packages
    mkdir -p /tmp/lambda-packages
    
    # Create initialization function
    create_lambda_function "VideoAnalysisInitFunction" "init_function.py" "index.lambda_handler" "256" "60" "ANALYSIS_TABLE=$ANALYSIS_TABLE"
    
    # Create moderation function
    create_lambda_function "VideoAnalysisModerationFunction" "moderation_function.py" "index.lambda_handler" "256" "60" "ANALYSIS_TABLE=$ANALYSIS_TABLE,SNS_TOPIC_ARN=$SNS_TOPIC_ARN,REKOGNITION_ROLE_ARN=arn:aws:iam::$AWS_ACCOUNT_ID:role/VideoAnalysisLambdaRole"
    
    # Create segment detection function
    create_lambda_function "VideoAnalysisSegmentFunction" "segment_function.py" "index.lambda_handler" "256" "60" "ANALYSIS_TABLE=$ANALYSIS_TABLE,SNS_TOPIC_ARN=$SNS_TOPIC_ARN,REKOGNITION_ROLE_ARN=arn:aws:iam::$AWS_ACCOUNT_ID:role/VideoAnalysisLambdaRole"
    
    # Create aggregation function
    create_lambda_function "VideoAnalysisAggregationFunction" "aggregation_function.py" "index.lambda_handler" "512" "300" "ANALYSIS_TABLE=$ANALYSIS_TABLE,RESULTS_BUCKET=$RESULTS_BUCKET"
    
    # Create trigger function (will be created later after state machine)
    log "Lambda functions created successfully"
}

# Helper function to create individual Lambda functions
create_lambda_function() {
    local function_name=$1
    local source_file=$2
    local handler=$3
    local memory=$4
    local timeout=$5
    local env_vars=$6
    
    info "Creating Lambda function: $function_name"
    
    # Check if function already exists
    if aws lambda get-function --function-name "$function_name" &>/dev/null; then
        warn "Lambda function $function_name already exists, updating..."
        return 0
    fi
    
    # Create function package directory
    local package_dir="/tmp/lambda-packages/$function_name"
    mkdir -p "$package_dir"
    
    # Copy source code from terraform directory
    if [ -f "../terraform/lambda_code/$source_file" ]; then
        cp "../terraform/lambda_code/$source_file" "$package_dir/index.py"
    else
        error "Source file not found: ../terraform/lambda_code/$source_file"
        exit 1
    fi
    
    # Create deployment package
    cd "$package_dir"
    zip -r "../$function_name.zip" .
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$function_name" \
        --runtime python3.9 \
        --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/VideoAnalysisLambdaRole" \
        --handler "$handler" \
        --zip-file "fileb:///tmp/lambda-packages/$function_name.zip" \
        --timeout "$timeout" \
        --memory-size "$memory" \
        --environment "Variables={$env_vars}" \
        --region "$AWS_REGION"
    
    log "Created Lambda function: $function_name"
    
    # Return to original directory
    cd - > /dev/null
}

# Function to create Step Functions state machine
create_state_machine() {
    info "Creating Step Functions state machine..."
    
    # Check if state machine already exists
    if aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:VideoAnalysisWorkflow" &>/dev/null; then
        warn "State machine VideoAnalysisWorkflow already exists"
        export STATE_MACHINE_ARN="arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:VideoAnalysisWorkflow"
        return 0
    fi
    
    # Create state machine definition
    cat > /tmp/video-analysis-state-machine.json << EOF
{
  "Comment": "Video Content Analysis Workflow",
  "StartAt": "InitializeAnalysis",
  "States": {
    "InitializeAnalysis": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "VideoAnalysisInitFunction",
        "Payload.$": "$"
      },
      "Next": "ParallelAnalysis",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 5,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ]
    },
    "ParallelAnalysis": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "ContentModeration",
          "States": {
            "ContentModeration": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "VideoAnalysisModerationFunction",
                "Payload.$": "$.Payload.body"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "SegmentDetection",
          "States": {
            "SegmentDetection": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "VideoAnalysisSegmentFunction",
                "Payload.$": "$.Payload.body"
              },
              "End": true
            }
          }
        }
      ],
      "Next": "WaitForCompletion"
    },
    "WaitForCompletion": {
      "Type": "Wait",
      "Seconds": 60,
      "Next": "AggregateResults"
    },
    "AggregateResults": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "VideoAnalysisAggregationFunction",
        "Payload": {
          "jobId.$": "$[0].Payload.body.jobId",
          "videoId.$": "$[0].Payload.body.videoId",
          "moderationJobId.$": "$[0].Payload.body.moderationJobId",
          "segmentJobId.$": "$[1].Payload.body.segmentJobId"
        }
      },
      "Next": "NotifyCompletion"
    },
    "NotifyCompletion": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "$SNS_TOPIC_ARN",
        "Message": {
          "jobId.$": "$.Payload.body.jobId",
          "videoId.$": "$.Payload.body.videoId",
          "status.$": "$.Payload.body.status",
          "resultsLocation.$": "$.Payload.body.resultsLocation"
        }
      },
      "End": true
    }
  }
}
EOF
    
    # Create the state machine
    STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
        --name VideoAnalysisWorkflow \
        --definition file:///tmp/video-analysis-state-machine.json \
        --role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/VideoAnalysisStepFunctionsRole" \
        --query stateMachineArn --output text)
    
    log "Created Step Functions state machine: $STATE_MACHINE_ARN"
    export STATE_MACHINE_ARN
}

# Function to create trigger Lambda function
create_trigger_function() {
    info "Creating S3 trigger Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "VideoAnalysisTriggerFunction" &>/dev/null; then
        warn "Trigger function VideoAnalysisTriggerFunction already exists"
        return 0
    fi
    
    # Create trigger function
    create_lambda_function "VideoAnalysisTriggerFunction" "trigger_function.py" "index.lambda_handler" "256" "60" "STATE_MACHINE_ARN=$STATE_MACHINE_ARN"
    
    # Add S3 trigger permission
    aws lambda add-permission \
        --function-name VideoAnalysisTriggerFunction \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger \
        --source-arn "arn:aws:s3:::$SOURCE_BUCKET"
    
    # Configure S3 bucket notification
    aws s3api put-bucket-notification-configuration \
        --bucket "$SOURCE_BUCKET" \
        --notification-configuration "$(cat << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "VideoAnalysisTrigger",
            "LambdaFunctionArn": "arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:VideoAnalysisTriggerFunction",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".mp4"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
        )"
    
    log "Created S3 trigger function and configured bucket notification"
}

# Function to create monitoring resources
create_monitoring() {
    info "Creating monitoring dashboard and alerts..."
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name VideoAnalysisDashboard \
        --dashboard-body "$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Duration", "FunctionName", "VideoAnalysisInitFunction"],
                    ["AWS/Lambda", "Duration", "FunctionName", "VideoAnalysisModerationFunction"],
                    ["AWS/Lambda", "Duration", "FunctionName", "VideoAnalysisSegmentFunction"],
                    ["AWS/Lambda", "Duration", "FunctionName", "VideoAnalysisAggregationFunction"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Lambda Function Duration"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/States", "ExecutionsFailed", "StateMachineArn", "$STATE_MACHINE_ARN"],
                    ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", "$STATE_MACHINE_ARN"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "Step Functions Executions"
            }
        }
    ]
}
EOF
        )"
    
    # Create CloudWatch alarm for failed executions
    aws cloudwatch put-metric-alarm \
        --alarm-name VideoAnalysisFailedExecutions \
        --alarm-description "Alert when Step Functions executions fail" \
        --metric-name ExecutionsFailed \
        --namespace AWS/States \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=StateMachineArn,Value="$STATE_MACHINE_ARN"
    
    log "Created monitoring dashboard and alerts"
}

# Function to display deployment summary
display_summary() {
    log "============================================="
    log "Video Content Analysis Deployment Complete!"
    log "============================================="
    log ""
    log "Resources Created:"
    log "  - S3 Buckets:"
    log "    - Source: $SOURCE_BUCKET"
    log "    - Results: $RESULTS_BUCKET"
    log "    - Temp: $TEMP_BUCKET"
    log "  - DynamoDB Table: $ANALYSIS_TABLE"
    log "  - SNS Topic: $SNS_TOPIC_ARN"
    log "  - SQS Queue: $SQS_QUEUE_URL"
    log "  - Lambda Functions:"
    log "    - VideoAnalysisInitFunction"
    log "    - VideoAnalysisModerationFunction"
    log "    - VideoAnalysisSegmentFunction"
    log "    - VideoAnalysisAggregationFunction"
    log "    - VideoAnalysisTriggerFunction"
    log "  - Step Functions State Machine: $STATE_MACHINE_ARN"
    log "  - IAM Roles:"
    log "    - VideoAnalysisLambdaRole"
    log "    - VideoAnalysisStepFunctionsRole"
    log "  - CloudWatch Dashboard: VideoAnalysisDashboard"
    log "  - CloudWatch Alarm: VideoAnalysisFailedExecutions"
    log ""
    log "Next Steps:"
    log "1. Upload a video file to s3://$SOURCE_BUCKET to trigger analysis"
    log "2. Monitor execution in Step Functions console"
    log "3. Check results in s3://$RESULTS_BUCKET"
    log "4. View monitoring dashboard in CloudWatch"
    log ""
    log "Sample upload command:"
    log "aws s3 cp your-video.mp4 s3://$SOURCE_BUCKET/"
    log ""
    log "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Video Content Analysis deployment..."
    
    # Check prerequisites
    check_command "aws"
    check_command "jq"
    check_command "zip"
    
    # Validate AWS setup
    validate_aws_credentials
    check_permissions
    
    # Generate resource names
    generate_resource_names
    
    # Create infrastructure components
    create_s3_buckets
    create_dynamodb_table
    create_messaging_infrastructure
    create_iam_roles
    
    # Wait for IAM roles to propagate
    info "Waiting for IAM roles to propagate..."
    sleep 30
    
    create_lambda_functions
    create_state_machine
    create_trigger_function
    create_monitoring
    
    # Display deployment summary
    display_summary
    
    log "Deployment completed successfully!"
}

# Execute main function
main "$@"