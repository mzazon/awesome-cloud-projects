#!/bin/bash

# =============================================================================
# Azure Static Website Acceleration with CDN and Storage - Deployment Script
# =============================================================================
# This script deploys a globally distributed static website using Azure Storage
# Account static hosting capabilities combined with Azure CDN for worldwide
# content acceleration.
#
# Prerequisites:
# - Azure CLI installed and configured
# - Active Azure subscription with Storage Account Contributor permissions
# - Bash shell environment
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_info "Run ./destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    log_info "Using Azure subscription: ${subscription_id}"
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        log_warning "curl is not available. Website testing will be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Resource validation
validate_resource_availability() {
    local resource_group="$1"
    local storage_account="$2"
    local location="$3"
    
    log_info "Validating resource availability..."
    
    # Check if resource group name is available
    if az group exists --name "${resource_group}" | grep -q "true"; then
        log_warning "Resource group '${resource_group}' already exists. Will use existing group."
    fi
    
    # Check if storage account name is available
    local name_available
    name_available=$(az storage account check-name --name "${storage_account}" --query nameAvailable -o tsv)
    if [[ "${name_available}" != "true" ]]; then
        log_error "Storage account name '${storage_account}' is not available."
        exit 1
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='${location}']" -o tsv | grep -q "${location}"; then
        log_error "Location '${location}' is not valid for this subscription."
        exit 1
    fi
    
    log_success "Resource availability validated"
}

# State management
save_deployment_state() {
    local resource_group="$1"
    local storage_account="$2"
    local cdn_profile="$3"
    local cdn_endpoint="$4"
    local location="$5"
    
    cat > "${STATE_FILE}" << EOF
RESOURCE_GROUP=${resource_group}
STORAGE_ACCOUNT=${storage_account}
CDN_PROFILE=${cdn_profile}
CDN_ENDPOINT=${cdn_endpoint}
LOCATION=${location}
DEPLOYMENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_info "Deployment state saved to ${STATE_FILE}"
}

