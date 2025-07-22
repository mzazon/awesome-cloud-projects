#!/bin/bash

# IoT Device Fleet Monitoring Cleanup Script
# This script removes all AWS resources created by the deployment script
# Recipe: IoT Fleet Monitoring with Device Defender

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOY_STATE_FILE="${SCRIPT_DIR}/.deploy_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}❌ Error: $1${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Confirmation prompt
confirm_destruction() {
    echo -e "${YELLOW}⚠️  WARNING: This script will permanently delete all IoT fleet monitoring resources!${NC}"
    echo -e "${YELLOW}   This action cannot be undone.${NC}"
    echo ""
    
    # Show resources to be deleted if state file exists
    if [ -f "${DEPLOY_STATE_FILE}" ]; then
        echo "Resources to be deleted:"
        echo "========================"
        source "${DEPLOY_STATE_FILE}"
        echo "Fleet Name: ${FLEET_NAME:-unknown}"
        echo "Security Profile: ${SECURITY_PROFILE_NAME:-unknown}"
        echo "Dashboard: ${DASHBOARD_NAME:-unknown}"
        echo "SNS Topic: ${SNS_TOPIC_NAME:-unknown}"
        echo "Lambda Function: ${LAMBDA_FUNCTION_NAME:-unknown}"
        echo "AWS Region: ${AWS_REGION:-unknown}"
        echo ""
    fi
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        echo "Destruction cancelled."
        exit 0
    fi
    
    echo ""
    info "Proceeding with resource destruction..."
}

# Load deployment state
load_deployment_state() {
    if [ ! -f "${DEPLOY_STATE_FILE}" ]; then
        error_exit "Deployment state file not found: ${DEPLOY_STATE_FILE}"
    fi
    
    source "${DEPLOY_STATE_FILE}"
    
    # Verify required variables are set
    if [ -z "${FLEET_NAME:-}" ] || [ -z "${AWS_REGION:-}" ]; then
        error_exit "Invalid deployment state file. Required variables not found."
    fi
    
    success "Deployment state loaded successfully"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Verify AWS permissions
    info "Verifying AWS permissions..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "Unable to verify AWS credentials. Please check your AWS configuration."
    fi
    
    success "Prerequisites check completed"
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    info "Removing CloudWatch resources..."
    
    # Delete dashboard
    if [ -n "${DASHBOARD_NAME:-}" ]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "${DASHBOARD_NAME}" 2>/dev/null || {
            warning "Dashboard ${DASHBOARD_NAME} may not exist or already deleted"
        }
        success "Dashboard deleted: ${DASHBOARD_NAME}"
    fi
    
    # Delete alarms
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        for alarm in "IoT-Fleet-High-Security-Violations-${RANDOM_SUFFIX}" \
                     "IoT-Fleet-Low-Connectivity-${RANDOM_SUFFIX}" \
                     "IoT-Fleet-Message-Processing-Errors-${RANDOM_SUFFIX}"; do
            aws cloudwatch delete-alarms \
                --alarm-names "${alarm}" 2>/dev/null || {
                warning "Alarm ${alarm} may not exist or already deleted"
            }
        done
        success "CloudWatch alarms deleted"
    fi
    
    success "CloudWatch resources removed"
}

# Remove IoT rules and log groups
remove_iot_rules() {
    info "Removing IoT rules and log groups..."
    
    # Delete IoT rules
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        for rule in "DeviceConnectionMonitoring${RANDOM_SUFFIX}" \
                    "MessageVolumeMonitoring${RANDOM_SUFFIX}"; do
            aws iot delete-topic-rule \
                --rule-name "${rule}" 2>/dev/null || {
                warning "IoT rule ${rule} may not exist or already deleted"
            }
        done
        success "IoT rules deleted"
    fi
    
    # Delete log group
    aws logs delete-log-group \
        --log-group-name "/aws/iot/fleet-monitoring" 2>/dev/null || {
        warning "Log group may not exist or already deleted"
    }
    
    success "IoT rules and log groups removed"
}

# Remove Lambda function and SNS topic
remove_lambda_and_sns() {
    info "Removing Lambda function and SNS resources..."
    
    # Delete Lambda function
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null || {
            warning "Lambda function ${LAMBDA_FUNCTION_NAME} may not exist or already deleted"
        }
        success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    # Delete SNS topic
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        aws sns delete-topic \
            --topic-arn "${SNS_TOPIC_ARN}" 2>/dev/null || {
            warning "SNS topic may not exist or already deleted"
        }
        success "SNS topic deleted"
    fi
    
    success "Lambda function and SNS resources removed"
}

# Remove IoT Device Defender configuration
remove_device_defender() {
    info "Removing IoT Device Defender configuration..."
    
    # Detach security profile from thing group
    if [ -n "${SECURITY_PROFILE_NAME:-}" ] && [ -n "${FLEET_NAME:-}" ]; then
        aws iot detach-security-profile \
            --security-profile-name "${SECURITY_PROFILE_NAME}" \
            --security-profile-target-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thinggroup/${FLEET_NAME}" 2>/dev/null || {
            warning "Security profile may not be attached or already detached"
        }
        success "Security profile detached from thing group"
    fi
    
    # Delete security profile
    if [ -n "${SECURITY_PROFILE_NAME:-}" ]; then
        aws iot delete-security-profile \
            --security-profile-name "${SECURITY_PROFILE_NAME}" 2>/dev/null || {
            warning "Security profile ${SECURITY_PROFILE_NAME} may not exist or already deleted"
        }
        success "Security profile deleted: ${SECURITY_PROFILE_NAME}"
    fi
    
    # Delete scheduled audit
    if [ -n "${SCHEDULED_AUDIT_NAME:-}" ]; then
        aws iot delete-scheduled-audit \
            --scheduled-audit-name "${SCHEDULED_AUDIT_NAME}" 2>/dev/null || {
            warning "Scheduled audit ${SCHEDULED_AUDIT_NAME} may not exist or already deleted"
        }
        success "Scheduled audit deleted: ${SCHEDULED_AUDIT_NAME}"
    fi
    
    success "Device Defender configuration removed"
}

# Remove test IoT things and thing group
remove_iot_things() {
    info "Removing IoT things and thing group..."
    
    # Remove test devices from thing group and delete things
    if [ -n "${FLEET_NAME:-}" ]; then
        for i in {1..5}; do
            THING_NAME="device-${FLEET_NAME}-${i}"
            # Remove thing from group
            aws iot remove-thing-from-thing-group \
                --thing-group-name "${FLEET_NAME}" \
                --thing-name "${THING_NAME}" 2>/dev/null || {
                warning "Thing ${THING_NAME} may not be in group or already removed"
            }
            # Delete thing
            aws iot delete-thing \
                --thing-name "${THING_NAME}" 2>/dev/null || {
                warning "Thing ${THING_NAME} may not exist or already deleted"
            }
        done
        success "Device things removed from fleet"
    fi
    
    # Delete test device
    if [ -n "${TEST_DEVICE_NAME:-}" ] && [ -n "${FLEET_NAME:-}" ]; then
        aws iot remove-thing-from-thing-group \
            --thing-group-name "${FLEET_NAME}" \
            --thing-name "${TEST_DEVICE_NAME}" 2>/dev/null || {
            warning "Test device may not be in group or already removed"
        }
        aws iot delete-thing \
            --thing-name "${TEST_DEVICE_NAME}" 2>/dev/null || {
            warning "Test device may not exist or already deleted"
        }
        success "Test device deleted: ${TEST_DEVICE_NAME}"
    fi
    
    # Delete thing group
    if [ -n "${FLEET_NAME:-}" ]; then
        aws iot delete-thing-group \
            --thing-group-name "${FLEET_NAME}" 2>/dev/null || {
            warning "Thing group ${FLEET_NAME} may not exist or already deleted"
        }
        success "Thing group deleted: ${FLEET_NAME}"
    fi
    
    success "IoT things and thing group removed"
}

# Remove IAM roles and policies
remove_iam_resources() {
    info "Removing IAM roles and policies..."
    
    # Detach and delete policies from Device Defender role
    if [ -n "${DEVICE_DEFENDER_ROLE_NAME:-}" ]; then
        aws iam detach-role-policy \
            --role-name "${DEVICE_DEFENDER_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSIoTDeviceDefenderAudit 2>/dev/null || {
            warning "Policy may not be attached to Device Defender role"
        }
        
        # Delete Device Defender role
        aws iam delete-role \
            --role-name "${DEVICE_DEFENDER_ROLE_NAME}" 2>/dev/null || {
            warning "Device Defender role may not exist or already deleted"
        }
        success "Device Defender role deleted: ${DEVICE_DEFENDER_ROLE_NAME}"
    fi
    
    # Detach and delete policies from Lambda role
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || {
            warning "Basic execution policy may not be attached to Lambda role"
        }
        
        if [ -n "${CUSTOM_POLICY_NAME:-}" ] && [ -n "${AWS_ACCOUNT_ID:-}" ]; then
            aws iam detach-role-policy \
                --role-name "${LAMBDA_ROLE_NAME}" \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${CUSTOM_POLICY_NAME}" 2>/dev/null || {
                warning "Custom policy may not be attached to Lambda role"
            }
        fi
        
        # Delete Lambda role
        aws iam delete-role \
            --role-name "${LAMBDA_ROLE_NAME}" 2>/dev/null || {
            warning "Lambda role may not exist or already deleted"
        }
        success "Lambda role deleted: ${LAMBDA_ROLE_NAME}"
    fi
    
    # Delete custom policy
    if [ -n "${CUSTOM_POLICY_NAME:-}" ] && [ -n "${AWS_ACCOUNT_ID:-}" ]; then
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${CUSTOM_POLICY_NAME}" 2>/dev/null || {
            warning "Custom policy may not exist or already deleted"
        }
        success "Custom policy deleted: ${CUSTOM_POLICY_NAME}"
    fi
    
    success "IAM roles and policies removed"
}

# Clean up temporary and state files
cleanup_files() {
    info "Cleaning up temporary and state files..."
    
    # Remove temporary files
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/dashboard.json
    
    # Remove deployment state file
    if [ -f "${DEPLOY_STATE_FILE}" ]; then
        rm -f "${DEPLOY_STATE_FILE}"
        success "Deployment state file removed"
    fi
    
    success "File cleanup completed"
}

# Wait for resources to be fully deleted
wait_for_resource_deletion() {
    info "Waiting for resource deletion to complete..."
    
    # Wait for Lambda function deletion
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        info "Waiting for Lambda function deletion..."
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
                success "Lambda function deletion confirmed"
                break
            fi
            
            if [ $attempt -eq $max_attempts ]; then
                warning "Lambda function may still be deleting"
                break
            fi
            
            sleep 2
            ((attempt++))
        done
    fi
    
    # Wait for IAM role deletion propagation
    info "Waiting for IAM role deletion propagation..."
    sleep 5
    
    success "Resource deletion wait completed"
}

# Display destruction summary
display_destruction_summary() {
    info "Destruction Summary:"
    echo "===================="
    echo "Fleet Name: ${FLEET_NAME:-unknown}"
    echo "Security Profile: ${SECURITY_PROFILE_NAME:-unknown}"
    echo "Dashboard: ${DASHBOARD_NAME:-unknown}"
    echo "SNS Topic: ${SNS_TOPIC_NAME:-unknown}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME:-unknown}"
    echo "Test Device: ${TEST_DEVICE_NAME:-unknown}"
    echo "AWS Region: ${AWS_REGION:-unknown}"
    echo ""
    echo "All resources have been deleted."
    echo "Destruction logs saved to: ${LOG_FILE}"
    echo ""
    echo "Note: Some resources may take additional time to be fully removed from AWS."
}

# Validate deletion (optional verification)
validate_deletion() {
    info "Performing deletion validation..."
    
    local validation_errors=0
    
    # Check if Lambda function still exists
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
            warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            ((validation_errors++))
        fi
    fi
    
    # Check if thing group still exists
    if [ -n "${FLEET_NAME:-}" ]; then
        if aws iot describe-thing-group --thing-group-name "${FLEET_NAME}" >/dev/null 2>&1; then
            warning "Thing group still exists: ${FLEET_NAME}"
            ((validation_errors++))
        fi
    fi
    
    # Check if security profile still exists
    if [ -n "${SECURITY_PROFILE_NAME:-}" ]; then
        if aws iot describe-security-profile --security-profile-name "${SECURITY_PROFILE_NAME}" >/dev/null 2>&1; then
            warning "Security profile still exists: ${SECURITY_PROFILE_NAME}"
            ((validation_errors++))
        fi
    fi
    
    if [ $validation_errors -eq 0 ]; then
        success "Deletion validation completed - no remaining resources found"
    else
        warning "Deletion validation found ${validation_errors} resources that may still exist"
        warning "These resources may be in the process of being deleted"
    fi
}

# Main destruction function
main() {
    echo "Starting IoT Device Fleet Monitoring resource destruction..."
    echo "=========================================================="
    
    # Initialize log file
    echo "Destruction started at $(date)" > "${LOG_FILE}"
    
    # Show confirmation prompt
    confirm_destruction
    
    # Run destruction steps
    check_prerequisites
    load_deployment_state
    
    # Remove resources in reverse order of creation
    remove_cloudwatch_resources
    remove_iot_rules
    remove_lambda_and_sns
    remove_device_defender
    remove_iot_things
    wait_for_resource_deletion
    remove_iam_resources
    validate_deletion
    cleanup_files
    
    success "Destruction completed successfully!"
    display_destruction_summary
    
    echo ""
    echo "Thank you for using the IoT Device Fleet Monitoring solution."
    echo "All resources have been cleaned up to avoid ongoing charges."
}

# Handle script interruption
trap 'echo -e "\n${RED}Script interrupted. Some resources may not have been deleted.${NC}"; exit 1' INT TERM

# Run main function
main "$@"