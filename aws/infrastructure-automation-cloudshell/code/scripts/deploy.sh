#!/bin/bash

# Infrastructure Management with CloudShell PowerShell - Deployment Script
# This script deploys the serverless automation workflow using CloudShell PowerShell,
# Systems Manager, Lambda, and CloudWatch monitoring.

set -euo pipefail

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic test)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
        error "Unable to retrieve AWS account information. Check your permissions."
        exit 1
    }
    
    log "Prerequisites check passed. Account ID: ${account_id}"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    # Resource names
    export ROLE_NAME="InfraAutomationRole-${RANDOM_SUFFIX}"
    export DOCUMENT_NAME="InfrastructureHealthCheck-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="InfrastructureAutomation-${RANDOM_SUFFIX}"
    export SCHEDULE_RULE_NAME="InfrastructureHealthSchedule-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="InfrastructureAutomation-${RANDOM_SUFFIX}"
    export ALARM_NAME="InfrastructureAutomationErrors-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/automation/infrastructure-health"
    export SNS_TOPIC_NAME="automation-alerts-${RANDOM_SUFFIX}"
    
    log "Environment configured for region: ${AWS_REGION}"
    info "Using random suffix: ${RANDOM_SUFFIX}"
}

# Create IAM role for automation
create_iam_role() {
    log "Creating IAM role for automation..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        warn "IAM role $ROLE_NAME already exists. Skipping creation."
        export AUTOMATION_ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
        return 0
    fi
    
    # Create assume role policy document
    cat > /tmp/assume-role-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": ["lambda.amazonaws.com", "ssm.amazonaws.com"]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/assume-role-policy.json \
        --description "Role for CloudShell PowerShell infrastructure automation" \
        --tags Key=Project,Value=InfrastructureAutomation Key=Environment,Value=Production
    
    # Attach necessary policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
        "arn:aws:iam::aws:policy/CloudWatchFullAccess"
        "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
        "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy"
        info "Attached policy: $policy"
    done
    
    # Wait for role to be available
    info "Waiting for IAM role to be ready..."
    sleep 10
    
    export AUTOMATION_ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
    log "IAM role created: $AUTOMATION_ROLE_ARN"
    
    # Clean up temporary files
    rm -f /tmp/assume-role-policy.json
}

# Create PowerShell script
create_powershell_script() {
    log "Creating PowerShell infrastructure health check script..."
    
    cat > /tmp/infrastructure-health-check.ps1 << 'EOF'
param(
    [string]$Region = (Get-DefaultAWSRegion).Region,
    [string]$LogGroup = "/aws/automation/infrastructure-health"
)

# Function to write structured logs
function Write-AutomationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    $logEntry = @{
        timestamp = $timestamp
        level = $Level
        message = $Message
        region = $Region
    } | ConvertTo-Json -Compress
    
    Write-Host $logEntry
    try {
        # Send to CloudWatch Logs
        Write-CWLLogEvent -LogGroupName $LogGroup -LogStreamName "health-check-$(Get-Date -Format 'yyyy-MM-dd')" -LogEvent @{
            Message = $logEntry
            Timestamp = [DateTimeOffset]::UtcNow
        }
    } catch {
        Write-Host "Warning: Could not write to CloudWatch Logs: $($_.Exception.Message)"
    }
}

# Check EC2 instance health
function Test-EC2Health {
    Write-AutomationLog "Starting EC2 health assessment"
    try {
        $instances = Get-EC2Instance -Region $Region
        $healthReport = @()
        
        foreach ($reservation in $instances) {
            foreach ($instance in $reservation.Instances) {
                $healthStatus = @{
                    InstanceId = $instance.InstanceId
                    State = $instance.State.Name
                    Type = $instance.InstanceType
                    LaunchTime = $instance.LaunchTime
                    PublicIP = $instance.PublicIpAddress
                    PrivateIP = $instance.PrivateIpAddress
                    SecurityGroups = ($instance.SecurityGroups | ForEach-Object { $_.GroupName }) -join ","
                }
                $healthReport += $healthStatus
            }
        }
        
        Write-AutomationLog "Found $($healthReport.Count) EC2 instances"
        return $healthReport
    } catch {
        Write-AutomationLog "EC2 health check failed: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Check S3 bucket compliance
function Test-S3Compliance {
    Write-AutomationLog "Starting S3 compliance assessment"
    try {
        $buckets = Get-S3Bucket -Region $Region
        $complianceReport = @()
        
        foreach ($bucket in $buckets) {
            try {
                $encryption = Get-S3BucketEncryption -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
                $versioning = Get-S3BucketVersioning -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
                $logging = Get-S3BucketLogging -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
                
                $complianceStatus = @{
                    BucketName = $bucket.BucketName
                    CreationDate = $bucket.CreationDate
                    EncryptionEnabled = $null -ne $encryption
                    VersioningEnabled = $versioning.Status -eq "Enabled"
                    LoggingEnabled = $null -ne $logging.LoggingEnabled
                }
                $complianceReport += $complianceStatus
            } catch {
                Write-AutomationLog "Error checking bucket $($bucket.BucketName): $($_.Exception.Message)" "WARNING"
            }
        }
        
        Write-AutomationLog "Assessed $($complianceReport.Count) S3 buckets"
        return $complianceReport
    } catch {
        Write-AutomationLog "S3 compliance check failed: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Main execution
try {
    Write-AutomationLog "Infrastructure health check started"
    
    $ec2Health = Test-EC2Health
    $s3Compliance = Test-S3Compliance
    
    $report = @{
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        Region = $Region
        EC2Health = $ec2Health
        S3Compliance = $s3Compliance
        Summary = @{
            EC2InstanceCount = $ec2Health.Count
            S3BucketCount = $s3Compliance.Count
            HealthyInstances = ($ec2Health | Where-Object { $_.State -eq "running" }).Count
            CompliantBuckets = ($s3Compliance | Where-Object { $_.EncryptionEnabled -and $_.VersioningEnabled }).Count
        }
    }
    
    # Save report to file
    $reportJson = $report | ConvertTo-Json -Depth 10
    $reportPath = "~/health-report-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
    $reportJson | Out-File -FilePath $reportPath
    
    Write-AutomationLog "Health check completed. Report saved to: $reportPath"
    Write-AutomationLog ($report.Summary | ConvertTo-Json)
    
    # Return summary for Systems Manager
    return $report.Summary
    
} catch {
    Write-AutomationLog "Health check failed: $($_.Exception.Message)" "ERROR"
    throw
}
EOF
    
    log "PowerShell script created successfully"
}

# Create Systems Manager automation document
create_automation_document() {
    log "Creating Systems Manager automation document..."
    
    # Check if document already exists
    if aws ssm describe-document --name "$DOCUMENT_NAME" &> /dev/null; then
        warn "Automation document $DOCUMENT_NAME already exists. Updating..."
        local update_action="update-document"
    else
        local update_action="create-document"
    fi
    
    # Read PowerShell script content and escape it for JSON
    local ps_script
    ps_script=$(cat /tmp/infrastructure-health-check.ps1 | jq -Rs .)
    
    # Create automation document
    cat > /tmp/automation-document.json << EOF
{
    "schemaVersion": "0.3",
    "description": "Infrastructure Health Check Automation using PowerShell",
    "assumeRole": "${AUTOMATION_ROLE_ARN}",
    "parameters": {
        "Region": {
            "type": "String",
            "description": "AWS Region for health check",
            "default": "${AWS_REGION}"
        },
        "LogGroupName": {
            "type": "String",
            "description": "CloudWatch Log Group for automation logs",
            "default": "${LOG_GROUP_NAME}"
        }
    },
    "mainSteps": [
        {
            "name": "CreateLogGroup",
            "action": "aws:executeAwsApi",
            "inputs": {
                "Service": "logs",
                "Api": "CreateLogGroup",
                "logGroupName": "{{ LogGroupName }}"
            },
            "onFailure": "Continue",
            "description": "Create CloudWatch Log Group if it doesn't exist"
        },
        {
            "name": "ExecuteHealthCheck",
            "action": "aws:executeScript",
            "inputs": {
                "Runtime": "PowerShell Core 6.0",
                "Script": ${ps_script},
                "InputPayload": {
                    "Region": "{{ Region }}",
                    "LogGroup": "{{ LogGroupName }}"
                }
            },
            "description": "Execute PowerShell infrastructure health check script"
        }
    ],
    "outputs": [
        "ExecuteHealthCheck.Payload"
    ]
}
EOF
    
    if [ "$update_action" = "create-document" ]; then
        aws ssm create-document \
            --name "$DOCUMENT_NAME" \
            --document-type "Automation" \
            --document-format "JSON" \
            --content file:///tmp/automation-document.json \
            --tags Key=Project,Value=InfrastructureAutomation
    else
        aws ssm update-document \
            --name "$DOCUMENT_NAME" \
            --content file:///tmp/automation-document.json \
            --document-version "\$LATEST" \
            --document-format "JSON"
    fi
    
    log "Systems Manager automation document created: $DOCUMENT_NAME"
    
    # Clean up temporary files
    rm -f /tmp/automation-document.json /tmp/infrastructure-health-check.ps1
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function for automation orchestration..."
    
    # Create Lambda function code
    cat > /tmp/lambda-automation.py << 'EOF'
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to orchestrate infrastructure automation
    """
    ssm = boto3.client('ssm')
    cloudwatch = boto3.client('cloudwatch')
    
    automation_document = os.environ['AUTOMATION_DOCUMENT_NAME']
    region = os.environ.get('AWS_REGION', 'us-east-1')
    
    try:
        logger.info(f"Starting automation execution for document: {automation_document}")
        
        # Execute automation document
        response = ssm.start_automation_execution(
            DocumentName=automation_document,
            Parameters={
                'Region': [region],
                'LogGroupName': ['/aws/automation/infrastructure-health']
            }
        )
        
        execution_id = response['AutomationExecutionId']
        logger.info(f"Automation execution started: {execution_id}")
        
        # Send custom metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Automation',
            MetricData=[
                {
                    'MetricName': 'AutomationExecutions',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'DocumentName',
                            'Value': automation_document
                        }
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Automation started successfully',
                'executionId': execution_id,
                'documentName': automation_document,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Automation execution failed: {str(e)}")
        
        # Send error metric
        try:
            cloudwatch.put_metric_data(
                Namespace='Infrastructure/Automation',
                MetricData=[
                    {
                        'MetricName': 'AutomationErrors',
                        'Value': 1,
                        'Unit': 'Count'
                    }
                ]
            )
        except Exception as metric_error:
            logger.error(f"Failed to send error metric: {str(metric_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
EOF
    
    # Create deployment package
    cd /tmp
    zip -q lambda-automation.zip lambda-automation.py
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null 2>&1; then
        warn "Lambda function $LAMBDA_FUNCTION_NAME already exists. Updating code..."
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://lambda-automation.zip
        
        aws lambda update-function-configuration \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --environment Variables="{AUTOMATION_DOCUMENT_NAME=${DOCUMENT_NAME}}"
    else
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$AUTOMATION_ROLE_ARN" \
            --handler lambda-automation.lambda_handler \
            --zip-file fileb://lambda-automation.zip \
            --timeout 300 \
            --memory-size 256 \
            --description "Infrastructure automation orchestration using PowerShell and SSM" \
            --environment Variables="{AUTOMATION_DOCUMENT_NAME=${DOCUMENT_NAME}}" \
            --tags Project=InfrastructureAutomation,Environment=Production
    fi
    
    # Wait for function to be ready
    info "Waiting for Lambda function to be ready..."
    aws lambda wait function-active --function-name "$LAMBDA_FUNCTION_NAME"
    
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query Configuration.FunctionArn --output text)
    
    log "Lambda function created: $LAMBDA_ARN"
    
    # Clean up temporary files
    rm -f /tmp/lambda-automation.py /tmp/lambda-automation.zip
    cd - > /dev/null
}

# Configure EventBridge scheduled events
configure_eventbridge() {
    log "Configuring EventBridge scheduled automation..."
    
    # Check if rule already exists
    if aws events describe-rule --name "$SCHEDULE_RULE_NAME" &> /dev/null 2>&1; then
        warn "EventBridge rule $SCHEDULE_RULE_NAME already exists. Updating..."
    fi
    
    # Create EventBridge rule for scheduled automation
    aws events put-rule \
        --name "$SCHEDULE_RULE_NAME" \
        --schedule-expression "cron(0 6 * * ? *)" \
        --description "Daily infrastructure health check at 6 AM UTC" \
        --state ENABLED \
        --tags Key=Project,Value=InfrastructureAutomation
    
    # Add Lambda as target for the rule
    aws events put-targets \
        --rule "$SCHEDULE_RULE_NAME" \
        --targets "Id"="1","Arn"="$LAMBDA_ARN"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "EventBridgeInvoke-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${SCHEDULE_RULE_NAME}" \
        2>/dev/null || warn "Permission may already exist"
    
    log "EventBridge scheduled automation configured: $SCHEDULE_RULE_NAME"
}

# Create SNS topic and CloudWatch monitoring
setup_monitoring() {
    log "Setting up CloudWatch monitoring and alerting..."
    
    # Create SNS topic for notifications
    if ! aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" &> /dev/null 2>&1; then
        aws sns create-topic --name "$SNS_TOPIC_NAME" \
            --tags Key=Project,Value=InfrastructureAutomation
        info "SNS topic created: $SNS_TOPIC_NAME"
    else
        info "SNS topic already exists: $SNS_TOPIC_NAME"
    fi
    
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    # Create CloudWatch alarm for automation failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Alert on infrastructure automation errors" \
        --metric-name AutomationErrors \
        --namespace Infrastructure/Automation \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --tags Key=Project,Value=InfrastructureAutomation
    
    # Create CloudWatch dashboard
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
                    ["Infrastructure/Automation", "AutomationExecutions"],
                    [".", "AutomationErrors"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Infrastructure Automation Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '${LOG_GROUP_NAME}'\n| fields @timestamp, level, message\n| sort @timestamp desc\n| limit 100",
                "region": "${AWS_REGION}",
                "title": "Automation Logs"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body file:///tmp/dashboard-config.json
    
    log "CloudWatch monitoring configured: $DASHBOARD_NAME"
    
    # Clean up temporary files
    rm -f /tmp/dashboard-config.json
}

# Test the automation workflow
test_automation() {
    log "Testing automation workflow..."
    
    # Test automation execution
    local execution_id
    execution_id=$(aws ssm start-automation-execution \
        --document-name "$DOCUMENT_NAME" \
        --parameters "Region=${AWS_REGION},LogGroupName=${LOG_GROUP_NAME}" \
        --query AutomationExecutionId --output text)
    
    info "Test automation execution started: $execution_id"
    
    # Wait a moment and check status
    sleep 30
    
    local status
    status=$(aws ssm describe-automation-executions \
        --filters "Key=ExecutionId,Values=${execution_id}" \
        --query "AutomationExecutions[0].AutomationExecutionStatus" --output text)
    
    info "Automation execution status: $status"
    
    # Test Lambda function invocation
    info "Testing Lambda function invocation..."
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload '{}' \
        /tmp/lambda-response.json > /dev/null
    
    local lambda_status_code
    lambda_status_code=$(cat /tmp/lambda-response.json | jq -r '.statusCode // "unknown"')
    
    if [ "$lambda_status_code" = "200" ]; then
        log "Lambda function test completed successfully"
    else
        warn "Lambda function test returned status: $lambda_status_code"
    fi
    
    # Clean up test files
    rm -f /tmp/lambda-response.json
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
    "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "awsRegion": "${AWS_REGION}",
    "awsAccountId": "${AWS_ACCOUNT_ID}",
    "randomSuffix": "${RANDOM_SUFFIX}",
    "resources": {
        "iamRole": {
            "name": "${ROLE_NAME}",
            "arn": "${AUTOMATION_ROLE_ARN}"
        },
        "automationDocument": {
            "name": "${DOCUMENT_NAME}"
        },
        "lambdaFunction": {
            "name": "${LAMBDA_FUNCTION_NAME}",
            "arn": "${LAMBDA_ARN}"
        },
        "eventBridgeRule": {
            "name": "${SCHEDULE_RULE_NAME}"
        },
        "cloudWatchDashboard": {
            "name": "${DASHBOARD_NAME}"
        },
        "cloudWatchAlarm": {
            "name": "${ALARM_NAME}"
        },
        "snsTopicArn": "${SNS_TOPIC_ARN}",
        "logGroupName": "${LOG_GROUP_NAME}"
    }
}
EOF
    
    log "Deployment information saved to deployment-info.json"
}

# Main execution
main() {
    log "Starting Infrastructure Management with CloudShell PowerShell deployment..."
    
    # Check if running in dry-run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        info "Running in dry-run mode - no resources will be created"
        return 0
    fi
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_powershell_script
    create_automation_document
    create_lambda_function
    configure_eventbridge
    setup_monitoring
    test_automation
    save_deployment_info
    
    log "Deployment completed successfully!"
    echo
    info "Resources created:"
    echo "  • IAM Role: $ROLE_NAME"
    echo "  • Automation Document: $DOCUMENT_NAME"
    echo "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  • EventBridge Rule: $SCHEDULE_RULE_NAME (scheduled for daily 6 AM UTC)"
    echo "  • CloudWatch Dashboard: $DASHBOARD_NAME"
    echo "  • CloudWatch Alarm: $ALARM_NAME"
    echo "  • SNS Topic: $SNS_TOPIC_NAME"
    echo
    info "Next steps:"
    echo "  1. Subscribe to SNS topic for notifications:"
    echo "     aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
    echo "  2. View CloudWatch dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
    echo "  3. Monitor automation logs: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/${LOG_GROUP_NAME//\//%2F}"
    echo "  4. Test automation manually: aws ssm start-automation-execution --document-name ${DOCUMENT_NAME}"
    echo
    warn "Remember to configure email notifications for the SNS topic to receive alerts!"
}

# Run main function
main "$@"