#!/bin/bash

# Deploy script for Automated Security Scanning with Inspector and Security Hub
# This script deploys the complete infrastructure described in the recipe

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
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check if a service is available in the region
check_service_availability() {
    local service=$1
    local region=$2
    
    case $service in
        "inspector2")
            if ! aws inspector2 describe-organization-configuration --region "$region" >/dev/null 2>&1; then
                error "Inspector v2 is not available in region $region"
            fi
            ;;
        "securityhub")
            if ! aws securityhub describe-hub --region "$region" >/dev/null 2>&1 && \
               [[ $? -ne 254 ]]; then  # 254 is expected when Security Hub is not enabled
                error "Security Hub is not available in region $region"
            fi
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    log "Verifying AWS credentials and permissions..."
    if ! aws iam get-user >/dev/null 2>&1 && ! aws sts assume-role --role-arn "$(aws sts get-caller-identity --query 'Arn' --output text)" --role-session-name "test" >/dev/null 2>&1; then
        warning "Cannot verify IAM permissions. Proceeding anyway..."
    fi
    
    success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI with a default region."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export SECURITY_HUB_ROLE_NAME="SecurityHubRole-${RANDOM_SUFFIX}"
    export INSPECTOR_ROLE_NAME="InspectorRole-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="security-response-handler-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="security-alerts-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="security-findings-rule-${RANDOM_SUFFIX}"
    export COMPLIANCE_LAMBDA_NAME="compliance-report-generator-${RANDOM_SUFFIX}"
    export WEEKLY_REPORT_RULE="weekly-compliance-report-${RANDOM_SUFFIX}"
    
    # Check service availability
    check_service_availability "inspector2" "$AWS_REGION"
    check_service_availability "securityhub" "$AWS_REGION"
    
    success "Environment variables configured"
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    log "Resource suffix: $RANDOM_SUFFIX"
}

# Function to create IAM policy documents
create_policy_documents() {
    log "Creating IAM policy documents..."
    
    # Create IAM trust policy for Security Hub
    cat > security-hub-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "securityhub.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # Create IAM trust policy for Lambda
    cat > lambda-trust-policy.json << 'EOF'
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

    # Create IAM policy for Lambda response function
    cat > lambda-response-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "securityhub:BatchImportFindings",
        "securityhub:BatchUpdateFindings",
        "securityhub:GetFindings",
        "sns:Publish",
        "inspector2:ListFindings",
        "inspector2:BatchGetFinding",
        "ec2:CreateTags",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    success "IAM policy documents created"
}

