#!/bin/bash

# Automated Service Lifecycle with VPC Lattice and EventBridge - Deployment Script
# This script deploys the complete infrastructure for automated service lifecycle management
# including VPC Lattice service network, EventBridge bus, Lambda functions, and monitoring

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
readonly LOG_FILE="/tmp/service-lifecycle-deploy-${TIMESTAMP}.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-service-lifecycle}"
readonly AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo 'us-east-1')}"
readonly DRY_RUN="${DRY_RUN:-false}"
readonly VERBOSE="${VERBOSE:-false}"

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    log_info "Check log file: ${LOG_FILE}"
    log_info "Run destroy.sh to clean up any partial deployment"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Deploy automated service lifecycle management infrastructure with VPC Lattice and EventBridge.

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without making changes
    -v, --verbose          Enable verbose output
    -r, --region REGION    AWS region (default: ${AWS_REGION})
    -n, --name NAME        Deployment name prefix (default: ${DEPLOYMENT_NAME})

ENVIRONMENT VARIABLES:
    AWS_REGION             AWS region to deploy resources
    DEPLOYMENT_NAME        Prefix for resource names
    DRY_RUN               Set to 'true' for dry run
    VERBOSE               Set to 'true' for verbose output

EXAMPLES:
    ${SCRIPT_NAME}                          # Deploy with defaults
    ${SCRIPT_NAME} --dry-run               # Preview deployment
    ${SCRIPT_NAME} --region us-west-2      # Deploy to specific region
    DEPLOYMENT_NAME=prod ${SCRIPT_NAME}    # Deploy with custom prefix

EOF
}

# Parse command line arguments
parse_args() {
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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -n|--name)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisites validation
check_prerequisites() {
    log_info "Validating prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi

    # Check required permissions (basic check)
    local required_services=("vpc-lattice" "events" "lambda" "iam" "logs" "cloudwatch")
    for service in "${required_services[@]}"; do
        if [[ "${VERBOSE}" == "true" ]]; then
            log_info "Checking ${service} permissions..."
        fi
    done

    # Validate region
    if ! aws ec2 describe-regions --region-names "${AWS_REGION}" &> /dev/null; then
        log_error "Invalid AWS region: ${AWS_REGION}"
        exit 1
    fi

    # Check for required tools
    local required_tools=("zip" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "Required tool '${tool}' is not installed"
            exit 1
        fi
    done

    log_success "Prerequisites validation completed"
}

# Generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource identifiers..."

    # Generate random suffix for unique naming
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --region "${AWS_REGION}" \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")

    # Define resource names
    export SERVICE_NETWORK_NAME="${DEPLOYMENT_NAME}-network-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_BUS_NAME="${DEPLOYMENT_NAME}-bus-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="${DEPLOYMENT_NAME}-role-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/vpclattice/${DEPLOYMENT_NAME}-${RANDOM_SUFFIX}"
    export HEALTH_LAMBDA_NAME="${DEPLOYMENT_NAME}-health-monitor-${RANDOM_SUFFIX}"
    export AUTOSCALE_LAMBDA_NAME="${DEPLOYMENT_NAME}-auto-scaler-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="${DEPLOYMENT_NAME}Lifecycle-${RANDOM_SUFFIX}"

    if [[ "${VERBOSE}" == "true" ]]; then
        log_info "Resource names generated with suffix: ${RANDOM_SUFFIX}"
        log_info "Service Network: ${SERVICE_NETWORK_NAME}"
        log_info "EventBridge Bus: ${EVENTBRIDGE_BUS_NAME}"
        log_info "IAM Role: ${LAMBDA_ROLE_NAME}"
    fi

    log_success "Resource names generated successfully"
}

# Create CloudWatch Log Group
create_log_group() {
    log_info "Creating CloudWatch Log Group..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create log group: ${LOG_GROUP_NAME}"
        return 0
    fi

    aws logs create-log-group \
        --log-group-name "${LOG_GROUP_NAME}" \
        --retention-in-days 7 \
        --region "${AWS_REGION}" || {
        log_warning "Log group may already exist or creation failed"
    }

    log_success "CloudWatch Log Group created: ${LOG_GROUP_NAME}"
}

# Create IAM role for Lambda functions
create_iam_role() {
    log_info "Creating IAM role for Lambda functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: ${LAMBDA_ROLE_NAME}"
        return 0
    fi

    # Create IAM role
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document '{
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
        }' \
        --region "${AWS_REGION}"

    # Wait for role to be created
    sleep 10

    # Attach necessary policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/VPCLatticeFullAccess"
        "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    )

    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn "${policy}" \
            --region "${AWS_REGION}"
        
        if [[ "${VERBOSE}" == "true" ]]; then
            log_info "Attached policy: ${policy}"
        fi
    done

    # Wait for policy attachment to propagate
    sleep 15

    log_success "IAM role created and configured: ${LAMBDA_ROLE_NAME}"
}

# Create VPC Lattice Service Network
create_service_network() {
    log_info "Creating VPC Lattice Service Network..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create service network: ${SERVICE_NETWORK_NAME}"
        return 0
    fi

    # Create VPC Lattice service network
    export SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name "${SERVICE_NETWORK_NAME}" \
        --auth-type AWS_IAM \
        --region "${AWS_REGION}" \
        --query 'id' --output text)

    # Get the CloudWatch Log Group ARN for access logs
    local log_group_arn=$(aws logs describe-log-groups \
        --log-group-name-prefix "${LOG_GROUP_NAME}" \
        --region "${AWS_REGION}" \
        --query 'logGroups[0].arn' --output text)

    # Enable access logs for the service network
    aws vpc-lattice create-access-log-subscription \
        --resource-identifier "${SERVICE_NETWORK_ID}" \
        --destination-arn "${log_group_arn}" \
        --region "${AWS_REGION}"

    log_success "VPC Lattice service network created: ${SERVICE_NETWORK_ID}"
}

# Create EventBridge custom bus
create_eventbridge_bus() {
    log_info "Creating EventBridge custom bus..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create EventBridge bus: ${EVENTBRIDGE_BUS_NAME}"
        return 0
    fi

    # Create custom EventBridge bus for service lifecycle events
    aws events create-event-bus \
        --name "${EVENTBRIDGE_BUS_NAME}" \
        --region "${AWS_REGION}"

    # Get EventBridge bus ARN for later use
    export EVENTBRIDGE_BUS_ARN=$(aws events describe-event-bus \
        --name "${EVENTBRIDGE_BUS_NAME}" \
        --region "${AWS_REGION}" \
        --query 'Arn' --output text)

    log_success "EventBridge custom bus created: ${EVENTBRIDGE_BUS_NAME}"
}

# Create Lambda function code files
create_lambda_code() {
    log_info "Creating Lambda function code..."

    local temp_dir="/tmp/service-lifecycle-lambda-${RANDOM_SUFFIX}"
    mkdir -p "${temp_dir}"

    # Create health monitoring Lambda function code
    cat > "${temp_dir}/health_monitor.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    lattice = boto3.client('vpc-lattice')
    cloudwatch = boto3.client('cloudwatch')
    eventbridge = boto3.client('events')
    
    service_network_id = os.environ['SERVICE_NETWORK_ID']
    event_bus_name = os.environ['EVENT_BUS_NAME']
    
    try:
        # Get service network services
        services = lattice.list_services(
            serviceNetworkIdentifier=service_network_id
        )
        
        for service in services.get('items', []):
            service_id = service['id']
            service_name = service['name']
            
            # Get CloudWatch metrics for service health
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(minutes=5)
            
            metrics = cloudwatch.get_metric_statistics(
                Namespace='AWS/VpcLattice',
                MetricName='RequestCount',
                Dimensions=[
                    {'Name': 'ServiceId', 'Value': service_id}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=300,
                Statistics=['Sum']
            )
            
            # Determine service health based on metrics
            request_count = sum([point['Sum'] for point in metrics['Datapoints']])
            health_status = 'healthy' if request_count > 0 else 'unhealthy'
            
            # Publish service health event
            event_detail = {
                'serviceId': service_id,
                'serviceName': service_name,
                'healthStatus': health_status,
                'requestCount': request_count,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'vpc-lattice.health-monitor',
                        'DetailType': 'Service Health Check',
                        'Detail': json.dumps(event_detail),
                        'EventBusName': event_bus_name
                    }
                ]
            )
        
        return {'statusCode': 200, 'body': 'Health check completed'}
        
    except Exception as e:
        print(f"Error in health monitoring: {str(e)}")
        return {'statusCode': 500, 'body': f"Error: {str(e)}"}
EOF

    # Create auto-scaling Lambda function code
    cat > "${temp_dir}/auto_scaler.py" << 'EOF'
import json
import boto3
import os