# Website content creation
create_website_content() {
    local content_dir="$1"
    
    log_info "Creating website content in ${content_dir}..."
    
    mkdir -p "${content_dir}"
    
    # Create index.html
    cat > "${content_dir}/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Global Product Catalog - Accelerated by Azure CDN</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <h1>Welcome to Our Global Store</h1>
        <p>Lightning-fast delivery worldwide via Azure CDN</p>
    </header>
    <main>
        <section class="hero">
            <h2>Experience Global Performance</h2>
            <p>This website is delivered from Azure's global edge network, 
               ensuring fast loading times regardless of your location.</p>
        </section>
        <section class="products">
            <h3>Featured Products</h3>
            <div class="product-grid">
                <div class="product">Premium Headphones - $299</div>
                <div class="product">Smart Watch - $399</div>
                <div class="product">Wireless Speaker - $199</div>
            </div>
        </section>
    </main>
    <footer>
        <p>Deployed with Azure Static Website + CDN</p>
        <p>Deployment Time: <span id="deployment-time"></span></p>
    </footer>
    <script src="app.js"></script>
</body>
</html>
EOF

    # Create styles.css
    cat > "${content_dir}/styles.css" << 'EOF'
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
header { background: #0078D4; color: white; padding: 2rem; text-align: center; }
.hero { padding: 3rem 2rem; background: #f4f4f4; text-align: center; }
.products { padding: 2rem; }
.product-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-top: 1rem; }
.product { background: white; padding: 1rem; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
footer { background: #f8f9fa; padding: 1rem; text-align: center; margin-top: 2rem; font-size: 0.9em; color: #666; }
EOF

    # Create app.js
    cat > "${content_dir}/app.js" << 'EOF'
document.addEventListener('DOMContentLoaded', function() {
    console.log('Static website loaded via Azure CDN');
    
    // Display deployment time if element exists
    const deploymentTimeElement = document.getElementById('deployment-time');
    if (deploymentTimeElement) {
        deploymentTimeElement.textContent = new Date().toISOString();
    }
    
    // Add performance timing
    window.addEventListener('load', function() {
        const loadTime = performance.timing.loadEventEnd - performance.timing.navigationStart;
        console.log('Page load time: ' + loadTime + 'ms');
        
        // Add load time to page if in development
        if (window.location.hostname.includes('blob.core.windows.net') || 
            window.location.hostname.includes('azureedge.net')) {
            const loadTimeElement = document.createElement('div');
            loadTimeElement.style.cssText = 'position:fixed;top:10px;right:10px;background:#0078D4;color:white;padding:5px 10px;border-radius:3px;font-size:12px;z-index:1000;';
            loadTimeElement.textContent = `Load: ${loadTime}ms`;
            document.body.appendChild(loadTimeElement);
        }
    });
});
EOF

    # Create 404.html
    cat > "${content_dir}/404.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - Global Store</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header><h1>Page Not Found</h1></header>
    <main style="padding: 2rem; text-align: center;">
        <h2>404 - Content Not Available</h2>
        <p>The requested page could not be found.</p>
        <a href="/" style="color: #0078D4;">Return to Home</a>
    </main>
</body>
</html>
EOF

    log_success "Website content created successfully"
}

# Resource deployment functions
deploy_storage_account() {
    local resource_group="$1"
    local storage_account="$2"
    local location="$3"
    
    log_info "Creating storage account: ${storage_account}"
    
    az storage account create \
        --name "${storage_account}" \
        --resource-group "${resource_group}" \
        --location "${location}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --allow-blob-public-access true \
        --tags purpose=static-website environment=demo \
        --output none
    
    log_success "Storage account created: ${storage_account}"
}

enable_static_website() {
    local storage_account="$1"
    
    log_info "Enabling static website hosting..."
    
    az storage blob service-properties update \
        --account-name "${storage_account}" \
        --static-website \
        --404-document 404.html \
        --index-document index.html \
        --output none
    
    log_success "Static website hosting enabled"
}

upload_website_content() {
    local storage_account="$1"
    local content_dir="$2"
    
    log_info "Uploading website content..."
    
    # Upload HTML files
    az storage blob upload-batch \
        --account-name "${storage_account}" \
        --source "${content_dir}" \
        --destination '$web' \
        --pattern "*.html" \
        --content-type "text/html" \
        --overwrite \
        --output none
    
    # Upload CSS files
    az storage blob upload-batch \
        --account-name "${storage_account}" \
        --source "${content_dir}" \
        --destination '$web' \
        --pattern "*.css" \
        --content-type "text/css" \
        --overwrite \
        --output none
    
    # Upload JavaScript files
    az storage blob upload-batch \
        --account-name "${storage_account}" \
        --source "${content_dir}" \
        --destination '$web' \
        --pattern "*.js" \
        --content-type "application/javascript" \
        --overwrite \
        --output none
    
    log_success "Website content uploaded successfully"
}

deploy_cdn() {
    local resource_group="$1"
    local cdn_profile="$2"
    local cdn_endpoint="$3"
    local website_url="$4"
    
    log_info "Creating CDN profile: ${cdn_profile}"
    
    az cdn profile create \
        --name "${cdn_profile}" \
        --resource-group "${resource_group}" \
        --sku Standard_Microsoft \
        --tags purpose=content-delivery \
        --output none
    
    # Extract origin hostname from website URL
    local origin_hostname
    origin_hostname=$(echo "${website_url}" | sed 's|https://||' | sed 's|/||')
    
    log_info "Creating CDN endpoint: ${cdn_endpoint}"
    
    az cdn endpoint create \
        --name "${cdn_endpoint}" \
        --profile-name "${cdn_profile}" \
        --resource-group "${resource_group}" \
        --origin "${origin_hostname}" \
        --origin-host-header "${origin_hostname}" \
        --enable-compression true \
        --content-types-to-compress "text/html" "text/css" "application/javascript" "application/json" \
        --tags purpose=global-acceleration \
        --output none
    
    log_success "CDN resources created successfully"
}

optimize_cdn() {
    local resource_group="$1"
    local cdn_profile="$2"
    local cdn_endpoint="$3"
    
    log_info "Optimizing CDN configuration..."
    
    # Configure query string caching behavior
    az cdn endpoint update \
        --name "${cdn_endpoint}" \
        --profile-name "${cdn_profile}" \
        --resource-group "${resource_group}" \
        --query-string-caching-behavior "IgnoreQueryString" \
        --output none
    
    # Enable optimization for general web delivery
    az cdn endpoint update \
        --name "${cdn_endpoint}" \
        --profile-name "${cdn_profile}" \
        --resource-group "${resource_group}" \
        --optimization-type "GeneralWebDelivery" \
        --output none
    
    log_success "CDN optimization configured"
}

# Testing functions
test_deployment() {
    local website_url="$1"
    local cdn_url="$2"
    
    log_info "Testing deployment..."
    
    # Test storage website
    log_info "Testing direct storage website access..."
    if curl -s -o /dev/null -w "%{http_code}" "${website_url}" | grep -q "200"; then
        log_success "Storage website is accessible"
    else
        log_warning "Storage website may not be ready yet"
    fi
    
    # Test CDN (may take time to propagate)
    log_info "Testing CDN endpoint (may take 5-10 minutes to propagate)..."
    local attempts=0
    local max_attempts=5
    
    while [[ ${attempts} -lt ${max_attempts} ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "https://${cdn_url}" | grep -q "200"; then
            log_success "CDN endpoint is accessible"
            break
        else
            log_info "CDN not ready yet, attempt $((attempts + 1))/${max_attempts}..."
            sleep 30
            ((attempts++))
        fi
    done
    
    if [[ ${attempts} -eq ${max_attempts} ]]; then
        log_warning "CDN endpoint may still be propagating. It can take up to 10 minutes."
    fi
}

# Main deployment function
main() {
    log_info "Starting Azure Static Website with CDN deployment..."
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Set default values with environment variable overrides
    local resource_group="${RESOURCE_GROUP:-rg-static-website-$(openssl rand -hex 3)}"
    local location="${LOCATION:-eastus}"
    local storage_account="${STORAGE_ACCOUNT:-staticsite$(openssl rand -hex 3)}"
    local cdn_profile="${CDN_PROFILE:-cdn-profile-$(openssl rand -hex 3)}"
    local cdn_endpoint="${CDN_ENDPOINT:-website-$(openssl rand -hex 3)}"
    local content_dir="${SCRIPT_DIR}/website-content"
    
    # Check if deployment already exists
    if [[ -f "${STATE_FILE}" ]]; then
        log_warning "Previous deployment state found. Remove ${STATE_FILE} to start fresh."
        source "${STATE_FILE}"
        log_info "Using existing deployment: Resource Group = ${RESOURCE_GROUP}"
    fi
    
    # Validate prerequisites
    check_prerequisites
    
    # Validate resource availability
    validate_resource_availability "${resource_group}" "${storage_account}" "${location}"
    
    # Create resource group
    log_info "Creating resource group: ${resource_group}"
    az group create \
        --name "${resource_group}" \
        --location "${location}" \
        --tags purpose=recipe environment=demo \
        --output none
    log_success "Resource group created: ${resource_group}"
    
    # Deploy storage account
    deploy_storage_account "${resource_group}" "${storage_account}" "${location}"
    
    # Enable static website hosting
    enable_static_website "${storage_account}"
    
    # Get website URL
    local website_url
    website_url=$(az storage account show \
        --name "${storage_account}" \
        --resource-group "${resource_group}" \
        --query "primaryEndpoints.web" \
        --output tsv)
    
    log_info "Website URL: ${website_url}"
    
    # Create and upload website content
    create_website_content "${content_dir}"
    upload_website_content "${storage_account}" "${content_dir}"
    
    # Deploy CDN
    deploy_cdn "${resource_group}" "${cdn_profile}" "${cdn_endpoint}" "${website_url}"
    
    # Optimize CDN configuration
    optimize_cdn "${resource_group}" "${cdn_profile}" "${cdn_endpoint}"
    
    # Get CDN URL
    local cdn_url
    cdn_url=$(az cdn endpoint show \
        --name "${cdn_endpoint}" \
        --profile-name "${cdn_profile}" \
        --resource-group "${resource_group}" \
        --query "hostName" \
        --output tsv)
    
    log_info "CDN URL: https://${cdn_url}"
    
    # Save deployment state
    save_deployment_state "${resource_group}" "${storage_account}" "${cdn_profile}" "${cdn_endpoint}" "${location}"
    
    # Test deployment
    test_deployment "${website_url}" "${cdn_url}"
    
    # Cleanup temporary files
    rm -rf "${content_dir}"
    
    # Display summary
    echo
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: ${resource_group}"
    echo "Storage Account: ${storage_account}"
    echo "CDN Profile: ${cdn_profile}"
    echo "CDN Endpoint: ${cdn_endpoint}"
    echo "Direct Website URL: ${website_url}"
    echo "CDN Website URL: https://${cdn_url}"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Visit your website at: ${website_url}"
    echo "2. Visit your CDN-accelerated site at: https://${cdn_url}"
    echo "3. CDN propagation may take 5-10 minutes for global availability"
    echo "4. Run ./destroy.sh to clean up resources when done"
    echo
    log_info "Deployment log saved to: ${LOG_FILE}"
}

# Run main function
main "$@"