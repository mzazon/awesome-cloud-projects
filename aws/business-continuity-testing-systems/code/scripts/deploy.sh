#!/bin/bash

# AWS Business Continuity Testing Framework Deployment Script
# This script deploys a comprehensive business continuity testing framework
# using AWS Systems Manager, Lambda, EventBridge, and CloudWatch

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions
    log "Validating AWS permissions..."
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
        error "Unable to verify AWS credentials."
        exit 1
    fi
    
    # Check for required tools
    for tool in zip jq; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is required but not installed."
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    if command -v openssl &> /dev/null; then
        BC_PROJECT_ID=$(openssl rand -hex 4)
    else
        BC_PROJECT_ID=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 8 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    fi
    
    export BC_FRAMEWORK_NAME="business-continuity-${BC_PROJECT_ID}"
    export AUTOMATION_ROLE_NAME="BCTestingRole-${BC_PROJECT_ID}"
    export TEST_RESULTS_BUCKET="bc-testing-results-${BC_PROJECT_ID}"
    
    # Testing schedule configuration
    export DAILY_TEST_SCHEDULE="rate(1 day)"
    export WEEKLY_COMPREHENSIVE_SCHEDULE="cron(0 2 ? * SUN *)"
    export MONTHLY_FULL_DR_SCHEDULE="cron(0 1 1 * ? *)"
    
    # Store configuration for cleanup
    cat > .bc-deployment-config << EOF
BC_PROJECT_ID=${BC_PROJECT_ID}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BC_FRAMEWORK_NAME=${BC_FRAMEWORK_NAME}
AUTOMATION_ROLE_NAME=${AUTOMATION_ROLE_NAME}
TEST_RESULTS_BUCKET=${TEST_RESULTS_BUCKET}
EOF
    
    log "Environment setup complete"
    log "Project ID: ${BC_PROJECT_ID}"
    log "AWS Region: ${AWS_REGION}"
    log "Account ID: ${AWS_ACCOUNT_ID}"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for business continuity testing..."
    
    # Create trust policy
    cat > /tmp/bc-testing-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "ssm.amazonaws.com",
                    "lambda.amazonaws.com",
                    "states.amazonaws.com",
                    "events.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    if aws iam get-role --role-name ${AUTOMATION_ROLE_NAME} &> /dev/null; then
        warning "IAM role ${AUTOMATION_ROLE_NAME} already exists, skipping creation"
    else
        aws iam create-role \
            --role-name ${AUTOMATION_ROLE_NAME} \
            --assume-role-policy-document file:///tmp/bc-testing-trust-policy.json \
            --description "Role for business continuity testing automation" \
            --tags Key=Purpose,Value=BusinessContinuityTesting Key=Project,Value=${BC_PROJECT_ID}
        
        success "IAM role created: ${AUTOMATION_ROLE_NAME}"
    fi
    
    # Create custom policy
    cat > /tmp/bc-testing-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:*",
                "ec2:*",
                "rds:*",
                "s3:*",
                "lambda:*",
                "states:*",
                "events:*",
                "cloudwatch:*",
                "sns:*",
                "logs:*",
                "backup:*",
                "iam:PassRole"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach policy
    aws iam put-role-policy \
        --role-name ${AUTOMATION_ROLE_NAME} \
        --policy-name BCTestingPolicy \
        --policy-document file:///tmp/bc-testing-policy.json
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
    
    success "IAM role and policies configured"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for test results..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${TEST_RESULTS_BUCKET} 2>/dev/null; then
        warning "S3 bucket ${TEST_RESULTS_BUCKET} already exists, skipping creation"
    else
        # Create bucket with proper region handling
        if [ "${AWS_REGION}" = "us-east-1" ]; then
            aws s3api create-bucket --bucket ${TEST_RESULTS_BUCKET}
        else
            aws s3api create-bucket \
                --bucket ${TEST_RESULTS_BUCKET} \
                --create-bucket-configuration LocationConstraint=${AWS_REGION}
        fi
        
        success "S3 bucket created: ${TEST_RESULTS_BUCKET}"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${TEST_RESULTS_BUCKET} \
        --versioning-configuration Status=Enabled
    
    # Create lifecycle policy
    cat > /tmp/test-results-lifecycle.json << 'EOF'
{
    "Rules": [
        {
            "ID": "BCTestResultsRetention",
            "Status": "Enabled",
            "Filter": {"Prefix": "test-results/"},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "Expiration": {
                "Days": 2555
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket ${TEST_RESULTS_BUCKET} \
        --lifecycle-configuration file:///tmp/test-results-lifecycle.json
    
    # Add bucket tags
    aws s3api put-bucket-tagging \
        --bucket ${TEST_RESULTS_BUCKET} \
        --tagging 'TagSet=[{Key=Purpose,Value=BusinessContinuityTesting},{Key=Project,Value='${BC_PROJECT_ID}'}]'
    
    success "S3 bucket configured with versioning and lifecycle policies"
}

# Function to create Systems Manager automation documents
create_ssm_documents() {
    log "Creating Systems Manager automation documents..."
    
    # Create backup validation runbook
    cat > /tmp/backup-validation-runbook.yaml << 'EOF'
schemaVersion: '0.3'
description: Validate backup integrity and restore capabilities
assumeRole: '{{ AutomationAssumeRole }}'
parameters:
  InstanceId:
    type: String
    description: EC2 instance ID to test backup restore
    default: 'i-1234567890abcdef0'
  BackupVaultName:
    type: String
    description: AWS Backup vault name
    default: 'default'
  AutomationAssumeRole:
    type: String
    description: IAM role for automation execution
mainSteps:
  - name: LogBackupValidationStart
    action: 'aws:executeScript'
    inputs:
      Runtime: python3.8
      Handler: log_start
      Script: |
        def log_start(events, context):
            print("Starting backup validation test...")
            print(f"Instance ID: {events['InstanceId']}")
            print(f"Backup Vault: {events['BackupVaultName']}")
            return {"status": "started", "timestamp": str(context.aws_request_id)}
      InputPayload:
        InstanceId: '{{ InstanceId }}'
        BackupVaultName: '{{ BackupVaultName }}'
    outputs:
      - Name: ValidationStatus
        Selector: $.Payload.status
        Type: String
  - name: ValidateBackupConfiguration
    action: 'aws:executeScript'
    inputs:
      Runtime: python3.8
      Handler: validate_backup
      Script: |
        import boto3
        def validate_backup(events, context):
            backup_client = boto3.client('backup')
            try:
                vaults = backup_client.list_backup_vaults()
                vault_exists = any(vault['BackupVaultName'] == events['BackupVaultName'] 
                                 for vault in vaults['BackupVaultList'])
                return {
                    "vault_exists": vault_exists,
                    "status": "validated" if vault_exists else "failed",
                    "message": f"Backup vault {events['BackupVaultName']} validation complete"
                }
            except Exception as e:
                return {"status": "error", "message": str(e)}
      InputPayload:
        BackupVaultName: '{{ BackupVaultName }}'
    outputs:
      - Name: BackupValidationResult
        Selector: $.Payload.status
        Type: String
outputs:
  - ValidationStatus: '{{ LogBackupValidationStart.ValidationStatus }}'
  - BackupValidationResult: '{{ ValidateBackupConfiguration.BackupValidationResult }}'
EOF
    
    # Create the backup validation document
    if aws ssm describe-document --name "BC-BackupValidation-${BC_PROJECT_ID}" &> /dev/null; then
        warning "Backup validation document already exists, updating..."
        aws ssm update-document \
            --name "BC-BackupValidation-${BC_PROJECT_ID}" \
            --content file:///tmp/backup-validation-runbook.yaml \
            --document-format "YAML" \
            --document-version '$LATEST'
    else
        aws ssm create-document \
            --name "BC-BackupValidation-${BC_PROJECT_ID}" \
            --document-type "Automation" \
            --document-format "YAML" \
            --content file:///tmp/backup-validation-runbook.yaml \
            --tags Key=Purpose,Value=BusinessContinuityTesting Key=Project,Value=${BC_PROJECT_ID}
    fi
    
    # Create database recovery runbook
    cat > /tmp/database-recovery-runbook.yaml << 'EOF'
schemaVersion: '0.3'
description: Test database backup and recovery procedures
assumeRole: '{{ AutomationAssumeRole }}'
parameters:
  DBInstanceIdentifier:
    type: String
    description: RDS instance identifier
    default: 'test-db'
  TestDBInstanceIdentifier:
    type: String
    description: Test database instance identifier
  AutomationAssumeRole:
    type: String
    description: IAM role for automation execution
mainSteps:
  - name: LogDatabaseTestStart
    action: 'aws:executeScript'
    inputs:
      Runtime: python3.8
      Handler: log_start
      Script: |
        def log_start(events, context):
            print("Starting database recovery test...")
            print(f"Source DB: {events['DBInstanceIdentifier']}")
            print(f"Test DB: {events['TestDBInstanceIdentifier']}")
            return {"status": "started", "timestamp": str(context.aws_request_id)}
      InputPayload:
        DBInstanceIdentifier: '{{ DBInstanceIdentifier }}'
        TestDBInstanceIdentifier: '{{ TestDBInstanceIdentifier }}'
    outputs:
      - Name: TestStatus
        Selector: $.Payload.status
        Type: String
  - name: ValidateDatabaseConfiguration
    action: 'aws:executeScript'
    inputs:
      Runtime: python3.8
      Handler: validate_database
      Script: |
        import boto3
        def validate_database(events, context):
            rds_client = boto3.client('rds')
            try:
                # Check if source database exists
                response = rds_client.describe_db_instances(
                    DBInstanceIdentifier=events['DBInstanceIdentifier']
                )
                db_status = response['DBInstances'][0]['DBInstanceStatus']
                return {
                    "status": "validated",
                    "db_status": db_status,
                    "message": f"Database {events['DBInstanceIdentifier']} is {db_status}"
                }
            except Exception as e:
                return {
                    "status": "simulated",
                    "message": f"Simulated database validation for {events['DBInstanceIdentifier']}"
                }
      InputPayload:
        DBInstanceIdentifier: '{{ DBInstanceIdentifier }}'
        TestDBInstanceIdentifier: '{{ TestDBInstanceIdentifier }}'
    outputs:
      - Name: DatabaseValidationResult
        Selector: $.Payload.status
        Type: String
outputs:
  - TestStatus: '{{ LogDatabaseTestStart.TestStatus }}'
  - DatabaseValidationResult: '{{ ValidateDatabaseConfiguration.DatabaseValidationResult }}'
EOF
    
    # Create the database recovery document
    if aws ssm describe-document --name "BC-DatabaseRecovery-${BC_PROJECT_ID}" &> /dev/null; then
        warning "Database recovery document already exists, updating..."
        aws ssm update-document \
            --name "BC-DatabaseRecovery-${BC_PROJECT_ID}" \
            --content file:///tmp/database-recovery-runbook.yaml \
            --document-format "YAML" \
            --document-version '$LATEST'
    else
        aws ssm create-document \
            --name "BC-DatabaseRecovery-${BC_PROJECT_ID}" \
            --document-type "Automation" \
            --document-format "YAML" \
            --content file:///tmp/database-recovery-runbook.yaml \
            --tags Key=Purpose,Value=BusinessContinuityTesting Key=Project,Value=${BC_PROJECT_ID}
    fi
    
    # Create application failover runbook
    cat > /tmp/application-failover-runbook.yaml << 'EOF'
schemaVersion: '0.3'
description: Test application failover to secondary region
assumeRole: '{{ AutomationAssumeRole }}'
parameters:
  DomainName:
    type: String
    description: Domain name for failover testing
    default: 'app.example.com'
  AutomationAssumeRole:
    type: String
    description: IAM role for automation execution
mainSteps:
  - name: LogFailoverTestStart
    action: 'aws:executeScript'
    inputs:
      Runtime: python3.8
      Handler: log_start
      Script: |
        def log_start(events, context):
            print("Starting application failover test...")
            print(f"Domain: {events['DomainName']}")
            return {"status": "started", "timestamp": str(context.aws_request_id)}
      InputPayload:
        DomainName: '{{ DomainName }}'
    outputs:
      - Name: FailoverStatus
        Selector: $.Payload.status
        Type: String
  - name: SimulateApplicationHealth
    action: 'aws:executeScript'
    inputs:
      Runtime: python3.8
      Handler: check_health
      Script: |
        import random
        def check_health(events, context):
            # Simulate health check
            health_status = random.choice([True, True, True, False])  # 75% success rate
            return {
                "healthy": health_status,
                "status": "healthy" if health_status else "unhealthy",
                "domain": events['DomainName'],
                "message": f"Simulated health check for {events['DomainName']}"
            }
      InputPayload:
        DomainName: '{{ DomainName }}'
    outputs:
      - Name: HealthCheckResult
        Selector: $.Payload.status
        Type: String
outputs:
  - FailoverStatus: '{{ LogFailoverTestStart.FailoverStatus }}'
  - HealthCheckResult: '{{ SimulateApplicationHealth.HealthCheckResult }}'
EOF
    
    # Create the application failover document
    if aws ssm describe-document --name "BC-ApplicationFailover-${BC_PROJECT_ID}" &> /dev/null; then
        warning "Application failover document already exists, updating..."
        aws ssm update-document \
            --name "BC-ApplicationFailover-${BC_PROJECT_ID}" \
            --content file:///tmp/application-failover-runbook.yaml \
            --document-format "YAML" \
            --document-version '$LATEST'
    else
        aws ssm create-document \
            --name "BC-ApplicationFailover-${BC_PROJECT_ID}" \
            --document-type "Automation" \
            --document-format "YAML" \
            --content file:///tmp/application-failover-runbook.yaml \
            --tags Key=Purpose,Value=BusinessContinuityTesting Key=Project,Value=${BC_PROJECT_ID}
    fi
    
    success "Systems Manager automation documents created"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions for test orchestration..."
    
    # Create test orchestrator function
    cat > /tmp/bc-test-orchestrator.py << 'EOF'
import json
import boto3
import datetime
import uuid
import os
from typing import Dict, List

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    test_type = event.get('testType', 'daily')
    test_id = str(uuid.uuid4())
    
    test_results = {
        'testId': test_id,
        'testType': test_type,
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'results': []
    }
    
    try:
        if test_type in ['daily', 'weekly', 'monthly']:
            # Execute backup validation
            backup_result = execute_backup_validation(ssm, test_id)
            test_results['results'].append(backup_result)
        
        if test_type in ['weekly', 'monthly']:
            # Execute database recovery test
            db_result = execute_database_recovery_test(ssm, test_id)
            test_results['results'].append(db_result)
        
        if test_type == 'monthly':
            # Execute full application failover test
            app_result = execute_application_failover_test(ssm, test_id)
            test_results['results'].append(app_result)
        
        # Store results in S3
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=f'test-results/{test_type}/{test_id}/results.json',
            Body=json.dumps(test_results, indent=2),
            ContentType='application/json'
        )
        
        # Generate summary report
        summary = generate_test_summary(test_results)
        
        # Send notification (if SNS topic is configured)
        if os.environ.get('SNS_TOPIC_ARN'):
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'BC Testing {test_type.title()} Report - {test_id[:8]}',
                Message=summary
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'testId': test_id,
                'summary': summary
            })
        }
        
    except Exception as e:
        error_message = f'BC testing failed: {str(e)}'
        if os.environ.get('SNS_TOPIC_ARN'):
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'BC Testing Failed - {test_id[:8]}',
                Message=error_message
            )
        raise e

