#!/bin/bash

# Deploy script for Dedicated Hosts License Compliance Recipe
# This script implements AWS EC2 Dedicated Hosts for License Compliance
# with automated monitoring and governance through License Manager and Config

set -e  # Exit on any error

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
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ${AWS_CLI_VERSION:0:1} != "2" ]]; then
        warn "AWS CLI v2 is recommended. Current version: $AWS_CLI_VERSION"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Check required permissions
    info "Verifying AWS permissions..."
    aws iam get-user &> /dev/null || warn "Unable to verify IAM permissions"
    
    log "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please configure AWS CLI or set AWS_REGION environment variable."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set naming convention
    export LICENSE_COMPLIANCE_PREFIX="license-compliance-${RANDOM_SUFFIX}"
    export DEDICATED_HOST_TAG_KEY="LicenseCompliance"
    export DEDICATED_HOST_TAG_VALUE="BYOL-Production"
    
    log "Environment configured:"
    info "  AWS Region: $AWS_REGION"
    info "  AWS Account ID: $AWS_ACCOUNT_ID"
    info "  Resource Prefix: $LICENSE_COMPLIANCE_PREFIX"
}

# Create SNS topic for compliance alerts
create_sns_topic() {
    log "Creating SNS topic for compliance alerts..."
    
    aws sns create-topic \
        --name "${LICENSE_COMPLIANCE_PREFIX}-compliance-alerts" \
        --attributes DisplayName="License Compliance Alerts" \
        > /dev/null
    
    export SNS_TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${LICENSE_COMPLIANCE_PREFIX}-compliance-alerts')].TopicArn" \
        --output text)
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        error "Failed to create or retrieve SNS topic ARN"
        exit 1
    fi
    
    log "SNS topic created: $SNS_TOPIC_ARN"
}

# Create License Manager configurations
create_license_configurations() {
    log "Creating License Manager configurations..."
    
    # Create Windows Server license configuration
    aws license-manager create-license-configuration \
        --name "${LICENSE_COMPLIANCE_PREFIX}-windows-server" \
        --description "Windows Server BYOL license tracking" \
        --license-counting-type Socket \
        --license-count 10 \
        --license-count-hard-limit \
        --tag-specifications ResourceType=license-configuration,Tags=[{Key=Purpose,Value=WindowsServer},{Key=Environment,Value=Production}] \
        > /dev/null
    
    # Get Windows license ARN
    export WINDOWS_LICENSE_ARN=$(aws license-manager list-license-configurations \
        --query "LicenseConfigurations[?Name=='${LICENSE_COMPLIANCE_PREFIX}-windows-server'].LicenseConfigurationArn" \
        --output text)
    
    if [[ -z "$WINDOWS_LICENSE_ARN" ]]; then
        error "Failed to create Windows Server license configuration"
        exit 1
    fi
    
    # Create Oracle license configuration
    aws license-manager create-license-configuration \
        --name "${LICENSE_COMPLIANCE_PREFIX}-oracle-enterprise" \
        --description "Oracle Enterprise Edition BYOL license tracking" \
        --license-counting-type Core \
        --license-count 16 \
        --license-count-hard-limit \
        --tag-specifications ResourceType=license-configuration,Tags=[{Key=Purpose,Value=OracleDB},{Key=Environment,Value=Production}] \
        > /dev/null
    
    # Get Oracle license ARN
    export ORACLE_LICENSE_ARN=$(aws license-manager list-license-configurations \
        --query "LicenseConfigurations[?Name=='${LICENSE_COMPLIANCE_PREFIX}-oracle-enterprise'].LicenseConfigurationArn" \
        --output text)
    
    if [[ -z "$ORACLE_LICENSE_ARN" ]]; then
        error "Failed to create Oracle license configuration"
        exit 1
    fi
    
    log "License configurations created:"
    info "  Windows Server: $WINDOWS_LICENSE_ARN"
    info "  Oracle Enterprise: $ORACLE_LICENSE_ARN"
}

