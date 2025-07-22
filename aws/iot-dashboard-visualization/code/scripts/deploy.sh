#!/bin/bash
#
# Deploy script for IoT Data Visualization with QuickSight
# This script creates the complete infrastructure for IoT data collection,
# processing, and visualization using AWS services.
#
# Usage: ./deploy.sh [--dry-run] [--debug] [--email your-email@example.com]
#
# Author: Recipe Generator
# Version: 1.0
# Last Updated: 2025-01-27

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
DEBUG=false
QUICKSIGHT_EMAIL=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        DEBUG)
            if [[ "$DEBUG" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
                echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
}

# Error handling
cleanup_on_error() {
    log ERROR "Deployment failed. Starting cleanup of partially created resources..."
    
    # Clean up resources in reverse order
    cleanup_resources 2>/dev/null || true
    
    log ERROR "Cleanup completed. Check $LOG_FILE for details."
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --email)
            QUICKSIGHT_EMAIL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--debug] [--email your-email@example.com]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --debug      Enable debug logging"
            echo "  --email      Email for QuickSight notifications"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log DEBUG "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local caller_identity=$(aws sts get-caller-identity --output text --query 'Arn')
    log DEBUG "AWS caller identity: $caller_identity"
    
    # Validate email for QuickSight
    if [[ -z "$QUICKSIGHT_EMAIL" ]]; then
        log WARN "No email provided for QuickSight. Using default format."
        QUICKSIGHT_EMAIL="quicksight-$(whoami)@example.com"
    fi
    
    log INFO "Prerequisites check completed"
}

# Initialize environment variables
init_environment() {
    log INFO "Initializing environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log WARN "No region configured, using default: $AWS_REGION"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export IOT_POLICY_NAME="iot-device-policy-${RANDOM_SUFFIX}"
    export IOT_THING_NAME="iot-sensor-${RANDOM_SUFFIX}"
    export IOT_RULE_NAME="RouteToKinesis${RANDOM_SUFFIX}"
    export KINESIS_STREAM_NAME="iot-data-stream-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="iot-analytics-bucket-${RANDOM_SUFFIX}"
    export FIREHOSE_DELIVERY_STREAM="iot-firehose-${RANDOM_SUFFIX}"
    export QUICKSIGHT_USER_NAME="quicksight-user-${RANDOM_SUFFIX}"
    export GLUE_DATABASE_NAME="iot_analytics_db_${RANDOM_SUFFIX}"
    export GLUE_TABLE_NAME="iot_sensor_data"
    export IOT_KINESIS_ROLE_NAME="IoTKinesisRole${RANDOM_SUFFIX}"
    export FIREHOSE_ROLE_NAME="FirehoseDeliveryRole${RANDOM_SUFFIX}"
    export IOT_KINESIS_POLICY_NAME="IoTKinesisPolicy${RANDOM_SUFFIX}"
    export FIREHOSE_S3_POLICY_NAME="FirehoseS3Policy${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
IOT_POLICY_NAME=${IOT_POLICY_NAME}
IOT_THING_NAME=${IOT_THING_NAME}
IOT_RULE_NAME=${IOT_RULE_NAME}
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
FIREHOSE_DELIVERY_STREAM=${FIREHOSE_DELIVERY_STREAM}
QUICKSIGHT_USER_NAME=${QUICKSIGHT_USER_NAME}
GLUE_DATABASE_NAME=${GLUE_DATABASE_NAME}
GLUE_TABLE_NAME=${GLUE_TABLE_NAME}
IOT_KINESIS_ROLE_NAME=${IOT_KINESIS_ROLE_NAME}
FIREHOSE_ROLE_NAME=${FIREHOSE_ROLE_NAME}
IOT_KINESIS_POLICY_NAME=${IOT_KINESIS_POLICY_NAME}
FIREHOSE_S3_POLICY_NAME=${FIREHOSE_S3_POLICY_NAME}
QUICKSIGHT_EMAIL=${QUICKSIGHT_EMAIL}
EOF
    
    log INFO "Environment initialized with suffix: ${RANDOM_SUFFIX}"
    log DEBUG "S3 bucket: ${S3_BUCKET_NAME}"
    log DEBUG "Kinesis stream: ${KINESIS_STREAM_NAME}"
}

# Execute AWS CLI command with error handling
execute_aws_command() {
    local description="$1"
    shift
    local command=("$@")
    
    log INFO "$description"
    log DEBUG "Executing: ${command[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would execute: ${command[*]}"
        return 0
    fi
    
    local output
    if output=$(${command[@]} 2>&1); then
        log DEBUG "Command succeeded: $output"
        return 0
    else
        log ERROR "Command failed: ${command[*]}"
        log ERROR "Error output: $output"
        return 1
    fi
}

# Create S3 bucket
create_s3_bucket() {
    log INFO "Creating S3 bucket for IoT data storage..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        log WARN "S3 bucket ${S3_BUCKET_NAME} already exists"
        return 0
    fi
    
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        execute_aws_command "Creating S3 bucket in us-east-1" \
            aws s3api create-bucket --bucket "${S3_BUCKET_NAME}"
    else
        execute_aws_command "Creating S3 bucket in ${AWS_REGION}" \
            aws s3api create-bucket \
            --bucket "${S3_BUCKET_NAME}" \
            --region "${AWS_REGION}" \
            --create-bucket-configuration LocationConstraint="${AWS_REGION}"
    fi
    
    # Enable versioning for data protection
    execute_aws_command "Enabling S3 bucket versioning" \
        aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    log INFO "S3 bucket created successfully: ${S3_BUCKET_NAME}"
}

# Create IoT Core resources
create_iot_resources() {
    log INFO "Creating IoT Core resources..."
    
    # Create IoT policy
    execute_aws_command "Creating IoT policy" \
        aws iot create-policy \
        --policy-name "${IOT_POLICY_NAME}" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["iot:Connect", "iot:Publish"],
                    "Resource": "*"
                }
            ]
        }'
    
    # Create IoT thing
    execute_aws_command "Creating IoT thing" \
        aws iot create-thing \
        --thing-name "${IOT_THING_NAME}" \
        --thing-type-name "SensorDevice" || true
    
    log INFO "IoT Core resources created successfully"
}

# Create Kinesis resources
create_kinesis_resources() {
    log INFO "Creating Kinesis Data Stream..."
    
    # Create Kinesis stream
    execute_aws_command "Creating Kinesis stream" \
        aws kinesis create-stream \
        --stream-name "${KINESIS_STREAM_NAME}" \
        --shard-count 1
    
    # Wait for stream to become active
    log INFO "Waiting for Kinesis stream to become active..."
    if [[ "$DRY_RUN" == "false" ]]; then
        aws kinesis wait stream-exists --stream-name "${KINESIS_STREAM_NAME}"
    fi
    
    log INFO "Kinesis stream created successfully: ${KINESIS_STREAM_NAME}"
}

# Create IAM roles and policies
create_iam_resources() {
    log INFO "Creating IAM roles and policies..."
    
    # Create IoT Kinesis role
    execute_aws_command "Creating IoT Kinesis role" \
        aws iam create-role \
        --role-name "${IOT_KINESIS_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "iot.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
    
    # Create IoT Kinesis policy
    execute_aws_command "Creating IoT Kinesis policy" \
        aws iam create-policy \
        --policy-name "${IOT_KINESIS_POLICY_NAME}" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "kinesis:PutRecord",
                        "kinesis:PutRecords"
                    ],
                    "Resource": "arn:aws:kinesis:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':stream/'${KINESIS_STREAM_NAME}'"
                }
            ]
        }'
    
    # Attach policy to IoT role
    execute_aws_command "Attaching policy to IoT role" \
        aws iam attach-role-policy \
        --role-name "${IOT_KINESIS_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IOT_KINESIS_POLICY_NAME}"
    
    # Create Firehose role
    execute_aws_command "Creating Firehose role" \
        aws iam create-role \
        --role-name "${FIREHOSE_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "firehose.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
    
    # Create Firehose S3 policy
    execute_aws_command "Creating Firehose S3 policy" \
        aws iam create-policy \
        --policy-name "${FIREHOSE_S3_POLICY_NAME}" \
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
                        "arn:aws:s3:::'${S3_BUCKET_NAME}'",
                        "arn:aws:s3:::'${S3_BUCKET_NAME}'/*"
                    ]
                }
            ]
        }'
    
    # Attach policy to Firehose role
    execute_aws_command "Attaching policy to Firehose role" \
        aws iam attach-role-policy \
        --role-name "${FIREHOSE_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${FIREHOSE_S3_POLICY_NAME}"
    
    # Wait for IAM role propagation
    log INFO "Waiting for IAM role propagation..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 10
    fi
    
    log INFO "IAM resources created successfully"
}

# Create IoT rule
create_iot_rule() {
    log INFO "Creating IoT Rules Engine rule..."
    
    execute_aws_command "Creating IoT rule" \
        aws iot create-topic-rule \
        --rule-name "${IOT_RULE_NAME}" \
        --topic-rule-payload '{
            "sql": "SELECT *, timestamp() as event_time FROM \"topic/sensor/data\"",
            "description": "Route IoT sensor data to Kinesis Data Streams",
            "actions": [
                {
                    "kinesis": {
                        "roleArn": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${IOT_KINESIS_ROLE_NAME}'",
                        "streamName": "'${KINESIS_STREAM_NAME}'"
                    }
                }
            ]
        }'
    
    log INFO "IoT rule created successfully"
}

# Create Firehose delivery stream
create_firehose_stream() {
    log INFO "Creating Kinesis Data Firehose delivery stream..."
    
    execute_aws_command "Creating Firehose delivery stream" \
        aws firehose create-delivery-stream \
        --delivery-stream-name "${FIREHOSE_DELIVERY_STREAM}" \
        --kinesis-stream-source-configuration '{
            "KinesisStreamARN": "arn:aws:kinesis:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':stream/'${KINESIS_STREAM_NAME}'",
            "RoleARN": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${FIREHOSE_ROLE_NAME}'"
        }' \
        --s3-destination-configuration '{
            "RoleARN": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${FIREHOSE_ROLE_NAME}'",
            "BucketARN": "arn:aws:s3:::'${S3_BUCKET_NAME}'",
            "Prefix": "iot-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
            "BufferingHints": {
                "SizeInMBs": 1,
                "IntervalInSeconds": 60
            },
            "CompressionFormat": "GZIP"
        }'
    
    log INFO "Firehose delivery stream created successfully"
}

# Create Glue resources
create_glue_resources() {
    log INFO "Creating AWS Glue Data Catalog resources..."
    
    # Create Glue database
    execute_aws_command "Creating Glue database" \
        aws glue create-database \
        --database-input '{
            "Name": "'${GLUE_DATABASE_NAME}'",
            "Description": "Database for IoT sensor data analytics"
        }'
    
    # Create Glue table
    execute_aws_command "Creating Glue table" \
        aws glue create-table \
        --database-name "${GLUE_DATABASE_NAME}" \
        --table-input '{
            "Name": "'${GLUE_TABLE_NAME}'",
            "Description": "Table for IoT sensor data",
            "StorageDescriptor": {
                "Columns": [
                    {
                        "Name": "device_id",
                        "Type": "string"
                    },
                    {
                        "Name": "temperature",
                        "Type": "int"
                    },
                    {
                        "Name": "humidity",
                        "Type": "int"
                    },
                    {
                        "Name": "pressure",
                        "Type": "int"
                    },
                    {
                        "Name": "timestamp",
                        "Type": "string"
                    },
                    {
                        "Name": "event_time",
                        "Type": "bigint"
                    }
                ],
                "Location": "s3://'${S3_BUCKET_NAME}'/iot-data/",
                "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
                "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
                "SerdeInfo": {
                    "SerializationLibrary": "org.openx.data.jsonserde.JsonSerDe"
                }
            }
        }'
    
    log INFO "Glue resources created successfully"
}

# Generate test data
generate_test_data() {
    log INFO "Generating test IoT sensor data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would generate test data"
        return 0
    fi
    
    for i in {1..10}; do
        local temp=$((RANDOM % 40 + 10))
        local humidity=$((RANDOM % 100))
        local pressure=$((RANDOM % 200 + 900))
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
        
        log DEBUG "Publishing sensor data: temp=${temp}, humidity=${humidity}, pressure=${pressure}"
        
        aws iot-data publish \
            --topic "topic/sensor/data" \
            --payload '{
                "device_id": "'${IOT_THING_NAME}'",
                "temperature": '${temp}',
                "humidity": '${humidity}',
                "pressure": '${pressure}',
                "timestamp": "'${timestamp}'"
            }' || log WARN "Failed to publish data point ${i}"
        
        sleep 2
    done
    
    log INFO "Test data generation completed"
}

# Setup QuickSight
setup_quicksight() {
    log INFO "Setting up QuickSight resources..."
    
    # Create QuickSight account (if not exists)
    execute_aws_command "Creating QuickSight account" \
        aws quicksight create-account-subscription \
        --edition STANDARD \
        --authentication-method IAM_AND_QUICKSIGHT \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --account-name "IoT Analytics Account" \
        --notification-email "${QUICKSIGHT_EMAIL}" \
        --region "${AWS_REGION}" || log WARN "QuickSight account may already exist"
    
    # Register QuickSight user
    execute_aws_command "Registering QuickSight user" \
        aws quicksight register-user \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --namespace default \
        --identity-type IAM \
        --iam-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:root" \
        --user-role ADMIN \
        --user-name "${QUICKSIGHT_USER_NAME}" \
        --region "${AWS_REGION}" || log WARN "QuickSight user may already exist"
    
    # Create QuickSight data source
    execute_aws_command "Creating QuickSight data source" \
        aws quicksight create-data-source \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-source-id "iot-athena-datasource-${RANDOM_SUFFIX}" \
        --name "IoT Analytics Data Source" \
        --type ATHENA \
        --data-source-parameters '{
            "AthenaParameters": {
                "WorkGroup": "primary"
            }
        }' \
        --permissions '[
            {
                "Principal": "arn:aws:quicksight:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':user/default/'${QUICKSIGHT_USER_NAME}'",
                "Actions": [
                    "quicksight:DescribeDataSource",
                    "quicksight:DescribeDataSourcePermissions",
                    "quicksight:PassDataSource"
                ]
            }
        ]' \
        --region "${AWS_REGION}" || log WARN "QuickSight data source may already exist"
    
    log INFO "QuickSight setup completed"
}

# Cleanup resources (for error handling)
cleanup_resources() {
    log WARN "Cleaning up resources due to deployment failure..."
    
    # Call the destroy script
    "${SCRIPT_DIR}/destroy.sh" --force 2>/dev/null || true
}

# Validate deployment
validate_deployment() {
    log INFO "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        log INFO "✅ S3 bucket is accessible"
    else
        log ERROR "❌ S3 bucket validation failed"
        return 1
    fi
    
    # Check Kinesis stream
    local stream_status=$(aws kinesis describe-stream --stream-name "${KINESIS_STREAM_NAME}" --query 'StreamDescription.StreamStatus' --output text)
    if [[ "$stream_status" == "ACTIVE" ]]; then
        log INFO "✅ Kinesis stream is active"
    else
        log ERROR "❌ Kinesis stream is not active: $stream_status"
        return 1
    fi
    
    # Check Glue database
    if aws glue get-database --name "${GLUE_DATABASE_NAME}" &>/dev/null; then
        log INFO "✅ Glue database exists"
    else
        log ERROR "❌ Glue database validation failed"
        return 1
    fi
    
    log INFO "Deployment validation completed successfully"
}

# Main deployment function
main() {
    log INFO "Starting IoT Data Visualization deployment..."
    log INFO "Deployment mode: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "LIVE")"
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    init_environment
    create_s3_bucket
    create_iot_resources
    create_kinesis_resources
    create_iam_resources
    create_iot_rule
    create_firehose_stream
    create_glue_resources
    generate_test_data
    setup_quicksight
    validate_deployment
    
    # Print deployment summary
    log INFO "🎉 Deployment completed successfully!"
    log INFO ""
    log INFO "📋 Deployment Summary:"
    log INFO "   S3 Bucket: ${S3_BUCKET_NAME}"
    log INFO "   Kinesis Stream: ${KINESIS_STREAM_NAME}"
    log INFO "   IoT Thing: ${IOT_THING_NAME}"
    log INFO "   Glue Database: ${GLUE_DATABASE_NAME}"
    log INFO "   QuickSight User: ${QUICKSIGHT_USER_NAME}"
    log INFO ""
    log INFO "🔧 Next Steps:"
    log INFO "   1. Access QuickSight console to create dashboards"
    log INFO "   2. Connect to the Athena data source"
    log INFO "   3. Create visualizations using the IoT sensor data"
    log INFO "   4. Set up real-time dashboards and alerts"
    log INFO ""
    log INFO "📄 Environment variables saved to: ${SCRIPT_DIR}/.env"
    log INFO "📄 Full deployment log: ${LOG_FILE}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO ""
        log INFO "💰 Estimated monthly cost: $15-25 (varies by usage)"
        log INFO "🧹 To clean up resources, run: ./destroy.sh"
    fi
}

# Run main function
main "$@"