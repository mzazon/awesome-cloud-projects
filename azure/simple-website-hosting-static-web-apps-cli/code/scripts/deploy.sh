#!/bin/bash

# ==============================================================================
# Azure Static Web Apps Deployment Script
# Recipe: Simple Website Hosting with Static Web Apps and CLI
# ==============================================================================
# This script deploys an Azure Static Web App with sample website content
# following Azure best practices and security standards.
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy-config"

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_ENVIRONMENT="demo"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ==============================================================================
# Utility Functions
# ==============================================================================

# Log function with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "${LOG_FILE}"
}

# Success message
success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "${LOG_FILE}"
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "${LOG_FILE}"
}

# Error message
error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "${LOG_FILE}" >&2
}

# Fatal error and exit
fatal() {
    error "$*"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Static Web App with sample website content.

OPTIONS:
    -n, --name NAME           Static Web App name (default: auto-generated)
    -g, --resource-group RG   Resource group name (default: auto-generated)
    -l, --location LOCATION   Azure region (default: ${DEFAULT_LOCATION})
    -e, --environment ENV     Environment tag (default: ${DEFAULT_ENVIRONMENT})
    -d, --directory DIR       Website source directory (default: creates sample)
    -f, --force              Force deployment (overwrite existing)
    -v, --verbose            Enable verbose logging
    -h, --help               Show this help message

EXAMPLES:
    $0                        # Deploy with defaults
    $0 -n my-app -g my-rg     # Deploy with custom names
    $0 -d ./my-website        # Deploy existing website
    $0 --force                # Force redeploy

EOF
}

# ==============================================================================
# Prerequisite Checks
# ==============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        fatal "Azure CLI is not installed. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version (minimum 2.29.0)
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    if [[ $(printf '%s\n' "2.29.0" "$az_version" | sort -V | head -n1) != "2.29.0" ]]; then
        fatal "Azure CLI version 2.29.0+ required. Current: $az_version"
    fi
    
    # Check Node.js for SWA CLI
    if ! command_exists node; then
        fatal "Node.js is not installed. Install from: https://nodejs.org"
    fi
    
    # Check Node.js version (minimum 16)
    local node_version
    node_version=$(node --version | sed 's/v//')
    if [[ $(printf '%s\n' "16.0.0" "$node_version" | sort -V | head -n1) != "16.0.0" ]]; then
        fatal "Node.js version 16+ required. Current: $node_version"
    fi
    
    # Check npm
    if ! command_exists npm; then
        fatal "npm is not installed (should come with Node.js)"
    fi
    
    # Check OpenSSL for random generation
    if ! command_exists openssl; then
        warning "OpenSSL not found. Using date-based random suffix."
    fi
    
    success "Prerequisites check completed"
}

# Check Azure authentication
check_azure_auth() {
    info "Checking Azure authentication..."
    
    if ! az account show >/dev/null 2>&1; then
        info "Not logged into Azure. Initiating login..."
        az login || fatal "Azure login failed"
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    success "Azure authentication verified"
}

# ==============================================================================
# Configuration Management
# ==============================================================================

# Generate unique suffix
generate_suffix() {
    if command_exists openssl; then
        openssl rand -hex 3
    else
        date +%s | tail -c 7
    fi
}

# Save deployment configuration
save_config() {
    cat > "${CONFIG_FILE}" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
STATIC_WEB_APP_NAME=${STATIC_WEB_APP_NAME}
LOCATION=${LOCATION}
ENVIRONMENT=${ENVIRONMENT}
WEBSITE_DIR=${WEBSITE_DIR}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
EOF
    success "Configuration saved to ${CONFIG_FILE}"
}

# Load existing configuration
load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${CONFIG_FILE}"
        info "Loaded existing configuration from ${CONFIG_FILE}"
        return 0
    fi
    return 1
}

# ==============================================================================
# Website Content Management
# ==============================================================================

# Create sample website content
create_sample_website() {
    local website_dir="$1"
    
    info "Creating sample website content in: $website_dir"
    mkdir -p "$website_dir"
    cd "$website_dir"
    
    # Create index.html
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>My Azure Static Web App</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <h1>Welcome to Azure Static Web Apps</h1>
        <nav>
            <a href="#about">About</a>
            <a href="#features">Features</a>
            <a href="#contact">Contact</a>
        </nav>
    </header>
    
    <main>
        <section id="about">
            <h2>About This Demo</h2>
            <p>This is a simple static website hosted on Azure Static Web Apps with global CDN distribution and automatic HTTPS.</p>
        </section>
        
        <section id="features">
            <h2>Key Features</h2>
            <ul>
                <li>Global content delivery network</li>
                <li>Automatic SSL certificates</li>
                <li>Custom domain support</li>
                <li>Built-in authentication</li>
                <li>Staging environments</li>
            </ul>
        </section>
        
        <section id="contact">
            <h2>Get Started</h2>
            <p>Deploy your own static website with Azure CLI in minutes!</p>
            <button onclick="showAlert()">Learn More</button>
        </section>
    </main>
    
    <footer>
        <p>&copy; 2025 Azure Static Web Apps Demo</p>
    </footer>
    
    <script src="script.js"></script>
</body>
</html>
EOF

    # Create styles.css
    cat > styles.css << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    line-height: 1.6;
    color: #333;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
}

header {
    background: rgba(255, 255, 255, 0.95);
    padding: 1rem 2rem;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    position: sticky;
    top: 0;
    z-index: 100;
}

header h1 {
    color: #0078d4;
    margin-bottom: 0.5rem;
}

nav a {
    color: #666;
    text-decoration: none;
    margin-right: 2rem;
    font-weight: 500;
    transition: color 0.3s ease;
}

nav a:hover {
    color: #0078d4;
}

main {
    max-width: 1200px;
    margin: 2rem auto;
    padding: 0 2rem;
}

section {
    background: white;
    margin: 2rem 0;
    padding: 2rem;
    border-radius: 10px;
    box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    animation: fadeInUp 0.6s ease-out;
}

@keyframes fadeInUp {
    from {
        opacity: 0;
        transform: translateY(30px);
    }
    to {
        opacity: 1;
        transform: translateY(0);
    }
}

h2 {
    color: #0078d4;
    margin-bottom: 1rem;
    border-bottom: 2px solid #e1e1e1;
    padding-bottom: 0.5rem;
}

ul {
    list-style: none;
    padding-left: 0;
}

li {
    padding: 0.5rem 0;
    border-left: 3px solid #0078d4;
    padding-left: 1rem;
    margin: 0.5rem 0;
    background: #f8f9fa;
}

button {
    background: linear-gradient(45deg, #0078d4, #00bcf2);
    color: white;
    border: none;
    padding: 12px 24px;
    border-radius: 25px;
    cursor: pointer;
    font-size: 1rem;
    font-weight: 600;
    transition: transform 0.2s ease, box-shadow 0.2s ease;
}

button:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(0,120,212,0.3);
}

footer {
    text-align: center;
    padding: 2rem;
    color: white;
    background: rgba(0,0,0,0.2);
    margin-top: 3rem;
}

@media (max-width: 768px) {
    header {
        padding: 1rem;
    }
    
    nav a {
        display: block;
        margin: 0.5rem 0;
    }
    
    main {
        padding: 0 1rem;
    }
    
    section {
        padding: 1.5rem;
    }
}
EOF

    # Create script.js
    cat > script.js << 'EOF'
// Simple interactive functionality for the demo website
function showAlert() {
    alert('🚀 Ready to deploy your own Azure Static Web App? \n\nKey benefits:\n• Global CDN distribution\n• Automatic HTTPS\n• Zero server management\n• Built-in CI/CD\n• Custom domains\n• Authentication ready');
}

// Add smooth scrolling for navigation links
document.addEventListener('DOMContentLoaded', function() {
    // Smooth scrolling for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });
    
    // Add loading animation
    document.body.style.opacity = '0';
    document.body.style.transition = 'opacity 0.5s ease-in';
    
    window.addEventListener('load', function() {
        document.body.style.opacity = '1';
    });
    
    // Console message for developers
    console.log('🌐 Azure Static Web Apps Demo\n📍 Deployed globally with Azure CDN\n🔒 Secured with automatic HTTPS\n⚡ Zero infrastructure management required');
});

// Simple performance monitoring
if ('performance' in window && 'measure' in window.performance) {
    window.addEventListener('load', function() {
        setTimeout(function() {
            const loadTime = Math.round(window.performance.timing.loadEventEnd - window.performance.timing.navigationStart);
            console.log(`⚡ Page loaded in ${loadTime}ms via Azure Global CDN`);
        }, 0);
    });
}
EOF

    # Create Static Web Apps configuration
    cat > staticwebapp.config.json << 'EOF'
{
  "navigationFallback": {
    "rewrite": "/index.html"
  },
  "routes": [
    {
      "route": "/",
      "serve": "/index.html",
      "statusCode": 200
    },
    {
      "route": "/*.{css,js,png,jpg,jpeg,gif,svg,ico}",
      "headers": {
        "cache-control": "public, max-age=31536000, immutable"
      }
    }
  ],
  "responseOverrides": {
    "404": {
      "rewrite": "/index.html"
    }
  },
  "globalHeaders": {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains"
  }
}
EOF

    success "Sample website content created"
}

# ==============================================================================
# Static Web Apps CLI Management
# ==============================================================================

# Install/update Static Web Apps CLI
setup_swa_cli() {
    info "Setting up Azure Static Web Apps CLI..."
    
    # Check if SWA CLI is installed
    if command_exists swa; then
        local current_version
        current_version=$(swa --version 2>/dev/null | head -n1 || echo "0.0.0")
        info "Current SWA CLI version: $current_version"
        
        # Check if version is 2.0.2 or higher
        if [[ $(printf '%s\n' "2.0.2" "$current_version" | sort -V | head -n1) != "2.0.2" ]]; then
            warning "SWA CLI version 2.0.2+ recommended for security. Upgrading..."
            npm install -g @azure/static-web-apps-cli@latest
        else
            success "SWA CLI version meets requirements"
        fi
    else
        info "Installing Azure Static Web Apps CLI..."
        npm install -g @azure/static-web-apps-cli@latest
    fi
    
    # Verify installation
    if command_exists swa; then
        local final_version
        final_version=$(swa --version 2>/dev/null | head -n1)
        success "SWA CLI ready - version: $final_version"
    else
        fatal "Failed to install Static Web Apps CLI"
    fi
}

# ==============================================================================
# Azure Resource Management
# ==============================================================================

# Create resource group
create_resource_group() {
    info "Creating resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        if [[ "$FORCE_DEPLOYMENT" == "true" ]]; then
            warning "Resource group exists, continuing with force flag"
        else
            warning "Resource group '$RESOURCE_GROUP' already exists"
            info "Use --force to redeploy or choose a different name"
            return 0
        fi
    else
        # Create resource group
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment="$ENVIRONMENT" \
            || fatal "Failed to create resource group"
    fi
    
    success "Resource group ready: $RESOURCE_GROUP"
}

# Create Static Web App
create_static_web_app() {
    info "Creating Static Web App: $STATIC_WEB_APP_NAME"
    
    # Check if Static Web App exists
    if az staticwebapp show --name "$STATIC_WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        if [[ "$FORCE_DEPLOYMENT" == "true" ]]; then
            warning "Static Web App exists, will update with new content"
        else
            warning "Static Web App '$STATIC_WEB_APP_NAME' already exists"
            info "Use --force to redeploy or choose a different name"
            return 0
        fi
    else
        # Create Static Web App
        az staticwebapp create \
            --name "$STATIC_WEB_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags environment="$ENVIRONMENT" purpose=recipe \
            || fatal "Failed to create Static Web App"
    fi
    
    # Get the default hostname
    STATIC_WEB_APP_URL=$(az staticwebapp show \
        --name "$STATIC_WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "defaultHostname" --output tsv)
    
    success "Static Web App ready: $STATIC_WEB_APP_NAME"
    info "Default URL: https://$STATIC_WEB_APP_URL"
}

# Deploy website content
deploy_content() {
    info "Deploying website content from: $WEBSITE_DIR"
    
    cd "$WEBSITE_DIR"
    
    # Authenticate and deploy using SWA CLI
    info "Authenticating with Azure Static Web Apps..."
    swa login \
        --resource-group "$RESOURCE_GROUP" \
        --app-name "$STATIC_WEB_APP_NAME" \
        || fatal "Failed to authenticate with SWA CLI"
    
    info "Deploying content to production environment..."
    swa deploy . \
        --env production \
        --resource-group "$RESOURCE_GROUP" \
        --app-name "$STATIC_WEB_APP_NAME" \
        || fatal "Failed to deploy content"
    
    success "Website content deployed successfully"
}

# ==============================================================================
# Validation and Testing
# ==============================================================================

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Wait for deployment to be ready
    info "Waiting for deployment to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s "https://$STATIC_WEB_APP_URL" >/dev/null 2>&1; then
            break
        fi
        info "Attempt $attempt/$max_attempts - waiting for site to be ready..."
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        warning "Site not responding after $max_attempts attempts"
        return 1
    fi
    
    # Test HTTP response and security headers
    info "Testing HTTP response and security headers..."
    local http_response
    http_response=$(curl -sI "https://$STATIC_WEB_APP_URL" | head -n1)
    
    if [[ $http_response == *"200"* ]]; then
        success "HTTP response: $http_response"
    else
        warning "Unexpected HTTP response: $http_response"
    fi
    
    # Check security headers
    local security_headers
    security_headers=$(curl -sI "https://$STATIC_WEB_APP_URL" | grep -E "(X-|Strict-Transport)" || true)
    
    if [[ -n "$security_headers" ]]; then
        success "Security headers configured"
        [[ "$VERBOSE" == "true" ]] && echo "$security_headers"
    else
        warning "Security headers not found"
    fi
    
    # Test SSL certificate
    info "Verifying SSL certificate..."
    if echo | openssl s_client -servername "$STATIC_WEB_APP_URL" -connect "$STATIC_WEB_APP_URL:443" >/dev/null 2>&1; then
        success "SSL certificate verification completed"
    else
        warning "SSL certificate verification failed"
    fi
    
    success "Deployment validation completed"
}

# ==============================================================================
# Main Deployment Function
# ==============================================================================

# Main deployment process
deploy() {
    log "Starting Azure Static Web App deployment"
    log "Deployment started at: $(date)"
    
    # Check prerequisites
    check_prerequisites
    check_azure_auth
    
    # Setup SWA CLI
    setup_swa_cli
    
    # Configure deployment if not forced
    if [[ "$FORCE_DEPLOYMENT" != "true" ]] && load_config; then
        info "Using existing configuration"
        info "Static Web App: $STATIC_WEB_APP_NAME"
        info "Resource Group: $RESOURCE_GROUP"
        info "Website Directory: $WEBSITE_DIR"
        
        read -p "Continue with existing configuration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Create website content if needed
    if [[ ! -d "$WEBSITE_DIR" ]] || [[ ! -f "$WEBSITE_DIR/index.html" ]]; then
        create_sample_website "$WEBSITE_DIR"
    else
        info "Using existing website content in: $WEBSITE_DIR"
    fi
    
    # Deploy Azure resources
    create_resource_group
    create_static_web_app
    
    # Deploy content
    deploy_content
    
    # Save configuration
    save_config
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    log "Deployment completed successfully!"
    echo
    success "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group:    $RESOURCE_GROUP"
    echo "Static Web App:    $STATIC_WEB_APP_NAME"
    echo "Location:          $LOCATION"
    echo "Website URL:       https://$STATIC_WEB_APP_URL"
    echo "Website Directory: $WEBSITE_DIR"
    echo "Configuration:     $CONFIG_FILE"
    echo "Log File:          $LOG_FILE"
    echo
    info "Access your website at: https://$STATIC_WEB_APP_URL"
    info "To clean up resources, run: ./destroy.sh"
}

# ==============================================================================
# Script Entry Point
# ==============================================================================

# Parse command line arguments
parse_arguments() {
    FORCE_DEPLOYMENT="false"
    VERBOSE="false"
    LOCATION="$DEFAULT_LOCATION"
    ENVIRONMENT="$DEFAULT_ENVIRONMENT"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                STATIC_WEB_APP_NAME="$2"
                shift 2
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -d|--directory)
                WEBSITE_DIR="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DEPLOYMENT="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set defaults if not provided
    local suffix
    suffix=$(generate_suffix)
    RESOURCE_GROUP="${RESOURCE_GROUP:-rg-staticweb-${suffix}}"
    STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-swa-demo-${suffix}}"
    WEBSITE_DIR="${WEBSITE_DIR:-${PROJECT_DIR}/static-website-demo}"
}

# Main execution
main() {
    # Initialize log file
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Display banner
    echo "=================================================="
    echo "Azure Static Web Apps Deployment Script"
    echo "=================================================="
    echo
    
    # Run deployment
    deploy
}

# Execute main function with all arguments
main "$@"