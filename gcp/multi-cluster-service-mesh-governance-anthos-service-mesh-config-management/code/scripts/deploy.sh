#!/bin/bash

# Multi-Cluster Service Mesh Governance Deployment Script
# This script deploys Anthos Service Mesh with Config Management across multiple GKE clusters
# 
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   --project-id PROJECT_ID     Specify GCP project ID (optional, generates unique if not provided)
#   --region REGION            Specify GCP region (default: us-central1)
#   --zone ZONE                Specify GCP zone (default: us-central1-a)
#   --dry-run                  Preview commands without executing
#   --help                     Show this help message

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DRY_RUN=false

# Initialize variables
PROJECT_ID=""
REGION="$DEFAULT_REGION"
ZONE="$DEFAULT_ZONE"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
Multi-Cluster Service Mesh Governance Deployment Script

This script deploys a complete multi-cluster service mesh governance solution using:
- Google Kubernetes Engine (GKE) clusters
- Anthos Service Mesh for traffic management and security
- Anthos Config Management for GitOps-driven policy enforcement
- Binary Authorization for container image security

Usage: $0 [OPTIONS]

Options:
  --project-id PROJECT_ID     Specify GCP project ID (optional, generates unique if not provided)
  --region REGION            Specify GCP region (default: $DEFAULT_REGION)
  --zone ZONE                Specify GCP zone (default: $DEFAULT_ZONE)
  --dry-run                  Preview commands without executing
  --help                     Show this help message

Examples:
  $0                                           # Deploy with auto-generated project
  $0 --project-id my-project-123              # Deploy to specific project
  $0 --region europe-west1 --zone europe-west1-b  # Deploy to different region/zone
  $0 --dry-run                                # Preview deployment commands

Prerequisites:
  - Google Cloud CLI (gcloud) installed and authenticated
  - kubectl CLI tool installed
  - Appropriate GCP permissions (Owner or Editor recommended)
  - Git client installed

Estimated deployment time: 20-30 minutes
Estimated cost: \$150-300/month for 3 GKE clusters

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --zone)
                ZONE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="${2:-Executing command}"
    
    log_info "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: $cmd"
    else
        echo "Executing: $cmd" >> "$LOG_FILE"
        eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
        local exit_code=${PIPESTATUS[0]}
        if [[ $exit_code -ne 0 ]]; then
            log_error "Command failed with exit code $exit_code: $cmd"
            return $exit_code
        fi
    fi
}

# Prerequisite checks
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check git
    if ! command -v git &> /dev/null; then
        log_error "git is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log "✅ All prerequisites met"
}

# Generate project ID if not provided
generate_project_id() {
    if [[ -z "$PROJECT_ID" ]]; then
        local timestamp=$(date +%s)
        PROJECT_ID="service-mesh-gov-${timestamp}"
        log "Generated project ID: $PROJECT_ID"
    fi
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    local random_suffix=$(openssl rand -hex 3)
    
    export PROJECT_ID
    export REGION
    export ZONE
    export PROD_CLUSTER="prod-cluster-${random_suffix}"
    export STAGING_CLUSTER="staging-cluster-${random_suffix}"
    export DEV_CLUSTER="dev-cluster-${random_suffix}"
    
    log "Environment configured:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Zone: $ZONE"
    log "  Production cluster: $PROD_CLUSTER"
    log "  Staging cluster: $STAGING_CLUSTER"
    log "  Development cluster: $DEV_CLUSTER"
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID="$PROJECT_ID"
REGION="$REGION"
ZONE="$ZONE"
PROD_CLUSTER="$PROD_CLUSTER"
STAGING_CLUSTER="$STAGING_CLUSTER"
DEV_CLUSTER="$DEV_CLUSTER"
EOF
    
    log "✅ Environment variables saved to ${SCRIPT_DIR}/.env"
}

# Configure GCP project and enable APIs
setup_gcp_project() {
    log "Setting up GCP project and enabling APIs..."
    
    # Set default project and region
    execute_cmd "gcloud config set project ${PROJECT_ID}" "Setting default project"
    execute_cmd "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_cmd "gcloud config set compute/zone ${ZONE}" "Setting default zone"
    
    # Enable required APIs
    local apis=(
        "container.googleapis.com"
        "mesh.googleapis.com"
        "gkehub.googleapis.com"
        "sourcerepo.googleapis.com"
        "binaryauthorization.googleapis.com"
        "containeranalysis.googleapis.com"
        "artifactregistry.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    log "Enabling required APIs..."
    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable $api" "Enabling $api"
        sleep 2  # Brief pause to avoid quota issues
    done
    
    log "✅ GCP project configured and APIs enabled"
}

# Create supporting resources
create_supporting_resources() {
    log "Creating supporting resources..."
    
    # Create Artifact Registry for container images
    execute_cmd "gcloud artifacts repositories create secure-apps \
        --repository-format=docker \
        --location=${REGION} \
        --description='Secure container images repository'" \
        "Creating Artifact Registry repository"
    
    # Create Git repository for configuration management
    execute_cmd "gcloud source repos create anthos-config-management" \
        "Creating Git repository for configuration management"
    
    log "✅ Supporting resources created"
}

# Create GKE clusters
create_gke_clusters() {
    log "Creating GKE clusters..."
    
    # Create production cluster
    execute_cmd "gcloud container clusters create ${PROD_CLUSTER} \
        --zone=${ZONE} \
        --machine-type=e2-standard-4 \
        --num-nodes=3 \
        --enable-ip-alias \
        --enable-autorepair \
        --enable-autoupgrade \
        --enable-workload-identity \
        --labels='env=production,mesh=enabled' \
        --logging=SYSTEM,WORKLOAD \
        --monitoring=SYSTEM \
        --async" \
        "Creating production GKE cluster"
    
    # Create staging cluster
    execute_cmd "gcloud container clusters create ${STAGING_CLUSTER} \
        --zone=${ZONE} \
        --machine-type=e2-standard-2 \
        --num-nodes=2 \
        --enable-ip-alias \
        --enable-autorepair \
        --enable-autoupgrade \
        --enable-workload-identity \
        --labels='env=staging,mesh=enabled' \
        --async" \
        "Creating staging GKE cluster"
    
    # Create development cluster
    execute_cmd "gcloud container clusters create ${DEV_CLUSTER} \
        --zone=${ZONE} \
        --machine-type=e2-standard-2 \
        --num-nodes=2 \
        --enable-ip-alias \
        --enable-autorepair \
        --enable-autoupgrade \
        --enable-workload-identity \
        --labels='env=development,mesh=enabled' \
        --async" \
        "Creating development GKE cluster"
    
    # Wait for clusters to be ready
    log "Waiting for clusters to be ready..."
    execute_cmd "gcloud container clusters list --filter='name:(${PROD_CLUSTER} OR ${STAGING_CLUSTER} OR ${DEV_CLUSTER})' --format='table(name,status)'" \
        "Checking cluster status"
    
    # Wait for all clusters to be running
    local clusters=("$PROD_CLUSTER" "$STAGING_CLUSTER" "$DEV_CLUSTER")
    for cluster in "${clusters[@]}"; do
        log "Waiting for cluster $cluster to be ready..."
        while true; do
            local status=$(gcloud container clusters describe "$cluster" --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
            if [[ "$status" == "RUNNING" ]]; then
                log "✅ Cluster $cluster is ready"
                break
            elif [[ "$status" == "NOT_FOUND" || "$status" == "ERROR" ]]; then
                log_error "Cluster $cluster failed to create"
                exit 1
            else
                log_info "Cluster $cluster status: $status (waiting...)"
                sleep 30
            fi
        done
    done
    
    log "✅ All GKE clusters created successfully"
}

# Register clusters to fleet and enable service mesh
setup_fleet_and_service_mesh() {
    log "Registering clusters to fleet and enabling service mesh..."
    
    # Get cluster credentials
    execute_cmd "gcloud container clusters get-credentials ${PROD_CLUSTER} --zone=${ZONE}" \
        "Getting production cluster credentials"
    execute_cmd "gcloud container clusters get-credentials ${STAGING_CLUSTER} --zone=${ZONE}" \
        "Getting staging cluster credentials"
    execute_cmd "gcloud container clusters get-credentials ${DEV_CLUSTER} --zone=${ZONE}" \
        "Getting development cluster credentials"
    
    # Register clusters to fleet
    execute_cmd "gcloud container fleet memberships register prod-membership \
        --gke-cluster=${ZONE}/${PROD_CLUSTER} \
        --enable-workload-identity" \
        "Registering production cluster to fleet"
    
    execute_cmd "gcloud container fleet memberships register staging-membership \
        --gke-cluster=${ZONE}/${STAGING_CLUSTER} \
        --enable-workload-identity" \
        "Registering staging cluster to fleet"
    
    execute_cmd "gcloud container fleet memberships register dev-membership \
        --gke-cluster=${ZONE}/${DEV_CLUSTER} \
        --enable-workload-identity" \
        "Registering development cluster to fleet"
    
    # Enable Service Mesh feature on the fleet
    execute_cmd "gcloud container fleet mesh enable" \
        "Enabling service mesh on fleet"
    
    # Apply managed service mesh to all clusters
    execute_cmd "gcloud container fleet mesh update \
        --memberships=prod-membership,staging-membership,dev-membership \
        --management=MANAGEMENT_AUTOMATIC \
        --control-plane=AUTOMATIC" \
        "Enabling managed service mesh on all clusters"
    
    log "✅ Fleet registration and service mesh configuration completed"
}

# Configure cross-cluster service discovery
configure_cross_cluster_discovery() {
    log "Configuring cross-cluster service discovery..."
    
    # Wait for service mesh to be ready
    log "Waiting for service mesh to be ready..."
    sleep 120
    
    # Create cross-cluster gateway for production
    execute_cmd "kubectl apply --context=gke_${PROJECT_ID}_${ZONE}_${PROD_CLUSTER} -f - << 'EOF'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: cross-cluster-gateway
  namespace: istio-system
spec:
  selector:
    istio: eastwestgateway
  servers:
    - port:
        number: 15021
        name: status-port
        protocol: HTTP
      hosts:
        - '*'
EOF" "Creating cross-cluster gateway for production"
    
    # Create cross-cluster gateway for staging
    execute_cmd "kubectl apply --context=gke_${PROJECT_ID}_${ZONE}_${STAGING_CLUSTER} -f - << 'EOF'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: cross-cluster-gateway
  namespace: istio-system
spec:
  selector:
    istio: eastwestgateway
  servers:
    - port:
        number: 15021
        name: status-port
        protocol: HTTP
      hosts:
        - '*'
EOF" "Creating cross-cluster gateway for staging"
    
    # Create cross-cluster gateway for development
    execute_cmd "kubectl apply --context=gke_${PROJECT_ID}_${ZONE}_${DEV_CLUSTER} -f - << 'EOF'
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: cross-cluster-gateway
  namespace: istio-system
spec:
  selector:
    istio: eastwestgateway
  servers:
    - port:
        number: 15021
        name: status-port
        protocol: HTTP
      hosts:
        - '*'
EOF" "Creating cross-cluster gateway for development"
    
    log "✅ Cross-cluster service discovery configured"
}

# Set up Anthos Config Management
setup_config_management() {
    log "Setting up Anthos Config Management..."
    
    # Create temporary directory for configuration
    local config_dir=$(mktemp -d)
    cd "$config_dir"
    
    # Clone the configuration repository
    execute_cmd "gcloud source repos clone anthos-config-management --project=${PROJECT_ID}" \
        "Cloning configuration repository"
    
    cd anthos-config-management
    
    # Create directory structure
    execute_cmd "mkdir -p config-root/{namespaces,cluster,system}" \
        "Creating configuration directory structure"
    execute_cmd "mkdir -p config-root/namespaces/{production,staging,development}" \
        "Creating namespace directories"
    
    # Create root configuration
    cat > config-root/system/repo.yaml << 'EOF'
apiVersion: configmanagement.gke.io/v1
kind: Repo
metadata:
  name: repo
spec:
  version: "1.0.0"
EOF
    
    # Create namespace configurations
    cat > config-root/namespaces/production/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    env: production
    istio-injection: enabled
EOF
    
    cat > config-root/namespaces/staging/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: staging
  labels:
    env: staging
    istio-injection: enabled
EOF
    
    cat > config-root/namespaces/development/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: development
  labels:
    env: development
    istio-injection: enabled
EOF
    
    # Commit initial configuration
    execute_cmd "git add ." "Adding initial configuration to git"
    execute_cmd "git -c user.email='deploy@example.com' -c user.name='Deploy Script' commit -m 'Initial Anthos Config Management setup'" \
        "Committing initial configuration"
    execute_cmd "git push origin master" "Pushing initial configuration"
    
    # Return to script directory
    cd "$SCRIPT_DIR"
    rm -rf "$config_dir"
    
    log "✅ Anthos Config Management repository configured"
}

# Configure service mesh security policies
configure_security_policies() {
    log "Configuring service mesh security policies..."
    
    # Create temporary directory for security configuration
    local config_dir=$(mktemp -d)
    cd "$config_dir"
    
    # Clone the configuration repository
    execute_cmd "gcloud source repos clone anthos-config-management --project=${PROJECT_ID}" \
        "Cloning configuration repository for security policies"
    
    cd anthos-config-management
    
    # Create strict mutual TLS policy
    cat > config-root/cluster/strict-mtls-policy.yaml << 'EOF'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: production-strict
  namespace: production
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: staging-strict
  namespace: staging
spec:
  mtls:
    mode: STRICT
EOF
    
    # Create authorization policies
    cat > config-root/namespaces/production/authz-policy.yaml << 'EOF'
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: production-access-control
  namespace: production
spec:
  selector:
    matchLabels:
      env: production
  rules:
  - from:
    - source:
        namespaces: ["production"]
    - source:
        namespaces: ["staging"]
        principals: ["cluster.local/ns/staging/sa/staging-service"]
    to:
    - operation:
        methods: ["GET", "POST"]
EOF
    
    # Create network policies
    cat > config-root/namespaces/production/network-policy.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: production-network-policy
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: production
    - namespaceSelector:
        matchLabels:
          name: istio-system
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: production
    - namespaceSelector:
        matchLabels:
          name: istio-system
  - to: []
    ports:
    - protocol: TCP
      port: 443
EOF
    
    # Commit security policies
    execute_cmd "git add ." "Adding security policies to git"
    execute_cmd "git -c user.email='deploy@example.com' -c user.name='Deploy Script' commit -m 'Add service mesh security policies'" \
        "Committing security policies"
    execute_cmd "git push origin master" "Pushing security policies"
    
    # Return to script directory
    cd "$SCRIPT_DIR"
    rm -rf "$config_dir"
    
    log "✅ Service mesh security policies configured"
}

# Configure Binary Authorization
configure_binary_authorization() {
    log "Configuring Binary Authorization..."
    
    # Create Binary Authorization policy
    local policy_file=$(mktemp)
    cat > "$policy_file" << EOF
admissionWhitelistPatterns:
- namePattern: gcr.io/google-containers/*
- namePattern: gcr.io/google_containers/*
- namePattern: k8s.gcr.io/*
- namePattern: gke.gcr.io/*
- namePattern: gcr.io/stackdriver-agents/*
clusterAdmissionRules:
  ${ZONE}.${PROD_CLUSTER}:
    requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/production-attestor
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
    evaluationMode: REQUIRE_ATTESTATION
  ${ZONE}.${STAGING_CLUSTER}:
    requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/staging-attestor
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
    evaluationMode: REQUIRE_ATTESTATION
defaultAdmissionRule:
  requireAttestationsBy: []
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: ALWAYS_DENY
name: projects/${PROJECT_ID}/policy
EOF
    
    # Apply Binary Authorization policy
    execute_cmd "gcloud container binauthz policy import $policy_file" \
        "Applying Binary Authorization policy"
    
    # Create attestors for production and staging
    execute_cmd "gcloud container binauthz attestors create production-attestor \
        --attestation-authority-note-project=${PROJECT_ID} \
        --attestation-authority-note=production-note \
        --description='Production environment attestor'" \
        "Creating production attestor"
    
    execute_cmd "gcloud container binauthz attestors create staging-attestor \
        --attestation-authority-note-project=${PROJECT_ID} \
        --attestation-authority-note=staging-note \
        --description='Staging environment attestor'" \
        "Creating staging attestor"
    
    # Clean up temporary file
    rm -f "$policy_file"
    
    log "✅ Binary Authorization configured"
}

# Deploy Config Management to clusters
deploy_config_management() {
    log "Deploying Config Management to clusters..."
    
    # Create Config Management configuration
    local config_file=$(mktemp)
    cat > "$config_file" << EOF
apiVersion: configmanagement.gke.io/v1
kind: ConfigManagement
metadata:
  name: config-management
spec:
  git:
    syncRepo: https://source.developers.google.com/p/${PROJECT_ID}/r/anthos-config-management
    syncBranch: master
    secretType: none
    policyDir: config-root
  sourceFormat: unstructured
  enableMultiRepo: false
EOF
    
    # Apply Config Management to all clusters
    execute_cmd "kubectl apply --context=gke_${PROJECT_ID}_${ZONE}_${PROD_CLUSTER} -f $config_file" \
        "Applying Config Management to production cluster"
    execute_cmd "kubectl apply --context=gke_${PROJECT_ID}_${ZONE}_${STAGING_CLUSTER} -f $config_file" \
        "Applying Config Management to staging cluster"
    execute_cmd "kubectl apply --context=gke_${PROJECT_ID}_${ZONE}_${DEV_CLUSTER} -f $config_file" \
        "Applying Config Management to development cluster"
    
    # Clean up temporary file
    rm -f "$config_file"
    
    # Wait for Config Management to sync
    log "Waiting for Config Management to sync..."
    sleep 60
    
    log "✅ Config Management deployed to all clusters"
}

# Configure observability and monitoring
configure_observability() {
    log "Configuring observability and monitoring..."
    
    # Create monitoring dashboard
    local dashboard_file=$(mktemp)
    cat > "$dashboard_file" << 'EOF'
{
  "displayName": "Service Mesh Governance Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Service Mesh Request Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum(rate(istio_requests_total[5m])) by (source_app, destination_service_name)"
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "mTLS Policy Compliance",
          "scorecard": {
            "timeSeriesQuery": {
              "prometheusQuery": "sum(istio_requests_total{security_policy=\"mutual_tls\"}) / sum(istio_requests_total)"
            }
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the monitoring dashboard
    execute_cmd "gcloud monitoring dashboards create --config-from-file=$dashboard_file" \
        "Creating monitoring dashboard"
    
    # Clean up temporary file
    rm -f "$dashboard_file"
    
    log "✅ Observability and monitoring configured"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    # Check fleet membership status
    execute_cmd "gcloud container fleet memberships list" \
        "Checking fleet membership status"
    
    # Check service mesh status
    execute_cmd "gcloud container fleet mesh describe" \
        "Checking service mesh status"
    
    # Check pods in istio-system namespace for each cluster
    local clusters=("$PROD_CLUSTER" "$STAGING_CLUSTER" "$DEV_CLUSTER")
    for cluster in "${clusters[@]}"; do
        log_info "Checking Istio system pods in $cluster..."
        execute_cmd "kubectl get pods -n istio-system --context=gke_${PROJECT_ID}_${ZONE}_${cluster}" \
            "Checking Istio pods in $cluster"
    done
    
    # Check Config Management sync status
    execute_cmd "kubectl get configmanagement --context=gke_${PROJECT_ID}_${ZONE}_${PROD_CLUSTER}" \
        "Checking Config Management status"
    
    # Check namespaces
    execute_cmd "kubectl get namespaces --show-labels --context=gke_${PROJECT_ID}_${ZONE}_${PROD_CLUSTER}" \
        "Checking namespace configuration"
    
    log "✅ Deployment validation completed"
}

# Display deployment summary
show_deployment_summary() {
    log "🎉 Multi-Cluster Service Mesh Governance deployment completed successfully!"
    echo
    log "Deployment Summary:"
    log "==================="
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Zone: $ZONE"
    echo
    log "Clusters Created:"
    log "- Production: $PROD_CLUSTER"
    log "- Staging: $STAGING_CLUSTER" 
    log "- Development: $DEV_CLUSTER"
    echo
    log "Services Configured:"
    log "- ✅ Anthos Service Mesh with managed control plane"
    log "- ✅ Fleet Management for centralized cluster control"
    log "- ✅ Anthos Config Management with GitOps workflow"
    log "- ✅ Binary Authorization for container security"
    log "- ✅ Cross-cluster service discovery"
    log "- ✅ Comprehensive security policies (mTLS, AuthZ, NetworkPolicy)"
    log "- ✅ Observability and monitoring dashboard"
    echo
    log "Next Steps:"
    log "1. Access the monitoring dashboard in Google Cloud Console"
    log "2. Review the GitOps repository: https://source.developers.google.com/p/${PROJECT_ID}/r/anthos-config-management"
    log "3. Deploy sample applications to test the service mesh"
    log "4. Configure additional security policies as needed"
    echo
    log "Cleanup:"
    log "To remove all resources, run: ./destroy.sh"
    echo
    log "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log "Deployment log available at: $LOG_FILE"
}

# Main execution function
main() {
    # Initialize log file
    echo "=== Multi-Cluster Service Mesh Governance Deployment Started at $(date) ===" > "$LOG_FILE"
    
    log "Starting Multi-Cluster Service Mesh Governance deployment..."
    log "Script version: 1.0.0"
    
    parse_args "$@"
    check_prerequisites
    generate_project_id
    setup_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No actual resources will be created"
        echo
    fi
    
    setup_gcp_project
    create_supporting_resources
    create_gke_clusters
    setup_fleet_and_service_mesh
    configure_cross_cluster_discovery
    setup_config_management
    configure_security_policies
    configure_binary_authorization
    deploy_config_management
    configure_observability
    
    if [[ "$DRY_RUN" != "true" ]]; then
        validate_deployment
        show_deployment_summary
    else
        log "DRY RUN completed. No resources were created."
    fi
    
    log "=== Deployment completed at $(date) ==="
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Exit code: $?"; exit 1' ERR

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi