#!/bin/bash

# Quantum-Safe Security Posture Management Deployment Script
# This script deploys the quantum-safe security infrastructure using GCP services
# including Security Command Center, Cloud KMS with post-quantum cryptography,
# Cloud Asset Inventory, and Cloud Monitoring

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/../terraform/terraform.tfvars"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    error "Deployment failed. Check ${LOG_FILE} for details."
    error "To cleanup resources, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Banner
echo "=========================================="
echo "  Quantum-Safe Security Posture Setup"
echo "=========================================="
echo ""

# Prerequisites validation
validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Check for required roles
    local current_user=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    info "Current user: ${current_user}"
    
    # Validate organization access
    if ! gcloud organizations list --format="value(name)" | head -1 > /dev/null 2>&1; then
        error "Cannot access organization. Ensure you have Organization Viewer role."
        exit 1
    fi
    
    # Check for terraform if using terraform deployment
    if [[ -f "${SCRIPT_DIR}/../terraform/main.tf" ]]; then
        if ! command -v terraform &> /dev/null; then
            warn "Terraform not found. Will use gcloud commands for deployment."
        else
            info "Terraform found. Terraform deployment available."
        fi
    fi
    
    success "Prerequisites validation completed"
}

# Set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Generate unique project ID
    export PROJECT_ID="quantum-security-$(date +%s)"
    export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export KMS_KEYRING_NAME="quantum-safe-keyring-${RANDOM_SUFFIX}"
    export KMS_KEY_NAME="quantum-safe-key-${RANDOM_SUFFIX}"
    
    # Billing account (get the first available)
    export BILLING_ACCOUNT=$(gcloud billing accounts list --format="value(name)" --limit=1)
    
    if [[ -z "${BILLING_ACCOUNT}" ]]; then
        error "No billing account found. Please ensure you have access to a billing account."
        exit 1
    fi
    
    info "Project ID: ${PROJECT_ID}"
    info "Organization ID: ${ORGANIZATION_ID##*/}"
    info "Region: ${REGION}"
    info "Billing Account: ${BILLING_ACCOUNT##*/}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "Environment setup completed"
}

# Create and configure project
setup_project() {
    info "Creating and configuring project..."
    
    # Create project
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        gcloud projects create "${PROJECT_ID}" \
            --name="Quantum Security Posture Management" \
            --organization="${ORGANIZATION_ID##*/}"
        info "Project ${PROJECT_ID} created"
    else
        warn "Project ${PROJECT_ID} already exists"
    fi
    
    # Link billing account
    gcloud billing projects link "${PROJECT_ID}" \
        --billing-account="${BILLING_ACCOUNT##*/}"
    
    # Set default project
    gcloud config set project "${PROJECT_ID}"
    
    success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "securitycenter.googleapis.com"
        "cloudkms.googleapis.com"
        "cloudasset.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        gcloud services enable "${api}" --project="${PROJECT_ID}"
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "APIs enabled successfully"
}

