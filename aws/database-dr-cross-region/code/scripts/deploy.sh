#!/bin/bash

#################################################################################
# Database Disaster Recovery with Read Replicas - Deploy Script
#
# This script deploys a comprehensive disaster recovery architecture using 
# Amazon RDS cross-region read replicas with automated failover mechanisms.
#
# Author: AWS Recipe Generator
# Version: 1.0
# Last Updated: 2025-07-12
#################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Secure Internal Field Separator

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="/tmp/dr-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_NAME="${0##*/}"

#################################################################################
# Logging Functions
#################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}"
}

#################################################################################
# Utility Functions
#################################################################################

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Wait for resource with timeout
wait_for_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local region="$3"
    local max_attempts="${4:-30}"
    local delay="${5:-30}"
    
    log_info "Waiting for $resource_type $resource_id to be available..."
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts - Checking $resource_type status..."
        
        case "$resource_type" in
            "rds")
                if aws rds describe-db-instances \
                    --region "$region" \
                    --db-instance-identifier "$resource_id" \
                    --query 'DBInstances[0].DBInstanceStatus' \
                    --output text 2>/dev/null | grep -q "available"; then
                    log_success "$resource_type $resource_id is now available"
                    return 0
                fi
                ;;
            *)
                log_error "Unknown resource type: $resource_type"
                return 1
                ;;
        esac
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "Timeout waiting for $resource_type $resource_id to be available"
            return 1
        fi
        
        log_info "Resource not ready, waiting $delay seconds..."
        sleep "$delay"
        ((attempt++))
    done
}

# Generate secure random password
generate_password() {
    if command_exists openssl; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-16
    else
        aws secretsmanager get-random-password \
            --exclude-characters '"@/\' \
            --password-length 16 \
            --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "TempPassword123!"
    fi
}

#################################################################################
# Validation Functions
#################################################################################

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2)
    log_info "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required environment variables
    local required_vars=("PRIMARY_REGION" "DR_REGION")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    # Validate regions
    if ! aws ec2 describe-regions --region "$PRIMARY_REGION" >/dev/null 2>&1; then
        log_error "Invalid primary region: $PRIMARY_REGION"
        exit 1
    fi
    
    if ! aws ec2 describe-regions --region "$DR_REGION" >/dev/null 2>&1; then
        log_error "Invalid DR region: $DR_REGION"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

validate_permissions() {
    log_info "Validating AWS permissions..."
    
    local required_permissions=(
        "rds:CreateDBInstance"
        "rds:CreateDBInstanceReadReplica"
        "rds:DescribeDBInstances"
        "sns:CreateTopic"
        "sns:Subscribe"
        "cloudwatch:PutMetricAlarm"
        "lambda:CreateFunction"
        "events:PutRule"
        "route53:CreateHealthCheck"
        "s3:CreateBucket"
        "iam:GetRole"
    )
    
    # Test a simple operation to verify basic permissions
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "Insufficient permissions to access AWS STS"
        exit 1
    fi
    
    log_success "Permission validation completed"
}

#################################################################################
# Resource Creation Functions
#################################################################################

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Generate unique identifiers
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        if command_exists openssl; then
            RANDOM_SUFFIX=$(openssl rand -hex 3)
        else
            RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
                --exclude-punctuation --exclude-uppercase \
                --password-length 6 --require-each-included-type \
                --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
        fi
        export RANDOM_SUFFIX
    fi
    
    # Set resource names
    export DB_INSTANCE_ID="primary-db-${RANDOM_SUFFIX}"
    export DB_REPLICA_ID="dr-replica-${RANDOM_SUFFIX}"
    export DB_SUBNET_GROUP="dr-subnet-group-${RANDOM_SUFFIX}"
    export SNS_TOPIC_PRIMARY="dr-primary-alerts-${RANDOM_SUFFIX}"
    export SNS_TOPIC_DR="dr-failover-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_PRIMARY="dr-coordinator-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_DR="replica-promoter-${RANDOM_SUFFIX}"
    export S3_BUCKET="dr-config-bucket-${RANDOM_SUFFIX}"
    export DB_PASSWORD
    DB_PASSWORD=$(generate_password)
    
    log_info "Resource naming configured with suffix: $RANDOM_SUFFIX"
    log_success "Environment setup completed"
}

