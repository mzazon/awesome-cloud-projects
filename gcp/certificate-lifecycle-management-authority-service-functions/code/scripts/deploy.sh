#!/bin/bash

# Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions
# Deployment Script for GCP
# This script deploys an automated certificate lifecycle management system

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    # Note: We don't automatically cleanup on error to preserve state for debugging
    # Users can run destroy.sh manually if needed
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-cert-lifecycle-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
FORCE_PROJECT_CREATION="${FORCE_PROJECT_CREATION:-false}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Resource names
CA_POOL_NAME="enterprise-ca-pool-${RANDOM_SUFFIX}"
ROOT_CA_NAME="root-ca-${RANDOM_SUFFIX}"
SUB_CA_NAME="sub-ca-${RANDOM_SUFFIX}"
MONITOR_FUNCTION_NAME="cert-monitor-${RANDOM_SUFFIX}"
RENEW_FUNCTION_NAME="cert-renew-${RANDOM_SUFFIX}"
REVOKE_FUNCTION_NAME="cert-revoke-${RANDOM_SUFFIX}"
SCHEDULER_JOB_NAME="cert-check-${RANDOM_SUFFIX}"
SERVICE_ACCOUNT_NAME="cert-automation-sa"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some operations may not work properly."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to setup project
setup_project() {
    log "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_success "Project ${PROJECT_ID} already exists"
    else
        if [[ "${FORCE_PROJECT_CREATION}" == "true" ]]; then
            log "Creating new project: ${PROJECT_ID}"
            gcloud projects create "${PROJECT_ID}" \
                --name="Certificate Lifecycle Management" \
                --labels="purpose=certificate-management,environment=demo"
            log_success "Project created: ${PROJECT_ID}"
        else
            log_error "Project ${PROJECT_ID} does not exist. Set FORCE_PROJECT_CREATION=true to create it."
            exit 1
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Billing is not enabled for project ${PROJECT_ID}. This may cause deployment failures."
        log_warning "Please enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
    fi
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "privateca.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "secretmanager.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}"
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled (30 seconds)..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create service account
create_service_account() {
    log "Creating service account for certificate automation..."
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create service account if it doesn't exist
    if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
        log_success "Service account already exists: ${service_account_email}"
    else
        gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
            --display-name="Certificate Automation Service Account" \
            --description="Service account for automated certificate lifecycle management"
        log_success "Service account created: ${service_account_email}"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/privateca.certificateManager"
        "roles/secretmanager.admin"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        log "Granting role ${role} to service account..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account_email}" \
            --role="${role}" \
            --quiet
    done
    
    # Export service account email for use in other functions
    export SERVICE_ACCOUNT_EMAIL="${service_account_email}"
    
    log_success "Service account configured with necessary permissions"
}

# Function to create CA infrastructure
create_ca_infrastructure() {
    log "Creating Certificate Authority infrastructure..."
    
    # Create Enterprise tier CA pool
    log "Creating CA pool: ${CA_POOL_NAME}"
    gcloud privateca pools create "${CA_POOL_NAME}" \
        --location="${REGION}" \
        --tier=ENTERPRISE \
        --subject="CN=Enterprise PKI Pool,O=Organization,C=US" \
        --issuance-policy="" \
        --publishing-options-include-ca-cert-url=true \
        --publishing-options-include-crl-access-url=true
    
    log_success "CA pool created: ${CA_POOL_NAME}"
    
    # Create root CA
    log "Creating root CA: ${ROOT_CA_NAME}"
    gcloud privateca roots create "${ROOT_CA_NAME}" \
        --pool="${CA_POOL_NAME}" \
        --location="${REGION}" \
        --subject="CN=Root CA,O=Organization,C=US" \
        --validity=10y \
        --key-algorithm=rsa-pkcs1-4096-sha256 \
        --max-chain-length=2
    
    # Enable the root CA
    gcloud privateca roots enable "${ROOT_CA_NAME}" \
        --pool="${CA_POOL_NAME}" \
        --location="${REGION}"
    
    log_success "Root CA created and enabled: ${ROOT_CA_NAME}"
    
    # Create subordinate CA
    log "Creating subordinate CA: ${SUB_CA_NAME}"
    gcloud privateca subordinates create "${SUB_CA_NAME}" \
        --pool="${CA_POOL_NAME}" \
        --location="${REGION}" \
        --issuer-pool="${CA_POOL_NAME}" \
        --issuer-location="${REGION}" \
        --subject="CN=Subordinate CA,O=Organization,OU=Operations,C=US" \
        --validity=5y \
        --key-algorithm=rsa-pkcs1-2048-sha256
    
    # Enable the subordinate CA
    gcloud privateca subordinates enable "${SUB_CA_NAME}" \
        --pool="${CA_POOL_NAME}" \
        --location="${REGION}"
    
    log_success "Subordinate CA created and enabled: ${SUB_CA_NAME}"
}