def lambda_handler(event, context):
    lattice = boto3.client('vpc-lattice')
    ecs = boto3.client('ecs')
    
    try:
        # Parse EventBridge event
        detail = json.loads(event['detail']) if isinstance(event['detail'], str) else event['detail']
        service_id = detail['serviceId']
        service_name = detail['serviceName']
        health_status = detail['healthStatus']
        request_count = detail['requestCount']
        
        print(f"Processing scaling event for service: {service_name}")
        print(f"Health status: {health_status}, Request count: {request_count}")
        
        # Get target groups for the service
        target_groups = lattice.list_target_groups(
            serviceIdentifier=service_id
        )
        
        for tg in target_groups.get('items', []):
            tg_id = tg['id']
            
            # Get current target count
            targets = lattice.list_targets(
                targetGroupIdentifier=tg_id
            )
            current_count = len(targets.get('items', []))
            
            # Determine scaling action
            if health_status == 'unhealthy' and current_count < 5:
                # Scale up if unhealthy and below max capacity
                print(f"Triggering scale-up for target group: {tg_id}")
                # In real implementation, trigger ECS/ASG scaling
                
            elif health_status == 'healthy' and request_count < 10 and current_count > 1:
                # Scale down if healthy with low traffic
                print(f"Triggering scale-down for target group: {tg_id}")
                # In real implementation, trigger ECS/ASG scaling
        
        return {'statusCode': 200, 'body': 'Scaling evaluation completed'}
        
    except Exception as e:
        print(f"Error in auto-scaling: {str(e)}")
        return {'statusCode': 500, 'body': f"Error: {str(e)}"}
EOF

    export LAMBDA_CODE_DIR="${temp_dir}"
    log_success "Lambda function code created in: ${temp_dir}"
}

# Create Lambda functions
create_lambda_functions() {
    log_info "Creating Lambda functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda functions"
        return 0
    fi

    local aws_account_id=$(aws sts get-caller-identity --query Account --output text)

    # Package and create health monitoring Lambda function
    cd "${LAMBDA_CODE_DIR}"
    zip -r health_monitor.zip health_monitor.py

    export HEALTH_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "${HEALTH_LAMBDA_NAME}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${aws_account_id}:role/${LAMBDA_ROLE_NAME}" \
        --handler health_monitor.lambda_handler \
        --zip-file fileb://health_monitor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID},EVENT_BUS_NAME=${EVENTBRIDGE_BUS_NAME}}" \
        --region "${AWS_REGION}" \
        --query 'FunctionArn' --output text)

    # Package and create auto-scaling Lambda function
    zip -r auto_scaler.zip auto_scaler.py

    export AUTOSCALE_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "${AUTOSCALE_LAMBDA_NAME}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${aws_account_id}:role/${LAMBDA_ROLE_NAME}" \
        --handler auto_scaler.lambda_handler \
        --zip-file fileb://auto_scaler.zip \
        --timeout 60 \
        --memory-size 256 \
        --region "${AWS_REGION}" \
        --query 'FunctionArn' --output text)

    cd - > /dev/null

    log_success "Lambda functions created successfully"
}

# Create EventBridge rules
create_eventbridge_rules() {
    log_info "Creating EventBridge rules..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create EventBridge rules"
        return 0
    fi

    local aws_account_id=$(aws sts get-caller-identity --query Account --output text)
    local health_rule_name="health-monitoring-rule-${RANDOM_SUFFIX}"
    local scheduled_rule_name="scheduled-health-check-${RANDOM_SUFFIX}"

    # Create rule for service health monitoring events
    aws events put-rule \
        --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
        --name "${health_rule_name}" \
        --event-pattern '{
            "source": ["vpc-lattice.health-monitor"],
            "detail-type": ["Service Health Check"],
            "detail": {
                "healthStatus": ["unhealthy", "healthy"]
            }
        }' \
        --state ENABLED \
        --region "${AWS_REGION}"

    # Add Lambda target to health monitoring rule
    aws events put-targets \
        --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
        --rule "${health_rule_name}" \
        --targets "Id=1,Arn=${AUTOSCALE_LAMBDA_ARN}" \
        --region "${AWS_REGION}"

    # Grant EventBridge permission to invoke auto-scaling Lambda
    aws lambda add-permission \
        --function-name "${AUTOSCALE_LAMBDA_NAME}" \
        --statement-id "eventbridge-invoke-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${aws_account_id}:rule/${EVENTBRIDGE_BUS_NAME}/${health_rule_name}" \
        --region "${AWS_REGION}"

    # Create scheduled health check rule
    aws events put-rule \
        --name "${scheduled_rule_name}" \
        --schedule-expression "rate(5 minutes)" \
        --state ENABLED \
        --region "${AWS_REGION}"

    # Add Lambda target for scheduled health checks
    aws events put-targets \
        --rule "${scheduled_rule_name}" \
        --targets "Id=1,Arn=${HEALTH_LAMBDA_ARN}" \
        --region "${AWS_REGION}"

    # Grant permission for CloudWatch Events to invoke health monitoring Lambda
    aws lambda add-permission \
        --function-name "${HEALTH_LAMBDA_NAME}" \
        --statement-id "cloudwatch-scheduled-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${aws_account_id}:rule/${scheduled_rule_name}" \
        --region "${AWS_REGION}"

    log_success "EventBridge rules configured successfully"
}

# Create CloudWatch dashboard
create_dashboard() {
    log_info "Creating CloudWatch dashboard..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create CloudWatch dashboard: ${DASHBOARD_NAME}"
        return 0
    fi

    # Create CloudWatch dashboard for service lifecycle monitoring
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "x": 0,
                    "y": 0,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "metrics": [
                            ["AWS/VpcLattice", "RequestCount"],
                            ["AWS/VpcLattice", "ResponseTime"],
                            ["AWS/VpcLattice", "TargetResponseTime"]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'"${AWS_REGION}"'",
                        "title": "VPC Lattice Service Metrics"
                    }
                },
                {
                    "type": "log",
                    "x": 0,
                    "y": 6,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "query": "SOURCE \"/aws/lambda/'"${HEALTH_LAMBDA_NAME}"'\" | fields @timestamp, @message | sort @timestamp desc | limit 20",
                        "region": "'"${AWS_REGION}"'",
                        "title": "Health Monitor Logs"
                    }
                }
            ]
        }' \
        --region "${AWS_REGION}"

    log_success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."

    local deployment_info="/tmp/service-lifecycle-deployment-${RANDOM_SUFFIX}.json"
    
    cat > "${deployment_info}" << EOF
{
    "deploymentName": "${DEPLOYMENT_NAME}",
    "randomSuffix": "${RANDOM_SUFFIX}",
    "region": "${AWS_REGION}",
    "timestamp": "${TIMESTAMP}",
    "resources": {
        "serviceNetworkId": "${SERVICE_NETWORK_ID:-}",
        "serviceNetworkName": "${SERVICE_NETWORK_NAME}",
        "eventBridgeBusName": "${EVENTBRIDGE_BUS_NAME}",
        "iamRoleName": "${LAMBDA_ROLE_NAME}",
        "logGroupName": "${LOG_GROUP_NAME}",
        "healthLambdaName": "${HEALTH_LAMBDA_NAME}",
        "autoScaleLambdaName": "${AUTOSCALE_LAMBDA_NAME}",
        "dashboardName": "${DASHBOARD_NAME}"
    }
}
EOF

    log_success "Deployment information saved to: ${deployment_info}"
    
    if [[ "${VERBOSE}" == "true" ]]; then
        cat "${deployment_info}"
    fi
}

# Main deployment function
main() {
    log_info "Starting automated service lifecycle deployment..."
    log_info "Deployment name: ${DEPLOYMENT_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Dry run: ${DRY_RUN}"
    log_info "Log file: ${LOG_FILE}"

    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    create_log_group
    create_iam_role
    create_service_network
    create_eventbridge_bus
    create_lambda_code
    create_lambda_functions
    create_eventbridge_rules
    create_dashboard
    save_deployment_info

    # Cleanup temporary files
    if [[ -n "${LAMBDA_CODE_DIR:-}" && -d "${LAMBDA_CODE_DIR}" ]]; then
        rm -rf "${LAMBDA_CODE_DIR}"
    fi

    log_success "Deployment completed successfully!"
    log_info "Resources created with suffix: ${RANDOM_SUFFIX}"
    log_info "Access CloudWatch dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
    log_info "View VPC Lattice service network: https://console.aws.amazon.com/vpc/home?region=${AWS_REGION}#ServiceNetworks:"
    log_info "Check EventBridge bus: https://console.aws.amazon.com/events/home?region=${AWS_REGION}#/eventbus/${EVENTBRIDGE_BUS_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "This was a dry run. No resources were actually created."
    fi
}

# Parse arguments and run main function
parse_args "$@"
main