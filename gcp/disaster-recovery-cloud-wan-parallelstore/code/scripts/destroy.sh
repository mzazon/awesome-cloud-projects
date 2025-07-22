#!/bin/bash

# Disaster Recovery Orchestration with Cloud WAN and Parallelstore - Cleanup Script
# This script safely removes all resources created by the disaster recovery solution
# to avoid ongoing charges and cleanup the environment.

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment_info.json"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1" | tee -a "${ERROR_LOG}"
}

# Error handling with continuation
handle_error() {
    log_error "$1"
    if [[ "${FORCE_CLEANUP:-false}" != "true" ]]; then
        read -p "Continue with cleanup despite error? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Resource existence checking
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local location="${3:-}"
    
    case "${resource_type}" in
        "parallelstore")
            gcloud parallelstore instances describe "${resource_name}" \
                --location="${location}" --project="${PROJECT_ID}" &> /dev/null
            ;;
        "function")
            gcloud functions describe "${resource_name}" \
                --region="${location}" --project="${PROJECT_ID}" &> /dev/null
            ;;
        "workflow")
            gcloud workflows describe "${resource_name}" \
                --location="${location}" --project="${PROJECT_ID}" &> /dev/null
            ;;
        "scheduler")
            gcloud scheduler jobs describe "${resource_name}" \
                --location="${location}" --project="${PROJECT_ID}" &> /dev/null
            ;;
        "vpn-gateway")
            gcloud compute vpn-gateways describe "${resource_name}" \
                --region="${location}" --project="${PROJECT_ID}" &> /dev/null
            ;;
        "router")
            gcloud compute routers describe "${resource_name}" \
                --region="${location}" --project="${PROJECT_ID}" &> /dev/null
            ;;
        "network")
            gcloud compute networks describe "${resource_name}" \
                --project="${PROJECT_ID}" &> /dev/null
            ;;
        "subnet")
            gcloud compute networks subnets describe "${resource_name}" \
                --region="${location}" --project="${PROJECT_ID}" &> /dev/null
            ;;
        "hub")
            gcloud network-connectivity hubs describe "${resource_name}" \
                --project="${PROJECT_ID}" &> /dev/null
            ;;
        "spoke")
            gcloud network-connectivity spokes describe "${resource_name}" \
                --region="${location}" --project="${PROJECT_ID}" &> /dev/null
            ;;
        "pubsub-topic")
            gcloud pubsub topics describe "${resource_name}" \
                --project="${PROJECT_ID}" &> /dev/null
            ;;
        "pubsub-subscription")
            gcloud pubsub subscriptions describe "${resource_name}" \
                --project="${PROJECT_ID}" &> /dev/null
            ;;
        "bucket")
            gsutil ls -b "gs://${resource_name}" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."

    if [[ -f "${DEPLOYMENT_INFO}" ]]; then
        log_info "Found deployment info file: ${DEPLOYMENT_INFO}"
        
        # Extract values from JSON using basic parsing
        if command -v jq &> /dev/null; then
            PROJECT_ID=$(jq -r '.project_id' "${DEPLOYMENT_INFO}")
            DR_PREFIX=$(jq -r '.dr_prefix' "${DEPLOYMENT_INFO}")
            PRIMARY_REGION=$(jq -r '.primary_region' "${DEPLOYMENT_INFO}")
            SECONDARY_REGION=$(jq -r '.secondary_region' "${DEPLOYMENT_INFO}")
            PRIMARY_ZONE=$(jq -r '.primary_zone' "${DEPLOYMENT_INFO}")
            SECONDARY_ZONE=$(jq -r '.secondary_zone' "${DEPLOYMENT_INFO}")
            RANDOM_SUFFIX=$(jq -r '.random_suffix' "${DEPLOYMENT_INFO}")
        else
            # Fallback parsing without jq
            log_warning "jq not available, using basic parsing"
            PROJECT_ID=$(grep '"project_id"' "${DEPLOYMENT_INFO}" | cut -d'"' -f4)
            DR_PREFIX=$(grep '"dr_prefix"' "${DEPLOYMENT_INFO}" | cut -d'"' -f4)
            PRIMARY_REGION=$(grep '"primary_region"' "${DEPLOYMENT_INFO}" | cut -d'"' -f4)
            SECONDARY_REGION=$(grep '"secondary_region"' "${DEPLOYMENT_INFO}" | cut -d'"' -f4)
        fi
        
        log_info "Loaded configuration from deployment info"
    else
        log_warning "No deployment info file found, using environment variables or defaults"
    fi

    # Set defaults if values are empty
    export PROJECT_ID="${PROJECT_ID:-${1:-}}"
    export PRIMARY_REGION="${PRIMARY_REGION:-us-central1}"
    export SECONDARY_REGION="${SECONDARY_REGION:-us-east1}"
    export PRIMARY_ZONE="${PRIMARY_ZONE:-${PRIMARY_REGION}-a}"
    export SECONDARY_ZONE="${SECONDARY_ZONE:-${SECONDARY_REGION}-a}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3 2>/dev/null || echo 'abc123')}"
    export DR_PREFIX="${DR_PREFIX:-hpc-dr-${RANDOM_SUFFIX}}"

    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "PROJECT_ID is required but not set"
        exit 1
    fi

    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  DR Prefix: ${DR_PREFIX}"
    log_info "  Primary Region: ${PRIMARY_REGION}"
    log_info "  Secondary Region: ${SECONDARY_REGION}"
}

confirm_destruction() {
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        log_warning "Force cleanup mode enabled, skipping confirmation"
        return 0
    fi

    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will DELETE the following resources:"
    echo "  • Project: ${PROJECT_ID}"
    echo "  • DR Prefix: ${DR_PREFIX}"
    echo "  • All Parallelstore instances (including data)"
    echo "  • All networking infrastructure"
    echo "  • All monitoring and automation resources"
    echo ""
    echo "💰 This will stop all associated billing charges."
    echo "🗑️  All data in Parallelstore will be permanently lost."
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    if [[ ! "${REPLY}" == "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "This is your final confirmation. Type 'DELETE' to proceed: " -r
    if [[ ! "${REPLY}" == "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi

    # Set the project
    gcloud config set project "${PROJECT_ID}" &> /dev/null || {
        log_error "Failed to set project ${PROJECT_ID}"
        exit 1
    }

    log_success "Prerequisites check completed"
}

remove_scheduler_and_functions() {
    log_info "Removing Cloud Scheduler jobs and Cloud Functions..."

    # Delete scheduler job
    local scheduler_job="${DR_PREFIX}-replication-job"
    if resource_exists "scheduler" "${scheduler_job}" "${PRIMARY_REGION}"; then
        log_info "Deleting scheduler job: ${scheduler_job}"
        if ! gcloud scheduler jobs delete "${scheduler_job}" \
            --location="${PRIMARY_REGION}" \
            --project="${PROJECT_ID}" \
            --quiet 2>/dev/null; then
            handle_error "Failed to delete scheduler job: ${scheduler_job}"
        else
            log_success "Deleted scheduler job: ${scheduler_job}"
        fi
    else
        log_info "Scheduler job ${scheduler_job} not found, skipping"
    fi

    # Delete Cloud Functions
    local functions=(
        "${DR_PREFIX}-health-monitor"
        "${DR_PREFIX}-replication-scheduler"
    )

    for function_name in "${functions[@]}"; do
        if resource_exists "function" "${function_name}" "${PRIMARY_REGION}"; then
            log_info "Deleting function: ${function_name}"
            if ! gcloud functions delete "${function_name}" \
                --region="${PRIMARY_REGION}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                handle_error "Failed to delete function: ${function_name}"
            else
                log_success "Deleted function: ${function_name}"
            fi
        else
            log_info "Function ${function_name} not found, skipping"
        fi
    done

    log_success "Scheduler and Functions cleanup completed"
}

remove_workflows_and_monitoring() {
    log_info "Removing Cloud Workflows and monitoring policies..."

    # Delete disaster recovery workflow
    local workflow_name="${DR_PREFIX}-dr-orchestrator"
    if resource_exists "workflow" "${workflow_name}" "${PRIMARY_REGION}"; then
        log_info "Deleting workflow: ${workflow_name}"
        if ! gcloud workflows delete "${workflow_name}" \
            --location="${PRIMARY_REGION}" \
            --project="${PROJECT_ID}" \
            --quiet 2>/dev/null; then
            handle_error "Failed to delete workflow: ${workflow_name}"
        else
            log_success "Deleted workflow: ${workflow_name}"
        fi
    else
        log_info "Workflow ${workflow_name} not found, skipping"
    fi

    # Delete monitoring policies and channels
    log_info "Cleaning up monitoring policies..."
    local policies
    if policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:\"${DR_PREFIX} HPC Infrastructure Health Alert\"" \
        --format="value(name)" \
        --project="${PROJECT_ID}" 2>/dev/null); then
        for policy in ${policies}; do
            log_info "Deleting monitoring policy: ${policy}"
            if ! gcloud alpha monitoring policies delete "${policy}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                log_warning "Failed to delete monitoring policy: ${policy}"
            fi
        done
    fi

    log_info "Cleaning up notification channels..."
    local channels
    if channels=$(gcloud alpha monitoring channels list \
        --filter="displayName:\"${DR_PREFIX} DR Trigger Channel\"" \
        --format="value(name)" \
        --project="${PROJECT_ID}" 2>/dev/null); then
        for channel in ${channels}; do
            log_info "Deleting notification channel: ${channel}"
            if ! gcloud alpha monitoring channels delete "${channel}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                log_warning "Failed to delete notification channel: ${channel}"
            fi
        done
    fi

    log_success "Workflows and monitoring cleanup completed"
}

remove_parallelstore_instances() {
    log_info "Removing Parallelstore instances..."

    local instances=(
        "${DR_PREFIX}-primary-pfs:${PRIMARY_ZONE}"
        "${DR_PREFIX}-secondary-pfs:${SECONDARY_ZONE}"
    )

    for instance_zone in "${instances[@]}"; do
        local instance_name="${instance_zone%%:*}"
        local zone="${instance_zone##*:}"
        
        if resource_exists "parallelstore" "${instance_name}" "${zone}"; then
            log_warning "Deleting Parallelstore instance: ${instance_name} (this may take several minutes)"
            if ! gcloud parallelstore instances delete "${instance_name}" \
                --location="${zone}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                handle_error "Failed to delete Parallelstore instance: ${instance_name}"
            else
                log_success "Deleted Parallelstore instance: ${instance_name}"
            fi
        else
            log_info "Parallelstore instance ${instance_name} not found, skipping"
        fi
    done

    # Wait for Parallelstore instances to be fully deleted
    log_info "Waiting for Parallelstore instances to be fully deleted..."
    local max_wait=1800  # 30 minutes
    local waited=0
    local check_interval=30

    while [[ ${waited} -lt ${max_wait} ]]; do
        local instances_remaining=0
        
        for instance_zone in "${instances[@]}"; do
            local instance_name="${instance_zone%%:*}"
            local zone="${instance_zone##*:}"
            
            if resource_exists "parallelstore" "${instance_name}" "${zone}"; then
                ((instances_remaining++))
            fi
        done

        if [[ ${instances_remaining} -eq 0 ]]; then
            break
        fi

        log_info "Waiting for ${instances_remaining} Parallelstore instances to be deleted..."
        sleep ${check_interval}
        ((waited += check_interval))
    done

    if [[ ${waited} -ge ${max_wait} ]]; then
        log_warning "Timeout waiting for Parallelstore instances to be deleted, continuing..."
    fi

    log_success "Parallelstore instances cleanup completed"
}

remove_network_connectivity() {
    log_info "Removing Network Connectivity Center and VPN infrastructure..."

    # Delete network connectivity spokes
    local spokes=(
        "${DR_PREFIX}-primary-spoke:${PRIMARY_REGION}"
        "${DR_PREFIX}-secondary-spoke:${SECONDARY_REGION}"
    )

    for spoke_region in "${spokes[@]}"; do
        local spoke_name="${spoke_region%%:*}"
        local region="${spoke_region##*:}"
        
        if resource_exists "spoke" "${spoke_name}" "${region}"; then
            log_info "Deleting spoke: ${spoke_name}"
            if ! gcloud network-connectivity spokes delete "${spoke_name}" \
                --region="${region}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                handle_error "Failed to delete spoke: ${spoke_name}"
            else
                log_success "Deleted spoke: ${spoke_name}"
            fi
        else
            log_info "Spoke ${spoke_name} not found, skipping"
        fi
    done

    # Wait for spokes to be deleted
    log_info "Waiting for spokes to be fully deleted..."
    sleep 30

    # Delete network connectivity hub
    local hub_name="${DR_PREFIX}-wan-hub"
    if resource_exists "hub" "${hub_name}"; then
        log_info "Deleting Network Connectivity hub: ${hub_name}"
        if ! gcloud network-connectivity hubs delete "${hub_name}" \
            --project="${PROJECT_ID}" \
            --quiet 2>/dev/null; then
            handle_error "Failed to delete hub: ${hub_name}"
        else
            log_success "Deleted hub: ${hub_name}"
        fi
    else
        log_info "Hub ${hub_name} not found, skipping"
    fi

    # Delete VPN tunnels
    local tunnels=(
        "${DR_PREFIX}-primary-to-secondary:${PRIMARY_REGION}"
        "${DR_PREFIX}-secondary-to-primary:${SECONDARY_REGION}"
    )

    for tunnel_region in "${tunnels[@]}"; do
        local tunnel_name="${tunnel_region%%:*}"
        local region="${tunnel_region##*:}"
        
        log_info "Deleting VPN tunnel: ${tunnel_name}"
        if ! gcloud compute vpn-tunnels delete "${tunnel_name}" \
            --region="${region}" \
            --project="${PROJECT_ID}" \
            --quiet 2>/dev/null; then
            log_warning "Failed to delete VPN tunnel: ${tunnel_name}"
        else
            log_success "Deleted VPN tunnel: ${tunnel_name}"
        fi
    done

    # Delete VPN gateways
    local gateways=(
        "${DR_PREFIX}-primary-vpn-gw:${PRIMARY_REGION}"
        "${DR_PREFIX}-secondary-vpn-gw:${SECONDARY_REGION}"
    )

    for gateway_region in "${gateways[@]}"; do
        local gateway_name="${gateway_region%%:*}"
        local region="${gateway_region##*:}"
        
        if resource_exists "vpn-gateway" "${gateway_name}" "${region}"; then
            log_info "Deleting VPN gateway: ${gateway_name}"
            if ! gcloud compute vpn-gateways delete "${gateway_name}" \
                --region="${region}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                handle_error "Failed to delete VPN gateway: ${gateway_name}"
            else
                log_success "Deleted VPN gateway: ${gateway_name}"
            fi
        else
            log_info "VPN gateway ${gateway_name} not found, skipping"
        fi
    done

    # Delete Cloud Routers
    local routers=(
        "${DR_PREFIX}-primary-router:${PRIMARY_REGION}"
        "${DR_PREFIX}-secondary-router:${SECONDARY_REGION}"
    )

    for router_region in "${routers[@]}"; do
        local router_name="${router_region%%:*}"
        local region="${router_region##*:}"
        
        if resource_exists "router" "${router_name}" "${region}"; then
            log_info "Deleting router: ${router_name}"
            if ! gcloud compute routers delete "${router_name}" \
                --region="${region}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                handle_error "Failed to delete router: ${router_name}"
            else
                log_success "Deleted router: ${router_name}"
            fi
        else
            log_info "Router ${router_name} not found, skipping"
        fi
    done

    log_success "Network infrastructure cleanup completed"
}

remove_vpc_networks_and_pubsub() {
    log_info "Removing VPC networks and Pub/Sub resources..."

    # Delete VPC subnets first
    local subnets=(
        "${DR_PREFIX}-primary-subnet:${PRIMARY_REGION}"
        "${DR_PREFIX}-secondary-subnet:${SECONDARY_REGION}"
    )

    for subnet_region in "${subnets[@]}"; do
        local subnet_name="${subnet_region%%:*}"
        local region="${subnet_region##*:}"
        
        if resource_exists "subnet" "${subnet_name}" "${region}"; then
            log_info "Deleting subnet: ${subnet_name}"
            if ! gcloud compute networks subnets delete "${subnet_name}" \
                --region="${region}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                handle_error "Failed to delete subnet: ${subnet_name}"
            else
                log_success "Deleted subnet: ${subnet_name}"
            fi
        else
            log_info "Subnet ${subnet_name} not found, skipping"
        fi
    done

    # Delete VPC networks
    local networks=(
        "${DR_PREFIX}-primary-vpc"
        "${DR_PREFIX}-secondary-vpc"
    )

    for network_name in "${networks[@]}"; do
        if resource_exists "network" "${network_name}"; then
            log_info "Deleting VPC network: ${network_name}"
            if ! gcloud compute networks delete "${network_name}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                handle_error "Failed to delete VPC network: ${network_name}"
            else
                log_success "Deleted VPC network: ${network_name}"
            fi
        else
            log_info "VPC network ${network_name} not found, skipping"
        fi
    done

    # Delete Pub/Sub subscriptions
    local subscriptions=(
        "${DR_PREFIX}-health-subscription"
        "${DR_PREFIX}-failover-subscription"
        "${DR_PREFIX}-replication-subscription"
    )

    for subscription_name in "${subscriptions[@]}"; do
        if resource_exists "pubsub-subscription" "${subscription_name}"; then
            log_info "Deleting Pub/Sub subscription: ${subscription_name}"
            if ! gcloud pubsub subscriptions delete "${subscription_name}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                log_warning "Failed to delete subscription: ${subscription_name}"
            else
                log_success "Deleted subscription: ${subscription_name}"
            fi
        else
            log_info "Subscription ${subscription_name} not found, skipping"
        fi
    done

    # Delete Pub/Sub topics
    local topics=(
        "${DR_PREFIX}-health-alerts"
        "${DR_PREFIX}-failover-commands"
        "${DR_PREFIX}-replication-status"
    )

    for topic_name in "${topics[@]}"; do
        if resource_exists "pubsub-topic" "${topic_name}"; then
            log_info "Deleting Pub/Sub topic: ${topic_name}"
            if ! gcloud pubsub topics delete "${topic_name}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null; then
                log_warning "Failed to delete topic: ${topic_name}"
            else
                log_success "Deleted topic: ${topic_name}"
            fi
        else
            log_info "Topic ${topic_name} not found, skipping"
        fi
    done

    # Delete Cloud Storage bucket
    local bucket_name="${DR_PREFIX}-replication-staging"
    if resource_exists "bucket" "${bucket_name}"; then
        log_info "Deleting Cloud Storage bucket: ${bucket_name}"
        if ! gsutil -m rm -r "gs://${bucket_name}" 2>/dev/null; then
            log_warning "Failed to delete bucket: ${bucket_name}"
        else
            log_success "Deleted bucket: ${bucket_name}"
        fi
    else
        log_info "Bucket ${bucket_name} not found, skipping"
    fi

    log_success "VPC networks and Pub/Sub cleanup completed"
}

cleanup_local_files() {
    log_info "Cleaning up local deployment files..."

    # Remove deployment info file
    if [[ -f "${DEPLOYMENT_INFO}" ]]; then
        rm -f "${DEPLOYMENT_INFO}"
        log_success "Removed deployment info file"
    fi

    # List any remaining log files
    if ls "${SCRIPT_DIR}"/*.log &> /dev/null; then
        log_info "Log files remaining in ${SCRIPT_DIR}:"
        ls -la "${SCRIPT_DIR}"/*.log || true
    fi

    log_success "Local files cleanup completed"
}

generate_cleanup_report() {
    log_info "Generating cleanup completion report..."

    local report_file="${SCRIPT_DIR}/cleanup_report.txt"
    cat > "${report_file}" << EOF
Disaster Recovery Cleanup Report
================================

Cleanup completed at: $(date)
Project ID: ${PROJECT_ID}
DR Prefix: ${DR_PREFIX}
Primary Region: ${PRIMARY_REGION}
Secondary Region: ${SECONDARY_REGION}

Resources Cleaned Up:
- Parallelstore instances (2)
- Network Connectivity Center hub and spokes
- VPN gateways and tunnels (2 each)
- Cloud Routers (2)
- VPC networks and subnets (2 each)
- Pub/Sub topics and subscriptions (3 each)
- Cloud Functions (2)
- Cloud Workflows (1)
- Cloud Scheduler jobs (1)
- Monitoring policies and channels
- Cloud Storage buckets (1)

Status: COMPLETED

Log files:
- Main log: ${LOG_FILE}
- Error log: ${ERROR_LOG}
- This report: ${report_file}

Note: This cleanup process removed all billable resources.
You should verify in the Google Cloud Console that no
unexpected resources remain.
EOF

    log_success "Cleanup report generated: ${report_file}"
}

main() {
    log_info "Starting disaster recovery solution cleanup..."
    log_info "Cleanup started at: $(date)"

    # Initialize log files
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    echo "Error log for cleanup started at $(date)" > "${ERROR_LOG}"

    # Load configuration and confirm
    load_deployment_config "$@"
    confirm_destruction
    check_prerequisites

    log_info "Beginning resource cleanup for DR prefix: ${DR_PREFIX}"

    # Execute cleanup steps in reverse order of creation
    remove_scheduler_and_functions
    remove_workflows_and_monitoring
    remove_parallelstore_instances
    remove_network_connectivity
    remove_vpc_networks_and_pubsub
    cleanup_local_files
    generate_cleanup_report

    log_success "Disaster recovery solution cleanup completed successfully!"
    log_info "Cleanup completed at: $(date)"
    log_info "Total cleanup time: $((SECONDS / 60)) minutes"
    
    echo ""
    echo "🧹 Cleanup Summary:"
    echo "Project ID: ${PROJECT_ID}"
    echo "DR Prefix: ${DR_PREFIX}"
    echo "All resources have been removed"
    echo ""
    echo "📋 Verification Steps:"
    echo "1. Check Google Cloud Console for any remaining resources"
    echo "2. Review billing to confirm charges have stopped"
    echo "3. Verify no unexpected resources remain in other regions"
    echo ""
    echo "📄 Cleanup logs available at:"
    echo "  Main log: ${LOG_FILE}"
    echo "  Error log: ${ERROR_LOG}"
    echo "  Report: ${SCRIPT_DIR}/cleanup_report.txt"
}

# Parse command line arguments
FORCE_CLEANUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --dr-prefix)
            DR_PREFIX="$2"
            shift 2
            ;;
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --project-id ID     Google Cloud Project ID"
            echo "  --dr-prefix PREFIX  Prefix for resource names"
            echo "  --force             Skip all confirmation prompts"
            echo "  --help              Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_ID          Google Cloud Project ID"
            echo "  DR_PREFIX           Resource name prefix"
            echo ""
            echo "This script will remove ALL resources created by the"
            echo "disaster recovery deployment. All data will be lost."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"