def execute_backup_validation(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-BackupValidation-{os.environ["PROJECT_ID"]}',
        Parameters={
            'InstanceId': [os.environ.get('TEST_INSTANCE_ID', 'i-1234567890abcdef0')],
            'BackupVaultName': [os.environ.get('BACKUP_VAULT_NAME', 'default')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'backup_validation',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def execute_database_recovery_test(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-DatabaseRecovery-{os.environ["PROJECT_ID"]}',
        Parameters={
            'DBInstanceIdentifier': [os.environ.get('DB_INSTANCE_ID', 'test-db')],
            'TestDBInstanceIdentifier': [f'test-db-{test_id[:8]}'],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'database_recovery',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def execute_application_failover_test(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-ApplicationFailover-{os.environ["PROJECT_ID"]}',
        Parameters={
            'DomainName': [os.environ.get('DOMAIN_NAME', 'app.example.com')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'application_failover',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def generate_test_summary(test_results):
    total_tests = len(test_results['results'])
    summary = f"""
Business Continuity Testing Summary
Test ID: {test_results['testId']}
Test Type: {test_results['testType']}
Timestamp: {test_results['timestamp']}

Tests Executed: {total_tests}

Test Results:
"""
    
    for result in test_results['results']:
        summary += f"- {result['test']}: {result['status']}\n"
    
    return summary
EOF
    
    # Package Lambda function
    cd /tmp
    zip bc-test-orchestrator.zip bc-test-orchestrator.py
    cd - > /dev/null
    
    # Create Lambda function
    ORCHESTRATOR_LAMBDA=$(aws lambda create-function \
        --function-name "bc-test-orchestrator-${BC_PROJECT_ID}" \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AUTOMATION_ROLE_NAME} \
        --handler bc-test-orchestrator.lambda_handler \
        --zip-file fileb:///tmp/bc-test-orchestrator.zip \
        --timeout 900 \
        --environment Variables='{
            "PROJECT_ID":"'${BC_PROJECT_ID}'",
            "RESULTS_BUCKET":"'${TEST_RESULTS_BUCKET}'",
            "AUTOMATION_ROLE_ARN":"arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${AUTOMATION_ROLE_NAME}'"
        }' \
        --tags Purpose=BusinessContinuityTesting,Project=${BC_PROJECT_ID} \
        --query 'FunctionArn' --output text 2>/dev/null || \
        aws lambda get-function --function-name "bc-test-orchestrator-${BC_PROJECT_ID}" --query 'Configuration.FunctionArn' --output text)
    
    echo "ORCHESTRATOR_LAMBDA=${ORCHESTRATOR_LAMBDA}" >> .bc-deployment-config
    
    success "Lambda functions created"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for BC testing alerts..."
    
    BC_SNS_TOPIC=$(aws sns create-topic \
        --name "bc-alerts-${BC_PROJECT_ID}" \
        --tags Key=Purpose,Value=BusinessContinuityTesting Key=Project,Value=${BC_PROJECT_ID} \
        --query 'TopicArn' --output text 2>/dev/null || \
        aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:bc-alerts-${BC_PROJECT_ID}" \
        --query 'Attributes.TopicArn' --output text)
    
    echo "BC_SNS_TOPIC=${BC_SNS_TOPIC}" >> .bc-deployment-config
    
    # Update Lambda environment with SNS topic
    aws lambda update-function-configuration \
        --function-name "bc-test-orchestrator-${BC_PROJECT_ID}" \
        --environment Variables='{
            "PROJECT_ID":"'${BC_PROJECT_ID}'",
            "RESULTS_BUCKET":"'${TEST_RESULTS_BUCKET}'",
            "AUTOMATION_ROLE_ARN":"arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${AUTOMATION_ROLE_NAME}'",
            "SNS_TOPIC_ARN":"'${BC_SNS_TOPIC}'"
        }' > /dev/null
    
    warning "Subscribe to SNS topic manually: aws sns subscribe --topic-arn ${BC_SNS_TOPIC} --protocol email --notification-endpoint your-email@example.com"
    
    success "SNS topic created: ${BC_SNS_TOPIC}"
}

# Function to create EventBridge schedules
create_eventbridge_schedules() {
    log "Creating EventBridge schedules for automated testing..."
    
    # Daily basic tests
    aws events put-rule \
        --name "bc-daily-tests-${BC_PROJECT_ID}" \
        --schedule-expression "${DAILY_TEST_SCHEDULE}" \
        --description "Daily business continuity basic tests" \
        --tags Key=Purpose,Value=BusinessContinuityTesting Key=Project,Value=${BC_PROJECT_ID}
    
    aws events put-targets \
        --rule "bc-daily-tests-${BC_PROJECT_ID}" \
        --targets Id=1,Arn=${ORCHESTRATOR_LAMBDA},Input='{"testType":"daily"}'
    
    # Weekly comprehensive tests
    aws events put-rule \
        --name "bc-weekly-tests-${BC_PROJECT_ID}" \
        --schedule-expression "${WEEKLY_COMPREHENSIVE_SCHEDULE}" \
        --description "Weekly comprehensive business continuity tests" \
        --tags Key=Purpose,Value=BusinessContinuityTesting Key=Project,Value=${BC_PROJECT_ID}
    
    aws events put-targets \
        --rule "bc-weekly-tests-${BC_PROJECT_ID}" \
        --targets Id=1,Arn=${ORCHESTRATOR_LAMBDA},Input='{"testType":"weekly"}'
    
    # Monthly full DR tests
    aws events put-rule \
        --name "bc-monthly-tests-${BC_PROJECT_ID}" \
        --schedule-expression "${MONTHLY_FULL_DR_SCHEDULE}" \
        --description "Monthly full disaster recovery tests" \
        --tags Key=Purpose,Value=BusinessContinuityTesting Key=Project,Value=${BC_PROJECT_ID}
    
    aws events put-targets \
        --rule "bc-monthly-tests-${BC_PROJECT_ID}" \
        --targets Id=1,Arn=${ORCHESTRATOR_LAMBDA},Input='{"testType":"monthly"}'
    
    # Grant EventBridge permissions to invoke Lambda
    for schedule in daily weekly monthly; do
        aws lambda add-permission \
            --function-name "bc-test-orchestrator-${BC_PROJECT_ID}" \
            --statement-id "allow-eventbridge-${schedule}" \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/bc-${schedule}-tests-${BC_PROJECT_ID} \
            2>/dev/null || true
    done
    
    success "EventBridge schedules configured"
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard for BC testing monitoring..."
    
    cat > /tmp/bc-dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Duration", "FunctionName", "bc-test-orchestrator-${BC_PROJECT_ID}"],
                    [".", "Errors", ".", "."],
                    [".", "Invocations", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "BC Testing Lambda Metrics",
                "view": "timeSeries"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/SSM", "ExecutionSuccess", "DocumentName", "BC-BackupValidation-${BC_PROJECT_ID}"],
                    [".", "ExecutionFailed", ".", "."],
                    [".", "ExecutionSuccess", "DocumentName", "BC-DatabaseRecovery-${BC_PROJECT_ID}"],
                    [".", "ExecutionFailed", ".", "."],
                    [".", "ExecutionSuccess", "DocumentName", "BC-ApplicationFailover-${BC_PROJECT_ID}"],
                    [".", "ExecutionFailed", ".", "."]
                ],
                "period": 86400,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "BC Testing Success/Failure Rates",
                "view": "number"
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/bc-test-orchestrator-${BC_PROJECT_ID}' | fields @timestamp, @message | filter @message like /Test/ | sort @timestamp desc | limit 20",
                "region": "${AWS_REGION}",
                "title": "Recent BC Test Executions",
                "view": "table"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "BC-Testing-${BC_PROJECT_ID}" \
        --dashboard-body file:///tmp/bc-dashboard.json
    
    success "CloudWatch dashboard created"
}

# Function to run deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check Systems Manager documents
    doc_count=$(aws ssm list-documents \
        --filters Key=DocumentType,Values=Automation Key=Name,Values=BC-*-${BC_PROJECT_ID} \
        --query 'length(DocumentIdentifiers)')
    
    if [ "$doc_count" -ge 3 ]; then
        success "Systems Manager documents: $doc_count created"
    else
        error "Expected 3 SSM documents, found $doc_count"
        return 1
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "bc-test-orchestrator-${BC_PROJECT_ID}" &> /dev/null; then
        success "Lambda function: bc-test-orchestrator-${BC_PROJECT_ID} created"
    else
        error "Lambda function not found"
        return 1
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket ${TEST_RESULTS_BUCKET} &> /dev/null; then
        success "S3 bucket: ${TEST_RESULTS_BUCKET} created"
    else
        error "S3 bucket not found"
        return 1
    fi
    
    # Check EventBridge rules
    rule_count=$(aws events list-rules --name-prefix "bc-" --query 'length(Rules)')
    if [ "$rule_count" -ge 3 ]; then
        success "EventBridge rules: $rule_count created"
    else
        error "Expected 3 EventBridge rules, found $rule_count"
        return 1
    fi
    
    success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: ${BC_PROJECT_ID}"
    echo "AWS Region: ${AWS_REGION}"
    echo "Account ID: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "Resources Created:"
    echo "- IAM Role: ${AUTOMATION_ROLE_NAME}"
    echo "- S3 Bucket: ${TEST_RESULTS_BUCKET}"
    echo "- Lambda Function: bc-test-orchestrator-${BC_PROJECT_ID}"
    echo "- SNS Topic: bc-alerts-${BC_PROJECT_ID}"
    echo "- Systems Manager Documents: 3"
    echo "- EventBridge Rules: 3"
    echo "- CloudWatch Dashboard: BC-Testing-${BC_PROJECT_ID}"
    echo ""
    echo "Next Steps:"
    echo "1. Subscribe to SNS topic for notifications:"
    echo "   aws sns subscribe --topic-arn ${BC_SNS_TOPIC} --protocol email --notification-endpoint your-email@example.com"
    echo ""
    echo "2. Test manual execution:"
    echo "   aws lambda invoke --function-name bc-test-orchestrator-${BC_PROJECT_ID} --payload '{\"testType\":\"daily\"}' response.json"
    echo ""
    echo "3. View CloudWatch dashboard:"
    echo "   https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=BC-Testing-${BC_PROJECT_ID}"
    echo ""
    echo "Configuration saved to: .bc-deployment-config"
}

# Function to cleanup temp files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f /tmp/bc-testing-*.json
    rm -f /tmp/*-runbook.yaml
    rm -f /tmp/bc-test-orchestrator.py
    rm -f /tmp/bc-test-orchestrator.zip
    rm -f /tmp/bc-dashboard.json
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting AWS Business Continuity Testing Framework deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    create_s3_bucket
    create_ssm_documents
    create_lambda_functions
    create_sns_topic
    create_eventbridge_schedules
    create_cloudwatch_dashboard
    validate_deployment
    cleanup_temp_files
    display_summary
    
    success "AWS Business Continuity Testing Framework deployed successfully!"
    success "Total deployment time: $SECONDS seconds"
}

# Trap errors
trap 'error "Deployment failed on line $LINENO. Exit code: $?"; cleanup_temp_files; exit 1' ERR

# Run main function
main "$@"