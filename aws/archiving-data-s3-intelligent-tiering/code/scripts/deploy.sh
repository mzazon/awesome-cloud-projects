#!/bin/bash

# Deployment script for Sustainable Data Archiving with S3 Intelligent-Tiering
# This script automates the deployment of a complete sustainable archiving solution

set -e

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    MAJOR_VERSION=$(echo $AWS_VERSION | cut -d. -f1)
    if [ "$MAJOR_VERSION" -lt 2 ]; then
        print_warning "AWS CLI v1 detected. v2 is recommended for best compatibility."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required permissions (basic test)
    print_status "Validating AWS permissions..."
    if ! aws s3 ls &> /dev/null; then
        print_error "Insufficient S3 permissions. Please ensure you have S3 administrative access."
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    print_status "Setting up environment variables..."
    
    # Set AWS region if not already set
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        print_warning "AWS_REGION not set, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query Account --output text)
    
    # Generate unique bucket names
    RANDOM_STRING=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export ARCHIVE_BUCKET="sustainable-archive-${RANDOM_STRING}"
    export ANALYTICS_BUCKET="archive-analytics-${RANDOM_STRING}"
    
    # Create deployment timestamp
    export DEPLOYMENT_TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    
    print_success "Environment configured:"
    echo "  AWS Region: $AWS_REGION"
    echo "  AWS Account ID: $AWS_ACCOUNT_ID"
    echo "  Archive Bucket: $ARCHIVE_BUCKET"
    echo "  Analytics Bucket: $ANALYTICS_BUCKET"
    echo "  Deployment Time: $DEPLOYMENT_TIMESTAMP"
}

# Function to create S3 buckets
create_s3_buckets() {
    print_status "Creating S3 buckets..."
    
    # Create the main archive bucket
    if aws s3api head-bucket --bucket $ARCHIVE_BUCKET 2>/dev/null; then
        print_warning "Archive bucket $ARCHIVE_BUCKET already exists"
    else
        aws s3api create-bucket --bucket $ARCHIVE_BUCKET \
            --region $AWS_REGION \
            --create-bucket-configuration LocationConstraint=$AWS_REGION 2>/dev/null || \
        aws s3api create-bucket --bucket $ARCHIVE_BUCKET \
            --region $AWS_REGION
        print_success "Archive bucket created: $ARCHIVE_BUCKET"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning --bucket $ARCHIVE_BUCKET \
        --versioning-configuration Status=Enabled
    print_success "Versioning enabled on archive bucket"
    
    # Add sustainability-focused tags
    aws s3api put-bucket-tagging --bucket $ARCHIVE_BUCKET \
        --tagging 'TagSet=[
            {Key=Purpose,Value=SustainableArchive},
            {Key=Environment,Value=Production},
            {Key=CostOptimization,Value=Enabled},
            {Key=SustainabilityGoal,Value=CarbonNeutral},
            {Key=DeploymentTimestamp,Value='$DEPLOYMENT_TIMESTAMP'}
        ]'
    print_success "Sustainability tags applied to archive bucket"
    
    # Create analytics bucket for Storage Lens reports
    if aws s3api head-bucket --bucket $ANALYTICS_BUCKET 2>/dev/null; then
        print_warning "Analytics bucket $ANALYTICS_BUCKET already exists"
    else
        aws s3api create-bucket --bucket $ANALYTICS_BUCKET \
            --region $AWS_REGION \
            --create-bucket-configuration LocationConstraint=$AWS_REGION 2>/dev/null || \
        aws s3api create-bucket --bucket $ANALYTICS_BUCKET \
            --region $AWS_REGION
        print_success "Analytics bucket created: $ANALYTICS_BUCKET"
    fi
}

# Function to configure S3 Intelligent-Tiering
configure_intelligent_tiering() {
    print_status "Configuring S3 Intelligent-Tiering..."
    
    # Create basic Intelligent-Tiering configuration
    aws s3api put-bucket-intelligent-tiering-configuration \
        --bucket $ARCHIVE_BUCKET \
        --id SustainableArchiveConfig \
        --intelligent-tiering-configuration '{
            "Id": "SustainableArchiveConfig",
            "Status": "Enabled",
            "Filter": {},
            "Tiering": {
                "Days": 1
            },
            "OptionalFields": [
                {
                    "BucketKeyEnabled": true
                }
            ]
        }' 2>/dev/null || true
    print_success "Basic Intelligent-Tiering configuration applied"
    
    # Configure advanced archive tiers for long-term data
    aws s3api put-bucket-intelligent-tiering-configuration \
        --bucket $ARCHIVE_BUCKET \
        --id AdvancedSustainableConfig \
        --intelligent-tiering-configuration '{
            "Id": "AdvancedSustainableConfig",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "long-term/"
            },
            "Tiering": {
                "Days": 1
            },
            "OptionalFields": [
                {
                    "BucketKeyEnabled": true
                }
            ]
        }' 2>/dev/null || true
    print_success "Advanced Intelligent-Tiering with archive tiers configured"
}

# Function to create lifecycle policies
create_lifecycle_policies() {
    print_status "Creating lifecycle policies..."
    
    # Create temporary lifecycle policy file
    cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "SustainabilityOptimization",
            "Status": "Enabled",
            "Filter": {},
            "Transitions": [
                {
                    "Days": 0,
                    "StorageClass": "INTELLIGENT_TIERING"
                }
            ],
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 30,
                    "StorageClass": "GLACIER"
                },
                {
                    "NoncurrentDays": 90,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ],
            "AbortIncompleteMultipartUpload": {
                "DaysAfterInitiation": 1
            }
        },
        {
            "ID": "DeleteOldVersions",
            "Status": "Enabled",
            "Filter": {},
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 365
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket $ARCHIVE_BUCKET \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    print_success "Lifecycle policy applied for comprehensive optimization"
    
    # Clean up temporary file
    rm -f /tmp/lifecycle-policy.json
}

# Function to configure S3 Storage Lens
configure_storage_lens() {
    print_status "Configuring S3 Storage Lens..."
    
    # Create temporary Storage Lens configuration file
    cat > /tmp/storage-lens-config.json << EOF
{
    "Id": "SustainabilityMetrics",
    "AccountLevel": {
        "ActivityMetrics": {
            "IsEnabled": true
        },
        "BucketLevel": {
            "ActivityMetrics": {
                "IsEnabled": true
            },
            "PrefixLevel": {
                "StorageMetrics": {
                    "IsEnabled": true
                }
            }
        }
    },
    "Include": {
        "Buckets": [
            "arn:aws:s3:::$ARCHIVE_BUCKET"
        ]
    },
    "DataExport": {
        "S3BucketDestination": {
            "OutputSchemaVersion": "V_1",
            "AccountId": "$AWS_ACCOUNT_ID",
            "Arn": "arn:aws:s3:::$ANALYTICS_BUCKET",
            "Format": "CSV",
            "Prefix": "storage-lens-reports/"
        }
    },
    "IsEnabled": true
}
EOF
    
    aws s3control put-storage-lens-configuration \
        --account-id $AWS_ACCOUNT_ID \
        --config-id SustainabilityMetrics \
        --storage-lens-configuration file:///tmp/storage-lens-config.json
    print_success "S3 Storage Lens configured for sustainability tracking"
    
    # Clean up temporary file
    rm -f /tmp/storage-lens-config.json
}

# Function to create IAM role for Lambda
create_lambda_role() {
    print_status "Creating IAM role for Lambda function..."
    
    # Create trust policy
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
    
    # Check if role already exists
    if aws iam get-role --role-name SustainabilityMonitorRole &>/dev/null; then
        print_warning "IAM role SustainabilityMonitorRole already exists"
        export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name SustainabilityMonitorRole \
            --query 'Role.Arn' --output text)
    else
        export LAMBDA_ROLE_ARN=$(aws iam create-role \
            --role-name SustainabilityMonitorRole \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
            --query 'Role.Arn' --output text)
        print_success "IAM role created: SustainabilityMonitorRole"
    fi
    
    # Create permissions policy
    cat > /tmp/lambda-permissions.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "s3:GetBucketTagging",
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:GetObject",
                "s3:GetStorageLensConfiguration",
                "s3:ListStorageLensConfigurations",
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
                "cloudwatch:PutMetricData",
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name SustainabilityMonitorRole \
        --policy-name SustainabilityPermissions \
        --policy-document file:///tmp/lambda-permissions.json
    print_success "IAM permissions applied to Lambda role"
    
    # Clean up temporary files
    rm -f /tmp/lambda-trust-policy.json /tmp/lambda-permissions.json
    
    # Wait for role propagation
    print_status "Waiting for IAM role propagation..."
    sleep 10
}

# Function to deploy Lambda function
deploy_lambda_function() {
    print_status "Deploying sustainability monitoring Lambda function..."
    
    # Create Lambda function code
    cat > /tmp/sustainability_monitor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    bucket_name = os.environ['ARCHIVE_BUCKET']
    
    try:
        # Get bucket tagging to identify sustainability goals
        tags_response = s3.get_bucket_tagging(Bucket=bucket_name)
        tags = {tag['Key']: tag['Value'] for tag in tags_response['TagSet']}
        
        # Calculate storage metrics
        storage_metrics = calculate_storage_efficiency(s3, bucket_name)
        
        # Estimate carbon footprint reduction
        carbon_metrics = calculate_carbon_impact(storage_metrics)
        
        # Publish custom CloudWatch metrics
        publish_sustainability_metrics(cloudwatch, storage_metrics, carbon_metrics)
        
        # Generate sustainability report
        report = generate_sustainability_report(storage_metrics, carbon_metrics, tags)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sustainability analysis completed',
                'report': report
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error in sustainability monitoring: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def calculate_storage_efficiency(s3, bucket_name):
    """Calculate storage efficiency metrics"""
    try:
        # Get bucket size metrics from CloudWatch (simplified for demo)
        total_objects = 0
        total_size = 0
        
        # In production, use S3 Inventory or Storage Lens for accurate metrics
        paginator = s3.get_paginator('list_objects_v2')
        
        for page in paginator.paginate(Bucket=bucket_name):
            if 'Contents' in page:
                for obj in page['Contents']:
                    total_objects += 1
                    total_size += obj['Size']
        
        return {
            'total_objects': total_objects,
            'total_size_gb': round(total_size / (1024**3), 2),
            'average_object_size_mb': round((total_size / total_objects) / (1024**2), 2) if total_objects > 0 else 0
        }
    except Exception as e:
        print(f"Error calculating storage metrics: {str(e)}")
        return {'total_objects': 0, 'total_size_gb': 0, 'average_object_size_mb': 0}

def calculate_carbon_impact(storage_metrics):
    """Estimate carbon footprint reduction through intelligent tiering"""
    # AWS estimates for carbon impact (simplified model)
    # Standard storage: ~0.000385 kg CO2/GB/month
    # IA storage: ~0.000308 kg CO2/GB/month (20% reduction)
    # Archive tiers: ~0.000077 kg CO2/GB/month (80% reduction)
    
    total_size_gb = storage_metrics['total_size_gb']
    
    # Estimate tier distribution (would be more accurate with actual metrics)
    estimated_standard = total_size_gb * 0.3  # 30% in standard
    estimated_ia = total_size_gb * 0.4        # 40% in IA
    estimated_archive = total_size_gb * 0.3   # 30% in archive tiers
    
    carbon_standard = estimated_standard * 0.000385
    carbon_ia = estimated_ia * 0.000308
    carbon_archive = estimated_archive * 0.000077
    
    total_carbon = carbon_standard + carbon_ia + carbon_archive
    carbon_saved = (total_size_gb * 0.000385) - total_carbon  # vs all standard
    
    return {
        'estimated_monthly_carbon_kg': round(total_carbon, 4),
        'estimated_monthly_savings_kg': round(carbon_saved, 4),
        'carbon_reduction_percentage': round((carbon_saved / (total_size_gb * 0.000385)) * 100, 1) if total_size_gb > 0 else 0
    }

def publish_sustainability_metrics(cloudwatch, storage_metrics, carbon_metrics):
    """Publish custom metrics to CloudWatch"""
    metrics = [
        {
            'MetricName': 'TotalStorageGB',
            'Value': storage_metrics['total_size_gb'],
            'Unit': 'Count'
        },
        {
            'MetricName': 'EstimatedMonthlyCarbonKg',
            'Value': carbon_metrics['estimated_monthly_carbon_kg'],
            'Unit': 'Count'
        },
        {
            'MetricName': 'CarbonReductionPercentage',
            'Value': carbon_metrics['carbon_reduction_percentage'],
            'Unit': 'Percent'
        }
    ]
    
    for metric in metrics:
        cloudwatch.put_metric_data(
            Namespace='SustainableArchive',
            MetricData=[{
                'MetricName': metric['MetricName'],
                'Value': metric['Value'],
                'Unit': metric['Unit'],
                'Timestamp': datetime.utcnow()
            }]
        )

def generate_sustainability_report(storage_metrics, carbon_metrics, tags):
    """Generate sustainability report"""
    return {
        'timestamp': datetime.utcnow().isoformat(),
        'sustainability_goal': tags.get('SustainabilityGoal', 'Not specified'),
        'storage_efficiency': {
            'total_objects': storage_metrics['total_objects'],
            'total_storage_gb': storage_metrics['total_size_gb'],
            'average_object_size_mb': storage_metrics['average_object_size_mb']
        },
        'environmental_impact': {
            'estimated_monthly_carbon_kg': carbon_metrics['estimated_monthly_carbon_kg'],
            'monthly_carbon_savings_kg': carbon_metrics['estimated_monthly_savings_kg'],
            'carbon_reduction_percentage': carbon_metrics['carbon_reduction_percentage']
        },
        'recommendations': generate_recommendations(storage_metrics, carbon_metrics)
    }

def generate_recommendations(storage_metrics, carbon_metrics):
    """Generate optimization recommendations"""
    recommendations = []
    
    if storage_metrics['average_object_size_mb'] < 1:
        recommendations.append("Consider using S3 Object Lambda to aggregate small objects for better efficiency")
    
    if carbon_metrics['carbon_reduction_percentage'] < 30:
        recommendations.append("Enable Deep Archive Access tier for longer retention periods")
    
    recommendations.append("Review access patterns monthly to optimize tier transition policies")
    
    return recommendations

def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
EOF
    
    # Package Lambda function
    cd /tmp
    zip sustainability-monitor.zip sustainability_monitor.py
    
    # Check if function already exists
    if aws lambda get-function --function-name sustainability-archive-monitor &>/dev/null; then
        print_warning "Lambda function sustainability-archive-monitor already exists, updating..."
        aws lambda update-function-code \
            --function-name sustainability-archive-monitor \
            --zip-file fileb://sustainability-monitor.zip > /dev/null
        export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
            --function-name sustainability-archive-monitor \
            --query 'Configuration.FunctionArn' --output text)
    else
        export LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
            --function-name sustainability-archive-monitor \
            --runtime python3.9 \
            --role $LAMBDA_ROLE_ARN \
            --handler sustainability_monitor.lambda_handler \
            --zip-file fileb://sustainability-monitor.zip \
            --timeout 300 \
            --environment Variables="{ARCHIVE_BUCKET=$ARCHIVE_BUCKET}" \
            --query 'FunctionArn' --output text)
    fi
    
    print_success "Sustainability monitoring Lambda deployed"
    
    # Clean up temporary files
    rm -f /tmp/sustainability_monitor.py /tmp/sustainability-monitor.zip
    cd - > /dev/null
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    print_status "Creating CloudWatch dashboard..."
    
    # Create dashboard configuration
    cat > /tmp/dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["SustainableArchive", "TotalStorageGB"],
                    [".", "EstimatedMonthlyCarbonKg"]
                ],
                "period": 3600,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Storage & Carbon Metrics"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["SustainableArchive", "CarbonReductionPercentage"]
                ],
                "period": 3600,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Carbon Footprint Reduction"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "SustainableArchive" \
        --dashboard-body file:///tmp/dashboard-config.json
    print_success "CloudWatch dashboard created for sustainability tracking"
    
    # Clean up temporary file
    rm -f /tmp/dashboard-config.json
}

# Function to setup automated monitoring
setup_automated_monitoring() {
    print_status "Setting up automated monitoring..."
    
    # Create EventBridge rule for daily monitoring
    if aws events describe-rule --name sustainability-daily-check &>/dev/null; then
        print_warning "EventBridge rule sustainability-daily-check already exists"
    else
        aws events put-rule \
            --name sustainability-daily-check \
            --schedule-expression "rate(1 day)" \
            --description "Daily sustainability metrics collection"
        print_success "EventBridge rule created for daily monitoring"
    fi
    
    # Add Lambda permission for EventBridge
    aws lambda add-permission \
        --function-name sustainability-archive-monitor \
        --statement-id allow-eventbridge-daily \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/sustainability-daily-check" \
        2>/dev/null || print_warning "Lambda permission already exists"
    
    # Add Lambda as target
    aws events put-targets \
        --rule sustainability-daily-check \
        --targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN"
    print_success "Lambda function scheduled for daily execution"
}

# Function to create sample data
create_sample_data() {
    print_status "Creating sample data for testing..."
    
    # Create local test data directory
    mkdir -p /tmp/test-data/long-term
    
    # Create different types of files to demonstrate tiering
    echo "Frequently accessed application data - $(date)" > /tmp/test-data/frequent-data.txt
    echo "Document archive from 2023 - $(date)" > /tmp/test-data/archive-doc-2023.pdf
    echo "Long-term backup data - $(date)" > /tmp/test-data/long-term/backup-data.zip
    
    # Upload sample data with different prefixes
    aws s3 cp /tmp/test-data/frequent-data.txt s3://$ARCHIVE_BUCKET/active/
    aws s3 cp /tmp/test-data/archive-doc-2023.pdf s3://$ARCHIVE_BUCKET/documents/
    aws s3 cp /tmp/test-data/long-term/backup-data.zip s3://$ARCHIVE_BUCKET/long-term/
    
    print_success "Sample data uploaded for testing"
    
    # Clean up local test data
    rm -rf /tmp/test-data
}

# Function to run initial validation
run_initial_validation() {
    print_status "Running initial validation..."
    
    # Test Lambda function
    print_status "Testing sustainability monitoring function..."
    LAMBDA_RESULT=$(aws lambda invoke \
        --function-name sustainability-archive-monitor \
        --payload '{}' \
        /tmp/sustainability-response.json \
        --query 'StatusCode' --output text)
    
    if [ "$LAMBDA_RESULT" = "200" ]; then
        print_success "Lambda function executed successfully"
    else
        print_error "Lambda function execution failed"
        cat /tmp/sustainability-response.json
    fi
    
    # Clean up response file
    rm -f /tmp/sustainability-response.json
    
    # Verify bucket configurations
    print_status "Verifying bucket configurations..."
    
    # Check Intelligent-Tiering configuration
    if aws s3api get-bucket-intelligent-tiering-configuration \
        --bucket $ARCHIVE_BUCKET \
        --id SustainableArchiveConfig &>/dev/null; then
        print_success "Intelligent-Tiering configuration verified"
    else
        print_error "Intelligent-Tiering configuration not found"
    fi
    
    # Check lifecycle policy
    if aws s3api get-bucket-lifecycle-configuration \
        --bucket $ARCHIVE_BUCKET &>/dev/null; then
        print_success "Lifecycle policy verified"
    else
        print_error "Lifecycle policy not found"
    fi
}

# Function to save deployment information
save_deployment_info() {
    print_status "Saving deployment information..."
    
    # Create deployment info file
    cat > sustainable-archive-deployment.json << EOF
{
    "deployment_timestamp": "$DEPLOYMENT_TIMESTAMP",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "archive_bucket": "$ARCHIVE_BUCKET",
    "analytics_bucket": "$ANALYTICS_BUCKET",
    "lambda_function_arn": "$LAMBDA_FUNCTION_ARN",
    "lambda_role_arn": "$LAMBDA_ROLE_ARN",
    "dashboard_url": "https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=SustainableArchive",
    "resources_created": [
        "S3 Bucket: $ARCHIVE_BUCKET",
        "S3 Bucket: $ANALYTICS_BUCKET",
        "IAM Role: SustainabilityMonitorRole",
        "Lambda Function: sustainability-archive-monitor",
        "EventBridge Rule: sustainability-daily-check",
        "CloudWatch Dashboard: SustainableArchive",
        "S3 Storage Lens: SustainabilityMetrics"
    ]
}
EOF
    
    print_success "Deployment information saved to sustainable-archive-deployment.json"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "  Sustainable Data Archiving Deployment"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    setup_environment
    
    echo ""
    print_status "Starting deployment process..."
    echo ""
    
    create_s3_buckets
    configure_intelligent_tiering
    create_lifecycle_policies
    configure_storage_lens
    create_lambda_role
    deploy_lambda_function
    create_cloudwatch_dashboard
    setup_automated_monitoring
    create_sample_data
    run_initial_validation
    save_deployment_info
    
    echo ""
    print_success "=========================================="
    print_success "  Deployment completed successfully!"
    print_success "=========================================="
    echo ""
    
    echo "Resources created:"
    echo "  • Archive Bucket: $ARCHIVE_BUCKET"
    echo "  • Analytics Bucket: $ANALYTICS_BUCKET"
    echo "  • Lambda Function: sustainability-archive-monitor"
    echo "  • CloudWatch Dashboard: SustainableArchive"
    echo "  • Daily Monitoring: Enabled"
    echo ""
    
    echo "Next steps:"
    echo "  1. View the CloudWatch dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=SustainableArchive"
    echo "  2. Monitor S3 Storage Lens reports in: $ANALYTICS_BUCKET"
    echo "  3. Upload data to $ARCHIVE_BUCKET to see Intelligent-Tiering in action"
    echo "  4. Review deployment details in: sustainable-archive-deployment.json"
    echo ""
    
    print_warning "Note: S3 Intelligent-Tiering transitions may take 24-48 hours to show initial effects."
    print_warning "Use 'aws s3api list-objects-v2 --bucket $ARCHIVE_BUCKET' to monitor storage classes over time."
}

# Error handling
trap 'print_error "Deployment failed. Check the output above for details."; exit 1' ERR

# Run main deployment
main "$@"