# Allocate Dedicated Hosts
allocate_dedicated_hosts() {
    log "Allocating Dedicated Hosts..."
    
    # Allocate Windows/SQL Server host
    aws ec2 allocate-hosts \
        --instance-family m5 \
        --availability-zone "${AWS_REGION}a" \
        --quantity 1 \
        --auto-placement off \
        --host-recovery on \
        --tag-specifications "ResourceType=dedicated-host,Tags=[{Key=${DEDICATED_HOST_TAG_KEY},Value=${DEDICATED_HOST_TAG_VALUE}},{Key=LicenseType,Value=WindowsServer},{Key=Purpose,Value=SQLServer}]" \
        > /dev/null
    
    # Get Windows host ID
    export WINDOWS_HOST_ID=$(aws ec2 describe-hosts \
        --filters "Name=tag:LicenseType,Values=WindowsServer" \
        --query "Hosts[0].HostId" --output text)
    
    if [[ "$WINDOWS_HOST_ID" == "None" ]] || [[ -z "$WINDOWS_HOST_ID" ]]; then
        error "Failed to allocate Windows Dedicated Host"
        exit 1
    fi
    
    # Allocate Oracle database host
    aws ec2 allocate-hosts \
        --instance-family r5 \
        --availability-zone "${AWS_REGION}b" \
        --quantity 1 \
        --auto-placement off \
        --host-recovery on \
        --tag-specifications "ResourceType=dedicated-host,Tags=[{Key=${DEDICATED_HOST_TAG_KEY},Value=${DEDICATED_HOST_TAG_VALUE}},{Key=LicenseType,Value=Oracle},{Key=Purpose,Value=Database}]" \
        > /dev/null
    
    # Get Oracle host ID
    export ORACLE_HOST_ID=$(aws ec2 describe-hosts \
        --filters "Name=tag:LicenseType,Values=Oracle" \
        --query "Hosts[0].HostId" --output text)
    
    if [[ "$ORACLE_HOST_ID" == "None" ]] || [[ -z "$ORACLE_HOST_ID" ]]; then
        error "Failed to allocate Oracle Dedicated Host"
        exit 1
    fi
    
    log "Dedicated Hosts allocated:"
    info "  Windows/SQL Server Host: $WINDOWS_HOST_ID"
    info "  Oracle Database Host: $ORACLE_HOST_ID"
}

# Set up License Manager reporting
setup_license_reporting() {
    log "Setting up License Manager reporting..."
    
    # Create S3 bucket for reports
    aws s3 mb "s3://${LICENSE_COMPLIANCE_PREFIX}-reports-${AWS_ACCOUNT_ID}" \
        --region "${AWS_REGION}" > /dev/null 2>&1 || true
    
    # Create bucket policy for License Manager
    cat > /tmp/license-manager-bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "LicenseManagerReportAccess",
            "Effect": "Allow",
            "Principal": {
                "Service": "license-manager.amazonaws.com"
            },
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::${LICENSE_COMPLIANCE_PREFIX}-reports-${AWS_ACCOUNT_ID}",
                "arn:aws:s3:::${LICENSE_COMPLIANCE_PREFIX}-reports-${AWS_ACCOUNT_ID}/*"
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "${LICENSE_COMPLIANCE_PREFIX}-reports-${AWS_ACCOUNT_ID}" \
        --policy file:///tmp/license-manager-bucket-policy.json
    
    # Create report generator
    aws license-manager create-license-manager-report-generator \
        --report-generator-name "${LICENSE_COMPLIANCE_PREFIX}-monthly-report" \
        --type LicenseConfigurationSummaryReport \
        --report-context "{\"licenseConfigurationArns\":[\"${WINDOWS_LICENSE_ARN}\"]}" \
        --report-frequency "{\"unit\":\"MONTH\",\"value\":1}" \
        --client-token "${LICENSE_COMPLIANCE_PREFIX}-report-$(date +%s)" \
        --description "Monthly license compliance report" \
        --s3-location "bucket=${LICENSE_COMPLIANCE_PREFIX}-reports-${AWS_ACCOUNT_ID},keyPrefix=monthly-reports/" \
        > /dev/null 2>&1 || warn "License Manager reporting setup may have failed - continuing"
    
    log "License Manager reporting configured"
}

# Configure AWS Config for compliance monitoring
configure_aws_config() {
    log "Configuring AWS Config for compliance monitoring..."
    
    # Create Config service role
    aws iam create-role \
        --role-name "${LICENSE_COMPLIANCE_PREFIX}-config-role" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "config.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' > /dev/null 2>&1 || warn "Config role may already exist"
    
    # Attach Config service role policy
    aws iam attach-role-policy \
        --role-name "${LICENSE_COMPLIANCE_PREFIX}-config-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole \
        > /dev/null 2>&1 || true
    
    # Create Config delivery channel S3 bucket
    aws s3 mb "s3://${LICENSE_COMPLIANCE_PREFIX}-config-${AWS_ACCOUNT_ID}" \
        --region "${AWS_REGION}" > /dev/null 2>&1 || true
    
    # Configure Config service
    aws configservice put-configuration-recorder \
        --configuration-recorder "{
            \"name\": \"${LICENSE_COMPLIANCE_PREFIX}-recorder\",
            \"roleARN\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LICENSE_COMPLIANCE_PREFIX}-config-role\",
            \"recordingGroup\": {
                \"allSupported\": false,
                \"includeGlobalResourceTypes\": false,
                \"resourceTypes\": [\"AWS::EC2::Host\", \"AWS::EC2::Instance\"]
            }
        }" > /dev/null 2>&1 || warn "Config recorder may already exist"
    
    # Set up Config delivery channel
    aws configservice put-delivery-channel \
        --delivery-channel "{
            \"name\": \"${LICENSE_COMPLIANCE_PREFIX}-delivery-channel\",
            \"s3BucketName\": \"${LICENSE_COMPLIANCE_PREFIX}-config-${AWS_ACCOUNT_ID}\",
            \"configSnapshotDeliveryProperties\": {
                \"deliveryFrequency\": \"TwentyFour_Hours\"
            }
        }" > /dev/null 2>&1 || warn "Config delivery channel may already exist"
    
    # Start Config recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name "${LICENSE_COMPLIANCE_PREFIX}-recorder" \
        > /dev/null 2>&1 || warn "Config recorder may already be started"
    
    log "AWS Config configured for Dedicated Host monitoring"
}

# Create CloudWatch alarms and monitoring
setup_monitoring() {
    log "Setting up CloudWatch monitoring and alarms..."
    
    # Create CloudWatch alarm for license utilization
    aws cloudwatch put-metric-alarm \
        --alarm-name "${LICENSE_COMPLIANCE_PREFIX}-license-utilization" \
        --alarm-description "Monitor license utilization threshold" \
        --metric-name LicenseUtilization \
        --namespace AWS/LicenseManager \
        --statistic Average \
        --period 3600 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=LicenseConfigurationArn,Value="${WINDOWS_LICENSE_ARN}" \
        > /dev/null
    
    # Create Config rule for Dedicated Host compliance
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "'${LICENSE_COMPLIANCE_PREFIX}'-host-compliance",
            "Description": "Checks if EC2 instances are running on properly configured Dedicated Hosts",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "EC2_DEDICATED_HOST_COMPLIANCE"
            },
            "Scope": {
                "ComplianceResourceTypes": ["AWS::EC2::Instance"]
            }
        }' > /dev/null 2>&1 || warn "Config rule creation may have failed"
    
    log "CloudWatch monitoring and Config rules configured"
}

# Create launch templates for BYOL instances
create_launch_templates() {
    log "Creating launch templates for BYOL instances..."
    
    # Get latest Amazon Linux 2 AMI ID for demonstration
    AMAZON_LINUX_AMI=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            "Name=state,Values=available" \
        --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
        --output text)
    
    # Create launch template for Windows Server with SQL Server (using Amazon Linux for demo)
    aws ec2 create-launch-template \
        --launch-template-name "${LICENSE_COMPLIANCE_PREFIX}-windows-sql" \
        --launch-template-data "{
            \"ImageId\": \"${AMAZON_LINUX_AMI}\",
            \"InstanceType\": \"m5.large\",
            \"TagSpecifications\": [
                {
                    \"ResourceType\": \"instance\",
                    \"Tags\": [
                        {\"Key\": \"Name\", \"Value\": \"${LICENSE_COMPLIANCE_PREFIX}-windows-sql\"},
                        {\"Key\": \"LicenseType\", \"Value\": \"WindowsServer\"},
                        {\"Key\": \"Application\", \"Value\": \"SQLServer\"},
                        {\"Key\": \"BYOLCompliance\", \"Value\": \"true\"}
                    ]
                }
            ],
            \"Placement\": {
                \"Tenancy\": \"host\"
            }
        }" > /dev/null
    
    # Create launch template for Oracle Database
    aws ec2 create-launch-template \
        --launch-template-name "${LICENSE_COMPLIANCE_PREFIX}-oracle-db" \
        --launch-template-data "{
            \"ImageId\": \"${AMAZON_LINUX_AMI}\",
            \"InstanceType\": \"r5.xlarge\",
            \"TagSpecifications\": [
                {
                    \"ResourceType\": \"instance\",
                    \"Tags\": [
                        {\"Key\": \"Name\", \"Value\": \"${LICENSE_COMPLIANCE_PREFIX}-oracle-db\"},
                        {\"Key\": \"LicenseType\", \"Value\": \"Oracle\"},
                        {\"Key\": \"Application\", \"Value\": \"Database\"},
                        {\"Key\": \"BYOLCompliance\", \"Value\": \"true\"}
                    ]
                }
            ],
            \"Placement\": {
                \"Tenancy\": \"host\"
            }
        }" > /dev/null
    
    log "Launch templates created for BYOL instances"
}

# Create Systems Manager documents for license inventory
setup_systems_manager() {
    log "Setting up Systems Manager for license inventory..."
    
    # Create custom document for license tracking (simplified for demo)
    aws ssm create-document \
        --name "${LICENSE_COMPLIANCE_PREFIX}-license-inventory" \
        --document-type "Command" \
        --content '{
            "schemaVersion": "2.2",
            "description": "Collect license information from BYOL instances",
            "mainSteps": [
                {
                    "action": "aws:runShellScript",
                    "name": "CollectLicenseInfo",
                    "inputs": {
                        "runCommand": [
                            "echo \"Collecting system information for license compliance...\"",
                            "uname -a",
                            "cat /proc/cpuinfo | grep processor | wc -l",
                            "free -h"
                        ]
                    }
                }
            ]
        }' > /dev/null 2>&1 || warn "SSM document may already exist"
    
    log "Systems Manager inventory configured"
}

# Create compliance dashboard
create_compliance_dashboard() {
    log "Creating compliance dashboard..."
    
    # Create CloudWatch dashboard
    cat > /tmp/license-compliance-dashboard.json << EOF
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
                    ["AWS/LicenseManager", "LicenseUtilization", "LicenseConfigurationArn", "${WINDOWS_LICENSE_ARN}"],
                    ["AWS/LicenseManager", "LicenseUtilization", "LicenseConfigurationArn", "${ORACLE_LICENSE_ARN}"]
                ],
                "period": 3600,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "License Utilization"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization", "InstanceId", "PLACEHOLDER"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Instance CPU Utilization"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${LICENSE_COMPLIANCE_PREFIX}-compliance-dashboard" \
        --dashboard-body file:///tmp/license-compliance-dashboard.json \
        > /dev/null
    
    log "Compliance dashboard created"
}

# Save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    cat > "${LICENSE_COMPLIANCE_PREFIX}-deployment-state.json" << EOF
{
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "resource_prefix": "${LICENSE_COMPLIANCE_PREFIX}",
    "sns_topic_arn": "${SNS_TOPIC_ARN}",
    "windows_license_arn": "${WINDOWS_LICENSE_ARN}",
    "oracle_license_arn": "${ORACLE_LICENSE_ARN}",
    "windows_host_id": "${WINDOWS_HOST_ID}",
    "oracle_host_id": "${ORACLE_HOST_ID}"
}
EOF
    
    log "Deployment state saved to ${LICENSE_COMPLIANCE_PREFIX}-deployment-state.json"
}

# Main deployment function
main() {
    log "Starting Dedicated Hosts License Compliance deployment..."
    
    check_prerequisites
    setup_environment
    create_sns_topic
    create_license_configurations
    allocate_dedicated_hosts
    setup_license_reporting
    configure_aws_config
    setup_monitoring
    create_launch_templates
    setup_systems_manager
    create_compliance_dashboard
    save_deployment_state
    
    log "Deployment completed successfully!"
    echo ""
    info "Deployment Summary:"
    info "  Resource Prefix: $LICENSE_COMPLIANCE_PREFIX"
    info "  Windows Host ID: $WINDOWS_HOST_ID"
    info "  Oracle Host ID: $ORACLE_HOST_ID"
    info "  License Configurations: Windows Server, Oracle Enterprise"
    info "  SNS Topic: $SNS_TOPIC_ARN"
    echo ""
    warn "Important Notes:"
    warn "  - Dedicated Hosts incur hourly charges regardless of instance usage"
    warn "  - Review AWS Dedicated Host pricing for cost estimates"
    warn "  - Use the destroy.sh script to clean up resources when done"
    echo ""
    log "Next steps:"
    info "  1. Launch BYOL instances using the created launch templates"
    info "  2. Associate instances with appropriate license configurations"
    info "  3. Monitor compliance through the CloudWatch dashboard"
    info "  4. Review monthly compliance reports in S3"
}

# Cleanup on script exit
cleanup() {
    rm -f /tmp/license-manager-bucket-policy.json
    rm -f /tmp/license-compliance-dashboard.json
}

trap cleanup EXIT

# Run main function
main "$@"