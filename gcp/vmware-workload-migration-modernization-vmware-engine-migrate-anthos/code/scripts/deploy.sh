#!/bin/bash

# VMware Workload Migration and Modernization Deployment Script
# This script deploys Google Cloud VMware Engine and Migrate to Containers infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Check if user is authenticated with gcloud
check_authentication() {
    log "Checking Google Cloud authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log "Authentication check completed successfully"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set project ID (try to get from gcloud config or prompt user)
    if [ -z "${PROJECT_ID:-}" ]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            read -p "Enter your Google Cloud Project ID: " PROJECT_ID
            export PROJECT_ID
        fi
    fi
    
    # Set default values if not already set
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export VMWARE_ENGINE_REGION="${VMWARE_ENGINE_REGION:-us-central1}"
    
    # Generate unique suffixes for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export PRIVATE_CLOUD_NAME="${PRIVATE_CLOUD_NAME:-vmware-cloud-${RANDOM_SUFFIX}}"
    export GKE_CLUSTER_NAME="${GKE_CLUSTER_NAME:-modernized-apps-${RANDOM_SUFFIX}}"
    export NETWORK_NAME="${NETWORK_NAME:-vmware-network-${RANDOM_SUFFIX}}"
    export REPOSITORY_NAME="${REPOSITORY_NAME:-modernized-apps}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log "Environment variables configured:"
    info "  PROJECT_ID: ${PROJECT_ID}"
    info "  REGION: ${REGION}"
    info "  ZONE: ${ZONE}"
    info "  PRIVATE_CLOUD_NAME: ${PRIVATE_CLOUD_NAME}"
    info "  GKE_CLUSTER_NAME: ${GKE_CLUSTER_NAME}"
    info "  NETWORK_NAME: ${NETWORK_NAME}"
}

# Enable required Google Cloud APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "vmwareengine.googleapis.com"
        "container.googleapis.com"
        "artifactregistry.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "compute.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        gcloud services enable "${api}" || {
            error "Failed to enable ${api}"
            exit 1
        }
    done
    
    log "All required APIs enabled successfully"
}

# Create VPC network and subnets
create_network() {
    log "Creating VPC network and subnets..."
    
    # Create VPC network
    info "Creating VPC network: ${NETWORK_NAME}"
    gcloud compute networks create "${NETWORK_NAME}" \
        --subnet-mode=custom \
        --bgp-routing-mode=regional || {
        error "Failed to create VPC network"
        exit 1
    }
    
    # Create subnet for VMware Engine management
    info "Creating subnet for VMware Engine management"
    gcloud compute networks subnets create vmware-mgmt-subnet \
        --network="${NETWORK_NAME}" \
        --range=10.10.0.0/24 \
        --region="${REGION}" || {
        error "Failed to create VMware management subnet"
        exit 1
    }
    
    # Create firewall rules for VMware traffic
    info "Creating firewall rules for VMware HCX traffic"
    gcloud compute firewall-rules create allow-vmware-hcx \
        --network="${NETWORK_NAME}" \
        --allow=tcp:443,tcp:8043,tcp:9443,udp:500,udp:4500 \
        --source-ranges=10.0.0.0/8,192.168.0.0/16 \
        --description="Allow VMware HCX traffic" || {
        error "Failed to create firewall rules"
        exit 1
    }
    
    log "Network infrastructure created successfully"
}

# Create VMware Engine private cloud
create_vmware_engine() {
    log "Creating Google Cloud VMware Engine private cloud..."
    warn "This operation takes 30-45 minutes to complete"
    
    info "Initiating VMware Engine private cloud creation: ${PRIVATE_CLOUD_NAME}"
    gcloud vmware private-clouds create "${PRIVATE_CLOUD_NAME}" \
        --location="${VMWARE_ENGINE_REGION}" \
        --cluster=initial-cluster \
        --node-type-config=type=standard-72,count=3 \
        --network="${NETWORK_NAME}" \
        --management-range=10.10.0.0/24 \
        --vmware-engine-network="${PRIVATE_CLOUD_NAME}-network" \
        --description="VMware migration private cloud" || {
        error "Failed to create VMware Engine private cloud"
        exit 1
    }
    
    # Wait for private cloud to be ready
    info "Waiting for VMware Engine private cloud to be ready..."
    while true; do
        STATE=$(gcloud vmware private-clouds describe "${PRIVATE_CLOUD_NAME}" \
            --location="${VMWARE_ENGINE_REGION}" \
            --format="value(state)" 2>/dev/null || echo "")
        
        if [ "$STATE" = "ACTIVE" ]; then
            log "VMware Engine private cloud is now active"
            break
        elif [ "$STATE" = "FAILED" ]; then
            error "VMware Engine private cloud creation failed"
            exit 1
        else
            info "Current state: ${STATE}. Waiting 60 seconds..."
            sleep 60
        fi
    done
    
    # Get and display vCenter IP
    VCENTER_IP=$(gcloud vmware private-clouds describe "${PRIVATE_CLOUD_NAME}" \
        --location="${VMWARE_ENGINE_REGION}" \
        --format="value(vcenter.internalIp)")
    
    log "VMware Engine private cloud created successfully"
    info "vCenter Server IP: ${VCENTER_IP}"
    info "vCenter URL: https://${VCENTER_IP}"
}

# Create Artifact Registry repository
create_artifact_registry() {
    log "Creating Artifact Registry repository..."
    
    info "Creating repository: ${REPOSITORY_NAME}"
    gcloud artifacts repositories create "${REPOSITORY_NAME}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="Repository for modernized application containers" || {
        error "Failed to create Artifact Registry repository"
        exit 1
    }
    
    # Configure Docker authentication
    info "Configuring Docker authentication for Artifact Registry"
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" || {
        error "Failed to configure Docker authentication"
        exit 1
    }
    
    log "Artifact Registry repository created successfully"
}

# Create GKE cluster
create_gke_cluster() {
    log "Creating Google Kubernetes Engine cluster..."
    
    info "Creating GKE cluster: ${GKE_CLUSTER_NAME}"
    gcloud container clusters create "${GKE_CLUSTER_NAME}" \
        --region="${REGION}" \
        --num-nodes=2 \
        --enable-autoscaling \
        --min-nodes=1 \
        --max-nodes=10 \
        --enable-autorepair \
        --enable-autoupgrade \
        --network="${NETWORK_NAME}" \
        --subnetwork=vmware-mgmt-subnet \
        --enable-ip-alias \
        --enable-network-policy \
        --enable-shielded-nodes \
        --disk-size=50GB \
        --disk-type=pd-ssd \
        --machine-type=e2-standard-2 || {
        error "Failed to create GKE cluster"
        exit 1
    }
    
    # Get cluster credentials
    info "Getting GKE cluster credentials"
    gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
        --region="${REGION}" || {
        error "Failed to get GKE cluster credentials"
        exit 1
    }
    
    # Create namespace for modernized applications
    info "Creating namespace for modernized applications"
    kubectl create namespace modernized-apps || {
        warn "Namespace might already exist"
    }
    
    log "GKE cluster created successfully"
}

