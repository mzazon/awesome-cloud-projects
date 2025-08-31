#!/bin/bash

# AWS Infrastructure Monitoring Quick Setup - Deployment Script
# This script deploys Systems Manager and CloudWatch monitoring infrastructure
# Based on the infrastructure-monitoring-quick-setup recipe

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 could not be found. Please install $1 and try again."
        exit 1
    fi
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        log "Please run 'aws configure' or set AWS credentials and try again."
        exit 1
    fi
    log_success "AWS CLI authentication verified"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    check_command "aws"
    
    # Check AWS authentication
    check_aws_auth
    
    # Check if jq is available (optional but helpful)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region (use configured region or default to us-east-1)
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No AWS region configured, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Store values for cleanup script
    echo "AWS_REGION=${AWS_REGION}" > .env
    echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> .env
    echo "RANDOM_SUFFIX=${RANDOM_SUFFIX}" >> .env
    
    log_success "Environment configured: Region=${AWS_REGION}, Account=${AWS_ACCOUNT_ID}, Suffix=${RANDOM_SUFFIX}"
}

# Function to verify EC2 instances exist
verify_ec2_instances() {
    log "Checking for EC2 instances to monitor..."
    
    local instance_count
    instance_count=$(aws ec2 describe-instances \
        --query 'length(Reservations[*].Instances[?State.Name==`running`])' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$instance_count" -eq 0 ]]; then
        log_warning "No running EC2 instances found. Some monitoring features may not show data immediately."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    else
        log_success "Found ${instance_count} running EC2 instances for monitoring"
    fi
}

# Function to create IAM service role
create_iam_role() {
    log "Creating IAM service role for Systems Manager..."
    
    local role_name="SSMServiceRole-${RANDOM_SUFFIX}"
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        log_warning "IAM role $role_name already exists, skipping creation"
        return 0
    fi
    
    # Create IAM role
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "Service": "ssm.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
            }
          ]
        }' > /dev/null
    
    # Attach required policies
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    
    log_success "IAM service role created: $role_name"
}

# Function to create CloudWatch Agent configuration
create_cloudwatch_config() {
    log "Creating CloudWatch Agent configuration..."
    
    local param_name="AmazonCloudWatch-Agent-Config-${RANDOM_SUFFIX}"
    
    # Check if parameter already exists
    if aws ssm get-parameter --name "$param_name" &>/dev/null; then
        log_warning "CloudWatch Agent configuration $param_name already exists, updating..."
    fi
    
    aws ssm put-parameter \
        --name "$param_name" \
        --type "String" \
        --value '{
          "metrics": {
            "namespace": "CWAgent",
            "metrics_collected": {
              "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],
                "metrics_collection_interval": 60
              },
              "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
              },
              "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
              }
            }
          }
        }' \
        --overwrite > /dev/null
    
    log_success "CloudWatch Agent configuration stored in Parameter Store"
}

# Function to create monitoring dashboard
create_dashboard() {
    log "Creating infrastructure monitoring dashboard..."
    
    local dashboard_name="Infrastructure-Monitoring-${RANDOM_SUFFIX}"
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body '{
          "widgets": [
            {
              "type": "metric",
              "width": 12,
              "height": 6,
              "properties": {
                "metrics": [
                  ["AWS/EC2", "CPUUtilization"],
                  ["AWS/EC2", "NetworkIn"],
                  ["AWS/EC2", "NetworkOut"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "'${AWS_REGION}'",
                "title": "EC2 Instance Performance"
              }
            },
            {
              "type": "metric",
              "width": 12,
              "height": 6,
              "properties": {
                "metrics": [
                  ["AWS/SSM-RunCommand", "CommandsSucceeded"],
                  ["AWS/SSM-RunCommand", "CommandsFailed"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "'${AWS_REGION}'",
                "title": "Systems Manager Operations"
              }
            }
          ]
        }' > /dev/null
    
    log_success "Infrastructure monitoring dashboard created: $dashboard_name"
}

# Function to create CloudWatch alarms
create_alarms() {
    log "Creating CloudWatch alarms for critical metrics..."
    
    # Create CPU utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "High-CPU-Utilization-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when CPU exceeds 80%" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching > /dev/null
    
    # Create disk space alarm (requires CloudWatch Agent)
    aws cloudwatch put-metric-alarm \
        --alarm-name "High-Disk-Usage-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when disk usage exceeds 85%" \
        --metric-name used_percent \
        --namespace CWAgent \
        --statistic Average \
        --period 300 \
        --threshold 85 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 > /dev/null
    
    log_success "Critical infrastructure alarms configured"
}

# Function to create compliance monitoring
create_compliance_monitoring() {
    log "Setting up compliance monitoring..."
    
    # Create compliance association for security baselines
    aws ssm create-association \
        --name "AWS-GatherSoftwareInventory" \
        --targets "Key=tag:Environment,Values=*" \
        --schedule-expression "rate(1 day)" \
        --association-name "Daily-Inventory-Collection-${RANDOM_SUFFIX}" > /dev/null
    
    # Create patch baseline association
    aws ssm create-association \
        --name "AWS-RunPatchBaseline" \
        --targets "Key=tag:Environment,Values=*" \
        --schedule-expression "rate(7 days)" \
        --association-name "Weekly-Patch-Scanning-${RANDOM_SUFFIX}" \
        --parameters "Operation=Scan" > /dev/null
    
    log_success "Compliance monitoring and patch scanning configured"
}

# Function to create log groups
create_log_groups() {
    log "Creating CloudWatch log groups..."
    
    # Create log group for system logs
    aws logs create-log-group \
        --log-group-name "/aws/systems-manager/infrastructure-${RANDOM_SUFFIX}" \
        --retention-in-days 30 > /dev/null 2>&1 || log_warning "System log group may already exist"
    
    # Create log group for application logs
    aws logs create-log-group \
        --log-group-name "/aws/ec2/application-logs-${RANDOM_SUFFIX}" \
        --retention-in-days 14 > /dev/null 2>&1 || log_warning "Application log group may already exist"
    
    # Create log stream for Run Command outputs
    aws logs create-log-stream \
        --log-group-name "/aws/systems-manager/infrastructure-${RANDOM_SUFFIX}" \
        --log-stream-name "run-command-outputs" > /dev/null 2>&1 || log_warning "Log stream may already exist"
    
    log_success "Centralized logging configured with retention policies"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Systems Manager managed instances
    local managed_instances
    managed_instances=$(aws ssm describe-instance-information \
        --query 'length(InstanceInformationList)' \
        --output text 2>/dev/null || echo "0")
    
    log "Found $managed_instances Systems Manager managed instances"
    
    # Check CloudWatch metrics
    local metrics_count
    metrics_count=$(aws cloudwatch list-metrics \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --query 'length(Metrics)' \
        --output text 2>/dev/null || echo "0")
    
    log "Found $metrics_count CloudWatch EC2 metrics"
    
    # Check alarm status
    local alarm_status
    alarm_status=$(aws cloudwatch describe-alarms \
        --alarm-names "High-CPU-Utilization-${RANDOM_SUFFIX}" \
        --query 'MetricAlarms[0].StateValue' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    log "CPU utilization alarm status: $alarm_status"
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "- IAM Role: SSMServiceRole-${RANDOM_SUFFIX}"
    echo "- CloudWatch Dashboard: Infrastructure-Monitoring-${RANDOM_SUFFIX}"
    echo "- CloudWatch Parameter: AmazonCloudWatch-Agent-Config-${RANDOM_SUFFIX}"
    echo "- CloudWatch Alarms: High-CPU-Utilization-${RANDOM_SUFFIX}, High-Disk-Usage-${RANDOM_SUFFIX}"
    echo "- SSM Associations: Daily-Inventory-Collection-${RANDOM_SUFFIX}, Weekly-Patch-Scanning-${RANDOM_SUFFIX}"
    echo "- Log Groups: /aws/systems-manager/infrastructure-${RANDOM_SUFFIX}, /aws/ec2/application-logs-${RANDOM_SUFFIX}"
    echo ""
    echo "Next Steps:"
    echo "1. View your CloudWatch dashboard in the AWS Console"
    echo "2. Check CloudWatch alarms for any immediate alerts"
    echo "3. Verify EC2 instances are appearing in Systems Manager"
    echo "4. Review compliance data as it becomes available"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "===================="
}

# Main deployment function
main() {
    log "Starting AWS Infrastructure Monitoring Quick Setup deployment..."
    
    # Run prerequisite checks
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Verify EC2 instances
    verify_ec2_instances
    
    # Deploy infrastructure components
    create_iam_role
    create_cloudwatch_config
    create_dashboard
    create_alarms
    create_compliance_monitoring
    create_log_groups
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
    
    log_success "AWS Infrastructure Monitoring deployment completed successfully!"
}

# Error handling
trap 'log_error "Deployment failed on line $LINENO. Check the error above."' ERR

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi