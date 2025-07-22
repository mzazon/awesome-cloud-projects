#!/bin/bash

# AWS EFS Performance Optimization and Monitoring - Deployment Script
# This script deploys an optimized EFS file system with comprehensive monitoring

set -e
set -o pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCE_FILE="${SCRIPT_DIR}/.deployment_resources"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log ERROR "$1"
    log ERROR "Deployment failed. Check log file: $LOG_FILE"
    log ERROR "You may need to run destroy.sh to clean up partially created resources"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log WARN "Cleaning up partially created resources due to error..."
    if [[ -f "$RESOURCE_FILE" ]]; then
        bash "${SCRIPT_DIR}/destroy.sh" --force
    fi
}

# Set trap for error cleanup
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS CLI version (v2 required)
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
    if [[ "$aws_version" -lt 2 ]]; then
        error_exit "AWS CLI v2 is required. Please upgrade your AWS CLI."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
        error_exit "Unable to retrieve AWS account information. Check your credentials."
    fi
    
    log SUCCESS "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log INFO "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log WARN "No region configured, defaulting to us-east-1"
    fi
    
    # Set AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export EFS_NAME="performance-optimized-efs-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="efs-sg-${RANDOM_SUFFIX}"
    
    # Get VPC information
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    
    if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
        # Try to get the first available VPC
        export VPC_ID=$(aws ec2 describe-vpcs \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
        
        if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
            error_exit "No VPC found. Please ensure you have a VPC in your account."
        fi
        log WARN "No default VPC found, using VPC: $VPC_ID"
    fi
    
    # Get subnet IDs
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[0:2].SubnetId' --output text 2>/dev/null)
    
    if [[ -z "$SUBNET_IDS" ]]; then
        error_exit "No subnets found in VPC $VPC_ID"
    fi
    
    # Store environment variables for cleanup
    cat > "$RESOURCE_FILE" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
EFS_NAME=$EFS_NAME
SECURITY_GROUP_NAME=$SECURITY_GROUP_NAME
VPC_ID=$VPC_ID
SUBNET_IDS=$SUBNET_IDS
EOF
    
    log SUCCESS "Environment setup complete"
    log INFO "VPC ID: $VPC_ID"
    log INFO "Subnet IDs: $SUBNET_IDS"
    log INFO "EFS Name: $EFS_NAME"
}

# Function to create security group
create_security_group() {
    log INFO "Creating security group for EFS mount targets..."
    
    aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "Security group for EFS mount targets - performance optimization recipe" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SECURITY_GROUP_NAME},{Key=Purpose,Value=EFS-Performance-Recipe}]" \
        >> "$LOG_FILE" 2>&1
    
    export SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --group-names "$SECURITY_GROUP_NAME" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    # Allow NFS traffic (port 2049) from within the security group
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 2049 \
        --source-group "$SECURITY_GROUP_ID" \
        >> "$LOG_FILE" 2>&1
    
    # Store security group ID
    echo "SECURITY_GROUP_ID=$SECURITY_GROUP_ID" >> "$RESOURCE_FILE"
    
    log SUCCESS "Security group created: $SECURITY_GROUP_ID"
}

# Function to create EFS file system
create_efs_filesystem() {
    log INFO "Creating EFS file system with performance optimization..."
    
    aws efs create-file-system \
        --creation-token "$EFS_NAME" \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --encrypted \
        --tags "Key=Name,Value=$EFS_NAME" \
               "Key=Environment,Value=production" \
               "Key=Purpose,Value=performance-optimized" \
               "Key=Recipe,Value=efs-performance-optimization-monitoring" \
        >> "$LOG_FILE" 2>&1
    
    export EFS_ID=$(aws efs describe-file-systems \
        --query "FileSystems[?CreationToken=='$EFS_NAME'].FileSystemId" \
        --output text)
    
    if [[ -z "$EFS_ID" ]]; then
        error_exit "Failed to retrieve EFS file system ID"
    fi
    
    # Wait for file system to become available
    log INFO "Waiting for EFS file system to become available..."
    aws efs wait file-system-available --file-system-id "$EFS_ID"
    
    # Store EFS ID
    echo "EFS_ID=$EFS_ID" >> "$RESOURCE_FILE"
    
    log SUCCESS "EFS file system created: $EFS_ID"
}

# Function to create mount targets
create_mount_targets() {
    log INFO "Creating mount targets in multiple availability zones..."
    
    local mount_target_ids=()
    
    for SUBNET_ID in $SUBNET_IDS; do
        log INFO "Creating mount target in subnet: $SUBNET_ID"
        
        local mount_target_id=$(aws efs create-mount-target \
            --file-system-id "$EFS_ID" \
            --subnet-id "$SUBNET_ID" \
            --security-groups "$SECURITY_GROUP_ID" \
            --query 'MountTargetId' --output text 2>/dev/null)
        
        if [[ -n "$mount_target_id" ]]; then
            mount_target_ids+=("$mount_target_id")
            log SUCCESS "Mount target created in subnet $SUBNET_ID: $mount_target_id"
        else
            log WARN "Failed to create mount target in subnet $SUBNET_ID"
        fi
    done
    
    if [[ ${#mount_target_ids[@]} -eq 0 ]]; then
        error_exit "Failed to create any mount targets"
    fi
    
    # Store mount target IDs
    echo "MOUNT_TARGET_IDS=${mount_target_ids[*]}" >> "$RESOURCE_FILE"
    
    # Wait for mount targets to become available
    log INFO "Waiting for mount targets to become available..."
    for mount_target_id in "${mount_target_ids[@]}"; do
        aws efs wait mount-target-available --mount-target-id "$mount_target_id"
    done
    
    log SUCCESS "All mount targets are available"
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log INFO "Creating CloudWatch monitoring dashboard..."
    
    # Create dashboard configuration
    cat > "${SCRIPT_DIR}/efs-dashboard.json" << EOF
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
                    [ "AWS/EFS", "TotalIOBytes", "FileSystemId", "$EFS_ID" ],
                    [ ".", "ReadIOBytes", ".", "." ],
                    [ ".", "WriteIOBytes", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "EFS IO Throughput",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
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
                    [ "AWS/EFS", "TotalIOTime", "FileSystemId", "$EFS_ID" ],
                    [ ".", "ReadIOTime", ".", "." ],
                    [ ".", "WriteIOTime", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "EFS IO Latency (ms)",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
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
                    [ "AWS/EFS", "ClientConnections", "FileSystemId", "$EFS_ID" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "EFS Client Connections",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/EFS", "PercentIOLimit", "FileSystemId", "$EFS_ID" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "EFS IO Limit Utilization (%)",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        }
    ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "EFS-Performance-$EFS_NAME" \
        --dashboard-body "file://${SCRIPT_DIR}/efs-dashboard.json" \
        >> "$LOG_FILE" 2>&1
    
    # Store dashboard name
    echo "DASHBOARD_NAME=EFS-Performance-$EFS_NAME" >> "$RESOURCE_FILE"
    
    log SUCCESS "CloudWatch dashboard created: EFS-Performance-$EFS_NAME"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log INFO "Creating performance monitoring alarms..."
    
    local alarm_names=()
    
    # High throughput utilization alarm
    local alarm_name="EFS-High-Throughput-Utilization-$EFS_NAME"
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "EFS throughput utilization exceeds 80%" \
        --metric-name PercentIOLimit \
        --namespace AWS/EFS \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FileSystemId,Value="$EFS_ID" \
        --tags "Key=Purpose,Value=EFS-Performance-Monitoring" \
               "Key=Recipe,Value=efs-performance-optimization-monitoring" \
        >> "$LOG_FILE" 2>&1
    
    alarm_names+=("$alarm_name")
    
    # High client connections alarm
    alarm_name="EFS-High-Client-Connections-$EFS_NAME"
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "EFS client connections exceed 500" \
        --metric-name ClientConnections \
        --namespace AWS/EFS \
        --statistic Sum \
        --period 300 \
        --threshold 500 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FileSystemId,Value="$EFS_ID" \
        --tags "Key=Purpose,Value=EFS-Performance-Monitoring" \
               "Key=Recipe,Value=efs-performance-optimization-monitoring" \
        >> "$LOG_FILE" 2>&1
    
    alarm_names+=("$alarm_name")
    
    # High IO latency alarm
    alarm_name="EFS-High-IO-Latency-$EFS_NAME"
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "EFS average IO time exceeds 50ms" \
        --metric-name TotalIOTime \
        --namespace AWS/EFS \
        --statistic Average \
        --period 300 \
        --threshold 50 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --dimensions Name=FileSystemId,Value="$EFS_ID" \
        --tags "Key=Purpose,Value=EFS-Performance-Monitoring" \
               "Key=Recipe,Value=efs-performance-optimization-monitoring" \
        >> "$LOG_FILE" 2>&1
    
    alarm_names+=("$alarm_name")
    
    # Store alarm names
    echo "ALARM_NAMES=${alarm_names[*]}" >> "$RESOURCE_FILE"
    
    log SUCCESS "CloudWatch alarms created successfully"
}

# Function to validate deployment
validate_deployment() {
    log INFO "Validating deployment..."
    
    # Check EFS file system
    local efs_status=$(aws efs describe-file-systems \
        --file-system-id "$EFS_ID" \
        --query 'FileSystems[0].LifeCycleState' --output text 2>/dev/null)
    
    if [[ "$efs_status" != "available" ]]; then
        error_exit "EFS file system is not in available state: $efs_status"
    fi
    
    # Check mount targets
    local mount_target_count=$(aws efs describe-mount-targets \
        --file-system-id "$EFS_ID" \
        --query 'length(MountTargets[?LifeCycleState==`available`])' --output text 2>/dev/null)
    
    if [[ "$mount_target_count" -lt 1 ]]; then
        error_exit "No available mount targets found"
    fi
    
    # Check dashboard
    aws cloudwatch get-dashboard \
        --dashboard-name "EFS-Performance-$EFS_NAME" \
        --query 'DashboardName' --output text >> "$LOG_FILE" 2>&1
    
    log SUCCESS "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log SUCCESS "=== EFS Performance Optimization Deployment Complete ==="
    log INFO ""
    log INFO "Resource Summary:"
    log INFO "  EFS File System ID: $EFS_ID"
    log INFO "  EFS Name: $EFS_NAME"
    log INFO "  Security Group ID: $SECURITY_GROUP_ID"
    log INFO "  CloudWatch Dashboard: EFS-Performance-$EFS_NAME"
    log INFO "  Region: $AWS_REGION"
    log INFO ""
    log INFO "Performance Configuration:"
    log INFO "  Performance Mode: General Purpose"
    log INFO "  Throughput Mode: Provisioned (100 MiB/s)"
    log INFO "  Encryption: Enabled"
    log INFO ""
    log INFO "Monitoring:"
    log INFO "  CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=EFS-Performance-$EFS_NAME"
    log INFO "  Alarms: 3 performance monitoring alarms created"
    log INFO ""
    log INFO "Next Steps:"
    log INFO "  1. Launch EC2 instances in the same VPC"
    log INFO "  2. Attach security group $SECURITY_GROUP_ID to your instances"
    log INFO "  3. Mount the EFS file system using: $EFS_ID.efs.$AWS_REGION.amazonaws.com:/"
    log INFO "  4. Monitor performance via CloudWatch dashboard"
    log INFO ""
    log INFO "To clean up all resources, run: ./destroy.sh"
    log INFO ""
    log SUCCESS "Deployment log saved to: $LOG_FILE"
}

# Main deployment function
main() {
    log INFO "Starting EFS Performance Optimization deployment..."
    log INFO "Log file: $LOG_FILE"
    
    # Initialize log file
    echo "=== EFS Performance Optimization Deployment Log ===" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    
    check_prerequisites
    setup_environment
    create_security_group
    create_efs_filesystem
    create_mount_targets
    create_cloudwatch_dashboard
    create_cloudwatch_alarms
    validate_deployment
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/efs-dashboard.json"
    
    display_summary
    
    log SUCCESS "Deployment completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "AWS EFS Performance Optimization Deployment Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --help, -h     Show this help message"
            echo "  --verbose, -v  Enable verbose logging"
            echo ""
            echo "This script deploys an optimized EFS file system with:"
            echo "  - Performance-optimized configuration"
            echo "  - Multi-AZ mount targets"
            echo "  - Comprehensive CloudWatch monitoring"
            echo "  - Performance alarms"
            echo ""
            exit 0
            ;;
        --verbose|-v)
            set -x
            shift
            ;;
        *)
            log ERROR "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main