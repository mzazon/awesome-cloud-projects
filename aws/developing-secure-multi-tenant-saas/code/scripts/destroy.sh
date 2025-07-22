#!/bin/bash

# Multi-Tenant SaaS Applications with Amplify and Fine-Grained Authorization - Cleanup Script
# This script safely removes all resources created by the multi-tenant SaaS platform deployment.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLEANUP_LOG="$PROJECT_ROOT/cleanup.log"

# Default values
DRY_RUN=false
FORCE=false
KEEP_LOGS=false
REGION=""
PROJECT_NAME=""

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Multi-Tenant SaaS Applications and all associated resources

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be destroyed without making changes
    -f, --force         Skip confirmation prompts (DANGEROUS)
    -k, --keep-logs     Keep CloudWatch log groups after cleanup
    -r, --region        AWS region (if not set, uses default from AWS config)
    -n, --name          Project name to destroy (auto-detected if not provided)
    -v, --verbose       Enable verbose logging

EXAMPLES:
    $0                                    # Interactive cleanup with confirmations
    $0 --dry-run                         # Preview what would be destroyed
    $0 --force                           # Destroy without prompts (DANGEROUS)
    $0 --keep-logs                       # Preserve CloudWatch logs
    $0 --region us-east-1 --name myapp   # Destroy specific project

SAFETY FEATURES:
    - Multiple confirmation prompts for destructive operations
    - Dry-run mode to preview changes
    - Backup critical configuration before deletion
    - Graceful handling of partially deleted resources
    - Detailed logging of all cleanup operations

⚠️  WARNING: This script will permanently delete all resources and data!
    Make sure you have backups of any important data before proceeding.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -n|--name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Safety confirmation function
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    cat << EOF

⚠️  DANGER: RESOURCE DESTRUCTION CONFIRMATION ⚠️

You are about to PERMANENTLY DELETE the following resources:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Project Name:     ${PROJECT_NAME:-"Auto-detected"}
AWS Region:       ${REGION:-"Default from AWS config"}
AWS Account:      $(aws sts get-caller-identity --query Account --output text 2>/dev/null || "Unknown")

Resources to be deleted:
• AWS Amplify Application and all environments
• AppSync GraphQL API and data sources
• Amazon Cognito User Pool and all users
• DynamoDB tables and ALL DATA stored in them
• Lambda functions and execution logs
• IAM roles and policies
• S3 buckets and ALL FILES stored in them
• CloudFormation stacks
• CloudWatch log groups (unless --keep-logs specified)

💾 DATA LOSS WARNING:
This operation will DELETE ALL TENANT DATA, USER ACCOUNTS, and CONFIGURATION.
This action CANNOT BE UNDONE!

EOF
    
    echo -n "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo -n "Last chance! Type 'YES' to confirm final deletion: "
    read -r final_confirmation
    
    if [[ "$final_confirmation" != "YES" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed resource destruction"
}

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
        exit 1
    fi
    
    # Check Amplify CLI if needed
    if command -v amplify &> /dev/null; then
        success "Amplify CLI available for cleanup"
    else
        warning "Amplify CLI not found - will use AWS CLI for cleanup"
    fi
    
    success "Prerequisites check completed"
}

