#!/bin/bash

# Secure API Gateway Architecture with Cloud Endpoints and Cloud Armor - Deployment Script
# This script deploys a production-ready API gateway using Cloud Endpoints, Cloud Armor, and Cloud Load Balancing

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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
    log_error "Deployment failed at line $1. Exit code: $2"
    log_error "Check the logs above for details."
    exit 1
}

# Set trap for error handling
trap 'handle_error ${LINENO} $?' ERR

# Banner
echo "=================================================="
echo "Secure API Gateway Architecture Deployment"
echo "Cloud Endpoints + Cloud Armor + Load Balancing"
echo "=================================================="
echo

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random values"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core project settings
    export PROJECT_ID="${PROJECT_ID:-secure-api-gateway-$(date +%s | tail -c 6)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export API_NAME="secure-api-${RANDOM_SUFFIX}"
    export BACKEND_SERVICE_NAME="api-backend-${RANDOM_SUFFIX}"
    export SECURITY_POLICY_NAME="api-security-policy-${RANDOM_SUFFIX}"
    
    # Store configuration for cleanup
    cat > deployment-config.env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
API_NAME=${API_NAME}
BACKEND_SERVICE_NAME=${BACKEND_SERVICE_NAME}
SECURITY_POLICY_NAME=${SECURITY_POLICY_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment configured - Project: ${PROJECT_ID}"
    log_info "Configuration saved to deployment-config.env"
}

# Create and configure project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Project ${PROJECT_ID} already exists. Skipping creation."
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Secure API Gateway Demo"
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "servicemanagement.googleapis.com"
        "servicecontrol.googleapis.com"
        "endpoints.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create backend service infrastructure
create_backend_service() {
    log_info "Creating backend service infrastructure..."
    
    # Create startup script for the backend service
    cat > startup-script.sh << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y python3 python3-pip
pip3 install flask

cat > /opt/api-server.py << 'PYTHON_EOF'
from flask import Flask, jsonify, request
import datetime

app = Flask(__name__)

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy", "timestamp": datetime.datetime.now().isoformat()})

@app.route("/api/v1/users", methods=["GET"])
def get_users():
    return jsonify({"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]})

@app.route("/api/v1/data", methods=["POST"])
def create_data():
    data = request.get_json()
    return jsonify({"message": "Data received", "data": data, "id": 12345})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PYTHON_EOF

# Start the API server
nohup python3 /opt/api-server.py > /var/log/api-server.log 2>&1 &
EOF
    
    # Create VM instance for backend service
    log_info "Creating backend service VM..."
    gcloud compute instances create "${BACKEND_SERVICE_NAME}" \
        --zone="${ZONE}" \
        --machine-type=e2-medium \
        --network-tier=PREMIUM \
        --maintenance-policy=MIGRATE \
        --image-family=debian-11 \
        --image-project=debian-cloud \
        --boot-disk-size=20GB \
        --boot-disk-type=pd-standard \
        --tags=backend-service,http-server \
        --metadata-from-file startup-script=startup-script.sh
    
    # Wait for instance to be ready
    log_info "Waiting for backend service to start..."
    sleep 60
    
    # Clean up temporary files
    rm -f startup-script.sh
    
    log_success "Backend service created and starting"
}

# Create OpenAPI specification
create_openapi_spec() {
    log_info "Creating OpenAPI specification..."
    
    # Get backend service internal IP for configuration
    local backend_ip
    backend_ip=$(gcloud compute instances describe "${BACKEND_SERVICE_NAME}" \
        --zone="${ZONE}" \
        --format="value(networkInterfaces[0].networkIP)")
    
    cat > openapi-spec.yaml << EOF
swagger: "2.0"
info:
  title: "Secure API Gateway Demo"
  description: "Production-ready API with Cloud Endpoints and Cloud Armor"
  version: "1.0.0"
host: "${API_NAME}.endpoints.${PROJECT_ID}.cloud.goog"
schemes:
  - "https"
produces:
  - "application/json"
paths:
  "/health":
    get:
      summary: "Health check endpoint"
      operationId: "healthCheck"
      responses:
        200:
          description: "Service is healthy"
  "/api/v1/users":
    get:
      summary: "Get users list"
      operationId: "getUsers"
      security:
        - api_key: []
      responses:
        200:
          description: "Users retrieved successfully"
  "/api/v1/data":
    post:
      summary: "Create new data"
      operationId: "createData"
      security:
        - api_key: []
      parameters:
        - in: "body"
          name: "body"
          required: true
          schema:
            type: "object"
      responses:
        200:
          description: "Data created successfully"
securityDefinitions:
  api_key:
    type: "apiKey"
    name: "key"
    in: "query"
x-google-backend:
  address: "http://${BACKEND_SERVICE_NAME}.${ZONE}.c.${PROJECT_ID}.internal:8080"
  protocol: "http"
EOF
    
    log_success "OpenAPI specification created"
}

# Deploy API configuration to Cloud Endpoints
deploy_endpoints_config() {
    log_info "Deploying API configuration to Cloud Endpoints..."
    
    # Deploy the API configuration
    gcloud endpoints services deploy openapi-spec.yaml
    
    # Get the service configuration ID
    export CONFIG_ID
    CONFIG_ID=$(gcloud endpoints configs list \
        --service="${API_NAME}.endpoints.${PROJECT_ID}.cloud.goog" \
        --format="value(id)" \
        --limit=1)
    
    # Create API key for authentication
    export API_KEY
    API_KEY=$(gcloud services api-keys create \
        --display-name="Secure API Gateway Key" \
        --api-target=service="${API_NAME}.endpoints.${PROJECT_ID}.cloud.goog" \
        --format="value(keyString)")
    
    # Store API key in config file
    echo "CONFIG_ID=${CONFIG_ID}" >> deployment-config.env
    echo "API_KEY=${API_KEY}" >> deployment-config.env
    
    log_success "API configuration deployed with ID: ${CONFIG_ID}"
    log_success "API key created: ${API_KEY}"
}

# Create Cloud Armor security policy
create_security_policy() {
    log_info "Creating Cloud Armor security policy..."
    
    # Create security policy
    gcloud compute security-policies create "${SECURITY_POLICY_NAME}" \
        --description="Security policy for API gateway with rate limiting and threat protection"
    
    # Add rate limiting rule (100 requests per minute per IP)
    log_info "Adding rate limiting rule..."
    gcloud compute security-policies rules create 1000 \
        --security-policy="${SECURITY_POLICY_NAME}" \
        --src-ip-ranges="*" \
        --action=rate-based-ban \
        --rate-limit-threshold-count=100 \
        --rate-limit-threshold-interval-sec=60 \
        --ban-duration-sec=300 \
        --conform-action=allow \
        --exceed-action=deny-429 \
        --enforce-on-key=IP
    
    # Add OWASP protection rule
    log_info "Adding XSS protection rule..."
    gcloud compute security-policies rules create 2000 \
        --security-policy="${SECURITY_POLICY_NAME}" \
        --expression="evaluatePreconfiguredExpr('xss-canary')" \
        --action=deny-403
    
    # Add SQL injection protection
    log_info "Adding SQL injection protection rule..."
    gcloud compute security-policies rules create 3000 \
        --security-policy="${SECURITY_POLICY_NAME}" \
        --expression="evaluatePreconfiguredExpr('sqli-canary')" \
        --action=deny-403
    
    # Add geo-restriction (example: block traffic from specific countries)
    log_info "Adding geo-restriction rule..."
    gcloud compute security-policies rules create 4000 \
        --security-policy="${SECURITY_POLICY_NAME}" \
        --expression="origin.region_code == 'CN' || origin.region_code == 'RU'" \
        --action=deny-403
    
    log_success "Cloud Armor security policy created with comprehensive rules"
}

# Deploy Endpoints Service Proxy (ESP)
deploy_esp_proxy() {
    log_info "Deploying Endpoints Service Proxy (ESP)..."
    
    # Get the backend service internal IP
    local backend_ip
    backend_ip=$(gcloud compute instances describe "${BACKEND_SERVICE_NAME}" \
        --zone="${ZONE}" \
        --format="value(networkInterfaces[0].networkIP)")
    
    # Create ESP container instance
    log_info "Creating ESP proxy container instance..."
    gcloud compute instances create-with-container "esp-proxy-${RANDOM_SUFFIX}" \
        --zone="${ZONE}" \
        --machine-type=e2-medium \
        --network-tier=PREMIUM \
        --tags=esp-proxy,http-server,https-server \
        --container-image=gcr.io/endpoints-release/endpoints-runtime:2 \
        --container-env=ESPv2_ARGS="--service=${API_NAME}.endpoints.${PROJECT_ID}.cloud.goog --rollout_strategy=managed --backend=http://${backend_ip}:8080" \
        --boot-disk-size=20GB \
        --boot-disk-type=pd-standard
    
    # Create firewall rules for ESP proxy
    log_info "Creating firewall rules for ESP proxy..."
    if ! gcloud compute firewall-rules describe allow-esp-proxy &>/dev/null; then
        gcloud compute firewall-rules create allow-esp-proxy \
            --allow=tcp:8080 \
            --source-ranges=0.0.0.0/0 \
            --target-tags=esp-proxy \
            --description="Allow traffic to ESP proxy"
    else
        log_warning "Firewall rule 'allow-esp-proxy' already exists"
    fi
    
    # Wait for ESP proxy to be ready
    log_info "Waiting for ESP proxy to be ready..."
    sleep 45
    
    log_success "ESP proxy deployed and configured"
}

# Create load balancer with Cloud Armor integration
create_load_balancer() {
    log_info "Creating load balancer with Cloud Armor integration..."
    
    # Create instance group for ESP proxy
    log_info "Creating instance group..."
    gcloud compute instance-groups unmanaged create "esp-proxy-group" \
        --zone="${ZONE}" \
        --description="Instance group for ESP proxy instances"
    
    gcloud compute instance-groups unmanaged add-instances "esp-proxy-group" \
        --zone="${ZONE}" \
        --instances="esp-proxy-${RANDOM_SUFFIX}"
    
    # Create health check
    log_info "Creating health check..."
    gcloud compute health-checks create http esp-health-check \
        --port=8080 \
        --request-path=/health \
        --check-interval=30s \
        --timeout=10s \
        --healthy-threshold=2 \
        --unhealthy-threshold=3
    
    # Create backend service
    log_info "Creating backend service with security policy..."
    gcloud compute backend-services create esp-backend-service \
        --protocol=HTTP \
        --health-checks=esp-health-check \
        --global \
        --load-balancing-scheme=EXTERNAL \
        --security-policy="${SECURITY_POLICY_NAME}"
    
    # Add instance group to backend service
    log_info "Adding instance group to backend service..."
    gcloud compute backend-services add-backend esp-backend-service \
        --instance-group=esp-proxy-group \
        --instance-group-zone="${ZONE}" \
        --global
    
    log_success "Backend service created with Cloud Armor integration"
}

# Configure URL maps and frontend services
configure_frontend() {
    log_info "Configuring URL maps and frontend services..."
    
    # Create URL map
    log_info "Creating URL map..."
    gcloud compute url-maps create esp-url-map \
        --default-service=esp-backend-service \
        --global
    
    # Reserve static IP address
    log_info "Reserving static IP address..."
    gcloud compute addresses create esp-gateway-ip \
        --global
    
    export GATEWAY_IP
    GATEWAY_IP=$(gcloud compute addresses describe esp-gateway-ip \
        --global --format="value(address)")
    
    # Create HTTP target proxy
    log_info "Creating HTTP target proxy..."
    gcloud compute target-http-proxies create esp-http-proxy \
        --url-map=esp-url-map \
        --global
    
    # Create forwarding rule
    log_info "Creating forwarding rule..."
    gcloud compute forwarding-rules create esp-forwarding-rule \
        --address=esp-gateway-ip \
        --global \
        --target-http-proxy=esp-http-proxy \
        --ports=80
    
    # Store gateway IP in config file
    echo "GATEWAY_IP=${GATEWAY_IP}" >> deployment-config.env
    
    log_success "Load balancer configured with static IP: ${GATEWAY_IP}"
    log_success "API Gateway accessible at: http://${GATEWAY_IP}"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Wait for load balancer to be fully ready
    log_info "Waiting for load balancer to be fully operational..."
    sleep 120
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    local health_status
    health_status=$(curl -s -w "%{http_code}" -o /dev/null "http://${GATEWAY_IP}/health" || echo "000")
    
    if [[ "${health_status}" == "200" ]]; then
        log_success "Health endpoint is responding correctly"
    else
        log_warning "Health endpoint returned status: ${health_status}"
        log_warning "This may be normal during initial deployment. Load balancer may need more time."
    fi
    
    # Display deployment summary
    echo
    echo "=================================================="
    echo "Deployment Summary"
    echo "=================================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "API Gateway IP: ${GATEWAY_IP}"
    echo "API Endpoint: http://${GATEWAY_IP}"
    echo "API Key: ${API_KEY}"
    echo
    echo "Test Commands:"
    echo "curl \"http://${GATEWAY_IP}/health\""
    echo "curl \"http://${GATEWAY_IP}/api/v1/users?key=${API_KEY}\""
    echo
    echo "Configuration saved to: deployment-config.env"
    echo "=================================================="
}

# Main deployment function
main() {
    log_info "Starting secure API gateway deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_backend_service
    create_openapi_spec
    deploy_endpoints_config
    create_security_policy
    deploy_esp_proxy
    create_load_balancer
    configure_frontend
    validate_deployment
    
    log_success "Deployment completed successfully!"
    log_info "Check the deployment summary above for access details."
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Deployment interrupted. Partial resources may have been created."
    log_info "Run the destroy.sh script to clean up any created resources."
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Execute main function
main "$@"