#!/bin/bash

# AWS Savings Plans Recommendations with Cost Explorer - Deployment Script
# This script automates the deployment of the entire Cost Explorer analysis infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

log "Starting AWS Savings Plans Recommendations deployment..."

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
    fi
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        error "zip is not installed. Please install it first."
    fi
    
    # Check minimum 60 days of historical data
    local start_date=$(date -d '60 days ago' +%Y-%m-%d)
    local end_date=$(date -d '1 day ago' +%Y-%m-%d)
    
    info "Checking for historical cost data (last 60 days)..."
    local cost_check=$(aws ce get-cost-and-usage \
        --time-period Start=${start_date},End=${end_date} \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$cost_check" == "0" ]] || [[ "$cost_check" == "None" ]]; then
        warn "Limited historical cost data found. Savings Plans recommendations may be less accurate."
    fi
    
    log "Prerequisites check completed successfully"
}

# Set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export LAMBDA_FUNCTION_NAME="savings-plans-analyzer-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="cost-recommendations-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="SavingsPlansAnalyzerRole-${RANDOM_SUFFIX}"
    export CLOUDWATCH_DASHBOARD_NAME="SavingsPlansRecommendations-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="MonthlySavingsPlansAnalysis-${RANDOM_SUFFIX}"
    
    log "Environment variables set successfully"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Resource Suffix: $RANDOM_SUFFIX"
}

# Create S3 bucket for storing recommendations
create_s3_bucket() {
    log "Creating S3 bucket for cost recommendations..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create S3 bucket: $S3_BUCKET_NAME"
        return
    fi
    
    # Check if bucket already exists
    if aws s3 ls "s3://$S3_BUCKET_NAME" &> /dev/null; then
        warn "S3 bucket $S3_BUCKET_NAME already exists, skipping creation"
        return
    fi
    
    # Create bucket with region-specific configuration
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://$S3_BUCKET_NAME" --region "$AWS_REGION"
    else
        aws s3 mb "s3://$S3_BUCKET_NAME" --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Apply lifecycle policy to manage costs
    cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "ArchiveOldRecommendations",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "savings-plans-recommendations/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET_NAME" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    
    log "S3 bucket created successfully: $S3_BUCKET_NAME"
}

# Create IAM role for Lambda function
create_iam_role() {
    log "Creating IAM role for Cost Explorer access..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create IAM role: $IAM_ROLE_NAME"
        return
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        warn "IAM role $IAM_ROLE_NAME already exists, skipping creation"
        export ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query Role.Arn --output text)
        return
    fi
    
    # Create trust policy for Lambda
    cat > /tmp/trust-policy.json << EOF
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
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "Role for Savings Plans analyzer Lambda function"
    
    # Create comprehensive policy for Cost Explorer and Savings Plans access
    cat > /tmp/ce-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ce:GetSavingsPlansPurchaseRecommendation",
                "ce:StartSavingsPlansPurchaseRecommendationGeneration",
                "ce:GetCostAndUsage",
                "ce:GetDimensionValues",
                "ce:GetUsageReport",
                "ce:GetRightsizingRecommendation",
                "ce:GetReservationCoverage",
                "ce:GetReservationPurchaseRecommendation",
                "ce:GetReservationUtilization",
                "ce:GetCostCategories",
                "ce:ListCostCategoryDefinitions",
                "savingsplans:DescribeSavingsPlans",
                "savingsplans:DescribeSavingsPlansOfferings",
                "savingsplans:DescribeSavingsPlansOfferingRates",
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::$S3_BUCKET_NAME"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "CostExplorerAccess" \
        --policy-document file:///tmp/ce-policy.json
    
    # Attach basic Lambda execution role
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Get role ARN
    export ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query Role.Arn --output text)
    
    log "IAM role created successfully: $ROLE_ARN"
    
    # Wait for role to be available
    info "Waiting for IAM role to become available..."
    sleep 10
}

# Create Lambda function for Savings Plans analysis
create_lambda_function() {
    log "Creating Lambda function for Savings Plans analysis..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        warn "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating code..."
        
        # Update function code
        cat > /tmp/savings_analyzer.py << 'EOF'
import json
import boto3
import datetime
from decimal import Decimal
import os
import traceback

def lambda_handler(event, context):
    """
    AWS Lambda function to analyze Savings Plans recommendations
    using Cost Explorer APIs and store results in S3
    """
    print(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        ce_client = boto3.client('ce')
        s3_client = boto3.client('s3')
        
        # Define analysis parameters with defaults
        lookback_days = event.get('lookback_days', 'SIXTY_DAYS')
        term_years = event.get('term_years', 'ONE_YEAR')
        payment_option = event.get('payment_option', 'NO_UPFRONT')
        bucket_name = event.get('bucket_name', os.environ.get('S3_BUCKET_NAME'))
        
        print(f"Analysis parameters: lookback={lookback_days}, term={term_years}, payment={payment_option}")
        
        results = {
            'analysis_date': datetime.datetime.now().isoformat(),
            'parameters': {
                'lookback_days': lookback_days,
                'term_years': term_years,
                'payment_option': payment_option
            },
            'recommendations': [],
            'errors': []
        }
        
        # Analyze different Savings Plans types
        sp_types = ['COMPUTE_SP', 'EC2_INSTANCE_SP', 'SAGEMAKER_SP']
        
        for sp_type in sp_types:
            try:
                print(f"Analyzing {sp_type} recommendations...")
                
                # Get Savings Plans recommendations
                response = ce_client.get_savings_plans_purchase_recommendation(
                    SavingsPlansType=sp_type,
                    TermInYears=term_years,
                    PaymentOption=payment_option,
                    LookbackPeriodInDays=lookback_days,
                    PageSize=10
                )
                
                # Process recommendation data
                if 'SavingsPlansPurchaseRecommendation' in response:
                    rec = response['SavingsPlansPurchaseRecommendation']
                    summary = rec.get('SavingsPlansPurchaseRecommendationSummary', {})
                    
                    recommendation = {
                        'savings_plan_type': sp_type,
                        'summary': {
                            'estimated_monthly_savings': summary.get('EstimatedMonthlySavingsAmount', '0'),
                            'estimated_roi': summary.get('EstimatedROI', '0'),
                            'estimated_savings_percentage': summary.get('EstimatedSavingsPercentage', '0'),
                            'hourly_commitment': summary.get('HourlyCommitmentToPurchase', '0'),
                            'total_recommendations': summary.get('TotalRecommendationCount', '0')
                        },
                        'details': []
                    }
                    
                    # Add detailed recommendations
                    for detail in rec.get('SavingsPlansPurchaseRecommendationDetails', []):
                        recommendation['details'].append({
                            'account_id': detail.get('AccountId', ''),
                            'currency_code': detail.get('CurrencyCode', 'USD'),
                            'estimated_monthly_savings': detail.get('EstimatedMonthlySavingsAmount', '0'),
                            'estimated_roi': detail.get('EstimatedROI', '0'),
                            'hourly_commitment': detail.get('HourlyCommitmentToPurchase', '0'),
                            'upfront_cost': detail.get('UpfrontCost', '0'),
                            'savings_plans_details': detail.get('SavingsPlansDetails', {})
                        })
                    
                    results['recommendations'].append(recommendation)
                    print(f"Successfully analyzed {sp_type} - found {len(recommendation['details'])} recommendations")
                else:
                    print(f"No recommendations found for {sp_type}")
                    results['recommendations'].append({
                        'savings_plan_type': sp_type,
                        'summary': {
                            'estimated_monthly_savings': '0',
                            'estimated_roi': '0',
                            'estimated_savings_percentage': '0',
                            'hourly_commitment': '0',
                            'total_recommendations': '0'
                        },
                        'details': []
                    })
                
            except Exception as e:
                error_msg = f"Error analyzing {sp_type}: {str(e)}"
                print(error_msg)
                results['errors'].append(error_msg)
                results['recommendations'].append({
                    'savings_plan_type': sp_type,
                    'error': str(e)
                })
        
        # Calculate total potential savings
        total_monthly_savings = 0
        for rec in results['recommendations']:
            if 'error' not in rec:
                try:
                    savings = float(rec['summary']['estimated_monthly_savings'])
                    total_monthly_savings += savings
                except (ValueError, KeyError):
                    pass
        
        results['total_monthly_savings'] = total_monthly_savings
        results['annual_savings_potential'] = total_monthly_savings * 12
        
        print(f"Total monthly savings potential: ${total_monthly_savings:.2f}")
        print(f"Annual savings potential: ${total_monthly_savings * 12:.2f}")
        
        # Save results to S3
        if bucket_name:
            try:
                timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
                key = f"savings-plans-recommendations/{timestamp}.json"
                
                s3_client.put_object(
                    Bucket=bucket_name,
                    Key=key,
                    Body=json.dumps(results, indent=2, default=str),
                    ContentType='application/json',
                    ServerSideEncryption='AES256'
                )
                
                results['report_location'] = f"s3://{bucket_name}/{key}"
                print(f"Results saved to: s3://{bucket_name}/{key}")
                
            except Exception as e:
                error_msg = f"Error saving to S3: {str(e)}"
                print(error_msg)
                results['errors'].append(error_msg)
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Analysis completed successfully',
                'total_monthly_savings': total_monthly_savings,
                'annual_savings_potential': total_monthly_savings * 12,
                'recommendations_count': len([r for r in results['recommendations'] if 'error' not in r]),
                'report_location': results.get('report_location'),
                'errors': results.get('errors', [])
            }, default=str)
        }
        
    except Exception as e:
        error_msg = f"Fatal error in lambda_handler: {str(e)}"
        print(error_msg)
        print(traceback.format_exc())
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'traceback': traceback.format_exc()
            })
        }
EOF
        
        # Create deployment package
        cd /tmp
        zip -r savings-analyzer.zip savings_analyzer.py
        
        # Update function code
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://savings-analyzer.zip
        
        log "Lambda function updated successfully"
        return
    fi
    
    # Create new Lambda function
    cat > /tmp/savings_analyzer.py << 'EOF'
import json
import boto3
import datetime
from decimal import Decimal
import os
import traceback

def lambda_handler(event, context):
    """
    AWS Lambda function to analyze Savings Plans recommendations
    using Cost Explorer APIs and store results in S3
    """
    print(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        ce_client = boto3.client('ce')
        s3_client = boto3.client('s3')
        
        # Define analysis parameters with defaults
        lookback_days = event.get('lookback_days', 'SIXTY_DAYS')
        term_years = event.get('term_years', 'ONE_YEAR')
        payment_option = event.get('payment_option', 'NO_UPFRONT')
        bucket_name = event.get('bucket_name', os.environ.get('S3_BUCKET_NAME'))
        
        print(f"Analysis parameters: lookback={lookback_days}, term={term_years}, payment={payment_option}")
        
        results = {
            'analysis_date': datetime.datetime.now().isoformat(),
            'parameters': {
                'lookback_days': lookback_days,
                'term_years': term_years,
                'payment_option': payment_option
            },
            'recommendations': [],
            'errors': []
        }
        
        # Analyze different Savings Plans types
        sp_types = ['COMPUTE_SP', 'EC2_INSTANCE_SP', 'SAGEMAKER_SP']
        
        for sp_type in sp_types:
            try:
                print(f"Analyzing {sp_type} recommendations...")
                
                # Get Savings Plans recommendations
                response = ce_client.get_savings_plans_purchase_recommendation(
                    SavingsPlansType=sp_type,
                    TermInYears=term_years,
                    PaymentOption=payment_option,
                    LookbackPeriodInDays=lookback_days,
                    PageSize=10
                )
                
                # Process recommendation data
                if 'SavingsPlansPurchaseRecommendation' in response:
                    rec = response['SavingsPlansPurchaseRecommendation']
                    summary = rec.get('SavingsPlansPurchaseRecommendationSummary', {})
                    
                    recommendation = {
                        'savings_plan_type': sp_type,
                        'summary': {
                            'estimated_monthly_savings': summary.get('EstimatedMonthlySavingsAmount', '0'),
                            'estimated_roi': summary.get('EstimatedROI', '0'),
                            'estimated_savings_percentage': summary.get('EstimatedSavingsPercentage', '0'),
                            'hourly_commitment': summary.get('HourlyCommitmentToPurchase', '0'),
                            'total_recommendations': summary.get('TotalRecommendationCount', '0')
                        },
                        'details': []
                    }
                    
                    # Add detailed recommendations
                    for detail in rec.get('SavingsPlansPurchaseRecommendationDetails', []):
                        recommendation['details'].append({
                            'account_id': detail.get('AccountId', ''),
                            'currency_code': detail.get('CurrencyCode', 'USD'),
                            'estimated_monthly_savings': detail.get('EstimatedMonthlySavingsAmount', '0'),
                            'estimated_roi': detail.get('EstimatedROI', '0'),
                            'hourly_commitment': detail.get('HourlyCommitmentToPurchase', '0'),
                            'upfront_cost': detail.get('UpfrontCost', '0'),
                            'savings_plans_details': detail.get('SavingsPlansDetails', {})
                        })
                    
                    results['recommendations'].append(recommendation)
                    print(f"Successfully analyzed {sp_type} - found {len(recommendation['details'])} recommendations")
                else:
                    print(f"No recommendations found for {sp_type}")
                    results['recommendations'].append({
                        'savings_plan_type': sp_type,
                        'summary': {
                            'estimated_monthly_savings': '0',
                            'estimated_roi': '0',
                            'estimated_savings_percentage': '0',
                            'hourly_commitment': '0',
                            'total_recommendations': '0'
                        },
                        'details': []
                    })
                
            except Exception as e:
                error_msg = f"Error analyzing {sp_type}: {str(e)}"
                print(error_msg)
                results['errors'].append(error_msg)
                results['recommendations'].append({
                    'savings_plan_type': sp_type,
                    'error': str(e)
                })
        
        # Calculate total potential savings
        total_monthly_savings = 0
        for rec in results['recommendations']:
            if 'error' not in rec:
                try:
                    savings = float(rec['summary']['estimated_monthly_savings'])
                    total_monthly_savings += savings
                except (ValueError, KeyError):
                    pass
        
        results['total_monthly_savings'] = total_monthly_savings
        results['annual_savings_potential'] = total_monthly_savings * 12
        
        print(f"Total monthly savings potential: ${total_monthly_savings:.2f}")
        print(f"Annual savings potential: ${total_monthly_savings * 12:.2f}")
        
        # Save results to S3
        if bucket_name:
            try:
                timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
                key = f"savings-plans-recommendations/{timestamp}.json"
                
                s3_client.put_object(
                    Bucket=bucket_name,
                    Key=key,
                    Body=json.dumps(results, indent=2, default=str),
                    ContentType='application/json',
                    ServerSideEncryption='AES256'
                )
                
                results['report_location'] = f"s3://{bucket_name}/{key}"
                print(f"Results saved to: s3://{bucket_name}/{key}")
                
            except Exception as e:
                error_msg = f"Error saving to S3: {str(e)}"
                print(error_msg)
                results['errors'].append(error_msg)
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Analysis completed successfully',
                'total_monthly_savings': total_monthly_savings,
                'annual_savings_potential': total_monthly_savings * 12,
                'recommendations_count': len([r for r in results['recommendations'] if 'error' not in r]),
                'report_location': results.get('report_location'),
                'errors': results.get('errors', [])
            }, default=str)
        }
        
    except Exception as e:
        error_msg = f"Fatal error in lambda_handler: {str(e)}"
        print(error_msg)
        print(traceback.format_exc())
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'traceback': traceback.format_exc()
            })
        }
