#!/bin/bash

# Secure Traffic Processing with Service Extensions and Confidential Computing - Deployment Script
# This script deploys a secure traffic processing pipeline using GCP Service Extensions
# and Confidential Computing with Cloud KMS encryption

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install openssl"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to prompt for confirmation
confirm_deployment() {
    echo ""
    warn "This script will create GCP resources that may incur charges."
    warn "Estimated cost: \$15-25 for Confidential VM instances, load balancer, and KMS operations"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled by user"
        exit 0
    fi
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Check if PROJECT_ID is already set, otherwise prompt user
    if [[ -z "${PROJECT_ID:-}" ]]; then
        echo "Please enter your GCP Project ID:"
        read -r PROJECT_ID
        export PROJECT_ID
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set resource names
    export KEYRING_NAME="traffic-keyring-${RANDOM_SUFFIX}"
    export KEY_NAME="traffic-encryption-key"
    export VM_NAME="confidential-processor-${RANDOM_SUFFIX}"
    export SERVICE_NAME="traffic-service-${RANDOM_SUFFIX}"
    export BUCKET_NAME="secure-traffic-data-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="confidential-processor"
    export INSTANCE_GROUP_NAME="traffic-processors"
    export HEALTH_CHECK_NAME="traffic-processor-health"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || {
        error "Failed to set project ${PROJECT_ID}. Please check if project exists and you have access."
        exit 1
    }
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log "Environment configured successfully"
    info "Project ID: ${PROJECT_ID}"
    info "Region: ${REGION}"
    info "Zone: ${ZONE}"
    info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required GCP APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "cloudkms.googleapis.com"
        "networkservices.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log "Successfully enabled ${api}"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    log "All required APIs enabled successfully"
}

# Function to create KMS resources
create_kms_resources() {
    log "Creating Cloud KMS resources..."
    
    # Create KMS key ring
    info "Creating KMS key ring: ${KEYRING_NAME}"
    if gcloud kms keyrings create "${KEYRING_NAME}" \
        --location="${REGION}" \
        --quiet; then
        log "KMS key ring created successfully"
    else
        error "Failed to create KMS key ring"
        exit 1
    fi
    
    # Create encryption key
    info "Creating encryption key: ${KEY_NAME}"
    if gcloud kms keys create "${KEY_NAME}" \
        --keyring="${KEYRING_NAME}" \
        --location="${REGION}" \
        --purpose=encryption \
        --quiet; then
        log "Encryption key created successfully"
    else
        error "Failed to create encryption key"
        exit 1
    fi
    
    # Create service account for Confidential VM
    info "Creating service account: ${SERVICE_ACCOUNT_NAME}"
    if gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="Confidential Traffic Processor" \
        --quiet; then
        log "Service account created successfully"
    else
        # Check if service account already exists
        if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
            warn "Service account already exists, continuing..."
        else
            error "Failed to create service account"
            exit 1
        fi
    fi
    
    # Grant KMS access to service account
    info "Granting KMS access to service account..."
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
        --quiet; then
        log "KMS permissions granted successfully"
    else
        error "Failed to grant KMS permissions"
        exit 1
    fi
    
    log "KMS resources created successfully"
}

# Function to create Confidential VM
create_confidential_vm() {
    log "Creating Confidential VM..."
    
    info "Creating Confidential VM: ${VM_NAME}"
    if gcloud compute instances create "${VM_NAME}" \
        --zone="${ZONE}" \
        --machine-type=n2d-standard-4 \
        --confidential-compute \
        --confidential-compute-type=SEV_SNP \
        --maintenance-policy=TERMINATE \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --scopes=cloud-platform \
        --image-family=ubuntu-2204-lts \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size=50GB \
        --boot-disk-type=pd-ssd \
        --tags=traffic-processor \
        --quiet; then
        log "Confidential VM created successfully"
    else
        error "Failed to create Confidential VM"
        exit 1
    fi
    
    # Wait for VM to be ready
    info "Waiting for VM to be ready..."
    sleep 30
    
    local retry_count=0
    local max_retries=10
    
    while [[ $retry_count -lt $max_retries ]]; do
        if gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="echo 'VM is ready'" --quiet &> /dev/null; then
            log "VM is ready and accessible"
            break
        else
            warn "VM not ready yet, waiting... (attempt $((retry_count + 1))/${max_retries})"
            sleep 30
            ((retry_count++))
        fi
    done
    
    if [[ $retry_count -eq $max_retries ]]; then
        error "VM failed to become ready within expected time"
        exit 1
    fi
}

# Function to install traffic processing engine
install_traffic_engine() {
    log "Installing traffic processing engine..."
    
    # Create the traffic processor script on the VM
    info "Installing dependencies and traffic processor on VM..."
    
    local install_script='
set -e
sudo apt-get update -y
sudo apt-get install -y python3-pip python3-venv build-essential

# Create virtual environment
python3 -m venv ~/traffic_env
source ~/traffic_env/bin/activate

# Install Python dependencies
pip install google-cloud-kms google-cloud-storage grpcio grpcio-tools

# Create traffic processing application
cat > ~/traffic_processor.py << '\''EOF'\''
import grpc
import logging
import signal
import sys
from concurrent import futures
import json
import base64
import time
import os
from google.cloud import kms
from google.cloud import storage

class ProcessingRequest:
    def __init__(self):
        self.request_headers = None
        self.request_body = None
        
class ProcessingResponse:
    def __init__(self):
        self.request_headers = None
        
class TrafficProcessor:
    def __init__(self):
        self.kms_client = kms.KeyManagementServiceClient()
        self.storage_client = storage.Client()
        project_id = os.environ.get("PROJECT_ID", "")
        region = os.environ.get("REGION", "us-central1")
        keyring_name = os.environ.get("KEYRING_NAME", "")
        key_name = os.environ.get("KEY_NAME", "traffic-encryption-key")
        self.key_name = f"projects/{project_id}/locations/{region}/keyRings/{keyring_name}/cryptoKeys/{key_name}"
        logging.info(f"Initialized with key: {self.key_name}")
    
    def Process(self, request_iterator, context):
        """Main processing method for Envoy external processor."""
        for request in request_iterator:
            try:
                # Process request headers with encryption
                if hasattr(request, "request_headers") and request.request_headers:
                    response = self.process_headers(request.request_headers)
                    yield response
                elif hasattr(request, "request_body") and request.request_body:
                    # Process and encrypt sensitive request body
                    response = self.process_body(request.request_body)
                    yield response
                else:
                    # Return empty response for unhandled cases
                    yield ProcessingResponse()
            except Exception as e:
                logging.error(f"Error processing request: {e}")
                yield ProcessingResponse()
    
    def process_headers(self, headers):
        """Process and encrypt sensitive headers."""
        sensitive_data = {}
        header_count = 0
        
        # Simulate header processing for demonstration
        if headers:
            header_count = 1  # Simplified for demo
            test_data = "authorization-header-value"
            encrypted_value = self.encrypt_data(test_data)
            sensitive_data["authorization"] = encrypted_value
        
        logging.info(f"Processed headers with encryption: {len(sensitive_data)} sensitive items")
        
        # Return modified headers response
        return ProcessingResponse()
    
    def process_body(self, body):
        """Process request body if needed."""
        logging.info("Processing request body")
        return ProcessingResponse()
    
    def encrypt_data(self, data):
        """Encrypt data using Cloud KMS."""
        try:
            encrypt_response = self.kms_client.encrypt(
                request={
                    "name": self.key_name,
                    "plaintext": data.encode("utf-8")
                }
            )
            encoded_ciphertext = base64.b64encode(encrypt_response.ciphertext).decode("utf-8")
            logging.info("Successfully encrypted data using KMS")
            return encoded_ciphertext
        except Exception as e:
            logging.error(f"Encryption failed: {e}")
            return "[ENCRYPTED]"

def serve():
    """Start the gRPC server."""
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    
    # Add traffic processor service
    # Note: In production, use proper protobuf definitions
    
    listen_addr = "[::]:8080"
    server.add_insecure_port(listen_addr)
    server.start()
    
    logging.info(f"Traffic processor started on {listen_addr}")
    logging.info("Server running with Confidential Computing protection")
    
    def signal_handler(sig, frame):
        logging.info("Shutting down server...")
        server.stop(0)
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        logging.info("Server stopped by user")

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )
    serve()
EOF

# Create systemd service
sudo tee /etc/systemd/system/traffic-processor.service > /dev/null << EOF
[Unit]
Description=Traffic Processor Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER
Environment=PATH=/home/$USER/traffic_env/bin
Environment=PROJECT_ID='"${PROJECT_ID}"'
Environment=REGION='"${REGION}"'
Environment=KEYRING_NAME='"${KEYRING_NAME}"'
Environment=KEY_NAME='"${KEY_NAME}"'
ExecStart=/home/$USER/traffic_env/bin/python /home/$USER/traffic_processor.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable traffic-processor
sudo systemctl start traffic-processor

echo "Traffic processor service installed and started"
'
    
    if gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="${install_script}" --quiet; then
        log "Traffic processing engine installed successfully"
    else
        error "Failed to install traffic processing engine"
        exit 1
    fi
    
    # Verify service is running
    info "Verifying traffic processor service..."
    if gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="sudo systemctl is-active traffic-processor" --quiet; then
        log "Traffic processor service is running"
    else
        error "Traffic processor service failed to start"
        exit 1
    fi
}

# Function to create backend service
create_backend_service() {
    log "Creating backend service infrastructure..."
    
    # Create instance group
    info "Creating instance group: ${INSTANCE_GROUP_NAME}"
    if gcloud compute instance-groups unmanaged create "${INSTANCE_GROUP_NAME}" \
        --zone="${ZONE}" \
        --quiet; then
        log "Instance group created successfully"
    else
        error "Failed to create instance group"
        exit 1
    fi
    
    # Add instance to group
    info "Adding VM to instance group..."
    if gcloud compute instance-groups unmanaged add-instances "${INSTANCE_GROUP_NAME}" \
        --zone="${ZONE}" \
        --instances="${VM_NAME}" \
        --quiet; then
        log "VM added to instance group successfully"
    else
        error "Failed to add VM to instance group"
        exit 1
    fi
    
    # Create health check
    info "Creating health check: ${HEALTH_CHECK_NAME}"
    if gcloud compute health-checks create grpc "${HEALTH_CHECK_NAME}" \
        --port=8080 \
        --global \
        --quiet; then
        log "Health check created successfully"
    else
        error "Failed to create health check"
        exit 1
    fi
    
    # Create backend service
    info "Creating backend service: ${SERVICE_NAME}"
    if gcloud compute backend-services create "${SERVICE_NAME}" \
        --load-balancing-scheme=EXTERNAL_MANAGED \
        --protocol=GRPC \
        --health-checks="${HEALTH_CHECK_NAME}" \
        --global \
        --quiet; then
        log "Backend service created successfully"
    else
        error "Failed to create backend service"
        exit 1
    fi
    
    # Add instance group as backend
    info "Adding instance group as backend..."
    if gcloud compute backend-services add-backend "${SERVICE_NAME}" \
        --instance-group="${INSTANCE_GROUP_NAME}" \
        --instance-group-zone="${ZONE}" \
        --global \
        --quiet; then
        log "Instance group added as backend successfully"
    else
        error "Failed to add instance group as backend"
        exit 1
    fi
}

# Function to create load balancer
create_load_balancer() {
    log "Creating Application Load Balancer..."
    
    # Create URL map
    info "Creating URL map: secure-traffic-map"
    if gcloud compute url-maps create secure-traffic-map \
        --default-service="${SERVICE_NAME}" \
        --global \
        --quiet; then
        log "URL map created successfully"
    else
        error "Failed to create URL map"
        exit 1
    fi
    
    # Create SSL certificate
    info "Creating SSL certificate: secure-traffic-cert"
    if gcloud compute ssl-certificates create secure-traffic-cert \
        --domains=secure-traffic.example.com \
        --global \
        --quiet; then
        log "SSL certificate created successfully"
    else
        error "Failed to create SSL certificate"
        exit 1
    fi
    
    # Create HTTPS proxy
    info "Creating HTTPS proxy: secure-traffic-proxy"
    if gcloud compute target-https-proxies create secure-traffic-proxy \
        --url-map=secure-traffic-map \
        --ssl-certificates=secure-traffic-cert \
        --global \
        --quiet; then
        log "HTTPS proxy created successfully"
    else
        error "Failed to create HTTPS proxy"
        exit 1
    fi
    
    # Create forwarding rule
    info "Creating forwarding rule: secure-traffic-forwarding"
    if gcloud compute forwarding-rules create secure-traffic-forwarding \
        --target-https-proxy=secure-traffic-proxy \
        --ports=443 \
        --global \
        --quiet; then
        log "Forwarding rule created successfully"
    else
        error "Failed to create forwarding rule"
        exit 1
    fi
}

# Function to create secure storage
create_secure_storage() {
    log "Creating secure storage bucket..."
    
    # Create storage bucket
    info "Creating storage bucket: ${BUCKET_NAME}"
    if gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"; then
        log "Storage bucket created successfully"
    else
        error "Failed to create storage bucket"
        exit 1
    fi
    
    # Configure bucket with customer-managed encryption
    info "Configuring bucket with CMEK encryption..."
    if gsutil kms encryption \
        -k "projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}" \
        "gs://${BUCKET_NAME}"; then
        log "CMEK encryption configured successfully"
    else
        error "Failed to configure CMEK encryption"
        exit 1
    fi
    
    # Set bucket lifecycle
    info "Setting bucket lifecycle policy..."
    cat > lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF
    
    if gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}"; then
        log "Lifecycle policy set successfully"
        rm -f lifecycle.json
    else
        error "Failed to set lifecycle policy"
        exit 1
    fi
}

# Function to configure network security
configure_network_security() {
    log "Configuring network security..."
    
    # Create firewall rule
    info "Creating firewall rule: allow-traffic-processor"
    if gcloud compute firewall-rules create allow-traffic-processor \
        --allow=tcp:8080 \
        --source-ranges=10.0.0.0/8 \
        --target-tags=traffic-processor \
        --description="Allow traffic processor communication" \
        --quiet; then
        log "Firewall rule created successfully"
    else
        # Check if rule already exists
        if gcloud compute firewall-rules describe allow-traffic-processor &> /dev/null; then
            warn "Firewall rule already exists, continuing..."
        else
            error "Failed to create firewall rule"
            exit 1
        fi
    fi
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check Confidential VM status
    info "Checking Confidential VM status..."
    local vm_status
    vm_status=$(gcloud compute instances describe "${VM_NAME}" \
        --zone="${ZONE}" \
        --format="value(status)" 2>/dev/null || echo "ERROR")
    
    if [[ "${vm_status}" == "RUNNING" ]]; then
        log "Confidential VM is running"
    else
        error "Confidential VM is not running (status: ${vm_status})"
        exit 1
    fi
    
    # Check traffic processor service
    info "Checking traffic processor service..."
    if gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --command="sudo systemctl is-active traffic-processor" --quiet; then
        log "Traffic processor service is active"
    else
        error "Traffic processor service is not active"
        exit 1
    fi
    
    # Get load balancer IP
    info "Getting load balancer IP address..."
    local lb_ip
    lb_ip=$(gcloud compute forwarding-rules describe secure-traffic-forwarding \
        --global --format="value(IPAddress)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${lb_ip}" != "NOT_FOUND" ]]; then
        log "Load balancer IP: ${lb_ip}"
    else
        warn "Could not retrieve load balancer IP"
    fi
    
    # Test KMS encryption
    info "Testing KMS encryption functionality..."
    if echo "test-data" | gcloud kms encrypt \
        --key="${KEY_NAME}" \
        --keyring="${KEYRING_NAME}" \
        --location="${REGION}" \
        --plaintext-file=- \
        --ciphertext-file=test.encrypted \
        --quiet; then
        
        if gcloud kms decrypt \
            --key="${KEY_NAME}" \
            --keyring="${KEYRING_NAME}" \
            --location="${REGION}" \
            --ciphertext-file=test.encrypted \
            --plaintext-file=- \
            --quiet | grep -q "test-data"; then
            log "KMS encryption/decryption working correctly"
            rm -f test.encrypted
        else
            error "KMS decryption failed"
            exit 1
        fi
    else
        error "KMS encryption failed"
        exit 1
    fi
}

# Function to display deployment summary
display_summary() {
    echo ""
    log "🎉 Deployment completed successfully!"
    echo ""
    info "Resources created:"
    info "  - Project ID: ${PROJECT_ID}"
    info "  - Confidential VM: ${VM_NAME}"
    info "  - KMS Key Ring: ${KEYRING_NAME}"
    info "  - KMS Key: ${KEY_NAME}"
    info "  - Storage Bucket: ${BUCKET_NAME}"
    info "  - Backend Service: ${SERVICE_NAME}"
    echo ""
    
    # Get load balancer IP
    local lb_ip
    lb_ip=$(gcloud compute forwarding-rules describe secure-traffic-forwarding \
        --global --format="value(IPAddress)" 2>/dev/null || echo "NOT_AVAILABLE")
    
    if [[ "${lb_ip}" != "NOT_AVAILABLE" ]]; then
        info "Load Balancer IP: ${lb_ip}"
        info "Test URL: https://${lb_ip} (use Host: secure-traffic.example.com)"
    fi
    
    echo ""
    warn "Note: The complete Service Extensions integration requires additional configuration"
    warn "      beyond the scope of this basic deployment."
    echo ""
    info "To clean up resources, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    echo ""
    log "Starting Secure Traffic Processing deployment..."
    echo ""
    
    # Pre-deployment checks and setup
    check_prerequisites
    confirm_deployment
    setup_environment
    
    # Core deployment steps
    enable_apis
    create_kms_resources
    create_confidential_vm
    install_traffic_engine
    create_backend_service
    create_load_balancer
    create_secure_storage
    configure_network_security
    
    # Post-deployment verification
    verify_deployment
    display_summary
    
    log "Deployment process completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"