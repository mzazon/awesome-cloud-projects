#!/bin/bash

# =============================================================================
# AWS RDS Disaster Recovery Deployment Script
# =============================================================================
# This script deploys a comprehensive disaster recovery solution for Amazon RDS
# databases including cross-region read replicas, monitoring, and automation.
# =============================================================================

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some advanced features may not work properly."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to validate inputs
validate_inputs() {
    log "Validating input parameters..."
    
    # Validate primary region
    if [[ -z "${PRIMARY_REGION:-}" ]]; then
        PRIMARY_REGION=$(aws configure get region)
        if [[ -z "$PRIMARY_REGION" ]]; then
            error "PRIMARY_REGION is not set and no default region configured"
            exit 1
        fi
        warn "Using default region from AWS CLI configuration: $PRIMARY_REGION"
    fi
    
    # Validate secondary region
    if [[ -z "${SECONDARY_REGION:-}" ]]; then
        error "SECONDARY_REGION environment variable is required"
        echo "Please set it with: export SECONDARY_REGION=us-west-2"
        exit 1
    fi
    
    # Validate database identifier
    if [[ -z "${DB_IDENTIFIER:-}" ]]; then
        error "DB_IDENTIFIER environment variable is required"
        echo "Please set it with: export DB_IDENTIFIER=your-database-id"
        exit 1
    fi
    
    # Ensure regions are different
    if [[ "$PRIMARY_REGION" == "$SECONDARY_REGION" ]]; then
        error "Primary and secondary regions must be different"
        exit 1
    fi
    
    log "Input validation completed successfully"
}

# Function to check if database exists and validate engine
check_database() {
    log "Checking source database..."
    
    # Check if database exists
    if ! aws rds describe-db-instances \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --region "$PRIMARY_REGION" \
        --query "DBInstances[0].DBInstanceArn" \
        --output text &> /dev/null; then
        error "Database $DB_IDENTIFIER not found in $PRIMARY_REGION"
        exit 1
    fi
    
    # Get database details
    DB_ARN=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --region "$PRIMARY_REGION" \
        --query "DBInstances[0].DBInstanceArn" \
        --output text)
    
    DB_ENGINE=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --region "$PRIMARY_REGION" \
        --query "DBInstances[0].Engine" \
        --output text)
    
    # Validate supported engine
    if [[ "$DB_ENGINE" != "mysql" && "$DB_ENGINE" != "postgres" ]]; then
        error "This script supports MySQL or PostgreSQL engines only. Detected: $DB_ENGINE"
        exit 1
    fi
    
    DB_STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --region "$PRIMARY_REGION" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text)
    
    if [[ "$DB_STATUS" != "available" ]]; then
        error "Database $DB_IDENTIFIER is not in 'available' status. Current status: $DB_STATUS"
        exit 1
    fi
    
    log "Database validation completed - Engine: $DB_ENGINE, Status: $DB_STATUS"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique resource names if not already set
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    
    # Export all required variables
    export DB_ARN
    export DB_ENGINE
    export REPLICA_NAME="${DB_IDENTIFIER}-replica-${RANDOM_SUFFIX}"
    export TOPIC_NAME="rds-dr-notifications-${RANDOM_SUFFIX}"
    export LAMBDA_NAME="rds-dr-manager-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="rds-dr-dashboard-${RANDOM_SUFFIX}"
    
    # Create temporary directory for deployment files
    TEMP_DIR=$(mktemp -d)
    export TEMP_DIR
    
    log "Environment setup completed"
    info "Replica name: $REPLICA_NAME"
    info "Temporary directory: $TEMP_DIR"
}

# Function to create cross-region read replica
create_read_replica() {
    log "Creating cross-region read replica..."
    
    # Check if replica already exists
    if aws rds describe-db-instances \
        --db-instance-identifier "$REPLICA_NAME" \
        --region "$SECONDARY_REGION" &> /dev/null; then
        warn "Read replica $REPLICA_NAME already exists in $SECONDARY_REGION"
        return 0
    fi
    
    # Get source database configuration
    IS_MULTI_AZ=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --region "$PRIMARY_REGION" \
        --query "DBInstances[0].MultiAZ" \
        --output text)
    
    DB_INSTANCE_CLASS=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_IDENTIFIER" \
        --region "$PRIMARY_REGION" \
        --query "DBInstances[0].DBInstanceClass" \
        --output text)
    
    info "Creating read replica with class: $DB_INSTANCE_CLASS, Multi-AZ: $IS_MULTI_AZ"
    
    # Create cross-region read replica
    aws rds create-db-instance-read-replica \
        --db-instance-identifier "$REPLICA_NAME" \
        --source-db-instance-identifier "$DB_ARN" \
        --source-region "$PRIMARY_REGION" \
        --region "$SECONDARY_REGION" \
        --multi-az "$IS_MULTI_AZ" \
        --db-instance-class "$DB_INSTANCE_CLASS" \
        --tags "Key=Purpose,Value=DisasterRecovery" "Key=Source,Value=$DB_IDENTIFIER" \
        > /dev/null
    
    log "Read replica creation initiated. This may take 15-30 minutes..."
}

# Function to create SNS topics
create_sns_topics() {
    log "Creating SNS topics for notifications..."
    
    # Create SNS topic in primary region
    PRIMARY_TOPIC_ARN=$(aws sns create-topic \
        --name "$TOPIC_NAME" \
        --region "$PRIMARY_REGION" \
        --query 'TopicArn' \
        --output text)
    
    # Create SNS topic in secondary region
    SECONDARY_TOPIC_ARN=$(aws sns create-topic \
        --name "$TOPIC_NAME" \
        --region "$SECONDARY_REGION" \
        --query 'TopicArn' \
        --output text)
    
    # Export topic ARNs for use in other functions
    export PRIMARY_TOPIC_ARN
    export SECONDARY_TOPIC_ARN
    
    log "SNS topics created successfully"
    info "Primary topic: $PRIMARY_TOPIC_ARN"
    info "Secondary topic: $SECONDARY_TOPIC_ARN"
    
    # Optionally subscribe email if provided
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
        aws sns subscribe \
            --topic-arn "$PRIMARY_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS" \
            --region "$PRIMARY_REGION" > /dev/null
        
        aws sns subscribe \
            --topic-arn "$SECONDARY_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS" \
            --region "$SECONDARY_REGION" > /dev/null
        
        log "Email subscription added: $EMAIL_ADDRESS (check your email to confirm)"
    fi
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for monitoring..."
    
    # Primary database high CPU alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${DB_IDENTIFIER}-HighCPU" \
        --metric-name CPUUtilization \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --evaluation-periods 3 \
        --threshold 80 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions "Name=DBInstanceIdentifier,Value=$DB_IDENTIFIER" \
        --alarm-actions "$PRIMARY_TOPIC_ARN" \
        --region "$PRIMARY_REGION" > /dev/null
    
    # Database connection alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${DB_IDENTIFIER}-DatabaseConnections" \
        --metric-name DatabaseConnections \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 0 \
        --comparison-operator LessThanThreshold \
        --dimensions "Name=DBInstanceIdentifier,Value=$DB_IDENTIFIER" \
        --alarm-actions "$PRIMARY_TOPIC_ARN" \
        --region "$PRIMARY_REGION" \
        --treat-missing-data notBreaching > /dev/null
    
    log "Primary region alarms created successfully"
    
    # Wait for replica to be available before creating replica-specific alarms
    info "Waiting for read replica to become available before creating replica alarms..."
    if aws rds wait db-instance-available \
        --db-instance-identifier "$REPLICA_NAME" \
        --region "$SECONDARY_REGION" \
        --cli-read-timeout 3600 \
        --cli-connect-timeout 60; then
        
        # Replica lag alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "${REPLICA_NAME}-ReplicaLag" \
            --metric-name ReplicaLag \
            --namespace AWS/RDS \
            --statistic Average \
            --period 300 \
            --evaluation-periods 2 \
            --threshold 300 \
            --comparison-operator GreaterThanOrEqualToThreshold \
            --dimensions "Name=DBInstanceIdentifier,Value=$REPLICA_NAME" \
            --alarm-actions "$SECONDARY_TOPIC_ARN" \
            --region "$SECONDARY_REGION" > /dev/null
        
        log "Replica alarms created successfully"
    else
        warn "Timeout waiting for replica. Replica lag alarm will need to be created manually."
    fi
}

# Function to create IAM role for Lambda
create_lambda_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_NAME}-role" &> /dev/null; then
        warn "IAM role ${LAMBDA_NAME}-role already exists"
        return 0
    fi
    
    # Create trust policy
    cat > "$TEMP_DIR/lambda-trust-policy.json" << 'EOF'
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
        --role-name "${LAMBDA_NAME}-role" \
        --assume-role-policy-document "file://$TEMP_DIR/lambda-trust-policy.json" \
        --region "$PRIMARY_REGION" > /dev/null
    
    # Create execution policy
    cat > "$TEMP_DIR/lambda-execution-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:PromoteReadReplica",
        "rds:ModifyDBInstance"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": [
        "$PRIMARY_TOPIC_ARN",
        "$SECONDARY_TOPIC_ARN"
      ]
    }
  ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${LAMBDA_NAME}-role" \
        --policy-name "DrLambdaExecutionPolicy" \
        --policy-document "file://$TEMP_DIR/lambda-execution-policy.json" > /dev/null
    
    log "IAM role and policies created successfully"
}

# Function to create and deploy Lambda function
create_lambda_function() {
    log "Creating Lambda function for disaster recovery management..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_NAME" --region "$PRIMARY_REGION" &> /dev/null; then
        warn "Lambda function $LAMBDA_NAME already exists"
        return 0
    fi
    
    # Create Lambda function code
    cat > "$TEMP_DIR/dr_manager.py" << 'EOF'
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    """
    Disaster Recovery Manager for RDS
    Handles automated failover and notification logic
    """
    
    try:
        rds = boto3.client('rds')
        sns = boto3.client('sns')
        
        # Parse the CloudWatch alarm event
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        new_state = message['NewStateValue']
        reason = message['NewStateReason']
        
        print(f"Processing alarm: {alarm_name}, State: {new_state}")
        
        # Determine the action based on alarm type
        if 'HighCPU' in alarm_name and new_state == 'ALARM':
            return handle_high_cpu_alert(alarm_name, reason, sns)
        elif 'ReplicaLag' in alarm_name and new_state == 'ALARM':
            return handle_replica_lag_alert(alarm_name, reason, sns)
        elif 'DatabaseConnections' in alarm_name and new_state == 'ALARM':
            return handle_connection_failure(alarm_name, reason, sns, rds)
        
        return {
            'statusCode': 200,
            'body': json.dumps('No action required')
        }
        
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_high_cpu_alert(alarm_name, reason, sns):
    """Handle high CPU utilization alerts"""
    message = f"HIGH CPU ALERT: {alarm_name}\nReason: {reason}\nRecommendation: Monitor performance and consider scaling."
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Subject='RDS Performance Alert',
        Message=message
    )
    
    print(f"Processed high CPU alert for {alarm_name}")
    return {'statusCode': 200, 'body': 'High CPU alert processed'}

def handle_replica_lag_alert(alarm_name, reason, sns):
    """Handle replica lag alerts"""
    message = f"REPLICA LAG ALERT: {alarm_name}\nReason: {reason}\nRecommendation: Check network connectivity and primary database load."
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Subject='RDS Replica Lag Alert',
        Message=message
    )
    
    print(f"Processed replica lag alert for {alarm_name}")
    return {'statusCode': 200, 'body': 'Replica lag alert processed'}

def handle_connection_failure(alarm_name, reason, sns, rds):
    """Handle database connection failures - potential failover scenario"""
    
    # Extract database identifier from alarm name
    db_identifier = alarm_name.split('-')[0]
    
    # Check database status
    try:
        response = rds.describe_db_instances(DBInstanceIdentifier=db_identifier)
        db_status = response['DBInstances'][0]['DBInstanceStatus']
        
        if db_status not in ['available']:
            message = f"CRITICAL DATABASE ALERT: {alarm_name}\nDatabase Status: {db_status}\nReason: {reason}\n\nThis may require manual intervention or failover to DR region."
            
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='CRITICAL: RDS Database Alert - Action Required',
                Message=message
            )
            
    except Exception as e:
        error_message = f"ERROR: Could not check database status for {db_identifier}\nError: {str(e)}\nImmediate manual investigation required."
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='CRITICAL: RDS Monitoring Error',
            Message=error_message
        )
    
    print(f"Processed connection failure alert for {alarm_name}")
    return {'statusCode': 200, 'body': 'Connection failure alert processed'}
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip dr_manager.zip dr_manager.py > /dev/null
    cd - > /dev/null
    
    # Get Lambda role ARN
    LAMBDA_ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${LAMBDA_NAME}-role"
    
    # Wait a moment for IAM role to propagate
    sleep 10
    
    # Deploy Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler dr_manager.lambda_handler \
        --zip-file "fileb://$TEMP_DIR/dr_manager.zip" \
        --timeout 300 \
        --memory-size 256 \
        --environment Variables="{SNS_TOPIC_ARN=${PRIMARY_TOPIC_ARN}}" \
        --region "$PRIMARY_REGION" > /dev/null
    
    log "Lambda function deployed successfully"
}

# Function to configure EventBridge integration
configure_eventbridge() {
    log "Configuring EventBridge integration..."
    
    # Subscribe Lambda function to SNS topic
    aws sns subscribe \
        --topic-arn "$PRIMARY_TOPIC_ARN" \
        --protocol lambda \
        --notification-endpoint "arn:aws:lambda:${PRIMARY_REGION}:$(aws sts get-caller-identity --query Account --output text):function:${LAMBDA_NAME}" \
        --region "$PRIMARY_REGION" > /dev/null
    
    # Grant SNS permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "$LAMBDA_NAME" \
        --statement-id sns-trigger \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn "$PRIMARY_TOPIC_ARN" \
        --region "$PRIMARY_REGION" > /dev/null
    
    log "EventBridge integration configured successfully"
}

# Function to create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    # Ensure read replica is available before creating dashboard
    if ! aws rds describe-db-instances \
        --db-instance-identifier "$REPLICA_NAME" \
        --region "$SECONDARY_REGION" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text &> /dev/null; then
        warn "Read replica not yet available. Dashboard will be created but may show incomplete data initially."
    fi
    
    # Create dashboard configuration
    cat > "$TEMP_DIR/dashboard-config.json" << EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "$DB_IDENTIFIER"],
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "$REPLICA_NAME"]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "$PRIMARY_REGION",
        "title": "Database CPU Utilization",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 0, "width": 12, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/RDS", "ReplicaLag", "DBInstanceIdentifier", "$REPLICA_NAME"]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "$SECONDARY_REGION",
        "title": "Read Replica Lag (seconds)",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 6, "width": 24, "height": 6,
      "properties": {
        "metrics": [
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "$DB_IDENTIFIER"],
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "$REPLICA_NAME"]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "$PRIMARY_REGION",
        "title": "Database Connections",
        "period": 300
      }
    }
  ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body "file://$TEMP_DIR/dashboard-config.json" \
        --region "$PRIMARY_REGION" > /dev/null
    
    log "CloudWatch dashboard created successfully"
    info "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=${PRIMARY_REGION}#dashboards:name=${DASHBOARD_NAME}"
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    cat > "rds-dr-deployment-state.json" << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "primary_region": "$PRIMARY_REGION",
  "secondary_region": "$SECONDARY_REGION",
  "source_db_identifier": "$DB_IDENTIFIER",
  "replica_name": "$REPLICA_NAME",
  "topic_name": "$TOPIC_NAME",
  "lambda_name": "$LAMBDA_NAME",
  "dashboard_name": "$DASHBOARD_NAME",
  "primary_topic_arn": "$PRIMARY_TOPIC_ARN",
  "secondary_topic_arn": "$SECONDARY_TOPIC_ARN",
  "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    log "Deployment state saved to rds-dr-deployment-state.json"
}

# Function to perform deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    local validation_errors=0
    
    # Check read replica status
    if ! REPLICA_STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier "$REPLICA_NAME" \
        --region "$SECONDARY_REGION" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text 2>/dev/null); then
        error "Read replica validation failed"
        ((validation_errors++))
    else
        info "Read replica status: $REPLICA_STATUS"
    fi
    
    # Check SNS topics
    if ! aws sns get-topic-attributes --topic-arn "$PRIMARY_TOPIC_ARN" --region "$PRIMARY_REGION" &> /dev/null; then
        error "Primary SNS topic validation failed"
        ((validation_errors++))
    fi
    
    # Check Lambda function
    if ! aws lambda get-function --function-name "$LAMBDA_NAME" --region "$PRIMARY_REGION" &> /dev/null; then
        error "Lambda function validation failed"
        ((validation_errors++))
    fi
    
    # Check CloudWatch dashboard
    if ! aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" --region "$PRIMARY_REGION" &> /dev/null; then
        error "CloudWatch dashboard validation failed"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log "Deployment validation completed successfully"
        return 0
    else
        error "Deployment validation failed with $validation_errors errors"
        return 1
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Temporary files cleaned up"
    fi
}

# Main deployment function
main() {
    log "Starting AWS RDS Disaster Recovery deployment..."
    
    # Set up error handling
    trap cleanup_temp_files EXIT
    
    # Run deployment steps
    check_prerequisites
    validate_inputs
    check_database
    setup_environment
    
    create_read_replica
    create_sns_topics
    create_cloudwatch_alarms
    create_lambda_iam_role
    create_lambda_function
    configure_eventbridge
    create_dashboard
    
    save_deployment_state
    
    if validate_deployment; then
        log "=============================================="
        log "AWS RDS Disaster Recovery deployment completed successfully!"
        log "=============================================="
        info "Primary Database: $DB_IDENTIFIER ($PRIMARY_REGION)"
        info "Read Replica: $REPLICA_NAME ($SECONDARY_REGION)"
        info "Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${PRIMARY_REGION}#dashboards:name=${DASHBOARD_NAME}"
        info "Configuration saved to: rds-dr-deployment-state.json"
        log ""
        log "Next steps:"
        log "1. Verify email subscription confirmation if configured"
        log "2. Review CloudWatch dashboard for baseline metrics"
        log "3. Test notification system using the test alarm feature"
        log "4. Document your disaster recovery procedures"
    else
        error "Deployment completed with validation errors. Please review the logs."
        exit 1
    fi
}

# Script usage information
usage() {
    echo "Usage: $0"
    echo ""
    echo "Required environment variables:"
    echo "  DB_IDENTIFIER      - Source RDS database identifier"
    echo "  SECONDARY_REGION   - AWS region for disaster recovery"
    echo ""
    echo "Optional environment variables:"
    echo "  PRIMARY_REGION     - Source AWS region (defaults to AWS CLI default)"
    echo "  EMAIL_ADDRESS      - Email for notifications"
    echo "  RANDOM_SUFFIX      - Custom suffix for resource names"
    echo ""
    echo "Example:"
    echo "  export DB_IDENTIFIER=my-production-db"
    echo "  export SECONDARY_REGION=us-west-2"
    echo "  export EMAIL_ADDRESS=admin@company.com"
    echo "  ./deploy.sh"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac