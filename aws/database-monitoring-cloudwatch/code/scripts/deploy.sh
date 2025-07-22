#!/bin/bash

# =============================================================================
# AWS Database Monitoring Dashboards Deployment Script
# =============================================================================
# This script deploys a comprehensive database monitoring solution using:
# - Amazon RDS (MySQL) with enhanced monitoring
# - CloudWatch dashboards and alarms
# - SNS notifications for alerting
# - IAM roles for enhanced monitoring
# 
# Author: AWS Recipe Generator
# Version: 1.0
# Last Updated: 2025-01-17
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
readonly RESOURCE_PREFIX="db-monitoring"
readonly DB_PASSWORD="MySecurePassword123!"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO" "$*"
}

success() {
    echo -e "${GREEN}✅${NC} $*"
    log "SUCCESS" "$*"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $*"
    log "WARNING" "$*"
}

error() {
    echo -e "${RED}❌${NC} $*" >&2
    log "ERROR" "$*"
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code: $exit_code"
        error "Check the log file for details: ${LOG_FILE}"
        warning "To clean up partial deployment, run: ${SCRIPT_DIR}/destroy.sh"
    fi
}

wait_for_resource() {
    local resource_type=$1
    local resource_id=$2
    local max_attempts=${3:-30}
    local wait_time=${4:-30}
    
    info "Waiting for ${resource_type} ${resource_id} to be ready..."
    
    case "${resource_type}" in
        "rds-instance")
            aws rds wait db-instance-available \
                --db-instance-identifier "${resource_id}" \
                --cli-read-timeout "${max_attempts}" \
                --cli-connect-timeout "${wait_time}"
            ;;
        *)
            error "Unknown resource type: ${resource_type}"
            return 1
            ;;
    esac
}

# =============================================================================
# Validation Functions
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: ${aws_version}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Get AWS account information
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    if [[ -z "${AWS_REGION}" ]]; then
        error "AWS region not configured. Please run 'aws configure set region <region>'."
        exit 1
    fi
    
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "AWS Region: ${AWS_REGION}"
    
    # Check required permissions
    info "Checking AWS permissions..."
    local required_services=("rds" "cloudwatch" "sns" "iam")
    
    for service in "${required_services[@]}"; do
        case "${service}" in
            "rds")
                if ! aws rds describe-db-instances --max-items 1 &> /dev/null; then
                    error "Missing RDS permissions. Required: rds:DescribeDBInstances, rds:CreateDBInstance, etc."
                    exit 1
                fi
                ;;
            "cloudwatch")
                if ! aws cloudwatch list-dashboards --max-items 1 &> /dev/null; then
                    error "Missing CloudWatch permissions. Required: cloudwatch:ListDashboards, cloudwatch:PutDashboard, etc."
                    exit 1
                fi
                ;;
            "sns")
                if ! aws sns list-topics --max-items 1 &> /dev/null; then
                    error "Missing SNS permissions. Required: sns:ListTopics, sns:CreateTopic, etc."
                    exit 1
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    error "Missing IAM permissions. Required: iam:ListRoles, iam:CreateRole, etc."
                    exit 1
                fi
                ;;
        esac
    done
    
    success "Prerequisites check completed successfully"
}

prompt_user_confirmation() {
    echo
    warning "This script will create the following AWS resources:"
    echo "  • RDS MySQL instance (db.t3.micro)"
    echo "  • CloudWatch dashboard and alarms"
    echo "  • SNS topic for notifications"
    echo "  • IAM role for enhanced monitoring"
    echo
    warning "Estimated monthly cost: \$15-30 (varies by region and usage)"
    echo
    
    if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Deployment cancelled by user"
            exit 0
        fi
    fi
}

validate_email() {
    local email=$1
    if [[ ! "${email}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: ${email}"
        return 1
    fi
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

generate_unique_identifiers() {
    info "Generating unique resource identifiers..."
    
    # Generate random suffix for unique naming
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export DB_INSTANCE_ID="${RESOURCE_PREFIX}-${random_suffix}"
    export SNS_TOPIC_NAME="database-alerts-${random_suffix}"
    export DASHBOARD_NAME="DatabaseMonitoring-${random_suffix}"
    export IAM_ROLE_NAME="rds-monitoring-role-${random_suffix}"
    
    info "Resource identifiers generated:"
    info "  DB Instance ID: ${DB_INSTANCE_ID}"
    info "  SNS Topic: ${SNS_TOPIC_NAME}"
    info "  Dashboard: ${DASHBOARD_NAME}"
    info "  IAM Role: ${IAM_ROLE_NAME}"
    
    # Store identifiers for cleanup script
    cat > "${SCRIPT_DIR}/deployment_state.env" << EOF
DB_INSTANCE_ID="${DB_INSTANCE_ID}"
SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
DASHBOARD_NAME="${DASHBOARD_NAME}"
IAM_ROLE_NAME="${IAM_ROLE_NAME}"
AWS_REGION="${AWS_REGION}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    success "Unique identifiers generated and saved"
}

get_user_email() {
    if [[ -n "${ALERT_EMAIL:-}" ]]; then
        info "Using provided email address: ${ALERT_EMAIL}"
        validate_email "${ALERT_EMAIL}"
    else
        echo
        read -p "Enter email address for database alerts: " ALERT_EMAIL
        validate_email "${ALERT_EMAIL}"
    fi
    
    export ALERT_EMAIL
}

create_iam_role() {
    info "Creating IAM role for RDS enhanced monitoring..."
    
    # Create trust policy document
    local trust_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "monitoring.rds.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
    
    # Create the IAM role
    if aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document "${trust_policy}" \
        --description "IAM role for RDS enhanced monitoring" \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "IAM role created: ${IAM_ROLE_NAME}"
    else
        error "Failed to create IAM role"
        return 1
    fi
    
    # Attach the required policy
    if aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole" \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "Policy attached to IAM role"
    else
        error "Failed to attach policy to IAM role"
        return 1
    fi
    
    # Get the role ARN
    export MONITORING_ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    info "IAM role ARN: ${MONITORING_ROLE_ARN}"
    
    # Wait a moment for role to propagate
    sleep 10
}

create_rds_instance() {
    info "Creating RDS MySQL instance with enhanced monitoring..."
    
    # Get default VPC security group
    local default_sg
    default_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=default" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    if [[ "${default_sg}" == "None" || -z "${default_sg}" ]]; then
        error "Could not find default security group"
        return 1
    fi
    
    info "Using security group: ${default_sg}"
    
    # Create RDS instance
    if aws rds create-db-instance \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --db-instance-class "db.t3.micro" \
        --engine "mysql" \
        --engine-version "8.0.35" \
        --allocated-storage 20 \
        --master-username "admin" \
        --master-user-password "${DB_PASSWORD}" \
        --vpc-security-group-ids "${default_sg}" \
        --monitoring-interval 60 \
        --monitoring-role-arn "${MONITORING_ROLE_ARN}" \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --backup-retention-period 7 \
        --storage-encrypted \
        --deletion-protection \
        --no-publicly-accessible \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "RDS instance creation initiated: ${DB_INSTANCE_ID}"
    else
        error "Failed to create RDS instance"
        return 1
    fi
    
    # Wait for instance to be available
    wait_for_resource "rds-instance" "${DB_INSTANCE_ID}"
    
    # Get the database endpoint
    export DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    success "RDS instance is available at: ${DB_ENDPOINT}"
}

create_sns_topic() {
    info "Creating SNS topic for database alerts..."
    
    # Create SNS topic
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --query 'TopicArn' --output text)
    
    if [[ -n "${SNS_TOPIC_ARN}" ]]; then
        success "SNS topic created: ${SNS_TOPIC_ARN}"
    else
        error "Failed to create SNS topic"
        return 1
    fi
    
    # Subscribe email to the topic
    if aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${ALERT_EMAIL}" \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "Email subscription created for: ${ALERT_EMAIL}"
        warning "Please check your email and confirm the SNS subscription"
    else
        error "Failed to create email subscription"
        return 1
    fi
}

create_cloudwatch_dashboard() {
    info "Creating CloudWatch dashboard for database metrics..."
    
    # Create dashboard JSON configuration
    local dashboard_body=$(cat << EOF
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
                    ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "Database Performance Overview",
                "period": 300,
                "stat": "Average"
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
                    ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "Storage and Latency Metrics",
                "period": 300,
                "stat": "Average"
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
                    ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    ["AWS/RDS", "ReadThroughput", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    ["AWS/RDS", "WriteThroughput", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "I/O Performance Metrics",
                "period": 300,
                "stat": "Average"
            }
        }
    ]
}
EOF
)
    
    # Create the dashboard
    if aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "${dashboard_body}" \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
    else
        error "Failed to create CloudWatch dashboard"
        return 1
    fi
}

create_cloudwatch_alarms() {
    info "Creating CloudWatch alarms for critical database metrics..."
    
    # CPU Utilization Alarm
    if aws cloudwatch put-metric-alarm \
        --alarm-name "${DB_INSTANCE_ID}-HighCPU" \
        --alarm-description "High CPU utilization on ${DB_INSTANCE_ID}" \
        --metric-name CPUUtilization \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --ok-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_ID}" \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "CPU utilization alarm created"
    else
        error "Failed to create CPU utilization alarm"
        return 1
    fi
    
    # Database Connections Alarm
    if aws cloudwatch put-metric-alarm \
        --alarm-name "${DB_INSTANCE_ID}-HighConnections" \
        --alarm-description "High database connections on ${DB_INSTANCE_ID}" \
        --metric-name DatabaseConnections \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 50 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --ok-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_ID}" \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "Database connections alarm created"
    else
        error "Failed to create database connections alarm"
        return 1
    fi
    
    # Free Storage Space Alarm (2GB threshold)
    if aws cloudwatch put-metric-alarm \
        --alarm-name "${DB_INSTANCE_ID}-LowStorage" \
        --alarm-description "Low free storage space on ${DB_INSTANCE_ID}" \
        --metric-name FreeStorageSpace \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 2147483648 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --ok-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_ID}" \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "Free storage space alarm created"
    else
        error "Failed to create free storage space alarm"
        return 1
    fi
    
    # Read Latency Alarm
    if aws cloudwatch put-metric-alarm \
        --alarm-name "${DB_INSTANCE_ID}-HighReadLatency" \
        --alarm-description "High read latency on ${DB_INSTANCE_ID}" \
        --metric-name ReadLatency \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 0.2 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --ok-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_ID}" \
        --output text >> "${LOG_FILE}" 2>&1; then
        success "Read latency alarm created"
    else
        error "Failed to create read latency alarm"
        return 1
    fi
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_deployment() {
    info "Validating deployment..."
    
    # Check RDS instance status
    local db_status
    db_status=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query 'DBInstances[0].DBInstanceStatus' --output text)
    
    if [[ "${db_status}" == "available" ]]; then
        success "RDS instance is available"
    else
        error "RDS instance status: ${db_status}"
        return 1
    fi
    
    # Check dashboard exists
    if aws cloudwatch get-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --query 'DashboardName' --output text &> /dev/null; then
        success "CloudWatch dashboard exists"
    else
        error "CloudWatch dashboard not found"
        return 1
    fi
    
    # Check alarms exist and get their states
    local alarms=("${DB_INSTANCE_ID}-HighCPU" "${DB_INSTANCE_ID}-HighConnections" "${DB_INSTANCE_ID}-LowStorage" "${DB_INSTANCE_ID}-HighReadLatency")
    
    for alarm in "${alarms[@]}"; do
        local alarm_state
        alarm_state=$(aws cloudwatch describe-alarms \
            --alarm-names "${alarm}" \
            --query 'MetricAlarms[0].StateValue' --output text 2>/dev/null)
        
        if [[ -n "${alarm_state}" ]]; then
            success "Alarm ${alarm}: ${alarm_state}"
        else
            error "Alarm ${alarm} not found"
            return 1
        fi
    done
    
    # Check SNS topic exists
    if aws sns get-topic-attributes \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --query 'Attributes.TopicArn' --output text &> /dev/null; then
        success "SNS topic exists"
    else
        error "SNS topic not found"
        return 1
    fi
    
    success "Deployment validation completed successfully"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    echo "======================================================================="
    echo "      AWS Database Monitoring Dashboards Deployment"
    echo "======================================================================="
    echo
    
    # Set up trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    # Check prerequisites
    check_prerequisites
    
    # Prompt for user confirmation
    prompt_user_confirmation
    
    # Get user email for alerts
    get_user_email
    
    # Generate unique identifiers
    generate_unique_identifiers
    
    echo
    info "Starting deployment process..."
    echo
    
    # Create resources in order
    create_iam_role
    create_rds_instance
    create_sns_topic
    create_cloudwatch_dashboard
    create_cloudwatch_alarms
    
    echo
    info "Validating deployment..."
    validate_deployment
    
    echo
    echo "======================================================================="
    echo "                    DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "======================================================================="
    echo
    success "Database monitoring solution deployed successfully!"
    echo
    info "Resources created:"
    echo "  • RDS Instance: ${DB_INSTANCE_ID}"
    echo "  • Database Endpoint: ${DB_ENDPOINT}"
    echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  • SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo
    info "CloudWatch Dashboard URL:"
    echo "  https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
    echo
    warning "Important next steps:"
    echo "  1. Check your email (${ALERT_EMAIL}) and confirm SNS subscription"
    echo "  2. Review alarm thresholds and adjust if needed"
    echo "  3. Connect to database at: ${DB_ENDPOINT}"
    echo "  4. Database credentials: admin / ${DB_PASSWORD}"
    echo
    warning "Monthly cost estimate: \$15-30 (varies by region and usage)"
    echo
    info "Deployment details saved to: ${SCRIPT_DIR}/deployment_state.env"
    info "Log file: ${LOG_FILE}"
    echo
    success "To clean up resources, run: ${SCRIPT_DIR}/destroy.sh"
    echo
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            ALERT_EMAIL="$2"
            shift 2
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --email EMAIL             Email address for alerts"
            echo "  --skip-confirmation       Skip user confirmation prompt"
            echo "  --help                    Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  ALERT_EMAIL              Email address for alerts"
            echo "  SKIP_CONFIRMATION        Skip confirmation (true/false)"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"