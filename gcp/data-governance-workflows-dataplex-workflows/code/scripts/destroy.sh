#!/bin/bash

# Data Governance Workflows with Dataplex and Cloud Workflows - Cleanup Script
# This script safely destroys the data governance infrastructure to avoid ongoing costs

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    log "$1" "$BLUE"
}

log_success() {
    log "$1" "$GREEN"
}

log_warning() {
    log "$1" "$YELLOW"
}

log_error() {
    log "$1" "$RED"
}

# Error handling
handle_error() {
    log_error "❌ Cleanup failed at line $1"
    log_error "Check the log file for details: $LOG_FILE"
    log_warning "⚠️  Some resources may still exist and continue to incur costs"
    log_info "Consider manual cleanup in the Google Cloud Console"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Prerequisites check
check_prerequisites() {
    log_info "🔍 Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "❌ Google Cloud CLI is not installed."
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "❌ Terraform is not installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "❌ You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if Terraform directory exists
    if [ ! -d "$TERRAFORM_DIR" ]; then
        log_error "❌ Terraform directory not found: $TERRAFORM_DIR"
        exit 1
    fi
    
    log_success "✅ Prerequisites check passed"
}

# Get deployment information
get_deployment_info() {
    log_info "📋 Getting deployment information..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if Terraform state exists
    if [ ! -f "terraform.tfstate" ]; then
        log_warning "⚠️  No Terraform state file found. Resources may not have been deployed via Terraform."
        log_info "Checking for manually created resources..."
        
        # Try to get project from gcloud config
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        
        if [ -z "$PROJECT_ID" ]; then
            log_error "❌ No project configured. Please set your project: gcloud config set project PROJECT_ID"
            exit 1
        fi
        
        export PROJECT_ID
        export REGION
        log_info "Using project: $PROJECT_ID, region: $REGION"
        return
    fi
    
    # Initialize Terraform if needed
    if [ ! -d ".terraform" ]; then
        log_info "Initializing Terraform..."
        terraform init
    fi
    
    # Get current deployment information
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    
    export PROJECT_ID
    export REGION
    
    log_success "✅ Deployment information retrieved"
    log_info "Project: $PROJECT_ID"
    log_info "Region: $REGION"
}

# Backup important data
backup_data() {
    log_info "💾 Backing up important data..."
    
    # Create backup directory
    BACKUP_DIR="${SCRIPT_DIR}/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup BigQuery data if dataset exists
    if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        cd "$TERRAFORM_DIR"
        
        # Try to get dataset name from Terraform output
        if terraform output -raw dataset_name &>/dev/null; then
            DATASET_NAME=$(terraform output -raw dataset_name)
            log_info "Backing up BigQuery dataset: $DATASET_NAME"
            
            # Export governance metrics
            if bq show --dataset "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
                log_info "Exporting data quality metrics..."
                bq extract --destination_format CSV \
                    "$PROJECT_ID:$DATASET_NAME.data_quality_metrics" \
                    "gs://temp-backup-bucket-$(date +%s)/data_quality_metrics.csv" 2>/dev/null || true
                
                log_info "Exporting compliance reports..."
                bq extract --destination_format CSV \
                    "$PROJECT_ID:$DATASET_NAME.compliance_reports" \
                    "gs://temp-backup-bucket-$(date +%s)/compliance_reports.csv" 2>/dev/null || true
            fi
        fi
    fi
    
    # Backup Terraform state
    if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        log_info "Backing up Terraform state..."
        cp "$TERRAFORM_DIR/terraform.tfstate" "$BACKUP_DIR/terraform.tfstate.backup"
    fi
    
    # Backup configuration files
    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        log_info "Backing up Terraform variables..."
        cp "$TERRAFORM_DIR/terraform.tfvars" "$BACKUP_DIR/terraform.tfvars.backup"
    fi
    
    log_success "✅ Data backup completed: $BACKUP_DIR"
}

# Confirm destruction
confirm_destruction() {
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    log_warning "=================================="
    log_warning "This will permanently delete all resources created by this deployment:"
    log_warning "- Dataplex lakes and zones"
    log_warning "- Cloud Workflows"
    log_warning "- BigQuery datasets and tables"
    log_warning "- Cloud Storage buckets and data"
    log_warning "- DLP templates and job triggers"
    log_warning "- Cloud Functions"
    log_warning "- Monitoring resources"
    log_warning ""
    log_warning "Project: $PROJECT_ID"
    log_warning "Region: $REGION"
    log_warning ""
    
    if [ "${AUTO_APPROVE:-false}" != "true" ]; then
        log_warning "Are you sure you want to proceed? This action cannot be undone."
        read -p "Type 'yes' to confirm destruction: " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
        
        log_warning "Final confirmation: Are you absolutely sure?"
        read -p "Type 'DELETE' to proceed: " final_confirm
        if [ "$final_confirm" != "DELETE" ]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Pre-cleanup manual resources
pre_cleanup() {
    log_info "🧹 Performing pre-cleanup of manual resources..."
    
    # Stop any running DLP jobs
    log_info "Stopping DLP jobs..."
    gcloud dlp jobs cancel --filter="state:RUNNING" --quiet 2>/dev/null || true
    
    # Cancel any running workflow executions
    log_info "Cancelling workflow executions..."
    if gcloud workflows list --filter="state:ACTIVE" --format="value(name)" | grep -q .; then
        gcloud workflows list --filter="state:ACTIVE" --format="value(name)" | while read -r workflow; do
            gcloud workflows executions list --workflow="$workflow" --filter="state:ACTIVE" --format="value(name)" | while read -r execution; do
                gcloud workflows executions cancel "$execution" --workflow="$workflow" --quiet 2>/dev/null || true
            done
        done
    fi
    
    log_success "✅ Pre-cleanup completed"
}

# Destroy Terraform resources
destroy_terraform() {
    log_info "🗑️  Destroying Terraform resources..."
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "terraform.tfstate" ]; then
        log_warning "⚠️  No Terraform state found. Skipping Terraform destruction."
        return
    fi
    
    # Validate Terraform configuration
    log_info "Validating Terraform configuration..."
    terraform validate
    
    # Plan destruction
    log_info "Planning destruction..."
    terraform plan -destroy -out=destroy.tfplan
    
    # Apply destruction
    log_info "Applying destruction..."
    terraform apply destroy.tfplan
    
    # Clean up Terraform files
    log_info "Cleaning up Terraform files..."
    rm -f destroy.tfplan
    rm -f terraform.tfstate.backup
    
    log_success "✅ Terraform resources destroyed"
}

# Manual cleanup of remaining resources
manual_cleanup() {
    log_info "🧹 Performing manual cleanup of remaining resources..."
    
    # Generate unique suffix for cleanup
    CLEANUP_SUFFIX=$(date +%s)
    
    # Clean up DLP resources
    log_info "Cleaning up DLP resources..."
    
    # List and delete DLP job triggers
    if gcloud dlp job-triggers list --format="value(name)" | grep -q .; then
        gcloud dlp job-triggers list --format="value(name)" | while read -r trigger; do
            log_info "Deleting DLP trigger: $trigger"
            gcloud dlp job-triggers delete "$trigger" --quiet 2>/dev/null || true
        done
    fi
    
    # List and delete DLP inspection templates
    if gcloud dlp inspect-templates list --format="value(name)" | grep -q .; then
        gcloud dlp inspect-templates list --format="value(name)" | while read -r template; do
            log_info "Deleting DLP template: $template"
            gcloud dlp inspect-templates delete "$template" --quiet 2>/dev/null || true
        done
    fi
    
    # Clean up Cloud Storage buckets (be careful with this)
    log_info "Cleaning up Cloud Storage buckets..."
    gsutil ls -p "$PROJECT_ID" | grep "governance-data-lake" | while read -r bucket; do
        log_info "Deleting bucket: $bucket"
        gsutil -m rm -r "$bucket" 2>/dev/null || true
    done
    
    # Clean up Cloud Functions
    log_info "Cleaning up Cloud Functions..."
    gcloud functions list --format="value(name)" | grep "data-quality-assessor" | while read -r function; do
        log_info "Deleting function: $function"
        gcloud functions delete "$function" --region="$REGION" --quiet 2>/dev/null || true
    done
    
    # Clean up Workflows
    log_info "Cleaning up Cloud Workflows..."
    gcloud workflows list --format="value(name)" | grep "governance-workflow" | while read -r workflow; do
        log_info "Deleting workflow: $workflow"
        gcloud workflows delete "$workflow" --location="$REGION" --quiet 2>/dev/null || true
    done
    
    # Clean up BigQuery datasets
    log_info "Cleaning up BigQuery datasets..."
    bq ls -d --format=prettyjson | jq -r '.[] | select(.datasetReference.datasetId | contains("governance_analytics")) | .datasetReference.datasetId' | while read -r dataset; do
        log_info "Deleting dataset: $dataset"
        bq rm -r -f "$PROJECT_ID:$dataset" 2>/dev/null || true
    done
    
    # Clean up Dataplex resources
    log_info "Cleaning up Dataplex resources..."
    
    # Delete Dataplex zones
    gcloud dataplex zones list --location="$REGION" --format="value(name)" | while read -r zone; do
        log_info "Deleting Dataplex zone: $zone"
        gcloud dataplex zones delete "$zone" --quiet 2>/dev/null || true
    done
    
    # Delete Dataplex lakes
    gcloud dataplex lakes list --location="$REGION" --format="value(name)" | while read -r lake; do
        log_info "Deleting Dataplex lake: $lake"
        gcloud dataplex lakes delete "$lake" --quiet 2>/dev/null || true
    done
    
    # Clean up monitoring resources
    log_info "Cleaning up monitoring resources..."
    gcloud logging metrics list --format="value(name)" | grep "governance" | while read -r metric; do
        log_info "Deleting log metric: $metric"
        gcloud logging metrics delete "$metric" --quiet 2>/dev/null || true
    done
    
    log_success "✅ Manual cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "🔍 Verifying cleanup..."
    
    local cleanup_complete=true
    
    # Check for remaining Dataplex resources
    if gcloud dataplex lakes list --location="$REGION" --format="value(name)" | grep -q .; then
        log_warning "⚠️  Some Dataplex lakes may still exist"
        cleanup_complete=false
    fi
    
    # Check for remaining Cloud Workflows
    if gcloud workflows list --format="value(name)" | grep "governance" | grep -q .; then
        log_warning "⚠️  Some Cloud Workflows may still exist"
        cleanup_complete=false
    fi
    
    # Check for remaining BigQuery datasets
    if bq ls -d --format=prettyjson | jq -r '.[] | select(.datasetReference.datasetId | contains("governance_analytics")) | .datasetReference.datasetId' | grep -q .; then
        log_warning "⚠️  Some BigQuery datasets may still exist"
        cleanup_complete=false
    fi
    
    # Check for remaining DLP resources
    if gcloud dlp job-triggers list --format="value(name)" | grep -q .; then
        log_warning "⚠️  Some DLP job triggers may still exist"
        cleanup_complete=false
    fi
    
    if [ "$cleanup_complete" = true ]; then
        log_success "✅ Cleanup verification completed - all resources removed"
    else
        log_warning "⚠️  Some resources may still exist. Please check the Google Cloud Console"
        log_info "Consider manual cleanup of any remaining resources to avoid costs"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "🧹 Cleaning up local files..."
    
    cd "$TERRAFORM_DIR"
    
    # Remove Terraform state lock
    rm -f .terraform.lock.hcl
    
    # Remove Terraform backend files
    rm -rf .terraform/
    
    # Remove temporary files
    rm -f *.tfplan
    rm -f outputs.json
    
    # Clean up function source if it exists
    if [ -d "function_source" ]; then
        rm -rf function_source/
    fi
    
    log_success "✅ Local files cleaned up"
}

# Display cleanup summary
display_summary() {
    log_info "📊 Cleanup Summary"
    log_info "=================="
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Cleanup Log: $LOG_FILE"
    
    if [ -d "${SCRIPT_DIR}/backup-"* ]; then
        log_info "Backup Directory: $(ls -d ${SCRIPT_DIR}/backup-* | tail -1)"
    fi
    
    log_info ""
    log_info "🔍 Recommended Next Steps:"
    log_info "========================="
    log_info "1. Check the Google Cloud Console to verify all resources are removed"
    log_info "2. Review your billing to ensure no unexpected charges"
    log_info "3. Clean up any remaining resources manually if needed"
    log_info "4. Consider removing the backup directory if no longer needed"
    log_info ""
    log_info "📚 Resources for Manual Cleanup (if needed):"
    log_info "============================================="
    log_info "- Dataplex: https://console.cloud.google.com/dataplex"
    log_info "- Cloud Workflows: https://console.cloud.google.com/workflows"
    log_info "- BigQuery: https://console.cloud.google.com/bigquery"
    log_info "- Cloud Storage: https://console.cloud.google.com/storage"
    log_info "- DLP: https://console.cloud.google.com/security/dlp"
    log_info "- Cloud Functions: https://console.cloud.google.com/functions"
}

# Main cleanup function
main() {
    log_info "🗑️  Starting Data Governance Workflows Cleanup"
    log_info "==============================================="
    
    check_prerequisites
    get_deployment_info
    backup_data
    confirm_destruction
    pre_cleanup
    destroy_terraform
    manual_cleanup
    verify_cleanup
    cleanup_local_files
    display_summary
    
    log_success "🎉 Cleanup completed successfully!"
    log_info "Total cleanup time: $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Help function
show_help() {
    cat << EOF
Data Governance Workflows Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -y, --yes           Auto-approve cleanup (skip confirmation)
    -p, --project       Set GCP project ID
    -r, --region        Set GCP region
    -v, --verbose       Enable verbose logging
    --no-backup         Skip data backup step
    --force             Force cleanup even if verification fails

Environment Variables:
    PROJECT_ID          GCP project ID to use
    REGION             GCP region to use (default: us-central1)
    AUTO_APPROVE       Skip confirmation prompt (true/false)
    SKIP_BACKUP        Skip data backup step (true/false)

Examples:
    $0                  # Interactive cleanup
    $0 -y               # Auto-approve cleanup
    $0 -p my-project    # Cleanup specific project
    $0 --no-backup      # Skip backup step

⚠️  WARNING: This script will permanently delete all resources!
Make sure you have backed up any important data before running this script.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -y|--yes)
            export AUTO_APPROVE=true
            shift
            ;;
        -p|--project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            export REGION="$2"
            shift 2
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        --no-backup)
            export SKIP_BACKUP=true
            shift
            ;;
        --force)
            export FORCE_CLEANUP=true
            shift
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