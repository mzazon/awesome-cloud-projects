#!/bin/bash

# Full-Stack Real-Time Applications with Amplify and AppSync - Destroy Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if script is run with dry-run flag
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE=true
            log "Force mode enabled - skipping confirmation prompts"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DESTRUCTION_LOG="${PROJECT_ROOT}/destruction.log"

# Function to confirm destructive actions
confirm_action() {
    local action="$1"
    
    if [ "$FORCE" = true ]; then
        log "Force mode: Proceeding with $action"
        return 0
    fi
    
    warning "This will $action"
    echo -n "Are you sure you want to continue? (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log "Operation cancelled by user"
            return 1
            ;;
    esac
}

# Find Amplify projects
find_amplify_projects() {
    log "Searching for Amplify projects..."
    
    # Look for Amplify projects in common locations
    AMPLIFY_PROJECTS=()
    
    # Check home directory
    if [ -d "${HOME}/amplify-projects" ]; then
        while IFS= read -r -d '' project; do
            if [ -d "$project/amplify" ]; then
                AMPLIFY_PROJECTS+=("$project")
            fi
        done < <(find "${HOME}/amplify-projects" -maxdepth 2 -name "*realtime*" -type d -print0 2>/dev/null)
    fi
    
    # Check current directory and parent directories
    local current_dir="$(pwd)"
    while [ "$current_dir" != "/" ]; do
        if [ -d "$current_dir/amplify" ] && [ -f "$current_dir/amplify/.config/project-config.json" ]; then
            AMPLIFY_PROJECTS+=("$current_dir")
            break
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    # Check if we found any projects
    if [ ${#AMPLIFY_PROJECTS[@]} -eq 0 ]; then
        warning "No Amplify projects found"
        return 1
    fi
    
    log "Found ${#AMPLIFY_PROJECTS[@]} Amplify project(s):"
    for project in "${AMPLIFY_PROJECTS[@]}"; do
        log "  - $project"
    done
    
    return 0
}

# Get project info from Amplify
get_project_info() {
    local project_dir="$1"
    
    log "Getting project information from: $project_dir"
    
    if [ ! -d "$project_dir/amplify" ]; then
        warning "No Amplify configuration found in $project_dir"
        return 1
    fi
    
    cd "$project_dir"
    
    # Get project name and region from Amplify config
    if [ -f "amplify/.config/project-config.json" ]; then
        PROJECT_NAME=$(jq -r '.projectName' amplify/.config/project-config.json 2>/dev/null || echo "")
        PROJECT_ENV=$(jq -r '.defaultEditor' amplify/.config/project-config.json 2>/dev/null || echo "")
    fi
    
    # Get region from local environment
    if [ -f "amplify/.config/local-env-info.json" ]; then
        AWS_REGION=$(jq -r '.envName' amplify/.config/local-env-info.json 2>/dev/null || echo "")
    fi
    
    # Fallback to AWS CLI configuration
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    fi
    
    log "Project info:"
    log "  Name: ${PROJECT_NAME:-'Unknown'}"
    log "  Region: ${AWS_REGION:-'Unknown'}"
    log "  Directory: $project_dir"
    
    export PROJECT_NAME AWS_REGION PROJECT_DIR="$project_dir"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi
    
    # Check Amplify CLI
    if ! command -v amplify &> /dev/null; then
        error "Amplify CLI is not installed"
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed - some features may be limited"
    fi
    
    success "Prerequisites check completed"
}

# List Amplify resources
list_amplify_resources() {
    log "Listing Amplify resources..."
    
    if [ "$DRY_RUN" = false ]; then
        cd "$PROJECT_DIR"
        
        # Get Amplify status
        if amplify status &> /dev/null; then
            log "Current Amplify resources:"
            amplify status
        else
            warning "Could not retrieve Amplify status"
        fi
        
        # List AppSync APIs
        if aws appsync list-graphql-apis --region "$AWS_REGION" &> /dev/null; then
            log "AppSync APIs in region $AWS_REGION:"
            aws appsync list-graphql-apis --region "$AWS_REGION" \
                --query 'graphqlApis[].{Name:name,ApiId:apiId,Status:status}' \
                --output table
        fi
        
        # List DynamoDB tables
        if aws dynamodb list-tables --region "$AWS_REGION" &> /dev/null; then
            log "DynamoDB tables in region $AWS_REGION:"
            aws dynamodb list-tables --region "$AWS_REGION" \
                --query 'TableNames[?contains(@, `realtime`) || contains(@, `chat`) || contains(@, `message`)]' \
                --output table
        fi
        
        # List Cognito User Pools
        if aws cognito-idp list-user-pools --max-results 60 --region "$AWS_REGION" &> /dev/null; then
            log "Cognito User Pools in region $AWS_REGION:"
            aws cognito-idp list-user-pools --max-results 60 --region "$AWS_REGION" \
                --query 'UserPools[?contains(Name, `realtime`) || contains(Name, `chat`)].{Name:Name,Id:Id,Status:Status}' \
                --output table
        fi
        
        # List Lambda functions
        if aws lambda list-functions --region "$AWS_REGION" &> /dev/null; then
            log "Lambda functions in region $AWS_REGION:"
            aws lambda list-functions --region "$AWS_REGION" \
                --query 'Functions[?contains(FunctionName, `realtime`) || contains(FunctionName, `chat`)].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' \
                --output table
        fi
        
        # List S3 buckets (for Amplify deployments)
        if aws s3api list-buckets --region "$AWS_REGION" &> /dev/null; then
            log "S3 buckets related to Amplify:"
            aws s3api list-buckets --region "$AWS_REGION" \
                --query 'Buckets[?contains(Name, `amplify`) || contains(Name, `realtime`)].{Name:Name,CreationDate:CreationDate}' \
                --output table
        fi
        
    else
        log "Would list all Amplify resources in project: $PROJECT_NAME"
    fi
    
    success "Resource listing completed"
}

# Delete Amplify backend resources
delete_amplify_backend() {
    log "Deleting Amplify backend resources..."
    
    if ! confirm_action "permanently delete all Amplify backend resources"; then
        return 1
    fi
    
    if [ "$DRY_RUN" = false ]; then
        cd "$PROJECT_DIR"
        
        # Check if Amplify project exists
        if [ ! -d "amplify" ]; then
            warning "No Amplify project found in $PROJECT_DIR"
            return 1
        fi
        
        log "Deleting Amplify project: $PROJECT_NAME"
        log "This operation may take 10-15 minutes..."
        
        # Delete all backend resources
        if amplify delete --yes --force; then
            success "Amplify backend resources deleted successfully"
        else
            error "Failed to delete Amplify backend resources"
        fi
        
        # Clean up local Amplify files
        if [ -d "amplify" ]; then
            log "Cleaning up local Amplify configuration..."
            rm -rf amplify/
            log "Local Amplify configuration removed"
        fi
        
        # Clean up aws-exports.js if it exists
        if [ -f "src/aws-exports.js" ]; then
            rm -f src/aws-exports.js
            log "AWS exports file removed"
        fi
        
    else
        log "Would delete Amplify backend resources:"
        log "  - AppSync GraphQL API with real-time subscriptions"
        log "  - Cognito User Pool and Identity Pool"
        log "  - DynamoDB tables and indexes"
        log "  - Lambda functions"
        log "  - S3 buckets"
        log "  - IAM roles and policies"
        log "  - CloudWatch log groups"
    fi
    
    success "Backend resource deletion completed"
}

# Clean up specific AWS resources (fallback)
cleanup_aws_resources() {
    log "Cleaning up remaining AWS resources..."
    
    if ! confirm_action "manually clean up remaining AWS resources"; then
        return 1
    fi
    
    if [ "$DRY_RUN" = false ]; then
        
        # Clean up AppSync APIs
        log "Cleaning up AppSync APIs..."
        API_IDS=$(aws appsync list-graphql-apis --region "$AWS_REGION" \
            --query 'graphqlApis[?contains(name, `realtime`) || contains(name, `chat`)].apiId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$API_IDS" ]; then
            for api_id in $API_IDS; do
                log "Deleting AppSync API: $api_id"
                aws appsync delete-graphql-api --api-id "$api_id" --region "$AWS_REGION" || warning "Failed to delete AppSync API: $api_id"
            done
        fi
        
        # Clean up DynamoDB tables
        log "Cleaning up DynamoDB tables..."
        TABLE_NAMES=$(aws dynamodb list-tables --region "$AWS_REGION" \
            --query 'TableNames[?contains(@, `realtime`) || contains(@, `chat`) || contains(@, `message`)]' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$TABLE_NAMES" ]; then
            for table_name in $TABLE_NAMES; do
                log "Deleting DynamoDB table: $table_name"
                aws dynamodb delete-table --table-name "$table_name" --region "$AWS_REGION" || warning "Failed to delete DynamoDB table: $table_name"
            done
        fi
        
        # Clean up Cognito User Pools
        log "Cleaning up Cognito User Pools..."
        USER_POOL_IDS=$(aws cognito-idp list-user-pools --max-results 60 --region "$AWS_REGION" \
            --query 'UserPools[?contains(Name, `realtime`) || contains(Name, `chat`)].Id' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$USER_POOL_IDS" ]; then
            for pool_id in $USER_POOL_IDS; do
                log "Deleting Cognito User Pool: $pool_id"
                aws cognito-idp delete-user-pool --user-pool-id "$pool_id" --region "$AWS_REGION" || warning "Failed to delete User Pool: $pool_id"
            done
        fi
        
        # Clean up Lambda functions
        log "Cleaning up Lambda functions..."
        FUNCTION_NAMES=$(aws lambda list-functions --region "$AWS_REGION" \
            --query 'Functions[?contains(FunctionName, `realtime`) || contains(FunctionName, `chat`)].FunctionName' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$FUNCTION_NAMES" ]; then
            for function_name in $FUNCTION_NAMES; do
                log "Deleting Lambda function: $function_name"
                aws lambda delete-function --function-name "$function_name" --region "$AWS_REGION" || warning "Failed to delete Lambda function: $function_name"
            done
        fi
        
        # Clean up S3 buckets
        log "Cleaning up S3 buckets..."
        BUCKET_NAMES=$(aws s3api list-buckets --region "$AWS_REGION" \
            --query 'Buckets[?contains(Name, `amplify`) || contains(Name, `realtime`)].Name' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$BUCKET_NAMES" ]; then
            for bucket_name in $BUCKET_NAMES; do
                log "Emptying and deleting S3 bucket: $bucket_name"
                aws s3 rm "s3://$bucket_name" --recursive --region "$AWS_REGION" || warning "Failed to empty S3 bucket: $bucket_name"
                aws s3api delete-bucket --bucket "$bucket_name" --region "$AWS_REGION" || warning "Failed to delete S3 bucket: $bucket_name"
            done
        fi
        
    else
        log "Would clean up remaining AWS resources:"
        log "  - AppSync APIs"
        log "  - DynamoDB tables"
        log "  - Cognito User Pools"
        log "  - Lambda functions"
        log "  - S3 buckets"
    fi
    
    success "AWS resource cleanup completed"
}

# Clean up local project files
cleanup_local_files() {
    log "Cleaning up local project files..."
    
    if [ ${#AMPLIFY_PROJECTS[@]} -eq 0 ]; then
        warning "No local projects found to clean up"
        return 0
    fi
    
    for project_dir in "${AMPLIFY_PROJECTS[@]}"; do
        if [ -d "$project_dir" ]; then
            log "Found project directory: $project_dir"
            
            if confirm_action "delete local project directory: $project_dir"; then
                if [ "$DRY_RUN" = false ]; then
                    rm -rf "$project_dir"
                    success "Deleted project directory: $project_dir"
                else
                    log "Would delete project directory: $project_dir"
                fi
            else
                log "Skipping deletion of: $project_dir"
            fi
        fi
    done
    
    success "Local file cleanup completed"
}

# Clean up environment variables
cleanup_environment() {
    log "Cleaning up environment variables..."
    
    if [ "$DRY_RUN" = false ]; then
        unset PROJECT_NAME
        unset APP_NAME
        unset AWS_REGION
        unset PROJECT_DIR
        unset RANDOM_SUFFIX
        unset API_ID
        unset TABLE_NAME
        
        log "Environment variables cleaned up"
    else
        log "Would clean up environment variables"
    fi
    
    success "Environment cleanup completed"
}

# Verify complete cleanup
verify_cleanup() {
    log "Verifying complete resource cleanup..."
    
    if [ "$DRY_RUN" = false ]; then
        local remaining_resources=false
        
        # Check for remaining AppSync APIs
        if aws appsync list-graphql-apis --region "$AWS_REGION" \
            --query 'graphqlApis[?contains(name, `realtime`) || contains(name, `chat`)]' \
            --output text 2>/dev/null | grep -q .; then
            warning "Found remaining AppSync APIs"
            remaining_resources=true
        fi
        
        # Check for remaining DynamoDB tables
        if aws dynamodb list-tables --region "$AWS_REGION" \
            --query 'TableNames[?contains(@, `realtime`) || contains(@, `chat`) || contains(@, `message`)]' \
            --output text 2>/dev/null | grep -q .; then
            warning "Found remaining DynamoDB tables"
            remaining_resources=true
        fi
        
        # Check for remaining Lambda functions
        if aws lambda list-functions --region "$AWS_REGION" \
            --query 'Functions[?contains(FunctionName, `realtime`) || contains(FunctionName, `chat`)]' \
            --output text 2>/dev/null | grep -q .; then
            warning "Found remaining Lambda functions"
            remaining_resources=true
        fi
        
        if [ "$remaining_resources" = true ]; then
            warning "Some resources may still exist. Please check the AWS console."
        else
            success "No remaining resources found"
        fi
        
    else
        log "Would verify complete cleanup of all resources"
    fi
    
    success "Cleanup verification completed"
}

# Main destruction function
destroy_application() {
    log "Starting destruction of Full-Stack Real-Time Application..."
    
    # Create destruction log
    if [ "$DRY_RUN" = false ]; then
        echo "Destruction started at $(date)" > "$DESTRUCTION_LOG"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Find and process Amplify projects
    if find_amplify_projects; then
        for project_dir in "${AMPLIFY_PROJECTS[@]}"; do
            log "Processing project: $project_dir"
            
            # Get project information
            get_project_info "$project_dir"
            
            # List resources before deletion
            list_amplify_resources
            
            # Delete Amplify backend
            delete_amplify_backend
            
            # Clean up any remaining AWS resources
            cleanup_aws_resources
            
            # Wait for resources to be fully deleted
            if [ "$DRY_RUN" = false ]; then
                log "Waiting for resources to be fully deleted..."
                sleep 30
            fi
            
            # Verify cleanup
            verify_cleanup
        done
        
        # Clean up local files
        cleanup_local_files
    else
        warning "No Amplify projects found. Attempting manual cleanup..."
        
        # Set default values for manual cleanup
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export PROJECT_NAME="manual-cleanup"
        
        # Try to clean up resources manually
        cleanup_aws_resources
        verify_cleanup
    fi
    
    # Clean up environment
    cleanup_environment
    
    if [ "$DRY_RUN" = false ]; then
        echo "Destruction completed at $(date)" >> "$DESTRUCTION_LOG"
        
        log "Destruction completed successfully!"
        log "Destruction log: $DESTRUCTION_LOG"
        log ""
        log "All resources have been removed."
        log "Please verify in the AWS console that no unexpected charges remain."
    else
        log "Dry-run completed successfully!"
        log "No resources were deleted."
        log "Run without --dry-run to actually delete resources."
    fi
    
    success "Full-Stack Real-Time Application destruction script completed"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --force      Skip confirmation prompts"
    echo "  --help       Show this help message"
    echo ""
    echo "This script will:"
    echo "  1. Find all Amplify projects related to real-time applications"
    echo "  2. Delete all Amplify backend resources"
    echo "  3. Clean up remaining AWS resources"
    echo "  4. Remove local project files"
    echo "  5. Verify complete cleanup"
    echo ""
    echo "WARNING: This is a destructive operation and cannot be undone!"
}

# Handle help option
if [[ "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Final confirmation
if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete:"
    echo "  • All Amplify backend resources"
    echo "  • AppSync GraphQL APIs"
    echo "  • DynamoDB tables and data"
    echo "  • Cognito User Pools and users"
    echo "  • Lambda functions"
    echo "  • S3 buckets and content"
    echo "  • IAM roles and policies"
    echo "  • Local project files"
    echo ""
    echo "This operation cannot be undone!"
    echo ""
    echo -n "Type 'DELETE' to confirm complete destruction: "
    read -r confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Destruction cancelled by user"
        exit 1
    fi
fi

# Trap errors and provide helpful messages
trap 'error "Destruction failed. Some resources may still exist. Please check the AWS console."' ERR

# Run the destruction
destroy_application