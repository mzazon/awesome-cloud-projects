#!/bin/bash

# AWS Application Migration Service Cleanup Script
# This script destroys the infrastructure created for automated application migration workflows

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE_DESTROY="${FORCE_DESTROY:-false}"
DRY_RUN="${DRY_RUN:-false}"
STATE_FILE="${SCRIPT_DIR}/deployment-state.env"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DESTROY="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --state-file)
            STATE_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --force       Skip confirmation prompts"
            echo "  --dry-run     Show what would be destroyed without making changes"
            echo "  --state-file  Path to deployment state file (default: ./deployment-state.env)"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        "vpc")
            aws ec2 describe-vpcs --vpc-ids "$resource_id" &>/dev/null
            ;;
        "subnet")
            aws ec2 describe-subnets --subnet-ids "$resource_id" &>/dev/null
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids "$resource_id" &>/dev/null
            ;;
        "internet-gateway")
            aws ec2 describe-internet-gateways --internet-gateway-ids "$resource_id" &>/dev/null
            ;;
        "route-table")
            aws ec2 describe-route-tables --route-table-ids "$resource_id" &>/dev/null
            ;;
        "workflow")
            aws migrationhub-orchestrator get-workflow --id "$resource_id" &>/dev/null
            ;;
        "ssm-document")
            aws ssm get-document --name "$resource_id" &>/dev/null
            ;;
        "cloudwatch-dashboard")
            aws cloudwatch get-dashboard --dashboard-name "$resource_id" &>/dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_id" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Safe deletion function
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local resource_name="${3:-$resource_id}"
    
    if [[ -z "$resource_id" || "$resource_id" == "null" ]]; then
        log_warning "Skipping deletion of $resource_type - ID not found"
        return 0
    fi
    
    if ! resource_exists "$resource_type" "$resource_id"; then
        log_warning "$resource_type $resource_name does not exist or already deleted"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete $resource_type: $resource_name"
        return 0
    fi
    
    log_info "Deleting $resource_type: $resource_name"
    
    case "$resource_type" in
        "workflow")
            aws migrationhub-orchestrator stop-workflow --id "$resource_id" 2>/dev/null || true
            sleep 5
            aws migrationhub-orchestrator delete-workflow --id "$resource_id"
            ;;
        "ssm-document")
            aws ssm delete-document --name "$resource_id"
            ;;
        "cloudwatch-dashboard")
            aws cloudwatch delete-dashboards --dashboard-names "$resource_id"
            ;;
        "cloudwatch-alarm")
            aws cloudwatch delete-alarms --alarm-names "$resource_id"
            ;;
        "security-group")
            aws ec2 delete-security-group --group-id "$resource_id"
            ;;
        "subnet")
            aws ec2 delete-subnet --subnet-id "$resource_id"
            ;;
        "route-table")
            aws ec2 delete-route-table --route-table-id "$resource_id"
            ;;
        "internet-gateway")
            # First detach from VPC if VPC_ID is available
            if [[ -n "${VPC_ID:-}" ]]; then
                aws ec2 detach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$resource_id" 2>/dev/null || true
            fi
            aws ec2 delete-internet-gateway --internet-gateway-id "$resource_id"
            ;;
        "vpc")
            aws ec2 delete-vpc --vpc-id "$resource_id"
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
    
    log_success "Deleted $resource_type: $resource_name"
}

# Display banner
echo -e "${RED}"
echo "=========================================="
echo "AWS Application Migration Service Cleanup"
echo "=========================================="
echo -e "${NC}"

# Load deployment state if available
if [[ -f "$STATE_FILE" ]]; then
    log_info "Loading deployment state from: $STATE_FILE"
    source "$STATE_FILE"
else
    log_warning "Deployment state file not found: $STATE_FILE"
    log_warning "Will attempt to clean up with limited information"
fi

# Validate prerequisites
log_info "Validating prerequisites..."

# Check if AWS CLI is installed and configured
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed. Please install it first."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error_exit "AWS credentials not configured. Please run 'aws configure' first."
fi

# Set region if not already set
if [[ -z "${AWS_REGION:-}" ]]; then
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION="us-east-1"
        log_warning "No region configured, defaulting to $AWS_REGION"
    fi
fi

export AWS_REGION

log_info "Cleanup configuration:"
log_info "  AWS Region: $AWS_REGION"
log_info "  Force Destroy: $FORCE_DESTROY"
log_info "  Dry Run: $DRY_RUN"
log_info "  State File: $STATE_FILE"

# Display resources to be destroyed
log_info "Resources to be destroyed:"
if [[ -n "${WORKFLOW_ID:-}" ]]; then
    log_info "  - Migration Hub Orchestrator Workflow: $WORKFLOW_ID"
fi
if [[ -n "${TEMPLATE_NAME:-}" ]]; then
    log_info "  - Migration Hub Orchestrator Template: $TEMPLATE_NAME"
fi
if [[ -n "${DASHBOARD_NAME:-}" ]]; then
    log_info "  - CloudWatch Dashboard: $DASHBOARD_NAME"
fi
if [[ -n "${ALARM_NAME:-}" ]]; then
    log_info "  - CloudWatch Alarm: $ALARM_NAME"
fi
if [[ -n "${SSM_DOCUMENT_NAME:-}" ]]; then
    log_info "  - Systems Manager Document: $SSM_DOCUMENT_NAME"
fi
if [[ -n "${MIGRATION_SG_ID:-}" ]]; then
    log_info "  - Security Group: $MIGRATION_SG_ID"
fi
if [[ -n "${PUBLIC_SUBNET_ID:-}" ]]; then
    log_info "  - Public Subnet: $PUBLIC_SUBNET_ID"
fi
if [[ -n "${PRIVATE_SUBNET_ID:-}" ]]; then
    log_info "  - Private Subnet: $PRIVATE_SUBNET_ID"
fi
if [[ -n "${ROUTE_TABLE_ID:-}" ]]; then
    log_info "  - Route Table: $ROUTE_TABLE_ID"
fi
if [[ -n "${IGW_ID:-}" ]]; then
    log_info "  - Internet Gateway: $IGW_ID"
fi
if [[ -n "${VPC_ID:-}" ]]; then
    log_info "  - VPC: $VPC_ID"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN MODE - No resources will be destroyed"
    exit 0
fi

# Confirmation prompt
if [[ "$FORCE_DESTROY" != "true" ]]; then
    echo ""
    log_warning "This will permanently delete all migration infrastructure!"
    log_warning "This action cannot be undone."
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
fi

log_info "Starting cleanup..."

# Step 1: Stop and clean up Migration Hub Orchestrator workflow
if [[ -n "${WORKFLOW_ID:-}" ]]; then
    log_info "Step 1: Cleaning up Migration Hub Orchestrator workflow..."
    safe_delete "workflow" "$WORKFLOW_ID" "$WORKFLOW_ID"
    
    # Wait for workflow to be fully deleted
    log_info "Waiting for workflow deletion to complete..."
    for i in {1..30}; do
        if ! resource_exists "workflow" "$WORKFLOW_ID"; then
            break
        fi
        sleep 5
    done
else
    log_info "Step 1: No workflow to clean up"
fi

# Step 2: Delete Migration Hub Orchestrator template
if [[ -n "${TEMPLATE_NAME:-}" ]]; then
    log_info "Step 2: Deleting Migration Hub Orchestrator template..."
    if [[ "$DRY_RUN" != "true" ]]; then
        aws migrationhub-orchestrator delete-template --template-id "$TEMPLATE_NAME" 2>/dev/null || \
            log_warning "Failed to delete template $TEMPLATE_NAME (may not exist)"
    else
        log_info "[DRY RUN] Would delete template: $TEMPLATE_NAME"
    fi
else
    log_info "Step 2: No template to delete"
fi

# Step 3: Remove CloudWatch resources
log_info "Step 3: Removing CloudWatch resources..."
if [[ -n "${DASHBOARD_NAME:-}" ]]; then
    safe_delete "cloudwatch-dashboard" "$DASHBOARD_NAME" "$DASHBOARD_NAME"
fi

if [[ -n "${ALARM_NAME:-}" ]]; then
    safe_delete "cloudwatch-alarm" "$ALARM_NAME" "$ALARM_NAME"
fi

# Step 4: Delete Systems Manager documents
if [[ -n "${SSM_DOCUMENT_NAME:-}" ]]; then
    log_info "Step 4: Deleting Systems Manager documents..."
    safe_delete "ssm-document" "$SSM_DOCUMENT_NAME" "$SSM_DOCUMENT_NAME"
else
    log_info "Step 4: No Systems Manager documents to delete"
fi

# Step 5: Remove security groups
if [[ -n "${MIGRATION_SG_ID:-}" ]]; then
    log_info "Step 5: Removing security groups..."
    safe_delete "security-group" "$MIGRATION_SG_ID" "Migration Security Group"
else
    log_info "Step 5: No security groups to remove"
fi

# Step 6: Remove VPC infrastructure (in reverse order of creation)
log_info "Step 6: Removing VPC infrastructure..."

# Delete subnets
if [[ -n "${PUBLIC_SUBNET_ID:-}" ]]; then
    safe_delete "subnet" "$PUBLIC_SUBNET_ID" "Public Subnet"
fi

if [[ -n "${PRIVATE_SUBNET_ID:-}" ]]; then
    safe_delete "subnet" "$PRIVATE_SUBNET_ID" "Private Subnet"
fi

# Delete route table
if [[ -n "${ROUTE_TABLE_ID:-}" ]]; then
    safe_delete "route-table" "$ROUTE_TABLE_ID" "Route Table"
fi

# Delete Internet Gateway
if [[ -n "${IGW_ID:-}" ]]; then
    safe_delete "internet-gateway" "$IGW_ID" "Internet Gateway"
fi

# Delete VPC
if [[ -n "${VPC_ID:-}" ]]; then
    safe_delete "vpc" "$VPC_ID" "VPC"
fi

# Step 7: Clean up local files
log_info "Step 7: Cleaning up local files..."
if [[ "$DRY_RUN" != "true" ]]; then
    rm -f "${SCRIPT_DIR}/deployment-state.env"
    rm -f "${SCRIPT_DIR}"/migration-*.json
    rm -f "${SCRIPT_DIR}"/post-migration-*.json
    log_success "Local files cleaned up"
else
    log_info "[DRY RUN] Would delete local state and temporary files"
fi

# Step 8: Final validation
log_info "Step 8: Performing final validation..."
if [[ "$DRY_RUN" != "true" ]]; then
    validation_failed=false
    
    # Check if any resources still exist
    if [[ -n "${VPC_ID:-}" ]] && resource_exists "vpc" "$VPC_ID"; then
        log_error "VPC $VPC_ID still exists after cleanup"
        validation_failed=true
    fi
    
    if [[ -n "${WORKFLOW_ID:-}" ]] && resource_exists "workflow" "$WORKFLOW_ID"; then
        log_error "Workflow $WORKFLOW_ID still exists after cleanup"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        log_error "Some resources may not have been properly deleted"
        log_error "Please check the AWS console and manually delete any remaining resources"
        exit 1
    fi
fi

# Display cleanup summary
log_success "================== CLEANUP COMPLETE =================="
log_success "Migration infrastructure cleanup completed successfully!"
log_success ""
log_success "Cleanup Summary:"
log_success "  - Migration Hub Orchestrator workflow and template removed"
log_success "  - CloudWatch dashboards and alarms deleted"
log_success "  - Systems Manager automation documents removed"
log_success "  - VPC infrastructure destroyed"
log_success "  - Local state files cleaned up"
log_success ""
log_success "Important Notes:"
log_success "  - MGN service initialization remains (region-level setting)"
log_success "  - Migration Hub home region configuration remains"
log_success "  - Any source servers with MGN agents will need manual cleanup"
log_success "  - Check AWS console for any remaining resources"
log_success ""
log_success "AWS Console URLs to verify cleanup:"
log_success "  MGN Console: https://console.aws.amazon.com/mgn/home?region=$AWS_REGION"
log_success "  Migration Hub: https://console.aws.amazon.com/migrationhub/home?region=$AWS_REGION"
log_success "  VPC Console: https://console.aws.amazon.com/vpc/home?region=$AWS_REGION"
log_success "  CloudWatch Console: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION"
log_success "=================================================="

log_success "Cleanup completed successfully at $(date)"