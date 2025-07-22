#!/bin/bash

# AWS Application Discovery Service - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS credentials
check_aws_credentials() {
    log "Checking AWS credentials..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    success "AWS credentials validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    success "AWS CLI version: $aws_version"
    
    check_aws_credentials
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [ ! -f "deployment-state.json" ]; then
        warning "deployment-state.json not found. Using default values."
        
        # Set default values if state file doesn't exist
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export MH_HOME_REGION="us-west-2"
        
        # Try to find discovery bucket
        local bucket_pattern="discovery-data-${AWS_ACCOUNT_ID}-"
        export DISCOVERY_BUCKET=$(aws s3 ls | grep "$bucket_pattern" | awk '{print $3}' | head -1)
        
        if [ -z "$DISCOVERY_BUCKET" ]; then
            warning "Could not find discovery bucket. Some cleanup may be incomplete."
        fi
        
        return 0
    fi
    
    # Load values from state file
    export AWS_REGION=$(cat deployment-state.json | grep -o '"awsRegion":"[^"]*' | cut -d'"' -f4)
    export AWS_ACCOUNT_ID=$(cat deployment-state.json | grep -o '"awsAccountId":"[^"]*' | cut -d'"' -f4)
    export MH_HOME_REGION=$(cat deployment-state.json | grep -o '"migrationHubHomeRegion":"[^"]*' | cut -d'"' -f4)
    export DISCOVERY_BUCKET=$(cat deployment-state.json | grep -o '"discoveryBucket":"[^"]*' | cut -d'"' -f4)
    export EXPORT_ID=$(cat deployment-state.json | grep -o '"exportId":"[^"]*' | cut -d'"' -f4)
    export APP_ID=$(cat deployment-state.json | grep -o '"applicationId":"[^"]*' | cut -d'"' -f4)
    
    success "Deployment state loaded successfully"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Migration Hub Home Region: $MH_HOME_REGION"
    log "Discovery Bucket: $DISCOVERY_BUCKET"
    log "Export ID: $EXPORT_ID"
    log "Application ID: $APP_ID"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    echo "==========================================="
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION"
    echo "==========================================="
    echo
    echo "This will permanently delete the following resources:"
    echo "- S3 bucket: $DISCOVERY_BUCKET (and all contents)"
    echo "- IAM role: ApplicationDiscoveryServiceRole"
    echo "- CloudWatch Events rule: DiscoveryReportSchedule"
    echo "- Athena database: discovery_analysis"
    echo "- Application group: $APP_ID"
    echo "- Discovery continuous export: $EXPORT_ID"
    echo
    echo "⚠️  Discovery agents will NOT be removed automatically."
    echo "    You must manually uninstall agents from your servers."
    echo
    read -p "Are you sure you want to continue? (Type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to stop data collection
stop_data_collection() {
    log "Stopping data collection..."
    
    # Get all agent IDs
    local agent_ids=$(aws discovery describe-agents \
        --query 'agentConfigurations[*].agentId' \
        --output text --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -n "$agent_ids" ] && [ "$agent_ids" != "None" ]; then
        log "Stopping data collection for agents: $agent_ids"
        aws discovery stop-data-collection-by-agent-ids \
            --agent-ids $agent_ids --region "$AWS_REGION"
        success "Data collection stopped for all agents"
    else
        warning "No agents found or agents already stopped"
    fi
}

# Function to stop continuous export
stop_continuous_export() {
    log "Stopping continuous export..."
    
    if [ -n "$EXPORT_ID" ] && [ "$EXPORT_ID" != "None" ]; then
        aws discovery stop-continuous-export \
            --export-id "$EXPORT_ID" \
            --region "$AWS_REGION" 2>/dev/null || {
            warning "Failed to stop continuous export (may already be stopped)"
        }
        success "Continuous export stopped"
    else
        # Try to find and stop any active exports
        local active_exports=$(aws discovery describe-continuous-exports \
            --query 'descriptions[?status==`ACTIVE`].exportId' \
            --output text --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [ -n "$active_exports" ] && [ "$active_exports" != "None" ]; then
            for export_id in $active_exports; do
                aws discovery stop-continuous-export \
                    --export-id "$export_id" \
                    --region "$AWS_REGION"
                success "Stopped continuous export: $export_id"
            done
        else
            warning "No active continuous exports found"
        fi
    fi
}

# Function to delete application groups
delete_application_groups() {
    log "Deleting application groups..."
    
    if [ -n "$APP_ID" ] && [ "$APP_ID" != "None" ]; then
        aws discovery delete-applications \
            --configuration-ids "$APP_ID" \
            --region "$AWS_REGION" 2>/dev/null || {
            warning "Failed to delete application group (may already be deleted)"
        }
        success "Application group deleted"
    else
        # Try to find and delete any applications
        local app_ids=$(aws discovery list-applications \
            --query 'applications[*].applicationId' \
            --output text --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [ -n "$app_ids" ] && [ "$app_ids" != "None" ]; then
            for app_id in $app_ids; do
                aws discovery delete-applications \
                    --configuration-ids "$app_id" \
                    --region "$AWS_REGION" 2>/dev/null || {
                    warning "Failed to delete application: $app_id"
                }
                success "Deleted application: $app_id"
            done
        else
            warning "No applications found to delete"
        fi
    fi
}

# Function to delete CloudWatch Events rule
delete_cloudwatch_rule() {
    log "Deleting CloudWatch Events rule..."
    
    if aws events describe-rule --name "DiscoveryReportSchedule" >/dev/null 2>&1; then
        # Remove targets first
        local targets=$(aws events list-targets-by-rule \
            --rule "DiscoveryReportSchedule" \
            --query 'Targets[*].Id' --output text 2>/dev/null || echo "")
        
        if [ -n "$targets" ] && [ "$targets" != "None" ]; then
            aws events remove-targets \
                --rule "DiscoveryReportSchedule" \
                --ids $targets
            success "Removed targets from CloudWatch Events rule"
        fi
        
        # Delete the rule
        aws events delete-rule --name "DiscoveryReportSchedule"
        success "CloudWatch Events rule deleted"
    else
        warning "CloudWatch Events rule not found"
    fi
}

# Function to delete Athena database
delete_athena_database() {
    log "Deleting Athena database..."
    
    if aws athena get-database --catalog-name "AwsDataCatalog" \
        --database-name "discovery_analysis" >/dev/null 2>&1; then
        
        # List and delete all tables first
        local tables=$(aws athena list-table-metadata \
            --catalog-name "AwsDataCatalog" \
            --database-name "discovery_analysis" \
            --query 'TableMetadataList[*].Name' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$tables" ] && [ "$tables" != "None" ]; then
            for table in $tables; do
                local query_id=$(aws athena start-query-execution \
                    --query-string "DROP TABLE IF EXISTS discovery_analysis.${table}" \
                    --result-configuration "OutputLocation=s3://${DISCOVERY_BUCKET}/athena-results/" \
                    --query 'QueryExecutionId' --output text 2>/dev/null || echo "")
                
                if [ -n "$query_id" ]; then
                    aws athena wait query-execution-completed \
                        --query-execution-id "$query_id" 2>/dev/null || true
                    success "Deleted Athena table: $table"
                fi
            done
        fi
        
        # Delete the database
        local query_id=$(aws athena start-query-execution \
            --query-string "DROP DATABASE IF EXISTS discovery_analysis" \
            --result-configuration "OutputLocation=s3://${DISCOVERY_BUCKET}/athena-results/" \
            --query 'QueryExecutionId' --output text 2>/dev/null || echo "")
        
        if [ -n "$query_id" ]; then
            aws athena wait query-execution-completed \
                --query-execution-id "$query_id" 2>/dev/null || true
            success "Athena database deleted"
        fi
    else
        warning "Athena database not found"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if [ -n "$DISCOVERY_BUCKET" ] && aws s3api head-bucket --bucket "$DISCOVERY_BUCKET" 2>/dev/null; then
        # Delete all objects in the bucket
        aws s3 rm "s3://${DISCOVERY_BUCKET}" --recursive 2>/dev/null || {
            warning "Failed to delete some objects in S3 bucket"
        }
        
        # Delete all versions and delete markers
        aws s3api delete-objects --bucket "$DISCOVERY_BUCKET" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$DISCOVERY_BUCKET" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        aws s3api delete-objects --bucket "$DISCOVERY_BUCKET" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$DISCOVERY_BUCKET" \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "$DISCOVERY_BUCKET"
        success "S3 bucket deleted: $DISCOVERY_BUCKET"
    else
        warning "S3 bucket not found or already deleted"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    if aws iam get-role --role-name ApplicationDiscoveryServiceRole >/dev/null 2>&1; then
        # Detach all policies
        local policies=$(aws iam list-attached-role-policies \
            --role-name ApplicationDiscoveryServiceRole \
            --query 'AttachedPolicies[*].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$policies" ] && [ "$policies" != "None" ]; then
            for policy in $policies; do
                aws iam detach-role-policy \
                    --role-name ApplicationDiscoveryServiceRole \
                    --policy-arn "$policy"
                success "Detached policy: $policy"
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name ApplicationDiscoveryServiceRole
        success "IAM role deleted: ApplicationDiscoveryServiceRole"
    else
        warning "IAM role not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-state.json"
        "lifecycle-policy.json"
        "discovery-service-role-policy.json"
        "create-servers-table.sql"
        "migration-assessment.json"
        "discovery-automation.py"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            success "Removed: $file"
        fi
    done
}

# Function to display post-cleanup instructions
display_post_cleanup_instructions() {
    log "Cleanup completed successfully!"
    echo
    echo "==========================================="
    echo "POST-CLEANUP INSTRUCTIONS"
    echo "==========================================="
    echo
    echo "⚠️  MANUAL CLEANUP REQUIRED:"
    echo
    echo "1. UNINSTALL DISCOVERY AGENTS:"
    echo "   - Linux: sudo /opt/aws/discovery/bin/aws-discovery-daemon --stop"
    echo "   - Linux: sudo /opt/aws/discovery/bin/uninstall"
    echo "   - Windows: Use Add/Remove Programs to uninstall AWS Discovery Agent"
    echo
    echo "2. REMOVE AGENTLESS COLLECTORS:"
    echo "   - Power off and delete the Agentless Collector VM from vCenter"
    echo "   - Remove the OVA template if no longer needed"
    echo
    echo "3. VERIFY CLEANUP:"
    echo "   - Check AWS Migration Hub console for any remaining resources"
    echo "   - Verify no unexpected charges on your AWS bill"
    echo
    echo "4. MIGRATION HUB HOME REGION:"
    echo "   - Migration Hub home region ($MH_HOME_REGION) configuration remains"
    echo "   - This is shared across all migration tools and should not be removed"
    echo "   - unless you're completely done with all migration activities"
    echo
    echo "==========================================="
    echo "All AWS resources have been successfully removed!"
    echo "==========================================="
}

# Main cleanup function
main() {
    log "Starting AWS Application Discovery Service cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state
    load_deployment_state
    
    # Confirm destruction
    confirm_destruction
    
    # Stop services and delete resources
    stop_data_collection
    stop_continuous_export
    delete_application_groups
    delete_cloudwatch_rule
    delete_athena_database
    delete_s3_bucket
    delete_iam_role
    
    # Clean up local files
    cleanup_local_files
    
    # Display post-cleanup instructions
    display_post_cleanup_instructions
    
    success "Cleanup completed successfully!"
}

# Trap to handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"