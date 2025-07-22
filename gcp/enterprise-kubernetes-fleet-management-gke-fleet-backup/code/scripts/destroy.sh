#!/bin/bash

# Enterprise Kubernetes Fleet Management with GKE Fleet and Backup for GKE - Cleanup Script
# This script safely removes all resources created during deployment

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
}

# Function to print section headers
print_section() {
    echo
    print_status "$BLUE" "=========================================="
    print_status "$BLUE" "$1"
    print_status "$BLUE" "=========================================="
}

# Function to confirm destructive actions
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "$message [Y/n]: " response
            response=${response:-y}
        else
            read -rp "$message [y/N]: " response
            response=${response:-n}
        fi
        
        case $response in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) print_status "$YELLOW" "Please answer yes or no." ;;
        esac
    done
}

# Function to check if configuration exists
check_configuration() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_status "$RED" "❌ Configuration file not found: $CONFIG_FILE"
        print_status "$YELLOW" "This script requires the configuration file created during deployment."
        print_status "$YELLOW" "If you know the project IDs, you can create the config file manually:"
        cat <<EOF

Create $CONFIG_FILE with the following content:
BILLING_ACCOUNT="your-billing-account-id"
REGION="us-central1"
ZONE="us-central1-a"
FLEET_HOST_PROJECT_ID="your-fleet-host-project-id"
WORKLOAD_PROJECT_1="your-production-project-id"
WORKLOAD_PROJECT_2="your-staging-project-id"
RANDOM_SUFFIX="your-random-suffix"
FLEET_NAME="enterprise-fleet-your-suffix"
BACKUP_PLAN_NAME="fleet-backup-plan-your-suffix"
PROD_CLUSTER_NAME="prod-cluster-your-suffix"
STAGING_CLUSTER_NAME="staging-cluster-your-suffix"

EOF
        exit 1
    fi
    
    # Load configuration
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    print_status "$GREEN" "✅ Configuration loaded successfully"
    log "INFO" "Fleet Host Project: $FLEET_HOST_PROJECT_ID"
    log "INFO" "Production Project: $WORKLOAD_PROJECT_1"
    log "INFO" "Staging Project: $WORKLOAD_PROJECT_2"
}

# Function to display cleanup warning
display_cleanup_warning() {
    print_section "⚠️  DESTRUCTIVE ACTION WARNING"
    
    cat <<EOF
This script will permanently delete the following resources:

🗑️  Projects:
   - Fleet Host Project: $FLEET_HOST_PROJECT_ID
   - Production Project: $WORKLOAD_PROJECT_1
   - Staging Project: $WORKLOAD_PROJECT_2

🗑️  GKE Clusters:
   - Production Cluster: $PROD_CLUSTER_NAME
   - Staging Cluster: $STAGING_CLUSTER_NAME

🗑️  Backup Plans:
   - Production Backup Plan: ${BACKUP_PLAN_NAME}-prod
   - Staging Backup Plan: ${BACKUP_PLAN_NAME}-staging

🗑️  Fleet Configuration:
   - Fleet Memberships
   - Config Management Settings
   - IAM Service Accounts

💡 Note: All data, configurations, and resources will be permanently lost.
         This action cannot be undone.

EOF
}

# Function to remove sample applications
remove_sample_applications() {
    print_section "Removing Sample Applications and Resources"
    
    # Clean up production cluster resources
    if gcloud projects describe "$WORKLOAD_PROJECT_1" &>/dev/null; then
        print_status "$BLUE" "Cleaning up production cluster resources..."
        
        gcloud config set project "$WORKLOAD_PROJECT_1"
        
        # Get cluster credentials if cluster exists
        if gcloud container clusters describe "$PROD_CLUSTER_NAME" --region="$REGION" &>/dev/null; then
            if gcloud container clusters get-credentials "$PROD_CLUSTER_NAME" --region="$REGION" --quiet &>/dev/null; then
                # Remove production namespace and applications
                if kubectl get namespace production &>/dev/null; then
                    print_status "$BLUE" "  Removing production namespace..."
                    kubectl delete namespace production --ignore-not-found=true --timeout=300s
                fi
                
                # Remove Config Connector resources
                if kubectl get namespace cnrm-system &>/dev/null; then
                    print_status "$BLUE" "  Removing Config Connector resources..."
                    kubectl delete storagebucket --all -n cnrm-system --ignore-not-found=true --timeout=300s
                    kubectl delete namespace cnrm-system --ignore-not-found=true --timeout=300s
                fi
            else
                print_status "$YELLOW" "⚠️  Could not get production cluster credentials"
            fi
        else
            print_status "$YELLOW" "⚠️  Production cluster not found or already deleted"
        fi
    else
        print_status "$YELLOW" "⚠️  Production project not found or already deleted"
    fi
    
    # Clean up staging cluster resources
    if gcloud projects describe "$WORKLOAD_PROJECT_2" &>/dev/null; then
        print_status "$BLUE" "Cleaning up staging cluster resources..."
        
        gcloud config set project "$WORKLOAD_PROJECT_2"
        
        # Get cluster credentials if cluster exists
        if gcloud container clusters describe "$STAGING_CLUSTER_NAME" --region="$REGION" &>/dev/null; then
            if gcloud container clusters get-credentials "$STAGING_CLUSTER_NAME" --region="$REGION" --quiet &>/dev/null; then
                # Remove staging namespace and applications
                if kubectl get namespace staging &>/dev/null; then
                    print_status "$BLUE" "  Removing staging namespace..."
                    kubectl delete namespace staging --ignore-not-found=true --timeout=300s
                fi
            else
                print_status "$YELLOW" "⚠️  Could not get staging cluster credentials"
            fi
        else
            print_status "$YELLOW" "⚠️  Staging cluster not found or already deleted"
        fi
    else
        print_status "$YELLOW" "⚠️  Staging project not found or already deleted"
    fi
    
    print_status "$GREEN" "✅ Application resources cleaned up"
}

# Function to remove backup plans
remove_backup_plans() {
    print_section "Removing Backup Plans"
    
    if gcloud projects describe "$FLEET_HOST_PROJECT_ID" &>/dev/null; then
        gcloud config set project "$FLEET_HOST_PROJECT_ID"
        
        # List existing backup plans
        local backup_plans
        backup_plans=$(gcloud backup-dr backup-plans list --location="$REGION" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$backup_plans" ]]; then
            print_status "$BLUE" "Found backup plans to delete..."
            
            # Delete production backup plan
            if echo "$backup_plans" | grep -q "${BACKUP_PLAN_NAME}-prod"; then
                print_status "$BLUE" "  Deleting production backup plan..."
                if ! gcloud backup-dr backup-plans delete "${BACKUP_PLAN_NAME}-prod" \
                    --location="$REGION" \
                    --quiet; then
                    print_status "$YELLOW" "⚠️  Warning: Failed to delete production backup plan"
                fi
            fi
            
            # Delete staging backup plan
            if echo "$backup_plans" | grep -q "${BACKUP_PLAN_NAME}-staging"; then
                print_status "$BLUE" "  Deleting staging backup plan..."
                if ! gcloud backup-dr backup-plans delete "${BACKUP_PLAN_NAME}-staging" \
                    --location="$REGION" \
                    --quiet; then
                    print_status "$YELLOW" "⚠️  Warning: Failed to delete staging backup plan"
                fi
            fi
        else
            print_status "$YELLOW" "⚠️  No backup plans found"
        fi
    else
        print_status "$YELLOW" "⚠️  Fleet host project not found"
    fi
    
    print_status "$GREEN" "✅ Backup plans removed"
}

# Function to unregister clusters from fleet
unregister_clusters_from_fleet() {
    print_section "Unregistering Clusters from Fleet"
    
    if gcloud projects describe "$FLEET_HOST_PROJECT_ID" &>/dev/null; then
        gcloud config set project "$FLEET_HOST_PROJECT_ID"
        
        # List existing fleet memberships
        local memberships
        memberships=$(gcloud container fleet memberships list --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$memberships" ]]; then
            print_status "$BLUE" "Found fleet memberships to unregister..."
            
            # Unregister production cluster
            if echo "$memberships" | grep -q "$PROD_CLUSTER_NAME"; then
                print_status "$BLUE" "  Unregistering production cluster..."
                if ! gcloud container fleet memberships unregister "$PROD_CLUSTER_NAME" --quiet; then
                    print_status "$YELLOW" "⚠️  Warning: Failed to unregister production cluster"
                fi
            fi
            
            # Unregister staging cluster
            if echo "$memberships" | grep -q "$STAGING_CLUSTER_NAME"; then
                print_status "$BLUE" "  Unregistering staging cluster..."
                if ! gcloud container fleet memberships unregister "$STAGING_CLUSTER_NAME" --quiet; then
                    print_status "$YELLOW" "⚠️  Warning: Failed to unregister staging cluster"
                fi
            fi
        else
            print_status "$YELLOW" "⚠️  No fleet memberships found"
        fi
    else
        print_status "$YELLOW" "⚠️  Fleet host project not found"
    fi
    
    print_status "$GREEN" "✅ Clusters unregistered from fleet"
}

# Function to delete GKE clusters
delete_gke_clusters() {
    print_section "Deleting GKE Clusters"
    
    # Delete production cluster
    if gcloud projects describe "$WORKLOAD_PROJECT_1" &>/dev/null; then
        print_status "$BLUE" "Deleting production cluster..."
        
        if gcloud container clusters describe "$PROD_CLUSTER_NAME" --project="$WORKLOAD_PROJECT_1" --region="$REGION" &>/dev/null; then
            if ! gcloud container clusters delete "$PROD_CLUSTER_NAME" \
                --project="$WORKLOAD_PROJECT_1" \
                --region="$REGION" \
                --quiet; then
                print_status "$YELLOW" "⚠️  Warning: Failed to delete production cluster"
            else
                print_status "$GREEN" "✅ Production cluster deleted"
            fi
        else
            print_status "$YELLOW" "⚠️  Production cluster not found"
        fi
    else
        print_status "$YELLOW" "⚠️  Production project not found"
    fi
    
    # Delete staging cluster
    if gcloud projects describe "$WORKLOAD_PROJECT_2" &>/dev/null; then
        print_status "$BLUE" "Deleting staging cluster..."
        
        if gcloud container clusters describe "$STAGING_CLUSTER_NAME" --project="$WORKLOAD_PROJECT_2" --region="$REGION" &>/dev/null; then
            if ! gcloud container clusters delete "$STAGING_CLUSTER_NAME" \
                --project="$WORKLOAD_PROJECT_2" \
                --region="$REGION" \
                --quiet; then
                print_status "$YELLOW" "⚠️  Warning: Failed to delete staging cluster"
            else
                print_status "$GREEN" "✅ Staging cluster deleted"
            fi
        else
            print_status "$YELLOW" "⚠️  Staging cluster not found"
        fi
    else
        print_status "$YELLOW" "⚠️  Staging project not found"
    fi
}

# Function to remove IAM service accounts
remove_iam_service_accounts() {
    print_section "Removing IAM Service Accounts"
    
    # Remove fleet manager service account
    if gcloud projects describe "$FLEET_HOST_PROJECT_ID" &>/dev/null; then
        gcloud config set project "$FLEET_HOST_PROJECT_ID"
        
        local fleet_sa="fleet-manager@${FLEET_HOST_PROJECT_ID}.iam.gserviceaccount.com"
        if gcloud iam service-accounts describe "$fleet_sa" &>/dev/null; then
            print_status "$BLUE" "Removing fleet manager service account..."
            gcloud iam service-accounts delete "$fleet_sa" --quiet
        fi
    fi
    
    # Remove Config Connector service account
    if gcloud projects describe "$WORKLOAD_PROJECT_1" &>/dev/null; then
        gcloud config set project "$WORKLOAD_PROJECT_1"
        
        local cnrm_sa="cnrm-system@${WORKLOAD_PROJECT_1}.iam.gserviceaccount.com"
        if gcloud iam service-accounts describe "$cnrm_sa" &>/dev/null; then
            print_status "$BLUE" "Removing Config Connector service account..."
            gcloud iam service-accounts delete "$cnrm_sa" --quiet
        fi
    fi
    
    print_status "$GREEN" "✅ IAM service accounts removed"
}

# Function to delete projects
delete_projects() {
    print_section "Deleting Google Cloud Projects"
    
    local projects=("$FLEET_HOST_PROJECT_ID" "$WORKLOAD_PROJECT_1" "$WORKLOAD_PROJECT_2")
    local project_names=("Fleet Host Project" "Production Workload Project" "Staging Workload Project")
    
    for i in "${!projects[@]}"; do
        local project="${projects[$i]}"
        local name="${project_names[$i]}"
        
        if gcloud projects describe "$project" &>/dev/null; then
            print_status "$BLUE" "Deleting $name ($project)..."
            
            if ! gcloud projects delete "$project" --quiet; then
                print_status "$RED" "❌ Failed to delete project: $project"
                print_status "$YELLOW" "You may need to delete this project manually in the Cloud Console"
            else
                print_status "$GREEN" "✅ Deleted project: $project"
            fi
        else
            print_status "$YELLOW" "⚠️  Project $project not found or already deleted"
        fi
        
        # Small delay to avoid rate limiting
        sleep 2
    done
}

# Function to clean up local files
cleanup_local_files() {
    print_section "Cleaning Up Local Configuration"
    
    # Clean up environment variables and local files
    print_status "$BLUE" "Removing local configuration files..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        if confirm_action "Remove local configuration file ($CONFIG_FILE)?"; then
            rm -f "$CONFIG_FILE"
            print_status "$GREEN" "✅ Configuration file removed"
        else
            print_status "$YELLOW" "⚠️  Configuration file preserved"
        fi
    fi
    
    # Reset gcloud project configuration
    print_status "$BLUE" "Resetting gcloud configuration..."
    gcloud config unset project &>/dev/null || true
    
    print_status "$GREEN" "✅ Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    print_section "Verifying Cleanup"
    
    local cleanup_success=true
    
    # Check if projects still exist
    for project in "$FLEET_HOST_PROJECT_ID" "$WORKLOAD_PROJECT_1" "$WORKLOAD_PROJECT_2"; do
        if gcloud projects describe "$project" &>/dev/null; then
            print_status "$YELLOW" "⚠️  Project $project still exists"
            cleanup_success=false
        fi
    done
    
    if $cleanup_success; then
        print_status "$GREEN" "✅ All resources have been successfully removed"
    else
        print_status "$YELLOW" "⚠️  Some resources may still exist. Check the Cloud Console for any remaining resources."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    print_section "Cleanup Summary"
    
    cat <<EOF

🧹 Enterprise Kubernetes Fleet Management Cleanup Complete!

✅ Cleanup Actions Performed:
   🗑️  Sample applications and namespaces removed
   🗑️  Backup plans deleted
   🗑️  Clusters unregistered from fleet
   🗑️  GKE clusters deleted
   🗑️  IAM service accounts removed
   🗑️  Google Cloud projects deleted
   🗑️  Local configuration cleaned up

📋 Projects Removed:
   - Fleet Host Project: $FLEET_HOST_PROJECT_ID
   - Production Project: $WORKLOAD_PROJECT_1
   - Staging Project: $WORKLOAD_PROJECT_2

💡 Post-Cleanup Notes:
   - All billable resources have been removed
   - No ongoing charges should occur from this deployment
   - If you see any remaining resources in the Cloud Console, delete them manually
   - Project deletion may take a few minutes to complete fully

📄 Cleanup log: $LOG_FILE

Thank you for testing Enterprise Kubernetes Fleet Management! 🚀

EOF
}

# Function to handle partial cleanup mode
partial_cleanup_mode() {
    print_section "Partial Cleanup Mode"
    
    cat <<EOF
Select which resources to clean up:

1) Sample applications only
2) Backup plans only
3) Fleet memberships only
4) GKE clusters only
5) IAM service accounts only
6) Everything except projects
7) Full cleanup (default)
8) Cancel

EOF
    
    read -rp "Enter your choice [1-8]: " choice
    
    case $choice in
        1)
            remove_sample_applications
            ;;
        2)
            remove_backup_plans
            ;;
        3)
            unregister_clusters_from_fleet
            ;;
        4)
            delete_gke_clusters
            ;;
        5)
            remove_iam_service_accounts
            ;;
        6)
            remove_sample_applications
            remove_backup_plans
            unregister_clusters_from_fleet
            delete_gke_clusters
            remove_iam_service_accounts
            ;;
        7|"")
            return 1  # Continue with full cleanup
            ;;
        8)
            print_status "$YELLOW" "Cleanup cancelled"
            exit 0
            ;;
        *)
            print_status "$RED" "Invalid choice. Exiting."
            exit 1
            ;;
    esac
    
    print_status "$GREEN" "✅ Partial cleanup completed"
    exit 0
}

# Main execution function
main() {
    local partial_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --partial)
                partial_mode=true
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [OPTIONS]

Enterprise Kubernetes Fleet Management Cleanup Script

OPTIONS:
    --partial    Run in partial cleanup mode (select specific resources to clean)
    --help, -h   Show this help message

DESCRIPTION:
    This script removes all resources created by the deployment script including:
    - GKE clusters
    - Fleet registrations
    - Backup plans
    - IAM service accounts
    - Google Cloud projects
    - Local configuration files

WARNING:
    This is a destructive operation that cannot be undone.
    All data and configurations will be permanently lost.

EOF
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                print_status "$YELLOW" "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    print_status "$GREEN" "🧹 Starting Enterprise Kubernetes Fleet Management Cleanup"
    
    log "INFO" "Cleanup started by user: $(whoami)"
    log "INFO" "Script location: $SCRIPT_DIR"
    log "INFO" "Partial mode: $partial_mode"
    
    # Check configuration
    check_configuration
    
    # Display warning and get confirmation
    display_cleanup_warning
    
    if ! confirm_action "Are you sure you want to proceed with the cleanup?"; then
        print_status "$YELLOW" "Cleanup cancelled by user"
        exit 0
    fi
    
    # Handle partial cleanup mode
    if $partial_mode; then
        partial_cleanup_mode
    fi
    
    # Execute cleanup steps
    remove_sample_applications
    remove_backup_plans
    unregister_clusters_from_fleet
    delete_gke_clusters
    remove_iam_service_accounts
    delete_projects
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    print_status "$GREEN" "✅ Cleanup completed successfully!"
    log "INFO" "Cleanup completed successfully"
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] && [[ $exit_code -ne 130 ]]; then  # 130 is Ctrl+C
        print_status "$RED" "❌ Cleanup failed with exit code $exit_code"
        print_status "$YELLOW" "Check the log file for details: $LOG_FILE"
        print_status "$YELLOW" "Some resources may still exist and need manual cleanup"
    fi
}

trap cleanup_on_exit EXIT

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi