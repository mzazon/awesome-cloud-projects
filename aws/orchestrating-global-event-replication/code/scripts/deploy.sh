#!/bin/bash

# AWS Multi-Region Event Replication with EventBridge - Deployment Script
# This script deploys a multi-region event replication architecture using EventBridge
# with global endpoints, cross-region event buses, and Lambda processors.

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
DEFAULT_PRIMARY_REGION="us-east-1"
DEFAULT_SECONDARY_REGION="us-west-2"
DEFAULT_TERTIARY_REGION="eu-west-1"

# Configuration variables
PRIMARY_REGION="${PRIMARY_REGION:-$DEFAULT_PRIMARY_REGION}"
SECONDARY_REGION="${SECONDARY_REGION:-$DEFAULT_SECONDARY_REGION}"
TERTIARY_REGION="${TERTIARY_REGION:-$DEFAULT_TERTIARY_REGION}"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${ERROR_LOG}" >&2)

# Utility functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: ${aws_version}"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if required tools are available
    local required_tools=("jq" "zip")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            error "Required tool '$tool' is not installed."
            exit 1
        fi
    done
    
    log "Prerequisites check completed successfully"
}

# Validate AWS regions
validate_regions() {
    log "Validating AWS regions..."
    
    local regions=("${PRIMARY_REGION}" "${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        if ! aws ec2 describe-regions --region-names "$region" >/dev/null 2>&1; then
            error "Invalid AWS region: $region"
            exit 1
        fi
        debug "Region $region is valid"
    done
    
    log "All regions are valid"
}

# Get AWS account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

# Generate random suffix for unique resource names
generate_random_suffix() {
    aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)"
}

# Wait for resource to be available
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local region="$3"
    local max_attempts=30
    local attempt=1
    
    debug "Waiting for $resource_type: $resource_name in region: $region"
    
    while [[ $attempt -le $max_attempts ]]; do
        case "$resource_type" in
            "lambda")
                if aws lambda get-function --function-name "$resource_name" --region "$region" >/dev/null 2>&1; then
                    debug "$resource_type $resource_name is ready"
                    return 0
                fi
                ;;
            "eventbus")
                if aws events describe-event-bus --name "$resource_name" --region "$region" >/dev/null 2>&1; then
                    debug "$resource_type $resource_name is ready"
                    return 0
                fi
                ;;
            "role")
                if aws iam get-role --role-name "$resource_name" >/dev/null 2>&1; then
                    debug "$resource_type $resource_name is ready"
                    return 0
                fi
                ;;
        esac
        
        debug "Attempt $attempt/$max_attempts: $resource_type $resource_name not ready, waiting..."
        sleep 10
        ((attempt++))
    done
    
    error "Timeout waiting for $resource_type: $resource_name"
    return 1
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create Lambda execution role
    local lambda_trust_policy='{
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
    }'
    
    if ! aws iam get-role --role-name lambda-execution-role >/dev/null 2>&1; then
        aws iam create-role \
            --role-name lambda-execution-role \
            --assume-role-policy-document "$lambda_trust_policy" \
            --tags Key=Purpose,Value=EventProcessing Key=Environment,Value=Production
        
        aws iam attach-role-policy \
            --role-name lambda-execution-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        log "Lambda execution role created"
    else
        log "Lambda execution role already exists"
    fi
    
    # Create EventBridge cross-region role
    local eventbridge_trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "events.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    
    local eventbridge_permissions='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "events:PutEvents"
                ],
                "Resource": [
                    "arn:aws:events:*:*:event-bus/*"
                ]
            }
        ]
    }'
    
    if ! aws iam get-role --role-name eventbridge-cross-region-role >/dev/null 2>&1; then
        aws iam create-role \
            --role-name eventbridge-cross-region-role \
            --assume-role-policy-document "$eventbridge_trust_policy" \
            --tags Key=Purpose,Value=CrossRegionReplication Key=Environment,Value=Production
        
        aws iam put-role-policy \
            --role-name eventbridge-cross-region-role \
            --policy-name EventBridgeCrossRegionPolicy \
            --policy-document "$eventbridge_permissions"
        
        log "EventBridge cross-region role created"
    else
        log "EventBridge cross-region role already exists"
    fi
    
    # Wait for roles to be available
    wait_for_resource "role" "lambda-execution-role" "global"
    wait_for_resource "role" "eventbridge-cross-region-role" "global"
    
    # Add delay for IAM eventual consistency
    sleep 30
}

# Create SNS topic for notifications
create_sns_topic() {
    log "Creating SNS topic for notifications..."
    
    aws sns create-topic \
        --name "eventbridge-alerts-${RANDOM_SUFFIX}" \
        --region "${PRIMARY_REGION}" \
        --tags Key=Purpose,Value=EventBridgeAlerts Key=Environment,Value=Production
    
    SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:eventbridge-alerts-${RANDOM_SUFFIX}" \
        --region "${PRIMARY_REGION}" \
        --query Attributes.TopicArn --output text)
    
    log "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Create custom event buses
create_event_buses() {
    log "Creating custom event buses in all regions..."
    
    local regions=("${PRIMARY_REGION}" "${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        debug "Creating event bus in region: $region"
        
        aws events create-event-bus \
            --name "${EVENT_BUS_NAME}" \
            --region "$region" \
            --kms-key-id alias/aws/events \
            --tags Key=Environment,Value=Production Key=Purpose,Value=MultiRegionReplication
        
        # Set event bus permissions
        aws events put-permission \
            --principal "${AWS_ACCOUNT_ID}" \
            --action events:PutEvents \
            --statement-id "AllowCrossRegionAccess" \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --region "$region"
        
        wait_for_resource "eventbus" "${EVENT_BUS_NAME}" "$region"
        debug "Event bus created in region: $region"
    done
    
    log "Custom event buses created in all regions"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions for event processing..."
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    region = os.environ.get('AWS_REGION', 'unknown')
    
    # Log the received event
    print(f"Processing event in region {region}")
    print(f"Event: {json.dumps(event, indent=2)}")
    
    # Extract event details
    for record in event.get('Records', []):
        event_source = record.get('source', 'unknown')
        event_detail_type = record.get('detail-type', 'unknown')
        event_detail = record.get('detail', {})
        
        # Process the event (implement your business logic here)
        process_business_event(event_source, event_detail_type, event_detail, region)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Events processed successfully in {region}',
            'timestamp': datetime.utcnow().isoformat(),
            'region': region
        })
    }

def process_business_event(source, detail_type, detail, region):
    """Process business events with region-specific logic"""
    
    # Example: Handle financial transaction events
    if source == 'finance.transactions' and detail_type == 'Transaction Created':
        transaction_id = detail.get('transactionId')
        amount = detail.get('amount')
        
        print(f"Processing transaction {transaction_id} "
              f"for amount {amount} in region {region}")
        
        # Implement your business logic here
        # Examples: update databases, send notifications, etc.
        
    # Example: Handle user events
    elif source == 'user.management' and detail_type == 'User Action':
        user_id = detail.get('userId')
        action = detail.get('action')
        
        print(f"Processing user action {action} for user {user_id} "
              f"in region {region}")
EOF
    
    # Create deployment package
    cd "${SCRIPT_DIR}"
    zip -q lambda_function.zip lambda_function.py
    
    # Deploy Lambda functions to all regions
    local regions=("${PRIMARY_REGION}" "${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        debug "Deploying Lambda function to region: $region"
        
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda_function.zip \
            --timeout 30 \
            --region "$region" \
            --tags Purpose=EventProcessing,Environment=Production
        
        wait_for_resource "lambda" "${LAMBDA_FUNCTION_NAME}" "$region"
        debug "Lambda function deployed to region: $region"
    done
    
    # Clean up temporary files
    rm -f lambda_function.py lambda_function.zip
    
    log "Lambda functions deployed to all regions"
}

