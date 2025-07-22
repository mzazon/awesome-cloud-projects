#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warn "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warn "Force mode enabled - will skip confirmation prompts"
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force]"
            exit 1
            ;;
    esac
done

# Function to execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DRY-RUN] Would execute: $cmd${NC}"
    else
        log "$description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || warn "Command failed but continuing: $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Function to get user confirmation
get_confirmation() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: This will delete all IoT Analytics pipeline resources!${NC}"
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Function to discover resources
discover_resources() {
    log "Discovering IoT Analytics resources..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Find IoT Analytics resources by pattern
    IOT_CHANNELS=$(aws iotanalytics list-channels --query 'channelSummaries[?starts_with(channelName, `iot-sensor-channel-`)].channelName' --output text)
    IOT_PIPELINES=$(aws iotanalytics list-pipelines --query 'pipelineSummaries[?starts_with(pipelineName, `iot-sensor-pipeline-`)].pipelineName' --output text)
    IOT_DATASTORES=$(aws iotanalytics list-datastores --query 'datastoreSummaries[?starts_with(datastoreName, `iot-sensor-datastore-`)].datastoreName' --output text)
    IOT_DATASETS=$(aws iotanalytics list-datasets --query 'datasetSummaries[?starts_with(datasetName, `iot-sensor-dataset-`)].datasetName' --output text)
    
    # Find Kinesis streams
    KINESIS_STREAMS=$(aws kinesis list-streams --query 'StreamNames[?starts_with(@, `iot-sensor-stream-`)]' --output text)
    
    # Find Timestream databases
    TIMESTREAM_DATABASES=$(aws timestream-write list-databases --query 'Databases[?starts_with(DatabaseName, `iot-sensor-db-`)].DatabaseName' --output text)
    
    # Find Lambda functions
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `ProcessIoTData`)].FunctionName' --output text)
    
    log "Resource discovery completed"
}

# Function to delete IoT Analytics resources
delete_iot_analytics_resources() {
    log "Deleting IoT Analytics resources..."
    
    # Delete datasets
    for dataset in $IOT_DATASETS; do
        execute_cmd "aws iotanalytics delete-dataset \
            --dataset-name $dataset \
            --output table" "Deleting IoT Analytics dataset: $dataset" true
    done
    
    # Delete pipelines
    for pipeline in $IOT_PIPELINES; do
        execute_cmd "aws iotanalytics delete-pipeline \
            --pipeline-name $pipeline \
            --output table" "Deleting IoT Analytics pipeline: $pipeline" true
    done
    
    # Delete datastores
    for datastore in $IOT_DATASTORES; do
        execute_cmd "aws iotanalytics delete-datastore \
            --datastore-name $datastore \
            --output table" "Deleting IoT Analytics datastore: $datastore" true
    done
    
    # Delete channels
    for channel in $IOT_CHANNELS; do
        execute_cmd "aws iotanalytics delete-channel \
            --channel-name $channel \
            --output table" "Deleting IoT Analytics channel: $channel" true
    done
    
    # Delete IoT rule
    execute_cmd "aws iot delete-topic-rule \
        --rule-name IoTAnalyticsRule \
        --output table" "Deleting IoT rule" true
}

# Function to delete Lambda function and event source mappings
delete_lambda_resources() {
    log "Deleting Lambda resources..."
    
    # Delete event source mappings first
    for function in $LAMBDA_FUNCTIONS; do
        # Get event source mappings for this function
        EVENT_SOURCE_MAPPINGS=$(aws lambda list-event-source-mappings \
            --function-name $function \
            --query 'EventSourceMappings[].UUID' \
            --output text)
        
        for mapping in $EVENT_SOURCE_MAPPINGS; do
            execute_cmd "aws lambda delete-event-source-mapping \
                --uuid $mapping \
                --output table" "Deleting event source mapping: $mapping" true
        done
        
        # Delete the function
        execute_cmd "aws lambda delete-function \
            --function-name $function \
            --output table" "Deleting Lambda function: $function" true
    done
}

# Function to delete Timestream resources
delete_timestream_resources() {
    log "Deleting Timestream resources..."
    
    for database in $TIMESTREAM_DATABASES; do
        # List tables in the database
        TIMESTREAM_TABLES=$(aws timestream-write list-tables \
            --database-name $database \
            --query 'Tables[].TableName' \
            --output text 2>/dev/null || echo "")
        
        # Delete tables first
        for table in $TIMESTREAM_TABLES; do
            execute_cmd "aws timestream-write delete-table \
                --database-name $database \
                --table-name $table \
                --output table" "Deleting Timestream table: $table" true
        done
        
        # Delete the database
        execute_cmd "aws timestream-write delete-database \
            --database-name $database \
            --output table" "Deleting Timestream database: $database" true
    done
}

# Function to delete Kinesis resources
delete_kinesis_resources() {
    log "Deleting Kinesis resources..."
    
    for stream in $KINESIS_STREAMS; do
        execute_cmd "aws kinesis delete-stream \
            --stream-name $stream \
            --output table" "Deleting Kinesis stream: $stream" true
        
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Waiting for Kinesis stream to be deleted..."
            # Wait for stream to be deleted (timeout after 5 minutes)
            timeout=300
            while [[ $timeout -gt 0 ]]; do
                if ! aws kinesis describe-stream --stream-name $stream &>/dev/null; then
                    log "Kinesis stream $stream successfully deleted"
                    break
                fi
                sleep 10
                timeout=$((timeout - 10))
            done
        fi
    done
}

# Function to delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Delete IoT Analytics service role
    execute_cmd "aws iam detach-role-policy \
        --role-name IoTAnalyticsServiceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSIoTAnalyticsServiceRole" "Detaching policy from IoT Analytics role" true
    
    execute_cmd "aws iam delete-role \
        --role-name IoTAnalyticsServiceRole \
        --output table" "Deleting IoT Analytics service role" true
    
    # Delete Lambda execution role
    execute_cmd "aws iam detach-role-policy \
        --role-name LambdaTimestreamRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" "Detaching basic execution policy from Lambda role" true
    
    execute_cmd "aws iam detach-role-policy \
        --role-name LambdaTimestreamRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonTimestreamFullAccess" "Detaching Timestream policy from Lambda role" true
    
    execute_cmd "aws iam detach-role-policy \
        --role-name LambdaTimestreamRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole" "Detaching Kinesis execution policy from Lambda role" true
    
    execute_cmd "aws iam delete-role \
        --role-name LambdaTimestreamRole \
        --output table" "Deleting Lambda execution role" true
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    execute_cmd "rm -f /tmp/lambda_function.py /tmp/lambda_function.zip" "Removing temporary Lambda files" true
}

# Function to display deletion summary
display_summary() {
    log "Deletion Summary:"
    echo "=================="
    echo "AWS Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo ""
    
    if [[ -n "$IOT_CHANNELS" ]]; then
        echo "IoT Analytics Channels deleted:"
        for channel in $IOT_CHANNELS; do
            echo "- $channel"
        done
        echo ""
    fi
    
    if [[ -n "$IOT_PIPELINES" ]]; then
        echo "IoT Analytics Pipelines deleted:"
        for pipeline in $IOT_PIPELINES; do
            echo "- $pipeline"
        done
        echo ""
    fi
    
    if [[ -n "$IOT_DATASTORES" ]]; then
        echo "IoT Analytics Datastores deleted:"
        for datastore in $IOT_DATASTORES; do
            echo "- $datastore"
        done
        echo ""
    fi
    
    if [[ -n "$IOT_DATASETS" ]]; then
        echo "IoT Analytics Datasets deleted:"
        for dataset in $IOT_DATASETS; do
            echo "- $dataset"
        done
        echo ""
    fi
    
    if [[ -n "$KINESIS_STREAMS" ]]; then
        echo "Kinesis Streams deleted:"
        for stream in $KINESIS_STREAMS; do
            echo "- $stream"
        done
        echo ""
    fi
    
    if [[ -n "$TIMESTREAM_DATABASES" ]]; then
        echo "Timestream Databases deleted:"
        for database in $TIMESTREAM_DATABASES; do
            echo "- $database"
        done
        echo ""
    fi
    
    if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
        echo "Lambda Functions deleted:"
        for function in $LAMBDA_FUNCTIONS; do
            echo "- $function"
        done
        echo ""
    fi
    
    echo "IAM Roles deleted:"
    echo "- IoTAnalyticsServiceRole"
    echo "- LambdaTimestreamRole"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "All resources have been successfully deleted!"
        log "Please verify in the AWS Console that all resources are removed"
    else
        log "Dry-run completed successfully!"
    fi
}

# Main deletion function
main() {
    log "Starting IoT Analytics Pipeline resource deletion..."
    
    check_prerequisites
    get_confirmation
    discover_resources
    
    # Display what will be deleted
    if [[ -n "$IOT_CHANNELS$IOT_PIPELINES$IOT_DATASTORES$IOT_DATASETS$KINESIS_STREAMS$TIMESTREAM_DATABASES$LAMBDA_FUNCTIONS" ]]; then
        log "Found resources to delete..."
    else
        warn "No IoT Analytics pipeline resources found to delete"
        exit 0
    fi
    
    # Delete resources in the correct order
    delete_lambda_resources
    delete_timestream_resources
    delete_kinesis_resources
    delete_iot_analytics_resources
    
    # Wait a bit before deleting IAM roles
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for resource deletion to complete before removing IAM roles..."
        sleep 30
    fi
    
    delete_iam_roles
    cleanup_local_files
    
    display_summary
}

# Error handling
handle_error() {
    error "Deletion failed on line $LINENO. Exit code: $?"
    warn "Some resources may not have been deleted. Please check the AWS Console."
    exit 1
}

trap 'handle_error' ERR

# Run main function
main "$@"