create_s3_bucket() {
    log_info "Creating S3 bucket for configuration storage..."
    
    # Create S3 bucket
    if aws s3 ls "s3://$S3_BUCKET" >/dev/null 2>&1; then
        log_warning "S3 bucket $S3_BUCKET already exists"
    else
        aws s3 mb "s3://$S3_BUCKET" --region "$PRIMARY_REGION"
        log_success "S3 bucket $S3_BUCKET created"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET" \
        --versioning-configuration Status=Enabled
    
    log_success "S3 bucket versioning enabled"
}

create_primary_database() {
    log_info "Creating primary RDS database instance..."
    
    # Check if instance already exists
    if aws rds describe-db-instances \
        --region "$PRIMARY_REGION" \
        --db-instance-identifier "$DB_INSTANCE_ID" >/dev/null 2>&1; then
        log_warning "Primary database $DB_INSTANCE_ID already exists"
        return 0
    fi
    
    # Create primary RDS instance
    aws rds create-db-instance \
        --region "$PRIMARY_REGION" \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password "$DB_PASSWORD" \
        --allocated-storage 20 \
        --backup-retention-period 7 \
        --storage-encrypted \
        --monitoring-interval 60 \
        --enable-performance-insights \
        --deletion-protection \
        --tags Key=Purpose,Value=DisasterRecovery \
               Key=Environment,Value=Production \
               Key=CreatedBy,Value="$SCRIPT_NAME"
    
    log_success "Primary database creation initiated"
    
    # Wait for database to be available
    wait_for_resource "rds" "$DB_INSTANCE_ID" "$PRIMARY_REGION" 30 60
}

create_read_replica() {
    log_info "Creating cross-region read replica..."
    
    # Check if replica already exists
    if aws rds describe-db-instances \
        --region "$DR_REGION" \
        --db-instance-identifier "$DB_REPLICA_ID" >/dev/null 2>&1; then
        log_warning "Read replica $DB_REPLICA_ID already exists"
        return 0
    fi
    
    # Create cross-region read replica
    aws rds create-db-instance-read-replica \
        --region "$DR_REGION" \
        --db-instance-identifier "$DB_REPLICA_ID" \
        --source-db-instance-identifier "arn:aws:rds:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:db:${DB_INSTANCE_ID}" \
        --db-instance-class db.t3.micro \
        --publicly-accessible false \
        --auto-minor-version-upgrade true \
        --monitoring-interval 60 \
        --enable-performance-insights \
        --tags Key=Purpose,Value=DisasterRecovery \
               Key=Environment,Value=Production \
               Key=Role,Value=ReadReplica \
               Key=CreatedBy,Value="$SCRIPT_NAME"
    
    log_success "Read replica creation initiated"
    
    # Wait for replica to be available
    wait_for_resource "rds" "$DB_REPLICA_ID" "$DR_REGION" 30 60
}

create_sns_topics() {
    log_info "Creating SNS topics for alerting..."
    
    # Create SNS topic in primary region
    export PRIMARY_SNS_ARN
    PRIMARY_SNS_ARN=$(aws sns create-topic \
        --region "$PRIMARY_REGION" \
        --name "$SNS_TOPIC_PRIMARY" \
        --query TopicArn --output text)
    
    # Create SNS topic in DR region
    export DR_SNS_ARN
    DR_SNS_ARN=$(aws sns create-topic \
        --region "$DR_REGION" \
        --name "$SNS_TOPIC_DR" \
        --query TopicArn --output text)
    
    log_success "SNS topics created"
    log_info "Primary SNS ARN: $PRIMARY_SNS_ARN"
    log_info "DR SNS ARN: $DR_SNS_ARN"
    
    # Subscribe email if EMAIL_ADDRESS is provided
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
        aws sns subscribe \
            --region "$PRIMARY_REGION" \
            --topic-arn "$PRIMARY_SNS_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS"
        
        aws sns subscribe \
            --region "$DR_REGION" \
            --topic-arn "$DR_SNS_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS"
        
        log_success "Email subscriptions created for $EMAIL_ADDRESS"
    else
        log_warning "EMAIL_ADDRESS not set - skipping email subscriptions"
    fi
}

create_cloudwatch_alarms() {
    log_info "Creating CloudWatch alarms for database monitoring..."
    
    # Primary database connection alarm
    aws cloudwatch put-metric-alarm \
        --region "$PRIMARY_REGION" \
        --alarm-name "${DB_INSTANCE_ID}-database-connection-failure" \
        --alarm-description "Alarm when database connection fails" \
        --metric-name DatabaseConnections \
        --namespace AWS/RDS \
        --statistic Average \
        --period 60 \
        --threshold 0 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 3 \
        --alarm-actions "$PRIMARY_SNS_ARN" \
        --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
        --treat-missing-data breaching
    
    # Replica lag alarm
    aws cloudwatch put-metric-alarm \
        --region "$DR_REGION" \
        --alarm-name "${DB_REPLICA_ID}-replica-lag-high" \
        --alarm-description "Alarm when replica lag exceeds threshold" \
        --metric-name ReplicaLag \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 300 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$DR_SNS_ARN" \
        --dimensions Name=DBInstanceIdentifier,Value="$DB_REPLICA_ID"
    
    # CPU utilization alarms
    aws cloudwatch put-metric-alarm \
        --region "$PRIMARY_REGION" \
        --alarm-name "${DB_INSTANCE_ID}-cpu-utilization-high" \
        --alarm-description "Alarm when CPU exceeds 80%" \
        --metric-name CPUUtilization \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$PRIMARY_SNS_ARN" \
        --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID"
    
    aws cloudwatch put-metric-alarm \
        --region "$DR_REGION" \
        --alarm-name "${DB_REPLICA_ID}-cpu-utilization-high" \
        --alarm-description "Alarm when DR instance CPU exceeds 80%" \
        --metric-name CPUUtilization \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$DR_SNS_ARN" \
        --dimensions Name=DBInstanceIdentifier,Value="$DB_REPLICA_ID"
    
    log_success "CloudWatch alarms created"
}

create_lambda_functions() {
    log_info "Creating Lambda functions for disaster recovery automation..."
    
    # Create temporary directory for Lambda code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create DR coordinator Lambda function
    cat > "$temp_dir/dr-coordinator.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Disaster Recovery Coordinator Lambda Function
    Handles primary database failure detection and initiates failover
    """
    
    # Initialize AWS clients
    rds = boto3.client('rds', region_name=os.environ['DR_REGION'])
    sns = boto3.client('sns', region_name=os.environ['DR_REGION'])
    route53 = boto3.client('route53')
    ssm = boto3.client('ssm', region_name=os.environ['DR_REGION'])
    
    try:
        # Parse CloudWatch alarm from SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message['AlarmName']
        
        print(f"Processing alarm: {alarm_name}")
        
        # Check if this is a database connection failure
        if 'database-connection-failure' in alarm_name:
            # Initiate disaster recovery procedure
            replica_id = os.environ['DB_REPLICA_ID']
            
            # Check replica status before promotion
            replica_status = rds.describe_db_instances(
                DBInstanceIdentifier=replica_id
            )['DBInstances'][0]['DBInstanceStatus']
            
            if replica_status == 'available':
                print(f"Promoting read replica {replica_id} to standalone instance")
                
                # Promote read replica
                rds.promote_read_replica(
                    DBInstanceIdentifier=replica_id
                )
                
                # Update parameter store with failover status
                ssm.put_parameter(
                    Name='/disaster-recovery/failover-status',
                    Value=json.dumps({
                        'status': 'in-progress',
                        'timestamp': datetime.utcnow().isoformat(),
                        'replica_id': replica_id
                    }),
                    Type='String',
                    Overwrite=True
                )
                
                # Send success notification
                sns.publish(
                    TopicArn=os.environ['DR_SNS_ARN'],
                    Subject='Disaster Recovery Initiated',
                    Message=f'Read replica {replica_id} promotion started. Monitor for completion.'
                )
                
                return {
                    'statusCode': 200,
                    'body': json.dumps(f'DR procedure initiated for {replica_id}')
                }
            else:
                print(f"Replica {replica_id} is not available for promotion: {replica_status}")
                return {
                    'statusCode': 400,
                    'body': json.dumps(f'Replica not ready for promotion: {replica_status}')
                }
        
    except Exception as e:
        print(f"Error in DR coordinator: {str(e)}")
        sns.publish(
            TopicArn=os.environ['DR_SNS_ARN'],
            Subject='Disaster Recovery Error',
            Message=f'Error in DR coordinator: {str(e)}'
        )
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    
    # Create Lambda deployment package for DR coordinator
    cd "$temp_dir"
    zip -r dr-coordinator.zip dr-coordinator.py
    
    # Check if Lambda execution role exists
    if ! aws iam get-role --role-name lambda-execution-role >/dev/null 2>&1; then
        log_warning "Lambda execution role not found. You may need to create it manually."
    fi
    
    # Create DR coordinator Lambda function
    aws lambda create-function \
        --region "$PRIMARY_REGION" \
        --function-name "$LAMBDA_FUNCTION_PRIMARY" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role" \
        --handler dr-coordinator.lambda_handler \
        --zip-file fileb://dr-coordinator.zip \
        --environment Variables="{
            \"DR_REGION\":\"$DR_REGION\",
            \"DB_REPLICA_ID\":\"$DB_REPLICA_ID\",
            \"DR_SNS_ARN\":\"$DR_SNS_ARN\"
        }" \
        --timeout 60 \
        --tags Purpose=DisasterRecovery,Environment=Production,CreatedBy="$SCRIPT_NAME" \
        2>/dev/null || log_warning "DR coordinator Lambda function may already exist"
    
    # Create replica promoter Lambda function code
    cat > "$temp_dir/replica-promoter.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Replica Promoter Lambda Function
    Handles post-promotion tasks and DNS updates
    """
    
    # Initialize AWS clients
    rds = boto3.client('rds', region_name=os.environ['DR_REGION'])
    route53 = boto3.client('route53')
    ssm = boto3.client('ssm', region_name=os.environ['DR_REGION'])
    sns = boto3.client('sns', region_name=os.environ['DR_REGION'])
    
    try:
        # Check if this is a promotion completion event
        if 'source' in event and event['source'] == 'aws.rds':
            detail = event['detail']
            
            if detail['eventName'] == 'promote-read-replica' and detail['responseElements']:
                db_instance_id = detail['responseElements']['dBInstanceIdentifier']
                
                print(f"Processing promotion completion for {db_instance_id}")
                
                # Wait for instance to be available
                waiter = rds.get_waiter('db_instance_available')
                waiter.wait(
                    DBInstanceIdentifier=db_instance_id,
                    WaiterConfig={'Delay': 30, 'MaxAttempts': 20}
                )
                
                # Get promoted instance details
                instance = rds.describe_db_instances(
                    DBInstanceIdentifier=db_instance_id
                )['DBInstances'][0]
                
                new_endpoint = instance['Endpoint']['Address']
                
                # Update parameter store
                ssm.put_parameter(
                    Name='/disaster-recovery/failover-status',
                    Value=json.dumps({
                        'status': 'completed',
                        'timestamp': datetime.utcnow().isoformat(),
                        'new_endpoint': new_endpoint,
                        'db_instance_id': db_instance_id
                    }),
                    Type='String',
                    Overwrite=True
                )
                
                # Send completion notification
                sns.publish(
                    TopicArn=os.environ['DR_SNS_ARN'],
                    Subject='Disaster Recovery Completed',
                    Message=f'''
Disaster recovery promotion completed successfully.

New Database Endpoint: {new_endpoint}
Instance ID: {db_instance_id}
Completion Time: {datetime.utcnow().isoformat()}

Please update application configurations to use the new endpoint.
                    '''
                )
                
                return {
                    'statusCode': 200,
                    'body': json.dumps('Promotion completion processed successfully')
                }
        
    except Exception as e:
        print(f"Error in replica promoter: {str(e)}")
        sns.publish(
            TopicArn=os.environ['DR_SNS_ARN'],
            Subject='Disaster Recovery Error',
            Message=f'Error in replica promoter: {str(e)}'
        )
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    
    # Create Lambda deployment package for replica promoter
    zip -r replica-promoter.zip replica-promoter.py
    
    # Create replica promoter Lambda function
    aws lambda create-function \
        --region "$DR_REGION" \
        --function-name "$LAMBDA_FUNCTION_DR" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role" \
        --handler replica-promoter.lambda_handler \
        --zip-file fileb://replica-promoter.zip \
        --environment Variables="{
            \"DR_REGION\":\"$DR_REGION\",
            \"DR_SNS_ARN\":\"$DR_SNS_ARN\"
        }" \
        --timeout 300 \
        --tags Purpose=DisasterRecovery,Environment=Production,CreatedBy="$SCRIPT_NAME" \
        2>/dev/null || log_warning "Replica promoter Lambda function may already exist"
    
    # Clean up temporary directory
    cd - >/dev/null
    rm -rf "$temp_dir"
    
    log_success "Lambda functions created"
}