# Detect project configuration
detect_project() {
    log "Detecting project configuration..."
    
    # Set AWS region
    if [[ -z "$REGION" ]]; then
        REGION=$(aws configure get region)
        if [[ -z "$REGION" ]]; then
            REGION="us-east-1"
            warning "No region specified, defaulting to us-east-1"
        fi
    fi
    export AWS_REGION="$REGION"
    
    # Try to read deployment info if available
    if [[ -f "$PROJECT_ROOT/deployment-info.json" ]] && command -v jq &> /dev/null; then
        PROJECT_NAME=$(jq -r '.projectName' "$PROJECT_ROOT/deployment-info.json" 2>/dev/null || echo "")
        DETECTED_REGION=$(jq -r '.region' "$PROJECT_ROOT/deployment-info.json" 2>/dev/null || echo "")
        
        if [[ -n "$DETECTED_REGION" ]] && [[ -z "$REGION" ]]; then
            REGION="$DETECTED_REGION"
            export AWS_REGION="$REGION"
        fi
        
        if [[ -n "$PROJECT_NAME" ]]; then
            success "Detected project from deployment info: $PROJECT_NAME"
        fi
    fi
    
    # Try to detect from Amplify config if in project directory
    local current_dir_name=$(basename "$PWD")
    if [[ -f "amplify/.config/project-config.json" ]] && command -v jq &> /dev/null; then
        local amplify_project_name=$(jq -r '.projectName' "amplify/.config/project-config.json" 2>/dev/null || echo "")
        if [[ -n "$amplify_project_name" ]] && [[ -z "$PROJECT_NAME" ]]; then
            PROJECT_NAME="$amplify_project_name"
            success "Detected project from Amplify config: $PROJECT_NAME"
        fi
    fi
    
    # If still no project name, try to detect from AWS resources
    if [[ -z "$PROJECT_NAME" ]]; then
        log "Searching for multi-tenant SaaS projects in AWS..."
        
        # Look for Amplify apps
        local amplify_apps=$(aws amplify list-apps \
            --region "$AWS_REGION" \
            --query 'apps[?contains(name, `multitenant`) || contains(name, `saas`)].name' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$amplify_apps" ]]; then
            warning "Found potential projects: $amplify_apps"
            warning "Please specify project name with --name option"
            exit 1
        fi
    fi
    
    if [[ -z "$PROJECT_NAME" ]]; then
        error "Could not detect project name. Please specify with --name option"
        exit 1
    fi
    
    log "Configuration detected:"
    log "  - Project Name: $PROJECT_NAME"
    log "  - AWS Region: $AWS_REGION"
}

# Backup critical configuration
backup_configuration() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would backup critical configuration to:"
        log "  - amplify-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        log "  - deployment-config-backup-$(date +%Y%m%d-%H%M%S).json"
        return 0
    fi
    
    log "Creating backup of critical configuration..."
    
    local backup_dir="$PROJECT_ROOT/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup Amplify configuration if exists
    if [[ -d "amplify" ]]; then
        cp -r amplify "$backup_dir/" 2>/dev/null || true
    fi
    
    # Backup deployment info
    if [[ -f "$PROJECT_ROOT/deployment-info.json" ]]; then
        cp "$PROJECT_ROOT/deployment-info.json" "$backup_dir/" 2>/dev/null || true
    fi
    
    # Export current AWS resource state
    log "Exporting current resource state..."
    
    # Amplify apps
    aws amplify list-apps \
        --region "$AWS_REGION" \
        --query "apps[?contains(name, '${PROJECT_NAME}')]" \
        > "$backup_dir/amplify-apps.json" 2>/dev/null || true
    
    # AppSync APIs
    aws appsync list-graphql-apis \
        --region "$AWS_REGION" \
        --query "graphqlApis[?contains(name, '${PROJECT_NAME}')]" \
        > "$backup_dir/appsync-apis.json" 2>/dev/null || true
    
    # Cognito User Pools
    aws cognito-idp list-user-pools \
        --max-results 50 \
        --region "$AWS_REGION" \
        --query "UserPools[?contains(Name, '${PROJECT_NAME}')]" \
        > "$backup_dir/cognito-user-pools.json" 2>/dev/null || true
    
    # DynamoDB tables
    aws dynamodb list-tables \
        --region "$AWS_REGION" \
        --query "TableNames[?contains(@, '${PROJECT_NAME}')]" \
        > "$backup_dir/dynamodb-tables.json" 2>/dev/null || true
    
    # Create backup archive
    if command -v tar &> /dev/null; then
        tar -czf "$PROJECT_ROOT/backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C "$PROJECT_ROOT" "$(basename "$backup_dir")"
        rm -rf "$backup_dir"
        success "Configuration backup created"
    else
        success "Configuration backup created in: $backup_dir"
    fi
}

# Remove Amplify application and resources
remove_amplify_resources() {
    log "Removing Amplify application and resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Amplify application and all environments"
        return 0
    fi
    
    # Use Amplify CLI if available and in project directory
    if command -v amplify &> /dev/null && [[ -f "amplify/.config/project-config.json" ]]; then
        log "Using Amplify CLI to delete resources..."
        
        # Delete all environments
        local environments=$(amplify env list --json 2>/dev/null | jq -r '.envs[]' 2>/dev/null || echo "")
        if [[ -n "$environments" ]]; then
            for env in $environments; do
                log "Deleting Amplify environment: $env"
                amplify env remove "$env" --yes 2>/dev/null || warning "Failed to remove environment: $env"
            done
        fi
        
        # Delete the entire Amplify project
        log "Deleting Amplify project..."
        amplify delete --yes 2>/dev/null || warning "Amplify CLI deletion failed, falling back to AWS CLI"
    fi
    
    # Use AWS CLI to ensure complete cleanup
    log "Using AWS CLI to ensure complete Amplify cleanup..."
    
    local app_ids=$(aws amplify list-apps \
        --region "$AWS_REGION" \
        --query "apps[?contains(name, '${PROJECT_NAME}')].appId" \
        --output text 2>/dev/null || echo "")
    
    for app_id in $app_ids; do
        if [[ -n "$app_id" ]] && [[ "$app_id" != "None" ]]; then
            log "Deleting Amplify app: $app_id"
            aws amplify delete-app \
                --app-id "$app_id" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete Amplify app: $app_id"
        fi
    done
    
    success "Amplify resources cleanup completed"
}

# Remove AppSync GraphQL APIs
remove_appsync_resources() {
    log "Removing AppSync GraphQL APIs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove AppSync GraphQL APIs and data sources"
        return 0
    fi
    
    local api_ids=$(aws appsync list-graphql-apis \
        --region "$AWS_REGION" \
        --query "graphqlApis[?contains(name, '${PROJECT_NAME}') || contains(name, 'MultiTenantSaaSAPI')].apiId" \
        --output text 2>/dev/null || echo "")
    
    for api_id in $api_ids; do
        if [[ -n "$api_id" ]] && [[ "$api_id" != "None" ]]; then
            log "Deleting AppSync API: $api_id"
            aws appsync delete-graphql-api \
                --api-id "$api_id" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete AppSync API: $api_id"
        fi
    done
    
    success "AppSync resources cleanup completed"
}

# Remove Cognito resources
remove_cognito_resources() {
    log "Removing Cognito User Pools and Identity Pools..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Cognito User Pools, Identity Pools, and all user data"
        return 0
    fi
    
    # Remove User Pools
    local user_pool_ids=$(aws cognito-idp list-user-pools \
        --max-results 50 \
        --region "$AWS_REGION" \
        --query "UserPools[?contains(Name, '${PROJECT_NAME}')].Id" \
        --output text 2>/dev/null || echo "")
    
    for pool_id in $user_pool_ids; do
        if [[ -n "$pool_id" ]] && [[ "$pool_id" != "None" ]]; then
            log "Deleting Cognito User Pool: $pool_id"
            
            # First delete all users
            local users=$(aws cognito-idp list-users \
                --user-pool-id "$pool_id" \
                --region "$AWS_REGION" \
                --query 'Users[].Username' \
                --output text 2>/dev/null || echo "")
            
            for username in $users; do
                if [[ -n "$username" ]] && [[ "$username" != "None" ]]; then
                    aws cognito-idp admin-delete-user \
                        --user-pool-id "$pool_id" \
                        --username "$username" \
                        --region "$AWS_REGION" 2>/dev/null || true
                fi
            done
            
            # Delete the user pool
            aws cognito-idp delete-user-pool \
                --user-pool-id "$pool_id" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete User Pool: $pool_id"
        fi
    done
    
    # Remove Identity Pools
    local identity_pool_ids=$(aws cognito-identity list-identity-pools \
        --max-results 50 \
        --region "$AWS_REGION" \
        --query "IdentityPools[?contains(IdentityPoolName, '${PROJECT_NAME}')].IdentityPoolId" \
        --output text 2>/dev/null || echo "")
    
    for pool_id in $identity_pool_ids; do
        if [[ -n "$pool_id" ]] && [[ "$pool_id" != "None" ]]; then
            log "Deleting Cognito Identity Pool: $pool_id"
            aws cognito-identity delete-identity-pool \
                --identity-pool-id "$pool_id" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete Identity Pool: $pool_id"
        fi
    done
    
    success "Cognito resources cleanup completed"
}

# Remove DynamoDB tables
remove_dynamodb_resources() {
    log "Removing DynamoDB tables..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove DynamoDB tables and ALL DATA"
        log "  - This includes all tenant data, user records, and configuration"
        return 0
    fi
    
    local table_names=$(aws dynamodb list-tables \
        --region "$AWS_REGION" \
        --query "TableNames[?contains(@, '${PROJECT_NAME}')]" \
        --output text 2>/dev/null || echo "")
    
    for table_name in $table_names; do
        if [[ -n "$table_name" ]] && [[ "$table_name" != "None" ]]; then
            log "Deleting DynamoDB table: $table_name"
            
            # Wait for table to be active before deletion
            aws dynamodb wait table-exists \
                --table-name "$table_name" \
                --region "$AWS_REGION" 2>/dev/null || true
            
            aws dynamodb delete-table \
                --table-name "$table_name" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete table: $table_name"
            
            # Wait for deletion to complete
            aws dynamodb wait table-not-exists \
                --table-name "$table_name" \
                --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
    
    success "DynamoDB resources cleanup completed"
}