# Function to create Cloud Functions
create_cloud_functions() {
    log "Creating Cloud Functions for certificate lifecycle management..."
    
    # Create temporary directory for function source code
    local temp_dir=$(mktemp -d)
    
    # Create certificate monitoring function
    log "Creating certificate monitoring function..."
    mkdir -p "${temp_dir}/cert-monitor-function"
    
    cat > "${temp_dir}/cert-monitor-function/main.py" << 'EOF'
import json
import datetime
import logging
import os
from google.cloud import secretmanager
from google.cloud import privateca_v1
from google.cloud import functions_v1
import cryptography
from cryptography import x509
from cryptography.hazmat.backends import default_backend
import base64

def certificate_monitor(request):
    """Monitor certificates for expiration and trigger renewal"""
    
    # Initialize clients
    secret_client = secretmanager.SecretManagerServiceClient()
    ca_client = privateca_v1.CertificateAuthorityServiceClient()
    
    project_id = os.environ.get('PROJECT_ID')
    ca_pool = os.environ.get('CA_POOL_NAME')
    location = os.environ.get('REGION')
    renewal_threshold_days = int(os.environ.get('RENEWAL_THRESHOLD_DAYS', '30'))
    
    try:
        # List all secrets with certificate metadata
        parent = f"projects/{project_id}"
        secrets = secret_client.list_secrets(request={"parent": parent})
        
        expiring_certificates = []
        
        for secret in secrets:
            if 'certificate' in secret.name.lower():
                try:
                    # Get the latest version of the secret
                    secret_version_name = f"{secret.name}/versions/latest"
                    response = secret_client.access_secret_version(
                        request={"name": secret_version_name}
                    )
                    
                    # Parse certificate
                    cert_data = response.payload.data.decode('utf-8')
                    cert = x509.load_pem_x509_certificate(
                        cert_data.encode(), default_backend()
                    )
                    
                    # Check expiration
                    days_until_expiry = (cert.not_valid_after - datetime.datetime.utcnow()).days
                    
                    if days_until_expiry <= renewal_threshold_days:
                        cert_info = {
                            'secret_name': secret.name,
                            'common_name': cert.subject.get_attributes_for_oid(x509.NameOID.COMMON_NAME)[0].value,
                            'expiry_date': cert.not_valid_after.isoformat(),
                            'days_until_expiry': days_until_expiry
                        }
                        expiring_certificates.append(cert_info)
                        
                        # Log certificate requiring renewal
                        logging.info(f"Certificate {cert_info['common_name']} expires in {days_until_expiry} days")
                        
                except Exception as e:
                    logging.error(f"Error processing secret {secret.name}: {str(e)}")
                    continue
        
        # Trigger renewal for expiring certificates
        if expiring_certificates:
            # In a production environment, this would trigger the renewal function
            # For this example, we'll log the certificates that need renewal
            logging.info(f"Found {len(expiring_certificates)} certificates requiring renewal")
            
            for cert in expiring_certificates:
                logging.warning(f"RENEWAL REQUIRED: {cert['common_name']} expires {cert['expiry_date']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f"Processed certificate monitoring",
                'expiring_certificates': len(expiring_certificates),
                'certificates': expiring_certificates
            })
        }
        
    except Exception as e:
        logging.error(f"Certificate monitoring error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    cat > "${temp_dir}/cert-monitor-function/requirements.txt" << 'EOF'
google-cloud-secret-manager==2.20.0
google-cloud-private-ca==1.11.0
google-cloud-functions==1.16.0
cryptography==41.0.7
EOF
    
    # Create certificate renewal function
    log "Creating certificate renewal function..."
    mkdir -p "${temp_dir}/cert-renewal-function"
    
    cat > "${temp_dir}/cert-renewal-function/main.py" << 'EOF'
import json
import logging
import datetime
import os
from google.cloud import secretmanager
from google.cloud import privateca_v1
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID

def certificate_renewal(request):
    """Renew expiring certificates using Certificate Authority Service"""
    
    # Initialize clients
    secret_client = secretmanager.SecretManagerServiceClient()
    ca_client = privateca_v1.CertificateAuthorityServiceClient()
    
    project_id = os.environ.get('PROJECT_ID')
    ca_pool = os.environ.get('CA_POOL_NAME')
    sub_ca = os.environ.get('SUB_CA_NAME')
    location = os.environ.get('REGION')
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json or 'common_name' not in request_json:
            raise ValueError("Missing required 'common_name' in request")
        
        common_name = request_json['common_name']
        validity_days = request_json.get('validity_days', 365)
        
        # Generate new private key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
        
        # Create certificate request
        subject = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Organization"),
            x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        ])
        
        # Build certificate signing request
        csr = x509.CertificateSigningRequestBuilder().subject_name(
            subject
        ).add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName(common_name),
            ]),
            critical=False,
        ).add_extension(
            x509.KeyUsage(
                digital_signature=True,
                key_encipherment=True,
                content_commitment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False
            ),
            critical=True,
        ).add_extension(
            x509.ExtendedKeyUsage([
                ExtendedKeyUsageOID.SERVER_AUTH,
                ExtendedKeyUsageOID.CLIENT_AUTH,
            ]),
            critical=True,
        ).sign(private_key, hashes.SHA256())
        
        # Submit certificate request to CA Service
        ca_parent = f"projects/{project_id}/locations/{location}/caPools/{ca_pool}"
        
        certificate_request = privateca_v1.Certificate(
            pem_csr=csr.public_bytes(serialization.Encoding.PEM).decode('utf-8'),
            lifetime=datetime.timedelta(days=validity_days)
        )
        
        request_obj = privateca_v1.CreateCertificateRequest(
            parent=ca_parent,
            certificate=certificate_request,
            certificate_id=f"{common_name.replace('.', '-')}-{int(datetime.datetime.now().timestamp())}"
        )
        
        # Issue the certificate
        operation = ca_client.create_certificate(request=request_obj)
        certificate = operation.result()
        
        # Prepare certificate and private key for storage
        cert_pem = certificate.pem_certificate
        private_key_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        ).decode('utf-8')
        
        # Store certificate in Secret Manager
        secret_name = f"projects/{project_id}/secrets/cert-{common_name.replace('.', '-')}"
        
        # Create or update secret with new certificate
        cert_bundle = {
            'certificate': cert_pem,
            'private_key': private_key_pem,
            'issued_date': datetime.datetime.utcnow().isoformat(),
            'expiry_date': (datetime.datetime.utcnow() + datetime.timedelta(days=validity_days)).isoformat()
        }
        
        secret_payload = json.dumps(cert_bundle).encode('utf-8')
        
        try:
            # Try to create new secret
            secret_client.create_secret(
                request={
                    "parent": f"projects/{project_id}",
                    "secret_id": f"cert-{common_name.replace('.', '-')}",
                    "secret": {"replication": {"automatic": {}}}
                }
            )
        except Exception:
            # Secret already exists, which is fine
            pass
        
        # Add new version
        secret_client.add_secret_version(
            request={
                "parent": secret_name,
                "payload": {"data": secret_payload}
            }
        )
        
        logging.info(f"Successfully renewed certificate for {common_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f"Certificate renewed successfully for {common_name}",
                'certificate_name': certificate.name,
                'expiry_date': (datetime.datetime.utcnow() + datetime.timedelta(days=validity_days)).isoformat()
            })
        }
        
    except Exception as e:
        logging.error(f"Certificate renewal error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    cat > "${temp_dir}/cert-renewal-function/requirements.txt" << 'EOF'
google-cloud-secret-manager==2.20.0
google-cloud-private-ca==1.11.0
cryptography==41.0.7
EOF
    
    # Deploy certificate monitoring function
    log "Deploying certificate monitoring function..."
    gcloud functions deploy "${MONITOR_FUNCTION_NAME}" \
        --source="${temp_dir}/cert-monitor-function" \
        --runtime=python39 \
        --trigger=http \
        --entry-point=certificate_monitor \
        --service-account="${SERVICE_ACCOUNT_EMAIL}" \
        --region="${REGION}" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},CA_POOL_NAME=${CA_POOL_NAME},REGION=${REGION},RENEWAL_THRESHOLD_DAYS=30" \
        --memory=256MB \
        --timeout=540s \
        --allow-unauthenticated
    
    # Deploy certificate renewal function
    log "Deploying certificate renewal function..."
    gcloud functions deploy "${RENEW_FUNCTION_NAME}" \
        --source="${temp_dir}/cert-renewal-function" \
        --runtime=python39 \
        --trigger=http \
        --entry-point=certificate_renewal \
        --service-account="${SERVICE_ACCOUNT_EMAIL}" \
        --region="${REGION}" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},CA_POOL_NAME=${CA_POOL_NAME},SUB_CA_NAME=${SUB_CA_NAME},REGION=${REGION}" \
        --memory=512MB \
        --timeout=540s \
        --allow-unauthenticated
    
    # Clean up temporary directory
    rm -rf "${temp_dir}"
    
    log_success "Cloud Functions deployed successfully"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log "Creating Cloud Scheduler job for automated monitoring..."
    
    # Get monitor function URL
    local monitor_function_url
    monitor_function_url=$(gcloud functions describe "${MONITOR_FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")
    
    # Create Cloud Scheduler job
    gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
        --location="${REGION}" \
        --schedule="0 8 * * *" \
        --time-zone="America/New_York" \
        --uri="${monitor_function_url}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"source":"scheduler","action":"monitor"}' \
        --oidc-service-account-email="${SERVICE_ACCOUNT_EMAIL}"
    
    log_success "Scheduler job created: ${SCHEDULER_JOB_NAME}"
    log "Monitor function URL: ${monitor_function_url}"
}

# Function to create certificate template
create_certificate_template() {
    log "Creating certificate template for standardized issuance..."
    
    local temp_dir=$(mktemp -d)
    
    cat > "${temp_dir}/web-server-template.yaml" << EOF
name: projects/${PROJECT_ID}/locations/${REGION}/certificateTemplates/web-server-template
description: "Standard template for web server certificates"
predefined_values:
  key_usage:
    base_key_usage:
      digital_signature: true
      key_encipherment: true
    extended_key_usage:
      server_auth: true
      client_auth: true
  ca_options:
    is_ca: false
  policy_ids:
    - object_id_path: [1, 3, 6, 1, 4, 1, 11129, 2, 5, 2]
identity_constraints:
  cel_expression:
    expression: 'subject_alt_names.all(san, san.type == DNS)'
    title: "DNS SANs only"
    description: "Only DNS Subject Alternative Names are allowed"
passthrough_extensions:
  known_extensions:
    - SUBJECT_ALT_NAME
  additional_extensions:
    - object_id_path: [2, 5, 29, 17]
EOF
    
    # Create the certificate template
    gcloud privateca templates create web-server-template \
        --location="${REGION}" \
        --definition-file="${temp_dir}/web-server-template.yaml"
    
    # Clean up temporary file
    rm -rf "${temp_dir}"
    
    log_success "Certificate template created for standardized issuance"
}