# Set up monitoring and alerting
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    # Create monitoring dashboard
    info "Creating monitoring dashboard"
    local dashboard_config=$(cat <<EOF
{
  "displayName": "VMware Migration and Modernization Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "VMware Engine Resource Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"vmware_vcenter\"",
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
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "GKE Container Performance",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"k8s_container\"",
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
)
    
    echo "$dashboard_config" > /tmp/dashboard.json
    gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json || {
        warn "Failed to create monitoring dashboard"
    }
    rm -f /tmp/dashboard.json
    
    # Create alerting policies
    info "Creating alerting policies"
    local alert_policy=$(cat <<EOF
{
  "displayName": "Hybrid Infrastructure Alerts",
  "conditions": [
    {
      "displayName": "High VMware CPU Usage",
      "conditionThreshold": {
        "filter": "resource.type=\"vmware_vcenter\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.8,
        "duration": "300s"
      }
    },
    {
      "displayName": "GKE Pod Failures",
      "conditionThreshold": {
        "filter": "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/restart_count\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5,
        "duration": "300s"
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
)
    
    echo "$alert_policy" > /tmp/alert_policy.json
    gcloud alpha monitoring policies create --policy-from-file=/tmp/alert_policy.json || {
        warn "Failed to create alerting policies"
    }
    rm -f /tmp/alert_policy.json
    
    log "Monitoring and alerting configured successfully"
}

# Create workspace for migration analysis
create_migration_workspace() {
    log "Creating migration analysis workspace..."
    
    # Create workspace directory
    WORKSPACE_DIR="${HOME}/vmware-migration-workspace"
    mkdir -p "${WORKSPACE_DIR}"
    cd "${WORKSPACE_DIR}"
    
    # Download and install Migrate to Containers CLI (simulation)
    info "Setting up Migrate to Containers CLI"
    cat > install_m2c.sh << 'EOF'
#!/bin/bash
# This script simulates the installation of Migrate to Containers CLI
# In a real deployment, you would download the actual CLI from Google Cloud
echo "Migrate to Containers CLI installation simulated"
echo "In production, download from: https://cloud.google.com/migrate/containers/docs/getting-started"
EOF
    chmod +x install_m2c.sh
    
    # Create assessment configuration
    info "Creating assessment configuration"
    cat > assessment-config.yaml << EOF
apiVersion: v1
kind: Config
metadata:
  name: vmware-assessment
spec:
  source:
    type: vmware
    connection:
      host: "$(gcloud vmware private-clouds describe "${PRIVATE_CLOUD_NAME}" \
        --location="${VMWARE_ENGINE_REGION}" \
        --format="value(vcenter.internalIp)" 2>/dev/null || echo "PENDING")"
      username: "cloudowner@gve.local"
  target:
    registry: "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}"
    cluster: "${GKE_CLUSTER_NAME}"
EOF
    
    # Create migration inventory
    info "Creating migration inventory template"
    cat > migration-inventory.yaml << EOF
migrations:
  - name: "web-tier-migration"
    type: "bulk"
    source: "on-premises-datacenter"
    target: "${PRIVATE_CLOUD_NAME}"
    workloads:
      - vm1-web-server
      - vm2-web-server
      - vm3-load-balancer
  - name: "database-tier-migration"
    type: "vmotion"
    source: "on-premises-datacenter"
    target: "${PRIVATE_CLOUD_NAME}"
    workloads:
      - vm4-primary-db
      - vm5-secondary-db
EOF
    
    # Create containerization candidates analysis
    info "Creating containerization analysis template"
    cat > containerization-candidates.yaml << EOF
workloads:
  - vm_name: "web-app-vm"
    application: "java-spring-boot"
    containerization_score: 85
    complexity: "low"
    dependencies: ["mysql", "redis"]
  - vm_name: "api-service-vm"
    application: "nodejs-express"
    containerization_score: 92
    complexity: "low"
    dependencies: ["postgresql"]
  - vm_name: "batch-processor-vm"
    application: "python-django"
    containerization_score: 78
    complexity: "medium"
    dependencies: ["rabbitmq", "elasticsearch"]
EOF
    
    log "Migration analysis workspace created at: ${WORKSPACE_DIR}"
}

# Deploy sample modernized application
deploy_sample_app() {
    log "Deploying sample modernized application..."
    
    # Create sample application deployment
    info "Creating sample application deployment"
    cat > sample-app-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: modernized-web-app
  namespace: modernized-apps
spec:
  replicas: 3
  selector:
    matchLabels:
      app: modernized-web-app
  template:
    metadata:
      labels:
        app: modernized-web-app
    spec:
      containers:
      - name: web-app
        image: gcr.io/google-samples/hello-app:1.0
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: modernized-web-app-service
  namespace: modernized-apps
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: modernized-web-app
EOF
    
    # Apply the deployment
    kubectl apply -f sample-app-deployment.yaml || {
        error "Failed to deploy sample application"
        exit 1
    }
    
    # Configure horizontal pod autoscaling
    info "Configuring horizontal pod autoscaling"
    kubectl autoscale deployment modernized-web-app \
        --namespace=modernized-apps \
        --cpu-percent=70 \
        --min=2 \
        --max=10 || {
        warn "Failed to configure autoscaling"
    }
    
    log "Sample modernized application deployed successfully"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    local info_file="${HOME}/vmware-migration-deployment-info.txt"
    
    cat > "$info_file" << EOF
VMware Migration and Modernization Deployment Information
Generated: $(date)

Project Details:
- Project ID: ${PROJECT_ID}
- Region: ${REGION}
- Zone: ${ZONE}

VMware Engine:
- Private Cloud Name: ${PRIVATE_CLOUD_NAME}
- Location: ${VMWARE_ENGINE_REGION}
- vCenter IP: $(gcloud vmware private-clouds describe "${PRIVATE_CLOUD_NAME}" \
    --location="${VMWARE_ENGINE_REGION}" \
    --format="value(vcenter.internalIp)" 2>/dev/null || echo "PENDING")

Networking:
- VPC Network: ${NETWORK_NAME}
- Management Subnet: vmware-mgmt-subnet (10.10.0.0/24)

GKE Cluster:
- Cluster Name: ${GKE_CLUSTER_NAME}
- Region: ${REGION}
- Namespace: modernized-apps

Artifact Registry:
- Repository: ${REPOSITORY_NAME}
- Location: ${REGION}

Migration Workspace:
- Directory: ${HOME}/vmware-migration-workspace

Next Steps:
1. Access vCenter Server at the provided IP address
2. Configure HCX for on-premises connectivity
3. Review migration inventory and containerization candidates
4. Execute workload migrations using HCX
5. Use Migrate to Containers for selected workloads
6. Monitor progress through Cloud Console

Cleanup:
- Run ./destroy.sh to remove all resources
- This will incur charges until cleaned up
EOF
    
    log "Deployment information saved to: $info_file"
}

# Main deployment function
main() {
    log "Starting VMware Migration and Modernization deployment..."
    
    # Run deployment steps
    check_prerequisites
    check_authentication
    setup_environment
    enable_apis
    create_network
    create_vmware_engine
    create_artifact_registry
    create_gke_cluster
    setup_monitoring
    create_migration_workspace
    deploy_sample_app
    save_deployment_info
    
    log "Deployment completed successfully!"
    info ""
    info "Important Notes:"
    info "- VMware Engine private cloud incurs significant costs (~$2000-5000/month)"
    info "- Review the deployment information file for access details"
    info "- Configure HCX for on-premises connectivity"
    info "- Use the migration workspace for workload analysis"
    info "- Run ./destroy.sh when finished to avoid ongoing charges"
    info ""
    log "Deployment information saved to: ${HOME}/vmware-migration-deployment-info.txt"
}

# Run main function
main "$@"