#!/bin/bash

# Database Performance Monitoring CDK Destruction Script
# This script provides an easy way to destroy the CDK stack and cleanup resources

set -e

# Default values
STACK_NAME="DatabasePerformanceMonitoringStack"
REGION=""
SKIP_CONFIRMATION="false"
PROFILE=""
FORCE_DELETE="false"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -s, --stack-name NAME          CDK stack name (default: $STACK_NAME)"
    echo "  -r, --region REGION            AWS region (default: from AWS CLI config)"
    echo "  -y, --yes                      Skip confirmation prompts"
    echo "  -f, --force                    Force deletion even if stack is in use"
    echo "  -p, --profile PROFILE          AWS CLI profile to use"
    echo "  -h, --help                     Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -s MyStackName -r us-west-2"
    echo "  $0 --yes --force"
    echo "  $0 -p production-profile"
}

# Function to check prerequisites
check_prerequisites() {
    print_color $BLUE "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_color $RED "Error: AWS CLI is not installed."
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_color $RED "Error: AWS CDK is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if [[ -n "$PROFILE" ]]; then
        export AWS_PROFILE=$PROFILE
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_color $RED "Error: AWS credentials not configured or invalid."
        exit 1
    fi
    
    print_color $GREEN "✓ All prerequisites met"
}

# Function to set region
set_region() {
    if [[ -z "$REGION" ]]; then
        REGION=$(aws configure get region)
        if [[ -z "$REGION" ]]; then
            print_color $RED "Error: No region specified and no default region configured."
            exit 1
        fi
    fi
    
    export CDK_DEFAULT_REGION=$REGION
    print_color $GREEN "✓ Using region: $REGION"
}

# Function to check if stack exists
check_stack_exists() {
    print_color $BLUE "Checking if stack exists..."
    
    if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
        print_color $YELLOW "Warning: Stack '$STACK_NAME' does not exist in region '$REGION'."
        print_color $GREEN "Nothing to destroy."
        exit 0
    fi
    
    print_color $GREEN "✓ Stack exists and can be destroyed"
}

# Function to show stack resources
show_stack_resources() {
    print_color $BLUE "Current stack resources:"
    echo "=========================="
    
    aws cloudformation describe-stack-resources \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'StackResources[*].[LogicalResourceId,ResourceType,ResourceStatus]' \
        --output table
    
    echo
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    print_color $YELLOW "⚠️  WARNING: This will permanently destroy the following resources:"
    echo "  - RDS Database instance and all its data"
    echo "  - S3 bucket and all performance reports"
    echo "  - Lambda functions and logs"
    echo "  - CloudWatch alarms and dashboard"
    echo "  - SNS topics and subscriptions"
    echo "  - All associated IAM roles and policies"
    echo
    
    print_color $RED "🚨 THIS ACTION CANNOT BE UNDONE! 🚨"
    echo
    
    read -p "Are you sure you want to destroy the stack '$STACK_NAME'? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        print_color $GREEN "Destruction cancelled."
        exit 0
    fi
}

# Function to backup important data
backup_data() {
    print_color $BLUE "Checking for backup opportunities..."
    
    # Get S3 bucket name from stack outputs
    local bucket_name=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`ReportsBucketName`].OutputValue' \
        --output text 2>/dev/null)
    
    if [[ -n "$bucket_name" && "$bucket_name" != "None" ]]; then
        print_color $YELLOW "Found S3 bucket with performance reports: $bucket_name"
        
        if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
            read -p "Do you want to create a backup of performance reports? (y/n): " backup_choice
            
            if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
                local backup_bucket="backup-$(date +%Y%m%d%H%M%S)-$bucket_name"
                print_color $BLUE "Creating backup bucket: $backup_bucket"
                
                aws s3 mb s3://$backup_bucket --region $REGION
                aws s3 sync s3://$bucket_name s3://$backup_bucket --region $REGION
                
                print_color $GREEN "✓ Backup created in bucket: $backup_bucket"
                print_color $YELLOW "Don't forget to delete the backup bucket when no longer needed."
            fi
        fi
    fi
}

# Function to destroy the stack
destroy_stack() {
    print_color $BLUE "Destroying CDK stack..."
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        print_color $YELLOW "Force deletion enabled - attempting to delete stack even if resources are in use"
    fi
    
    # First, try to empty S3 buckets to avoid deletion failures
    print_color $BLUE "Preparing S3 buckets for deletion..."
    
    local bucket_name=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`ReportsBucketName`].OutputValue' \
        --output text 2>/dev/null)
    
    if [[ -n "$bucket_name" && "$bucket_name" != "None" ]]; then
        print_color $BLUE "Emptying S3 bucket: $bucket_name"
        aws s3 rm s3://$bucket_name --recursive --region $REGION 2>/dev/null || true
        
        # Delete all versions if versioning is enabled
        aws s3api delete-objects \
            --bucket $bucket_name \
            --delete "$(aws s3api list-object-versions \
                --bucket $bucket_name \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --region $REGION)" \
            --region $REGION 2>/dev/null || true
        
        print_color $GREEN "✓ S3 bucket emptied"
    fi
    
    # Destroy the CDK stack
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        cdk destroy $STACK_NAME --force
    else
        cdk destroy $STACK_NAME
    fi
    
    print_color $GREEN "✓ Stack destroyed successfully"
}

# Function to cleanup remaining resources
cleanup_remaining() {
    print_color $BLUE "Checking for remaining resources..."
    
    # Check if there are any remaining resources
    if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
        print_color $YELLOW "Warning: Stack still exists. Some resources may not have been deleted."
        
        if [[ "$FORCE_DELETE" == "true" ]]; then
            print_color $BLUE "Force deletion enabled - attempting to delete remaining resources manually"
            
            # Try to delete the stack through CloudFormation
            aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
            
            print_color $BLUE "Waiting for stack deletion to complete..."
            aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION
        fi
    else
        print_color $GREEN "✓ No remaining resources found"
    fi
}

# Function to show destruction summary
show_summary() {
    print_color $BLUE "Destruction Summary:"
    echo "===================="
    echo "Stack Name: $STACK_NAME"
    echo "Region: $REGION"
    echo "Timestamp: $(date)"
    echo
    
    if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
        print_color $GREEN "✅ Stack successfully destroyed"
    else
        print_color $YELLOW "⚠️  Stack may still exist - check AWS Console"
    fi
    
    echo
    print_color $GREEN "🗑️  Database Performance Monitoring solution destroyed!"
    print_color $BLUE "Remember to:"
    echo "  1. Check for any remaining resources in the AWS Console"
    echo "  2. Verify that all charges have stopped"
    echo "  3. Clean up any backup buckets created during this process"
    echo "  4. Remove any local configuration files if no longer needed"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -y|--yes)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        -f|--force)
            FORCE_DELETE="true"
            shift
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_color $RED "Error: Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
print_color $BLUE "Starting Database Performance Monitoring CDK destruction..."
echo

check_prerequisites
set_region
check_stack_exists
show_stack_resources
confirm_destruction
backup_data
destroy_stack
cleanup_remaining
show_summary

print_color $GREEN "Destruction completed successfully! 🗑️"