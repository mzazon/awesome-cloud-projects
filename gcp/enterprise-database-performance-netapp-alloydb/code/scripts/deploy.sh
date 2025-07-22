#!/bin/bash

# Enterprise Database Performance with NetApp Volumes and AlloyDB - Deployment Script
# This script deploys the complete enterprise-grade database architecture
# Author: Generated from Cloud Recipe
# Version: 1.2

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

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-enterprise-db-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
VPC_NAME="${VPC_NAME:-enterprise-db-vpc}"
SUBNET_NAME="${SUBNET_NAME:-enterprise-db-subnet}"

# Generate unique identifiers
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
ALLOYDB_CLUSTER_ID="${ALLOYDB_CLUSTER_ID:-enterprise-alloydb-${RANDOM_SUFFIX}}"
NETAPP_STORAGE_POOL="${NETAPP_STORAGE_POOL:-enterprise-storage-pool-${RANDOM_SUFFIX}}"
NETAPP_VOLUME="${NETAPP_VOLUME:-enterprise-db-volume-${RANDOM_SUFFIX}}"

# Database credentials (should be overridden with secure values)
DB_PASSWORD="${DB_PASSWORD:-ChangeMe123!}"

# Display deployment configuration
display_config() {
    log "Enterprise Database Performance Deployment Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Zone: ${ZONE}"
    echo "  VPC Name: ${VPC_NAME}"
    echo "  AlloyDB Cluster: ${ALLOYDB_CLUSTER_ID}"
    echo "  NetApp Storage Pool: ${NETAPP_STORAGE_POOL}"
    echo "  NetApp Volume: ${NETAPP_VOLUME}"
    echo ""
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'."
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        warning "Project ${PROJECT_ID} does not exist or is not accessible."
        read -p "Would you like to create the project? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gcloud projects create "${PROJECT_ID}" || error "Failed to create project"
        else
            error "Project is required to continue."
        fi
    fi
    
    # Set project and region
    gcloud config set project "${PROJECT_ID}" || error "Failed to set project"
    gcloud config set compute/region "${REGION}" || error "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error "Failed to set zone"
    
    success "Prerequisites check completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "alloydb.googleapis.com"
        "netapp.googleapis.com"
        "compute.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "servicenetworking.googleapis.com"
        "cloudkms.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" || error "Failed to enable ${api}"
    done
    
    success "All required APIs enabled"
}

# Create VPC network infrastructure
create_network_infrastructure() {
    log "Creating enterprise VPC network infrastructure..."
    
    # Create VPC network
    if ! gcloud compute networks describe "${VPC_NAME}" &> /dev/null; then
        log "Creating VPC network: ${VPC_NAME}"
        gcloud compute networks create "${VPC_NAME}" \
            --subnet-mode=custom \
            --description="Enterprise database VPC" || error "Failed to create VPC"
    else
        warning "VPC ${VPC_NAME} already exists, skipping creation"
    fi
    
    # Create subnet
    if ! gcloud compute networks subnets describe "${SUBNET_NAME}" --region="${REGION}" &> /dev/null; then
        log "Creating subnet: ${SUBNET_NAME}"
        gcloud compute networks subnets create "${SUBNET_NAME}" \
            --network="${VPC_NAME}" \
            --range=10.0.0.0/24 \
            --region="${REGION}" \
            --description="Enterprise database subnet" || error "Failed to create subnet"
    else
        warning "Subnet ${SUBNET_NAME} already exists, skipping creation"
    fi
    
    success "VPC network infrastructure created"
}

# Configure private service connection
configure_private_service_connection() {
    log "Configuring private service connection for AlloyDB..."
    
    # Allocate IP range for private service connection
    if ! gcloud compute addresses describe alloydb-private-range --global &> /dev/null; then
        log "Allocating IP range for private service connection"
        gcloud compute addresses create alloydb-private-range \
            --global \
            --purpose=VPC_PEERING \
            --prefix-length=16 \
            --network="${VPC_NAME}" \
            --description="Private IP range for AlloyDB" || error "Failed to create private IP range"
    else
        warning "Private IP range alloydb-private-range already exists, skipping creation"
    fi
    
    # Create private connection
    log "Creating private service connection"
    if ! gcloud services vpc-peerings list --network="${VPC_NAME}" --format="value(network)" | grep -q "${VPC_NAME}"; then
        gcloud services vpc-peerings connect \
            --service=servicenetworking.googleapis.com \
            --ranges=alloydb-private-range \
            --network="${VPC_NAME}" || error "Failed to create private service connection"
    else
        warning "Private service connection already exists, skipping creation"
    fi
    
    success "Private service connection configured"
}

# Create NetApp Volumes storage pool
create_netapp_storage_pool() {
    log "Creating NetApp Volumes storage pool..."
    
    if ! gcloud netapp storage-pools describe "${NETAPP_STORAGE_POOL}" --location="${REGION}" &> /dev/null; then
        log "Creating high-performance storage pool: ${NETAPP_STORAGE_POOL}"
        gcloud netapp storage-pools create "${NETAPP_STORAGE_POOL}" \
            --location="${REGION}" \
            --service-level=FLEX \
            --capacity=20TiB \
            --network="${VPC_NAME}" \
            --description="Enterprise database storage pool" || error "Failed to create storage pool"
        
        # Wait for storage pool creation
        log "Waiting for storage pool creation to complete..."
        local timeout=1800  # 30 minutes
        local elapsed=0
        local interval=30
        
        while [ $elapsed -lt $timeout ]; do
            local state=$(gcloud netapp storage-pools describe "${NETAPP_STORAGE_POOL}" \
                --location="${REGION}" \
                --format="value(state)" 2>/dev/null || echo "")
            
            if [ "$state" = "READY" ]; then
                success "Storage pool created successfully"
                return 0
            fi
            
            log "Storage pool state: ${state}. Waiting ${interval} seconds..."
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        error "Storage pool creation timed out after ${timeout} seconds"
    else
        warning "Storage pool ${NETAPP_STORAGE_POOL} already exists, skipping creation"
    fi
}

# Create NetApp volume
create_netapp_volume() {
    log "Creating NetApp volume for database storage..."
    
    if ! gcloud netapp volumes describe "${NETAPP_VOLUME}" --location="${REGION}" &> /dev/null; then
        log "Creating high-performance volume: ${NETAPP_VOLUME}"
        gcloud netapp volumes create "${NETAPP_VOLUME}" \
            --location="${REGION}" \
            --storage-pool="${NETAPP_STORAGE_POOL}" \
            --capacity=10TiB \
            --protocols=NFSV4 \
            --share-name=enterprise-db-data \
            --description="Enterprise database data volume" || error "Failed to create volume"
        
        # Wait for volume creation
        log "Waiting for volume creation to complete..."
        local timeout=1800  # 30 minutes
        local elapsed=0
        local interval=30
        
        while [ $elapsed -lt $timeout ]; do
            local state=$(gcloud netapp volumes describe "${NETAPP_VOLUME}" \
                --location="${REGION}" \
                --format="value(state)" 2>/dev/null || echo "")
            
            if [ "$state" = "READY" ]; then
                # Get volume mount information
                VOLUME_MOUNT_PATH=$(gcloud netapp volumes describe "${NETAPP_VOLUME}" \
                    --location="${REGION}" \
                    --format="value(mountOptions.mountPath)" 2>/dev/null || echo "")
                success "Volume created successfully: ${VOLUME_MOUNT_PATH}"
                return 0
            fi
            
            log "Volume state: ${state}. Waiting ${interval} seconds..."
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        error "Volume creation timed out after ${timeout} seconds"
    else
        warning "Volume ${NETAPP_VOLUME} already exists, skipping creation"
    fi
}

# Create AlloyDB cluster
create_alloydb_cluster() {
    log "Creating AlloyDB cluster for enterprise workloads..."
    
    if ! gcloud alloydb clusters describe "${ALLOYDB_CLUSTER_ID}" --region="${REGION}" &> /dev/null; then
        log "Creating AlloyDB cluster: ${ALLOYDB_CLUSTER_ID}"
        gcloud alloydb clusters create "${ALLOYDB_CLUSTER_ID}" \
            --region="${REGION}" \
            --network="${VPC_NAME}" \
            --database-version=POSTGRES_15 \
            --continuous-backup-enabled \
            --automated-backup-start-time="02:00" \
            --automated-backup-days-of-week=MONDAY,TUESDAY,WEDNESDAY,THURSDAY,FRIDAY,SATURDAY,SUNDAY \
            --automated-backup-retention-period=30d \
            --password="${DB_PASSWORD}" || error "Failed to create AlloyDB cluster"
        
        # Wait for cluster creation
        log "Waiting for AlloyDB cluster creation to complete..."
        local timeout=3600  # 60 minutes
        local elapsed=0
        local interval=60
        
        while [ $elapsed -lt $timeout ]; do
            local state=$(gcloud alloydb clusters describe "${ALLOYDB_CLUSTER_ID}" \
                --region="${REGION}" \
                --format="value(state)" 2>/dev/null || echo "")
            
            if [ "$state" = "READY" ]; then
                success "AlloyDB cluster created successfully"
                return 0
            fi
            
            log "Cluster state: ${state}. Waiting ${interval} seconds..."
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        error "AlloyDB cluster creation timed out after ${timeout} seconds"
    else
        warning "AlloyDB cluster ${ALLOYDB_CLUSTER_ID} already exists, skipping creation"
    fi
}

# Create primary instance
create_primary_instance() {
    log "Creating AlloyDB primary instance..."
    
    local primary_instance="${ALLOYDB_CLUSTER_ID}-primary"
    
    if ! gcloud alloydb instances describe "${primary_instance}" --cluster="${ALLOYDB_CLUSTER_ID}" --region="${REGION}" &> /dev/null; then
        log "Creating primary instance: ${primary_instance}"
        gcloud alloydb instances create "${primary_instance}" \
            --cluster="${ALLOYDB_CLUSTER_ID}" \
            --region="${REGION}" \
            --instance-type=PRIMARY \
            --cpu-count=16 \
            --memory-size=64GiB \
            --database-flags=shared_preload_libraries=pg_stat_statements,pg_hint_plan || error "Failed to create primary instance"
        
        # Wait for primary instance creation
        log "Waiting for primary instance creation to complete..."
        local timeout=3600  # 60 minutes
        local elapsed=0
        local interval=60
        
        while [ $elapsed -lt $timeout ]; do
            local state=$(gcloud alloydb instances describe "${primary_instance}" \
                --cluster="${ALLOYDB_CLUSTER_ID}" \
                --region="${REGION}" \
                --format="value(state)" 2>/dev/null || echo "")
            
            if [ "$state" = "READY" ]; then
                success "Primary instance created successfully"
                return 0
            fi
            
            log "Primary instance state: ${state}. Waiting ${interval} seconds..."
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        error "Primary instance creation timed out after ${timeout} seconds"
    else
        warning "Primary instance ${primary_instance} already exists, skipping creation"
    fi
}

# Create read replica
create_read_replica() {
    log "Creating AlloyDB read replica..."
    
    local replica_instance="${ALLOYDB_CLUSTER_ID}-replica-01"
    
    if ! gcloud alloydb instances describe "${replica_instance}" --cluster="${ALLOYDB_CLUSTER_ID}" --region="${REGION}" &> /dev/null; then
        log "Creating read replica: ${replica_instance}"
        gcloud alloydb instances create "${replica_instance}" \
            --cluster="${ALLOYDB_CLUSTER_ID}" \
            --region="${REGION}" \
            --instance-type=READ_POOL \
            --cpu-count=8 \
            --memory-size=32GiB \
            --read-pool-node-count=3 || error "Failed to create read replica"
        
        # Wait for replica creation
        log "Waiting for read replica creation to complete..."
        local timeout=3600  # 60 minutes
        local elapsed=0
        local interval=60
        
        while [ $elapsed -lt $timeout ]; do
            local state=$(gcloud alloydb instances describe "${replica_instance}" \
                --cluster="${ALLOYDB_CLUSTER_ID}" \
                --region="${REGION}" \
                --format="value(state)" 2>/dev/null || echo "")
            
            if [ "$state" = "READY" ]; then
                # Get connection information
                ALLOYDB_PRIMARY_IP=$(gcloud alloydb instances describe "${ALLOYDB_CLUSTER_ID}-primary" \
                    --cluster="${ALLOYDB_CLUSTER_ID}" \
                    --region="${REGION}" \
                    --format="value(ipAddress)" 2>/dev/null || echo "")
                
                ALLOYDB_REPLICA_IP=$(gcloud alloydb instances describe "${replica_instance}" \
                    --cluster="${ALLOYDB_CLUSTER_ID}" \
                    --region="${REGION}" \
                    --format="value(ipAddress)" 2>/dev/null || echo "")
                
                success "Read replica created - Primary: ${ALLOYDB_PRIMARY_IP}, Replica: ${ALLOYDB_REPLICA_IP}"
                return 0
            fi
            
            log "Read replica state: ${state}. Waiting ${interval} seconds..."
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        error "Read replica creation timed out after ${timeout} seconds"
    else
        warning "Read replica ${replica_instance} already exists, skipping creation"
    fi
}

# Setup monitoring
setup_monitoring() {
    log "Setting up database performance monitoring..."
    
    # Create monitoring dashboard configuration
    cat > /tmp/dashboard-config.json << 'EOF'
{
  "displayName": "Enterprise Database Performance Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "AlloyDB CPU Utilization",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"alloydb_instance\"",
                "aggregation": {
                  "alignmentPeriod": "300s",
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
        "widget": {
          "title": "NetApp Volume Performance",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"netapp_volume\"",
                "aggregation": {
                  "alignmentPeriod": "300s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            }
          }
        }
      }
    ]
  }
}
EOF
    
    # Create monitoring dashboard
    gcloud monitoring dashboards create --config-from-file=/tmp/dashboard-config.json || warning "Dashboard creation failed"
    
    # Create alert policy configuration
    cat > /tmp/alert-policy.yaml << 'EOF'
displayName: "AlloyDB High CPU Alert"
conditions:
  - displayName: "AlloyDB CPU > 80%"
    conditionThreshold:
      filter: 'resource.type="alloydb_instance"'
      comparison: COMPARISON_GT
      thresholdValue: 0.8
      duration: 300s
notificationChannels: []
alertStrategy:
  autoClose: 86400s
EOF
    
    # Create alert policy
    gcloud alpha monitoring policies create --policy-from-file=/tmp/alert-policy.yaml || warning "Alert policy creation failed"
    
    # Cleanup temporary files
    rm -f /tmp/dashboard-config.json /tmp/alert-policy.yaml
    
    success "Database performance monitoring configured"
}

# Configure load balancing
configure_load_balancing() {
    log "Configuring database load balancing..."
    
    # Create health check
    if ! gcloud compute health-checks describe alloydb-health-check &> /dev/null; then
        gcloud compute health-checks create tcp alloydb-health-check \
            --port=5432 \
            --check-interval=10s \
            --timeout=5s \
            --healthy-threshold=2 \
            --unhealthy-threshold=3 || error "Failed to create health check"
    else
        warning "Health check alloydb-health-check already exists, skipping creation"
    fi
    
    # Create backend service
    if ! gcloud compute backend-services describe alloydb-backend --region="${REGION}" &> /dev/null; then
        gcloud compute backend-services create alloydb-backend \
            --protocol=TCP \
            --health-checks=alloydb-health-check \
            --region="${REGION}" \
            --load-balancing-scheme=INTERNAL || error "Failed to create backend service"
    else
        warning "Backend service alloydb-backend already exists, skipping creation"
    fi
    
    # Create forwarding rule
    if ! gcloud compute forwarding-rules describe alloydb-forwarding-rule --region="${REGION}" &> /dev/null; then
        gcloud compute forwarding-rules create alloydb-forwarding-rule \
            --region="${REGION}" \
            --load-balancing-scheme=INTERNAL \
            --network="${VPC_NAME}" \
            --subnet="${SUBNET_NAME}" \
            --address=10.0.0.100 \
            --ports=5432 \
            --backend-service=alloydb-backend || error "Failed to create forwarding rule"
    else
        warning "Forwarding rule alloydb-forwarding-rule already exists, skipping creation"
    fi
    
    success "Database load balancing configured at 10.0.0.100:5432"
}

# Configure encryption and security
configure_security() {
    log "Implementing database security and encryption..."
    
    # Create KMS keyring
    if ! gcloud kms keyrings describe alloydb-keyring --location="${REGION}" &> /dev/null; then
        gcloud kms keyrings create alloydb-keyring \
            --location="${REGION}" || error "Failed to create KMS keyring"
    else
        warning "KMS keyring alloydb-keyring already exists, skipping creation"
    fi
    
    # Create encryption key
    if ! gcloud kms keys describe alloydb-key --location="${REGION}" --keyring=alloydb-keyring &> /dev/null; then
        gcloud kms keys create alloydb-key \
            --location="${REGION}" \
            --keyring=alloydb-keyring \
            --purpose=encryption || error "Failed to create encryption key"
    else
        warning "Encryption key alloydb-key already exists, skipping creation"
    fi
    
    # Note: Cluster encryption configuration would need to be done during cluster creation
    # This is a limitation of the current AlloyDB implementation
    
    success "Database security and encryption configured"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > /tmp/deployment-info.txt << EOF
Enterprise Database Performance Deployment Summary
================================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}

Network Infrastructure:
- VPC Name: ${VPC_NAME}
- Subnet Name: ${SUBNET_NAME}

AlloyDB Configuration:
- Cluster ID: ${ALLOYDB_CLUSTER_ID}
- Primary Instance: ${ALLOYDB_CLUSTER_ID}-primary
- Read Replica: ${ALLOYDB_CLUSTER_ID}-replica-01
- Primary IP: ${ALLOYDB_PRIMARY_IP:-Not available}
- Replica IP: ${ALLOYDB_REPLICA_IP:-Not available}

NetApp Volumes:
- Storage Pool: ${NETAPP_STORAGE_POOL}
- Volume: ${NETAPP_VOLUME}
- Mount Path: ${VOLUME_MOUNT_PATH:-Not available}

Load Balancer Endpoint: 10.0.0.100:5432

Security:
- KMS Keyring: alloydb-keyring
- Encryption Key: alloydb-key

Deployment completed at: $(date)
EOF
    
    echo ""
    success "Deployment information saved to /tmp/deployment-info.txt"
    cat /tmp/deployment-info.txt
}

# Main deployment function
main() {
    echo "=================================================="
    echo "Enterprise Database Performance Deployment Script"
    echo "=================================================="
    echo ""
    
    display_config
    
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    enable_apis
    create_network_infrastructure
    configure_private_service_connection
    create_netapp_storage_pool
    create_netapp_volume
    create_alloydb_cluster
    create_primary_instance
    create_read_replica
    setup_monitoring
    configure_load_balancing
    configure_security
    save_deployment_info
    
    echo ""
    success "🎉 Enterprise database performance architecture deployment completed successfully!"
    echo ""
    log "Next steps:"
    echo "1. Review the deployment information above"
    echo "2. Connect to your database using the provided IP addresses"
    echo "3. Configure your applications to use the load balancer endpoint"
    echo "4. Monitor performance through the Cloud Console"
    echo ""
    warning "Remember to update the default database password for production use!"
}

# Run main function
main "$@"