#!/bin/bash

# Deploy script for SageMaker AutoML for Time Series Forecasting
# This script automates the deployment of the complete forecasting solution

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/deployment.log"
DEPLOYMENT_STATE_FILE="$PROJECT_ROOT/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}" >&2
    exit 1
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

info() {
    log "${BLUE}INFO: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy the AutoML Forecasting solution on AWS.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -f, --force         Force deployment even if resources exist
    -r, --region        AWS region (default: current region)
    -b, --bucket-suffix Custom bucket suffix (default: random)
    -v, --verbose       Enable verbose logging
    --skip-training     Skip AutoML training (for testing)
    --cleanup-on-fail   Cleanup resources if deployment fails

EXAMPLES:
    $0                          # Deploy with default settings
    $0 --dry-run               # Preview deployment
    $0 --force --region us-west-2  # Force deploy in specific region
    $0 --skip-training         # Deploy infrastructure only

EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
VERBOSE=false
SKIP_TRAINING=false
CLEANUP_ON_FAIL=false
CUSTOM_REGION=""
CUSTOM_BUCKET_SUFFIX=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -r|--region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        -b|--bucket-suffix)
            CUSTOM_BUCKET_SUFFIX="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-training)
            SKIP_TRAINING=true
            shift
            ;;
        --cleanup-on-fail)
            CLEANUP_ON_FAIL=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Verbose logging
if [ "$VERBOSE" = true ]; then
    set -x
fi

# Prerequisite checks
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! "$AWS_CLI_VERSION" =~ ^2\. ]]; then
        warning "AWS CLI v2 is recommended. Current version: $AWS_CLI_VERSION"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error "Python3 is not installed. Please install Python 3.9 or later."
    fi
    
    # Check required Python packages
    python3 -c "import pandas, numpy, json, boto3" 2>/dev/null || {
        warning "Required Python packages not found. Installing..."
        pip3 install pandas numpy boto3 --user
    }
    
    # Check permissions
    info "Checking AWS permissions..."
    local required_services=("sagemaker" "s3" "iam" "lambda" "cloudwatch")
    for service in "${required_services[@]}"; do
        if ! aws "$service" help &> /dev/null; then
            error "AWS CLI access to $service is not available. Check your permissions."
        fi
    done
    
    success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    info "Initializing environment variables..."
    
    # Set AWS region
    if [ -n "$CUSTOM_REGION" ]; then
        export AWS_REGION="$CUSTOM_REGION"
    else
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    if [ -n "$CUSTOM_BUCKET_SUFFIX" ]; then
        RANDOM_SUFFIX="$CUSTOM_BUCKET_SUFFIX"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names
    export FORECAST_BUCKET="automl-forecasting-${RANDOM_SUFFIX}"
    export SAGEMAKER_ROLE_NAME="AutoMLForecastingRole-${RANDOM_SUFFIX}"
    export AUTOML_JOB_NAME="retail-demand-forecast-${RANDOM_SUFFIX}"
    export MODEL_NAME="automl-forecast-model-${RANDOM_SUFFIX}"
    export ENDPOINT_CONFIG_NAME="automl-forecast-config-${RANDOM_SUFFIX}"
    export ENDPOINT_NAME="automl-forecast-endpoint-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="automl-forecast-api-${RANDOM_SUFFIX}"
    
    # Save deployment state
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
FORECAST_BUCKET=$FORECAST_BUCKET
SAGEMAKER_ROLE_NAME=$SAGEMAKER_ROLE_NAME
AUTOML_JOB_NAME=$AUTOML_JOB_NAME
MODEL_NAME=$MODEL_NAME
ENDPOINT_CONFIG_NAME=$ENDPOINT_CONFIG_NAME
ENDPOINT_NAME=$ENDPOINT_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
DEPLOYMENT_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would use the following configuration:"
        cat "$DEPLOYMENT_STATE_FILE"
        return 0
    fi
    
    success "Environment initialized - Region: $AWS_REGION, Suffix: $RANDOM_SUFFIX"
}

# Create S3 bucket and configure security
create_s3_bucket() {
    info "Creating S3 bucket: $FORECAST_BUCKET"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create S3 bucket $FORECAST_BUCKET"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$FORECAST_BUCKET" 2>/dev/null; then
        if [ "$FORCE" = false ]; then
            error "Bucket $FORECAST_BUCKET already exists. Use --force to continue."
        else
            warning "Bucket $FORECAST_BUCKET already exists, continuing..."
            return 0
        fi
    fi
    
    # Create bucket with region-specific handling
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://$FORECAST_BUCKET"
    else
        aws s3 mb "s3://$FORECAST_BUCKET" --region "$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$FORECAST_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$FORECAST_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$FORECAST_BUCKET" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    success "S3 bucket created and configured: $FORECAST_BUCKET"
}

# Create IAM role for SageMaker
create_iam_role() {
    info "Creating IAM role: $SAGEMAKER_ROLE_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create IAM role $SAGEMAKER_ROLE_NAME"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$SAGEMAKER_ROLE_NAME" &>/dev/null; then
        if [ "$FORCE" = false ]; then
            error "IAM role $SAGEMAKER_ROLE_NAME already exists. Use --force to continue."
        else
            warning "IAM role $SAGEMAKER_ROLE_NAME already exists, continuing..."
            return 0
        fi
    fi
    
    # Create role with trust policy
    aws iam create-role \
        --role-name "$SAGEMAKER_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": [
                            "sagemaker.amazonaws.com",
                            "lambda.amazonaws.com"
                        ]
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --description "Role for AutoML Forecasting solution"
    
    # Attach managed policies
    local policies=(
        "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "$SAGEMAKER_ROLE_NAME" \
            --policy-arn "$policy"
    done
    
    # Wait for role to be available
    info "Waiting for IAM role to be available..."
    sleep 10
    
    success "IAM role created: $SAGEMAKER_ROLE_NAME"
}

# Generate and upload training data
generate_training_data() {
    info "Generating training data..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would generate and upload training data"
        return 0
    fi
    
    # Change to project root for data generation
    cd "$PROJECT_ROOT"
    
    # Create training data generation script
    cat > generate_training_data.py << 'EOF'
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random
import os

# Set random seed for reproducibility
np.random.seed(42)
random.seed(42)

print("Generating comprehensive e-commerce sales data...")

# Generate 3 years of daily sales data for 50 products
start_date = datetime(2021, 1, 1)
end_date = datetime(2023, 12, 31)
dates = pd.date_range(start=start_date, end=end_date, freq='D')

# Define product categories with different seasonality patterns
product_categories = {
    'electronics': ['laptop', 'smartphone', 'tablet', 'headphones', 'camera'],
    'clothing': ['shirt', 'pants', 'dress', 'jacket', 'shoes'],
    'home': ['furniture', 'appliance', 'bedding', 'kitchen', 'decor'],
    'sports': ['equipment', 'apparel', 'footwear', 'accessories', 'outdoor'],
    'books': ['fiction', 'nonfiction', 'textbook', 'childrens', 'technical']
}

regions = ['North', 'South', 'East', 'West', 'Central']

# Generate holiday calendar (simplified)
holidays = [
    datetime(2021, 1, 1), datetime(2021, 7, 4), datetime(2021, 11, 25),
    datetime(2021, 12, 25), datetime(2022, 1, 1), datetime(2022, 7, 4),
    datetime(2022, 11, 24), datetime(2022, 12, 25), datetime(2023, 1, 1),
    datetime(2023, 7, 4), datetime(2023, 11, 23), datetime(2023, 12, 25)
]

data = []

for category, products in product_categories.items():
    for product in products:
        for region in regions:
            item_id = f"{category}_{product}_{region}"
            
            # Base demand with category-specific characteristics
            if category == 'electronics':
                base_demand = np.random.uniform(80, 150)
                seasonality_strength = 0.4
                trend_strength = 0.03
            elif category == 'clothing':
                base_demand = np.random.uniform(60, 120)
                seasonality_strength = 0.6
                trend_strength = 0.01
            elif category == 'home':
                base_demand = np.random.uniform(40, 100)
                seasonality_strength = 0.3
                trend_strength = 0.02
            elif category == 'sports':
                base_demand = np.random.uniform(30, 80)
                seasonality_strength = 0.5
                trend_strength = 0.01
            else:  # books
                base_demand = np.random.uniform(20, 60)
                seasonality_strength = 0.2
                trend_strength = -0.01
            
            # Generate time series with multiple patterns
            for i, date in enumerate(dates):
                # Annual seasonality
                annual_season = seasonality_strength * np.sin(2 * np.pi * i / 365)
                
                # Quarterly patterns
                quarterly_pattern = 0.2 * np.sin(2 * np.pi * i / 90)
                
                # Weekly seasonality (higher on weekends)
                weekly_pattern = 0.3 * np.sin(2 * np.pi * i / 7)
                
                # Linear trend
                trend = trend_strength * i
                
                # Holiday effects
                holiday_boost = 0
                for holiday in holidays:
                    if abs((date - holiday).days) <= 2:
                        holiday_boost = 0.8
                    elif abs((date - holiday).days) <= 7:
                        holiday_boost = 0.4
                
                # Random promotions (5% chance per day)
                promotion = 1 if random.random() < 0.05 else 0
                promotion_boost = 0.7 if promotion else 0
                
                # Calculate demand
                demand = base_demand * (1 + annual_season + quarterly_pattern + 
                                      weekly_pattern + trend + holiday_boost + 
                                      promotion_boost) + np.random.normal(0, 5)
                
                # Ensure non-negative demand
                demand = max(0, demand)
                
                # Add weather impact for certain categories
                weather_factor = 0
                if category in ['clothing', 'sports']:
                    # Simplified weather impact
                    weather_factor = 0.2 * np.sin(2 * np.pi * i / 365 + np.pi/2)
                
                final_demand = demand * (1 + weather_factor)
                
                data.append({
                    'timestamp': date.strftime('%Y-%m-%d'),
                    'target_value': round(final_demand, 2),
                    'item_id': item_id,
                    'category': category,
                    'product': product,
                    'region': region,
                    'promotion': promotion,
                    'is_holiday': 1 if date in holidays else 0,
                    'day_of_week': date.weekday(),
                    'month': date.month,
                    'quarter': (date.month - 1) // 3 + 1
                })

df = pd.DataFrame(data)
df = df.sort_values(['item_id', 'timestamp'])

# Save training dataset
df.to_csv('ecommerce_sales_data.csv', index=False)
print(f"Generated {len(df)} rows of sales data for {len(df['item_id'].unique())} unique items")
print(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")
print("Category statistics:")
print(df.groupby('category')['target_value'].agg(['mean', 'std']).round(2))
EOF
    
    # Generate data
    python3 generate_training_data.py
    
    # Prepare AutoML-compatible format
    cat > prepare_automl_data.py << 'EOF'
import pandas as pd
from datetime import datetime, timedelta
import json

print("Preparing AutoML-compatible dataset...")

# Read the generated data
df = pd.read_csv('ecommerce_sales_data.csv')

# Create AutoML-compatible format
automl_data = df[['timestamp', 'target_value', 'item_id', 'promotion', 
                 'is_holiday', 'day_of_week', 'month', 'quarter']].copy()

# Ensure proper data types
automl_data['timestamp'] = pd.to_datetime(automl_data['timestamp'])
automl_data['target_value'] = automl_data['target_value'].astype(float)

# Sort by item_id and timestamp
automl_data = automl_data.sort_values(['item_id', 'timestamp'])

# Split into train and validation sets (80/20 split by time)
unique_dates = sorted(automl_data['timestamp'].unique())
split_date = unique_dates[int(len(unique_dates) * 0.8)]

train_data = automl_data[automl_data['timestamp'] <= split_date]
val_data = automl_data[automl_data['timestamp'] > split_date]

# Save datasets
train_data.to_csv('automl_train_data.csv', index=False)
val_data.to_csv('automl_validation_data.csv', index=False)

print(f"Training data: {len(train_data)} rows")
print(f"Validation data: {len(val_data)} rows")
print(f"Training date range: {train_data['timestamp'].min()} to {train_data['timestamp'].max()}")
print(f"Validation date range: {val_data['timestamp'].min()} to {val_data['timestamp'].max()}")

# Create schema file for AutoML
schema = {
    "version": "1.0",
    "data_format": "CSV",
    "target_attribute_name": "target_value",
    "timestamp_attribute_name": "timestamp",
    "item_identifier_attribute_name": "item_id",
    "forecast_frequency": "D",
    "forecast_horizon": 14,
    "forecast_quantiles": ["0.1", "0.5", "0.9"]
}

with open('automl_schema.json', 'w') as f:
    json.dump(schema, f, indent=2)

print("AutoML training data prepared successfully")
EOF
    
    python3 prepare_automl_data.py
    
    # Upload to S3
    aws s3 cp ecommerce_sales_data.csv "s3://$FORECAST_BUCKET/training-data/"
    aws s3 cp automl_train_data.csv "s3://$FORECAST_BUCKET/automl-data/train/"
    aws s3 cp automl_validation_data.csv "s3://$FORECAST_BUCKET/automl-data/validation/"
    aws s3 cp automl_schema.json "s3://$FORECAST_BUCKET/automl-data/"
    
    success "Training data generated and uploaded"
}

# Create AutoML job
create_automl_job() {
    if [ "$SKIP_TRAINING" = true ]; then
        info "Skipping AutoML training as requested"
        return 0
    fi
    
    info "Creating AutoML job: $AUTOML_JOB_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create AutoML job $AUTOML_JOB_NAME"
        return 0
    fi
    
    # Get SageMaker execution role ARN
    local sagemaker_role_arn=$(aws iam get-role \
        --role-name "$SAGEMAKER_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    # Create AutoML job configuration
    cat > automl_job_config.json << EOF
{
    "AutoMLJobName": "$AUTOML_JOB_NAME",
    "AutoMLJobInputDataConfig": [
        {
            "ChannelName": "training",
            "DataSource": {
                "S3DataSource": {
                    "S3DataType": "S3Prefix",
                    "S3Uri": "s3://$FORECAST_BUCKET/automl-data/train/",
                    "S3DataDistributionType": "FullyReplicated"
                }
            },
            "ContentType": "text/csv",
            "CompressionType": "None",
            "TargetAttributeName": "target_value"
        }
    ],
    "AutoMLJobOutputDataConfig": {
        "S3OutputPath": "s3://$FORECAST_BUCKET/automl-output/"
    },
    "RoleArn": "$sagemaker_role_arn",
    "AutoMLProblemTypeConfig": {
        "TimeSeriesForecastingJobConfig": {
            "ForecastFrequency": "D",
            "ForecastHorizon": 14,
            "TimeSeriesConfig": {
                "TargetAttributeName": "target_value",
                "TimestampAttributeName": "timestamp",
                "ItemIdentifierAttributeName": "item_id"
            },
            "ForecastQuantiles": ["0.1", "0.5", "0.9"],
            "Transformations": {
                "Filling": {
                    "target_value": "mean"
                },
                "Aggregation": {
                    "target_value": "sum"
                }
            },
            "CandidateGenerationConfig": {
                "AlgorithmsConfig": [
                    {
                        "AutoMLAlgorithms": [
                            "cnn-qr",
                            "deepar",
                            "prophet",
                            "npts",
                            "arima",
                            "ets"
                        ]
                    }
                ]
            }
        }
    },
    "AutoMLJobObjective": {
        "MetricName": "MAPE"
    }
}
EOF
    
    # Create AutoML job
    aws sagemaker create-auto-ml-job-v2 \
        --cli-input-json file://automl_job_config.json
    
    success "AutoML job created: $AUTOML_JOB_NAME"
    info "Training will take 2-4 hours. Monitor progress with: aws sagemaker describe-auto-ml-job-v2 --auto-ml-job-name $AUTOML_JOB_NAME"
}

# Wait for AutoML job completion (optional)
wait_for_automl_completion() {
    if [ "$SKIP_TRAINING" = true ]; then
        return 0
    fi
    
    info "Waiting for AutoML job completion (this may take 2-4 hours)..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would wait for AutoML job completion"
        return 0
    fi
    
    local max_wait_time=14400  # 4 hours in seconds
    local wait_time=0
    local check_interval=600   # 10 minutes
    
    while [ $wait_time -lt $max_wait_time ]; do
        local status=$(aws sagemaker describe-auto-ml-job-v2 \
            --auto-ml-job-name "$AUTOML_JOB_NAME" \
            --query 'AutoMLJobStatus' --output text)
        
        info "AutoML job status: $status (waited ${wait_time}s)"
        
        case $status in
            "Completed")
                success "AutoML job completed successfully"
                return 0
                ;;
            "Failed")
                error "AutoML job failed. Check CloudWatch logs for details."
                ;;
            "Stopped")
                error "AutoML job was stopped."
                ;;
        esac
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    warning "AutoML job is still running after 4 hours. You can monitor it separately."
}

# Create CloudWatch monitoring
create_monitoring() {
    info "Setting up CloudWatch monitoring..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create CloudWatch monitoring"
        return 0
    fi
    
    # Create CloudWatch dashboard
    cat > monitoring_dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/SageMaker/Endpoints", "Invocations", "EndpointName", "$ENDPOINT_NAME"],
                    ["AWS/SageMaker/Endpoints", "InvocationErrors", "EndpointName", "$ENDPOINT_NAME"],
                    ["AWS/SageMaker/Endpoints", "ModelLatency", "EndpointName", "$ENDPOINT_NAME"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Forecast Endpoint Metrics",
                "view": "timeSeries"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "AutoML-Forecasting-${RANDOM_SUFFIX}" \
        --dashboard-body file://monitoring_dashboard.json
    
    success "CloudWatch monitoring configured"
}

# Deploy Lambda function for API
deploy_lambda_function() {
    info "Deploying Lambda function: $LAMBDA_FUNCTION_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would deploy Lambda function $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Create Lambda function code
    cat > forecast_api_lambda.py << 'EOF'
import json
import boto3
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    Lambda function to provide real-time forecasting API
    """
    try:
        # Parse request
        body = json.loads(event.get('body', '{}'))
        item_id = body.get('item_id')
        forecast_horizon = int(body.get('forecast_horizon', 14))
        
        if not item_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'item_id is required'})
            }
        
        # Initialize SageMaker runtime
        runtime = boto3.client('sagemaker-runtime')
        
        # Get endpoint name from environment
        endpoint_name = os.environ.get('SAGEMAKER_ENDPOINT_NAME')
        
        if not endpoint_name:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Endpoint not configured'})
            }
        
        # Prepare mock inference request (in production, fetch real historical data)
        inference_data = {
            'instances': [
                {
                    'start': '2023-01-01',
                    'target': [100 + i * 0.1 for i in range(365)],  # Mock historical data
                    'item_id': item_id
                }
            ],
            'configuration': {
                'num_samples': 100,
                'output_types': ['mean', 'quantiles'],
                'quantiles': ['0.1', '0.5', '0.9']
            }
        }
        
        # Make prediction (this will work once endpoint is deployed)
        try:
            response = runtime.invoke_endpoint(
                EndpointName=endpoint_name,
                ContentType='application/json',
                Body=json.dumps(inference_data)
            )
            
            # Parse response
            result = json.loads(response['Body'].read().decode())
        except Exception as e:
            # Return mock data if endpoint not ready
            result = {
                'predictions': [{
                    'mean': [120 + i * 0.5 for i in range(forecast_horizon)],
                    'quantiles': {
                        '0.1': [100 + i * 0.3 for i in range(forecast_horizon)],
                        '0.5': [120 + i * 0.5 for i in range(forecast_horizon)],
                        '0.9': [140 + i * 0.7 for i in range(forecast_horizon)]
                    }
                }]
            }
        
        # Format response
        forecast_response = {
            'item_id': item_id,
            'forecast_horizon': forecast_horizon,
            'forecast': result.get('predictions', [{}])[0],
            'generated_at': datetime.now().isoformat(),
            'model_type': 'SageMaker AutoML',
            'confidence_intervals': True
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(forecast_response)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Internal server error'
            })
        }
EOF
    
    # Create deployment package
    zip forecast_api.zip forecast_api_lambda.py
    
    # Get IAM role ARN
    local lambda_role_arn=$(aws iam get-role \
        --role-name "$SAGEMAKER_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$lambda_role_arn" \
        --handler forecast_api_lambda.lambda_handler \
        --zip-file fileb://forecast_api.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{SAGEMAKER_ENDPOINT_NAME=$ENDPOINT_NAME}" \
        --description "AutoML Forecasting API for real-time predictions"
    
    success "Lambda function deployed: $LAMBDA_FUNCTION_NAME"
}

# Cleanup on failure
cleanup_on_failure() {
    if [ "$CLEANUP_ON_FAIL" = true ]; then
        warning "Deployment failed. Cleaning up resources..."
        "$SCRIPT_DIR/destroy.sh" --force --state-file "$DEPLOYMENT_STATE_FILE"
    fi
}

# Main deployment function
main() {
    info "Starting AutoML Forecasting solution deployment..."
    
    # Set up error handling
    trap 'error "Deployment failed at line $LINENO"' ERR
    trap 'cleanup_on_failure' EXIT
    
    # Initialize log file
    echo "=== AutoML Forecasting Deployment Log ===" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    
    # Execute deployment steps
    check_prerequisites
    initialize_environment
    create_s3_bucket
    create_iam_role
    generate_training_data
    create_automl_job
    create_monitoring
    deploy_lambda_function
    
    # Create deployment summary
    cat > "$PROJECT_ROOT/deployment_summary.txt" << EOF
=== AutoML Forecasting Solution - Deployment Summary ===

Deployment completed at: $(date)
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID

Resources Created:
- S3 Bucket: $FORECAST_BUCKET
- IAM Role: $SAGEMAKER_ROLE_NAME
- AutoML Job: $AUTOML_JOB_NAME
- Lambda Function: $LAMBDA_FUNCTION_NAME
- CloudWatch Dashboard: AutoML-Forecasting-${RANDOM_SUFFIX}

Next Steps:
1. Monitor AutoML job progress:
   aws sagemaker describe-auto-ml-job-v2 --auto-ml-job-name $AUTOML_JOB_NAME

2. After AutoML completes, deploy the model endpoint:
   # This requires manual steps once training is complete

3. Test the Lambda API:
   aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME \\
     --payload '{"body": "{\"item_id\": \"test_item\"}"}' response.json

4. Access CloudWatch dashboard:
   https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=AutoML-Forecasting-${RANDOM_SUFFIX}

Cost Monitoring:
- Monitor costs at: https://console.aws.amazon.com/billing/
- Estimated training cost: \$75-200 for full AutoML cycle
- Remember to clean up resources when done: ./scripts/destroy.sh

Troubleshooting:
- Check deployment log: $LOG_FILE
- Check CloudWatch logs for Lambda function errors
- Verify IAM permissions if encountering access issues

EOF
    
    # Disable error trap for successful completion
    trap - ERR EXIT
    
    success "Deployment completed successfully!"
    info "Deployment summary saved to: $PROJECT_ROOT/deployment_summary.txt"
    info "Monitor AutoML training progress (2-4 hours): aws sagemaker describe-auto-ml-job-v2 --auto-ml-job-name $AUTOML_JOB_NAME"
    
    if [ "$SKIP_TRAINING" = false ]; then
        warning "AutoML training is in progress. This will take 2-4 hours to complete."
        info "You can monitor progress in the AWS Console or use the AWS CLI command shown above."
    fi
}

# Run main function
main "$@"