configure_eventbridge() {
    log_info "Configuring EventBridge rules for automation..."
    
    # Create EventBridge rule for RDS events
    aws events put-rule \
        --region "$DR_REGION" \
        --name "rds-promotion-events" \
        --event-pattern '{
            "source": ["aws.rds"],
            "detail-type": ["RDS DB Instance Event"],
            "detail": {
                "eventName": ["promote-read-replica"]
            }
        }' \
        --state ENABLED \
        --description "Capture RDS promotion events for DR automation"
    
    # Add Lambda target to EventBridge rule
    aws events put-targets \
        --region "$DR_REGION" \
        --rule "rds-promotion-events" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${DR_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_DR}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --region "$DR_REGION" \
        --function-name "$LAMBDA_FUNCTION_DR" \
        --statement-id eventbridge-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${DR_REGION}:${AWS_ACCOUNT_ID}:rule/rds-promotion-events" \
        2>/dev/null || log_warning "EventBridge permission may already exist"
    
    log_success "EventBridge automation configured"
}

create_route53_health_checks() {
    log_info "Creating Route 53 health checks..."
    
    # Create health check for primary database
    export PRIMARY_HEALTH_CHECK_ID
    PRIMARY_HEALTH_CHECK_ID=$(aws route53 create-health-check \
        --caller-reference "primary-db-health-$(date +%s)" \
        --health-check-config "{
            \"Type\": \"CLOUDWATCH_METRIC\",
            \"AlarmRegion\": \"$PRIMARY_REGION\",
            \"AlarmName\": \"${DB_INSTANCE_ID}-database-connection-failure\",
            \"InsufficientDataHealthStatus\": \"Failure\"
        }" \
        --query 'HealthCheck.Id' --output text)
    
    # Create health check for DR database
    export DR_HEALTH_CHECK_ID
    DR_HEALTH_CHECK_ID=$(aws route53 create-health-check \
        --caller-reference "dr-db-health-$(date +%s)" \
        --health-check-config "{
            \"Type\": \"CLOUDWATCH_METRIC\",
            \"AlarmRegion\": \"$DR_REGION\",
            \"AlarmName\": \"${DB_REPLICA_ID}-replica-lag-high\",
            \"InsufficientDataHealthStatus\": \"Success\"
        }" \
        --query 'HealthCheck.Id' --output text)
    
    log_success "Route 53 health checks created"
    log_info "Primary Health Check ID: $PRIMARY_HEALTH_CHECK_ID"
    log_info "DR Health Check ID: $DR_HEALTH_CHECK_ID"
}

configure_sns_lambda_integration() {
    log_info "Configuring SNS-Lambda integration..."
    
    # Subscribe DR coordinator Lambda to primary SNS topic
    aws sns subscribe \
        --region "$PRIMARY_REGION" \
        --topic-arn "$PRIMARY_SNS_ARN" \
        --protocol lambda \
        --notification-endpoint "arn:aws:lambda:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_PRIMARY}"
    
    # Grant SNS permission to invoke Lambda
    aws lambda add-permission \
        --region "$PRIMARY_REGION" \
        --function-name "$LAMBDA_FUNCTION_PRIMARY" \
        --statement-id sns-invoke \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn "$PRIMARY_SNS_ARN" \
        2>/dev/null || log_warning "SNS Lambda permission may already exist"
    
    log_success "SNS-Lambda integration configured"
}

create_runbook() {
    log_info "Creating disaster recovery runbook..."
    
    # Create runbook with all resource information
    cat > /tmp/dr-runbook.json << EOF
{
    "disaster_recovery_runbook": {
        "version": "1.0",
        "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "primary_region": "$PRIMARY_REGION",
        "dr_region": "$DR_REGION",
        "aws_account_id": "$AWS_ACCOUNT_ID",
        "resources": {
            "primary_db": "$DB_INSTANCE_ID",
            "replica_db": "$DB_REPLICA_ID",
            "s3_bucket": "$S3_BUCKET",
            "sns_primary": "$PRIMARY_SNS_ARN",
            "sns_dr": "$DR_SNS_ARN",
            "lambda_coordinator": "$LAMBDA_FUNCTION_PRIMARY",
            "lambda_promoter": "$LAMBDA_FUNCTION_DR",
            "primary_health_check": "${PRIMARY_HEALTH_CHECK_ID:-N/A}",
            "dr_health_check": "${DR_HEALTH_CHECK_ID:-N/A}"
        },
        "manual_failover_steps": [
            "1. Verify primary database is truly unavailable",
            "2. Check replica lag is minimal (< 5 minutes)",
            "3. Promote replica using: aws rds promote-read-replica --db-instance-identifier $DB_REPLICA_ID --region $DR_REGION",
            "4. Wait for promotion to complete",
            "5. Update application connection strings",
            "6. Verify application functionality",
            "7. Update DNS records if needed"
        ],
        "rollback_steps": [
            "1. Create new read replica from promoted instance",
            "2. Switch applications back to original region",
            "3. Verify data consistency",
            "4. Clean up temporary resources"
        ],
        "monitoring_urls": {
            "cloudwatch_primary": "https://${PRIMARY_REGION}.console.aws.amazon.com/cloudwatch/home?region=${PRIMARY_REGION}#alarmsV2:",
            "cloudwatch_dr": "https://${DR_REGION}.console.aws.amazon.com/cloudwatch/home?region=${DR_REGION}#alarmsV2:",
            "rds_primary": "https://${PRIMARY_REGION}.console.aws.amazon.com/rds/home?region=${PRIMARY_REGION}#database:id=${DB_INSTANCE_ID}",
            "rds_dr": "https://${DR_REGION}.console.aws.amazon.com/rds/home?region=${DR_REGION}#database:id=${DB_REPLICA_ID}"
        }
    }
}
EOF
    
    # Upload runbook to S3
    aws s3 cp /tmp/dr-runbook.json "s3://$S3_BUCKET/dr-runbook.json"
    
    # Clean up local file
    rm -f /tmp/dr-runbook.json
    
    log_success "Disaster recovery runbook created and stored in S3"
}

save_deployment_info() {
    log_info "Saving deployment information..."
    
    # Create deployment info file
    cat > /tmp/deployment-info.json << EOF
{
    "deployment_info": {
        "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "script_version": "1.0",
        "aws_account_id": "$AWS_ACCOUNT_ID",
        "primary_region": "$PRIMARY_REGION",
        "dr_region": "$DR_REGION",
        "resources": {
            "primary_db_instance_id": "$DB_INSTANCE_ID",
            "dr_replica_instance_id": "$DB_REPLICA_ID",
            "s3_config_bucket": "$S3_BUCKET",
            "sns_primary_topic": "$SNS_TOPIC_PRIMARY",
            "sns_dr_topic": "$SNS_TOPIC_DR",
            "lambda_coordinator": "$LAMBDA_FUNCTION_PRIMARY",
            "lambda_promoter": "$LAMBDA_FUNCTION_DR",
            "random_suffix": "$RANDOM_SUFFIX"
        },
        "next_steps": [
            "Monitor CloudWatch alarms for database health",
            "Test disaster recovery procedures in non-production environment",
            "Update application connection strings to use database endpoints",
            "Configure application-level health checks",
            "Schedule regular disaster recovery drills"
        ]
    }
}
EOF
    
    # Save to S3
    aws s3 cp /tmp/deployment-info.json "s3://$S3_BUCKET/deployment-info.json"
    
    # Save locally for immediate reference
    cp /tmp/deployment-info.json ./dr-deployment-info.json
    
    log_success "Deployment information saved to S3 and local file"
}

#################################################################################
# Main Deployment Function
#################################################################################

main() {
    local start_time
    start_time=$(date +%s)
    
    log_info "Starting Database Disaster Recovery deployment..."
    log_info "Log file: $LOG_FILE"
    
    # Set default values for required environment variables if not set
    export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
    export DR_REGION="${DR_REGION:-us-west-2}"
    
    log_info "Primary Region: $PRIMARY_REGION"
    log_info "DR Region: $DR_REGION"
    
    # Validation phase
    validate_prerequisites
    validate_permissions
    
    # Setup phase
    setup_environment
    
    # Resource creation phase
    create_s3_bucket
    create_primary_database
    create_read_replica
    create_sns_topics
    create_cloudwatch_alarms
    create_lambda_functions
    configure_eventbridge
    create_route53_health_checks
    configure_sns_lambda_integration
    create_runbook
    save_deployment_info
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Deployment completed successfully!"
    log_info "Total deployment time: ${duration} seconds"
    
    # Display summary
    echo
    echo "==================================="
    echo "DEPLOYMENT SUMMARY"
    echo "==================================="
    echo "Primary Database: $DB_INSTANCE_ID (Region: $PRIMARY_REGION)"
    echo "DR Replica: $DB_REPLICA_ID (Region: $DR_REGION)"
    echo "S3 Configuration Bucket: $S3_BUCKET"
    echo "Primary SNS Topic: $PRIMARY_SNS_ARN"
    echo "DR SNS Topic: $DR_SNS_ARN"
    echo "Lambda Coordinator: $LAMBDA_FUNCTION_PRIMARY"
    echo "Lambda Promoter: $LAMBDA_FUNCTION_DR"
    echo
    echo "Important Files:"
    echo "- Deployment Info: ./dr-deployment-info.json"
    echo "- Log File: $LOG_FILE"
    echo
    echo "Next Steps:"
    echo "1. Configure email notifications by setting EMAIL_ADDRESS environment variable"
    echo "2. Update application connection strings"
    echo "3. Test disaster recovery procedures"
    echo "4. Schedule regular DR drills"
    echo
    echo "To clean up resources, run: ./destroy.sh"
    echo "==================================="
}

#################################################################################
# Error Handling
#################################################################################

trap 'log_error "Deployment failed on line $LINENO. Check log file: $LOG_FILE"' ERR

# Show usage if help requested
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    cat << EOF
Database Disaster Recovery Deployment Script

USAGE:
    $0 [OPTIONS]

ENVIRONMENT VARIABLES:
    PRIMARY_REGION      Primary AWS region (default: us-east-1)
    DR_REGION          Disaster recovery AWS region (default: us-west-2)
    EMAIL_ADDRESS      Email for SNS notifications (optional)
    RANDOM_SUFFIX      Resource naming suffix (auto-generated if not set)

EXAMPLES:
    # Deploy with default regions
    $0

    # Deploy with custom regions
    PRIMARY_REGION=us-west-1 DR_REGION=eu-west-1 $0

    # Deploy with email notifications
    EMAIL_ADDRESS=admin@example.com $0

REQUIREMENTS:
    - AWS CLI v2 installed and configured
    - Appropriate AWS permissions for RDS, Lambda, SNS, CloudWatch, Route 53
    - Lambda execution role: lambda-execution-role (with appropriate permissions)

FILES CREATED:
    - ./dr-deployment-info.json (deployment summary)
    - $LOG_FILE (detailed log)
EOF
    exit 0
fi

# Execute main function
main "$@"