#!/bin/bash

# Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing - Cleanup Script
# This script safely removes all infrastructure created for the AI inference solution
# Author: Recipe Generator
# Version: 1.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/ai-inference-destroy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
SKIP_CONFIRMATION=false
FORCE_DELETE=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    print_status "Prerequisites check completed successfully"
}

# Function to detect environment variables
detect_environment_variables() {
    print_step "Detecting environment variables and resources..."
    
    # Try to get current project from gcloud config
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            print_error "PROJECT_ID not set and no default project configured"
            print_error "Please set PROJECT_ID environment variable or configure gcloud"
            exit 1
        fi
    fi
    
    # Set default values if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Try to detect RANDOM_SUFFIX from existing resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        print_status "Attempting to detect RANDOM_SUFFIX from existing resources..."
        
        # Look for TPU resources that match our naming pattern
        local tpu_list
        tpu_list=$(gcloud compute tpus tpu-vm list --zone="$ZONE" --format="value(name)" --filter="name~'^ironwood-cluster-.*'" 2>/dev/null || echo "")
        
        if [[ -n "$tpu_list" ]]; then
            # Extract suffix from first matching TPU
            local first_tpu
            first_tpu=$(echo "$tpu_list" | head -n1)
            RANDOM_SUFFIX=$(echo "$first_tpu" | sed 's/ironwood-cluster-//' | sed 's/-small$//' | sed 's/-medium$//' | sed 's/-large$//')
            print_status "Detected RANDOM_SUFFIX: $RANDOM_SUFFIX"
        else
            print_warning "Could not detect RANDOM_SUFFIX from existing resources"
            print_warning "You may need to specify RANDOM_SUFFIX environment variable"
        fi
    fi
    
    # Set resource names
    export CLUSTER_NAME="${CLUSTER_NAME:-ironwood-cluster-${RANDOM_SUFFIX:-}}"
    export ENDPOINT_PREFIX="${ENDPOINT_PREFIX:-inference-endpoint-${RANDOM_SUFFIX:-}}"
    export SA_EMAIL="${SA_EMAIL:-tpu-inference-sa@${PROJECT_ID}.iam.gserviceaccount.com}"
    
    print_status "Environment variables configured:"
    print_status "  PROJECT_ID: $PROJECT_ID"
    print_status "  REGION: $REGION"
    print_status "  ZONE: $ZONE"
    print_status "  CLUSTER_NAME: $CLUSTER_NAME"
    print_status "  RANDOM_SUFFIX: ${RANDOM_SUFFIX:-'not detected'}"
}

# Function to list resources to be deleted
list_resources_to_delete() {
    print_step "Scanning for resources to delete..."
    
    local resources_found=false
    
    echo -e "\n${YELLOW}=== Resources Found for Deletion ===${NC}"
    
    # Check TPU resources
    echo -e "\n${BLUE}TPU Resources:${NC}"
    local tpu_list
    tpu_list=$(gcloud compute tpus tpu-vm list --zone="$ZONE" --format="value(name,state,acceleratorType)" --filter="name~'${CLUSTER_NAME}'" 2>/dev/null || echo "")
    
    if [[ -n "$tpu_list" ]]; then
        echo "$tpu_list" | while read -r name state accel_type; do
            echo -e "  • ${RED}$name${NC} ($state, $accel_type)"
            resources_found=true
        done
    else
        echo -e "  ${YELLOW}No TPU resources found${NC}"
    fi
    
    # Check Vertex AI endpoints
    echo -e "\n${BLUE}Vertex AI Endpoints:${NC}"
    local endpoints_list
    endpoints_list=$(gcloud ai endpoints list --region="$REGION" --format="value(name,displayName)" --filter="displayName~'${ENDPOINT_PREFIX}'" 2>/dev/null || echo "")
    
    if [[ -n "$endpoints_list" ]]; then
        echo "$endpoints_list" | while read -r name display_name; do
            echo -e "  • ${RED}$display_name${NC} ($name)"
            resources_found=true
        done
    else
        echo -e "  ${YELLOW}No Vertex AI endpoints found${NC}"
    fi
    
    # Check load balancer components
    echo -e "\n${BLUE}Load Balancer Components:${NC}"
    
    # Forwarding rules
    if gcloud compute forwarding-rules describe ai-inference-forwarding-rule --global &> /dev/null; then
        echo -e "  • ${RED}ai-inference-forwarding-rule${NC} (global forwarding rule)"
        resources_found=true
    fi
    
    # HTTP proxy
    if gcloud compute target-http-proxies describe ai-inference-proxy &> /dev/null; then
        echo -e "  • ${RED}ai-inference-proxy${NC} (HTTP proxy)"
        resources_found=true
    fi
    
    # URL map
    if gcloud compute url-maps describe ai-inference-lb &> /dev/null; then
        echo -e "  • ${RED}ai-inference-lb${NC} (URL map)"
        resources_found=true
    fi
    
    # Backend services
    local backends=("small" "medium" "large")
    for backend in "${backends[@]}"; do
        local service_name="inference-backend-${backend}"
        if gcloud compute backend-services describe "$service_name" --global &> /dev/null; then
            echo -e "  • ${RED}$service_name${NC} (backend service)"
            resources_found=true
        fi
    done
    
    # Health checks
    if gcloud compute health-checks describe tpu-health-check &> /dev/null; then
        echo -e "  • ${RED}tpu-health-check${NC} (health check)"
        resources_found=true
    fi
    
    # Global IP
    if gcloud compute addresses describe ai-inference-ip --global &> /dev/null; then
        echo -e "  • ${RED}ai-inference-ip${NC} (global IP address)"
        resources_found=true
    fi
    
    # Check Redis instances
    echo -e "\n${BLUE}Redis Instances:${NC}"
    if gcloud redis instances describe inference-cache --region="$REGION" &> /dev/null; then
        echo -e "  • ${RED}inference-cache${NC} (Redis instance)"
        resources_found=true
    else
        echo -e "  ${YELLOW}No Redis instances found${NC}"
    fi
    
    # Check BigQuery datasets
    echo -e "\n${BLUE}BigQuery Datasets:${NC}"
    if command -v bq &> /dev/null; then
        if bq ls -d "${PROJECT_ID}:tpu_analytics" &> /dev/null; then
            echo -e "  • ${RED}tpu_analytics${NC} (BigQuery dataset)"
            resources_found=true
        else
            echo -e "  ${YELLOW}No BigQuery datasets found${NC}"
        fi
    else
        echo -e "  ${YELLOW}bq CLI not available, skipping BigQuery check${NC}"
    fi
    
    # Check Pub/Sub resources
    echo -e "\n${BLUE}Pub/Sub Resources:${NC}"
    if gcloud pubsub topics describe tpu-metrics-stream &> /dev/null; then
        echo -e "  • ${RED}tpu-metrics-stream${NC} (Pub/Sub topic)"
        resources_found=true
    fi
    
    if gcloud pubsub subscriptions describe tpu-analytics-sub &> /dev/null; then
        echo -e "  • ${RED}tpu-analytics-sub${NC} (Pub/Sub subscription)"
        resources_found=true
    fi
    
    if [[ "$resources_found" != "true" ]]; then
        echo -e "  ${YELLOW}No Pub/Sub resources found${NC}"
    fi
    
    # Check service account
    echo -e "\n${BLUE}Service Accounts:${NC}"
    if gcloud iam service-accounts describe "$SA_EMAIL" &> /dev/null; then
        echo -e "  • ${RED}$SA_EMAIL${NC} (service account)"
        resources_found=true
    else
        echo -e "  ${YELLOW}No service account found${NC}"
    fi
    
    if [[ "$resources_found" != "true" ]]; then
        echo -e "\n${GREEN}No resources found to delete.${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}=== End of Resource List ===${NC}\n"
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "\n${RED}WARNING: This will permanently delete all the resources listed above!${NC}"
    echo -e "${RED}This action cannot be undone.${NC}"
    echo -e "\nProject: ${BLUE}$PROJECT_ID${NC}"
    echo -e "Region: ${BLUE}$REGION${NC}"
    
    echo -e "\n${YELLOW}Are you sure you want to delete all these resources? (yes/no):${NC} "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Deletion cancelled by user"
        exit 0
    fi
    
    # Double confirmation for expensive resources
    echo -e "\n${RED}This will delete expensive TPU resources. Please confirm again.${NC}"
    echo -e "${YELLOW}Type 'DELETE' to proceed:${NC} "
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        print_status "Deletion cancelled by user"
        exit 0
    fi
}

# Function to delete Vertex AI endpoints
delete_vertex_ai_endpoints() {
    print_step "Deleting Vertex AI endpoints..."
    
    local endpoints_deleted=false
    local endpoints_list
    endpoints_list=$(gcloud ai endpoints list --region="$REGION" --format="value(name)" --filter="displayName~'${ENDPOINT_PREFIX}'" 2>/dev/null || echo "")
    
    if [[ -n "$endpoints_list" ]]; then
        echo "$endpoints_list" | while read -r endpoint_id; do
            if [[ -n "$endpoint_id" ]]; then
                print_status "Deleting Vertex AI endpoint: $endpoint_id"
                gcloud ai endpoints delete "$endpoint_id" \
                    --region="$REGION" \
                    --quiet &>> "$LOG_FILE" || {
                    print_warning "Failed to delete endpoint: $endpoint_id"
                }
                endpoints_deleted=true
            fi
        done
    fi
    
    if [[ "$endpoints_deleted" == "true" ]]; then
        print_status "✅ Vertex AI endpoints deletion initiated"
    else
        print_status "No Vertex AI endpoints to delete"
    fi
}

# Function to delete TPU resources
delete_tpu_resources() {
    print_step "Deleting TPU resources..."
    
    local tpu_pods=("${CLUSTER_NAME}-small" "${CLUSTER_NAME}-medium" "${CLUSTER_NAME}-large")
    local tpus_deleted=false
    
    for pod in "${tpu_pods[@]}"; do
        if gcloud compute tpus tpu-vm describe "$pod" --zone="$ZONE" &> /dev/null; then
            print_status "Deleting TPU pod: $pod"
            gcloud compute tpus tpu-vm delete "$pod" \
                --zone="$ZONE" \
                --quiet &>> "$LOG_FILE" || {
                print_warning "Failed to delete TPU pod: $pod"
            }
            tpus_deleted=true
        else
            print_status "TPU pod $pod not found, skipping"
        fi
    done
    
    if [[ "$tpus_deleted" == "true" ]]; then
        print_status "✅ TPU resources deletion initiated"
        
        # Wait for TPU deletion to complete before proceeding
        print_status "Waiting for TPU resources to be fully deleted..."
        sleep 60
        
        # Verify deletion
        for pod in "${tpu_pods[@]}"; do
            local max_attempts=10
            local attempt=1
            
            while [[ $attempt -le $max_attempts ]]; do
                if ! gcloud compute tpus tpu-vm describe "$pod" --zone="$ZONE" &> /dev/null; then
                    print_status "✅ TPU pod $pod fully deleted"
                    break
                else
                    print_status "Waiting for TPU pod $pod deletion (attempt $attempt/$max_attempts)"
                    sleep 30
                    ((attempt++))
                fi
            done
        done
    else
        print_status "No TPU resources to delete"
    fi
}

# Function to delete load balancer components
delete_load_balancer() {
    print_step "Deleting load balancer components..."
    
    # Delete forwarding rule
    if gcloud compute forwarding-rules describe ai-inference-forwarding-rule --global &> /dev/null; then
        print_status "Deleting global forwarding rule..."
        gcloud compute forwarding-rules delete ai-inference-forwarding-rule \
            --global \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete forwarding rule"
        }
        print_status "✅ Global forwarding rule deleted"
    fi
    
    # Delete HTTP proxy
    if gcloud compute target-http-proxies describe ai-inference-proxy &> /dev/null; then
        print_status "Deleting HTTP proxy..."
        gcloud compute target-http-proxies delete ai-inference-proxy \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete HTTP proxy"
        }
        print_status "✅ HTTP proxy deleted"
    fi
    
    # Delete URL map
    if gcloud compute url-maps describe ai-inference-lb &> /dev/null; then
        print_status "Deleting URL map..."
        gcloud compute url-maps delete ai-inference-lb \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete URL map"
        }
        print_status "✅ URL map deleted"
    fi
    
    # Delete backend services
    local backends=("small" "medium" "large")
    for backend in "${backends[@]}"; do
        local service_name="inference-backend-${backend}"
        if gcloud compute backend-services describe "$service_name" --global &> /dev/null; then
            print_status "Deleting backend service: $service_name"
            gcloud compute backend-services delete "$service_name" \
                --global \
                --quiet &>> "$LOG_FILE" || {
                print_warning "Failed to delete backend service: $service_name"
            }
            print_status "✅ Backend service deleted: $service_name"
        fi
    done
    
    # Delete health check
    if gcloud compute health-checks describe tpu-health-check &> /dev/null; then
        print_status "Deleting health check..."
        gcloud compute health-checks delete tpu-health-check \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete health check"
        }
        print_status "✅ Health check deleted"
    fi
    
    # Delete global IP address
    if gcloud compute addresses describe ai-inference-ip --global &> /dev/null; then
        print_status "Deleting global IP address..."
        gcloud compute addresses delete ai-inference-ip \
            --global \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete global IP address"
        }
        print_status "✅ Global IP address deleted"
    fi
}

# Function to delete Redis cache
delete_redis_cache() {
    print_step "Deleting Redis cache..."
    
    if gcloud redis instances describe inference-cache --region="$REGION" &> /dev/null; then
        print_status "Deleting Redis instance..."
        gcloud redis instances delete inference-cache \
            --region="$REGION" \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete Redis instance"
        }
        print_status "✅ Redis cache deletion initiated"
    else
        print_status "No Redis cache to delete"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    print_step "Deleting monitoring and analytics resources..."
    
    # Delete Pub/Sub subscription
    if gcloud pubsub subscriptions describe tpu-analytics-sub &> /dev/null; then
        print_status "Deleting Pub/Sub subscription..."
        gcloud pubsub subscriptions delete tpu-analytics-sub \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete Pub/Sub subscription"
        }
        print_status "✅ Pub/Sub subscription deleted"
    fi
    
    # Delete Pub/Sub topic
    if gcloud pubsub topics describe tpu-metrics-stream &> /dev/null; then
        print_status "Deleting Pub/Sub topic..."
        gcloud pubsub topics delete tpu-metrics-stream \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete Pub/Sub topic"
        }
        print_status "✅ Pub/Sub topic deleted"
    fi
    
    # Delete BigQuery dataset
    if command -v bq &> /dev/null; then
        if bq ls -d "${PROJECT_ID}:tpu_analytics" &> /dev/null; then
            print_status "Deleting BigQuery dataset..."
            bq rm -r -f "${PROJECT_ID}:tpu_analytics" &>> "$LOG_FILE" || {
                print_warning "Failed to delete BigQuery dataset"
            }
            print_status "✅ BigQuery dataset deleted"
        fi
    else
        print_warning "bq CLI not available, skipping BigQuery cleanup"
    fi
}

# Function to delete service account
delete_service_account() {
    print_step "Deleting service account..."
    
    if gcloud iam service-accounts describe "$SA_EMAIL" &> /dev/null; then
        print_status "Removing IAM policy bindings..."
        
        # Remove IAM bindings (best effort)
        local roles=(
            "roles/aiplatform.user"
            "roles/compute.admin"
            "roles/monitoring.metricWriter"
            "roles/logging.logWriter"
            "roles/redis.admin"
        )
        
        for role in "${roles[@]}"; do
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$SA_EMAIL" \
                --role="$role" &>> "$LOG_FILE" || {
                print_warning "Failed to remove role $role (may not exist)"
            }
        done
        
        print_status "Deleting service account..."
        gcloud iam service-accounts delete "$SA_EMAIL" \
            --quiet &>> "$LOG_FILE" || {
            print_warning "Failed to delete service account"
        }
        print_status "✅ Service account deleted"
    else
        print_status "No service account to delete"
    fi
}

# Function to wait for resource deletion
wait_for_deletion_completion() {
    print_step "Waiting for resource deletion to complete..."
    
    # Wait for expensive resources to be fully deleted
    print_status "Ensuring TPU and Redis resources are fully deleted..."
    sleep 90
    
    # Check if any TPU resources still exist
    local remaining_tpus
    remaining_tpus=$(gcloud compute tpus tpu-vm list --zone="$ZONE" --format="value(name)" --filter="name~'${CLUSTER_NAME}'" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_tpus" ]]; then
        print_warning "Some TPU resources may still be deleting:"
        echo "$remaining_tpus"
    else
        print_status "✅ All TPU resources confirmed deleted"
    fi
    
    # Check Redis deletion
    if gcloud redis instances describe inference-cache --region="$REGION" &> /dev/null; then
        print_warning "Redis instance may still be deleting"
    else
        print_status "✅ Redis instance confirmed deleted"
    fi
}

# Function to validate deletion
validate_deletion() {
    print_step "Validating resource deletion..."
    
    local cleanup_issues=false
    
    # Check for remaining TPU resources
    local remaining_tpus
    remaining_tpus=$(gcloud compute tpus tpu-vm list --zone="$ZONE" --format="value(name)" --filter="name~'${CLUSTER_NAME}'" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_tpus" ]]; then
        print_warning "Remaining TPU resources found:"
        echo "$remaining_tpus"
        cleanup_issues=true
    else
        print_status "✅ No TPU resources remaining"
    fi
    
    # Check for remaining load balancer components
    if gcloud compute forwarding-rules describe ai-inference-forwarding-rule --global &> /dev/null; then
        print_warning "Global forwarding rule still exists"
        cleanup_issues=true
    fi
    
    if gcloud compute backend-services list --global --filter="name~'inference-backend'" --format="value(name)" 2>/dev/null | grep -q .; then
        print_warning "Some backend services still exist"
        cleanup_issues=true
    fi
    
    # Check Redis
    if gcloud redis instances describe inference-cache --region="$REGION" &> /dev/null; then
        print_warning "Redis instance still exists (may be deleting)"
        cleanup_issues=true
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "$SA_EMAIL" &> /dev/null; then
        print_warning "Service account still exists"
        cleanup_issues=true
    fi
    
    if [[ "$cleanup_issues" == "true" ]]; then
        print_warning "Some resources may still exist or be in the process of deletion"
        print_warning "This is normal for resources that take time to delete (TPU, Redis)"
        print_warning "Check the Google Cloud Console to monitor deletion progress"
    else
        print_status "✅ All resources successfully deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    print_step "Cleanup Summary"
    
    echo -e "\n${GREEN}=== AI Inference Infrastructure Cleanup Complete ===${NC}"
    echo -e "Project ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "Region: ${BLUE}$REGION${NC}"
    echo -e "Zone: ${BLUE}$ZONE${NC}"
    
    echo -e "\n${YELLOW}Resources Removed:${NC}"
    echo -e "  • TPU pods (small, medium, large)"
    echo -e "  • Vertex AI endpoints"
    echo -e "  • Load balancer components"
    echo -e "  • Redis cache"
    echo -e "  • Monitoring resources"
    echo -e "  • Service account and IAM bindings"
    
    echo -e "\n${YELLOW}Important Notes:${NC}"
    echo -e "• Some resources may take additional time to fully delete"
    echo -e "• Check Google Cloud Console to verify complete deletion"
    echo -e "• Monitor billing to ensure no unexpected charges"
    echo -e "• Review Cloud Monitoring for any remaining alerts"
    
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo -e "• Verify in Google Cloud Console that all resources are deleted"
    echo -e "• Check billing reports to confirm cost reduction"
    echo -e "• Review project quotas if planning future deployments"
    
    echo -e "\n${YELLOW}Log File:${NC} $LOG_FILE"
    echo -e "${GREEN}Cleanup completed successfully!${NC}\n"
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    print_error "Cleanup process encountered errors. Check log file: $LOG_FILE"
    print_warning "Some resources may not have been deleted completely"
    print_warning "Please check Google Cloud Console and manually delete any remaining resources"
    print_warning "This is especially important for expensive resources like TPUs"
    exit 1
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Large-Scale AI Model Inference infrastructure

OPTIONS:
    -p, --project PROJECT_ID    Google Cloud project ID (default: current gcloud project)
    -r, --region REGION         Google Cloud region (default: us-central1)
    -z, --zone ZONE            Google Cloud zone (default: us-central1-a)
    -s, --suffix SUFFIX        Random suffix used during deployment (auto-detected if possible)
    -d, --dry-run              Show what would be deleted without actually deleting
    -y, --yes                  Skip confirmation prompts (DANGEROUS!)
    -f, --force                Force deletion even if some resources fail
    -h, --help                 Show this help message

EXAMPLES:
    $0                                          # Destroy with auto-detected settings
    $0 -p my-project -r us-west1               # Destroy in specific project and region
    $0 -d                                      # Dry run to see what would be deleted
    $0 -s abc123                               # Specify the random suffix explicitly

ENVIRONMENT VARIABLES:
    PROJECT_ID                 Google Cloud project ID
    REGION                     Google Cloud region  
    ZONE                       Google Cloud zone
    RANDOM_SUFFIX              Random suffix used during deployment

SAFETY FEATURES:
    • Double confirmation required for deletion
    • Dry run mode to preview deletions
    • Automatic resource detection
    • Safe deletion order (expensive resources first)
    • Comprehensive validation and error handling

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -s|--suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    echo -e "${BLUE}Large-Scale AI Model Inference Cleanup Script${NC}"
    echo -e "${BLUE}=============================================${NC}\n"
    
    # Start logging
    print_status "Starting cleanup at $(date)"
    print_status "Log file: $LOG_FILE"
    
    # Set trap for error handling
    if [[ "$FORCE_DELETE" != "true" ]]; then
        trap handle_cleanup_error ERR
    fi
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Detect environment and resources
    detect_environment_variables
    
    # List resources to be deleted
    if ! list_resources_to_delete; then
        print_status "No resources found to delete. Exiting."
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "DRY RUN MODE - No resources will be deleted"
        print_status "The resources listed above would be deleted in actual run"
        exit 0
    fi
    
    # Execute cleanup steps (in order of dependency)
    print_status "Beginning resource deletion..."
    
    delete_vertex_ai_endpoints
    delete_load_balancer
    delete_tpu_resources
    delete_redis_cache
    delete_monitoring_resources
    delete_service_account
    wait_for_deletion_completion
    validate_deletion
    display_cleanup_summary
    
    print_status "Cleanup completed successfully at $(date)"
}

# Execute main function with all arguments
main "$@"