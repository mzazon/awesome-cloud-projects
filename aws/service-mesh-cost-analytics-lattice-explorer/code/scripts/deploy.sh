#!/bin/bash

# deploy.sh - Deployment script for Service Mesh Cost Analytics with VPC Lattice and Cost Explorer
# Recipe: service-mesh-cost-analytics-lattice-explorer
# Version: 1.1
# Last Updated: 2025-07-12

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=${DRY_RUN:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "${LOG_FILE}"
    echo "Check ${LOG_FILE} for detailed logs"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${LOG_FILE}"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "${LOG_FILE}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        error_exit "AWS CLI version 2.0.0 or higher is required. Current version: $AWS_CLI_VERSION"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check if Cost Explorer is enabled
    if ! aws ce get-cost-and-usage \
        --time-period Start=2025-01-01,End=2025-01-02 \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --query 'ResultsByTime[0]' &> /dev/null; then
        warning "Cost Explorer may not be enabled. This can take up to 24 hours to activate."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check required permissions (basic check)
    REQUIRED_SERVICES=("iam" "lambda" "s3" "vpc-lattice" "cloudwatch" "events" "ce")
    for service in "${REQUIRED_SERVICES[@]}"; do
        case $service in
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    error_exit "Missing IAM permissions. Ensure you have rights to create IAM roles and policies."
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --max-items 1 &> /dev/null; then
                    error_exit "Missing Lambda permissions."
                fi
                ;;
            "s3")
                if ! aws s3 ls &> /dev/null; then
                    error_exit "Missing S3 permissions."
                fi
                ;;
            "vpc-lattice")
                if ! aws vpc-lattice list-service-networks --max-results 1 &> /dev/null; then
                    error_exit "Missing VPC Lattice permissions."
                fi
                ;;
        esac
    done
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # AWS configuration
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not set. Set AWS_REGION environment variable or configure AWS CLI."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Project-specific variables
    export PROJECT_NAME="lattice-cost-analytics"
    export FUNCTION_NAME="lattice-cost-processor-${RANDOM_SUFFIX}"
    export BUCKET_NAME="lattice-analytics-${RANDOM_SUFFIX}"
    export ROLE_NAME="LatticeAnalyticsRole-${RANDOM_SUFFIX}"
    export SERVICE_NETWORK_NAME="cost-demo-network-${RANDOM_SUFFIX}"
    export SERVICE_NAME="demo-service-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export PROJECT_NAME="${PROJECT_NAME}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export ROLE_NAME="${ROLE_NAME}"
export SERVICE_NETWORK_NAME="${SERVICE_NETWORK_NAME}"
export SERVICE_NAME="${SERVICE_NAME}"
EOF
    
    info "Environment configured for region: $AWS_REGION"
    info "Account ID: $AWS_ACCOUNT_ID"
    info "Resource suffix: $RANDOM_SUFFIX"
    success "Environment setup completed"
}

# Function to create IAM role and policies
create_iam_resources() {
    log "Creating IAM role and policies..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${ROLE_NAME} already exists, skipping creation"
        ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text)
        return 0
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/trust-policy.json" << 'EOF'
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
    
    # Create IAM role
    if [[ "$DRY_RUN" == "false" ]]; then
        aws iam create-role \
            --role-name "${ROLE_NAME}" \
            --assume-role-policy-document file://"${SCRIPT_DIR}/trust-policy.json" \
            --description "Role for VPC Lattice cost analytics" \
            --tags Key=Project,Value="${PROJECT_NAME}" Key=Environment,Value=demo
    fi
    
    # Store role ARN
    export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    
    # Create custom policy for cost analytics
    cat > "${SCRIPT_DIR}/cost-analytics-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "ce:GetUsageReport",
        "ce:ListCostCategoryDefinitions",
        "ce:GetCostCategories",
        "ce:GetRecommendations"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics",
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "vpc-lattice:GetService",
        "vpc-lattice:GetServiceNetwork",
        "vpc-lattice:ListServices",
        "vpc-lattice:ListServiceNetworks"
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
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF
    
    # Create and attach custom policy
    export POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LatticeAnalyticsPolicy-${RANDOM_SUFFIX}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        aws iam create-policy \
            --policy-name "LatticeAnalyticsPolicy-${RANDOM_SUFFIX}" \
            --policy-document file://"${SCRIPT_DIR}/cost-analytics-policy.json" \
            --description "Policy for VPC Lattice cost analytics"
        
        # Wait for policy to be available
        sleep 5
        
        # Attach policies to role
        aws iam attach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "${POLICY_ARN}"
        
        aws iam attach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Wait for role to be ready
        sleep 10
    fi
    
    success "IAM resources created successfully"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for analytics data..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        warning "S3 bucket ${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create S3 bucket with region-specific configuration
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://${BUCKET_NAME}"
        else
            aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${BUCKET_NAME}" \
            --versioning-configuration Status=Enabled
        
        # Configure encryption
        aws s3api put-bucket-encryption \
            --bucket "${BUCKET_NAME}" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
        
        # Apply tags
        aws s3api put-bucket-tagging \
            --bucket "${BUCKET_NAME}" \
            --tagging "TagSet=[{Key=CostCenter,Value=engineering},{Key=Project,Value=${PROJECT_NAME}},{Key=Environment,Value=demo}]"
        
        # Create folder structure
        aws s3api put-object --bucket "${BUCKET_NAME}" --key cost-reports/
        aws s3api put-object --bucket "${BUCKET_NAME}" --key metrics-data/
    fi
    
    success "S3 bucket created: ${BUCKET_NAME}"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for cost processing..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        warning "Lambda function ${FUNCTION_NAME} already exists, updating code..."
        UPDATE_EXISTING=true
    else
        UPDATE_EXISTING=false
    fi
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import datetime
from decimal import Decimal
import os

def lambda_handler(event, context):
    ce_client = boto3.client('ce')
    cw_client = boto3.client('cloudwatch')
    s3_client = boto3.client('s3')
    lattice_client = boto3.client('vpc-lattice')
    
    bucket_name = os.environ['BUCKET_NAME']
    
    # Calculate date range for cost analysis
    end_date = datetime.datetime.now().date()
    start_date = end_date - datetime.timedelta(days=7)
    
    try:
        # Get VPC Lattice service networks
        service_networks = lattice_client.list_service_networks()
        
        cost_data = {}
        
        # Query Cost Explorer for VPC Lattice related costs
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'REGION'}
            ],
            Filter={
                'Or': [
                    {
                        'Dimensions': {
                            'Key': 'SERVICE',
                            'Values': ['Amazon Virtual Private Cloud']
                        }
                    },
                    {
                        'Dimensions': {
                            'Key': 'SERVICE',
                            'Values': ['VPC Lattice', 'Amazon VPC Lattice']
                        }
                    }
                ]
            }
        )
        
        # Process cost data
        for result in response['ResultsByTime']:
            date = result['TimePeriod']['Start']
            for group in result['Groups']:
                service = group['Keys'][0]
                region = group['Keys'][1]
                amount = float(group['Metrics']['BlendedCost']['Amount'])
                
                cost_data[f"{date}_{service}_{region}"] = {
                    'date': date,
                    'service': service,
                    'region': region,
                    'cost': amount,
                    'currency': group['Metrics']['BlendedCost']['Unit']
                }
        
        # Get VPC Lattice CloudWatch metrics
        metrics_data = {}
        for network in service_networks.get('items', []):
            network_id = network['id']
            network_name = network.get('name', network_id)
            
            # Get request count metrics for service network
            try:
                metric_response = cw_client.get_metric_statistics(
                    Namespace='AWS/VpcLattice',
                    MetricName='TotalRequestCount',
                    Dimensions=[
                        {'Name': 'ServiceNetwork', 'Value': network_id}
                    ],
                    StartTime=datetime.datetime.combine(start_date, datetime.time.min),
                    EndTime=datetime.datetime.combine(end_date, datetime.time.min),
                    Period=86400,  # Daily
                    Statistics=['Sum']
                )
                
                total_requests = sum([point['Sum'] for point in metric_response['Datapoints']])
            except Exception as e:
                print(f"Warning: Could not get metrics for network {network_id}: {str(e)}")
                total_requests = 0
            
            metrics_data[network_id] = {
                'network_name': network_name,
                'request_count': total_requests
            }
        
        # Combine cost and metrics data
        analytics_report = {
            'report_date': end_date.isoformat(),
            'time_period': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            },
            'cost_data': cost_data,
            'metrics_data': metrics_data,
            'summary': {
                'total_cost': sum([item['cost'] for item in cost_data.values()]),
                'total_requests': sum([item['request_count'] for item in metrics_data.values()]),
                'cost_per_request': 0
            }
        }
        
        # Calculate cost per request if requests exist
        if analytics_report['summary']['total_requests'] > 0:
            analytics_report['summary']['cost_per_request'] = (
                analytics_report['summary']['total_cost'] / 
                analytics_report['summary']['total_requests']
            )
        
        # Store analytics report in S3
        report_key = f"cost-reports/{end_date.isoformat()}_lattice_analytics.json"
        s3_client.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(analytics_report, indent=2),
            ContentType='application/json'
        )
        
        # Create CloudWatch custom metrics
        cw_client.put_metric_data(
            Namespace='VPCLattice/CostAnalytics',
            MetricData=[
                {
                    'MetricName': 'TotalCost',
                    'Value': analytics_report['summary']['total_cost'],
                    'Unit': 'None'
                },
                {
                    'MetricName': 'TotalRequests',
                    'Value': analytics_report['summary']['total_requests'],
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'CostPerRequest',
                    'Value': analytics_report['summary']['cost_per_request'],
                    'Unit': 'None'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost analytics completed successfully',
                'report_location': f's3://{bucket_name}/{report_key}',
                'summary': analytics_report['summary']
            })
        }
        
    except Exception as e:
        print(f"Error processing cost analytics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Package Lambda function
        cd "${SCRIPT_DIR}"
        zip -q lambda-package.zip lambda_function.py
        
        if [[ "$UPDATE_EXISTING" == "true" ]]; then
            # Update existing function
            aws lambda update-function-code \
                --function-name "${FUNCTION_NAME}" \
                --zip-file fileb://lambda-package.zip
            
            aws lambda update-function-configuration \
                --function-name "${FUNCTION_NAME}" \
                --environment Variables="{BUCKET_NAME=${BUCKET_NAME}}"
        else
            # Create new function
            aws lambda create-function \
                --function-name "${FUNCTION_NAME}" \
                --runtime python3.11 \
                --role "${ROLE_ARN}" \
                --handler lambda_function.lambda_handler \
                --zip-file fileb://lambda-package.zip \
                --timeout 300 \
                --memory-size 512 \
                --environment Variables="{BUCKET_NAME=${BUCKET_NAME}}" \
                --description "VPC Lattice cost analytics processor" \
                --tags Project="${PROJECT_NAME}",Environment=demo,CostCenter=engineering
        fi
        
        # Store Lambda ARN
        export LAMBDA_ARN=$(aws lambda get-function \
            --function-name "${FUNCTION_NAME}" \
            --query 'Configuration.FunctionArn' --output text)
        
        # Clean up package file
        rm -f lambda-package.zip
    fi
    
    success "Lambda function created/updated: ${FUNCTION_NAME}"
}

# Function to create VPC Lattice resources
create_vpc_lattice_resources() {
    log "Creating VPC Lattice service network and demo service..."
    
    # Check if service network already exists
    if aws vpc-lattice list-service-networks \
        --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" \
        --output text | grep -q .; then
        warning "Service network ${SERVICE_NETWORK_NAME} already exists, skipping creation"
        export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" --output text)
    else
        if [[ "$DRY_RUN" == "false" ]]; then
            # Create VPC Lattice service network
            aws vpc-lattice create-service-network \
                --name "${SERVICE_NETWORK_NAME}" \
                --auth-type AWS_IAM \
                --tags Key=Project,Value="${PROJECT_NAME}" \
                    Key=Environment,Value=demo \
                    Key=CostCenter,Value=engineering
            
            # Wait for creation and get ID
            sleep 5
            export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
                --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" --output text)
        fi
    fi
    
    # Check if service already exists
    if aws vpc-lattice list-services \
        --query "items[?name=='${SERVICE_NAME}'].id" \
        --output text | grep -q .; then
        warning "Service ${SERVICE_NAME} already exists, skipping creation"
        export SERVICE_ID=$(aws vpc-lattice list-services \
            --query "items[?name=='${SERVICE_NAME}'].id" --output text)
    else
        if [[ "$DRY_RUN" == "false" ]]; then
            # Create sample service
            aws vpc-lattice create-service \
                --name "${SERVICE_NAME}" \
                --auth-type AWS_IAM \
                --tags Key=Project,Value="${PROJECT_NAME}" \
                    Key=ServiceType,Value=demo
            
            # Get service ID
            sleep 5
            export SERVICE_ID=$(aws vpc-lattice list-services \
                --query "items[?name=='${SERVICE_NAME}'].id" --output text)
            
            # Associate service with service network
            aws vpc-lattice create-service-network-service-association \
                --service-network-identifier "${SERVICE_NETWORK_ID}" \
                --service-identifier "${SERVICE_ID}"
        fi
    fi
    
    success "VPC Lattice resources created: ${SERVICE_NETWORK_NAME}"
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard for cost visualization..."
    
    # Create dashboard configuration
    cat > "${SCRIPT_DIR}/dashboard-config.json" << EOF
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
          [ "VPCLattice/CostAnalytics", "TotalCost" ],
          [ ".", "TotalRequests" ]
        ],
        "period": 86400,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "VPC Lattice Cost and Traffic Overview",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "VPCLattice/CostAnalytics", "CostPerRequest" ]
        ],
        "period": 86400,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "Cost Per Request Efficiency",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/VpcLattice", "TotalRequestCount", "ServiceNetwork", "${SERVICE_NETWORK_ID:-demo-network}" ],
          [ ".", "ActiveConnectionCount", ".", "." ],
          [ ".", "TotalConnectionCount", ".", "." ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "VPC Lattice Service Network Traffic Metrics"
      }
    }
  ]
}
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create CloudWatch dashboard
        aws cloudwatch put-dashboard \
            --dashboard-name "VPCLattice-CostAnalytics-${RANDOM_SUFFIX}" \
            --dashboard-body file://"${SCRIPT_DIR}/dashboard-config.json"
    fi
    
    success "CloudWatch dashboard created: VPCLattice-CostAnalytics-${RANDOM_SUFFIX}"
}

# Function to set up EventBridge automation
setup_eventbridge_automation() {
    log "Setting up automated cost analysis schedule..."
    
    # Check if rule already exists
    if aws events describe-rule --name "lattice-cost-analysis-${RANDOM_SUFFIX}" &> /dev/null; then
        warning "EventBridge rule already exists, skipping creation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create EventBridge rule
        aws events put-rule \
            --name "lattice-cost-analysis-${RANDOM_SUFFIX}" \
            --schedule-expression "rate(1 day)" \
            --description "Daily VPC Lattice cost analysis trigger" \
            --state ENABLED
        
        # Get rule ARN
        export RULE_ARN=$(aws events describe-rule \
            --name "lattice-cost-analysis-${RANDOM_SUFFIX}" \
            --query 'Arn' --output text)
        
        # Add Lambda function as target
        aws events put-targets \
            --rule "lattice-cost-analysis-${RANDOM_SUFFIX}" \
            --targets "Id"="1","Arn"="${LAMBDA_ARN}"
        
        # Grant EventBridge permission to invoke Lambda
        aws lambda add-permission \
            --function-name "${FUNCTION_NAME}" \
            --statement-id lattice-cost-analysis-trigger \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "${RULE_ARN}" || true
    fi
    
    success "Automated cost analysis scheduled for daily execution"
}

# Function to apply cost allocation tags
apply_cost_allocation_tags() {
    log "Applying cost allocation tags to resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Tag Lambda function
        aws lambda tag-resource \
            --resource "${LAMBDA_ARN}" \
            --tags CostCenter=engineering,Project="${PROJECT_NAME}",Environment=demo || true
        
        # Tag IAM role
        aws iam tag-role \
            --role-name "${ROLE_NAME}" \
            --tags Key=CostCenter,Value=engineering Key=Project,Value="${PROJECT_NAME}" || true
        
        # Tag VPC Lattice service network if it exists
        if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
            NETWORK_ARN=$(aws vpc-lattice get-service-network \
                --service-network-identifier "${SERVICE_NETWORK_ID}" \
                --query 'arn' --output text 2>/dev/null || echo "")
            
            if [[ -n "$NETWORK_ARN" ]]; then
                aws vpc-lattice tag-resource \
                    --resource-arn "${NETWORK_ARN}" \
                    --tags CostCenter=engineering,Project="${PROJECT_NAME}",Environment=demo || true
            fi
        fi
    fi
    
    success "Cost allocation tags applied to all resources"
}

# Function to run initial test
run_initial_test() {
    log "Running initial test of the cost analytics function..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Invoke Lambda function for initial test
        aws lambda invoke \
            --function-name "${FUNCTION_NAME}" \
            --payload '{}' \
            "${SCRIPT_DIR}/test-response.json"
        
        # Check if test was successful
        if grep -q '"statusCode": 200' "${SCRIPT_DIR}/test-response.json"; then
            success "Initial test completed successfully"
            cat "${SCRIPT_DIR}/test-response.json" | grep -o '"summary":[^}]*}' || true
        else
            warning "Initial test had issues. Check CloudWatch logs for details."
            cat "${SCRIPT_DIR}/test-response.json"
        fi
        
        # Clean up test response file
        rm -f "${SCRIPT_DIR}/test-response.json"
    fi
}

# Function to display deployment summary
display_summary() {
    echo
    echo "======================================"
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY 🎉"
    echo "======================================"
    echo
    echo "📊 Service Mesh Cost Analytics Resources:"
    echo "  • IAM Role: ${ROLE_NAME}"
    echo "  • Lambda Function: ${FUNCTION_NAME}"
    echo "  • S3 Bucket: ${BUCKET_NAME}"
    echo "  • Service Network: ${SERVICE_NETWORK_NAME}"
    echo "  • CloudWatch Dashboard: VPCLattice-CostAnalytics-${RANDOM_SUFFIX}"
    echo "  • EventBridge Rule: lattice-cost-analysis-${RANDOM_SUFFIX}"
    echo
    echo "🔗 Quick Links:"
    echo "  • Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=VPCLattice-CostAnalytics-${RANDOM_SUFFIX}"
    echo "  • Lambda Function: https://console.aws.amazon.com/lambda/home?region=${AWS_REGION}#/functions/${FUNCTION_NAME}"
    echo "  • S3 Bucket: https://console.aws.amazon.com/s3/buckets/${BUCKET_NAME}"
    echo "  • VPC Lattice: https://console.aws.amazon.com/vpc/home?region=${AWS_REGION}#ServiceNetworks:"
    echo
    echo "📝 Next Steps:"
    echo "  1. Wait 24 hours for comprehensive cost data collection"
    echo "  2. Monitor the CloudWatch dashboard for cost metrics"
    echo "  3. Check S3 bucket for daily cost reports"
    echo "  4. Review Lambda function logs in CloudWatch"
    echo
    echo "💰 Estimated Monthly Cost: \$15-25 (excluding service mesh traffic)"
    echo
    echo "🧹 Cleanup: Run './destroy.sh' to remove all resources"
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "⚠️  This was a DRY RUN - no resources were actually created"
    fi
}

# Main deployment function
main() {
    echo "🚀 Starting Service Mesh Cost Analytics Deployment"
    echo "=================================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 DRY RUN MODE - No resources will be created"
    fi
    
    echo "📋 Deployment started at: $(date)"
    echo "📁 Working directory: ${SCRIPT_DIR}"
    echo "📊 Log file: ${LOG_FILE}"
    echo
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_iam_resources
    create_s3_bucket
    create_lambda_function
    create_vpc_lattice_resources
    create_cloudwatch_dashboard
    setup_eventbridge_automation
    apply_cost_allocation_tags
    
    if [[ "$DRY_RUN" == "false" ]]; then
        run_initial_test
    fi
    
    display_summary
    
    log "Deployment completed successfully at $(date)"
}

# Handle script interruption
trap 'echo -e "\n${RED}Deployment interrupted. Check ${LOG_FILE} for details.${NC}"; exit 1' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--help]"
            echo "  --dry-run    Perform a dry run without creating resources"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main deployment
main "$@"