EOF
    
    # Create deployment package
    cd /tmp
    zip -r savings-analyzer.zip savings_analyzer.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$ROLE_ARN" \
        --handler savings_analyzer.lambda_handler \
        --zip-file fileb://savings-analyzer.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{S3_BUCKET_NAME=$S3_BUCKET_NAME}" \
        --description "Analyzes AWS Savings Plans recommendations using Cost Explorer APIs"
    
    log "Lambda function created successfully: $LAMBDA_FUNCTION_NAME"
}

# Test Lambda function
test_lambda_function() {
    log "Testing Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would test Lambda function: $LAMBDA_FUNCTION_NAME"
        return
    fi
    
    # Create test payload
    cat > /tmp/test-payload.json << EOF
{
    "lookback_days": "SIXTY_DAYS",
    "term_years": "ONE_YEAR",
    "payment_option": "NO_UPFRONT",
    "bucket_name": "$S3_BUCKET_NAME"
}
EOF
    
    # Invoke function
    info "Invoking Lambda function for test..."
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload file:///tmp/test-payload.json \
        --cli-binary-format raw-in-base64-out \
        /tmp/lambda-response.json
    
    # Check response
    if jq -e '.errorMessage' /tmp/lambda-response.json > /dev/null 2>&1; then
        error "Lambda function test failed: $(jq -r '.errorMessage' /tmp/lambda-response.json)"
    else
        local response_body=$(jq -r '.body' /tmp/lambda-response.json)
        local savings=$(echo "$response_body" | jq -r '.total_monthly_savings // 0')
        log "Lambda function test completed successfully"
        info "Monthly savings potential: \$${savings}"
    fi
}