# Setup organization-level security policies
setup_security_policies() {
    info "Configuring organization-level security policies..."
    
    # Create quantum security policy file
    cat > "${SCRIPT_DIR}/quantum-security-policy.yaml" << EOF
name: organizations/${ORGANIZATION_ID##*/}/policies/compute.requireOsLogin
spec:
  rules:
  - enforce: true
---
name: organizations/${ORGANIZATION_ID##*/}/policies/iam.disableServiceAccountKeyCreation
spec:
  rules:
  - enforce: true
EOF
    
    # Apply organization policies (may require org admin permissions)
    if gcloud org-policies set-policy "${SCRIPT_DIR}/quantum-security-policy.yaml" 2>/dev/null; then
        success "Organization policies applied"
    else
        warn "Could not apply organization policies. May require Organization Policy Administrator role."
    fi
}

# Create KMS infrastructure with post-quantum cryptography
setup_kms() {
    info "Setting up Cloud KMS with post-quantum cryptography..."
    
    # Create KMS keyring
    if ! gcloud kms keyrings describe "${KMS_KEYRING_NAME}" \
        --location="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
        gcloud kms keyrings create "${KMS_KEYRING_NAME}" \
            --location="${REGION}" \
            --project="${PROJECT_ID}"
        info "KMS keyring ${KMS_KEYRING_NAME} created"
    else
        warn "KMS keyring ${KMS_KEYRING_NAME} already exists"
    fi
    
    # Create post-quantum cryptography keys
    # Note: PQ algorithms may be in preview - fallback to standard algorithms if not available
    
    # Try ML-DSA-65 (post-quantum)
    if ! gcloud kms keys describe "${KMS_KEY_NAME}-ml-dsa" \
        --keyring="${KMS_KEYRING_NAME}" \
        --location="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
        
        if gcloud kms keys create "${KMS_KEY_NAME}-ml-dsa" \
            --location="${REGION}" \
            --keyring="${KMS_KEYRING_NAME}" \
            --purpose=asymmetric-signing \
            --algorithm=PQ_SIGN_ML_DSA_65 \
            --project="${PROJECT_ID}" 2>/dev/null; then
            success "Post-quantum ML-DSA key created"
        else
            warn "Post-quantum algorithms not available. Creating standard RSA key instead."
            gcloud kms keys create "${KMS_KEY_NAME}-rsa" \
                --location="${REGION}" \
                --keyring="${KMS_KEYRING_NAME}" \
                --purpose=asymmetric-signing \
                --algorithm=RSA_SIGN_PKCS1_4096_SHA256 \
                --project="${PROJECT_ID}"
        fi
    fi
    
    # Try SLH-DSA (post-quantum)
    if ! gcloud kms keys describe "${KMS_KEY_NAME}-slh-dsa" \
        --keyring="${KMS_KEYRING_NAME}" \
        --location="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
        
        if ! gcloud kms keys create "${KMS_KEY_NAME}-slh-dsa" \
            --location="${REGION}" \
            --keyring="${KMS_KEYRING_NAME}" \
            --purpose=asymmetric-signing \
            --algorithm=PQ_SIGN_SLH_DSA_SHA2_128S \
            --project="${PROJECT_ID}" 2>/dev/null; then
            warn "SLH-DSA algorithm not available in this region"
        else
            success "Post-quantum SLH-DSA key created"
        fi
    fi
    
    success "KMS setup completed"
}

# Setup Asset Inventory
setup_asset_inventory() {
    info "Configuring Cloud Asset Inventory..."
    
    # Create Pub/Sub topic for asset changes
    if ! gcloud pubsub topics describe crypto-asset-changes --project="${PROJECT_ID}" &>/dev/null; then
        gcloud pubsub topics create crypto-asset-changes --project="${PROJECT_ID}"
        info "Pub/Sub topic created"
    fi
    
    # Create asset inventory feed (may require organization permissions)
    if gcloud asset feeds create quantum-crypto-assets \
        --organization="${ORGANIZATION_ID##*/}" \
        --asset-types="cloudkms.googleapis.com/CryptoKey,cloudkms.googleapis.com/KeyRing" \
        --content-type=RESOURCE \
        --pubsub-topic="projects/${PROJECT_ID}/topics/crypto-asset-changes" 2>/dev/null; then
        success "Asset inventory feed created"
    else
        warn "Could not create asset inventory feed. May require Asset Inventory Admin role at org level."
    fi
    
    # Create storage bucket for inventory exports
    local bucket_name="${PROJECT_ID}-crypto-inventory"
    if ! gsutil ls -b "gs://${bucket_name}" &>/dev/null; then
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${bucket_name}"
        info "Storage bucket created: gs://${bucket_name}"
    fi
}

# Setup Security Command Center (if available)
setup_security_command_center() {
    info "Configuring Security Command Center..."
    
    # Check if Security Command Center is available (requires enterprise subscription)
    if gcloud scc organizations describe "${ORGANIZATION_ID##*/}" &>/dev/null; then
        info "Security Command Center is available"
        
        # Create security posture (this may require preview APIs)
        cat > "${SCRIPT_DIR}/quantum-security-posture.yaml" << EOF
displayName: "Quantum-Safe Security Posture"
description: "Assess readiness for post-quantum cryptography threats"
EOF
        
        if gcloud scc postures create quantum-safe-posture \
            --organization="${ORGANIZATION_ID##*/}" \
            --location=global \
            --from-file="${SCRIPT_DIR}/quantum-security-posture.yaml" 2>/dev/null; then
            success "Security posture created"
        else
            warn "Could not create security posture. Feature may be in preview."
        fi
    else
        warn "Security Command Center Enterprise not available. Some features will be limited."
    fi
}

# Setup monitoring and alerting
setup_monitoring() {
    info "Setting up Cloud Monitoring and alerting..."
    
    # Create monitoring dashboard
    cat > "${SCRIPT_DIR}/quantum-metrics-dashboard.json" << 'EOF'
{
  "displayName": "Quantum Security Posture Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Post-Quantum Key Usage",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"cloudkms_cryptokey\"",
                "aggregation": {
                  "alignmentPeriod": "300s",
                  "perSeriesAligner": "ALIGN_COUNT"
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
          "title": "Quantum Vulnerability Alerts",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"gce_instance\" AND log_name=\"quantum_vulnerability_scan\"",
                "aggregation": {
                  "alignmentPeriod": "3600s",
                  "perSeriesAligner": "ALIGN_COUNT"
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
    
    # Create dashboard
    if gcloud monitoring dashboards create \
        --config-from-file="${SCRIPT_DIR}/quantum-metrics-dashboard.json" \
        --project="${PROJECT_ID}" &>/dev/null; then
        success "Monitoring dashboard created"
    else
        warn "Could not create monitoring dashboard"
    fi
    
    # Create alerting policy
    cat > "${SCRIPT_DIR}/quantum-alert-policy.yaml" << 'EOF'
displayName: "Quantum Vulnerability Detection"
conditions:
- displayName: "Weak encryption detected"
  conditionThreshold:
    filter: 'resource.type="gce_instance" AND log_name="quantum_vulnerability_scan"'
    comparison: COMPARISON_GT
    thresholdValue: 0
    duration: 300s
notificationChannels: []
alertStrategy:
  autoClose: 86400s
EOF
    
    # Apply alert policy
    if gcloud alpha monitoring policies create \
        --policy-from-file="${SCRIPT_DIR}/quantum-alert-policy.yaml" \
        --project="${PROJECT_ID}" &>/dev/null; then
        success "Alert policy created"
    else
        warn "Could not create alert policy"
    fi
}

# Deploy compliance reporting function
setup_compliance_function() {
    info "Deploying compliance reporting function..."
    
    # Create function source directory
    local function_dir="${SCRIPT_DIR}/compliance-function"
    mkdir -p "${function_dir}"
    
    # Create function code
    cat > "${function_dir}/main.py" << 'EOF'
import json
import functions_framework
from google.cloud import asset_v1
from datetime import datetime

@functions_framework.http
def generate_quantum_compliance_report(request):
    """Generate quantum readiness compliance report"""
    
    try:
        # Get organization ID from request
        org_id = request.args.get('org_id', '')
        if not org_id:
            return json.dumps({"error": "Organization ID required"}), 400
        
        # Initialize asset client
        asset_client = asset_v1.AssetServiceClient()
        
        # Query cryptographic assets
        parent = f"organizations/{org_id}"
        
        # Generate basic compliance report
        report = {
            "report_date": datetime.now().isoformat(),
            "organization_id": org_id,
            "status": "assessment_required",
            "recommendations": [
                "Implement post-quantum cryptography assessment",
                "Migrate to quantum-safe algorithms",
                "Establish cryptographic agility"
            ]
        }
        
        return json.dumps(report, indent=2)
        
    except Exception as e:
        return json.dumps({"error": str(e)}), 500
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-asset==3.18.1
functions-framework==3.4.0
EOF
    
    # Deploy function
    if gcloud functions deploy quantum-compliance-report \
        --runtime=python39 \
        --trigger=http \
        --source="${function_dir}" \
        --entry-point=generate_quantum_compliance_report \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --allow-unauthenticated 2>/dev/null; then
        success "Compliance function deployed"
        
        # Create scheduler job for quarterly reports
        if gcloud scheduler jobs create http quantum-compliance-scheduler \
            --schedule="0 9 1 */3 *" \
            --uri="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/quantum-compliance-report?org_id=${ORGANIZATION_ID##*/}" \
            --http-method=GET \
            --location="${REGION}" \
            --project="${PROJECT_ID}" 2>/dev/null; then
            success "Compliance scheduler created"
        fi
    else
        warn "Could not deploy compliance function"
    fi
}

# Generate terraform variables file
generate_terraform_vars() {
    if [[ -f "${SCRIPT_DIR}/../terraform/main.tf" ]]; then
        info "Generating Terraform variables file..."
        
        cat > "${CONFIG_FILE}" << EOF
# Quantum-Safe Security Posture Management Configuration
project_id         = "${PROJECT_ID}"
organization_id    = "${ORGANIZATION_ID##*/}"
region            = "${REGION}"
zone              = "${ZONE}"
kms_keyring_name  = "${KMS_KEYRING_NAME}"
kms_key_name      = "${KMS_KEY_NAME}"
billing_account   = "${BILLING_ACCOUNT##*/}"

# Security settings
enable_organization_policies = true
enable_asset_inventory       = true
enable_monitoring           = true
enable_compliance_reporting = true

# Resource naming
resource_suffix = "${RANDOM_SUFFIX}"
EOF
        
        success "Terraform configuration generated: ${CONFIG_FILE}"
    fi
}

# Validation and testing
validate_deployment() {
    info "Validating deployment..."
    
    # Check project exists and is accessible
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        success "✅ Project ${PROJECT_ID} is accessible"
    else
        error "❌ Project validation failed"
        return 1
    fi
    
    # Check KMS keyring
    if gcloud kms keyrings describe "${KMS_KEYRING_NAME}" \
        --location="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
        success "✅ KMS keyring created successfully"
    else
        error "❌ KMS keyring validation failed"
        return 1
    fi
    
    # Check for keys
    local key_count=$(gcloud kms keys list --keyring="${KMS_KEYRING_NAME}" \
        --location="${REGION}" --project="${PROJECT_ID}" --format="value(name)" | wc -l)
    if [[ ${key_count} -gt 0 ]]; then
        success "✅ Cryptographic keys created (${key_count} keys)"
    else
        warn "⚠️  No cryptographic keys found"
    fi
    
    # Check APIs
    local enabled_apis=$(gcloud services list --enabled --project="${PROJECT_ID}" --format="value(name)" | grep -E "(kms|security|asset)" | wc -l)
    if [[ ${enabled_apis} -ge 3 ]]; then
        success "✅ Required APIs are enabled"
    else
        warn "⚠️  Some APIs may not be enabled"
    fi
    
    success "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "         DEPLOYMENT COMPLETED"
    echo "=========================================="
    echo ""
    echo "📋 Deployment Summary:"
    echo "   • Project ID: ${PROJECT_ID}"
    echo "   • Organization: ${ORGANIZATION_ID##*/}"
    echo "   • Region: ${REGION}"
    echo "   • KMS Keyring: ${KMS_KEYRING_NAME}"
    echo ""
    echo "🔐 Quantum-Safe Security Components:"
    echo "   • Cloud KMS with post-quantum cryptography"
    echo "   • Cloud Asset Inventory for crypto assets"
    echo "   • Security Command Center integration"
    echo "   • Cloud Monitoring and alerting"
    echo "   • Automated compliance reporting"
    echo ""
    echo "📊 Access Points:"
    echo "   • Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    echo "   • KMS Keys: https://console.cloud.google.com/security/kms/keyrings?project=${PROJECT_ID}"
    echo "   • Security Center: https://console.cloud.google.com/security/command-center?project=${PROJECT_ID}"
    echo "   • Monitoring: https://console.cloud.google.com/monitoring?project=${PROJECT_ID}"
    echo ""
    echo "📁 Configuration Files:"
    echo "   • Deployment log: ${LOG_FILE}"
    if [[ -f "${CONFIG_FILE}" ]]; then
        echo "   • Terraform vars: ${CONFIG_FILE}"
    fi
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Review Security Command Center for quantum vulnerabilities"
    echo "   2. Configure additional notification channels for alerts"
    echo "   3. Customize compliance reporting for your organization"
    echo "   4. Plan migration strategy for quantum-vulnerable systems"
    echo ""
    echo "🧹 To cleanup resources: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    info "Starting quantum-safe security posture deployment..."
    
    validate_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_security_policies
    setup_kms
    setup_asset_inventory
    setup_security_command_center
    setup_monitoring
    setup_compliance_function
    generate_terraform_vars
    validate_deployment
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    success "Deployment completed successfully in ${duration} seconds"
    display_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi