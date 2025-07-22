#!/bin/bash

# AWS IoT Data Ingestion Pipeline Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Global variables
FORCE_DELETE=false
DEPLOYMENT_VARS_FILE="deployment_vars.txt"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install and configure it first."
        exit 1
    fi
    
    # Check if AWS is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment variables
load_deployment_vars() {
    if [[ ! -f "$DEPLOYMENT_VARS_FILE" ]]; then
        log_error "Deployment variables file ($DEPLOYMENT_VARS_FILE) not found."
        log_error "This file is created during deployment and contains resource identifiers."
        log_error "Without it, manual cleanup may be required."
        exit 1
    fi
    
    log_info "Loading deployment variables from $DEPLOYMENT_VARS_FILE..."
    source "$DEPLOYMENT_VARS_FILE"
    
    # Verify required variables are loaded
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "IOT_THING_NAME" "IOT_POLICY_NAME"
        "LAMBDA_FUNCTION_NAME" "DYNAMODB_TABLE_NAME" "IAM_ROLE_NAME"
        "SNS_TOPIC_NAME" "IOT_RULE_NAME" "CERT_ARN" "CERT_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not found in deployment variables file."
            exit 1
        fi
    done
    
    log_success "Deployment variables loaded successfully"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "- IoT Thing: $IOT_THING_NAME"
    echo "- IoT Policy: $IOT_POLICY_NAME"
    echo "- IoT Rule: $IOT_RULE_NAME"
    echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- DynamoDB Table: $DYNAMODB_TABLE_NAME (and all data)"
    echo "- IAM Role: $IAM_ROLE_NAME"
    echo "- SNS Topic: ${SNS_TOPIC_ARN:-$SNS_TOPIC_NAME}"
    echo "- IoT Certificates and local certificate files"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to delete IoT Rule
delete_iot_rule() {
    log_info "Deleting IoT Rule: $IOT_RULE_NAME..."
    
    if aws iot get-topic-rule --rule-name "$IOT_RULE_NAME" &>/dev/null; then
        aws iot delete-topic-rule --rule-name "$IOT_RULE_NAME"
        log_success "IoT Rule deleted successfully"
    else
        log_warning "IoT Rule $IOT_RULE_NAME not found (may already be deleted)"
    fi
}

# Function to delete Lambda function and permissions
delete_lambda_function() {
    log_info "Deleting Lambda function: $LAMBDA_FUNCTION_NAME..."
    
    # Remove IoT permission from Lambda function
    aws lambda remove-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id iot-invoke 2>/dev/null || true
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log_success "Lambda function deleted successfully"
    else
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME not found (may already be deleted)"
    fi
    
    # Clean up local Lambda files
    if [[ -d "iot-processor" ]]; then
        rm -rf iot-processor
        log_info "Local Lambda files cleaned up"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log_info "Deleting DynamoDB table: $DYNAMODB_TABLE_NAME..."
    
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" &>/dev/null; then
        aws dynamodb delete-table --table-name "$DYNAMODB_TABLE_NAME"
        
        # Wait for table deletion
        log_info "Waiting for DynamoDB table deletion to complete..."
        aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE_NAME"
        
        log_success "DynamoDB table deleted successfully"
    else
        log_warning "DynamoDB table $DYNAMODB_TABLE_NAME not found (may already be deleted)"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
            log_success "SNS topic deleted successfully"
        else
            log_warning "SNS topic not found (may already be deleted)"
        fi
    else
        log_warning "SNS topic ARN not found in deployment variables"
    fi
}

# Function to delete IAM role and policies
delete_iam_role() {
    log_info "Deleting IAM role and policies: $IAM_ROLE_NAME..."
    
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-name IoTProcessorPolicy 2>/dev/null || true
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$IAM_ROLE_NAME"
        log_success "IAM role and policies deleted successfully"
    else
        log_warning "IAM role $IAM_ROLE_NAME not found (may already be deleted)"
    fi
}

# Function to delete IoT certificates and policies
delete_iot_certificates() {
    log_info "Deleting IoT certificates and policies..."
    
    # Detach certificate from thing
    if aws iot describe-thing --thing-name "$IOT_THING_NAME" &>/dev/null && [[ -n "${CERT_ARN:-}" ]]; then
        aws iot detach-thing-principal \
            --thing-name "$IOT_THING_NAME" \
            --principal "$CERT_ARN" 2>/dev/null || true
        log_info "Certificate detached from IoT Thing"
    fi
    
    # Detach policy from certificate
    if [[ -n "${CERT_ARN:-}" ]]; then
        aws iot detach-principal-policy \
            --policy-name "$IOT_POLICY_NAME" \
            --principal "$CERT_ARN" 2>/dev/null || true
        log_info "Policy detached from certificate"
    fi
    
    # Delete certificate
    if [[ -n "${CERT_ID:-}" ]]; then
        # Deactivate certificate first
        aws iot update-certificate \
            --certificate-id "$CERT_ID" \
            --new-status INACTIVE 2>/dev/null || true
        
        # Delete certificate
        aws iot delete-certificate --certificate-id "$CERT_ID" 2>/dev/null || true
        log_success "IoT certificate deleted"
    fi
    
    # Delete IoT policy
    if aws iot get-policy --policy-name "$IOT_POLICY_NAME" &>/dev/null; then
        aws iot delete-policy --policy-name "$IOT_POLICY_NAME"
        log_success "IoT policy deleted"
    else
        log_warning "IoT policy $IOT_POLICY_NAME not found (may already be deleted)"
    fi
}

# Function to delete IoT Thing
delete_iot_thing() {
    log_info "Deleting IoT Thing: $IOT_THING_NAME..."
    
    if aws iot describe-thing --thing-name "$IOT_THING_NAME" &>/dev/null; then
        aws iot delete-thing --thing-name "$IOT_THING_NAME"
        log_success "IoT Thing deleted successfully"
    else
        log_warning "IoT Thing $IOT_THING_NAME not found (may already be deleted)"
    fi
    
    # Also try to delete the thing type (if no other things are using it)
    aws iot delete-thing-type --thing-type-name "SensorDevice" 2>/dev/null || true
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "device-cert.pem"
        "device-private.key"
        "device-public.key"
        "amazon-root-ca.pem"
        "iot-policy.json"
        "iot-rule.json"
        "lambda-trust-policy.json"
        "lambda-permissions.json"
        "deployment_vars.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    # Check IoT Thing
    if aws iot describe-thing --thing-name "$IOT_THING_NAME" &>/dev/null; then
        log_error "IoT Thing $IOT_THING_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_error "Lambda function $LAMBDA_FUNCTION_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" &>/dev/null; then
        log_error "DynamoDB table $DYNAMODB_TABLE_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log_error "IAM role $IAM_ROLE_NAME still exists"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
    else
        log_warning "$cleanup_errors resources may still exist. Manual cleanup may be required."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "==============="
    echo "The following resources have been removed:"
    echo "- IoT Thing: $IOT_THING_NAME"
    echo "- IoT Policy: $IOT_POLICY_NAME"
    echo "- IoT Rule: $IOT_RULE_NAME"
    echo "- IoT Certificates"
    echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- DynamoDB Table: $DYNAMODB_TABLE_NAME"
    echo "- IAM Role: $IAM_ROLE_NAME"
    echo "- SNS Topic: ${SNS_TOPIC_ARN:-$SNS_TOPIC_NAME}"
    echo "- Local certificate and configuration files"
    echo ""
    log_success "AWS IoT Data Ingestion Pipeline cleanup completed!"
}

# Error handling function
handle_error() {
    local exit_code=$?
    log_error "An error occurred during cleanup (exit code: $exit_code)"
    log_error "Some resources may not have been deleted. Please check AWS console and clean up manually if needed."
    exit $exit_code
}

# Trap errors
trap handle_error ERR

# Main cleanup flow
main() {
    log_info "Starting AWS IoT Data Ingestion Pipeline cleanup..."
    
    check_prerequisites
    load_deployment_vars
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_iot_rule
    delete_lambda_function
    delete_iam_role
    delete_sns_topic
    delete_dynamodb_table
    delete_iot_certificates
    delete_iot_thing
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
    exit 0
}

# Help function
show_help() {
    echo "AWS IoT Data Ingestion Pipeline Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Force deletion without confirmation prompt"
    echo "  --vars-file    Specify custom deployment variables file (default: deployment_vars.txt)"
    echo ""
    echo "This script removes all resources created by the deployment script:"
    echo "- AWS IoT Core resources (Thing, Policy, Certificates, Rules)"
    echo "- Lambda function and IAM role"
    echo "- DynamoDB table and all data"
    echo "- SNS topic"
    echo "- Local certificate and configuration files"
    echo ""
    echo "Prerequisites:"
    echo "- AWS CLI installed and configured"
    echo "- deployment_vars.txt file from deployment"
    echo "- Appropriate AWS permissions for resource deletion"
    echo ""
    echo "WARNING: This operation is irreversible and will delete all data!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        --vars-file)
            DEPLOYMENT_VARS_FILE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"