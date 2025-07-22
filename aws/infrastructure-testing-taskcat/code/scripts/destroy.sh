#!/bin/bash

# Infrastructure Testing with TaskCat and CloudFormation - Cleanup Script
# This script safely removes all resources created by the TaskCat deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output formatting
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

# Check if dry run mode is enabled
DRY_RUN=${DRY_RUN:-false}

if [ "$DRY_RUN" = "true" ]; then
    log_warning "Running in DRY RUN mode - no resources will be destroyed"
fi

# Check if force mode is enabled (skip confirmations)
FORCE_MODE=${FORCE_MODE:-false}

# Function to execute commands (respects dry run mode)
execute_command() {
    local command="$1"
    local description="$2"
    
    log "$description"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY RUN: $command"
        return 0
    else
        eval "$command" || {
            log_warning "Command failed but continuing cleanup: $command"
            return 0  # Continue cleanup even if individual commands fail
        }
    fi
}

# Function to wait for user confirmation
confirm_action() {
    local message="$1"
    
    if [ "$FORCE_MODE" = "true" ]; then
        log "FORCE MODE: Skipping confirmation for: $message"
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    echo -n "Do you want to continue? (y/N): "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log "Operation cancelled by user"
            exit 0
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check TaskCat (warn if not available but don't fail)
    if ! command -v taskcat &> /dev/null; then
        log_warning "TaskCat is not installed. Manual stack cleanup may be required."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to detect existing TaskCat projects
detect_taskcat_projects() {
    log "Detecting TaskCat projects and resources..."
    
    # Set AWS region if not already set
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            log_warning "AWS_REGION not set, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Look for .taskcat.yml in current directory
    if [ -f ".taskcat.yml" ]; then
        log "Found TaskCat configuration file in current directory"
        export TASKCAT_PROJECT_DIR="$(pwd)"
        
        # Extract project name from config if possible
        if command -v python3 &> /dev/null; then
            PROJECT_NAME=$(python3 -c "
import yaml
import sys
try:
    with open('.taskcat.yml', 'r') as f:
        config = yaml.safe_load(f)
    print(config.get('project', {}).get('name', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
            export PROJECT_NAME
        else
            export PROJECT_NAME="unknown"
        fi
    else
        log_warning "No .taskcat.yml found in current directory"
        export TASKCAT_PROJECT_DIR=""
        export PROJECT_NAME="unknown"
    fi
    
    log "Detection completed:"
    log "  AWS_REGION: $AWS_REGION"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  PROJECT_NAME: $PROJECT_NAME"
    log "  TASKCAT_PROJECT_DIR: ${TASKCAT_PROJECT_DIR:-'Not found'}"
}

# Function to find and list TaskCat stacks
find_taskcat_stacks() {
    log "Searching for TaskCat CloudFormation stacks..."
    
    local regions=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1" "ap-northeast-1")
    
    # If we found a project config, try to get regions from it
    if [ -f ".taskcat.yml" ] && command -v python3 &> /dev/null; then
        local config_regions=$(python3 -c "
import yaml
import sys
try:
    with open('.taskcat.yml', 'r') as f:
        config = yaml.safe_load(f)
    regions = config.get('project', {}).get('regions', [])
    if regions:
        print(' '.join(regions))
    else:
        print('')
except:
    print('')
" 2>/dev/null)
        
        if [ -n "$config_regions" ]; then
            regions=($config_regions)
            log "Using regions from TaskCat config: ${regions[*]}"
        fi
    fi
    
    export TASKCAT_STACKS=()
    
    for region in "${regions[@]}"; do
        log "Checking region: $region"
        
        # Search for stacks with TaskCat naming patterns
        local stacks=$(aws cloudformation list-stacks \
            --region "$region" \
            --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
            --query 'StackSummaries[?contains(StackName, `taskcat`) || contains(StackName, `tCaT`)].StackName' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$stacks" ] && [ "$stacks" != "None" ]; then
            for stack in $stacks; do
                TASKCAT_STACKS+=("$region:$stack")
                log "Found TaskCat stack: $stack in $region"
            done
        fi
    done
    
    if [ ${#TASKCAT_STACKS[@]} -eq 0 ]; then
        log "No TaskCat stacks found"
    else
        log_success "Found ${#TASKCAT_STACKS[@]} TaskCat stacks"
    fi
}

# Function to clean up TaskCat stacks using TaskCat command
cleanup_with_taskcat() {
    log "Attempting TaskCat-managed cleanup..."
    
    if [ "$TASKCAT_PROJECT_DIR" = "" ]; then
        log_warning "No TaskCat project directory found, skipping TaskCat cleanup"
        return 1
    fi
    
    if ! command -v taskcat &> /dev/null; then
        log_warning "TaskCat not available, skipping TaskCat cleanup"
        return 1
    fi
    
    cd "$TASKCAT_PROJECT_DIR"
    
    # Use TaskCat to clean up stacks
    execute_command "taskcat test clean --project-root ." "Cleaning up TaskCat test stacks"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Wait a moment for cleanup to start
        sleep 5
        
        # Verify cleanup
        local remaining_stacks=$(find_taskcat_stacks 2>/dev/null | wc -l || echo "0")
        if [ "$remaining_stacks" -eq 0 ]; then
            log_success "TaskCat cleanup completed successfully"
            return 0
        else
            log_warning "Some stacks may still exist after TaskCat cleanup"
            return 1
        fi
    fi
    
    return 0
}

# Function to manually delete CloudFormation stacks
manual_stack_cleanup() {
    log "Performing manual CloudFormation stack cleanup..."
    
    if [ ${#TASKCAT_STACKS[@]} -eq 0 ]; then
        log "No stacks to clean up manually"
        return 0
    fi
    
    for stack_info in "${TASKCAT_STACKS[@]}"; do
        local region=$(echo "$stack_info" | cut -d: -f1)
        local stack_name=$(echo "$stack_info" | cut -d: -f2)
        
        execute_command "aws cloudformation delete-stack --stack-name '$stack_name' --region '$region'" \
            "Deleting stack: $stack_name in $region"
    done
    
    if [ "$DRY_RUN" = "false" ]; then
        # Wait for stack deletions to complete
        log "Waiting for stack deletions to complete..."
        
        for stack_info in "${TASKCAT_STACKS[@]}"; do
            local region=$(echo "$stack_info" | cut -d: -f1)
            local stack_name=$(echo "$stack_info" | cut -d: -f2)
            
            log "Waiting for stack deletion: $stack_name in $region"
            
            # Wait with timeout
            local timeout=1800  # 30 minutes
            local elapsed=0
            local wait_interval=30
            
            while [ $elapsed -lt $timeout ]; do
                local status=$(aws cloudformation describe-stacks \
                    --stack-name "$stack_name" \
                    --region "$region" \
                    --query 'Stacks[0].StackStatus' \
                    --output text 2>/dev/null || echo "DELETE_COMPLETE")
                
                if [ "$status" = "DELETE_COMPLETE" ] || [ "$status" = "None" ]; then
                    log_success "Stack $stack_name deleted successfully"
                    break
                elif [ "$status" = "DELETE_FAILED" ]; then
                    log_warning "Stack $stack_name deletion failed"
                    break
                else
                    log "Stack $stack_name status: $status (waiting...)"
                    sleep $wait_interval
                    elapsed=$((elapsed + wait_interval))
                fi
            done
            
            if [ $elapsed -ge $timeout ]; then
                log_warning "Timeout waiting for stack $stack_name deletion"
            fi
        done
    fi
}

# Function to find and clean up S3 buckets
cleanup_s3_buckets() {
    log "Searching for TaskCat S3 buckets..."
    
    # Search for S3 buckets with TaskCat naming patterns
    local buckets=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `taskcat`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$buckets" ] && [ "$buckets" != "None" ]; then
        for bucket in $buckets; do
            log "Found TaskCat bucket: $bucket"
            
            confirm_action "This will delete S3 bucket '$bucket' and all its contents."
            
            # Empty bucket first
            execute_command "aws s3 rm s3://$bucket --recursive" \
                "Emptying S3 bucket: $bucket"
            
            # Delete bucket
            execute_command "aws s3 rb s3://$bucket" \
                "Deleting S3 bucket: $bucket"
        done
    else
        log "No TaskCat S3 buckets found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [ "$TASKCAT_PROJECT_DIR" != "" ] && [ -d "$TASKCAT_PROJECT_DIR" ]; then
        cd "$TASKCAT_PROJECT_DIR"
        
        # Clean up TaskCat output directories
        local cleanup_dirs=(
            "taskcat_outputs"
            "reports"
            ".taskcat"
            ".taskcat_outputs"
        )
        
        for dir in "${cleanup_dirs[@]}"; do
            if [ -d "$dir" ]; then
                execute_command "rm -rf '$dir'" "Removing directory: $dir"
            fi
        done
        
        # Clean up any generated artifacts
        if [ -f "taskcat_report.json" ]; then
            execute_command "rm -f taskcat_report.json" "Removing TaskCat report"
        fi
        
        # Ask about removing the entire project directory
        if [ "$FORCE_MODE" = "false" ]; then
            echo -e "${YELLOW}Do you want to remove the entire project directory?${NC}"
            echo -n "Directory: $TASKCAT_PROJECT_DIR (y/N): "
            read -r response
            
            case "$response" in
                [yY][eE][sS]|[yY])
                    if [ "$(basename "$TASKCAT_PROJECT_DIR")" != "." ]; then
                        execute_command "cd .. && rm -rf '$(basename "$TASKCAT_PROJECT_DIR")'" \
                            "Removing project directory"
                    else
                        log "Skipping removal of current directory"
                    fi
                    ;;
                *)
                    log "Keeping project directory"
                    ;;
            esac
        fi
    fi
    
    log_success "Local file cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Re-check for TaskCat stacks
    find_taskcat_stacks
    if [ ${#TASKCAT_STACKS[@]} -gt 0 ]; then
        log_warning "Found ${#TASKCAT_STACKS[@]} remaining TaskCat stacks"
        for stack_info in "${TASKCAT_STACKS[@]}"; do
            log "  - $stack_info"
        done
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Re-check for TaskCat S3 buckets
    local remaining_buckets=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `taskcat`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_buckets" ] && [ "$remaining_buckets" != "None" ]; then
        log_warning "Found remaining TaskCat S3 buckets: $remaining_buckets"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "Cleanup verification passed - no TaskCat resources found"
    else
        log_warning "Cleanup verification found $cleanup_issues issue(s)"
        log "You may need to manually clean up remaining resources"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    log "==============="
    log "AWS Region: $AWS_REGION"
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "Project Name: $PROJECT_NAME"
    
    if [ "$DRY_RUN" = "false" ]; then
        log ""
        log "Cleanup completed. If you encounter any issues:"
        log "1. Check AWS Console for remaining CloudFormation stacks"
        log "2. Check S3 Console for remaining buckets"
        log "3. Use AWS CLI to manually delete remaining resources"
        log ""
        log "Common manual cleanup commands:"
        log "  aws cloudformation delete-stack --stack-name STACK_NAME --region REGION"
        log "  aws s3 rm s3://BUCKET_NAME --recursive && aws s3 rb s3://BUCKET_NAME"
    fi
    
    log_success "TaskCat infrastructure cleanup script completed!"
}

# Main execution function
main() {
    log "Starting TaskCat Infrastructure Cleanup"
    log "======================================"
    
    # Check if help is requested
    if [[ "$*" == *"--help"* ]] || [[ "$*" == *"-h"* ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --dry-run          Run in dry-run mode (no resources destroyed)"
        echo "  --force            Skip confirmation prompts"
        echo ""
        echo "Environment Variables:"
        echo "  DRY_RUN            Set to 'true' for dry-run mode"
        echo "  FORCE_MODE         Set to 'true' to skip confirmations"
        echo "  AWS_REGION         AWS region to use (default: from AWS CLI config)"
        echo ""
        echo "This script will:"
        echo "1. Find and delete TaskCat CloudFormation stacks"
        echo "2. Find and delete TaskCat S3 buckets"
        echo "3. Clean up local TaskCat files and directories"
        echo ""
        exit 0
    fi
    
    # Parse command line arguments
    for arg in "$@"; do
        case $arg in
            --dry-run)
                DRY_RUN=true
                ;;
            --force)
                FORCE_MODE=true
                ;;
        esac
    done
    
    # Warning about destructive operations
    if [ "$DRY_RUN" = "false" ] && [ "$FORCE_MODE" = "false" ]; then
        echo -e "${RED}WARNING: This script will delete AWS resources and may incur charges!${NC}"
        echo -e "${RED}This includes CloudFormation stacks, S3 buckets, and their contents.${NC}"
        echo ""
        confirm_action "Do you want to proceed with TaskCat resource cleanup?"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    detect_taskcat_projects
    find_taskcat_stacks
    
    # Try TaskCat-managed cleanup first, fall back to manual if needed
    if ! cleanup_with_taskcat; then
        manual_stack_cleanup
    fi
    
    cleanup_s3_buckets
    cleanup_local_files
    verify_cleanup
    display_summary
}

# Trap errors and provide helpful message
trap 'log_error "Cleanup failed on line $LINENO. Some resources may remain. Check AWS Console manually."' ERR

# Run main function
main "$@"