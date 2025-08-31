#!/bin/bash

#####################################################################
# Deploy Script for Simple Infrastructure Templates CloudFormation S3
# Recipe: Simple Infrastructure Templates with CloudFormation and S3
# Version: 1.1
# 
# This script deploys a secure S3 bucket using CloudFormation template
# with proper error handling, logging, and idempotent operations.
#####################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMPLATE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TEMPLATE_FILE="${TEMPLATE_DIR}/s3-infrastructure-template.yaml"

# Default values
DEFAULT_STACK_NAME="simple-s3-infrastructure"
DEFAULT_AWS_REGION="us-east-1"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Display current AWS identity
    local account_id
    local aws_region
    account_id=$(aws sts get-caller-identity --query Account --output text)
    aws_region=$(aws configure get region || echo "$DEFAULT_AWS_REGION")
    
    log "INFO" "AWS Account ID: $account_id"
    log "INFO" "AWS Region: $aws_region"
    
    # Check CloudFormation permissions
    if ! aws cloudformation list-stacks --query 'StackSummaries[0].StackName' --output text &> /dev/null; then
        log "ERROR" "Insufficient CloudFormation permissions. Please check your IAM permissions."
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites check completed"
}

# Function to generate CloudFormation template
generate_template() {
    log "INFO" "Generating CloudFormation template..."
    
    cat > "$TEMPLATE_FILE" << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Simple S3 bucket with security best practices'

Parameters:
  BucketName:
    Type: String
    Description: Name for the S3 bucket
    MinLength: 3
    MaxLength: 63
    AllowedPattern: '^[a-z0-9][a-z0-9-]*[a-z0-9]$'
    ConstraintDescription: 'Bucket name must be 3-63 characters, start and end with lowercase letter or number, contain only lowercase letters, numbers, and hyphens'

Resources:
  MyS3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref BucketName
      VersioningConfiguration:
        Status: Enabled
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
            BucketKeyEnabled: true
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      Tags:
        - Key: Environment
          Value: Development
        - Key: Purpose
          Value: Infrastructure-Template-Demo
        - Key: ManagedBy
          Value: CloudFormation

Outputs:
  BucketName:
    Description: Name of the created S3 bucket
    Value: !Ref MyS3Bucket
    Export:
      Name: !Sub "${AWS::StackName}-BucketName"
  BucketArn:
    Description: ARN of the created S3 bucket
    Value: !GetAtt MyS3Bucket.Arn
    Export:
      Name: !Sub "${AWS::StackName}-BucketArn"
  BucketDomainName:
    Description: Domain name of the S3 bucket
    Value: !GetAtt MyS3Bucket.DomainName
    Export:
      Name: !Sub "${AWS::StackName}-BucketDomainName"
EOF
    
    log "SUCCESS" "CloudFormation template generated at: $TEMPLATE_FILE"
}

# Function to validate template
validate_template() {
    log "INFO" "Validating CloudFormation template..."
    
    local validation_result
    if validation_result=$(aws cloudformation validate-template --template-body "file://$TEMPLATE_FILE" 2>&1); then
        log "SUCCESS" "Template validation successful"
        log "INFO" "Template description: $(echo "$validation_result" | jq -r '.Description // "N/A"')"
    else
        log "ERROR" "Template validation failed: $validation_result"
        exit 1
    fi
}

# Function to check if stack exists
stack_exists() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" &> /dev/null
}

# Function to get stack status
get_stack_status() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND"
}

# Function to deploy stack
deploy_stack() {
    local stack_name="$1"
    local bucket_name="$2"
    
    log "INFO" "Deploying CloudFormation stack: $stack_name"
    log "INFO" "S3 Bucket name: $bucket_name"
    
    # Check if stack already exists
    local current_status
    current_status=$(get_stack_status "$stack_name")
    
    if [[ "$current_status" == "NOT_FOUND" ]]; then
        log "INFO" "Creating new CloudFormation stack..."
        
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters "ParameterKey=BucketName,ParameterValue=$bucket_name" \
            --tags "Key=CreatedBy,Value=deploy-script" \
                   "Key=CreatedAt,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --capabilities CAPABILITY_IAM \
            --enable-termination-protection
            
    elif [[ "$current_status" =~ ^(CREATE_COMPLETE|UPDATE_COMPLETE)$ ]]; then
        log "WARN" "Stack already exists and is in a stable state: $current_status"
        log "INFO" "Updating existing stack..."
        
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters "ParameterKey=BucketName,ParameterValue=$bucket_name" \
            --capabilities CAPABILITY_IAM \
            2>/dev/null || log "INFO" "No updates to be performed"
            
    else
        log "ERROR" "Stack is in an unstable state: $current_status"
        log "ERROR" "Please resolve the stack issue before proceeding"
        exit 1
    fi
}

# Function to wait for stack completion
wait_for_stack() {
    local stack_name="$1"
    local operation="$2"  # create or update
    
    log "INFO" "Waiting for stack $operation to complete..."
    
    local wait_command
    case "$operation" in
        create)
            wait_command="stack-create-complete"
            ;;
        update)
            wait_command="stack-update-complete"
            ;;
        *)
            log "ERROR" "Invalid operation: $operation"
            exit 1
            ;;
    esac
    
    # Use AWS CLI wait with timeout
    if timeout 1800 aws cloudformation wait "$wait_command" --stack-name "$stack_name"; then
        log "SUCCESS" "Stack $operation completed successfully"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log "ERROR" "Stack $operation timed out after 30 minutes"
        else
            log "ERROR" "Stack $operation failed"
        fi
        
        # Show stack events for debugging
        log "INFO" "Recent stack events:"
        aws cloudformation describe-stack-events --stack-name "$stack_name" \
            --query 'StackEvents[0:5].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
            --output table
        exit 1
    fi
}

# Function to display stack outputs
display_outputs() {
    local stack_name="$1"
    
    log "INFO" "Retrieving stack outputs..."
    
    local outputs
    outputs=$(aws cloudformation describe-stacks --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs' --output table 2>/dev/null)
    
    if [[ -n "$outputs" && "$outputs" != "None" ]]; then
        log "SUCCESS" "Stack outputs:"
        echo "$outputs"
        
        # Save outputs to file for reference
        aws cloudformation describe-stacks --stack-name "$stack_name" \
            --query 'Stacks[0].Outputs' --output json > "${SCRIPT_DIR}/stack-outputs.json"
        log "INFO" "Stack outputs saved to: ${SCRIPT_DIR}/stack-outputs.json"
    else
        log "WARN" "No outputs found for stack"
    fi
}

# Function to validate deployment
validate_deployment() {
    local stack_name="$1"
    
    log "INFO" "Validating deployment..."
    
    # Get bucket name from stack outputs
    local bucket_name
    bucket_name=$(aws cloudformation describe-stacks --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
        --output text)
    
    if [[ -z "$bucket_name" || "$bucket_name" == "None" ]]; then
        log "ERROR" "Could not retrieve bucket name from stack outputs"
        exit 1
    fi
    
    log "INFO" "Validating S3 bucket: $bucket_name"
    
    # Check bucket exists and is accessible
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "SUCCESS" "S3 bucket is accessible"
    else
        log "ERROR" "S3 bucket is not accessible"
        exit 1
    fi
    
    # Check encryption configuration
    local encryption_status
    encryption_status=$(aws s3api get-bucket-encryption --bucket "$bucket_name" \
        --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
        --output text 2>/dev/null || echo "NONE")
    
    if [[ "$encryption_status" == "AES256" ]]; then
        log "SUCCESS" "S3 bucket encryption is properly configured"
    else
        log "ERROR" "S3 bucket encryption is not properly configured"
        exit 1
    fi
    
    # Check versioning status
    local versioning_status
    versioning_status=$(aws s3api get-bucket-versioning --bucket "$bucket_name" \
        --query 'Status' --output text 2>/dev/null || echo "NONE")
    
    if [[ "$versioning_status" == "Enabled" ]]; then
        log "SUCCESS" "S3 bucket versioning is enabled"
    else
        log "ERROR" "S3 bucket versioning is not enabled"
        exit 1
    fi
    
    # Check public access block
    local public_access_block
    public_access_block=$(aws s3api get-public-access-block --bucket "$bucket_name" \
        --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null)
    
    if echo "$public_access_block" | jq -e '.BlockPublicAcls and .BlockPublicPolicy and .IgnorePublicAcls and .RestrictPublicBuckets' >/dev/null; then
        log "SUCCESS" "S3 bucket public access is properly blocked"
    else
        log "ERROR" "S3 bucket public access is not properly configured"
        exit 1
    fi
    
    log "SUCCESS" "Deployment validation completed successfully"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Simple Infrastructure Templates CloudFormation S3 Recipe

OPTIONS:
    -s, --stack-name NAME     CloudFormation stack name (default: $DEFAULT_STACK_NAME)
    -b, --bucket-name NAME    S3 bucket name (if not provided, will be generated)
    -r, --region REGION       AWS region (default: current configured region)
    -d, --dry-run            Validate template only, don't deploy
    -v, --verbose            Enable verbose logging
    -h, --help               Show this help message

EXAMPLES:
    $0                                          # Deploy with default settings
    $0 -s my-stack -b my-unique-bucket-name    # Deploy with custom names
    $0 -d                                      # Dry run - validate only
    $0 -v                                      # Verbose logging

NOTES:
    - AWS credentials must be configured
    - S3 bucket names must be globally unique
    - If bucket name is not provided, a unique name will be generated
    - Logs are written to: $LOG_FILE

EOF
}

# Main deployment function
main() {
    local stack_name="$DEFAULT_STACK_NAME"
    local bucket_name=""
    local aws_region=""
    local dry_run=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--stack-name)
                stack_name="$2"
                shift 2
                ;;
            -b|--bucket-name)
                bucket_name="$2"
                shift 2
                ;;
            -r|--region)
                aws_region="$2"
                shift 2
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set AWS region if provided
    if [[ -n "$aws_region" ]]; then
        export AWS_DEFAULT_REGION="$aws_region"
        log "INFO" "Using AWS region: $aws_region"
    fi
    
    # Enable verbose logging if requested
    if [[ "$verbose" == true ]]; then
        set -x
    fi
    
    # Generate bucket name if not provided
    if [[ -z "$bucket_name" ]]; then
        local random_suffix
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            openssl rand -hex 3)
        bucket_name="my-infrastructure-bucket-${random_suffix}"
        log "INFO" "Generated bucket name: $bucket_name"
    fi
    
    # Start deployment
    log "INFO" "Starting deployment process..."
    log "INFO" "Stack name: $stack_name"
    log "INFO" "Bucket name: $bucket_name"
    log "INFO" "Log file: $LOG_FILE"
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    generate_template
    validate_template
    
    if [[ "$dry_run" == true ]]; then
        log "SUCCESS" "Dry run completed successfully. Template is valid."
        exit 0
    fi
    
    # Determine if this is a create or update operation
    local operation="create"
    if stack_exists "$stack_name"; then
        local current_status
        current_status=$(get_stack_status "$stack_name")
        if [[ "$current_status" =~ ^(CREATE_COMPLETE|UPDATE_COMPLETE)$ ]]; then
            operation="update"
        fi
    fi
    
    deploy_stack "$stack_name" "$bucket_name"
    wait_for_stack "$stack_name" "$operation"
    display_outputs "$stack_name"
    validate_deployment "$stack_name"
    
    log "SUCCESS" "Deployment completed successfully!"
    log "INFO" "Stack name: $stack_name"
    log "INFO" "S3 bucket: $bucket_name"
    log "INFO" "To clean up resources, run: ${SCRIPT_DIR}/destroy.sh -s $stack_name"
}

# Trap for cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Deployment failed with exit code: $exit_code"
        log "INFO" "Check the log file for details: $LOG_FILE"
    fi
}

trap cleanup EXIT

# Run main function
main "$@"