# Create EventBridge rules
create_eventbridge_rules() {
    log "Creating EventBridge rules for cross-region replication..."
    
    # Create rule in primary region for cross-region replication
    aws events put-rule \
        --name "cross-region-replication-rule" \
        --event-pattern '{
            "source": ["finance.transactions", "user.management"],
            "detail-type": ["Transaction Created", "User Action"],
            "detail": {
                "priority": ["high", "critical"]
            }
        }' \
        --state ENABLED \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --region "${PRIMARY_REGION}"
    
    # Create rules in secondary and tertiary regions for local processing
    local regions=("${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        aws events put-rule \
            --name "local-processing-rule" \
            --event-pattern '{
                "source": ["finance.transactions", "user.management"],
                "detail-type": ["Transaction Created", "User Action"]
            }' \
            --state ENABLED \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --region "$region"
        
        debug "Local processing rule created in region: $region"
    done
    
    log "EventBridge rules created"
}

# Configure EventBridge targets
configure_eventbridge_targets() {
    log "Configuring EventBridge targets..."
    
    # Add cross-region targets to primary region rule
    aws events put-targets \
        --rule cross-region-replication-rule \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --targets "[
            {
                \"Id\": \"1\",
                \"Arn\": \"arn:aws:events:${SECONDARY_REGION}:${AWS_ACCOUNT_ID}:event-bus/${EVENT_BUS_NAME}\",
                \"RoleArn\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/eventbridge-cross-region-role\"
            },
            {
                \"Id\": \"2\", 
                \"Arn\": \"arn:aws:events:${TERTIARY_REGION}:${AWS_ACCOUNT_ID}:event-bus/${EVENT_BUS_NAME}\",
                \"RoleArn\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/eventbridge-cross-region-role\"
            },
            {
                \"Id\": \"3\",
                \"Arn\": \"arn:aws:lambda:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}\"
            }
        ]" \
        --region "${PRIMARY_REGION}"
    
    # Add Lambda targets to secondary and tertiary regions
    local regions=("${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        aws events put-targets \
            --rule local-processing-rule \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --targets "[
                {
                    \"Id\": \"1\",
                    \"Arn\": \"arn:aws:lambda:${region}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}\"
                }
            ]" \
            --region "$region"
        
        debug "Lambda target configured in region: $region"
    done
    
    log "EventBridge targets configured"
}

# Create Route 53 health check and global endpoint
create_global_endpoint() {
    log "Creating Route 53 health check and global endpoint..."
    
    # Create Route 53 health check
    HEALTH_CHECK_ID=$(aws route53 create-health-check \
        --caller-reference "${HEALTH_CHECK_NAME}-$(date +%s)" \
        --health-check-config '{
            "Type": "HTTPS",
            "ResourcePath": "/",
            "FullyQualifiedDomainName": "events.'${PRIMARY_REGION}'.amazonaws.com",
            "Port": 443,
            "RequestInterval": 30,
            "FailureThreshold": 3
        }' \
        --query HealthCheck.Id --output text)
    
    debug "Health check created: $HEALTH_CHECK_ID"
    
    # Create global endpoint
    aws events create-endpoint \
        --name "${GLOBAL_ENDPOINT_NAME}" \
        --routing-config '{
            "FailoverConfig": {
                "Primary": {
                    "HealthCheck": "'${HEALTH_CHECK_ID}'"
                },
                "Secondary": {
                    "Route": "'${SECONDARY_REGION}'"
                }
            }
        }' \
        --replication-config '{
            "State": "ENABLED"
        }' \
        --event-buses '[
            {
                "EventBusArn": "arn:aws:events:'${PRIMARY_REGION}':'${AWS_ACCOUNT_ID}':event-bus/'${EVENT_BUS_NAME}'"
            },
            {
                "EventBusArn": "arn:aws:events:'${SECONDARY_REGION}':'${AWS_ACCOUNT_ID}':event-bus/'${EVENT_BUS_NAME}'"
            }
        ]' \
        --region "${PRIMARY_REGION}"
    
    GLOBAL_ENDPOINT_ARN=$(aws events describe-endpoint \
        --name "${GLOBAL_ENDPOINT_NAME}" \
        --region "${PRIMARY_REGION}" \
        --query EndpointArn --output text)
    
    log "Global endpoint created: ${GLOBAL_ENDPOINT_ARN}"
}

# Set up CloudWatch monitoring
setup_monitoring() {
    log "Setting up CloudWatch monitoring and alarms..."
    
    # Create CloudWatch alarm for failed events
    aws cloudwatch put-metric-alarm \
        --alarm-name "EventBridge-FailedInvocations-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when EventBridge rule fails" \
        --metric-name FailedInvocations \
        --namespace AWS/Events \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=RuleName,Value=cross-region-replication-rule \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --region "${PRIMARY_REGION}"
    
    # Create CloudWatch alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "Lambda-Errors-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when Lambda function errors occur" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 3 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=FunctionName,Value="${LAMBDA_FUNCTION_NAME}" \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --region "${PRIMARY_REGION}"
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "EventBridge-MultiRegion-${RANDOM_SUFFIX}" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            ["AWS/Events", "SuccessfulInvocations", "RuleName", "cross-region-replication-rule"],
                            [".", "FailedInvocations", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'${PRIMARY_REGION}'",
                        "title": "EventBridge Rule Performance"
                    }
                },
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            ["AWS/Lambda", "Invocations", "FunctionName", "'${LAMBDA_FUNCTION_NAME}'"],
                            [".", "Errors", ".", "."],
                            [".", "Duration", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'${PRIMARY_REGION}'",
                        "title": "Lambda Function Performance"
                    }
                }
            ]
        }' \
        --region "${PRIMARY_REGION}"
    
    log "CloudWatch monitoring and alarms configured"
}

# Create event pattern templates
create_event_patterns() {
    log "Creating event pattern templates..."
    
    # Create specialized rules for different event types
    local patterns=(
        "financial-events-rule:finance.transactions,finance.payments:Transaction Created,Payment Processed,Fraud Detected"
        "user-events-rule:user.management,user.authentication:User Login,User Logout,Password Reset"
        "system-events-rule:system.monitoring,system.alerts:System Error,Performance Alert,Security Incident"
    )
    
    for pattern in "${patterns[@]}"; do
        IFS=':' read -r rule_name sources detail_types <<< "$pattern"
        
        # Create event pattern JSON
        local event_pattern=$(cat <<EOF
{
    "source": [$(echo "$sources" | sed 's/,/", "/g' | sed 's/^/"/; s/$/"/')]
}
EOF
        )
        
        aws events put-rule \
            --name "$rule_name" \
            --event-pattern "$event_pattern" \
            --state ENABLED \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --region "${PRIMARY_REGION}"
        
        debug "Event pattern rule created: $rule_name"
    done
    
    log "Event pattern templates created"
}

# Test the deployment
test_deployment() {
    log "Testing deployment..."
    
    # Create test event
    local test_event='[
        {
            "Source": "finance.transactions",
            "DetailType": "Transaction Created",
            "Detail": "{\"transactionId\":\"tx-test-001\",\"amount\":\"1000.00\",\"currency\":\"USD\",\"priority\":\"high\"}",
            "EventBusName": "'${EVENT_BUS_NAME}'"
        }
    ]'
    
    # Send test event
    aws events put-events \
        --entries "$test_event" \
        --region "${PRIMARY_REGION}"
    
    log "Test event sent successfully"
    
    # Wait for processing
    sleep 15
    
    # Check if Lambda functions processed the event
    local regions=("${PRIMARY_REGION}" "${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        local log_group="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        if aws logs describe-log-groups \
            --log-group-name-prefix "$log_group" \
            --region "$region" \
            --query 'logGroups[0].logGroupName' \
            --output text >/dev/null 2>&1; then
            debug "Lambda function logs available in region: $region"
        else
            warn "Lambda function logs not available in region: $region"
        fi
    done
    
    log "Deployment test completed"
}

# Save deployment configuration
save_deployment_config() {
    log "Saving deployment configuration..."
    
    cat > "${SCRIPT_DIR}/deployment_config.json" << EOF
{
    "deployment_id": "eventbridge-multiregion-${RANDOM_SUFFIX}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "regions": {
        "primary": "${PRIMARY_REGION}",
        "secondary": "${SECONDARY_REGION}",
        "tertiary": "${TERTIARY_REGION}"
    },
    "resources": {
        "event_bus_name": "${EVENT_BUS_NAME}",
        "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
        "global_endpoint_name": "${GLOBAL_ENDPOINT_NAME}",
        "health_check_name": "${HEALTH_CHECK_NAME}",
        "sns_topic_arn": "${SNS_TOPIC_ARN}",
        "global_endpoint_arn": "${GLOBAL_ENDPOINT_ARN}",
        "health_check_id": "${HEALTH_CHECK_ID}"
    },
    "account_id": "${AWS_ACCOUNT_ID}",
    "random_suffix": "${RANDOM_SUFFIX}"
}
EOF
    
    log "Deployment configuration saved to: ${SCRIPT_DIR}/deployment_config.json"
}

# Main deployment function
main() {
    log "Starting AWS Multi-Region EventBridge deployment..."
    
    # Check if dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "DRY RUN MODE: No resources will be created"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    validate_regions
    
    # Set up environment
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(get_account_id)
    
    export RANDOM_SUFFIX
    RANDOM_SUFFIX=$(generate_random_suffix)
    
    # Set resource names
    export EVENT_BUS_NAME="global-events-bus-${RANDOM_SUFFIX}"
    export GLOBAL_ENDPOINT_NAME="global-endpoint-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="event-processor-${RANDOM_SUFFIX}"
    export HEALTH_CHECK_NAME="eventbridge-health-${RANDOM_SUFFIX}"
    
    log "Deployment ID: eventbridge-multiregion-${RANDOM_SUFFIX}"
    log "AWS Account: ${AWS_ACCOUNT_ID}"
    log "Regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
    
    # Create resources
    create_iam_roles
    create_sns_topic
    create_event_buses
    create_lambda_functions
    create_eventbridge_rules
    configure_eventbridge_targets
    create_global_endpoint
    setup_monitoring
    create_event_patterns
    
    # Test deployment
    test_deployment
    
    # Save configuration
    save_deployment_config
    
    log "Deployment completed successfully!"
    log "Configuration saved to: ${SCRIPT_DIR}/deployment_config.json"
    log "Global endpoint ARN: ${GLOBAL_ENDPOINT_ARN}"
    log "SNS topic ARN: ${SNS_TOPIC_ARN}"
    
    # Print next steps
    echo
    echo "Next steps:"
    echo "1. Configure your application to send events to the global endpoint"
    echo "2. Set up SNS topic subscriptions for alert notifications"
    echo "3. Review CloudWatch dashboard: EventBridge-MultiRegion-${RANDOM_SUFFIX}"
    echo "4. Test failover scenarios using the health check"
    echo
    echo "To clean up resources, run: ./destroy.sh"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --primary-region)
            PRIMARY_REGION="$2"
            shift 2
            ;;
        --secondary-region)
            SECONDARY_REGION="$2"
            shift 2
            ;;
        --tertiary-region)
            TERTIARY_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Check prerequisites without creating resources"
            echo "  --debug                Enable debug logging"
            echo "  --primary-region       Primary AWS region (default: us-east-1)"
            echo "  --secondary-region     Secondary AWS region (default: us-west-2)"
            echo "  --tertiary-region      Tertiary AWS region (default: eu-west-1)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"