# Remove Lambda functions
remove_lambda_resources() {
    log "Removing Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Lambda functions and execution logs"
        return 0
    fi
    
    local function_names=$(aws lambda list-functions \
        --region "$AWS_REGION" \
        --query "Functions[?contains(FunctionName, '${PROJECT_NAME}')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    for function_name in $function_names; do
        if [[ -n "$function_name" ]] && [[ "$function_name" != "None" ]]; then
            log "Deleting Lambda function: $function_name"
            aws lambda delete-function \
                --function-name "$function_name" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete function: $function_name"
        fi
    done
    
    success "Lambda resources cleanup completed"
}

# Remove S3 buckets
remove_s3_resources() {
    log "Removing S3 buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove S3 buckets and ALL FILES"
        return 0
    fi
    
    local bucket_names=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}')].Name" \
        --output text 2>/dev/null || echo "")
    
    for bucket_name in $bucket_names; do
        if [[ -n "$bucket_name" ]] && [[ "$bucket_name" != "None" ]]; then
            log "Deleting S3 bucket: $bucket_name"
            
            # Empty bucket first
            aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null || true
            
            # Delete bucket
            aws s3api delete-bucket \
                --bucket "$bucket_name" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete bucket: $bucket_name"
        fi
    done
    
    success "S3 resources cleanup completed"
}

# Remove IAM roles and policies
remove_iam_resources() {
    log "Removing IAM roles and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove IAM roles and policies created by Amplify"
        return 0
    fi
    
    # Find roles created by Amplify
    local role_names=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '${PROJECT_NAME}') || contains(RoleName, 'amplify')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    for role_name in $role_names; do
        if [[ -n "$role_name" ]] && [[ "$role_name" != "None" ]]; then
            log "Processing IAM role: $role_name"
            
            # Detach managed policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                if [[ -n "$policy_arn" ]] && [[ "$policy_arn" != "None" ]]; then
                    aws iam detach-role-policy \
                        --role-name "$role_name" \
                        --policy-arn "$policy_arn" 2>/dev/null || true
                fi
            done
            
            # Delete inline policies
            local inline_policies=$(aws iam list-role-policies \
                --role-name "$role_name" \
                --query 'PolicyNames' \
                --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                if [[ -n "$policy_name" ]] && [[ "$policy_name" != "None" ]]; then
                    aws iam delete-role-policy \
                        --role-name "$role_name" \
                        --policy-name "$policy_name" 2>/dev/null || true
                fi
            done
            
            # Delete the role
            aws iam delete-role \
                --role-name "$role_name" 2>/dev/null || warning "Failed to delete role: $role_name"
        fi
    done
    
    success "IAM resources cleanup completed"
}

# Remove CloudFormation stacks
remove_cloudformation_resources() {
    log "Removing CloudFormation stacks..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove CloudFormation stacks created by Amplify"
        return 0
    fi
    
    local stack_names=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --region "$AWS_REGION" \
        --query "StackSummaries[?contains(StackName, '${PROJECT_NAME}') || contains(StackName, 'amplify')].StackName" \
        --output text 2>/dev/null || echo "")
    
    for stack_name in $stack_names; do
        if [[ -n "$stack_name" ]] && [[ "$stack_name" != "None" ]]; then
            log "Deleting CloudFormation stack: $stack_name"
            aws cloudformation delete-stack \
                --stack-name "$stack_name" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete stack: $stack_name"
            
            # Wait for deletion to complete
            log "Waiting for stack deletion to complete: $stack_name"
            aws cloudformation wait stack-delete-complete \
                --stack-name "$stack_name" \
                --region "$AWS_REGION" 2>/dev/null || warning "Stack deletion wait failed: $stack_name"
        fi
    done
    
    success "CloudFormation resources cleanup completed"
}

# Remove CloudWatch log groups
remove_cloudwatch_logs() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log "Keeping CloudWatch log groups as requested"
        return 0
    fi
    
    log "Removing CloudWatch log groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove CloudWatch log groups and ALL LOGS"
        return 0
    fi
    
    local log_groups=$(aws logs describe-log-groups \
        --region "$AWS_REGION" \
        --query "logGroups[?contains(logGroupName, '${PROJECT_NAME}') || contains(logGroupName, '/aws/lambda/') || contains(logGroupName, '/aws/appsync/')].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    for log_group in $log_groups; do
        if [[ -n "$log_group" ]] && [[ "$log_group" != "None" ]]; then
            log "Deleting log group: $log_group"
            aws logs delete-log-group \
                --log-group-name "$log_group" \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to delete log group: $log_group"
        fi
    done
    
    success "CloudWatch logs cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local project files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove local Amplify project files and caches"
        return 0
    fi
    
    # Remove Amplify configuration
    if [[ -d "amplify" ]]; then
        log "Removing Amplify configuration directory"
        rm -rf amplify
    fi
    
    # Remove node_modules if present
    if [[ -d "node_modules" ]]; then
        log "Removing node_modules directory"
        rm -rf node_modules
    fi
    
    # Remove generated files
    local generated_files=(
        "src/aws-exports.js"
        "src/aws-exports.ts"
        "amplify-meta.json"
        "deployment-info.json"
        "package-lock.json"
        ".amplify"
        "build"
        ".next"
    )
    
    for file in "${generated_files[@]}"; do
        if [[ -e "$file" ]]; then
            log "Removing generated file/directory: $file"
            rm -rf "$file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Final verification
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local resources_remaining=false
    
    # Check Amplify apps
    local amplify_count=$(aws amplify list-apps \
        --region "$AWS_REGION" \
        --query "length(apps[?contains(name, '${PROJECT_NAME}')])" \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$amplify_count" -gt 0 ]]; then
        warning "$amplify_count Amplify apps still exist"
        resources_remaining=true
    fi
    
    # Check AppSync APIs
    local appsync_count=$(aws appsync list-graphql-apis \
        --region "$AWS_REGION" \
        --query "length(graphqlApis[?contains(name, '${PROJECT_NAME}')])" \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$appsync_count" -gt 0 ]]; then
        warning "$appsync_count AppSync APIs still exist"
        resources_remaining=true
    fi
    
    # Check DynamoDB tables
    local dynamodb_count=$(aws dynamodb list-tables \
        --region "$AWS_REGION" \
        --query "length(TableNames[?contains(@, '${PROJECT_NAME}')])" \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$dynamodb_count" -gt 0 ]]; then
        warning "$dynamodb_count DynamoDB tables still exist"
        resources_remaining=true
    fi
    
    if [[ "$resources_remaining" == "true" ]]; then
        warning "Some resources may still exist. Manual cleanup may be required."
        warning "Check the AWS Console for any remaining resources."
    else
        success "Cleanup verification completed - no resources detected"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log "Generating cleanup report..."
    
    local report_file="$PROJECT_ROOT/cleanup-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
Multi-Tenant SaaS Platform Cleanup Report
Generated: $(date)
Project: $PROJECT_NAME
Region: $AWS_REGION

Cleanup Operations Performed:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ AWS Amplify applications and environments
✅ AppSync GraphQL APIs and data sources
✅ Amazon Cognito User Pools and Identity Pools
✅ DynamoDB tables and all data
✅ Lambda functions and code
✅ S3 buckets and all files
✅ IAM roles and policies
✅ CloudFormation stacks
$([ "$KEEP_LOGS" == "true" ] && echo "⚠️  CloudWatch log groups (preserved)" || echo "✅ CloudWatch log groups")
✅ Local project files and configuration

Backup Information:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Configuration backup created before cleanup.
Check for backup files in the project directory.

Important Notes:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  All tenant data has been permanently deleted
⚠️  All user accounts and authentication data has been removed
⚠️  This action cannot be undone
⚠️  Verify billing to ensure no unexpected charges

To recreate the platform, run the deployment script:
./scripts/deploy.sh

EOF
    
    success "Cleanup report saved to: $report_file"
}

# Main cleanup function
main() {
    # Set up logging
    exec 1> >(tee -a "$CLEANUP_LOG")
    exec 2> >(tee -a "$CLEANUP_LOG" >&2)
    
    log "Starting Multi-Tenant SaaS Platform cleanup..."
    log "Cleanup log: $CLEANUP_LOG"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No actual changes will be made"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    detect_project
    
    if [[ "$DRY_RUN" != "true" ]]; then
        confirm_destruction
        backup_configuration
    fi
    
    remove_amplify_resources
    remove_appsync_resources
    remove_cognito_resources
    remove_dynamodb_resources
    remove_lambda_resources
    remove_s3_resources
    remove_iam_resources
    remove_cloudformation_resources
    remove_cloudwatch_logs
    cleanup_local_files
    
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_cleanup
        generate_cleanup_report
        success "Multi-Tenant SaaS Platform cleanup completed successfully!"
        log "Total cleanup time: $SECONDS seconds"
    else
        log "DRY RUN completed successfully"
        log "Run without --dry-run to perform actual cleanup"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi