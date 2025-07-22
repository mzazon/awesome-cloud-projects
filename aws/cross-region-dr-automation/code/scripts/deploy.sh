#!/bin/bash

#############################################################################
# AWS Cross-Region Disaster Recovery Automation Deployment Script
# 
# This script deploys AWS Elastic Disaster Recovery (DRS) infrastructure
# with automated failover capabilities across multiple regions.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for DRS, Lambda, CloudWatch, etc.
# - Source servers running supported operating systems
# - Network connectivity between source servers and AWS
#
# Usage: ./deploy.sh [--dry-run] [--force] [--region us-east-1]
#############################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMP_DIR=$(mktemp -d)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_PRIMARY_REGION="us-east-1"
DEFAULT_DR_REGION="us-west-2"
DEFAULT_NOTIFICATION_EMAIL="admin@example.com"
DRY_RUN=false
FORCE_DEPLOY=false

#############################################################################
# Utility Functions
#############################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
    log "INFO" "$*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
    log "SUCCESS" "$*"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
    log "WARNING" "$*"
}

error() {
    echo -e "${RED}❌ $*${NC}"
    log "ERROR" "$*"
}

fatal() {
    error "$*"
    cleanup
    exit 1
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Cross-Region Disaster Recovery Automation

OPTIONS:
    --primary-region REGION     Primary AWS region (default: us-east-1)
    --dr-region REGION          Disaster recovery region (default: us-west-2)
    --notification-email EMAIL  Email for DR notifications (default: admin@example.com)
    --dry-run                   Show what would be deployed without making changes
    --force                     Skip confirmation prompts
    --help                      Show this help message

EXAMPLES:
    $0                                              # Deploy with defaults
    $0 --primary-region us-east-1 --dr-region us-west-2
    $0 --dry-run                                    # Preview deployment
    $0 --force --notification-email ops@company.com

EOF
}

#############################################################################
# Prerequisites Validation
#############################################################################

check_prerequisites() {
    info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI is not installed. Please install AWS CLI v2."
    fi

    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$aws_version" | cut -d. -f1) -lt 2 ]]; then
        fatal "AWS CLI v2 is required. Current version: $aws_version"
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi

    # Check required tools
    local required_tools=("jq" "python3" "zip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            fatal "$tool is required but not installed."
        fi
    done

    # Check AWS account permissions
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    info "Using AWS Account: $account_id"

    # Validate regions
    if ! aws ec2 describe-regions --region-names "$PRIMARY_REGION" &> /dev/null; then
        fatal "Invalid primary region: $PRIMARY_REGION"
    fi

    if ! aws ec2 describe-regions --region-names "$DR_REGION" &> /dev/null; then
        fatal "Invalid DR region: $DR_REGION"
    fi

    success "Prerequisites validation completed"
}

#############################################################################
# Configuration Setup
#############################################################################

setup_environment() {
    info "Setting up environment variables..."

    # Export core variables
    export PRIMARY_REGION="$PRIMARY_REGION"
    export DR_REGION="$DR_REGION"
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Generate unique identifiers
    DR_PROJECT_ID=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword --region "${PRIMARY_REGION}" 2>/dev/null || \
        echo "dr$(date +%s | tail -c 8)")

    export DRS_PROJECT_NAME="enterprise-dr-${DR_PROJECT_ID}"
    export DR_VPC_NAME="disaster-recovery-vpc-${DR_PROJECT_ID}"
    export AUTOMATION_ROLE_NAME="DRAutomationRole-${DR_PROJECT_ID}"

    # Store configuration for reference
    cat > "${TEMP_DIR}/deployment-config.env" << EOF
PRIMARY_REGION=${PRIMARY_REGION}
DR_REGION=${DR_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DR_PROJECT_ID=${DR_PROJECT_ID}
DRS_PROJECT_NAME=${DRS_PROJECT_NAME}
DR_VPC_NAME=${DR_VPC_NAME}
AUTOMATION_ROLE_NAME=${AUTOMATION_ROLE_NAME}
NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    success "Environment configuration completed"
    info "DR Project ID: ${DR_PROJECT_ID}"
    info "Primary Region: ${PRIMARY_REGION}"
    info "DR Region: ${DR_REGION}"
}

#############################################################################
# DRS Service Initialization
#############################################################################

initialize_drs_service() {
    info "Initializing AWS Elastic Disaster Recovery service..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would initialize DRS in regions: $PRIMARY_REGION, $DR_REGION"
        return 0
    fi

    # Initialize DRS in primary region
    aws drs initialize-service --region "${PRIMARY_REGION}" || {
        warning "DRS already initialized in primary region or initialization failed"
    }

    # Initialize DRS in DR region
    aws drs initialize-service --region "${DR_REGION}" || {
        warning "DRS already initialized in DR region or initialization failed"
    }

    # Get default security group for replication template
    local default_sg=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=default \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "${PRIMARY_REGION}")

    # Get default subnet for staging area
    local default_subnet=$(aws ec2 describe-subnets \
        --filters Name=default-for-az,Values=true \
        --query 'Subnets[0].SubnetId' \
        --output text \
        --region "${PRIMARY_REGION}")

    # Create replication configuration template
    local replication_template=$(aws drs create-replication-configuration-template \
        --associate-default-security-group \
        --bandwidth-throttling 50000 \
        --create-public-ip \
        --data-plane-routing PRIVATE_IP \
        --default-large-staging-disk-type GP3 \
        --ebs-encryption DEFAULT \
        --replication-server-instance-type m5.large \
        --replication-servers-security-groups-ids "${default_sg}" \
        --staging-area-subnet-id "${default_subnet}" \
        --staging-area-tags "Key=Project,Value=${DRS_PROJECT_NAME}" \
        --use-dedicated-replication-server \
        --region "${PRIMARY_REGION}" \
        --query 'replicationConfigurationTemplateID' \
        --output text 2>/dev/null || echo "existing")

    echo "REPLICATION_TEMPLATE_ID=${replication_template}" >> "${TEMP_DIR}/deployment-config.env"

    success "DRS service initialization completed"
}

#############################################################################
# IAM Roles Creation
#############################################################################

create_iam_roles() {
    info "Creating IAM roles for disaster recovery automation..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create IAM role: $AUTOMATION_ROLE_NAME"
        return 0
    fi

    # Create trust policy
    cat > "${TEMP_DIR}/dr-automation-trust-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "lambda.amazonaws.com",
                    "ssm.amazonaws.com",
                    "states.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create IAM role
    aws iam create-role \
        --role-name "${AUTOMATION_ROLE_NAME}" \
        --assume-role-policy-document "file://${TEMP_DIR}/dr-automation-trust-policy.json" \
        --description "Role for disaster recovery automation" \
        --region "${PRIMARY_REGION}" || {
        warning "IAM role may already exist or creation failed"
    }

    # Create custom policy for DRS operations
    cat > "${TEMP_DIR}/dr-automation-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "drs:*",
                "ec2:*",
                "iam:PassRole",
                "route53:*",
                "sns:*",
                "ssm:*",
                "lambda:*",
                "logs:*",
                "cloudwatch:*",
                "states:*",
                "events:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${AUTOMATION_ROLE_NAME}" \
        --policy-name DRAutomationPolicy \
        --policy-document "file://${TEMP_DIR}/dr-automation-policy.json" \
        --region "${PRIMARY_REGION}"

    # Wait for role propagation
    sleep 10

    success "IAM roles created successfully"
}

#############################################################################
# DR Infrastructure Setup
#############################################################################

setup_dr_infrastructure() {
    info "Setting up DR region infrastructure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create VPC and infrastructure in $DR_REGION"
        return 0
    fi

    # Create VPC in DR region
    local dr_vpc_id=$(aws ec2 create-vpc \
        --cidr-block 10.100.0.0/16 \
        --tag-specifications \
            "ResourceType=vpc,Tags=[{Key=Name,Value=${DR_VPC_NAME}},{Key=Purpose,Value=DisasterRecovery}]" \
        --region "${DR_REGION}" \
        --query 'Vpc.VpcId' \
        --output text)

    # Create subnets
    local dr_public_subnet=$(aws ec2 create-subnet \
        --vpc-id "${dr_vpc_id}" \
        --cidr-block 10.100.1.0/24 \
        --availability-zone "${DR_REGION}a" \
        --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=DR-Public-Subnet-${DR_PROJECT_ID}}]" \
        --region "${DR_REGION}" \
        --query 'Subnet.SubnetId' \
        --output text)

    local dr_private_subnet=$(aws ec2 create-subnet \
        --vpc-id "${dr_vpc_id}" \
        --cidr-block 10.100.2.0/24 \
        --availability-zone "${DR_REGION}a" \
        --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=DR-Private-Subnet-${DR_PROJECT_ID}}]" \
        --region "${DR_REGION}" \
        --query 'Subnet.SubnetId' \
        --output text)

    # Create Internet Gateway
    local dr_igw=$(aws ec2 create-internet-gateway \
        --tag-specifications \
            "ResourceType=internet-gateway,Tags=[{Key=Name,Value=DR-IGW-${DR_PROJECT_ID}}]" \
        --region "${DR_REGION}" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)

    # Attach Internet Gateway
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "${dr_igw}" \
        --vpc-id "${dr_vpc_id}" \
        --region "${DR_REGION}"

    # Create and configure route table
    local dr_public_rt=$(aws ec2 create-route-table \
        --vpc-id "${dr_vpc_id}" \
        --tag-specifications \
            "ResourceType=route-table,Tags=[{Key=Name,Value=DR-Public-RT-${DR_PROJECT_ID}}]" \
        --region "${DR_REGION}" \
        --query 'RouteTable.RouteTableId' \
        --output text)

    aws ec2 create-route \
        --route-table-id "${dr_public_rt}" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "${dr_igw}" \
        --region "${DR_REGION}"

    aws ec2 associate-route-table \
        --route-table-id "${dr_public_rt}" \
        --subnet-id "${dr_public_subnet}" \
        --region "${DR_REGION}"

    # Store infrastructure IDs
    cat >> "${TEMP_DIR}/deployment-config.env" << EOF
DR_VPC_ID=${dr_vpc_id}
DR_PUBLIC_SUBNET=${dr_public_subnet}
DR_PRIVATE_SUBNET=${dr_private_subnet}
DR_IGW=${dr_igw}
DR_PUBLIC_RT=${dr_public_rt}
EOF

    success "DR infrastructure created successfully"
    info "DR VPC: ${dr_vpc_id}"
}

#############################################################################
# Lambda Functions Deployment
#############################################################################

deploy_lambda_functions() {
    info "Deploying Lambda functions for DR automation..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would deploy Lambda functions for failover and testing"
        return 0
    fi

    # Create SNS topic first
    local dr_sns_topic=$(aws sns create-topic \
        --name "dr-alerts-${DR_PROJECT_ID}" \
        --region "${PRIMARY_REGION}" \
        --query 'TopicArn' \
        --output text)

    # Subscribe to SNS topic
    aws sns subscribe \
        --topic-arn "${dr_sns_topic}" \
        --protocol email \
        --notification-endpoint "${NOTIFICATION_EMAIL}" \
        --region "${PRIMARY_REGION}" || {
        warning "Failed to subscribe to SNS topic - email may be invalid"
    }

    # Create automated failover Lambda function
    cat > "${TEMP_DIR}/automated-failover.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    drs_client = boto3.client('drs', region_name=os.environ['DR_REGION'])
    route53_client = boto3.client('route53')
    sns_client = boto3.client('sns')
    
    try:
        # Get source servers for recovery
        response = drs_client.describe_source_servers()
        source_servers = response.get('sourceServers', [])
        
        recovery_jobs = []
        
        for server in source_servers:
            if server.get('sourceServerID'):
                # Start recovery job
                job_response = drs_client.start_recovery(
                    sourceServers=[{
                        'sourceServerID': server['sourceServerID'],
                        'recoverySnapshotID': 'LATEST'
                    }],
                    tags={
                        'Purpose': 'AutomatedDR',
                        'Timestamp': datetime.utcnow().isoformat()
                    }
                )
                recovery_jobs.append(job_response['job']['jobID'])
        
        # Send notification
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=f'Automated DR failover initiated. Jobs: {recovery_jobs}',
            Subject='DR Failover Activated'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Failover initiated successfully',
                'recoveryJobs': recovery_jobs
            })
        }
        
    except Exception as e:
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=f'DR failover failed: {str(e)}',
            Subject='DR Failover Failed'
        )
        raise e
EOF

    # Package and deploy failover Lambda
    cd "${TEMP_DIR}"
    zip -q automated-failover.zip automated-failover.py

    local failover_lambda=$(aws lambda create-function \
        --function-name "dr-automated-failover-${DR_PROJECT_ID}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AUTOMATION_ROLE_NAME}" \
        --handler automated-failover.lambda_handler \
        --zip-file fileb://automated-failover.zip \
        --timeout 300 \
        --environment Variables="{DR_REGION=${DR_REGION},SNS_TOPIC_ARN=${dr_sns_topic}}" \
        --region "${PRIMARY_REGION}" \
        --query 'FunctionArn' \
        --output text)

    # Store Lambda ARN
    echo "FAILOVER_LAMBDA_ARN=${failover_lambda}" >> "${TEMP_DIR}/deployment-config.env"
    echo "DR_SNS_TOPIC_ARN=${dr_sns_topic}" >> "${TEMP_DIR}/deployment-config.env"

    success "Lambda functions deployed successfully"
}

#############################################################################
# CloudWatch Monitoring Setup
#############################################################################

setup_monitoring() {
    info "Setting up CloudWatch monitoring and alarms..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create CloudWatch alarms and dashboard"
        return 0
    fi

    # Get SNS topic ARN from config
    source "${TEMP_DIR}/deployment-config.env"

    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "Application-Health-${DR_PROJECT_ID}" \
        --alarm-description "Monitor application health for DR trigger" \
        --metric-name HealthCheckStatus \
        --namespace AWS/Route53 \
        --statistic Minimum \
        --period 60 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 3 \
        --alarm-actions "${DR_SNS_TOPIC_ARN}" \
        --region "${PRIMARY_REGION}"

    # Create CloudWatch dashboard
    cat > "${TEMP_DIR}/dr-dashboard.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/DRS", "ReplicationLag", "SourceServerID", "ALL"],
                    [".", "ReplicationStatus", ".", "."],
                    [".", "StagingStorageUtilization", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${PRIMARY_REGION}",
                "title": "DRS Replication Metrics",
                "view": "timeSeries"
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/dr-automated-failover-${DR_PROJECT_ID}' | fields @timestamp, @message | sort @timestamp desc | limit 20",
                "region": "${PRIMARY_REGION}",
                "title": "DR Automation Logs",
                "view": "table"
            }
        }
    ]
}
EOF

    aws cloudwatch put-dashboard \
        --dashboard-name "DR-Monitoring-${DR_PROJECT_ID}" \
        --dashboard-body "file://${TEMP_DIR}/dr-dashboard.json" \
        --region "${PRIMARY_REGION}"

    success "CloudWatch monitoring configured successfully"
}

#############################################################################
# Agent Installation Scripts
#############################################################################

create_agent_scripts() {
    info "Creating DRS agent installation scripts..."

    # Create output directory
    local scripts_dir="${SCRIPT_DIR}/../agent-scripts"
    mkdir -p "${scripts_dir}"

    # Generate Linux agent installation script
    cat > "${scripts_dir}/install-drs-agent-linux.sh" << EOF
#!/bin/bash
# AWS Elastic Disaster Recovery Agent Installation Script for Linux

set -e

# Configuration
AWS_REGION="${PRIMARY_REGION}"
DRS_ENDPOINT="https://drs.\${AWS_REGION}.amazonaws.com"

echo "Installing AWS DRS Agent for Linux..."

# Download DRS agent
if [ -f /etc/redhat-release ]; then
    # RHEL/CentOS
    sudo yum update -y
    wget "https://aws-elastic-disaster-recovery-\${AWS_REGION}.s3.amazonaws.com/latest/linux/aws-replication-installer-init.py"
elif [ -f /etc/debian_version ]; then
    # Ubuntu/Debian
    sudo apt-get update -y
    wget "https://aws-elastic-disaster-recovery-\${AWS_REGION}.s3.amazonaws.com/latest/linux/aws-replication-installer-init.py"
fi

# Install agent with provided credentials
sudo python3 aws-replication-installer-init.py \\
    --region "\${AWS_REGION}" \\
    --aws-access-key-id "\${AWS_ACCESS_KEY_ID}" \\
    --aws-secret-access-key "\${AWS_SECRET_ACCESS_KEY}" \\
    --no-prompt

echo "DRS Agent installation completed successfully"
EOF

    # Generate Windows agent installation script
    cat > "${scripts_dir}/install-drs-agent-windows.ps1" << EOF
# AWS Elastic Disaster Recovery Agent Installation Script for Windows

Write-Host "Installing AWS DRS Agent for Windows..."

# Configuration
\$AwsRegion = "${PRIMARY_REGION}"

# Download DRS agent installer
\$installerUrl = "https://aws-elastic-disaster-recovery-\${AwsRegion}.s3.amazonaws.com/latest/windows/AwsReplicationWindowsInstaller.exe"
\$installerPath = "\$env:TEMP\\AwsReplicationWindowsInstaller.exe"

try {
    Invoke-WebRequest -Uri \$installerUrl -OutFile \$installerPath
    
    # Install agent silently
    Start-Process -FilePath \$installerPath -ArgumentList "/S", "/v/qn" -Wait
    
    # Configure agent
    & "C:\\Program Files (x86)\\AWS Replication Agent\\aws-replication-installer-init.exe" \`
        --region \$AwsRegion \`
        --aws-access-key-id \$env:AWS_ACCESS_KEY_ID \`
        --aws-secret-access-key \$env:AWS_SECRET_ACCESS_KEY \`
        --no-prompt
    
    Write-Host "DRS Agent installation completed successfully"
}
catch {
    Write-Error "Failed to install DRS Agent: \$_"
    exit 1
}
EOF

    chmod +x "${scripts_dir}/install-drs-agent-linux.sh"

    success "DRS agent installation scripts created in ${scripts_dir}"
}

#############################################################################
# Deployment Verification
#############################################################################

verify_deployment() {
    info "Verifying deployment..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would verify all deployed resources"
        return 0
    fi

    local verification_failed=false

    # Source deployment configuration
    source "${TEMP_DIR}/deployment-config.env"

    # Check DRS initialization
    if ! aws drs describe-replication-configuration-templates --region "${PRIMARY_REGION}" &> /dev/null; then
        error "DRS service not properly initialized"
        verification_failed=true
    fi

    # Check IAM role
    if ! aws iam get-role --role-name "${AUTOMATION_ROLE_NAME}" &> /dev/null; then
        error "IAM role not created: ${AUTOMATION_ROLE_NAME}"
        verification_failed=true
    fi

    # Check DR VPC
    if [[ -n "${DR_VPC_ID:-}" ]]; then
        if ! aws ec2 describe-vpcs --vpc-ids "${DR_VPC_ID}" --region "${DR_REGION}" &> /dev/null; then
            error "DR VPC not found: ${DR_VPC_ID}"
            verification_failed=true
        fi
    fi

    # Check Lambda function
    if [[ -n "${FAILOVER_LAMBDA_ARN:-}" ]]; then
        if ! aws lambda get-function --function-name "dr-automated-failover-${DR_PROJECT_ID}" --region "${PRIMARY_REGION}" &> /dev/null; then
            error "Lambda function not found"
            verification_failed=true
        fi
    fi

    # Check SNS topic
    if [[ -n "${DR_SNS_TOPIC_ARN:-}" ]]; then
        if ! aws sns get-topic-attributes --topic-arn "${DR_SNS_TOPIC_ARN}" --region "${PRIMARY_REGION}" &> /dev/null; then
            error "SNS topic not found"
            verification_failed=true
        fi
    fi

    if [[ "$verification_failed" == "true" ]]; then
        fatal "Deployment verification failed. Check the logs for details."
    fi

    success "Deployment verification completed successfully"
}

#############################################################################
# Main Deployment Process
#############################################################################

main() {
    info "Starting AWS Cross-Region Disaster Recovery deployment..."
    info "Log file: $LOG_FILE"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --primary-region)
                PRIMARY_REGION="$2"
                shift 2
                ;;
            --dr-region)
                DR_REGION="$2"
                shift 2
                ;;
            --notification-email)
                NOTIFICATION_EMAIL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DEPLOY=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Set defaults if not provided
    PRIMARY_REGION="${PRIMARY_REGION:-$DEFAULT_PRIMARY_REGION}"
    DR_REGION="${DR_REGION:-$DEFAULT_DR_REGION}"
    NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-$DEFAULT_NOTIFICATION_EMAIL}"

    # Display configuration
    info "Deployment Configuration:"
    info "  Primary Region: $PRIMARY_REGION"
    info "  DR Region: $DR_REGION"
    info "  Notification Email: $NOTIFICATION_EMAIL"
    info "  Dry Run: $DRY_RUN"

    # Confirmation prompt
    if [[ "$FORCE_DEPLOY" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Deployment cancelled by user"
            exit 0
        fi
    fi

    # Execute deployment steps
    check_prerequisites
    setup_environment
    initialize_drs_service
    create_iam_roles
    setup_dr_infrastructure
    deploy_lambda_functions
    setup_monitoring
    create_agent_scripts
    verify_deployment

    # Copy deployment configuration to persistent location
    if [[ "$DRY_RUN" != "true" ]]; then
        cp "${TEMP_DIR}/deployment-config.env" "${SCRIPT_DIR}/deployment-config.env"
    fi

    # Display completion message
    echo
    success "==================================================================="
    success "AWS Cross-Region Disaster Recovery deployment completed!"
    success "==================================================================="
    echo
    info "Next steps:"
    info "1. Install DRS agents on source servers using scripts in ../agent-scripts/"
    info "2. Configure replication settings for each source server"
    info "3. Test failover procedures using the Lambda functions"
    info "4. Monitor DR status using CloudWatch dashboard: DR-Monitoring-${DR_PROJECT_ID}"
    info "5. Subscribe additional contacts to SNS topic: dr-alerts-${DR_PROJECT_ID}"
    echo
    info "For cleanup, run: ./destroy.sh"
    echo
    info "Deployment configuration saved to: ${SCRIPT_DIR}/deployment-config.env"
    echo
}

# Run main function with all arguments
main "$@"