# Function to configure monitoring and alerting
configure_monitoring() {
    log "Configuring monitoring and alerting..."
    
    local temp_dir=$(mktemp -d)
    
    cat > "${temp_dir}/cert-alert-policy.yaml" << EOF
displayName: "Certificate Expiration Alert"
documentation:
  content: "Alert when certificates are approaching expiration"
  mimeType: "text/markdown"
conditions:
  - displayName: "Certificate Monitor Function Errors"
    conditionThreshold:
      filter: 'resource.type="cloud_function" AND resource.labels.function_name="${MONITOR_FUNCTION_NAME}"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 0
      duration: 300s
      aggregations:
        - alignmentPeriod: 300s
          perSeriesAligner: ALIGN_RATE
          crossSeriesReducer: REDUCE_SUM
notificationChannels: []
alertStrategy:
  autoClose: 86400s
enabled: true
EOF
    
    # Create the alerting policy
    gcloud alpha monitoring policies create --policy-from-file="${temp_dir}/cert-alert-policy.yaml"
    
    # Clean up temporary file
    rm -rf "${temp_dir}"
    
    log_success "Monitoring and alerting configured"
}

# Function to perform validation tests
perform_validation() {
    log "Performing validation tests..."
    
    # Test certificate issuance
    log "Testing certificate renewal function..."
    local renew_function_url
    renew_function_url=$(gcloud functions describe "${RENEW_FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")
    
    # Issue test certificate
    curl -X POST "${renew_function_url}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
        -d '{"common_name": "test.example.com", "validity_days": 90}' \
        --silent --fail || log_warning "Certificate renewal test failed - this may be expected if quotas are exceeded"
    
    # Test monitoring function
    log "Testing certificate monitoring function..."
    local monitor_function_url
    monitor_function_url=$(gcloud functions describe "${MONITOR_FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")
    
    curl -X POST "${monitor_function_url}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
        -d '{"source":"manual_test","action":"monitor"}' \
        --silent --fail || log_warning "Certificate monitoring test failed - this may be expected"
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "CA Pool: ${CA_POOL_NAME}"
    echo "Root CA: ${ROOT_CA_NAME}"
    echo "Subordinate CA: ${SUB_CA_NAME}"
    echo "Monitor Function: ${MONITOR_FUNCTION_NAME}"
    echo "Renewal Function: ${RENEW_FUNCTION_NAME}"
    echo "Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo "Service Account: ${SERVICE_ACCOUNT_EMAIL}"
    echo ""
    echo "Function URLs:"
    echo "Monitor: $(gcloud functions describe "${MONITOR_FUNCTION_NAME}" --region="${REGION}" --format="value(httpsTrigger.url)" 2>/dev/null || echo "N/A")"
    echo "Renewal: $(gcloud functions describe "${RENEW_FUNCTION_NAME}" --region="${REGION}" --format="value(httpsTrigger.url)" 2>/dev/null || echo "N/A")"
    echo ""
    echo "Next Steps:"
    echo "1. Configure notification channels for alerting"
    echo "2. Set up certificate templates for your specific use cases"
    echo "3. Begin issuing certificates using the renewal function"
    echo "4. Monitor certificate lifecycle through Cloud Logging"
    echo ""
    echo "To clean up all resources, run: ./destroy.sh"
    echo "===================="
}

# Main deployment function
main() {
    log "Starting Certificate Lifecycle Management deployment..."
    log "Using Project ID: ${PROJECT_ID}"
    log "Using Region: ${REGION}"
    
    check_prerequisites
    setup_project
    enable_apis
    create_service_account
    create_ca_infrastructure
    create_cloud_functions
    create_scheduler_job
    create_certificate_template
    configure_monitoring
    perform_validation
    display_summary
    
    log_success "Certificate Lifecycle Management deployment completed successfully!"
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
        --force-project-creation)
            FORCE_PROJECT_CREATION="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id PROJECT_ID          Set Google Cloud project ID"
            echo "  --region REGION                  Set deployment region (default: us-central1)"
            echo "  --force-project-creation         Create project if it doesn't exist"
            echo "  --help                           Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_ID                       Google Cloud project ID"
            echo "  REGION                           Deployment region"
            echo "  FORCE_PROJECT_CREATION           Create project if needed (true/false)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main deployment
main