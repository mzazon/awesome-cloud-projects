#!/bin/bash

# Real-Time Inventory Intelligence with Google Distributed Cloud Edge and Cloud Vision
# Deployment Script
# 
# This script deploys the complete infrastructure for real-time inventory intelligence
# using Google Distributed Cloud Edge and Cloud Vision API

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling function
handle_error() {
    log_error "An error occurred on line $1. Exiting."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log "Google Cloud SDK version: $GCLOUD_VERSION"
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it: gcloud components install kubectl"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK with gsutil component"
        exit 1
    fi
    
    # Check if openssl is installed (for random generation)
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl for random string generation"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project and permissions
validate_project() {
    log "Validating project and permissions..."
    
    # Check if project is set
    if [ -z "${PROJECT_ID:-}" ]; then
        log_error "PROJECT_ID is not set. Please set it before running this script."
        exit 1
    fi
    
    # Verify project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or you don't have access to it"
        exit 1
    fi
    
    # Check billing is enabled
    BILLING_ENABLED=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null || echo "false")
    if [ "$BILLING_ENABLED" != "True" ]; then
        log_warning "Billing may not be enabled for project '$PROJECT_ID'. Some services may not work."
    fi
    
    log_success "Project validation completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "vision.googleapis.com"
        "sql-component.googleapis.com"
        "monitoring.googleapis.com"
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: $api"
        if gcloud services enable "$api" --project="$PROJECT_ID"; then
            log_success "API $api enabled successfully"
        else
            log_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Cloud SQL database
create_database() {
    log "Creating Cloud SQL database for inventory management..."
    
    # Check if instance already exists
    if gcloud sql instances describe "$DB_INSTANCE_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Cloud SQL instance '$DB_INSTANCE_NAME' already exists, skipping creation"
        return
    fi
    
    # Create Cloud SQL instance
    log "Creating Cloud SQL instance: $DB_INSTANCE_NAME"
    gcloud sql instances create "$DB_INSTANCE_NAME" \
        --database-version=POSTGRES_14 \
        --tier=db-f1-micro \
        --region="$REGION" \
        --storage-type=SSD \
        --storage-size=20GB \
        --backup-start-time=03:00 \
        --project="$PROJECT_ID"
    
    # Set root password
    log "Setting database password..."
    gcloud sql users set-password postgres \
        --instance="$DB_INSTANCE_NAME" \
        --password="$DB_PASSWORD" \
        --project="$PROJECT_ID"
    
    # Create inventory database
    log "Creating inventory_intelligence database..."
    gcloud sql databases create inventory_intelligence \
        --instance="$DB_INSTANCE_NAME" \
        --project="$PROJECT_ID"
    
    log_success "Cloud SQL database created and configured"
}

# Function to create storage bucket
create_storage() {
    log "Setting up Cloud Storage for image processing..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        log_warning "Storage bucket '$BUCKET_NAME' already exists, skipping creation"
        return
    fi
    
    # Create storage bucket
    log "Creating storage bucket: $BUCKET_NAME"
    gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://$BUCKET_NAME"
    
    # Configure bucket for Vision API access
    log "Configuring bucket permissions for Vision API..."
    gsutil iam ch "serviceAccount:service-$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')@gcp-sa-vision.iam.gserviceaccount.com:objectViewer" \
        "gs://$BUCKET_NAME"
    
    # Set lifecycle policy for cost optimization
    log "Setting up lifecycle policy..."
    cat > /tmp/lifecycle.json << EOF
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 30}
    }
  ]
}
EOF
    
    gsutil lifecycle set /tmp/lifecycle.json "gs://$BUCKET_NAME"
    rm -f /tmp/lifecycle.json
    
    log_success "Cloud Storage bucket configured with lifecycle policy"
}

# Function to create service account
create_service_account() {
    log "Creating service account for edge processing..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Service account '$SERVICE_ACCOUNT_EMAIL' already exists, skipping creation"
    else
        # Create service account
        log "Creating service account: inventory-edge-processor"
        gcloud iam service-accounts create inventory-edge-processor \
            --display-name="Inventory Edge Processor" \
            --description="Service account for edge inventory processing" \
            --project="$PROJECT_ID"
    fi
    
    # Grant necessary permissions
    log "Granting IAM permissions..."
    local roles=(
        "roles/ml.developer"
        "roles/cloudsql.client"
        "roles/storage.objectAdmin"
        "roles/monitoring.metricWriter"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        log "Granting role: $role"
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
            --role="$role" \
            --quiet
    done
    
    # Create and download service account key if it doesn't exist
    if [ ! -f "inventory-edge-key.json" ]; then
        log "Creating service account key..."
        gcloud iam service-accounts keys create inventory-edge-key.json \
            --iam-account="$SERVICE_ACCOUNT_EMAIL" \
            --project="$PROJECT_ID"
    else
        log_warning "Service account key already exists, skipping creation"
    fi
    
    log_success "Service account created with appropriate permissions"
}

# Function to configure Vision API
configure_vision_api() {
    log "Configuring Cloud Vision API integration..."
    
    # Check if product set already exists
    if gcloud ml vision product-sets describe "retail_inventory_set" \
        --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Product set 'retail_inventory_set' already exists, skipping creation"
    else
        # Create a Product Set for inventory items
        log "Creating product set for retail inventory..."
        gcloud ml vision product-sets create \
            --display-name="Retail Inventory Products" \
            --product-set-id="retail_inventory_set" \
            --location="$REGION" \
            --project="$PROJECT_ID"
    fi
    
    # Check if sample product already exists
    if gcloud ml vision products describe "sample_product_001" \
        --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Sample product already exists, skipping creation"
    else
        # Create sample product for demonstration
        log "Creating sample product..."
        gcloud ml vision products create \
            --display-name="Sample Product" \
            --product-category="packagedgoods" \
            --product-id="sample_product_001" \
            --location="$REGION" \
            --project="$PROJECT_ID"
        
        # Add product to product set
        log "Adding product to product set..."
        gcloud ml vision product-sets add-product \
            --product-set-id="retail_inventory_set" \
            --product-id="sample_product_001" \
            --location="$REGION" \
            --project="$PROJECT_ID"
    fi
    
    log_success "Cloud Vision API configured for product recognition"
}

# Function to set up monitoring
setup_monitoring() {
    log "Setting up monitoring dashboard and alerting..."
    
    # Create custom dashboard for inventory monitoring
    log "Creating monitoring dashboard..."
    cat > /tmp/inventory-dashboard.json << EOF
{
  "displayName": "Inventory Intelligence Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Inventory Levels by Location",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"global\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Edge Processing Latency",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"k8s_container\" AND metadata.user_labels.app=\"inventory-processor\"",
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
    
    if gcloud monitoring dashboards create --config-from-file=/tmp/inventory-dashboard.json --project="$PROJECT_ID"; then
        log_success "Monitoring dashboard created"
    else
        log_warning "Failed to create monitoring dashboard, but continuing deployment"
    fi
    
    rm -f /tmp/inventory-dashboard.json
    
    log_success "Monitoring setup completed"
}

# Function to create Kubernetes deployment (if cluster exists)
deploy_edge_application() {
    log "Deploying edge processing application..."
    
    # Note: This assumes Google Distributed Cloud Edge cluster is already set up
    # In a real scenario, you would need to connect to your edge cluster
    
    log_warning "Google Distributed Cloud Edge cluster setup requires physical hardware deployment"
    log_warning "Please ensure your edge cluster is configured and kubectl context is set"
    
    # Check if kubectl can connect to a cluster
    if ! kubectl cluster-info &>/dev/null; then
        log_warning "No Kubernetes cluster available. Skipping edge application deployment."
        log_warning "Please configure your Google Distributed Cloud Edge cluster and run:"
        log_warning "kubectl apply -f ../kubernetes/inventory-processor-deployment.yaml"
        return
    fi
    
    # Create Kubernetes deployment manifest for edge processing
    mkdir -p ../kubernetes
    cat > ../kubernetes/inventory-processor-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-processor
  namespace: default
  labels:
    app: inventory-processor
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inventory-processor
  template:
    metadata:
      labels:
        app: inventory-processor
    spec:
      serviceAccountName: inventory-edge-processor
      containers:
      - name: processor
        image: gcr.io/google-samples/vision-product-search:latest
        env:
        - name: PROJECT_ID
          value: "$PROJECT_ID"
        - name: BUCKET_NAME
          value: "$BUCKET_NAME"
        - name: DB_INSTANCE_CONNECTION
          value: "$PROJECT_ID:$REGION:$DB_INSTANCE_NAME"
        - name: GOOGLE_APPLICATION_CREDENTIALS
          value: "/var/secrets/google/key.json"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: google-cloud-key
          mountPath: /var/secrets/google
      - name: cloud-sql-proxy
        image: gcr.io/cloudsql-docker/gce-proxy:1.33.2
        command:
        - "/cloud_sql_proxy"
        - "-instances=$PROJECT_ID:$REGION:$DB_INSTANCE_NAME=tcp:5432"
        securityContext:
          runAsNonRoot: true
      volumes:
      - name: google-cloud-key
        secret:
          secretName: google-cloud-key
---
apiVersion: v1
kind: Service
metadata:
  name: inventory-processor
  labels:
    app: inventory-processor
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: inventory-processor
---
apiVersion: v1
kind: Secret
metadata:
  name: google-cloud-key
type: Opaque
data:
  key.json: $(base64 -w 0 < inventory-edge-key.json)
EOF
    
    log "Applying Kubernetes deployment..."
    if kubectl apply -f ../kubernetes/inventory-processor-deployment.yaml; then
        log_success "Edge processing application deployed successfully"
    else
        log_warning "Failed to deploy edge application. Please check your cluster connectivity."
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Database Instance: $DB_INSTANCE_NAME"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Service Account: $SERVICE_ACCOUNT_EMAIL"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Configure your Google Distributed Cloud Edge cluster"
    echo "2. Deploy the edge processing application using the generated Kubernetes manifests"
    echo "3. Configure IP cameras at retail locations"
    echo "4. Test the system with sample images"
    echo
    echo "=== IMPORTANT FILES ==="
    echo "- Service Account Key: inventory-edge-key.json (keep secure!)"
    echo "- Kubernetes Manifests: ../kubernetes/inventory-processor-deployment.yaml"
    echo
    echo "=== MONITORING ==="
    echo "- Dashboard: https://console.cloud.google.com/monitoring/dashboards"
    echo "- Cloud SQL: https://console.cloud.google.com/sql/instances"
    echo "- Storage: https://console.cloud.google.com/storage/browser/$BUCKET_NAME"
    echo
}

# Main deployment function
main() {
    log "Starting Real-Time Inventory Intelligence deployment..."
    
    # Set environment variables
    export PROJECT_ID="${PROJECT_ID:-inventory-intelligence-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export CLUSTER_NAME="${CLUSTER_NAME:-inventory-edge-cluster}"
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DB_INSTANCE_NAME="${DB_INSTANCE_NAME:-inventory-db-${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-inventory-images-${RANDOM_SUFFIX}}"
    export DB_PASSWORD="${DB_PASSWORD:-SecureInventoryPass123!}"
    export SERVICE_ACCOUNT_EMAIL="inventory-edge-processor@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    # Run deployment steps
    check_prerequisites
    validate_project
    enable_apis
    create_database
    create_storage
    create_service_account
    configure_vision_api
    setup_monitoring
    deploy_edge_application
    show_deployment_summary
    
    log_success "Deployment script completed successfully!"
}

# Parse command line arguments
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
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id PROJECT_ID    Google Cloud Project ID"
            echo "  --region REGION           Google Cloud Region (default: us-central1)"
            echo "  --help                    Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"