#!/bin/bash

# Deploy script for Cross-Account Data Sharing with Data Exchange
# This script automates the deployment of a secure data sharing solution using AWS Data Exchange

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error_log() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$ERROR_LOG"
}

warn_log() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

info_log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Cleanup function for error handling
cleanup_on_error() {
    error_log "Deployment failed. Starting cleanup of partially created resources..."
    
    # Remove local files
    rm -f data-exchange-trust-policy.json
    rm -f notification-lambda.py notification-lambda.zip
    rm -f update-lambda.py update-lambda.zip
    rm -f subscriber-access-script.sh
    rm -rf sample-data/
    
    error_log "Partial cleanup completed. You may need to manually clean up AWS resources."
    exit 1
}

# Set up error trap
trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_log "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        error_log "AWS CLI version 2.0.0 or higher is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_log "AWS credentials not configured. Please run 'aws configure' or set up environment variables."
        exit 1
    fi
    
    # Check required tools
    for tool in jq zip; do
        if ! command -v "$tool" &> /dev/null; then
            error_log "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    # Check permissions
    if ! aws dataexchange list-data-sets &> /dev/null; then
        error_log "Insufficient permissions for AWS Data Exchange. Please ensure you have DataExchange permissions."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn_log "No default region configured. Using us-east-1"
    fi
    
    export PROVIDER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export DATASET_NAME="enterprise-analytics-data-${RANDOM_SUFFIX}"
    export PROVIDER_BUCKET="data-exchange-provider-${RANDOM_SUFFIX}"
    export SUBSCRIBER_BUCKET="data-exchange-subscriber-${RANDOM_SUFFIX}"
    
    # Prompt for subscriber account ID
    if [[ -z "${SUBSCRIBER_ACCOUNT_ID:-}" ]]; then
        read -p "Enter the subscriber AWS account ID (12 digits): " SUBSCRIBER_ACCOUNT_ID
        if [[ ! "$SUBSCRIBER_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
            error_log "Invalid AWS account ID format. Must be 12 digits."
            exit 1
        fi
    fi
    export SUBSCRIBER_ACCOUNT_ID
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=$AWS_REGION
PROVIDER_ACCOUNT_ID=$PROVIDER_ACCOUNT_ID
DATASET_NAME=$DATASET_NAME
PROVIDER_BUCKET=$PROVIDER_BUCKET
SUBSCRIBER_BUCKET=$SUBSCRIBER_BUCKET
SUBSCRIBER_ACCOUNT_ID=$SUBSCRIBER_ACCOUNT_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log "Environment setup completed. Using region: $AWS_REGION, Account: $PROVIDER_ACCOUNT_ID"
}

# Create S3 bucket for data provider
create_provider_bucket() {
    log "Creating provider S3 bucket: $PROVIDER_BUCKET"
    
    # Create bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb s3://$PROVIDER_BUCKET
    else
        aws s3 mb s3://$PROVIDER_BUCKET --region $AWS_REGION
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket $PROVIDER_BUCKET \
        --versioning-configuration Status=Enabled
    
    # Add bucket encryption
    aws s3api put-bucket-encryption \
        --bucket $PROVIDER_BUCKET \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    log "Provider S3 bucket created and configured successfully"
}

# Create IAM role for Data Exchange
create_iam_role() {
    log "Creating IAM role for Data Exchange operations..."
    
    # Create trust policy
    cat > data-exchange-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "dataexchange.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Check if role already exists
    if aws iam get-role --role-name DataExchangeProviderRole &> /dev/null; then
        warn_log "IAM role DataExchangeProviderRole already exists. Skipping creation."
    else
        # Create the IAM role
        aws iam create-role \
            --role-name DataExchangeProviderRole \
            --assume-role-policy-document file://data-exchange-trust-policy.json \
            --description "Role for AWS Data Exchange provider operations"
        
        # Attach necessary permissions
        aws iam attach-role-policy \
            --role-name DataExchangeProviderRole \
            --policy-arn arn:aws:iam::aws:policy/AWSDataExchangeProviderFullAccess
        
        # Wait for role to be available
        aws iam wait role-exists --role-name DataExchangeProviderRole
        
        log "IAM role created and configured successfully"
    fi
}

# Create and upload sample data
create_sample_data() {
    log "Creating and uploading sample data assets..."
    
    # Create sample data directory
    mkdir -p sample-data
    
    # Generate sample customer analytics data
    cat > sample-data/customer-analytics.csv << 'EOF'
customer_id,purchase_date,amount,category,region
C001,2024-01-15,150.50,electronics,us-east
C002,2024-01-16,89.99,books,us-west
C003,2024-01-17,299.99,clothing,eu-central
C004,2024-01-18,45.75,home,us-east
C005,2024-01-19,199.99,electronics,asia-pacific
C006,2024-01-20,325.00,electronics,us-west
C007,2024-01-21,75.25,books,eu-central
C008,2024-01-22,189.99,clothing,asia-pacific
C009,2024-01-23,99.50,home,us-east
C010,2024-01-24,249.99,electronics,us-west
EOF
    
    # Generate sample sales summary
    cat > sample-data/sales-summary.json << 'EOF'
{
    "report_date": "2024-01-31",
    "total_sales": 1675.45,
    "transaction_count": 10,
    "top_category": "electronics",
    "average_order_value": 167.55,
    "regional_breakdown": {
        "us-east": 349.75,
        "us-west": 824.48,
        "eu-central": 375.24,
        "asia-pacific": 489.98
    }
}
EOF
    
    # Upload sample data to S3
    aws s3 cp sample-data/ s3://$PROVIDER_BUCKET/analytics-data/ --recursive
    
    log "Sample data uploaded successfully"
}

# Create Data Exchange dataset
create_dataset() {
    log "Creating Data Exchange dataset..."
    
    # Create the data set
    DATASET_RESPONSE=$(aws dataexchange create-data-set \
        --asset-type S3_SNAPSHOT \
        --description "Enterprise customer analytics data for secure cross-account sharing" \
        --name "$DATASET_NAME" \
        --tags Environment=Production,DataType=Analytics,Recipe=CrossAccountSharing)
    
    # Extract and save data set ID
    export DATASET_ID=$(echo $DATASET_RESPONSE | jq -r '.Id')
    echo "DATASET_ID=$DATASET_ID" >> "${SCRIPT_DIR}/.env"
    
    log "Data set created with ID: $DATASET_ID"
}

# Create revision and import assets
create_revision_and_import() {
    log "Creating revision and importing assets..."
    
    # Create a new revision
    REVISION_RESPONSE=$(aws dataexchange create-revision \
        --data-set-id $DATASET_ID \
        --comment "Initial data revision with customer analytics and sales summary")
    
    # Extract revision ID
    export REVISION_ID=$(echo $REVISION_RESPONSE | jq -r '.Id')
    echo "REVISION_ID=$REVISION_ID" >> "${SCRIPT_DIR}/.env"
    
    # Import customer analytics CSV asset
    info_log "Importing customer analytics CSV..."
    IMPORT_JOB_CSV=$(aws dataexchange create-job \
        --type IMPORT_ASSETS_FROM_S3 \
        --details "{
            \"ImportAssetsFromS3JobDetails\": {
                \"DataSetId\": \"$DATASET_ID\",
                \"RevisionId\": \"$REVISION_ID\",
                \"AssetSources\": [
                    {
                        \"Bucket\": \"$PROVIDER_BUCKET\",
                        \"Key\": \"analytics-data/customer-analytics.csv\"
                    }
                ]
            }
        }")
    
    # Extract job ID and wait for completion
    IMPORT_JOB_ID=$(echo $IMPORT_JOB_CSV | jq -r '.Id')
    info_log "Waiting for CSV import job to complete..."
    aws dataexchange wait job-completed --job-id $IMPORT_JOB_ID
    
    # Import JSON asset
    info_log "Importing sales summary JSON..."
    IMPORT_JOB_JSON=$(aws dataexchange create-job \
        --type IMPORT_ASSETS_FROM_S3 \
        --details "{
            \"ImportAssetsFromS3JobDetails\": {
                \"DataSetId\": \"$DATASET_ID\",
                \"RevisionId\": \"$REVISION_ID\",
                \"AssetSources\": [
                    {
                        \"Bucket\": \"$PROVIDER_BUCKET\",
                        \"Key\": \"analytics-data/sales-summary.json\"
                    }
                ]
            }
        }")
    
    # Wait for second import job
    IMPORT_JOB_ID_2=$(echo $IMPORT_JOB_JSON | jq -r '.Id')
    info_log "Waiting for JSON import job to complete..."
    aws dataexchange wait job-completed --job-id $IMPORT_JOB_ID_2
    
    # Finalize the revision
    aws dataexchange update-revision \
        --data-set-id $DATASET_ID \
        --revision-id $REVISION_ID \
        --finalized
    
    log "Revision created and assets imported successfully"
}

# Create data grant for cross-account sharing
create_data_grant() {
    log "Creating data grant for subscriber account: $SUBSCRIBER_ACCOUNT_ID"
    
    # Create data grant with 1-year expiration
    DATA_GRANT_RESPONSE=$(aws dataexchange create-data-grant \
        --name "Analytics Data Grant for Account $SUBSCRIBER_ACCOUNT_ID" \
        --description "Cross-account data sharing grant for analytics data - Created by automated deployment" \
        --dataset-id $DATASET_ID \
        --recipient-account-id $SUBSCRIBER_ACCOUNT_ID \
        --ends-at "2025-12-31T23:59:59Z")
    
    # Extract and save data grant ID
    export DATA_GRANT_ID=$(echo $DATA_GRANT_RESPONSE | jq -r '.Id')
    echo "DATA_GRANT_ID=$DATA_GRANT_ID" >> "${SCRIPT_DIR}/.env"
    
    log "Data grant created with ID: $DATA_GRANT_ID"
    info_log "Share this grant ID with the subscriber: $DATA_GRANT_ID"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions for automation and notifications..."
    
    # Create notification Lambda function
    cat > notification-lambda.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Handles AWS Data Exchange events and sends notifications
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    try:
        # Parse the Data Exchange event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', 'Unknown')
        dataset_id = detail.get('dataSetId', 'Unknown')
        event_time = event.get('time', datetime.utcnow().isoformat())
        
        # Create notification message
        message = f"""
AWS Data Exchange Event Notification

Event: {event_name}
Dataset ID: {dataset_id}
Timestamp: {event_time}
Account: {detail.get('accountId', 'Unknown')}
Region: {detail.get('awsRegion', 'Unknown')}

Event Details:
{json.dumps(detail, indent=2)}

This is an automated notification from your Data Exchange monitoring system.
        """
        
        # Log the event (could be extended to send to SNS, SES, etc.)
        print(f"Data Exchange Event: {event_name}")
        print(f"Dataset: {dataset_id}")
        print("Notification logged successfully")
        
        # In a production environment, you would send this to SNS, SES, or other notification service
        # sns = boto3.client('sns')
        # topic_arn = os.environ.get('SNS_TOPIC_ARN')
        # if topic_arn:
        #     sns.publish(
        #         TopicArn=topic_arn,
        #         Message=message,
        #         Subject=f'Data Exchange Event: {event_name}'
        #     )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Notification processed successfully',
                'eventName': event_name,
                'datasetId': dataset_id
            })
        }
        
    except Exception as e:
        print(f"Error processing notification: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOF
    
    # Create update Lambda function
    cat > update-lambda.py << 'EOF'
import json
import boto3
from datetime import datetime, timedelta
import csv
import random
import os

def lambda_handler(event, context):
    """
    Automatically updates data sets with new revisions
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    dataexchange = boto3.client('dataexchange')
    s3 = boto3.client('s3')
    
    try:
        dataset_id = event.get('dataset_id')
        bucket_name = event.get('bucket_name')
        
        if not dataset_id or not bucket_name:
            raise ValueError('Missing required parameters: dataset_id and bucket_name')
        
        # Generate updated sample data
        current_date = datetime.now().strftime('%Y-%m-%d')
        current_timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # Create updated customer data
        updated_data = []
        categories = ['electronics', 'books', 'clothing', 'home', 'sports']
        regions = ['us-east', 'us-west', 'eu-central', 'asia-pacific', 'south-america']
        
        for i in range(1, 11):  # Generate 10 records
            updated_data.append([
                f'C{i:03d}',
                current_date,
                f'{random.uniform(50, 500):.2f}',
                random.choice(categories),
                random.choice(regions)
            ])
        
        # Create CSV content
        csv_content = 'customer_id,purchase_date,amount,category,region\n'
        for row in updated_data:
            csv_content += ','.join(row) + '\n'
        
        # Upload updated data to S3
        s3_key = f'analytics-data/customer-analytics-{current_timestamp}.csv'
        s3.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=csv_content,
            ContentType='text/csv'
        )
        
        print(f"Uploaded new data to s3://{bucket_name}/{s3_key}")
        
        # Create new revision
        revision_response = dataexchange.create_revision(
            DataSetId=dataset_id,
            Comment=f'Automated update - {current_date} - {current_timestamp}'
        )
        
        revision_id = revision_response['Id']
        print(f"Created revision: {revision_id}")
        
        # Import new assets
        import_job = dataexchange.create_job(
            Type='IMPORT_ASSETS_FROM_S3',
            Details={
                'ImportAssetsFromS3JobDetails': {
                    'DataSetId': dataset_id,
                    'RevisionId': revision_id,
                    'AssetSources': [
                        {
                            'Bucket': bucket_name,
                            'Key': s3_key
                        }
                    ]
                }
            }
        )
        
        import_job_id = import_job['Id']
        print(f"Started import job: {import_job_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data update initiated successfully',
                'revision_id': revision_id,
                'import_job_id': import_job_id,
                's3_key': s3_key
            })
        }
        
    except Exception as e:
        print(f"Error updating data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOF
    
    # Create deployment packages
    zip notification-lambda.zip notification-lambda.py
    zip update-lambda.zip update-lambda.py
    
    # Create notification Lambda function
    if aws lambda get-function --function-name DataExchangeNotificationHandler &> /dev/null; then
        warn_log "Notification Lambda function already exists. Updating code..."
        aws lambda update-function-code \
            --function-name DataExchangeNotificationHandler \
            --zip-file fileb://notification-lambda.zip
    else
        aws lambda create-function \
            --function-name DataExchangeNotificationHandler \
            --runtime python3.9 \
            --role arn:aws:iam::$PROVIDER_ACCOUNT_ID:role/DataExchangeProviderRole \
            --handler notification-lambda.lambda_handler \
            --zip-file fileb://notification-lambda.zip \
            --description "Handles Data Exchange events and notifications" \
            --timeout 60
    fi
    
    # Create update Lambda function
    if aws lambda get-function --function-name DataExchangeAutoUpdate &> /dev/null; then
        warn_log "Update Lambda function already exists. Updating code..."
        aws lambda update-function-code \
            --function-name DataExchangeAutoUpdate \
            --zip-file fileb://update-lambda.zip
    else
        aws lambda create-function \
            --function-name DataExchangeAutoUpdate \
            --runtime python3.9 \
            --role arn:aws:iam::$PROVIDER_ACCOUNT_ID:role/DataExchangeProviderRole \
            --handler update-lambda.lambda_handler \
            --zip-file fileb://update-lambda.zip \
            --timeout 120 \
            --description "Automatically updates data sets with new revisions"
    fi
    
    log "Lambda functions created successfully"
}

# Configure EventBridge rules
configure_eventbridge() {
    log "Configuring EventBridge rules for automation..."
    
    # Create EventBridge rule for Data Exchange events
    if aws events describe-rule --name DataExchangeEventRule &> /dev/null; then
        warn_log "EventBridge rule already exists. Updating..."
        aws events put-rule \
            --name DataExchangeEventRule \
            --event-pattern '{
                "source": ["aws.dataexchange"],
                "detail-type": ["Data Exchange Asset Import State Change"]
            }' \
            --description "Captures Data Exchange events for notifications"
    else
        aws events put-rule \
            --name DataExchangeEventRule \
            --event-pattern '{
                "source": ["aws.dataexchange"],
                "detail-type": ["Data Exchange Asset Import State Change"]
            }' \
            --description "Captures Data Exchange events for notifications"
    fi
    
    # Add Lambda function as target
    aws events put-targets \
        --rule DataExchangeEventRule \
        --targets "Id"="1","Arn"="arn:aws:lambda:$AWS_REGION:$PROVIDER_ACCOUNT_ID:function:DataExchangeNotificationHandler"
    
    # Grant EventBridge permission to invoke notification Lambda
    aws lambda add-permission \
        --function-name DataExchangeNotificationHandler \
        --statement-id DataExchangeEventPermission \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn arn:aws:events:$AWS_REGION:$PROVIDER_ACCOUNT_ID:rule/DataExchangeEventRule \
        2>/dev/null || warn_log "Permission already exists for notification Lambda"
    
    # Create scheduled rule for daily data updates
    if aws events describe-rule --name DataExchangeAutoUpdateSchedule &> /dev/null; then
        warn_log "Auto-update schedule rule already exists. Updating..."
    fi
    
    aws events put-rule \
        --name DataExchangeAutoUpdateSchedule \
        --schedule-expression "rate(24 hours)" \
        --description "Triggers daily data updates for Data Exchange"
    
    # Add Lambda function as target with input
    aws events put-targets \
        --rule DataExchangeAutoUpdateSchedule \
        --targets "Id"="1","Arn"="arn:aws:lambda:$AWS_REGION:$PROVIDER_ACCOUNT_ID:function:DataExchangeAutoUpdate","Input"="{\"dataset_id\":\"$DATASET_ID\",\"bucket_name\":\"$PROVIDER_BUCKET\"}"
    
    # Grant EventBridge permission to invoke update Lambda
    aws lambda add-permission \
        --function-name DataExchangeAutoUpdate \
        --statement-id DataExchangeSchedulePermission \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn arn:aws:events:$AWS_REGION:$PROVIDER_ACCOUNT_ID:rule/DataExchangeAutoUpdateSchedule \
        2>/dev/null || warn_log "Permission already exists for update Lambda"
    
    log "EventBridge rules configured successfully"
}

# Configure monitoring and alerts
configure_monitoring() {
    log "Configuring monitoring and alerts..."
    
    # Create CloudWatch log group for Data Exchange operations
    if aws logs describe-log-groups --log-group-name-prefix "/aws/dataexchange/operations" --query 'logGroups[0]' --output text | grep -q "None"; then
        aws logs create-log-group \
            --log-group-name /aws/dataexchange/operations \
            --retention-in-days 30
    else
        warn_log "CloudWatch log group already exists"
    fi
    
    # Create CloudWatch alarm for failed data grants (this will be a custom metric)
    aws cloudwatch put-metric-alarm \
        --alarm-name "DataExchangeFailedGrants" \
        --alarm-description "Alert when data grants fail" \
        --metric-name "FailedDataGrants" \
        --namespace "AWS/DataExchange" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --treat-missing-data notBreaching
    
    # Create custom metric filter for Lambda errors
    aws logs put-metric-filter \
        --log-group-name "/aws/lambda/DataExchangeAutoUpdate" \
        --filter-name "ErrorMetricFilter" \
        --filter-pattern "ERROR" \
        --metric-transformations \
            metricName=DataExchangeLambdaErrors,metricNamespace=CustomMetrics,metricValue=1
    
    log "Monitoring and alerts configured successfully"
}

# Create subscriber access script
create_subscriber_script() {
    log "Creating subscriber access script..."
    
    cat > subscriber-access-script.sh << 'EOF'
#!/bin/bash

# Subscriber Access Script for AWS Data Exchange
# This script helps subscribers accept data grants and export entitled data

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error_log() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info_log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Configuration
DATA_GRANT_ID="$1"
SUBSCRIBER_BUCKET="$2"

if [ -z "$DATA_GRANT_ID" ] || [ -z "$SUBSCRIBER_BUCKET" ]; then
    echo "Usage: $0 <data-grant-id> <subscriber-bucket-name>"
    echo ""
    echo "Example: $0 dgrant-12345678 my-subscriber-bucket"
    echo ""
    echo "This script will:"
    echo "1. Accept the data grant"
    echo "2. List entitled data sets"
    echo "3. Create subscriber S3 bucket if needed"
    echo "4. Export entitled assets to the bucket"
    exit 1
fi

log "Starting Data Exchange subscriber access process..."
info_log "Data Grant ID: $DATA_GRANT_ID"
info_log "Subscriber Bucket: $SUBSCRIBER_BUCKET"

# Accept the data grant
log "Accepting data grant: $DATA_GRANT_ID"
aws dataexchange accept-data-grant --data-grant-id $DATA_GRANT_ID

# Wait a moment for the grant to be processed
sleep 5

# List entitled data sets
log "Retrieving entitled data sets..."
ENTITLED_DATASETS=$(aws dataexchange list-data-sets \
    --origin ENTITLED \
    --query 'DataSets[0].Id' \
    --output text)

if [ "$ENTITLED_DATASETS" = "None" ] || [ -z "$ENTITLED_DATASETS" ]; then
    error_log "No entitled data sets found. The data grant may not be processed yet."
    exit 1
fi

info_log "Entitled to data set: $ENTITLED_DATASETS"

# Create subscriber S3 bucket if it doesn't exist
log "Ensuring subscriber bucket exists: $SUBSCRIBER_BUCKET"
aws s3 mb s3://$SUBSCRIBER_BUCKET 2>/dev/null || log "Bucket already exists or creation failed"

# List available revisions
log "Listing available revisions..."
LATEST_REVISION=$(aws dataexchange list-revisions \
    --data-set-id $ENTITLED_DATASETS \
    --query 'Revisions[0].Id' \
    --output text)

info_log "Latest revision: $LATEST_REVISION"

# Export entitled assets to subscriber bucket
log "Creating export job for entitled data..."
EXPORT_JOB_RESPONSE=$(aws dataexchange create-job \
    --type EXPORT_ASSETS_TO_S3 \
    --details "{
        \"ExportAssetsToS3JobDetails\": {
            \"DataSetId\": \"$ENTITLED_DATASETS\",
            \"RevisionId\": \"$LATEST_REVISION\",
            \"AssetDestinations\": [
                {
                    \"AssetId\": \"*\",
                    \"Bucket\": \"$SUBSCRIBER_BUCKET\",
                    \"Key\": \"imported-data/\"
                }
            ]
        }
    }")

EXPORT_JOB_ID=$(echo $EXPORT_JOB_RESPONSE | jq -r '.Id')
info_log "Export job ID: $EXPORT_JOB_ID"

log "Waiting for export job to complete..."
aws dataexchange wait job-completed --job-id $EXPORT_JOB_ID

log "✅ Data grant accepted and export completed successfully!"
info_log "Data is now available in s3://$SUBSCRIBER_BUCKET/imported-data/"

# List the exported files
log "Exported files:"
aws s3 ls s3://$SUBSCRIBER_BUCKET/imported-data/ --recursive
EOF
    
    chmod +x subscriber-access-script.sh
    
    log "Subscriber access script created successfully"
    info_log "Script location: $(pwd)/subscriber-access-script.sh"
}

# Main deployment function
main() {
    log "Starting AWS Data Exchange cross-account data sharing deployment..."
    
    # Initialize log files
    echo "Deployment started at $(date)" > "$LOG_FILE"
    echo "Error log for deployment started at $(date)" > "$ERROR_LOG"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_provider_bucket
    create_iam_role
    create_sample_data
    create_dataset
    create_revision_and_import
    create_data_grant
    create_lambda_functions
    configure_eventbridge
    configure_monitoring
    create_subscriber_script
    
    # Deployment summary
    log "🎉 Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Provider Account ID: $PROVIDER_ACCOUNT_ID"
    echo "AWS Region: $AWS_REGION"
    echo "Dataset Name: $DATASET_NAME"
    echo "Dataset ID: $DATASET_ID"
    echo "Data Grant ID: $DATA_GRANT_ID"
    echo "Provider S3 Bucket: $PROVIDER_BUCKET"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Share the Data Grant ID with your subscriber: $DATA_GRANT_ID"
    echo "2. Provide the subscriber with the subscriber-access-script.sh"
    echo "3. Monitor data sharing through CloudWatch and Data Exchange console"
    echo "4. The system will automatically update data daily via scheduled Lambda"
    echo ""
    echo "=== SUBSCRIBER INSTRUCTIONS ==="
    echo "The subscriber should run:"
    echo "./subscriber-access-script.sh $DATA_GRANT_ID <their-bucket-name>"
    echo ""
    log "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log "Deployment logs available at: $LOG_FILE"
}

# Run main function
main "$@"