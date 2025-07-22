#!/bin/bash

# Destroy script for ECR Container Registry Replication Strategies
# This script removes all ECR replication infrastructure created by deploy.sh
# including repositories, replication rules, lifecycle policies, and monitoring

set -euo pipefail

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "Error on line $1"
    log_error "Cleanup failed. Some resources may remain. Check the logs above for details."
    exit 1
}

trap 'error_exit $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy ECR Container Registry Replication Strategies infrastructure

OPTIONS:
    -h, --help          Show this help message
    -c, --config        Path to deployment config file (default: ./last-deployment.env)
    -f, --force         Skip confirmation prompts
    -n, --dry-run       Show what would be destroyed without making changes
    -v, --verbose       Enable verbose logging
    -k, --keep-images   Keep container images (only delete repositories)
    -m, --manual        Provide configuration manually (interactive)

Examples:
    $0                              # Use last deployment config with confirmation
    $0 -f                           # Force cleanup without confirmation
    $0 -n                           # Dry run to see what would be destroyed
    $0 -c ./my-deployment.env       # Use specific config file
    $0 -m                           # Manual configuration input
EOF
}

# Default values
CONFIG_FILE="./last-deployment.env"
FORCE=false
DRY_RUN=false
VERBOSE=false
KEEP_IMAGES=false
MANUAL_CONFIG=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -k|--keep-images)
            KEEP_IMAGES=true
            shift
            ;;
        -m|--manual)
            MANUAL_CONFIG=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load configuration
load_configuration() {
    if [[ "$MANUAL_CONFIG" == true ]]; then
        manual_configuration
        return
    fi
    
    # Try to find config file
    if [[ ! -f "$CONFIG_FILE" ]]; then
        # Try script directory
        if [[ -f "$SCRIPT_DIR/last-deployment.env" ]]; then
            CONFIG_FILE="$SCRIPT_DIR/last-deployment.env"
        else
            log_error "Configuration file not found: $CONFIG_FILE"
            log_error "Use -m for manual configuration or specify correct path with -c"
            exit 1
        fi
    fi
    
    log "Loading configuration from: $CONFIG_FILE"
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Validate required variables
    local required_vars=("AWS_ACCOUNT_ID" "SOURCE_REGION" "REPLICATION_REGIONS" 
                         "REPO_PREFIX" "PROD_REPO" "TEST_REPO" "RANDOM_SUFFIX")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not found in configuration file"
            exit 1
        fi
    done
    
    log_success "Configuration loaded successfully"
    log "  Account ID: $AWS_ACCOUNT_ID"
    log "  Source Region: $SOURCE_REGION"
    log "  Replication Regions: $REPLICATION_REGIONS"
    log "  Repository Prefix: $REPO_PREFIX"
    log "  Deployment ID: $RANDOM_SUFFIX"
}

# Manual configuration input
manual_configuration() {
    log "Manual configuration mode - Please provide the following information:"
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    SOURCE_REGION=$(aws configure get region)
    
    echo -n "Repository prefix (default: enterprise-apps): "
    read -r input_prefix
    REPO_PREFIX=${input_prefix:-enterprise-apps}
    
    echo -n "Deployment ID/suffix: "
    read -r RANDOM_SUFFIX
    
    echo -n "Replication regions (comma-separated): "
    read -r REPLICATION_REGIONS
    
    # Construct repository names
    PROD_REPO="${REPO_PREFIX}/production-${RANDOM_SUFFIX}"
    TEST_REPO="${REPO_PREFIX}/testing-${RANDOM_SUFFIX}"
    
    # Optional monitoring resources
    echo -n "SNS Topic ARN (optional): "
    read -r TOPIC_ARN
    
    log_success "Manual configuration completed"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == true ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return
    fi
    
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This will permanently delete the following resources:"
    log_warning "  - ECR repositories: $PROD_REPO, $TEST_REPO"
    log_warning "  - All container images in these repositories"
    log_warning "  - Replication configuration"
    log_warning "  - Lifecycle policies"
    log_warning "  - CloudWatch dashboard: ECR-Replication-Monitoring-$RANDOM_SUFFIX"
    log_warning "  - SNS topic: ECR-Replication-Alerts-$RANDOM_SUFFIX"
    log_warning "  - Repository policies"
    log_warning ""
    log_warning "Regions affected: $SOURCE_REGION, $REPLICATION_REGIONS"
    log_warning ""
    
    if [[ "$KEEP_IMAGES" == true ]]; then
        log_warning "Note: Container images will be preserved (--keep-images flag)"
    fi
    
    echo -n "Are you sure you want to continue? (type 'DELETE' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Remove container images
remove_images() {
    if [[ "$KEEP_IMAGES" == true ]]; then
        log "Skipping image removal as requested (--keep-images flag)"
        return
    fi
    
    log "Removing container images from all regions..."
    
    # Parse replication regions
    local all_regions="$SOURCE_REGION,$REPLICATION_REGIONS"
    IFS=',' read -ra REGIONS <<< "$all_regions"
    
    for region in "${REGIONS[@]}"; do
        # Remove leading/trailing whitespace
        region=$(echo "$region" | xargs)
        
        log "Checking region: $region"
        
        for repo in "$PROD_REPO" "$TEST_REPO"; do
            if [[ "$DRY_RUN" == true ]]; then
                log "DRY RUN: Would remove all images from $repo in $region"
                continue
            fi
            
            # Check if repository exists
            if ! aws ecr describe-repositories \
                --repository-names "$repo" \
                --region "$region" &> /dev/null; then
                log "Repository $repo not found in region $region"
                continue
            fi
            
            # Get all images in repository
            local images=$(aws ecr describe-images \
                --repository-name "$repo" \
                --region "$region" \
                --query 'imageDetails[*].imageDigest' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$images" && "$images" != "None" ]]; then
                log "Removing images from $repo in region $region"
                
                # Convert to image IDs format
                local image_ids=""
                for digest in $images; do
                    if [[ -n "$image_ids" ]]; then
                        image_ids+=","
                    fi
                    image_ids+="{\"imageDigest\":\"$digest\"}"
                done
                
                # Delete images in batches
                aws ecr batch-delete-image \
                    --repository-name "$repo" \
                    --region "$region" \
                    --image-ids "[$image_ids]" > /dev/null
                
                log_success "Removed images from $repo in $region"
            else
                log "No images found in $repo in region $region"
            fi
        done
    done
}

# Remove repositories
remove_repositories() {
    log "Removing ECR repositories from all regions..."
    
    # Parse replication regions
    local all_regions="$SOURCE_REGION,$REPLICATION_REGIONS"
    IFS=',' read -ra REGIONS <<< "$all_regions"
    
    for region in "${REGIONS[@]}"; do
        # Remove leading/trailing whitespace
        region=$(echo "$region" | xargs)
        
        log "Checking region: $region"
        
        for repo in "$PROD_REPO" "$TEST_REPO"; do
            if [[ "$DRY_RUN" == true ]]; then
                log "DRY RUN: Would delete repository $repo in $region"
                continue
            fi
            
            # Check if repository exists
            if aws ecr describe-repositories \
                --repository-names "$repo" \
                --region "$region" &> /dev/null; then
                
                # Force delete repository with all images
                aws ecr delete-repository \
                    --repository-name "$repo" \
                    --region "$region" \
                    --force > /dev/null
                
                log_success "Deleted repository $repo in $region"
            else
                log "Repository $repo not found in region $region"
            fi
        done
    done
}

# Remove replication configuration
remove_replication_configuration() {
    log "Removing replication configuration..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would remove replication configuration"
        return
    fi
    
    # Remove replication rules
    aws ecr put-replication-configuration \
        --region "$SOURCE_REGION" \
        --replication-configuration '{"rules": []}' > /dev/null
    
    log_success "Removed replication configuration"
}

# Remove monitoring resources
remove_monitoring() {
    log "Removing monitoring resources..."
    
    # Remove CloudWatch dashboard
    local dashboard_name="ECR-Replication-Monitoring-$RANDOM_SUFFIX"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would delete CloudWatch dashboard: $dashboard_name"
    else
        if aws cloudwatch describe-dashboards \
            --dashboard-names "$dashboard_name" \
            --region "$SOURCE_REGION" &> /dev/null; then
            
            aws cloudwatch delete-dashboards \
                --dashboard-names "$dashboard_name" \
                --region "$SOURCE_REGION" > /dev/null
            
            log_success "Deleted CloudWatch dashboard: $dashboard_name"
        else
            log "CloudWatch dashboard not found: $dashboard_name"
        fi
    fi
    
    # Remove SNS topic if specified
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log "DRY RUN: Would delete SNS topic: $TOPIC_ARN"
        else
            aws sns delete-topic \
                --topic-arn "$TOPIC_ARN" \
                --region "$SOURCE_REGION" > /dev/null
            
            log_success "Deleted SNS topic: $TOPIC_ARN"
        fi
    fi
    
    # Remove CloudWatch alarms
    local alarm_name="ECR-Replication-Failure-Rate"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would delete CloudWatch alarm: $alarm_name"
    else
        if aws cloudwatch describe-alarms \
            --alarm-names "$alarm_name" \
            --region "$SOURCE_REGION" &> /dev/null; then
            
            aws cloudwatch delete-alarms \
                --alarm-names "$alarm_name" \
                --region "$SOURCE_REGION" > /dev/null
            
            log_success "Deleted CloudWatch alarm: $alarm_name"
        else
            log "CloudWatch alarm not found: $alarm_name"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "$SCRIPT_DIR/last-deployment.env"
        "$SCRIPT_DIR/deployment-config.env"
        "./replication-config.json"
        "./prod-lifecycle-policy.json"
        "./test-lifecycle-policy.json"
        "./prod-repo-policy.json"
        "./ecr-dashboard.json"
        "./cleanup-lambda.py"
        "./cleanup-lambda.zip"
        "./Dockerfile"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log "DRY RUN: Would remove file: $file"
            else
                rm -f "$file"
                log_success "Removed file: $file"
            fi
        fi
    done
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would verify cleanup"
        return
    fi
    
    # Check repositories in source region
    local remaining_repos=$(aws ecr describe-repositories \
        --region "$SOURCE_REGION" \
        --query "repositories[?starts_with(repositoryName, '$REPO_PREFIX')].repositoryName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_repos" && "$remaining_repos" != "None" ]]; then
        log_warning "Some repositories may still exist in $SOURCE_REGION: $remaining_repos"
    else
        log_success "All repositories removed from $SOURCE_REGION"
    fi
    
    # Check replication configuration
    local replication_rules=$(aws ecr describe-registry \
        --region "$SOURCE_REGION" \
        --query 'replicationConfiguration.rules' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$replication_rules" == "None" || "$replication_rules" == "[]" ]]; then
        log_success "Replication configuration removed"
    else
        log_warning "Replication configuration may still exist"
    fi
    
    log_success "Cleanup verification completed"
}

# Main cleanup function
main() {
    log "Starting ECR Container Registry Replication Strategies cleanup..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    check_prerequisites
    load_configuration
    confirm_destruction
    remove_images
    remove_repositories
    remove_replication_configuration
    remove_monitoring
    cleanup_local_files
    verify_cleanup
    
    log_success "Cleanup completed successfully!"
    log ""
    log "📋 Cleanup Summary:"
    log "  - Removed ECR repositories: $PROD_REPO, $TEST_REPO"
    log "  - Removed replication configuration"
    log "  - Removed monitoring resources"
    log "  - Cleaned up local files"
    log ""
    log "🔍 Verification:"
    log "  - Check AWS Console to confirm all resources are removed"
    log "  - Monitor AWS billing for cost reductions"
    log ""
    log "📊 Useful Commands for Verification:"
    log "  aws ecr describe-repositories --region $SOURCE_REGION"
    log "  aws ecr describe-registry --region $SOURCE_REGION"
    log "  aws cloudwatch describe-dashboards --region $SOURCE_REGION"
    
    if [[ "$DRY_RUN" == false ]]; then
        log_success "All ECR Container Registry Replication Strategies resources have been removed"
    fi
}

# Run main function
main "$@"