#!/bin/bash

# deploy.sh - Deploy Zero-Trust Network Security with Service Extensions and Cloud Armor
# This script deploys a comprehensive zero-trust network security architecture using 
# Google Cloud's Service Extensions, Cloud Armor, and Identity-Aware Proxy

set -euo pipefail

# Colors for output
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Starting cleanup of partial resources..."
    if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
        bash "${SCRIPT_DIR}/destroy.sh" --force
    fi
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Zero-Trust Network Security with Service Extensions and Cloud Armor

OPTIONS:
    -p, --project       Google Cloud Project ID (required)
    -r, --region        Deployment region (default: ${DEFAULT_REGION})
    -z, --zone          Deployment zone (default: ${DEFAULT_ZONE})
    -n, --name          Application name prefix (default: auto-generated)
    --dry-run           Show what would be deployed without executing
    --skip-apis         Skip API enablement (assume APIs are already enabled)
    --skip-iam          Skip IAM configuration
    -h, --help          Show this help message

EXAMPLES:
    $0 --project my-gcp-project
    $0 --project my-gcp-project --region us-west1 --zone us-west1-a
    $0 --project my-gcp-project --name my-app --dry-run

PREREQUISITES:
    - Google Cloud CLI (gcloud) installed and authenticated
    - Project billing enabled
    - Required IAM permissions (Security Admin, Network Admin, Service Account Admin)

EOF
}

# Parse command line arguments
parse_args() {
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
            -n|--name)
                APP_NAME_PREFIX="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-apis)
                SKIP_APIS=true
                shift
                ;;
            --skip-iam)
                SKIP_IAM=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Initialize variables
PROJECT_ID=""
REGION="${DEFAULT_REGION}"
ZONE="${DEFAULT_ZONE}"
APP_NAME_PREFIX=""
DRY_RUN=false
SKIP_APIS=false
SKIP_IAM=false

# Parse arguments
parse_args "$@"

# Validate required parameters
if [[ -z "${PROJECT_ID}" ]]; then
    log_error "Project ID is required. Use --project flag or set PROJECT_ID environment variable."
    show_help
    exit 1
fi

# Set derived variables
RANDOM_SUFFIX=$(openssl rand -hex 3)
APP_NAME="${APP_NAME_PREFIX:-zero-trust-app-${RANDOM_SUFFIX}}"
NETWORK_NAME="zero-trust-vpc"
SUBNET_NAME="zero-trust-subnet"
SECURITY_POLICY_NAME="zero-trust-armor-policy"
SERVICE_EXTENSION_NAME="zero-trust-extension"

# Dry run function
execute_command() {
    local cmd="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${cmd}"
        return 0
    else
        log_info "Executing: ${cmd}"
        eval "${cmd}"
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        error_exit "Cannot access project '${PROJECT_ID}'. Check project ID and permissions."
    fi

    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud beta billing projects describe "${PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "${billing_account}" ]]; then
        error_exit "Billing is not enabled for project '${PROJECT_ID}'. Enable billing first."
    fi

    # Check required APIs
    local required_apis=(
        "compute.googleapis.com"
        "iap.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "servicedirectory.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "run.googleapis.com"
    )

    if [[ "${SKIP_APIS}" != "true" ]]; then
        log_info "Checking required APIs..."
        for api in "${required_apis[@]}"; do
            if ! gcloud services list --enabled --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
                log_warning "API ${api} is not enabled. Will enable during deployment."
            fi
        done
    fi

    log_success "Prerequisites check completed"
}

# Enable required APIs
enable_apis() {
    if [[ "${SKIP_APIS}" == "true" ]]; then
        log_info "Skipping API enablement (--skip-apis flag)"
        return 0
    fi

    log_info "Enabling required APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "iap.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "servicedirectory.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "run.googleapis.com"
    )

    for api in "${apis[@]}"; do
        execute_command "gcloud services enable ${api} --project=${PROJECT_ID}"
    done

    # Wait for APIs to be fully enabled
    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi

    log_success "Required APIs enabled"
}

# Set up environment
setup_environment() {
    log_info "Setting up environment variables and gcloud configuration..."

    execute_command "gcloud config set project ${PROJECT_ID}"
    execute_command "gcloud config set compute/region ${REGION}"
    execute_command "gcloud config set compute/zone ${ZONE}"

    log_info "Environment configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  App Name: ${APP_NAME}"
    log_info "  Network: ${NETWORK_NAME}"
    log_info "  Security Policy: ${SECURITY_POLICY_NAME}"

    log_success "Environment configured"
}

# Create VPC network
create_vpc_network() {
    log_info "Creating VPC network with security-first design..."

    # Create custom VPC network
    execute_command "gcloud compute networks create ${NETWORK_NAME} \
        --subnet-mode custom \
        --bgp-routing-mode global \
        --description 'Zero-trust network for secure applications' \
        --project=${PROJECT_ID}"

    # Create subnet with private Google access
    execute_command "gcloud compute networks subnets create ${SUBNET_NAME} \
        --network ${NETWORK_NAME} \
        --range 10.0.0.0/24 \
        --region ${REGION} \
        --enable-private-ip-google-access \
        --description 'Subnet for zero-trust application backends' \
        --project=${PROJECT_ID}"

    # Create firewall rules for IAP access
    execute_command "gcloud compute firewall-rules create ${APP_NAME}-allow-iap \
        --network ${NETWORK_NAME} \
        --allow tcp:80,tcp:443,tcp:22 \
        --source-ranges 35.235.240.0/20 \
        --description 'Allow IAP access to instances' \
        --project=${PROJECT_ID}"

    # Create firewall rule for health checks
    execute_command "gcloud compute firewall-rules create ${APP_NAME}-allow-health-check \
        --network ${NETWORK_NAME} \
        --allow tcp:80 \
        --source-ranges 130.211.0.0/22,35.191.0.0/16 \
        --description 'Allow health check access' \
        --project=${PROJECT_ID}"

    log_success "VPC network created with secure configuration"
}

# Deploy backend application
deploy_backend() {
    log_info "Deploying sample application backend..."

    # Create service account for backend instances
    execute_command "gcloud iam service-accounts create ${APP_NAME}-backend \
        --display-name 'Zero Trust Backend Service Account' \
        --description 'Service account for backend instances' \
        --project=${PROJECT_ID}"

    # Create startup script
    local startup_script="/tmp/${APP_NAME}-startup.sh"
    cat > "${startup_script}" << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y nginx
cat > /var/www/html/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html><head><title>Zero Trust Protected App</title></head>
<body>
<h1>Secure Application</h1>
<p>This application is protected by zero-trust security.</p>
<p>Request processed at: $(date)</p>
<p>Server: $(hostname)</p>
</body></html>
HTML_EOF
systemctl enable nginx
systemctl start nginx
EOF

    # Create backend compute instance
    execute_command "gcloud compute instances create ${APP_NAME}-backend \
        --zone ${ZONE} \
        --machine-type e2-medium \
        --subnet ${SUBNET_NAME} \
        --no-address \
        --service-account ${APP_NAME}-backend@${PROJECT_ID}.iam.gserviceaccount.com \
        --scopes cloud-platform \
        --image-family ubuntu-2004-lts \
        --image-project ubuntu-os-cloud \
        --metadata-from-file startup-script=${startup_script} \
        --tags zero-trust-backend \
        --description 'Backend instance for zero-trust application' \
        --project=${PROJECT_ID}"

    # Wait for instance to be ready
    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info "Waiting for backend instance to be ready..."
        gcloud compute instances wait-until-ready "${APP_NAME}-backend" \
            --zone="${ZONE}" \
            --project="${PROJECT_ID}"
    fi

    log_success "Backend application deployed"
}

# Configure Cloud Armor
configure_cloud_armor() {
    log_info "Configuring Cloud Armor security policy..."

    # Create Cloud Armor security policy
    execute_command "gcloud compute security-policies create ${SECURITY_POLICY_NAME} \
        --description 'Zero-trust security policy with DDoS and WAF protection' \
        --type CLOUD_ARMOR \
        --project=${PROJECT_ID}"

    # Add rate limiting rule
    execute_command "gcloud compute security-policies rules create 1000 \
        --security-policy ${SECURITY_POLICY_NAME} \
        --expression 'true' \
        --action rate-based-ban \
        --rate-limit-threshold-count 100 \
        --rate-limit-threshold-interval-sec 60 \
        --ban-duration-sec 300 \
        --conform-action allow \
        --exceed-action deny-429 \
        --enforce-on-key IP \
        --description 'Rate limiting rule - 100 requests per minute per IP' \
        --project=${PROJECT_ID}"

    # Add geo-blocking rule
    execute_command "gcloud compute security-policies rules create 2000 \
        --security-policy ${SECURITY_POLICY_NAME} \
        --expression \"origin.region_code == 'CN' || origin.region_code == 'RU'\" \
        --action deny-403 \
        --description 'Block traffic from high-risk geographic regions' \
        --project=${PROJECT_ID}"

    # Add OWASP protection rule
    execute_command "gcloud compute security-policies rules create 3000 \
        --security-policy ${SECURITY_POLICY_NAME} \
        --expression \"evaluatePreconfiguredExpr('xss-stable')\" \
        --action deny-403 \
        --description 'Block XSS attacks using OWASP rules' \
        --project=${PROJECT_ID}"

    log_success "Cloud Armor security policy configured"
}

# Deploy Service Extension
deploy_service_extension() {
    log_info "Deploying Service Extension for custom traffic inspection..."

    local temp_dir="/tmp/${APP_NAME}-service-extension"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"

    # Create service extension application
    cat > main.py << 'EOF'
import json
import logging
from flask import Flask, request, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

@app.route('/process', methods=['POST'])
def process_request():
    try:
        # Parse the request from the load balancer
        data = request.get_json()
        headers = data.get('headers', {})
        path = data.get('path', '')
        method = data.get('method', '')
        
        # Custom security logic
        security_score = 100
        risk_factors = []
        
        # Check for suspicious patterns
        if 'admin' in path.lower():
            security_score -= 30
            risk_factors.append('Admin path access')
        
        # Check user agent
        user_agent = headers.get('user-agent', '').lower()
        if 'bot' in user_agent or 'crawler' in user_agent:
            security_score -= 20
            risk_factors.append('Bot user agent')
        
        # Check request method
        if method in ['PUT', 'DELETE', 'PATCH']:
            security_score -= 10
            risk_factors.append('Destructive HTTP method')
        
        # Make security decision
        if security_score < 50:
            logging.warning(f"Blocking request: {risk_factors}")
            return jsonify({
                'action': 'DENY',
                'status_code': 403,
                'body': 'Access denied by security policy'
            })
        
        # Add security headers to response
        response_headers = {
            'X-Security-Score': str(security_score),
            'X-Frame-Options': 'DENY',
            'X-Content-Type-Options': 'nosniff'
        }
        
        logging.info(f"Allowing request with score: {security_score}")
        return jsonify({
            'action': 'ALLOW',
            'headers': response_headers
        })
        
    except Exception as e:
        logging.error(f"Error processing request: {e}")
        return jsonify({'action': 'ALLOW'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    # Create requirements file
    cat > requirements.txt << 'EOF'
Flask==2.3.3
gunicorn==21.2.0
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY main.py .
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app"]
EOF

    # Deploy to Cloud Run
    execute_command "gcloud run deploy ${SERVICE_EXTENSION_NAME} \
        --source . \
        --region ${REGION} \
        --allow-unauthenticated \
        --memory 512Mi \
        --cpu 1 \
        --max-instances 10 \
        --description 'Service extension for zero-trust traffic inspection' \
        --project=${PROJECT_ID}"

    cd - > /dev/null

    log_success "Service Extension deployed"
}

# Configure load balancer
configure_load_balancer() {
    log_info "Configuring global load balancer with IAP..."

    # Create health check
    execute_command "gcloud compute health-checks create http ${APP_NAME}-health-check \
        --port 80 \
        --request-path / \
        --check-interval 30s \
        --timeout 10s \
        --healthy-threshold 2 \
        --unhealthy-threshold 3 \
        --description 'Health check for zero-trust backends' \
        --project=${PROJECT_ID}"

    # Create instance group
    execute_command "gcloud compute instance-groups unmanaged create ${APP_NAME}-ig \
        --zone ${ZONE} \
        --description 'Instance group for zero-trust backend' \
        --project=${PROJECT_ID}"

    # Add instance to group
    execute_command "gcloud compute instance-groups unmanaged add-instances ${APP_NAME}-ig \
        --instances ${APP_NAME}-backend \
        --zone ${ZONE} \
        --project=${PROJECT_ID}"

    # Create backend service with IAP
    execute_command "gcloud compute backend-services create ${APP_NAME}-backend-service \
        --protocol HTTP \
        --port-name http \
        --health-checks ${APP_NAME}-health-check \
        --global \
        --iap \
        --description 'Backend service with IAP protection' \
        --project=${PROJECT_ID}"

    # Add backend to service
    execute_command "gcloud compute backend-services add-backend ${APP_NAME}-backend-service \
        --instance-group ${APP_NAME}-ig \
        --instance-group-zone ${ZONE} \
        --global \
        --project=${PROJECT_ID}"

    # Attach Cloud Armor policy
    execute_command "gcloud compute backend-services update ${APP_NAME}-backend-service \
        --security-policy ${SECURITY_POLICY_NAME} \
        --global \
        --project=${PROJECT_ID}"

    # Create URL map
    execute_command "gcloud compute url-maps create ${APP_NAME}-url-map \
        --default-service ${APP_NAME}-backend-service \
        --description 'URL map for zero-trust application' \
        --project=${PROJECT_ID}"

    # Create SSL certificate
    execute_command "gcloud compute ssl-certificates create ${APP_NAME}-ssl-cert \
        --domains ${APP_NAME}.example.com \
        --global \
        --description 'SSL certificate for zero-trust application' \
        --project=${PROJECT_ID}"

    # Create HTTPS proxy
    execute_command "gcloud compute target-https-proxies create ${APP_NAME}-https-proxy \
        --url-map ${APP_NAME}-url-map \
        --ssl-certificates ${APP_NAME}-ssl-cert \
        --global-ssl-certificates \
        --description 'HTTPS proxy with SSL termination' \
        --project=${PROJECT_ID}"

    # Create global forwarding rule
    execute_command "gcloud compute forwarding-rules create ${APP_NAME}-forwarding-rule \
        --global \
        --target-https-proxy ${APP_NAME}-https-proxy \
        --ports 443 \
        --description 'Global forwarding rule for HTTPS traffic' \
        --project=${PROJECT_ID}"

    log_success "Load balancer configured with IAP protection"
}

# Configure monitoring
configure_monitoring() {
    log_info "Configuring security monitoring and logging..."

    # Create log sink for security events
    execute_command "gcloud logging sinks create zero-trust-security-sink \
        storage.googleapis.com/${PROJECT_ID}-security-logs \
        --log-filter='protoPayload.serviceName=\"iap.googleapis.com\" OR 
                     protoPayload.serviceName=\"compute.googleapis.com\" OR
                     resource.type=\"gce_instance\" OR
                     resource.type=\"http_load_balancer\"' \
        --description 'Security events from zero-trust infrastructure' \
        --project=${PROJECT_ID}" || log_warning "Log sink creation failed - may already exist"

    log_success "Security monitoring configured"
}

# Get deployment information
get_deployment_info() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run completed. No resources were actually created."
        return 0
    fi

    log_info "Retrieving deployment information..."

    # Get load balancer IP
    local lb_ip
    lb_ip=$(gcloud compute forwarding-rules describe "${APP_NAME}-forwarding-rule" \
        --global --format "value(IPAddress)" --project="${PROJECT_ID}" 2>/dev/null || echo "Not available")

    # Get service extension URL
    local extension_url
    extension_url=$(gcloud run services describe "${SERVICE_EXTENSION_NAME}" \
        --region "${REGION}" --format "value(status.url)" --project="${PROJECT_ID}" 2>/dev/null || echo "Not available")

    log_success "Zero-Trust Network Security deployment completed!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "App Name: ${APP_NAME}"
    echo "Load Balancer IP: ${lb_ip}"
    echo "Service Extension URL: ${extension_url}"
    echo "Domain: ${APP_NAME}.example.com"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Configure DNS to point ${APP_NAME}.example.com to ${lb_ip}"
    echo "2. Set up OAuth consent screen for IAP"
    echo "3. Configure IAP access policies"
    echo "4. Test security policies and monitoring"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ${SCRIPT_DIR}/destroy.sh --project ${PROJECT_ID}"
}

# Main execution
main() {
    log_info "Starting Zero-Trust Network Security deployment..."
    log_info "Timestamp: $(date)"

    check_prerequisites
    setup_environment
    enable_apis
    create_vpc_network
    deploy_backend
    configure_cloud_armor
    deploy_service_extension
    configure_load_balancer
    configure_monitoring
    get_deployment_info

    log_success "Deployment completed successfully!"
}

# Execute main function
main "$@"