#!/bin/bash

# AWS IoT Device Management Cleanup Script
# This script safely removes all IoT device management infrastructure
# based on the recipe "IoT Device Registry with IoT Core"

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to confirm destructive action
confirm_destruction() {
    echo ""
    echo "🚨 WARNING: This will permanently delete all IoT Device Management resources!"
    echo ""
    if [ -f deployment-vars.env ]; then
        source deployment-vars.env
        echo "Resources to be deleted:"
        echo "  • IoT Thing: ${IOT_THING_NAME:-unknown}"
        echo "  • IoT Policy: ${IOT_POLICY_NAME:-unknown}"
        echo "  • Device Certificate: ${CERT_ARN:-unknown}"
        echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME:-unknown}"
        echo "  • IoT Rule: ${IOT_RULE_NAME:-unknown}"
        echo "  • IAM Role: ${LAMBDA_ROLE_NAME:-unknown}"
    else
        warning "deployment-vars.env not found. Will attempt to detect resources."
    fi
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to load environment variables
load_environment() {
    log "Loading deployment configuration..."
    
    if [ -f deployment-vars.env ]; then
        source deployment-vars.env
        log "Loaded deployment variables from deployment-vars.env"
    else
        warning "deployment-vars.env not found"
        
        # Try to detect environment variables from user input
        read -p "Enter IoT Thing name (or press Enter to skip): " IOT_THING_NAME
        read -p "Enter IoT Policy name (or press Enter to skip): " IOT_POLICY_NAME
        read -p "Enter IoT Rule name (or press Enter to skip): " IOT_RULE_NAME
        read -p "Enter Lambda Function name (or press Enter to skip): " LAMBDA_FUNCTION_NAME
        read -p "Enter IAM Role name (or press Enter to skip): " LAMBDA_ROLE_NAME
        
        # Set AWS region if not already set
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, using us-east-1"
        fi
    fi
    
    success "Environment configuration loaded"
}

# Function to remove IoT rule and Lambda permissions
remove_iot_rule() {
    if [ -n "${IOT_RULE_NAME:-}" ]; then
        log "Removing IoT rule and Lambda permissions..."
        
        # Remove Lambda permission for IoT rule
        if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
            aws lambda remove-permission \
                --function-name "${LAMBDA_FUNCTION_NAME}" \
                --statement-id iot-lambda-permission \
                2>/dev/null || warning "Lambda permission may not exist"
        fi
        
        # Delete IoT rule
        aws iot delete-topic-rule \
            --rule-name "${IOT_RULE_NAME}" \
            2>/dev/null || warning "IoT rule may not exist"
        
        success "IoT rule and Lambda permissions removed"
    else
        warning "IoT rule name not specified, skipping"
    fi
}

# Function to delete Lambda function and IAM role
remove_lambda_function() {
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        log "Deleting Lambda function..."
        
        # Delete Lambda function
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            2>/dev/null || warning "Lambda function may not exist"
        
        success "Lambda function deleted"
    else
        warning "Lambda function name not specified, skipping"
    fi
    
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        log "Deleting IAM role..."
        
        # Detach policies from role
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            2>/dev/null || warning "Policy may not be attached"
        
        # Delete IAM role
        aws iam delete-role \
            --role-name "${LAMBDA_ROLE_NAME}" \
            2>/dev/null || warning "IAM role may not exist"
        
        success "IAM role deleted"
    else
        warning "IAM role name not specified, skipping"
    fi
}

# Function to remove certificate associations and delete certificate
remove_device_certificate() {
    if [ -n "${IOT_THING_NAME:-}" ] && [ -n "${CERT_ARN:-}" ]; then
        log "Removing certificate associations..."
        
        # Detach certificate from IoT Thing
        aws iot detach-thing-principal \
            --thing-name "${IOT_THING_NAME}" \
            --principal "${CERT_ARN}" \
            2>/dev/null || warning "Certificate may not be attached to Thing"
        
        # Detach policy from certificate
        if [ -n "${IOT_POLICY_NAME:-}" ]; then
            aws iot detach-policy \
                --policy-name "${IOT_POLICY_NAME}" \
                --target "${CERT_ARN}" \
                2>/dev/null || warning "Policy may not be attached to certificate"
        fi
        
        # Extract certificate ID from ARN
        CERT_ID=$(echo "${CERT_ARN}" | cut -d'/' -f2)
        
        # Deactivate certificate
        aws iot update-certificate \
            --certificate-id "${CERT_ID}" \
            --new-status INACTIVE \
            2>/dev/null || warning "Certificate may already be inactive"
        
        # Delete certificate
        aws iot delete-certificate \
            --certificate-id "${CERT_ID}" \
            --force-delete \
            2>/dev/null || warning "Certificate may not exist"
        
        success "Device certificate deleted"
    else
        warning "Certificate ARN or Thing name not specified, skipping certificate cleanup"
    fi
}

# Function to delete IoT policy and Thing
remove_iot_resources() {
    if [ -n "${IOT_POLICY_NAME:-}" ]; then
        log "Deleting IoT policy..."
        
        # Delete IoT policy
        aws iot delete-policy \
            --policy-name "${IOT_POLICY_NAME}" \
            2>/dev/null || warning "IoT policy may not exist"
        
        success "IoT policy deleted"
    else
        warning "IoT policy name not specified, skipping"
    fi
    
    if [ -n "${IOT_THING_NAME:-}" ]; then
        log "Deleting IoT Thing..."
        
        # Delete IoT Thing
        aws iot delete-thing \
            --thing-name "${IOT_THING_NAME}" \
            2>/dev/null || warning "IoT Thing may not exist"
        
        success "IoT Thing deleted"
    else
        warning "IoT Thing name not specified, skipping"
    fi
}

# Function to clean up CloudWatch logs
cleanup_cloudwatch_logs() {
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        log "Cleaning up CloudWatch log groups..."
        
        # Delete Lambda function log group
        aws logs delete-log-group \
            --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" \
            2>/dev/null || warning "Lambda log group may not exist"
        
        success "CloudWatch log groups cleaned up"
    else
        warning "Lambda function name not specified, skipping log cleanup"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of files to remove
    files_to_remove=(
        "device-cert.pem"
        "device-public-key.pem"
        "device-private-key.pem"
        "cert-arn.txt"
        "device-policy.json"
        "lambda-trust-policy.json"
        "lambda-function.py"
        "lambda-function.zip"
        "iot-rule.json"
        "device-shadow.json"
        "shadow-response.json"
        "iot-thing-result.json"
        "lambda-test-response.json"
        "outfile"
    )
    
    # Remove files if they exist
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify resource deletion
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    cleanup_verified=true
    
    # Check if IoT Thing still exists
    if [ -n "${IOT_THING_NAME:-}" ]; then
        if aws iot describe-thing --thing-name "${IOT_THING_NAME}" &>/dev/null; then
            warning "IoT Thing still exists: ${IOT_THING_NAME}"
            cleanup_verified=false
        fi
    fi
    
    # Check if Lambda function still exists
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            cleanup_verified=false
        fi
    fi
    
    # Check if IoT rule still exists
    if [ -n "${IOT_RULE_NAME:-}" ]; then
        if aws iot get-topic-rule --rule-name "${IOT_RULE_NAME}" &>/dev/null; then
            warning "IoT rule still exists: ${IOT_RULE_NAME}"
            cleanup_verified=false
        fi
    fi
    
    # Check if IAM role still exists
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
            warning "IAM role still exists: ${LAMBDA_ROLE_NAME}"
            cleanup_verified=false
        fi
    fi
    
    if [ "$cleanup_verified" = true ]; then
        success "All resources successfully cleaned up"
    else
        warning "Some resources may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo ""
    echo "🗑️  Resources Removed:"
    echo "  • IoT Thing: ${IOT_THING_NAME:-'not specified'}"
    echo "  • IoT Policy: ${IOT_POLICY_NAME:-'not specified'}"
    echo "  • Device Certificate: ${CERT_ARN:-'not specified'}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME:-'not specified'}"
    echo "  • IoT Rule: ${IOT_RULE_NAME:-'not specified'}"
    echo "  • IAM Role: ${LAMBDA_ROLE_NAME:-'not specified'}"
    echo "  • CloudWatch Log Groups"
    echo "  • Local deployment files"
    echo ""
    
    if [ -n "${DEPLOY_DIR:-}" ] && [ "$PWD" = "$DEPLOY_DIR" ]; then
        echo "📁 You can now safely delete this deployment directory:"
        echo "   cd .. && rm -rf $(basename "$DEPLOY_DIR")"
        echo ""
    fi
    
    success "IoT Device Management infrastructure cleanup completed!"
}

# Function to handle orphaned resources
cleanup_orphaned_resources() {
    log "Checking for orphaned resources..."
    
    # Find IoT things with temperature-sensor prefix
    echo "Searching for orphaned IoT things..."
    aws iot list-things --query 'things[?starts_with(thingName, `temperature-sensor-`)].thingName' --output text | \
    while read -r thing_name; do
        if [ -n "$thing_name" ]; then
            warning "Found orphaned IoT Thing: $thing_name"
            read -p "Delete this Thing? (y/n): " delete_thing
            if [ "$delete_thing" = "y" ]; then
                # Get thing principals (certificates)
                aws iot list-thing-principals --thing-name "$thing_name" --query 'principals' --output text | \
                while read -r principal; do
                    if [ -n "$principal" ]; then
                        aws iot detach-thing-principal --thing-name "$thing_name" --principal "$principal" || true
                    fi
                done
                aws iot delete-thing --thing-name "$thing_name" || true
                success "Deleted orphaned Thing: $thing_name"
            fi
        fi
    done
    
    # Find policies with device-policy prefix
    echo "Searching for orphaned IoT policies..."
    aws iot list-policies --query 'policies[?starts_with(policyName, `device-policy-`)].policyName' --output text | \
    while read -r policy_name; do
        if [ -n "$policy_name" ]; then
            warning "Found orphaned IoT Policy: $policy_name"
            read -p "Delete this Policy? (y/n): " delete_policy
            if [ "$delete_policy" = "y" ]; then
                aws iot delete-policy --policy-name "$policy_name" || true
                success "Deleted orphaned Policy: $policy_name"
            fi
        fi
    done
}

# Main cleanup function
main() {
    log "Starting AWS IoT Device Management cleanup..."
    
    confirm_destruction
    load_environment
    remove_iot_rule
    remove_lambda_function
    remove_device_certificate
    remove_iot_resources
    cleanup_cloudwatch_logs
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    # Offer to clean up orphaned resources
    echo ""
    read -p "Would you like to search for and clean up orphaned resources? (y/n): " cleanup_orphaned
    if [ "$cleanup_orphaned" = "y" ]; then
        cleanup_orphaned_resources
    fi
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist."' INT TERM

# Run main function
main "$@"