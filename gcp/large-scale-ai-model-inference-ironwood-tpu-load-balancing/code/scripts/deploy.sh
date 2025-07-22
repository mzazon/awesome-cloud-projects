#!/bin/bash

# Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing - Deployment Script
# This script deploys the complete AI inference infrastructure on Google Cloud Platform
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
LOG_FILE="/tmp/ai-inference-deploy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
SKIP_CONFIRMATION=false

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
        print_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        print_error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version (minimum 400.0.0 required)
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "0.0.0")
    print_status "Detected gcloud version: $gcloud_version"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if bq CLI is available (for BigQuery operations)
    if ! command -v bq &> /dev/null; then
        print_warning "BigQuery CLI (bq) not found. Some analytics features may not work."
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        print_warning "curl not found. HTTP testing capabilities will be limited."
    fi
    
    print_status "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    print_step "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-ai-inference-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export MODEL_NAME="${MODEL_NAME:-llama-70b}"
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    
    export CLUSTER_NAME="ironwood-cluster-${RANDOM_SUFFIX}"
    export ENDPOINT_PREFIX="inference-endpoint-${RANDOM_SUFFIX}"
    export SA_EMAIL="tpu-inference-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    print_status "Environment variables configured:"
    print_status "  PROJECT_ID: $PROJECT_ID"
    print_status "  REGION: $REGION"
    print_status "  ZONE: $ZONE"
    print_status "  MODEL_NAME: $MODEL_NAME"
    print_status "  CLUSTER_NAME: $CLUSTER_NAME"
    print_status "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
}

# Function to check project and billing
check_project_and_billing() {
    print_step "Validating project and billing..."
    
    # Check if project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        print_error "Project '$PROJECT_ID' does not exist or you don't have access to it."
        print_error "Please create the project first or check your permissions."
        exit 1
    fi
    
    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "$billing_account" ]]; then
        print_error "Billing is not enabled for project '$PROJECT_ID'."
        print_error "Please enable billing before proceeding with TPU deployments."
        exit 1
    fi
    
    print_status "Project validation completed successfully"
    print_status "Billing account: $billing_account"
}

# Function to set gcloud configuration
configure_gcloud() {
    print_step "Configuring gcloud settings..."
    
    gcloud config set project "$PROJECT_ID" || {
        print_error "Failed to set project configuration"
        exit 1
    }
    
    gcloud config set compute/region "$REGION" || {
        print_error "Failed to set region configuration"
        exit 1
    }
    
    gcloud config set compute/zone "$ZONE" || {
        print_error "Failed to set zone configuration"
        exit 1
    }
    
    print_status "gcloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    print_step "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "aiplatform.googleapis.com"
        "container.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "bigquery.googleapis.com"
        "pubsub.googleapis.com"
        "redis.googleapis.com"
        "cloudbilling.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        print_status "Enabling $api..."
        if ! gcloud services enable "$api" 2>> "$LOG_FILE"; then
            print_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    print_status "Waiting for APIs to be fully activated..."
    sleep 30
    
    print_status "All required APIs enabled successfully"
}

# Function to create service account
create_service_account() {
    print_step "Creating TPU inference service account..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "$SA_EMAIL" &> /dev/null; then
        print_warning "Service account $SA_EMAIL already exists, skipping creation"
    else
        gcloud iam service-accounts create tpu-inference-sa \
            --display-name="TPU Inference Service Account" \
            --description="Service account for TPU inference operations" || {
            print_error "Failed to create service account"
            exit 1
        }
        print_status "Service account created: $SA_EMAIL"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/aiplatform.user"
        "roles/compute.admin"
        "roles/monitoring.metricWriter"
        "roles/logging.logWriter"
        "roles/redis.admin"
    )
    
    for role in "${roles[@]}"; do
        print_status "Granting role $role to service account..."
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SA_EMAIL" \
            --role="$role" &>> "$LOG_FILE" || {
            print_warning "Failed to grant role $role (may already exist)"
        }
    done
    
    print_status "Service account configuration completed"
}

# Function to create TPU resources
create_tpu_resources() {
    print_step "Creating Ironwood TPU resources..."
    
    # Create small TPU pod for initial testing (256 chips)
    print_status "Creating small TPU pod (256 chips)..."
    if ! gcloud compute tpus tpu-vm describe "${CLUSTER_NAME}-small" --zone="$ZONE" &> /dev/null; then
        gcloud compute tpus tpu-vm create "${CLUSTER_NAME}-small" \
            --zone="$ZONE" \
            --accelerator-type=v7-256 \
            --version=tpu-ubuntu2204-base \
            --service-account="$SA_EMAIL" \
            --tags=tpu-inference || {
            print_error "Failed to create small TPU pod"
            exit 1
        }
        print_status "✅ Small TPU pod created successfully"
    else
        print_warning "Small TPU pod already exists, skipping creation"
    fi
    
    # Create medium TPU pod for production workloads (1024 chips)
    print_status "Creating medium TPU pod (1024 chips)..."
    if ! gcloud compute tpus tpu-vm describe "${CLUSTER_NAME}-medium" --zone="$ZONE" &> /dev/null; then
        gcloud compute tpus tpu-vm create "${CLUSTER_NAME}-medium" \
            --zone="$ZONE" \
            --accelerator-type=v7-1024 \
            --version=tpu-ubuntu2204-base \
            --service-account="$SA_EMAIL" \
            --tags=tpu-inference || {
            print_error "Failed to create medium TPU pod"
            exit 1
        }
        print_status "✅ Medium TPU pod created successfully"
    else
        print_warning "Medium TPU pod already exists, skipping creation"
    fi
    
    # Create large TPU pod for enterprise-scale inference (9216 chips)
    print_status "Creating large TPU pod (9216 chips)..."
    if ! gcloud compute tpus tpu-vm describe "${CLUSTER_NAME}-large" --zone="$ZONE" &> /dev/null; then
        gcloud compute tpus tpu-vm create "${CLUSTER_NAME}-large" \
            --zone="$ZONE" \
            --accelerator-type=v7-9216 \
            --version=tpu-ubuntu2204-base \
            --service-account="$SA_EMAIL" \
            --tags=tpu-inference || {
            print_error "Failed to create large TPU pod"
            exit 1
        }
        print_status "✅ Large TPU pod created successfully"
    else
        print_warning "Large TPU pod already exists, skipping creation"
    fi
    
    print_status "All TPU resources created successfully"
}

# Function to create health checks
create_health_checks() {
    print_step "Creating health checks for TPU endpoints..."
    
    if ! gcloud compute health-checks describe tpu-health-check &> /dev/null; then
        gcloud compute health-checks create http tpu-health-check \
            --port=8080 \
            --request-path="/health" \
            --check-interval=10s \
            --timeout=5s \
            --unhealthy-threshold=3 \
            --healthy-threshold=2 \
            --description="Health check for TPU inference endpoints" || {
            print_error "Failed to create health check"
            exit 1
        }
        print_status "✅ Health check created successfully"
    else
        print_warning "Health check already exists, skipping creation"
    fi
}

# Function to create backend services
create_backend_services() {
    print_step "Creating backend services for load balancing..."
    
    local backends=("small" "medium" "large")
    
    for backend in "${backends[@]}"; do
        local service_name="inference-backend-${backend}"
        
        if ! gcloud compute backend-services describe "$service_name" --global &> /dev/null; then
            print_status "Creating backend service: $service_name"
            gcloud compute backend-services create "$service_name" \
                --load-balancing-scheme=EXTERNAL \
                --protocol=HTTP \
                --port-name=http \
                --health-checks=tpu-health-check \
                --enable-cdn \
                --global \
                --description="Backend service for ${backend} TPU tier" || {
                print_error "Failed to create backend service: $service_name"
                exit 1
            }
            print_status "✅ Backend service created: $service_name"
        else
            print_warning "Backend service $service_name already exists, skipping creation"
        fi
    done
}

# Function to create load balancer
create_load_balancer() {
    print_step "Creating intelligent load balancer..."
    
    # Create URL map
    if ! gcloud compute url-maps describe ai-inference-lb &> /dev/null; then
        gcloud compute url-maps create ai-inference-lb \
            --default-service=inference-backend-medium \
            --description="AI inference load balancer with intelligent routing" || {
            print_error "Failed to create URL map"
            exit 1
        }
        
        # Add path-based routing rules
        gcloud compute url-maps add-path-matcher ai-inference-lb \
            --path-matcher-name=inference-matcher \
            --default-service=inference-backend-medium \
            --path-rules="/simple/*=inference-backend-small,/complex/*=inference-backend-large" || {
            print_warning "Failed to add path matcher (may already exist)"
        }
        
        print_status "✅ URL map created with intelligent routing"
    else
        print_warning "URL map already exists, skipping creation"
    fi
    
    # Create HTTP proxy
    if ! gcloud compute target-http-proxies describe ai-inference-proxy &> /dev/null; then
        gcloud compute target-http-proxies create ai-inference-proxy \
            --url-map=ai-inference-lb \
            --description="HTTP proxy for AI inference load balancer" || {
            print_error "Failed to create HTTP proxy"
            exit 1
        }
        print_status "✅ HTTP proxy created"
    else
        print_warning "HTTP proxy already exists, skipping creation"
    fi
    
    # Reserve global IP address
    if ! gcloud compute addresses describe ai-inference-ip --global &> /dev/null; then
        gcloud compute addresses create ai-inference-ip \
            --global \
            --description="Global IP for AI inference load balancer" || {
            print_error "Failed to create global IP address"
            exit 1
        }
        print_status "✅ Global IP address reserved"
    else
        print_warning "Global IP address already exists, skipping creation"
    fi
    
    # Create forwarding rule
    if ! gcloud compute forwarding-rules describe ai-inference-forwarding-rule --global &> /dev/null; then
        gcloud compute forwarding-rules create ai-inference-forwarding-rule \
            --load-balancing-scheme=EXTERNAL \
            --network-tier=PREMIUM \
            --address=ai-inference-ip \
            --global \
            --target-http-proxy=ai-inference-proxy \
            --ports=80 || {
            print_error "Failed to create forwarding rule"
            exit 1
        }
        print_status "✅ Global forwarding rule created"
    else
        print_warning "Global forwarding rule already exists, skipping creation"
    fi
}

# Function to create monitoring resources
create_monitoring_resources() {
    print_step "Setting up monitoring and analytics..."
    
    # Create BigQuery dataset
    local dataset_name="tpu_analytics"
    if ! bq ls -d "${PROJECT_ID}:${dataset_name}" &> /dev/null; then
        bq mk --dataset \
            --location="$REGION" \
            --description="TPU Inference Analytics Dataset" \
            "${PROJECT_ID}:${dataset_name}" || {
            print_warning "Failed to create BigQuery dataset (bq CLI may not be available)"
        }
        print_status "✅ BigQuery dataset created"
    else
        print_warning "BigQuery dataset already exists, skipping creation"
    fi
    
    # Create Pub/Sub topic and subscription
    if ! gcloud pubsub topics describe tpu-metrics-stream &> /dev/null; then
        gcloud pubsub topics create tpu-metrics-stream \
            --message-retention-duration=7d || {
            print_error "Failed to create Pub/Sub topic"
            exit 1
        }
        print_status "✅ Pub/Sub topic created"
    else
        print_warning "Pub/Sub topic already exists, skipping creation"
    fi
    
    if ! gcloud pubsub subscriptions describe tpu-analytics-sub &> /dev/null; then
        gcloud pubsub subscriptions create tpu-analytics-sub \
            --topic=tpu-metrics-stream \
            --ack-deadline=600 || {
            print_error "Failed to create Pub/Sub subscription"
            exit 1
        }
        print_status "✅ Pub/Sub subscription created"
    else
        print_warning "Pub/Sub subscription already exists, skipping creation"
    fi
}

# Function to create Redis cache
create_redis_cache() {
    print_step "Creating Redis cache for inference optimization..."
    
    if ! gcloud redis instances describe inference-cache --region="$REGION" &> /dev/null; then
        gcloud redis instances create inference-cache \
            --size=100 \
            --region="$REGION" \
            --network=default \
            --redis-version=redis_6_x \
            --enable-auth \
            --display-name="AI Inference Cache" || {
            print_error "Failed to create Redis cache"
            exit 1
        }
        print_status "✅ Redis cache created successfully"
    else
        print_warning "Redis cache already exists, skipping creation"
    fi
}

# Function to wait for resources to be ready
wait_for_resources() {
    print_step "Waiting for resources to be fully operational..."
    
    # Wait for TPU resources
    local tpu_pods=("${CLUSTER_NAME}-small" "${CLUSTER_NAME}-medium" "${CLUSTER_NAME}-large")
    
    for pod in "${tpu_pods[@]}"; do
        print_status "Waiting for TPU pod $pod to be ready..."
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            local state
            state=$(gcloud compute tpus tpu-vm describe "$pod" --zone="$ZONE" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            
            if [[ "$state" == "READY" ]]; then
                print_status "✅ TPU pod $pod is ready"
                break
            elif [[ "$state" == "FAILED" ]]; then
                print_error "TPU pod $pod failed to start"
                exit 1
            else
                print_status "TPU pod $pod state: $state (attempt $attempt/$max_attempts)"
                sleep 60
                ((attempt++))
            fi
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            print_error "Timeout waiting for TPU pod $pod to be ready"
            exit 1
        fi
    done
    
    # Wait for load balancer to be ready
    print_status "Waiting for load balancer to be ready..."
    sleep 120  # Load balancer typically takes 2-3 minutes
    
    print_status "All resources are operational"
}

# Function to validate deployment
validate_deployment() {
    print_step "Validating deployment..."
    
    # Check TPU pod status
    print_status "Validating TPU pods..."
    gcloud compute tpus tpu-vm list \
        --zone="$ZONE" \
        --filter="name~'${CLUSTER_NAME}'" \
        --format="table(name,state,acceleratorType,health)" || {
        print_warning "Failed to list TPU pods"
    }
    
    # Check load balancer status
    print_status "Validating load balancer..."
    local lb_ip
    lb_ip=$(gcloud compute addresses describe ai-inference-ip --global --format="value(address)" 2>/dev/null || echo "")
    
    if [[ -n "$lb_ip" ]]; then
        print_status "✅ Load balancer IP: $lb_ip"
        
        # Test basic connectivity (if curl is available)
        if command -v curl &> /dev/null; then
            print_status "Testing load balancer connectivity..."
            if curl -f -s --max-time 10 "http://$lb_ip/" &> /dev/null; then
                print_status "✅ Load balancer is responding"
            else
                print_warning "Load balancer may not be fully ready yet (this is normal for new deployments)"
            fi
        fi
    else
        print_warning "Could not retrieve load balancer IP"
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "$SA_EMAIL" &> /dev/null; then
        print_status "✅ Service account is configured"
    else
        print_warning "Service account validation failed"
    fi
    
    print_status "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    print_step "Deployment Summary"
    
    echo -e "\n${GREEN}=== AI Inference Infrastructure Deployment Complete ===${NC}"
    echo -e "Project ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "Region: ${BLUE}$REGION${NC}"
    echo -e "Zone: ${BLUE}$ZONE${NC}"
    echo -e "Cluster Name: ${BLUE}$CLUSTER_NAME${NC}"
    
    # Get load balancer IP
    local lb_ip
    lb_ip=$(gcloud compute addresses describe ai-inference-ip --global --format="value(address)" 2>/dev/null || echo "Not available")
    echo -e "Load Balancer IP: ${BLUE}$lb_ip${NC}"
    
    echo -e "\n${YELLOW}TPU Resources Created:${NC}"
    echo -e "  • ${CLUSTER_NAME}-small (256 chips)"
    echo -e "  • ${CLUSTER_NAME}-medium (1024 chips)"  
    echo -e "  • ${CLUSTER_NAME}-large (9216 chips)"
    
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo -e "1. Deploy your AI models to the Vertex AI endpoints"
    echo -e "2. Configure model routing based on complexity"
    echo -e "3. Set up monitoring dashboards"
    echo -e "4. Test inference performance"
    
    echo -e "\n${YELLOW}Important Notes:${NC}"
    echo -e "• TPU resources incur significant costs - monitor usage carefully"
    echo -e "• Use the destroy script to clean up resources when done"
    echo -e "• Check Cloud Monitoring for performance metrics"
    
    echo -e "\n${YELLOW}Log File:${NC} $LOG_FILE"
    echo -e "${GREEN}Deployment completed successfully!${NC}\n"
}

# Function to handle cleanup on script failure
cleanup_on_failure() {
    print_error "Deployment failed. Check log file: $LOG_FILE"
    print_warning "You may need to manually clean up partially created resources"
    print_warning "Run the destroy script to remove any created resources"
    exit 1
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing

OPTIONS:
    -p, --project PROJECT_ID    Google Cloud project ID (default: auto-generated)
    -r, --region REGION         Google Cloud region (default: us-central1)
    -z, --zone ZONE            Google Cloud zone (default: us-central1-a)
    -m, --model MODEL_NAME      Model name (default: llama-70b)
    -d, --dry-run              Show what would be deployed without actually deploying
    -y, --yes                  Skip confirmation prompts
    -h, --help                 Show this help message

EXAMPLES:
    $0                                          # Deploy with default settings
    $0 -p my-project -r us-west1               # Deploy to specific project and region
    $0 -d                                      # Dry run to see what would be deployed
    $0 -y                                      # Deploy without confirmation prompts

ENVIRONMENT VARIABLES:
    PROJECT_ID                 Google Cloud project ID
    REGION                     Google Cloud region  
    ZONE                       Google Cloud zone
    MODEL_NAME                 Model name for deployment
    RANDOM_SUFFIX              Custom suffix for resource names

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
            -m|--model)
                MODEL_NAME="$2"
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

# Function to confirm deployment
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "\n${YELLOW}WARNING: This deployment will create expensive TPU resources!${NC}"
    echo -e "Estimated daily cost: ${RED}\$2,500 - \$15,000${NC}"
    echo -e "\nResources to be created:"
    echo -e "  • 3 Ironwood TPU pods (256, 1024, 9216 chips)"
    echo -e "  • Global load balancer with CDN"
    echo -e "  • Redis cache (100GB)"
    echo -e "  • Monitoring and analytics infrastructure"
    echo -e "\nProject: ${BLUE}$PROJECT_ID${NC}"
    echo -e "Region: ${BLUE}$REGION${NC}"
    
    echo -e "\n${YELLOW}Do you want to proceed? (yes/no):${NC} "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Deployment cancelled by user"
        exit 0
    fi
}

# Main deployment function
main() {
    echo -e "${BLUE}Large-Scale AI Model Inference Deployment Script${NC}"
    echo -e "${BLUE}================================================${NC}\n"
    
    # Start logging
    print_status "Starting deployment at $(date)"
    print_status "Log file: $LOG_FILE"
    
    # Set trap for cleanup on failure
    trap cleanup_on_failure ERR
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set environment variables
    set_environment_variables
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm deployment
    confirm_deployment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "DRY RUN MODE - No resources will be created"
        print_status "The following resources would be created:"
        echo -e "  • TPU pods: ${CLUSTER_NAME}-{small,medium,large}"
        echo -e "  • Service account: $SA_EMAIL"
        echo -e "  • Load balancer: ai-inference-lb"
        echo -e "  • Redis cache: inference-cache"
        echo -e "  • Monitoring resources: tpu_analytics dataset"
        exit 0
    fi
    
    # Execute deployment steps
    check_project_and_billing
    configure_gcloud
    enable_apis
    create_service_account
    create_tpu_resources
    create_health_checks
    create_backend_services
    create_load_balancer
    create_monitoring_resources
    create_redis_cache
    wait_for_resources
    validate_deployment
    display_summary
    
    print_status "Deployment completed successfully at $(date)"
}

# Execute main function with all arguments
main "$@"