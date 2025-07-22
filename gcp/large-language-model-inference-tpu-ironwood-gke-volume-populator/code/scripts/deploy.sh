#!/bin/bash
set -euo pipefail

# Large Language Model Inference with TPU Ironwood and GKE Volume Populator - Deployment Script
# This script deploys the complete infrastructure for high-performance LLM inference

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration variables
PROJECT_ID="${PROJECT_ID:-llm-inference-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
CLUSTER_NAME="${CLUSTER_NAME:-tpu-ironwood-cluster}"
RANDOM_SUFFIX=$(openssl rand -hex 3)
BUCKET_NAME="${BUCKET_NAME:-llm-models-${RANDOM_SUFFIX}}"
PARALLELSTORE_NAME="${PARALLELSTORE_NAME:-model-storage-${RANDOM_SUFFIX}}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-tpu-inference-sa-${RANDOM_SUFFIX}}"
MODEL_PATH="${MODEL_PATH:-}"
DRY_RUN="${DRY_RUN:-false}"

# Display configuration
display_config() {
    log "Deployment Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Zone: $ZONE"
    echo "  Cluster Name: $CLUSTER_NAME"
    echo "  Bucket Name: $BUCKET_NAME"
    echo "  Parallelstore Name: $PARALLELSTORE_NAME"
    echo "  Service Account: $SERVICE_ACCOUNT"
    echo "  Model Path: ${MODEL_PATH:-'Not specified - will use placeholder'}"
    echo "  Dry Run: $DRY_RUN"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud CLI."
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null)
    if [[ -z "$gcloud_version" ]]; then
        error "Unable to determine gcloud version."
        exit 1
    fi
    success "gcloud CLI version: $gcloud_version"
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install kubectl."
        exit 1
    fi
    success "kubectl found"
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Required for generating random strings."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud CLI with gsutil."
        exit 1
    fi
    success "gsutil found"
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    success "Google Cloud authentication verified"
    
    # Warn about TPU Ironwood availability
    warn "TPU Ironwood is in limited preview and requires explicit quota approval."
    warn "Contact Google Cloud sales if you haven't already obtained access."
    
    # Estimate costs
    warn "Estimated costs: \$1,200-2,500 per hour for TPU Ironwood pods during active inference"
    
    success "Prerequisites check completed"
}

# Configure gcloud
configure_gcloud() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would configure gcloud for project: $PROJECT_ID"
        return
    fi
    
    log "Configuring gcloud CLI..."
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    success "gcloud configured for project $PROJECT_ID"
}

# Enable required APIs
enable_apis() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would enable required Google Cloud APIs"
        return
    fi
    
    log "Enabling required Google Cloud APIs..."
    local apis=(
        "container.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "parallelstore.googleapis.com"
        "compute.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            success "Enabled $api"
        else
            error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to propagate
    log "Waiting for APIs to propagate..."
    sleep 30
    success "All required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Cloud Storage bucket: gs://$BUCKET_NAME"
        return
    fi
    
    log "Creating Cloud Storage bucket for model artifacts..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        warn "Bucket gs://$BUCKET_NAME already exists, skipping creation"
    else
        if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
            success "Created bucket: gs://$BUCKET_NAME"
        else
            error "Failed to create bucket: gs://$BUCKET_NAME"
            exit 1
        fi
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://$BUCKET_NAME"
    success "Enabled versioning on bucket"
    
    # Upload model artifacts if path is provided
    if [[ -n "$MODEL_PATH" && -d "$MODEL_PATH" ]]; then
        log "Uploading model artifacts from $MODEL_PATH..."
        gsutil -m cp -r "$MODEL_PATH"/* "gs://$BUCKET_NAME/models/llm-7b/"
        success "Model artifacts uploaded"
    else
        warn "No model path provided. You'll need to upload model artifacts manually to gs://$BUCKET_NAME/models/llm-7b/"
    fi
}

# Create service account
create_service_account() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create service account: $SERVICE_ACCOUNT"
        return
    fi
    
    log "Creating service account for TPU inference..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
        warn "Service account $SERVICE_ACCOUNT already exists, skipping creation"
    else
        if gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
            --display-name="TPU Inference Service Account" \
            --description="Service account for LLM inference with TPU Ironwood"; then
            success "Created service account: $SERVICE_ACCOUNT"
        else
            error "Failed to create service account"
            exit 1
        fi
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/tpu.admin"
        "roles/storage.objectViewer"
        "roles/parallelstore.admin"
    )
    
    for role in "${roles[@]}"; do
        log "Granting role $role to service account..."
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" \
            --quiet
    done
    
    success "Service account configured with necessary permissions"
}

# Create GKE cluster
create_gke_cluster() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create GKE cluster: $CLUSTER_NAME"
        return
    fi
    
    log "Creating GKE cluster with TPU Ironwood support..."
    
    # Check if cluster already exists
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" &> /dev/null; then
        warn "Cluster $CLUSTER_NAME already exists, skipping creation"
    else
        if gcloud container clusters create "$CLUSTER_NAME" \
            --zone="$ZONE" \
            --machine-type=e2-standard-4 \
            --num-nodes=2 \
            --enable-autoscaling \
            --min-nodes=1 \
            --max-nodes=10 \
            --enable-autorepair \
            --enable-autoupgrade \
            --addons=HorizontalPodAutoscaling,HttpLoadBalancing \
            --enable-network-policy \
            --enable-ip-alias \
            --enable-workload-identity \
            --quiet; then
            success "Created GKE cluster: $CLUSTER_NAME"
        else
            error "Failed to create GKE cluster"
            exit 1
        fi
    fi
    
    # Get cluster credentials
    log "Getting cluster credentials..."
    if gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE"; then
        success "Cluster credentials configured"
    else
        error "Failed to get cluster credentials"
        exit 1
    fi
}

# Configure Workload Identity
configure_workload_identity() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would configure Workload Identity"
        return
    fi
    
    log "Configuring Workload Identity..."
    
    # Create Kubernetes service account
    if kubectl get serviceaccount tpu-inference-pod &> /dev/null; then
        warn "Kubernetes service account already exists, skipping creation"
    else
        kubectl create serviceaccount tpu-inference-pod --namespace=default
        success "Created Kubernetes service account"
    fi
    
    # Annotate with Google Service Account
    kubectl annotate serviceaccount tpu-inference-pod \
        --namespace=default \
        "iam.gke.io/gcp-service-account=${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --overwrite
    
    # Configure Workload Identity binding
    gcloud iam service-accounts add-iam-policy-binding \
        --role="roles/iam.workloadIdentityUser" \
        --member="serviceAccount:${PROJECT_ID}.svc.id.goog[default/tpu-inference-pod]" \
        "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    
    success "Workload Identity configured"
}

# Create Parallelstore instance
create_parallelstore() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Parallelstore instance: $PARALLELSTORE_NAME"
        return
    fi
    
    log "Creating Parallelstore instance for high-performance model storage..."
    
    # Check if instance already exists
    if gcloud parallelstore instances describe "$PARALLELSTORE_NAME" --location="$ZONE" &> /dev/null; then
        warn "Parallelstore instance $PARALLELSTORE_NAME already exists, skipping creation"
    else
        if gcloud parallelstore instances create "$PARALLELSTORE_NAME" \
            --location="$ZONE" \
            --capacity-gib=1024 \
            --performance-tier=SSD \
            --network="projects/${PROJECT_ID}/global/networks/default" \
            --description="High-performance storage for LLM model weights"; then
            success "Created Parallelstore instance: $PARALLELSTORE_NAME"
        else
            error "Failed to create Parallelstore instance"
            exit 1
        fi
    fi
    
    # Wait for instance to become ready
    log "Waiting for Parallelstore instance to become ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local state=$(gcloud parallelstore instances describe "$PARALLELSTORE_NAME" \
            --location="$ZONE" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "READY" ]]; then
            success "Parallelstore instance is ready"
            break
        elif [[ "$state" == "FAILED" ]]; then
            error "Parallelstore instance creation failed"
            exit 1
        else
            log "Attempt $attempt/$max_attempts: Parallelstore state is $state, waiting..."
            sleep 30
            ((attempt++))
        fi
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "Timeout waiting for Parallelstore instance to become ready"
        exit 1
    fi
}

# Set bucket IAM permissions
set_bucket_permissions() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would set bucket IAM permissions"
        return
    fi
    
    log "Setting bucket IAM permissions..."
    gsutil iam ch "serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com:objectViewer" \
        "gs://$BUCKET_NAME"
    success "Bucket IAM permissions configured"
}

# Deploy Kubernetes resources
deploy_kubernetes_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would deploy Kubernetes resources"
        return
    fi
    
    log "Deploying Kubernetes resources..."
    
    # Create GCP Data Source for Volume Populator
    log "Creating GCP Data Source..."
    kubectl apply -f - <<EOF
apiVersion: parallelstore.csi.storage.gke.io/v1
kind: GCPDataSource
metadata:
  name: llm-model-source
  namespace: default
spec:
  bucket: ${BUCKET_NAME}
  path: "models/llm-7b/"
  serviceAccount: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com
EOF

    # Create StorageClass for Parallelstore with Volume Populator
    log "Creating StorageClass..."
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: parallelstore-csi-volume-populator
provisioner: parallelstore.csi.storage.gke.io
parameters:
  instance-name: ${PARALLELSTORE_NAME}
  location: ${ZONE}
  capacity-gib: "1024"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

    # Create PersistentVolumeClaim with Volume Populator
    log "Creating PersistentVolumeClaim..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage-pvc
  namespace: default
spec:
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: 1024Gi
  storageClassName: parallelstore-csi-volume-populator
  dataSource:
    apiVersion: parallelstore.csi.storage.gke.io/v1
    kind: GCPDataSource
    name: llm-model-source
EOF

    # Deploy TPU Ironwood inference deployment
    log "Creating TPU Ironwood inference deployment..."
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tpu-ironwood-inference
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tpu-ironwood-inference
  template:
    metadata:
      labels:
        app: tpu-ironwood-inference
      annotations:
        iam.gke.io/gcp-service-account: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com
    spec:
      serviceAccountName: tpu-inference-pod
      containers:
      - name: inference-server
        image: gcr.io/gke-release/tpu-inference:latest
        resources:
          requests:
            google.com/tpu: "8"
          limits:
            google.com/tpu: "8"
        volumeMounts:
        - name: model-storage
          mountPath: /models
          readOnly: true
        env:
        - name: MODEL_PATH
          value: "/models"
        - name: TPU_NAME
          value: "ironwood-v7"
        - name: BATCH_SIZE
          value: "32"
        ports:
        - containerPort: 8080
          name: http
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 300
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-storage-pvc
EOF

    # Create service to expose inference endpoints
    log "Creating LoadBalancer service..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: tpu-inference-service
  namespace: default
  annotations:
    cloud.google.com/load-balancer-type: "External"
spec:
  type: LoadBalancer
  selector:
    app: tpu-ironwood-inference
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
    name: http
  sessionAffinity: ClientIP
EOF

    success "Kubernetes resources deployed"
}

# Wait for deployment to be ready
wait_for_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would wait for deployment to be ready"
        return
    fi
    
    log "Waiting for TPU inference deployment to be ready..."
    
    # Wait for deployment rollout
    if kubectl rollout status deployment/tpu-ironwood-inference --timeout=600s; then
        success "Deployment is ready"
    else
        error "Deployment failed to become ready"
        exit 1
    fi
    
    # Wait for external IP
    log "Waiting for LoadBalancer external IP..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local external_ip=$(kubectl get service tpu-inference-service \
            --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [[ -n "$external_ip" && "$external_ip" != "null" ]]; then
            success "LoadBalancer external IP: $external_ip"
            echo "EXTERNAL_IP=$external_ip" > .deployment_vars
            break
        else
            log "Attempt $attempt/$max_attempts: Waiting for external IP..."
            sleep 30
            ((attempt++))
        fi
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        warn "Timeout waiting for external IP. Service may still be provisioning."
    fi
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create monitoring dashboard"
        return
    fi
    
    log "Creating Cloud Monitoring dashboard..."
    
    # Create a simple dashboard configuration
    cat > dashboard_config.json <<EOF
{
  "displayName": "TPU Ironwood LLM Inference Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "TPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF

    if gcloud alpha monitoring dashboards create --config-from-file=dashboard_config.json; then
        success "Monitoring dashboard created"
    else
        warn "Failed to create monitoring dashboard (non-critical)"
    fi
    
    rm -f dashboard_config.json
}

# Display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "GKE Cluster: $CLUSTER_NAME"
    echo "Model Bucket: gs://$BUCKET_NAME"
    echo "Parallelstore: $PARALLELSTORE_NAME"
    echo "Service Account: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "Next Steps:"
        echo "1. Upload your LLM model to gs://$BUCKET_NAME/models/llm-7b/"
        echo "2. Check deployment status: kubectl get pods"
        echo "3. Get service endpoint: kubectl get service tpu-inference-service"
        echo "4. Monitor deployment: kubectl logs -l app=tpu-ironwood-inference"
        echo ""
        
        if [[ -f .deployment_vars ]]; then
            source .deployment_vars
            echo "Inference Endpoint: http://$EXTERNAL_IP"
        fi
    fi
    
    success "Deployment completed successfully!"
}

# Main execution
main() {
    log "Starting TPU Ironwood LLM Inference deployment..."
    
    display_config
    
    # Confirmation for non-dry-run
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        warn "This deployment will create billable resources in Google Cloud."
        warn "Estimated cost: \$1,200-2,500 per hour for TPU Ironwood pods."
        echo ""
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    check_prerequisites
    configure_gcloud
    enable_apis
    create_storage_bucket
    create_service_account
    create_gke_cluster
    configure_workload_identity
    create_parallelstore
    set_bucket_permissions
    deploy_kubernetes_resources
    wait_for_deployment
    create_monitoring_dashboard
    display_summary
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
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
        --model-path)
            MODEL_PATH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run          Show what would be deployed without making changes"
            echo "  --project-id ID    Google Cloud project ID"
            echo "  --region REGION    Google Cloud region (default: us-central1)"
            echo "  --zone ZONE        Google Cloud zone (default: us-central1-a)"
            echo "  --model-path PATH  Local path to model files to upload"
            echo "  --help             Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  PROJECT_ID         Google Cloud project ID"
            echo "  REGION             Google Cloud region"
            echo "  ZONE               Google Cloud zone"
            echo "  MODEL_PATH         Local path to model files"
            echo "  DRY_RUN            Set to 'true' for dry run mode"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"