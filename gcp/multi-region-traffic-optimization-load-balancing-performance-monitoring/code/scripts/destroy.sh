#!/bin/bash

# Destroy Multi-Region Traffic Optimization Infrastructure
# This script safely removes all resources created by the deploy.sh script

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
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handler (non-fatal for cleanup)
error_continue() {
    log_warning "Non-fatal error at line $1, continuing cleanup..."
}

trap 'error_continue $LINENO' ERR

# Display banner
echo -e "${RED}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    GCP Multi-Region Infrastructure Cleanup                   ║
║                           ⚠️  DESTRUCTIVE OPERATION ⚠️                        ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "Google Cloud CLI (gcloud) is not installed."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
    exit 1
fi

log_success "Prerequisites check completed"

# Load deployment information if available
if [[ -f "deployment-info.txt" ]]; then
    log "Loading deployment information from deployment-info.txt..."
    
    # Extract project ID and random suffix from deployment info
    PROJECT_ID=$(grep "Project ID:" deployment-info.txt | cut -d' ' -f3)
    RANDOM_SUFFIX=$(grep "Random Suffix:" deployment-info.txt | cut -d' ' -f3)
    
    if [[ -n "$PROJECT_ID" && -n "$RANDOM_SUFFIX" ]]; then
        log "Found deployment info - Project: ${PROJECT_ID}, Suffix: ${RANDOM_SUFFIX}"
    else
        log_warning "Could not parse deployment info completely"
    fi
else
    log_warning "deployment-info.txt not found. You'll need to provide project and resource details manually."
fi

# Interactive configuration if deployment info not available
if [[ -z "${PROJECT_ID:-}" ]]; then
    echo
    log "Please provide the project ID to clean up:"
    read -p "Project ID: " PROJECT_ID
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required for cleanup"
        exit 1
    fi
fi

if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
    echo
    log "Please provide the random suffix used during deployment:"
    read -p "Random suffix (e.g., a1b2c3): " RANDOM_SUFFIX
    
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        log_error "Random suffix is required to identify resources"
        exit 1
    fi
fi

# Set region variables
export REGION_US="${REGION_US:-us-central1}"
export REGION_EU="${REGION_EU:-europe-west1}"
export REGION_APAC="${REGION_APAC:-asia-southeast1}"
export ZONE_US="${ZONE_US:-us-central1-a}"
export ZONE_EU="${ZONE_EU:-europe-west1-b}"
export ZONE_APAC="${ZONE_APAC:-asia-southeast1-a}"

log "Configuration:"
log "  Project ID: ${PROJECT_ID}"
log "  Random Suffix: ${RANDOM_SUFFIX}"
log "  Regions: US(${REGION_US}), EU(${REGION_EU}), APAC(${REGION_APAC})"

# Set project
gcloud config set project "${PROJECT_ID}" || {
    log_error "Failed to set project. Please verify the project ID."
    exit 1
}

# Warning and confirmation
echo
echo -e "${RED}⚠️  WARNING: This will permanently delete all resources created by the deployment! ⚠️${NC}"
echo -e "${RED}This includes:${NC}"
echo -e "${RED}  - Global Load Balancer and all associated components${NC}"
echo -e "${RED}  - All Compute Engine instances and instance groups${NC}"
echo -e "${RED}  - VPC network and firewall rules${NC}"
echo -e "${RED}  - Monitoring and connectivity tests${NC}"
echo -e "${RED}  - ALL OTHER RESOURCES in project ${PROJECT_ID}${NC}"
echo
echo -e "${YELLOW}Type 'DELETE' (in capitals) to confirm destruction:${NC}"
read -p "> " confirmation

if [[ "$confirmation" != "DELETE" ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo
log "Starting cleanup process..."

# Function to safely delete resources
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local extra_args="${3:-}"
    
    log "Attempting to delete ${resource_type}: ${resource_name}"
    
    if eval "gcloud compute ${resource_type} delete ${resource_name} ${extra_args} --quiet --project=${PROJECT_ID}" 2>/dev/null; then
        log_success "Deleted ${resource_type}: ${resource_name}"
    else
        log_warning "Failed to delete ${resource_type}: ${resource_name} (may not exist)"
    fi
}

# Function to safely delete non-compute resources
safe_delete_other() {
    local command="$1"
    local description="$2"
    
    log "Attempting to delete ${description}"
    
    if eval "${command}" 2>/dev/null; then
        log_success "Deleted ${description}"
    else
        log_warning "Failed to delete ${description} (may not exist)"
    fi
}

# Step 1: Remove Monitoring and Network Intelligence Resources
log "Step 1: Removing monitoring and network intelligence resources..."

# Remove uptime checks
safe_delete_other "gcloud alpha monitoring uptime delete global-app-uptime-${RANDOM_SUFFIX} --quiet --project=${PROJECT_ID}" "uptime check"

# Remove connectivity tests
safe_delete_other "gcloud network-management connectivity-tests delete us-to-eu-test --quiet --project=${PROJECT_ID}" "US-EU connectivity test"
safe_delete_other "gcloud network-management connectivity-tests delete us-to-apac-test --quiet --project=${PROJECT_ID}" "US-APAC connectivity test"

log_success "Monitoring and network intelligence resources cleanup completed"

# Step 2: Remove Load Balancer Components (in correct order)
log "Step 2: Removing load balancer components..."

# Remove forwarding rule first
safe_delete "forwarding-rules" "global-http-rule-${RANDOM_SUFFIX}" "--global"

# Remove target proxy
safe_delete "target-http-proxies" "global-http-proxy-${RANDOM_SUFFIX}" ""

# Remove URL map
safe_delete "url-maps" "global-url-map-${RANDOM_SUFFIX}" "--global"

log_success "Load balancer components cleanup completed"

# Step 3: Remove Backend Services and Health Checks
log "Step 3: Removing backend services and health checks..."

# Remove backend service (this will automatically remove CDN configuration)
safe_delete "backend-services" "global-backend-${RANDOM_SUFFIX}" "--global"

# Remove health check
safe_delete "health-checks" "global-health-check-${RANDOM_SUFFIX}" ""

log_success "Backend services and health checks cleanup completed"

# Step 4: Remove Compute Resources
log "Step 4: Removing compute resources..."

# Remove managed instance groups
safe_delete "instance-groups" "managed delete us-ig-${RANDOM_SUFFIX}" "--zone=${ZONE_US}"
safe_delete "instance-groups" "managed delete eu-ig-${RANDOM_SUFFIX}" "--zone=${ZONE_EU}"
safe_delete "instance-groups" "managed delete apac-ig-${RANDOM_SUFFIX}" "--zone=${ZONE_APAC}"

# Wait a moment for instance groups to be deleted
log "Waiting for instance groups to be fully deleted..."
sleep 30

# Remove instance template
safe_delete "instance-templates" "app-template-${RANDOM_SUFFIX}" ""

log_success "Compute resources cleanup completed"

# Step 5: Remove Network Resources
log "Step 5: Removing network resources..."

# Remove firewall rules
safe_delete "firewall-rules" "allow-http-https" ""
safe_delete "firewall-rules" "allow-health-checks" ""

# Remove subnets
safe_delete "networks" "subnets delete us-subnet" "--region=${REGION_US}"
safe_delete "networks" "subnets delete eu-subnet" "--region=${REGION_EU}"
safe_delete "networks" "subnets delete apac-subnet" "--region=${REGION_APAC}"

# Wait for subnets to be deleted
log "Waiting for subnets to be fully deleted..."
sleep 15

# Remove VPC network
safe_delete "networks" "global-app-vpc" ""

log_success "Network resources cleanup completed"

# Step 6: Clean up local files
log "Step 6: Cleaning up local files..."

# Remove temporary and deployment files
if [[ -f "startup-script.sh" ]]; then
    rm -f startup-script.sh
    log_success "Removed startup-script.sh"
fi

if [[ -f "deployment-info.txt" ]]; then
    echo
    read -p "$(echo -e ${YELLOW}Do you want to remove deployment-info.txt? [y/N]: ${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f deployment-info.txt
        log_success "Removed deployment-info.txt"
    else
        log "Kept deployment-info.txt for reference"
    fi
fi

# Step 7: Optional Project Deletion
echo
log "Checking if this is a dedicated project for this recipe..."

# Check if project name suggests it was created for this recipe
if [[ "$PROJECT_ID" =~ ^traffic-optimization-.* ]]; then
    echo
    echo -e "${YELLOW}This appears to be a dedicated project created for this recipe.${NC}"
    echo -e "${YELLOW}Would you like to delete the entire project? This will remove ALL resources and cannot be undone.${NC}"
    echo
    read -p "$(echo -e ${RED}Delete entire project ${PROJECT_ID}? [y/N]: ${NC})" -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo
        echo -e "${RED}Final confirmation: Type 'DELETE PROJECT' to delete the entire project:${NC}"
        read -p "> " project_confirmation
        
        if [[ "$project_confirmation" == "DELETE PROJECT" ]]; then
            log "Deleting project ${PROJECT_ID}..."
            
            # Schedule project for deletion
            if gcloud projects delete "${PROJECT_ID}" --quiet; then
                log_success "Project ${PROJECT_ID} scheduled for deletion"
                log "Note: Project deletion may take several minutes to complete"
            else
                log_error "Failed to delete project ${PROJECT_ID}"
            fi
        else
            log "Project deletion cancelled"
        fi
    else
        log "Project kept - only individual resources were deleted"
    fi
else
    log "Project appears to be an existing project - individual resources deleted only"
fi

# Verification step
log "Performing verification..."

# Check for remaining resources
log "Checking for any remaining resources..."

REMAINING_INSTANCES=$(gcloud compute instances list --filter="name~.*${RANDOM_SUFFIX}.*" --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null | wc -l)
REMAINING_GROUPS=$(gcloud compute instance-groups list --filter="name~.*${RANDOM_SUFFIX}.*" --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null | wc -l)
REMAINING_LB=$(gcloud compute forwarding-rules list --filter="name~.*${RANDOM_SUFFIX}.*" --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null | wc -l)

if [[ $REMAINING_INSTANCES -eq 0 && $REMAINING_GROUPS -eq 0 && $REMAINING_LB -eq 0 ]]; then
    log_success "Verification complete: No remaining resources found"
else
    log_warning "Some resources may still exist. Check manually if needed:"
    log_warning "  Instances: $REMAINING_INSTANCES"
    log_warning "  Instance Groups: $REMAINING_GROUPS"
    log_warning "  Load Balancers: $REMAINING_LB"
fi

# Final summary
echo
log_success "Cleanup process completed!"
echo -e "${GREEN}"
cat << EOF
╔══════════════════════════════════════════════════════════════════════════════╗
║                            CLEANUP SUMMARY                                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ ✅ Load balancer components removed                                           ║
║ ✅ Backend services and health checks removed                                 ║
║ ✅ Compute instances and groups removed                                       ║
║ ✅ Network resources removed                                                  ║
║ ✅ Monitoring and connectivity tests removed                                  ║
║                                                                              ║
║ Project: ${PROJECT_ID}                              ║
║                                                                              ║
║ Note: It may take a few minutes for all resources to be fully removed       ║
║       from the Google Cloud Console.                                        ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Cost monitoring reminder
echo -e "${YELLOW}"
cat << EOF
💡 Cost Monitoring Reminder:
   - Check your billing dashboard to verify no unexpected charges
   - Resources are typically billed until they are fully deleted
   - Some resources may have a small delay before deletion completes
   
   Monitor your billing at: https://console.cloud.google.com/billing
EOF
echo -e "${NC}"

log "All cleanup operations completed successfully!"

exit 0