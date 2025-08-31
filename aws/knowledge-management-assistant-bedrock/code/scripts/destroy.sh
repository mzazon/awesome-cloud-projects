#!/bin/bash

# Knowledge Management Assistant with Bedrock Agents - Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# to avoid ongoing AWS charges.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script arguments
FORCE_CLEANUP=${1:-""}

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "deployment_state.json" ]]; then
        log_warning "deployment_state.json not found. Manual resource identification required."
        return 1
    fi
    
    # Extract values from deployment state
    export DEPLOYMENT_ID=$(jq -r '.deployment_id // empty' deployment_state.json)
    export AWS_REGION=$(jq -r '.aws_region // empty' deployment_state.json)
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // empty' deployment_state.json)
    export BUCKET_NAME=$(jq -r '.bucket_name // empty' deployment_state.json)
    export KB_ID=$(jq -r '.kb_id // empty' deployment_state.json)
    export AGENT_ID=$(jq -r '.agent_id // empty' deployment_state.json)
    export DATA_SOURCE_ID=$(jq -r '.data_source_id // empty' deployment_state.json)
    export API_ID=$(jq -r '.api_id // empty' deployment_state.json)
    export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name // empty' deployment_state.json)
    export COLLECTION_NAME=$(jq -r '.collection_name // empty' deployment_state.json)
    export RANDOM_SUFFIX=$(jq -r '.deployment_id // empty' deployment_state.json)
    
    if [[ -z "$DEPLOYMENT_ID" ]]; then
        log_warning "Invalid deployment state file. Some resources may need manual cleanup."
        return 1
    fi
    
    log_success "Deployment state loaded for deployment ID: $DEPLOYMENT_ID"
    return 0
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "--force" ]]; then
        log_warning "Force cleanup mode enabled. Skipping confirmation prompt."
        return 0
    fi
    
    echo
    log_warning "This will permanently delete all resources created by the Knowledge Management Assistant deployment."
    echo
    echo "Resources to be deleted:"
    [[ -n "${BUCKET_NAME:-}" ]] && echo "  - S3 Bucket: $BUCKET_NAME (including all contents)"
    [[ -n "${KB_ID:-}" ]] && echo "  - Knowledge Base: $KB_ID"
    [[ -n "${AGENT_ID:-}" ]] && echo "  - Bedrock Agent: $AGENT_ID"
    [[ -n "${API_ID:-}" ]] && echo "  - API Gateway: $API_ID"
    [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
    [[ -n "${COLLECTION_NAME:-}" ]] && echo "  - OpenSearch Collection: $COLLECTION_NAME"
    [[ -n "${RANDOM_SUFFIX:-}" ]] && echo "  - IAM Roles and Policies (suffix: $RANDOM_SUFFIX)"
    echo
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    echo
    log_info "Proceeding with cleanup..."
}

# Safe resource deletion with error handling
safe_delete() {
    local resource_type="$1"
    local command="$2"
    local identifier="$3"
    
    if [[ -z "$identifier" ]]; then
        log_warning "Skipping $resource_type deletion - identifier not found"
        return 0
    fi
    
    log_info "Deleting $resource_type: $identifier"
    
    if eval "$command" 2>/dev/null; then
        log_success "$resource_type deleted successfully"
    else
        log_warning "Failed to delete $resource_type: $identifier (may not exist or already deleted)"
    fi
}

# Delete API Gateway
delete_api_gateway() {
    if [[ -n "${API_ID:-}" ]]; then
        log_info "Deleting API Gateway and related resources..."
        
        # Delete API Gateway
        safe_delete "API Gateway" \
            "aws apigateway delete-rest-api --rest-api-id $API_ID" \
            "$API_ID"
    else
        log_warning "API Gateway ID not found, skipping deletion"
    fi
}

# Delete Lambda function and related resources
delete_lambda_resources() {
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_info "Deleting Lambda function and related resources..."
        
        # Delete Lambda function
        safe_delete "Lambda function" \
            "aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME" \
            "$LAMBDA_FUNCTION_NAME"
    else
        log_warning "Lambda function name not found, skipping deletion"
    fi
    
    # Delete Lambda IAM resources
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        delete_lambda_iam_resources
    fi
}

# Delete Lambda IAM resources
delete_lambda_iam_resources() {
    log_info "Deleting Lambda IAM resources..."
    
    local lambda_role_name="LambdaBedrockRole-${RANDOM_SUFFIX}"
    local lambda_policy_name="LambdaBedrockAccess-${RANDOM_SUFFIX}"
    
    # Detach policies from Lambda role
    safe_delete "Lambda basic execution policy attachment" \
        "aws iam detach-role-policy --role-name $lambda_role_name --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "$lambda_role_name"
    
    safe_delete "Lambda Bedrock policy attachment" \
        "aws iam detach-role-policy --role-name $lambda_role_name --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$lambda_policy_name" \
        "$lambda_role_name"
    
    # Delete custom Lambda policy
    safe_delete "Lambda Bedrock policy" \
        "aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$lambda_policy_name" \
        "$lambda_policy_name"
    
    # Delete Lambda role
    safe_delete "Lambda IAM role" \
        "aws iam delete-role --role-name $lambda_role_name" \
        "$lambda_role_name"
}

# Delete Bedrock Agent
delete_bedrock_agent() {
    if [[ -n "${AGENT_ID:-}" ]]; then
        log_info "Deleting Bedrock Agent..."
        
        # Delete agent (this automatically removes associations)
        safe_delete "Bedrock Agent" \
            "aws bedrock-agent delete-agent --agent-id $AGENT_ID" \
            "$AGENT_ID"
    else
        log_warning "Bedrock Agent ID not found, skipping deletion"
    fi
}

# Delete Knowledge Base and data source
delete_knowledge_base() {
    if [[ -n "${KB_ID:-}" ]]; then
        log_info "Deleting Knowledge Base and data source..."
        
        # Delete data source first
        if [[ -n "${DATA_SOURCE_ID:-}" ]]; then
            safe_delete "Knowledge Base data source" \
                "aws bedrock-agent delete-data-source --knowledge-base-id $KB_ID --data-source-id $DATA_SOURCE_ID" \
                "$DATA_SOURCE_ID"
        fi
        
        # Wait a moment for data source deletion to propagate
        sleep 5
        
        # Delete knowledge base
        safe_delete "Knowledge Base" \
            "aws bedrock-agent delete-knowledge-base --knowledge-base-id $KB_ID" \
            "$KB_ID"
    else
        log_warning "Knowledge Base ID not found, skipping deletion"
    fi
}

# Delete OpenSearch Serverless collection
delete_opensearch_collection() {
    if [[ -n "${COLLECTION_NAME:-}" ]]; then
        log_info "Deleting OpenSearch Serverless collection..."
        
        # Get collection ID
        local collection_id
        collection_id=$(aws opensearchserverless list-collections \
            --query "collectionSummaries[?name=='$COLLECTION_NAME'].id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$collection_id" ]]; then
            safe_delete "OpenSearch Serverless collection" \
                "aws opensearchserverless delete-collection --id $collection_id" \
                "$collection_id"
            
            # Wait for collection deletion to complete
            log_info "Waiting for OpenSearch collection deletion to complete..."
            local max_attempts=12
            local attempt=1
            
            while [[ $attempt -le $max_attempts ]]; do
                local status
                status=$(aws opensearchserverless list-collections \
                    --query "collectionSummaries[?name=='$COLLECTION_NAME'].status" \
                    --output text 2>/dev/null || echo "")
                
                if [[ -z "$status" ]]; then
                    log_success "OpenSearch collection deleted successfully"
                    break
                fi
                
                log_info "Collection status: $status (attempt $attempt/$max_attempts)"
                sleep 15
                ((attempt++))
            done
        else
            log_warning "OpenSearch collection not found or already deleted"
        fi
    else
        log_warning "OpenSearch collection name not found, skipping deletion"
    fi
}

# Delete Bedrock IAM resources
delete_bedrock_iam_resources() {
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        log_info "Deleting Bedrock IAM resources..."
        
        local bedrock_role_name="BedrockAgentRole-${RANDOM_SUFFIX}"
        local s3_policy_name="BedrockS3Access-${RANDOM_SUFFIX}"
        local bedrock_policy_name="BedrockMinimalAccess-${RANDOM_SUFFIX}"
        
        # Detach policies from Bedrock role
        safe_delete "Bedrock S3 policy attachment" \
            "aws iam detach-role-policy --role-name $bedrock_role_name --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$s3_policy_name" \
            "$bedrock_role_name"
        
        safe_delete "Bedrock minimal access policy attachment" \
            "aws iam detach-role-policy --role-name $bedrock_role_name --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$bedrock_policy_name" \
            "$bedrock_role_name"
        
        # Delete custom policies
        safe_delete "Bedrock S3 access policy" \
            "aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$s3_policy_name" \
            "$s3_policy_name"
        
        safe_delete "Bedrock minimal access policy" \
            "aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$bedrock_policy_name" \
            "$bedrock_policy_name"
        
        # Delete Bedrock role
        safe_delete "Bedrock IAM role" \
            "aws iam delete-role --role-name $bedrock_role_name" \
            "$bedrock_role_name"
    else
        log_warning "Random suffix not found, skipping Bedrock IAM resource deletion"
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "Deleting S3 bucket and all contents..."
        
        # Check if bucket exists
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            # Remove all objects and versions
            log_info "Removing all objects from S3 bucket..."
            aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || log_warning "Failed to remove some objects"
            
            # Remove any remaining object versions
            aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json 2>/dev/null | \
                jq -r '.Versions[]? | .Key + " " + .VersionId' | \
                while read -r key version; do
                    if [[ -n "$key" && -n "$version" ]]; then
                        aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version" 2>/dev/null || true
                    fi
                done
            
            # Remove delete markers
            aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json 2>/dev/null | \
                jq -r '.DeleteMarkers[]? | .Key + " " + .VersionId' | \
                while read -r key version; do
                    if [[ -n "$key" && -n "$version" ]]; then
                        aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version" 2>/dev/null || true
                    fi
                done
            
            # Delete the bucket
            safe_delete "S3 bucket" \
                "aws s3 rb s3://$BUCKET_NAME" \
                "$BUCKET_NAME"
        else
            log_warning "S3 bucket not found or already deleted: $BUCKET_NAME"
        fi
    else
        log_warning "S3 bucket name not found, skipping deletion"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "*.json"
        "*.py"
        "*.zip"
        "deployment_summary.txt"
        "sample-docs"
    )
    
    for pattern in "${files_to_remove[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            rm -rf $pattern 2>/dev/null || log_warning "Failed to remove $pattern"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Cannot proceed with cleanup."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required tools
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some features may not work properly."
    fi
    
    log_success "Prerequisites check completed"
}

# Main cleanup orchestration
main() {
    log_info "Starting Knowledge Management Assistant cleanup..."
    
    check_prerequisites
    
    # Load deployment state (non-fatal if it fails)
    if ! load_deployment_state; then
        log_warning "Could not load deployment state. Will attempt manual resource identification."
        
        # Try to find resources manually if we have a suffix
        if [[ -n "${1:-}" && "$1" != "--force" ]]; then
            export RANDOM_SUFFIX="$1"
            export BUCKET_NAME="knowledge-docs-${RANDOM_SUFFIX}"
            export LAMBDA_FUNCTION_NAME="bedrock-agent-proxy-${RANDOM_SUFFIX}"
            export API_NAME="knowledge-management-api-${RANDOM_SUFFIX}"
            export COLLECTION_NAME="kb-collection-${RANDOM_SUFFIX}"
            log_info "Using manual suffix: $RANDOM_SUFFIX"
        else
            log_error "No deployment state found and no suffix provided."
            echo "Usage: $0 [deployment-suffix] [--force]"
            echo "  or place the script in the same directory as deployment_state.json"
            exit 1
        fi
    fi
    
    confirm_cleanup
    
    echo
    log_info "🧹 Beginning resource cleanup (this may take several minutes)..."
    
    # Delete resources in reverse order of creation to handle dependencies
    delete_api_gateway
    delete_lambda_resources
    delete_bedrock_agent
    delete_knowledge_base
    delete_opensearch_collection
    delete_bedrock_iam_resources
    delete_s3_bucket
    cleanup_local_files
    
    echo
    log_success "🎉 Cleanup completed successfully!"
    echo
    echo -e "${GREEN}All Knowledge Management Assistant resources have been removed.${NC}"
    echo
    echo -e "${BLUE}Summary:${NC}"
    echo "✅ API Gateway deleted"
    echo "✅ Lambda function and IAM roles deleted"
    echo "✅ Bedrock Agent deleted"
    echo "✅ Knowledge Base and data source deleted"
    echo "✅ OpenSearch Serverless collection deleted"
    echo "✅ S3 bucket and contents deleted"
    echo "✅ IAM roles and policies deleted"
    echo "✅ Local files cleaned up"
    echo
    echo -e "${YELLOW}Note:${NC} Some resources may take a few minutes to fully disappear from the AWS console."
    echo
}

# Run main function
main "$@"