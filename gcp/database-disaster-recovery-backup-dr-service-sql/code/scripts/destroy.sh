#!/bin/bash

# Database Disaster Recovery with Backup and DR Service and Cloud SQL - Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper confirmation prompts and dependency handling.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for confirmation
confirm() {
    local message="$1"
    local response
    
    echo -e "${YELLOW}[CONFIRM]${NC} $message"
    read -p "Continue? (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to safe delete resource with retry
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    local max_retries="${4:-3}"
    local retry_count=0
    
    log "Attempting to delete $resource_type: $resource_name"
    
    while [ $retry_count -lt $max_retries ]; do
        if eval "$delete_command" >/dev/null 2>&1; then
            success "Deleted $resource_type: $resource_name"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                warning "Failed to delete $resource_type: $resource_name. Retrying in 10 seconds... ($retry_count/$max_retries)"
                sleep 10
            else
                warning "Failed to delete $resource_type: $resource_name after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local max_wait="${3:-300}" # Default 5 minutes
    local counter=0
    
    log "Waiting for $resource_name to be deleted..."
    
    while [ $counter -lt $max_wait ]; do
        if ! eval "$check_command" >/dev/null 2>&1; then
            success "$resource_name deleted successfully"
            return 0
        else
            echo -n "."
            sleep 5
            counter=$((counter + 5))
        fi
    done
    
    warning "$resource_name deletion timed out after $max_wait seconds"
    return 1
}

# Banner
echo "=================================================="
echo "  Database Disaster Recovery Cleanup Script"
echo "  GCP Cloud SQL + Backup and DR Service"
echo "=================================================="
echo ""

# Prerequisites Check
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command_exists gcloud; then
    error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 >/dev/null 2>&1; then
    error "Not authenticated with gcloud. Run 'gcloud auth login' first."
fi

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    error "No project set. Run 'gcloud config set project PROJECT_ID' first."
fi

success "Prerequisites check completed. Using project: $PROJECT_ID"

# Load configuration from deployment if available
CONFIG_FILE="deployment-config.env"
if [ -f "$CONFIG_FILE" ]; then
    log "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
    success "Configuration loaded successfully"
else
    warning "Configuration file not found. You'll need to provide resource names manually."
    
    # Prompt for resource information
    echo ""
    echo "Please provide the resource names to delete:"
    read -p "Primary DB Instance Name: " DB_INSTANCE_NAME
    read -p "DR Replica Name: " DR_REPLICA_NAME
    read -p "Primary Backup Vault Name: " BACKUP_VAULT_PRIMARY
    read -p "Secondary Backup Vault Name: " BACKUP_VAULT_SECONDARY
    read -p "Primary Region (default: us-central1): " PRIMARY_REGION
    read -p "Secondary Region (default: us-east1): " SECONDARY_REGION
    
    # Set defaults if empty
    PRIMARY_REGION="${PRIMARY_REGION:-us-central1}"
    SECONDARY_REGION="${SECONDARY_REGION:-us-east1}"
    BACKUP_PLAN_NAME="backup-plan-${DB_INSTANCE_NAME}"
    SCHEDULER_JOB_NAME="dr-validation-job"
fi

# Validate required variables
if [ -z "${DB_INSTANCE_NAME:-}" ] || [ -z "${DR_REPLICA_NAME:-}" ]; then
    error "Database instance names are required. Please provide them or ensure deployment-config.env exists."
fi

# Display resources to be deleted
echo ""
echo "=================================================="
echo "          RESOURCES TO BE DELETED"
echo "=================================================="
echo ""
echo "Project: $PROJECT_ID"
echo ""
echo "Cloud SQL Instances:"
echo "  Primary DB Instance: ${DB_INSTANCE_NAME} (Region: ${PRIMARY_REGION})"
echo "  DR Replica: ${DR_REPLICA_NAME} (Region: ${SECONDARY_REGION})"
echo ""
echo "Backup and DR Resources:"
echo "  Primary Backup Vault: ${BACKUP_VAULT_PRIMARY:-N/A}"
echo "  Secondary Backup Vault: ${BACKUP_VAULT_SECONDARY:-N/A}"
echo "  Backup Plan: ${BACKUP_PLAN_NAME:-N/A}"
echo ""
echo "Cloud Functions:"
echo "  orchestrate-disaster-recovery (Region: ${PRIMARY_REGION})"
echo "  validate-backups (Region: ${PRIMARY_REGION})"
echo ""
echo "Other Resources:"
echo "  Cloud Scheduler Job: ${SCHEDULER_JOB_NAME:-N/A}"
echo "  Pub/Sub Topic: disaster-recovery-alerts"
echo "  Pub/Sub Subscription: dr-function-trigger"
echo ""

# Final confirmation
echo -e "${RED}WARNING: This will permanently delete all disaster recovery resources!${NC}"
echo -e "${RED}WARNING: This action cannot be undone!${NC}"
echo ""

if ! confirm "Are you sure you want to delete ALL disaster recovery resources?"; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo ""
log "Starting cleanup process..."

# Step 1: Remove Cloud Functions and Scheduled Jobs
log "Removing Cloud Functions and scheduled jobs..."

# Delete Cloud Scheduler job
if [ -n "${SCHEDULER_JOB_NAME:-}" ]; then
    if gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$PRIMARY_REGION" >/dev/null 2>&1; then
        safe_delete "Cloud Scheduler Job" "$SCHEDULER_JOB_NAME" \
            "gcloud scheduler jobs delete '$SCHEDULER_JOB_NAME' --location='$PRIMARY_REGION' --quiet"
    else
        log "Cloud Scheduler job '$SCHEDULER_JOB_NAME' not found or already deleted"
    fi
fi

# Delete Cloud Functions
FUNCTIONS=("orchestrate-disaster-recovery" "validate-backups" "monitor-backup-replication")

for func in "${FUNCTIONS[@]}"; do
    if gcloud functions describe "$func" --region="$PRIMARY_REGION" >/dev/null 2>&1; then
        safe_delete "Cloud Function" "$func" \
            "gcloud functions delete '$func' --region='$PRIMARY_REGION' --quiet"
    else
        log "Cloud Function '$func' not found or already deleted"
    fi
done

success "Cloud Functions and scheduled jobs cleanup completed"

# Step 2: Remove Monitoring and Pub/Sub Resources
log "Removing monitoring and messaging resources..."

# Delete Pub/Sub subscription
if gcloud pubsub subscriptions describe dr-function-trigger >/dev/null 2>&1; then
    safe_delete "Pub/Sub Subscription" "dr-function-trigger" \
        "gcloud pubsub subscriptions delete dr-function-trigger --quiet"
else
    log "Pub/Sub subscription 'dr-function-trigger' not found or already deleted"
fi

# Delete Pub/Sub topic
if gcloud pubsub topics describe disaster-recovery-alerts >/dev/null 2>&1; then
    safe_delete "Pub/Sub Topic" "disaster-recovery-alerts" \
        "gcloud pubsub topics delete disaster-recovery-alerts --quiet"
else
    log "Pub/Sub topic 'disaster-recovery-alerts' not found or already deleted"
fi

# Remove monitoring alert policies
log "Removing monitoring alert policies..."
ALERT_POLICIES=$(gcloud alpha monitoring policies list \
    --filter="displayName:'Cloud SQL Primary Instance Health Alert'" \
    --format="value(name)" 2>/dev/null || true)

if [ -n "$ALERT_POLICIES" ]; then
    echo "$ALERT_POLICIES" | while read -r policy; do
        if [ -n "$policy" ]; then
            safe_delete "Monitoring Alert Policy" "$policy" \
                "gcloud alpha monitoring policies delete '$policy' --quiet"
        fi
    done
else
    log "No monitoring alert policies found"
fi

success "Monitoring and messaging resources cleanup completed"

# Step 3: Remove Backup Plans and Associations
log "Removing backup plans and associations..."

if [ -n "${BACKUP_PLAN_NAME:-}" ]; then
    # Remove backup plan associations first
    if gcloud backup-dr backup-plan-associations list \
        --location="$PRIMARY_REGION" \
        --filter="backupPlan:$BACKUP_PLAN_NAME" \
        --format="value(name)" >/dev/null 2>&1; then
        
        log "Removing backup plan associations..."
        ASSOCIATIONS=$(gcloud backup-dr backup-plan-associations list \
            --location="$PRIMARY_REGION" \
            --filter="backupPlan:$BACKUP_PLAN_NAME" \
            --format="value(name)" 2>/dev/null || true)
        
        if [ -n "$ASSOCIATIONS" ]; then
            echo "$ASSOCIATIONS" | while read -r association; do
                if [ -n "$association" ]; then
                    ASSOCIATION_NAME=$(basename "$association")
                    safe_delete "Backup Plan Association" "$ASSOCIATION_NAME" \
                        "gcloud backup-dr backup-plan-associations delete '$ASSOCIATION_NAME' --location='$PRIMARY_REGION' --quiet"
                fi
            done
        fi
    fi
    
    # Delete backup plans
    if gcloud backup-dr backup-plans describe "$BACKUP_PLAN_NAME" --location="$PRIMARY_REGION" >/dev/null 2>&1; then
        safe_delete "Backup Plan" "$BACKUP_PLAN_NAME" \
            "gcloud backup-dr backup-plans delete '$BACKUP_PLAN_NAME' --location='$PRIMARY_REGION' --quiet"
        
        # Wait for backup plan deletion
        wait_for_deletion \
            "gcloud backup-dr backup-plans describe '$BACKUP_PLAN_NAME' --location='$PRIMARY_REGION'" \
            "Backup Plan $BACKUP_PLAN_NAME"
    else
        log "Backup plan '$BACKUP_PLAN_NAME' not found or already deleted"
    fi
    
    # Delete secondary region backup plan if it exists
    BACKUP_PLAN_SECONDARY="backup-plan-${DR_REPLICA_NAME}"
    if gcloud backup-dr backup-plans describe "$BACKUP_PLAN_SECONDARY" --location="$SECONDARY_REGION" >/dev/null 2>&1; then
        safe_delete "Secondary Backup Plan" "$BACKUP_PLAN_SECONDARY" \
            "gcloud backup-dr backup-plans delete '$BACKUP_PLAN_SECONDARY' --location='$SECONDARY_REGION' --quiet"
    fi
fi

success "Backup plans and associations cleanup completed"

# Step 4: Remove Cloud SQL Instances
log "Removing Cloud SQL instances..."

# Delete DR replica first (dependencies)
if gcloud sql instances describe "$DR_REPLICA_NAME" >/dev/null 2>&1; then
    log "Deleting DR replica: $DR_REPLICA_NAME"
    safe_delete "Cloud SQL DR Replica" "$DR_REPLICA_NAME" \
        "gcloud sql instances delete '$DR_REPLICA_NAME' --quiet"
    
    # Wait for replica deletion
    wait_for_deletion \
        "gcloud sql instances describe '$DR_REPLICA_NAME'" \
        "DR Replica $DR_REPLICA_NAME" \
        600  # 10 minutes
else
    log "DR replica '$DR_REPLICA_NAME' not found or already deleted"
fi

# Remove deletion protection and delete primary instance
if gcloud sql instances describe "$DB_INSTANCE_NAME" >/dev/null 2>&1; then
    log "Removing deletion protection from primary instance..."
    if gcloud sql instances patch "$DB_INSTANCE_NAME" --no-deletion-protection >/dev/null 2>&1; then
        success "Deletion protection removed from $DB_INSTANCE_NAME"
    else
        warning "Failed to remove deletion protection from $DB_INSTANCE_NAME"
    fi
    
    log "Deleting primary Cloud SQL instance: $DB_INSTANCE_NAME"
    safe_delete "Cloud SQL Primary Instance" "$DB_INSTANCE_NAME" \
        "gcloud sql instances delete '$DB_INSTANCE_NAME' --quiet"
    
    # Wait for primary instance deletion
    wait_for_deletion \
        "gcloud sql instances describe '$DB_INSTANCE_NAME'" \
        "Primary Instance $DB_INSTANCE_NAME" \
        600  # 10 minutes
else
    log "Primary instance '$DB_INSTANCE_NAME' not found or already deleted"
fi

success "Cloud SQL instances cleanup completed"

# Step 5: Remove Backup Vaults
log "Removing backup vaults..."

# Note: Backup vaults can only be deleted if they don't contain any backups
# and the minimum retention period has passed

if [ -n "${BACKUP_VAULT_PRIMARY:-}" ]; then
    if gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_PRIMARY" --location="$PRIMARY_REGION" >/dev/null 2>&1; then
        log "Attempting to delete primary backup vault (may fail if backups exist)..."
        if safe_delete "Primary Backup Vault" "$BACKUP_VAULT_PRIMARY" \
            "gcloud backup-dr backup-vaults delete '$BACKUP_VAULT_PRIMARY' --location='$PRIMARY_REGION' --quiet"; then
            success "Primary backup vault deleted successfully"
        else
            warning "Primary backup vault could not be deleted. It may contain backups or be within retention period."
            warning "The vault will need to be deleted manually after retention period expires."
        fi
    else
        log "Primary backup vault '$BACKUP_VAULT_PRIMARY' not found or already deleted"
    fi
fi

if [ -n "${BACKUP_VAULT_SECONDARY:-}" ]; then
    if gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_SECONDARY" --location="$SECONDARY_REGION" >/dev/null 2>&1; then
        log "Attempting to delete secondary backup vault (may fail if backups exist)..."
        if safe_delete "Secondary Backup Vault" "$BACKUP_VAULT_SECONDARY" \
            "gcloud backup-dr backup-vaults delete '$BACKUP_VAULT_SECONDARY' --location='$SECONDARY_REGION' --quiet"; then
            success "Secondary backup vault deleted successfully"
        else
            warning "Secondary backup vault could not be deleted. It may contain backups or be within retention period."
            warning "The vault will need to be deleted manually after retention period expires."
        fi
    else
        log "Secondary backup vault '$BACKUP_VAULT_SECONDARY' not found or already deleted"
    fi
fi

success "Backup vaults cleanup completed"

# Step 6: Clean up local files
log "Cleaning up local files..."

# Remove configuration file
if [ -f "$CONFIG_FILE" ]; then
    rm -f "$CONFIG_FILE"
    success "Removed configuration file: $CONFIG_FILE"
fi

# Remove any function directories that might exist
if [ -d "dr-functions" ]; then
    rm -rf "dr-functions"
    success "Removed function directory: dr-functions"
fi

# Remove any temporary files
rm -f monitoring-policy.json 2>/dev/null || true

success "Local files cleanup completed"

# Final verification
log "Performing final verification..."

# Check if major resources still exist
REMAINING_RESOURCES=0

# Check Cloud SQL instances
if gcloud sql instances describe "$DB_INSTANCE_NAME" >/dev/null 2>&1; then
    warning "Primary Cloud SQL instance '$DB_INSTANCE_NAME' still exists"
    REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
fi

if gcloud sql instances describe "$DR_REPLICA_NAME" >/dev/null 2>&1; then
    warning "DR replica '$DR_REPLICA_NAME' still exists"
    REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
fi

# Check backup vaults
if [ -n "${BACKUP_VAULT_PRIMARY:-}" ] && gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_PRIMARY" --location="$PRIMARY_REGION" >/dev/null 2>&1; then
    warning "Primary backup vault '$BACKUP_VAULT_PRIMARY' still exists"
    REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
fi

if [ -n "${BACKUP_VAULT_SECONDARY:-}" ] && gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_SECONDARY" --location="$SECONDARY_REGION" >/dev/null 2>&1; then
    warning "Secondary backup vault '$BACKUP_VAULT_SECONDARY' still exists"
    REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
fi

# Check Cloud Functions
FUNCTIONS=("orchestrate-disaster-recovery" "validate-backups")
for func in "${FUNCTIONS[@]}"; do
    if gcloud functions describe "$func" --region="$PRIMARY_REGION" >/dev/null 2>&1; then
        warning "Cloud Function '$func' still exists"
        REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
    fi
done

echo ""
echo "=================================================="
if [ $REMAINING_RESOURCES -eq 0 ]; then
    echo "        CLEANUP COMPLETED SUCCESSFULLY"
    echo "=================================================="
    echo ""
    success "All disaster recovery resources have been removed"
    echo ""
    echo "Note: Some resources like backup data may be retained based on"
    echo "retention policies and cannot be immediately deleted."
else
    echo "        CLEANUP COMPLETED WITH WARNINGS"
    echo "=================================================="
    echo ""
    warning "$REMAINING_RESOURCES resources could not be deleted"
    echo ""
    echo "This is normal for backup vaults with active backups."
    echo "These resources will need to be deleted manually after"
    echo "retention periods expire or backups are manually removed."
fi

echo ""
echo "Cleanup Summary:"
echo "  ✅ Cloud Functions removed"
echo "  ✅ Cloud Scheduler jobs removed" 
echo "  ✅ Pub/Sub resources removed"
echo "  ✅ Monitoring policies removed"
echo "  ✅ Backup plans removed"
if [ $REMAINING_RESOURCES -eq 0 ]; then
    echo "  ✅ Cloud SQL instances removed"
    echo "  ✅ Backup vaults removed"
else
    echo "  ⚠️  Some resources remain (see warnings above)"
fi
echo "  ✅ Local files cleaned up"
echo ""

if [ $REMAINING_RESOURCES -gt 0 ]; then
    echo "To check remaining resources later, run:"
    echo "  gcloud sql instances list"
    echo "  gcloud backup-dr backup-vaults list --location=$PRIMARY_REGION"
    echo "  gcloud backup-dr backup-vaults list --location=$SECONDARY_REGION"
    echo ""
fi

success "Cleanup process completed"
echo ""