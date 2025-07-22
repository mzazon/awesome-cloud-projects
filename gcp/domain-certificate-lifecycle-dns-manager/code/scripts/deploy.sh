#!/bin/bash

# Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager
# Deployment Script for GCP
# 
# This script automates the deployment of:
# - Cloud DNS zone for domain management
# - Certificate Manager for SSL/TLS automation
# - Cloud Functions for certificate monitoring and DNS updates
# - Cloud Scheduler for automated monitoring
# - Application Load Balancer with certificate integration

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if billing is enabled (basic check)
    if ! gcloud alpha billing accounts list --format="value(name)" | head -n1 > /dev/null 2>&1; then
        log_warning "Cannot verify billing account. Ensure billing is enabled for your project."
    fi
    
    log_success "Prerequisites validated successfully"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set project and region defaults
    export PROJECT_ID="${PROJECT_ID:-cert-dns-automation-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 4)")
    export DNS_ZONE_NAME="automation-zone-${RANDOM_SUFFIX}"
    export DOMAIN_NAME="${DOMAIN_NAME:-example-${RANDOM_SUFFIX}.com}"
    export CERT_NAME="ssl-cert-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="cert-automation-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB="cert-check-${RANDOM_SUFFIX}"
    
    log_success "Environment configured:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Domain: ${DOMAIN_NAME}"
    log_info "  DNS Zone: ${DNS_ZONE_NAME}"
}

# Function to create or set project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_info "Using existing project: ${PROJECT_ID}"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Certificate DNS Automation"
        
        # Wait for project to be ready
        sleep 10
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dns.googleapis.com"
        "certificatemanager.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "secretmanager.googleapis.com"
        "monitoring.googleapis.com"
        "compute.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Function to create DNS zone
create_dns_zone() {
    log_info "Creating Cloud DNS zone..."
    
    if gcloud dns managed-zones create "${DNS_ZONE_NAME}" \
        --dns-name="${DOMAIN_NAME}." \
        --description="Automated DNS zone for certificate management" \
        --visibility=public \
        --quiet; then
        
        # Get nameserver information
        gcloud dns managed-zones describe "${DNS_ZONE_NAME}" \
            --format="value(nameServers)" > nameservers.txt
        
        log_success "DNS zone created successfully"
        log_info "Configure these nameservers with your domain registrar:"
        cat nameservers.txt
    else
        log_error "Failed to create DNS zone"
        exit 1
    fi
}

# Function to create service account
create_service_account() {
    log_info "Creating service account for automation..."
    
    local sa_email="cert-automation@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create service account
    if gcloud iam service-accounts create cert-automation \
        --display-name="Certificate Automation Service Account" \
        --description="Service account for DNS and certificate automation" \
        --quiet; then
        
        # Grant necessary permissions
        local roles=(
            "roles/dns.admin"
            "roles/certificatemanager.editor"
            "roles/monitoring.metricWriter"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            log_info "Granting role: ${role}"
            gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${sa_email}" \
                --role="${role}" \
                --quiet
        done
        
        log_success "Service account configured with appropriate permissions"
    else
        log_error "Failed to create service account"
        exit 1
    fi
}

# Function to create certificate
create_certificate() {
    log_info "Creating Google-managed certificate..."
    
    # Create certificate
    if gcloud certificate-manager certificates create "${CERT_NAME}" \
        --domains="${DOMAIN_NAME}" \
        --global \
        --quiet; then
        
        # Create certificate map
        gcloud certificate-manager maps create "cert-map-${RANDOM_SUFFIX}" \
            --global \
            --quiet
        
        # Add certificate to map
        gcloud certificate-manager maps entries create "${DOMAIN_NAME}" \
            --map="cert-map-${RANDOM_SUFFIX}" \
            --certificates="${CERT_NAME}" \
            --hostname="${DOMAIN_NAME}" \
            --global \
            --quiet
        
        log_success "Certificate and certificate map created"
    else
        log_error "Failed to create certificate"
        exit 1
    fi
}

# Function to create Cloud Functions
create_cloud_functions() {
    log_info "Creating Cloud Functions for certificate management..."
    
    # Create function source directory
    local func_dir="cert-automation-function"
    mkdir -p "${func_dir}"
    
    # Create main function file
    cat > "${func_dir}/main.py" << 'EOF'
import json
import logging
import os
from datetime import datetime, timedelta
from google.cloud import certificatemanager_v1
from google.cloud import dns
from google.cloud import monitoring_v3
from google.cloud import secretmanager
import functions_framework

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def check_certificates(request):
    """Monitor certificate status and handle lifecycle events."""
    try:
        project_id = os.environ.get('GCP_PROJECT')
        
        # Initialize clients
        cert_client = certificatemanager_v1.CertificateManagerClient()
        dns_client = dns.Client(project=project_id)
        monitoring_client = monitoring_v3.MetricServiceClient()
        
        # List all certificates
        location = f"projects/{project_id}/locations/global"
        certificates = cert_client.list_certificates(parent=location)
        
        results = []
        for cert in certificates:
            cert_info = {
                'name': cert.name,
                'domains': list(cert.managed.domains),
                'state': cert.managed.state.name,
                'provisioning_issue': cert.managed.provisioning_issue.reason if cert.managed.provisioning_issue else None
            }
            
            # Check certificate expiration
            if cert.managed.state == certificatemanager_v1.Certificate.ManagedCertificate.State.ACTIVE:
                # Certificate is active - log success metric
                write_metric(monitoring_client, project_id, 'certificate_status', 1, cert.name)
                logger.info(f"Certificate {cert.name} is active and healthy")
            else:
                # Certificate has issues - log failure metric
                write_metric(monitoring_client, project_id, 'certificate_status', 0, cert.name)
                logger.warning(f"Certificate {cert.name} state: {cert.managed.state.name}")
            
            results.append(cert_info)
        
        return {
            'status': 'success',
            'certificates_checked': len(results),
            'certificates': results,
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Certificate check failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def write_metric(client, project_id, metric_type, value, resource_name):
    """Write custom metric to Cloud Monitoring."""
    try:
        project_name = f"projects/{project_id}"
        
        series = monitoring_v3.TimeSeries()
        series.metric.type = f"custom.googleapis.com/{metric_type}"
        series.resource.type = "global"
        series.resource.labels["project_id"] = project_id
        
        point = monitoring_v3.Point()
        point.value.int64_value = value
        point.interval.end_time.seconds = int(datetime.utcnow().timestamp())
        series.points = [point]
        
        client.create_time_series(name=project_name, time_series=[series])
        
    except Exception as e:
        logger.error(f"Failed to write metric: {str(e)}")

@functions_framework.http
def update_dns_record(request):
    """Update DNS records for certificate validation or domain changes."""
    try:
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Invalid JSON payload'}, 400
            
        project_id = os.environ.get('GCP_PROJECT')
        zone_name = request_json.get('zone_name')
        record_name = request_json.get('record_name')
        record_type = request_json.get('record_type', 'A')
        record_data = request_json.get('record_data')
        ttl = request_json.get('ttl', 300)
        
        if not all([zone_name, record_name, record_data]):
            return {'error': 'Missing required parameters'}, 400
        
        # Initialize DNS client and get zone
        dns_client = dns.Client(project=project_id)
        zone = dns_client.zone(zone_name)
        
        # Create or update DNS record
        record_set = zone.resource_record_set(record_name, record_type, ttl, [record_data])
        
        # Check if record exists and update or create
        changes = zone.changes()
        
        try:
            existing_record = next(zone.list_resource_record_sets(name=record_name, type_=record_type))
            changes.delete_record_set(existing_record)
            logger.info(f"Existing record found, updating: {record_name}")
        except StopIteration:
            logger.info(f"Creating new record: {record_name}")
        
        changes.add_record_set(record_set)
        changes.create()
        
        # Wait for changes to complete
        while changes.status != 'done':
            changes.reload()
        
        return {
            'status': 'success',
            'message': f'DNS record {record_name} updated successfully',
            'record_type': record_type,
            'record_data': record_data
        }
        
    except Exception as e:
        logger.error(f"DNS update failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    # Create requirements file
    cat > "${func_dir}/requirements.txt" << 'EOF'
google-cloud-certificate-manager==1.13.0
google-cloud-dns==0.35.0
google-cloud-monitoring==2.21.0
google-cloud-secret-manager==2.20.0
functions-framework==3.5.0
EOF
    
    # Deploy certificate monitoring function
    log_info "Deploying certificate monitoring function..."
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source "${func_dir}" \
        --entry-point check_certificates \
        --memory 256MB \
        --timeout 60s \
        --service-account "cert-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID}" \
        --quiet; then
        
        log_success "Certificate monitoring function deployed"
    else
        log_error "Failed to deploy certificate monitoring function"
        exit 1
    fi
    
    # Deploy DNS update function
    log_info "Deploying DNS update function..."
    if gcloud functions deploy "dns-update-${RANDOM_SUFFIX}" \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source "${func_dir}" \
        --entry-point update_dns_record \
        --memory 256MB \
        --timeout 60s \
        --service-account "cert-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID}" \
        --quiet; then
        
        log_success "DNS update function deployed"
    else
        log_error "Failed to deploy DNS update function"
        exit 1
    fi
    
    # Get function URLs
    export CERT_FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --format="value(httpsTrigger.url)")
    export DNS_FUNCTION_URL=$(gcloud functions describe "dns-update-${RANDOM_SUFFIX}" \
        --format="value(httpsTrigger.url)")
    
    log_success "Cloud Functions deployed successfully"
    log_info "Certificate monitoring URL: ${CERT_FUNCTION_URL}"
    log_info "DNS update URL: ${DNS_FUNCTION_URL}"
    
    # Cleanup temporary directory
    rm -rf "${func_dir}"
}

# Function to create Cloud Scheduler jobs
create_scheduler_jobs() {
    log_info "Creating Cloud Scheduler jobs..."
    
    # Create main monitoring job
    if gcloud scheduler jobs create http "${SCHEDULER_JOB}" \
        --schedule="0 */6 * * *" \
        --uri="${CERT_FUNCTION_URL}" \
        --http-method=GET \
        --description="Automated certificate health monitoring" \
        --time-zone="UTC" \
        --quiet; then
        
        log_success "Main monitoring job created"
    else
        log_error "Failed to create main monitoring job"
        exit 1
    fi
    
    # Create daily audit job
    if gcloud scheduler jobs create http "daily-cert-audit-${RANDOM_SUFFIX}" \
        --schedule="0 2 * * *" \
        --uri="${CERT_FUNCTION_URL}" \
        --http-method=GET \
        --description="Daily comprehensive certificate audit" \
        --time-zone="UTC" \
        --quiet; then
        
        log_success "Daily audit job created"
    else
        log_error "Failed to create daily audit job"
        exit 1
    fi
    
    log_success "Scheduled monitoring jobs created successfully"
}

# Function to create load balancer
create_load_balancer() {
    log_info "Creating Application Load Balancer..."
    
    # Create backend service
    if gcloud compute backend-services create "demo-backend-${RANDOM_SUFFIX}" \
        --protocol=HTTP \
        --port-name=http \
        --health-checks-region="${REGION}" \
        --global \
        --quiet; then
        
        log_success "Backend service created"
    else
        log_error "Failed to create backend service"
        exit 1
    fi
    
    # Create URL map
    gcloud compute url-maps create "demo-url-map-${RANDOM_SUFFIX}" \
        --default-service="demo-backend-${RANDOM_SUFFIX}" \
        --global \
        --quiet
    
    # Create HTTPS proxy
    gcloud compute target-https-proxies create "demo-https-proxy-${RANDOM_SUFFIX}" \
        --url-map="demo-url-map-${RANDOM_SUFFIX}" \
        --certificate-map="cert-map-${RANDOM_SUFFIX}" \
        --global \
        --quiet
    
    # Create forwarding rule
    gcloud compute forwarding-rules create "demo-https-rule-${RANDOM_SUFFIX}" \
        --target-https-proxy="demo-https-proxy-${RANDOM_SUFFIX}" \
        --ports=443 \
        --global \
        --quiet
    
    # Get load balancer IP
    export LB_IP=$(gcloud compute forwarding-rules describe "demo-https-rule-${RANDOM_SUFFIX}" \
        --global --format="value(IPAddress)")
    
    log_success "Load balancer created successfully"
    log_info "Load balancer IP: ${LB_IP}"
}

# Function to configure DNS records
configure_dns_records() {
    log_info "Configuring DNS records..."
    
    # Add A record
    if curl -X POST "${DNS_FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d "{
            \"zone_name\": \"${DNS_ZONE_NAME}\",
            \"record_name\": \"${DOMAIN_NAME}.\",
            \"record_type\": \"A\",
            \"record_data\": \"${LB_IP}\",
            \"ttl\": 300
        }" >/dev/null 2>&1; then
        
        log_success "A record configured"
    else
        log_warning "A record configuration may have failed"
    fi
    
    # Add CNAME record
    if curl -X POST "${DNS_FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d "{
            \"zone_name\": \"${DNS_ZONE_NAME}\",
            \"record_name\": \"www.${DOMAIN_NAME}.\",
            \"record_type\": \"CNAME\",
            \"record_data\": \"${DOMAIN_NAME}.\",
            \"ttl\": 300
        }" >/dev/null 2>&1; then
        
        log_success "CNAME record configured"
    else
        log_warning "CNAME record configuration may have failed"
    fi
    
    log_success "DNS records configured successfully"
}

# Function to save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > deployment_state.env << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export DNS_ZONE_NAME="${DNS_ZONE_NAME}"
export DOMAIN_NAME="${DOMAIN_NAME}"
export CERT_NAME="${CERT_NAME}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export SCHEDULER_JOB="${SCHEDULER_JOB}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export CERT_FUNCTION_URL="${CERT_FUNCTION_URL}"
export DNS_FUNCTION_URL="${DNS_FUNCTION_URL}"
export LB_IP="${LB_IP}"
EOF
    
    log_success "Deployment state saved to deployment_state.env"
}

# Function to display post-deployment information
display_post_deployment_info() {
    log_success "Deployment completed successfully!"
    echo
    log_info "Resource Summary:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Domain: ${DOMAIN_NAME}"
    log_info "  DNS Zone: ${DNS_ZONE_NAME}"
    log_info "  Certificate: ${CERT_NAME}"
    log_info "  Load Balancer IP: ${LB_IP}"
    echo
    log_info "Function URLs:"
    log_info "  Certificate Monitor: ${CERT_FUNCTION_URL}"
    log_info "  DNS Update: ${DNS_FUNCTION_URL}"
    echo
    log_warning "Important Next Steps:"
    log_warning "1. Configure nameservers with your domain registrar (see nameservers.txt)"
    log_warning "2. Wait 5-15 minutes for certificate validation to complete"
    log_warning "3. Monitor certificate status with: gcloud certificate-manager certificates describe ${CERT_NAME} --global"
    echo
    log_info "To test the deployment, wait for certificate validation then visit: https://${DOMAIN_NAME}"
    log_info "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    echo "=================================================="
    echo "Domain and Certificate Lifecycle Management"
    echo "GCP Deployment Script"
    echo "=================================================="
    echo
    
    validate_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_dns_zone
    create_service_account
    create_certificate
    create_cloud_functions
    create_scheduler_jobs
    create_load_balancer
    configure_dns_records
    save_deployment_state
    display_post_deployment_info
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Run ./destroy.sh to clean up partial deployment."; exit 1' INT TERM

# Run main function
main "$@"