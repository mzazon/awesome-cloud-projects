#!/bin/bash

# =============================================================================
# Azure Secure Web Application Deployment Script
# =============================================================================
# This script deploys Azure Static Web Apps with Azure Front Door and WAF
# for securing global web applications with enterprise-grade protection.
#
# Prerequisites:
# - Azure CLI v2.53.0 or later
# - Appropriate Azure permissions (Owner/Contributor)
# - Git installed (for Static Web App deployment)
#
# Usage:
#   ./deploy.sh [--dry-run] [--resource-group-suffix SUFFIX]
#
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
CUSTOM_SUFFIX=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Logging and Output Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_info "Partial resources may have been created. Run destroy.sh to clean up."
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Helper Functions
# =============================================================================

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Static Web Apps with Front Door and WAF protection.

OPTIONS:
    --dry-run                    Show what would be deployed without making changes
    --resource-group-suffix      Custom suffix for resource group name
    --help                       Show this help message

EXAMPLES:
    $0                          # Deploy with auto-generated suffix
    $0 --dry-run                # Preview deployment without changes
    $0 --resource-group-suffix mycompany  # Use custom suffix

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.53.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &>/dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Git is installed
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed. Please install Git for Static Web App deployment."
        exit 1
    fi
    
    # Get subscription info
    local subscription_id subscription_name
    subscription_id=$(az account show --query id -o tsv)
    subscription_name=$(az account show --query name -o tsv)
    log_info "Using Azure subscription: ${subscription_name} (${subscription_id})"
    
    log_success "Prerequisites check completed"
}

generate_random_suffix() {
    if [[ -n "${CUSTOM_SUFFIX}" ]]; then
        echo "${CUSTOM_SUFFIX}"
    else
        openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)"
    fi
}

wait_for_deployment() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be ready..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if az resource show --name "${resource_name}" --resource-group "${resource_group}" --resource-type "${resource_type}" &>/dev/null; then
            log_success "${resource_type} '${resource_name}' is ready"
            return 0
        fi
        
        log_info "Attempt ${attempt}/${max_attempts}: Waiting for ${resource_type} to be ready..."
        sleep 10
        ((attempt++))
    done
    
    log_error "Timeout waiting for ${resource_type} '${resource_name}' to be ready"
    return 1
}

# =============================================================================
# Deployment Functions
# =============================================================================

set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Generate unique suffix for globally unique names
    RANDOM_SUFFIX=$(generate_random_suffix)
    
    # Core configuration
    export RESOURCE_GROUP="rg-secure-webapp-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Service names
    export SWA_NAME="swa-secure-${RANDOM_SUFFIX}"
    export AFD_NAME="afd-secure-${RANDOM_SUFFIX}"
    export WAF_POLICY_NAME="wafpolicy${RANDOM_SUFFIX}"
    export ENDPOINT_NAME="endpoint-${RANDOM_SUFFIX}"
    
    log_info "Configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Static Web App: ${SWA_NAME}"
    log_info "  Front Door: ${AFD_NAME}"
    log_info "  WAF Policy: ${WAF_POLICY_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE: No resources will be created"
    fi
}

create_resource_group() {
    log_info "Creating resource group..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=security-demo environment=production \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

create_static_web_app() {
    log_info "Creating Azure Static Web App..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Static Web App: ${SWA_NAME}"
        return 0
    fi
    
    az staticwebapp create \
        --name "${SWA_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard \
        --source https://github.com/staticwebdev/vanilla-basic \
        --branch main \
        --app-location "/" \
        --output-location "public" \
        --tags security=enhanced deployment=automated \
        --output none
    
    # Wait for Static Web App to be ready
    wait_for_deployment "Microsoft.Web/staticSites" "${SWA_NAME}" "${RESOURCE_GROUP}"
    
    # Get hostname
    export SWA_HOSTNAME=$(az staticwebapp show \
        --name "${SWA_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostname \
        --output tsv)
    
    log_success "Static Web App created: https://${SWA_HOSTNAME}"
}

create_waf_policy() {
    log_info "Creating WAF policy with security rules..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create WAF policy: ${WAF_POLICY_NAME}"
        return 0
    fi
    
    # Create WAF policy
    az network front-door waf-policy create \
        --name "${WAF_POLICY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --sku Standard_AzureFrontDoor \
        --mode Prevention \
        --tags purpose=security compliance=required \
        --output none
    
    # Enable Microsoft Default Rule Set (DRS) for OWASP protection
    az network front-door waf-policy managed-rules add \
        --policy-name "${WAF_POLICY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type Microsoft_DefaultRuleSet \
        --version 2.1 \
        --action Block \
        --output none
    
    # Enable Bot Manager Rule Set
    az network front-door waf-policy managed-rules add \
        --policy-name "${WAF_POLICY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type Microsoft_BotManagerRuleSet \
        --version 1.0 \
        --action Block \
        --output none
    
    log_success "WAF policy created with OWASP and Bot protection rules"
}

create_custom_security_rules() {
    log_info "Configuring custom security rules..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create custom security rules"
        return 0
    fi
    
    # Add rate limiting rule (100 requests per minute per IP)
    az network front-door waf-policy custom-rule create \
        --name RateLimitRule \
        --policy-name "${WAF_POLICY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --rule-type RateLimiting \
        --rate-limit-threshold 100 \
        --rate-limit-duration-in-minutes 1 \
        --priority 1 \
        --action Block \
        --output none
    
    # Add geo-filtering rule (allow specific regions)
    az network front-door waf-policy custom-rule create \
        --name GeoFilterRule \
        --policy-name "${WAF_POLICY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --rule-type MatchRule \
        --priority 2 \
        --action Allow \
        --match-condition RemoteAddr GeoMatch "US" "CA" "GB" "DE" \
        --negate-condition false \
        --output none
    
    log_success "Custom security rules configured for rate limiting and geo-filtering"
}

create_front_door() {
    log_info "Creating Azure Front Door with WAF integration..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Front Door: ${AFD_NAME}"
        return 0
    fi
    
    # Create Front Door profile
    az afd profile create \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --sku Standard_AzureFrontDoor \
        --tags security=waf-enabled performance=optimized \
        --output none
    
    # Create Front Door endpoint
    az afd endpoint create \
        --endpoint-name "${ENDPOINT_NAME}" \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --enabled-state Enabled \
        --output none
    
    # Get endpoint hostname
    export AFD_HOSTNAME=$(az afd endpoint show \
        --endpoint-name "${ENDPOINT_NAME}" \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query hostName \
        --output tsv)
    
    log_success "Front Door created: https://${AFD_HOSTNAME}"
}

configure_origin_group() {
    log_info "Configuring origin group and origin..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure origin group for Static Web App"
        return 0
    fi
    
    # Create origin group
    az afd origin-group create \
        --origin-group-name "og-staticwebapp" \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --probe-request-type GET \
        --probe-protocol Https \
        --probe-interval-in-seconds 30 \
        --probe-path "/" \
        --sample-size 4 \
        --successful-samples-required 3 \
        --additional-latency-in-milliseconds 50 \
        --output none
    
    # Add Static Web App as origin
    az afd origin create \
        --origin-name "origin-swa" \
        --origin-group-name "og-staticwebapp" \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --host-name "${SWA_HOSTNAME}" \
        --origin-host-header "${SWA_HOSTNAME}" \
        --priority 1 \
        --weight 1000 \
        --enabled-state Enabled \
        --http-port 80 \
        --https-port 443 \
        --output none
    
    log_success "Origin group configured with health monitoring"
}

create_routes_and_apply_waf() {
    log_info "Creating routes and applying WAF policy..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create routes with WAF policy"
        return 0
    fi
    
    # Create route for all traffic
    az afd route create \
        --route-name "route-secure" \
        --endpoint-name "${ENDPOINT_NAME}" \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --origin-group "og-staticwebapp" \
        --supported-protocols Http Https \
        --patterns-to-match "/*" \
        --forwarding-protocol HttpsOnly \
        --link-to-default-domain Enabled \
        --https-redirect Enabled \
        --output none
    
    # Get WAF policy ID
    local waf_policy_id
    waf_policy_id=$(az network front-door waf-policy show \
        --name "${WAF_POLICY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id \
        --output tsv)
    
    # Associate WAF policy with endpoint
    az afd security-policy create \
        --security-policy-name "security-policy-waf" \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --domains "${ENDPOINT_NAME}" \
        --waf-policy-id "${waf_policy_id}" \
        --output none
    
    log_success "Routes configured with WAF policy applied"
}

configure_static_web_app_integration() {
    log_info "Configuring Static Web App for Front Door integration..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Static Web App configuration"
        return 0
    fi
    
    # Get Front Door ID
    local front_door_id
    front_door_id=$(az afd profile show \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query frontDoorId \
        --output tsv)
    
    # Create configuration file
    cat > "${SCRIPT_DIR}/staticwebapp.config.json" << EOF
{
  "networking": {
    "allowedIpRanges": ["AzureFrontDoor.Backend"]
  },
  "forwardingGateway": {
    "requiredHeaders": {
      "X-Azure-FDID": "${front_door_id}"
    },
    "allowedForwardedHosts": [
      "${AFD_HOSTNAME}"
    ]
  },
  "routes": [
    {
      "route": "/.auth/*",
      "headers": {
        "Cache-Control": "no-store"
      }
    }
  ]
}
EOF
    
    log_success "Static Web App configuration created at ${SCRIPT_DIR}/staticwebapp.config.json"
    log_info "Deploy this configuration file to your Static Web App repository"
}

configure_caching_optimization() {
    log_info "Enabling caching and compression optimizations..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure caching and compression"
        return 0
    fi
    
    # Create cache rule for static assets
    az afd rule create \
        --rule-name "rule-cache-static" \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --endpoint-name "${ENDPOINT_NAME}" \
        --rule-set-name "ruleset-caching" \
        --order 1 \
        --match-variable RequestUri \
        --operator Contains \
        --match-values ".css" ".js" ".jpg" ".png" ".gif" ".svg" ".woff" \
        --action-name CacheExpiration \
        --cache-behavior Override \
        --cache-duration "7.00:00:00" \
        --output none
    
    # Enable compression for text content
    az afd rule create \
        --rule-name "rule-compression" \
        --profile-name "${AFD_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --endpoint-name "${ENDPOINT_NAME}" \
        --rule-set-name "ruleset-compression" \
        --order 1 \
        --match-variable RequestHeader \
        --selector "Accept-Encoding" \
        --operator Contains \
        --match-values "gzip" \
        --action-name Compression \
        --enable-compression true \
        --output none
    
    log_success "Caching and compression optimizations configured"
}

print_deployment_summary() {
    log_info "Deployment Summary:"
    log_info "===================="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Static Web App: https://${SWA_HOSTNAME}"
    log_info "Front Door Endpoint: https://${AFD_HOSTNAME}"
    log_info "WAF Policy: ${WAF_POLICY_NAME}"
    log_info ""
    log_info "Configuration Files:"
    log_info "  Static Web App Config: ${SCRIPT_DIR}/staticwebapp.config.json"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Deploy the staticwebapp.config.json to your repository"
    log_info "2. Test the Front Door endpoint: https://${AFD_HOSTNAME}"
    log_info "3. Verify WAF protection is working"
    log_info "4. Configure custom domain if needed"
    log_info ""
    log_info "Cleanup: Run ./destroy.sh to remove all resources"
}

# =============================================================================
# Main Deployment Flow
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --resource-group-suffix)
                CUSTOM_SUFFIX="$2"
                shift 2
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    log_info "Starting Azure Secure Web Application deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    # Deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_static_web_app
    create_waf_policy
    create_custom_security_rules
    create_front_door
    configure_origin_group
    create_routes_and_apply_waf
    configure_static_web_app_integration
    configure_caching_optimization
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        print_deployment_summary
        log_success "Deployment completed successfully!"
        log_info "Check the validation section in the recipe for testing instructions"
    else
        log_info "Dry run completed. No resources were created."
    fi
}

# Run main function
main "$@"