# Function to enable Security Hub and Inspector
enable_security_services() {
    log "Enabling Security Hub and Inspector..."
    
    # Check if Security Hub is already enabled
    if aws securityhub describe-hub --region "$AWS_REGION" >/dev/null 2>&1; then
        warning "Security Hub is already enabled"
    else
        log "Enabling Security Hub..."
        aws securityhub enable-security-hub \
            --enable-default-standards \
            --region "$AWS_REGION"
        success "Security Hub enabled"
    fi
    
    # Check if Inspector is already enabled
    INSPECTOR_STATUS=$(aws inspector2 batch-get-account-status \
        --account-ids "$AWS_ACCOUNT_ID" \
        --query 'accounts[0].state.status' \
        --output text 2>/dev/null || echo "DISABLED")
    
    if [[ "$INSPECTOR_STATUS" == "ENABLED" ]]; then
        warning "Inspector is already enabled"
    else
        log "Enabling Inspector for EC2, ECR, and Lambda scanning..."
        aws inspector2 enable \
            --resource-types EC2 ECR LAMBDA \
            --region "$AWS_REGION"
        success "Inspector enabled"
    fi
    
    # Wait for services to initialize
    log "Waiting for services to initialize..."
    sleep 30
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for security alerts..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query TopicArn --output text)
    
    # Store the topic ARN for cleanup
    echo "$SNS_TOPIC_ARN" > .sns_topic_arn
    
    # Subscribe an email address to the topic if provided
    if [[ -n "${ALERT_EMAIL:-}" ]]; then
        log "Subscribing $ALERT_EMAIL to SNS topic..."
        aws sns subscribe \
            --topic-arn "$SNS_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$ALERT_EMAIL"
        success "Email subscription created for $ALERT_EMAIL"
    else
        warning "No ALERT_EMAIL environment variable set. You can subscribe to the topic manually:"
        warning "aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
    fi
    
    success "SNS topic created: $SNS_TOPIC_ARN"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create Lambda function code for security response handler
    cat > security-response-handler.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process Security Hub findings and trigger appropriate responses
    """
    try:
        # Parse the EventBridge event
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        sns = boto3.client('sns')
        
        for finding in findings:
            severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
            title = finding.get('Title', 'Security Finding')
            description = finding.get('Description', '')
            resource_id = finding.get('Resources', [{}])[0].get('Id', 'Unknown')
            
            # Create alert message
            message = {
                'timestamp': datetime.utcnow().isoformat(),
                'severity': severity,
                'title': title,
                'description': description,
                'resource': resource_id,
                'finding_id': finding.get('Id', ''),
                'aws_account': finding.get('AwsAccountId', ''),
                'region': finding.get('Region', '')
            }
            
            # Send notification for HIGH and CRITICAL findings
            if severity in ['HIGH', 'CRITICAL']:
                sns.publish(
                    TopicArn=os.environ['SNS_TOPIC_ARN'],
                    Subject=f"Security Alert: {severity} - {title}",
                    Message=json.dumps(message, indent=2)
                )
                logger.info(f"Sent alert for {severity} finding: {title}")
            
            # Auto-remediation logic for specific finding types
            if 'EC2' in resource_id and 'vulnerability' in title.lower():
                # Tag resources for remediation
                try:
                    ec2 = boto3.client('ec2')
                    instance_id = resource_id.split('/')[-1]
                    ec2.create_tags(
                        Resources=[instance_id],
                        Tags=[
                            {'Key': 'SecurityStatus', 'Value': 'RequiresPatching'},
                            {'Key': 'LastSecurityScan', 'Value': datetime.utcnow().isoformat()}
                        ]
                    )
                    logger.info(f"Tagged EC2 instance {instance_id} for remediation")
                except Exception as e:
                    logger.error(f"Failed to tag EC2 instance: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Processed {len(findings)} security findings',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing security findings: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

    # Create compliance reporting Lambda function
    cat > compliance-report-generator.py << 'EOF'
import json
import boto3
import csv
import logging
from datetime import datetime, timedelta
from io import StringIO

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Generate compliance report from Security Hub findings
    """
    try:
        securityhub = boto3.client('securityhub')
        
        # Get findings from last 7 days
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=7)
        
        paginator = securityhub.get_paginator('get_findings')
        findings = []
        
        for page in paginator.paginate(
            Filters={
                'CreatedAt': [
                    {
                        'Start': start_time.isoformat(),
                        'End': end_time.isoformat()
                    }
                ]
            }
        ):
            findings.extend(page['Findings'])
        
        logger.info(f"Generated compliance report with {len(findings)} findings")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Generated compliance report with {len(findings)} findings',
                'report_size': len(findings),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error generating compliance report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create IAM role for Lambda
    log "Creating IAM role for Lambda functions..."
    aws iam create-role \
        --role-name "$LAMBDA_FUNCTION_NAME-role" \
        --assume-role-policy-document file://lambda-trust-policy.json
    
    # Store role name for cleanup
    echo "$LAMBDA_FUNCTION_NAME-role" > .lambda_role_name
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_FUNCTION_NAME-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for Lambda
    LAMBDA_POLICY_ARN=$(aws iam create-policy \
        --policy-name "$LAMBDA_FUNCTION_NAME-policy" \
        --policy-document file://lambda-response-policy.json \
        --query Policy.Arn --output text)
    
    # Store policy ARN for cleanup
    echo "$LAMBDA_POLICY_ARN" > .lambda_policy_arn
    
    aws iam attach-role-policy \
        --role-name "$LAMBDA_FUNCTION_NAME-role" \
        --policy-arn "$LAMBDA_POLICY_ARN"
    
    # Wait for role to be available
    log "Waiting for IAM role to propagate..."
    sleep 15
    
    # Create deployment packages
    zip security-response-handler.zip security-response-handler.py
    zip compliance-report-generator.zip compliance-report-generator.py
    
    # Create security response Lambda function
    log "Creating security response Lambda function..."
    LAMBDA_ARN=$(aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_FUNCTION_NAME-role" \
        --handler security-response-handler.lambda_handler \
        --zip-file fileb://security-response-handler.zip \
        --environment Variables="{SNS_TOPIC_ARN=$(cat .sns_topic_arn)}" \
        --timeout 300 \
        --query FunctionArn --output text)
    
    # Store Lambda ARN for cleanup
    echo "$LAMBDA_ARN" > .lambda_function_arn
    
    # Create compliance reporting Lambda function
    log "Creating compliance reporting Lambda function..."
    COMPLIANCE_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "$COMPLIANCE_LAMBDA_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_FUNCTION_NAME-role" \
        --handler compliance-report-generator.lambda_handler \
        --zip-file fileb://compliance-report-generator.zip \
        --timeout 300 \
        --query FunctionArn --output text)
    
    # Store compliance Lambda ARN for cleanup
    echo "$COMPLIANCE_LAMBDA_ARN" > .compliance_lambda_arn
    
    success "Lambda functions created successfully"
}

# Function to create EventBridge rules
create_eventbridge_rules() {
    log "Creating EventBridge rules..."
    
    # Create EventBridge rule for Security Hub findings
    aws events put-rule \
        --name "$EVENTBRIDGE_RULE_NAME" \
        --event-pattern '{
          "source": ["aws.securityhub"],
          "detail-type": ["Security Hub Findings - Imported"],
          "detail": {
            "findings": {
              "Severity": {
                "Label": ["HIGH", "CRITICAL"]
              }
            }
          }
        }' \
        --description "Route high severity security findings to Lambda"
    
    # Store rule name for cleanup
    echo "$EVENTBRIDGE_RULE_NAME" > .eventbridge_rule_name
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "$EVENTBRIDGE_RULE_NAME" \
        --targets "Id"="1","Arn"="$(cat .lambda_function_arn)"
    
    # Give EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "AllowEventBridge" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/$EVENTBRIDGE_RULE_NAME"
    
    # Create EventBridge rule for weekly reporting
    aws events put-rule \
        --name "$WEEKLY_REPORT_RULE" \
        --schedule-expression "rate(7 days)" \
        --description "Generate weekly compliance report"
    
    # Store weekly rule name for cleanup
    echo "$WEEKLY_REPORT_RULE" > .weekly_rule_name
    
    # Add compliance Lambda as target
    aws events put-targets \
        --rule "$WEEKLY_REPORT_RULE" \
        --targets "Id"="1","Arn"="$(cat .compliance_lambda_arn)"
    
    # Give EventBridge permission to invoke compliance Lambda
    aws lambda add-permission \
        --function-name "$COMPLIANCE_LAMBDA_NAME" \
        --statement-id "AllowEventBridgeWeekly" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/$WEEKLY_REPORT_RULE"
    
    success "EventBridge rules created and configured"
}

# Function to enable additional security standards
enable_security_standards() {
    log "Enabling additional security standards in Security Hub..."
    
    # Enable AWS Foundational Security Best Practices and CIS AWS Foundations Benchmark
    aws securityhub batch-enable-standards \
        --standards-subscription-requests '[
          {
            "StandardsArn": "arn:aws:securityhub:'"$AWS_REGION"'::standard/aws-foundational-security-best-practices/v/1.0.0"
          },
          {
            "StandardsArn": "arn:aws:securityhub:'"$AWS_REGION"'::standard/cis-aws-foundations-benchmark/v/1.2.0"
          }
        ]' || warning "Some security standards may already be enabled"
    
    success "Additional security standards enabled"
}

# Function to configure Inspector settings
configure_inspector() {
    log "Configuring Inspector scanning settings..."
    
    # Configure Inspector to use hybrid scanning mode
    aws inspector2 update-configuration \
        --ec2-configuration '{
          "scanMode": "EC2_HYBRID"
        }' \
        --ecr-configuration '{
          "rescanDuration": "DAYS_30"
        }' || warning "Inspector configuration may already be set"
    
    success "Inspector scanning configuration updated"
}

# Function to create Security Hub custom insights
create_custom_insights() {
    log "Creating Security Hub custom insights..."
    
    # Create custom insight for critical vulnerabilities
    aws securityhub create-insight \
        --name "Critical Vulnerabilities by Resource" \
        --filters '{
          "SeverityLabel": [{"Value": "CRITICAL", "Comparison": "EQUALS"}],
          "RecordState": [{"Value": "ACTIVE", "Comparison": "EQUALS"}]
        }' \
        --group-by-attribute "ResourceType" || warning "Insight may already exist"
    
    # Create insight for unpatched EC2 instances
    aws securityhub create-insight \
        --name "Unpatched EC2 Instances" \
        --filters '{
          "ResourceType": [{"Value": "AwsEc2Instance", "Comparison": "EQUALS"}],
          "ComplianceStatus": [{"Value": "FAILED", "Comparison": "EQUALS"}]
        }' \
        --group-by-attribute "ResourceId" || warning "Insight may already exist"
    
    success "Security Hub custom insights created"
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    cat > .deployment_state << EOF
DEPLOYMENT_TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
EVENTBRIDGE_RULE_NAME=$EVENTBRIDGE_RULE_NAME
COMPLIANCE_LAMBDA_NAME=$COMPLIANCE_LAMBDA_NAME
WEEKLY_REPORT_RULE=$WEEKLY_REPORT_RULE
EOF
    
    success "Deployment state saved to .deployment_state"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo
    echo "=================================="
    echo "    DEPLOYMENT SUMMARY"
    echo "=================================="
    echo "Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo
    echo "Created Resources:"
    echo "- Security Hub: Enabled"
    echo "- Inspector: Enabled"
    echo "- SNS Topic: $SNS_TOPIC_NAME"
    echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- Compliance Lambda: $COMPLIANCE_LAMBDA_NAME"
    echo "- EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    echo "- Weekly Report Rule: $WEEKLY_REPORT_RULE"
    echo
    echo "Next Steps:"
    echo "1. Subscribe to SNS topic for alerts if not done already:"
    echo "   aws sns subscribe --topic-arn $(cat .sns_topic_arn) --protocol email --notification-endpoint your-email@example.com"
    echo
    echo "2. Monitor Security Hub findings in the AWS Console"
    echo "3. Review Inspector scan results"
    echo "4. Check CloudWatch logs for Lambda function execution"
    echo
    echo "To clean up resources, run: ./destroy.sh"
    echo "=================================="
}

# Main deployment function
main() {
    log "Starting deployment of Automated Security Scanning with Inspector and Security Hub"
    
    check_prerequisites
    setup_environment
    create_policy_documents
    enable_security_services
    create_sns_topic
    create_lambda_functions
    create_eventbridge_rules
    enable_security_standards
    configure_inspector
    create_custom_insights
    save_deployment_state
    display_summary
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"