# Set up automated EventBridge rule
setup_eventbridge_automation() {
    log "Setting up automated monthly analysis with EventBridge..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create EventBridge rule: $EVENTBRIDGE_RULE_NAME"
        return
    fi
    
    # Check if rule already exists
    if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" &> /dev/null; then
        warn "EventBridge rule $EVENTBRIDGE_RULE_NAME already exists, skipping creation"
        return
    fi
    
    # Create EventBridge rule for monthly analysis
    aws events put-rule \
        --name "$EVENTBRIDGE_RULE_NAME" \
        --schedule-expression "rate(30 days)" \
        --description "Monthly Savings Plans recommendations generation" \
        --state ENABLED
    
    # Add Lambda function as target
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "AllowEventBridgeInvoke-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}"
    
    # Create target configuration
    cat > /tmp/targets.json << EOF
[
    {
        "Id": "1",
        "Arn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
        "Input": "{\"lookback_days\": \"SIXTY_DAYS\", \"term_years\": \"ONE_YEAR\", \"payment_option\": \"NO_UPFRONT\", \"bucket_name\": \"${S3_BUCKET_NAME}\"}"
    }
]
EOF
    
    aws events put-targets \
        --rule "$EVENTBRIDGE_RULE_NAME" \
        --targets file:///tmp/targets.json
    
    log "EventBridge automation configured successfully"
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard for monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create CloudWatch dashboard: $CLOUDWATCH_DASHBOARD_NAME"
        return
    fi
    
    # Check if dashboard already exists
    if aws cloudwatch get-dashboard --dashboard-name "$CLOUDWATCH_DASHBOARD_NAME" &> /dev/null; then
        warn "CloudWatch dashboard $CLOUDWATCH_DASHBOARD_NAME already exists, updating..."
    fi
    
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
                    ["AWS/Lambda", "Duration", "FunctionName", "$LAMBDA_FUNCTION_NAME"],
                    ["AWS/Lambda", "Invocations", "FunctionName", "$LAMBDA_FUNCTION_NAME"],
                    ["AWS/Lambda", "Errors", "FunctionName", "$LAMBDA_FUNCTION_NAME"],
                    ["AWS/Lambda", "Throttles", "FunctionName", "$LAMBDA_FUNCTION_NAME"]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AWS_REGION",
                "title": "Savings Plans Analyzer Performance",
                "period": 300,
                "stat": "Average"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/lambda/$LAMBDA_FUNCTION_NAME' | fields @timestamp, @message | sort @timestamp desc | limit 50",
                "region": "$AWS_REGION",
                "title": "Recent Analysis Logs"
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
                    ["AWS/S3", "BucketSizeBytes", "BucketName", "$S3_BUCKET_NAME", "StorageType", "StandardStorage"],
                    ["AWS/S3", "NumberOfObjects", "BucketName", "$S3_BUCKET_NAME", "StorageType", "AllStorageTypes"]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AWS_REGION",
                "title": "S3 Bucket Metrics",
                "period": 86400,
                "stat": "Average"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$CLOUDWATCH_DASHBOARD_NAME" \
        --dashboard-body file:///tmp/dashboard-config.json
    
    log "CloudWatch dashboard created successfully: $CLOUDWATCH_DASHBOARD_NAME"
}

# Generate deployment summary
generate_deployment_summary() {
    log "Generating deployment summary..."
    
    local summary_file="/tmp/deployment-summary.json"
    
    cat > "$summary_file" << EOF
{
    "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "resources": {
        "lambda_function": {
            "name": "$LAMBDA_FUNCTION_NAME",
            "arn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
        },
        "iam_role": {
            "name": "$IAM_ROLE_NAME",
            "arn": "$ROLE_ARN"
        },
        "s3_bucket": {
            "name": "$S3_BUCKET_NAME",
            "arn": "arn:aws:s3:::${S3_BUCKET_NAME}"
        },
        "eventbridge_rule": {
            "name": "$EVENTBRIDGE_RULE_NAME",
            "arn": "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}"
        },
        "cloudwatch_dashboard": {
            "name": "$CLOUDWATCH_DASHBOARD_NAME",
            "url": "https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${CLOUDWATCH_DASHBOARD_NAME}"
        }
    },
    "next_steps": [
        "Review the CloudWatch dashboard for monitoring",
        "Check S3 bucket for generated reports",
        "Modify EventBridge rule schedule if needed",
        "Review Lambda function logs for any issues"
    ]
}
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        aws s3 cp "$summary_file" "s3://$S3_BUCKET_NAME/deployment-summary.json"
    fi
    
    log "Deployment completed successfully!"
    info "=== DEPLOYMENT SUMMARY ==="
    info "Lambda Function: $LAMBDA_FUNCTION_NAME"
    info "S3 Bucket: $S3_BUCKET_NAME"
    info "IAM Role: $IAM_ROLE_NAME"
    info "EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    info "CloudWatch Dashboard: $CLOUDWATCH_DASHBOARD_NAME"
    info "Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${CLOUDWATCH_DASHBOARD_NAME}"
    info "=========================="
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f /tmp/trust-policy.json
    rm -f /tmp/ce-policy.json
    rm -f /tmp/savings_analyzer.py
    rm -f /tmp/savings-analyzer.zip
    rm -f /tmp/test-payload.json
    rm -f /tmp/lambda-response.json
    rm -f /tmp/targets.json
    rm -f /tmp/dashboard-config.json
    rm -f /tmp/lifecycle-policy.json
    rm -f /tmp/deployment-summary.json
}

# Main execution
main() {
    log "Starting AWS Savings Plans Recommendations deployment..."
    
    # Run all deployment steps
    check_prerequisites
    set_environment_variables
    create_s3_bucket
    create_iam_role
    create_lambda_function
    test_lambda_function
    setup_eventbridge_automation
    create_cloudwatch_dashboard
    generate_deployment_summary
    cleanup_temp_files
    
    log "All deployment steps completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "You can now:"
        info "1. View the CloudWatch dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${CLOUDWATCH_DASHBOARD_NAME}"
        info "2. Check S3 bucket for reports: https://s3.console.aws.amazon.com/s3/buckets/${S3_BUCKET_NAME}"
        info "3. Monitor Lambda function: https://${AWS_REGION}.console.aws.amazon.com/lambda/home?region=${AWS_REGION}#/functions/${LAMBDA_FUNCTION_NAME}"
        info "4. Review EventBridge rule: https://${AWS_REGION}.console.aws.amazon.com/events/home?region=${AWS_REGION}#/rules/${EVENTBRIDGE_RULE_NAME}"
    fi
}

# Run main function
main "$@"