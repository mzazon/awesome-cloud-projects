#!/bin/bash

# Deploy script for Progressive Web Apps with Static Hosting and CDN
# This script automates the deployment of a Progressive Web App using Azure Static Web Apps,
# Azure CDN, and Azure Application Insights following the recipe implementation.

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Git is installed
    if ! command_exists git; then
        error "Git is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command_exists node; then
        error "Node.js is not installed. Please install it first."
        exit 1
    fi
    
    # Check if OpenSSL is installed
    if ! command_exists openssl; then
        error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "All prerequisites met."
}

# Set default values
set_defaults() {
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables with defaults
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-pwa-demo-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    export SWA_NAME="${SWA_NAME:-swa-pwa-${RANDOM_SUFFIX}}"
    export CDN_PROFILE="${CDN_PROFILE:-cdn-pwa-${RANDOM_SUFFIX}}"
    export AI_NAME="${AI_NAME:-ai-pwa-${RANDOM_SUFFIX}}"
    export GITHUB_USERNAME="${GITHUB_USERNAME:-}"
    export REPO_NAME="${REPO_NAME:-azure-pwa-demo}"
    export DRY_RUN="${DRY_RUN:-false}"
}

# Display configuration
display_configuration() {
    log "Deployment Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Subscription ID: $SUBSCRIPTION_ID"
    echo "  Static Web App Name: $SWA_NAME"
    echo "  CDN Profile Name: $CDN_PROFILE"
    echo "  Application Insights Name: $AI_NAME"
    echo "  GitHub Username: $GITHUB_USERNAME"
    echo "  Repository Name: $REPO_NAME"
    echo "  Dry Run: $DRY_RUN"
    echo ""
}

# Prompt for GitHub username if not provided
prompt_github_info() {
    if [[ -z "$GITHUB_USERNAME" ]]; then
        read -p "Enter your GitHub username: " GITHUB_USERNAME
        export GITHUB_USERNAME
    fi
    
    if [[ -z "$GITHUB_USERNAME" ]]; then
        error "GitHub username is required for Static Web Apps deployment."
        exit 1
    fi
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create resource group: $RESOURCE_GROUP"
        return
    fi
    
    # Check if resource group already exists
    if az group exists --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "Resource group '$RESOURCE_GROUP' already exists. Skipping creation."
        return
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=pwa-demo environment=production \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "✅ Resource group created: $RESOURCE_GROUP"
    else
        error "Failed to create resource group"
        exit 1
    fi
}

# Create local PWA project structure
create_pwa_project() {
    log "Creating local PWA project structure..."
    
    local project_dir="pwa-demo"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create PWA project in: $project_dir"
        return
    fi
    
    # Create project directory if it doesn't exist
    if [[ ! -d "$project_dir" ]]; then
        mkdir -p "$project_dir"
        cd "$project_dir"
        mkdir -p src/{css,js,images,api/hello}
        
        # Create main HTML file
        cat > src/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure PWA Demo</title>
    <link rel="manifest" href="/manifest.json">
    <link rel="stylesheet" href="/css/styles.css">
    <meta name="theme-color" content="#0078d4">
    <link rel="apple-touch-icon" href="/images/icon-192.png">
    <script src="/config.js"></script>
</head>
<body>
    <header>
        <h1>Azure Progressive Web App</h1>
        <button id="install-button" style="display: none;">Install App</button>
    </header>
    <main>
        <section id="content">
            <h2>Welcome to Azure Static Web Apps</h2>
            <p>This PWA demonstrates offline capabilities, global CDN distribution, and comprehensive monitoring.</p>
            <button id="api-test">Test API</button>
            <div id="api-result"></div>
            <div id="performance-metrics">
                <h3>Performance Insights</h3>
                <p>Real-time monitoring via Azure Application Insights</p>
            </div>
        </section>
    </main>
    <script type="module" src="/js/app-insights.js"></script>
    <script src="/js/app.js"></script>
</body>
</html>
EOF

        # Create web app manifest
        cat > src/manifest.json << 'EOF'
{
    "name": "Azure PWA Demo",
    "short_name": "AzurePWA",
    "description": "Progressive Web App built with Azure Static Web Apps",
    "start_url": "/",
    "display": "standalone",
    "theme_color": "#0078d4",
    "background_color": "#ffffff",
    "orientation": "portrait-primary",
    "icons": [
        {
            "src": "/images/icon-192.png",
            "sizes": "192x192",
            "type": "image/png",
            "purpose": "maskable any"
        },
        {
            "src": "/images/icon-512.png",
            "sizes": "512x512",
            "type": "image/png",
            "purpose": "maskable any"
        }
    ],
    "categories": ["productivity", "utilities"]
}
EOF

        # Create service worker
        cat > src/sw.js << 'EOF'
const CACHE_NAME = 'azure-pwa-v1';
const STATIC_CACHE = 'static-cache-v1';
const API_CACHE = 'api-cache-v1';

const STATIC_ASSETS = [
    '/',
    '/index.html',
    '/css/styles.css',
    '/js/app.js',
    '/manifest.json',
    '/images/icon-192.png',
    '/images/icon-512.png'
];

// Install event - cache static assets
self.addEventListener('install', event => {
    console.log('Service Worker installing');
    event.waitUntil(
        caches.open(STATIC_CACHE)
            .then(cache => cache.addAll(STATIC_ASSETS))
            .then(() => self.skipWaiting())
    );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
    console.log('Service Worker activating');
    event.waitUntil(
        caches.keys().then(keys => {
            return Promise.all(
                keys.map(key => {
                    if (key !== STATIC_CACHE && key !== API_CACHE) {
                        return caches.delete(key);
                    }
                })
            );
        }).then(() => self.clients.claim())
    );
});

// Fetch event - serve from cache or network
self.addEventListener('fetch', event => {
    const url = new URL(event.request.url);
    
    if (url.pathname.startsWith('/api/')) {
        // Network first for API calls
        event.respondWith(
            fetch(event.request)
                .then(response => {
                    const responseClone = response.clone();
                    caches.open(API_CACHE)
                        .then(cache => cache.put(event.request, responseClone));
                    return response;
                })
                .catch(() => caches.match(event.request))
        );
    } else {
        // Cache first for static assets
        event.respondWith(
            caches.match(event.request)
                .then(response => response || fetch(event.request))
        );
    }
});
EOF

        # Create main application JavaScript
        cat > src/js/app.js << 'EOF'
class AzurePWA {
    constructor() {
        this.initServiceWorker();
        this.initInstallPrompt();
        this.initAPITest();
        this.initApplicationInsights();
    }

    async initServiceWorker() {
        if ('serviceWorker' in navigator) {
            try {
                const registration = await navigator.serviceWorker.register('/sw.js');
                console.log('SW registered:', registration);
            } catch (error) {
                console.log('SW registration failed:', error);
            }
        }
    }

    initInstallPrompt() {
        let deferredPrompt;
        const installButton = document.getElementById('install-button');

        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            installButton.style.display = 'block';
        });

        installButton.addEventListener('click', async () => {
            if (deferredPrompt) {
                deferredPrompt.prompt();
                const { outcome } = await deferredPrompt.userChoice;
                console.log('Install prompt outcome:', outcome);
                deferredPrompt = null;
                installButton.style.display = 'none';
            }
        });
    }

    initAPITest() {
        const button = document.getElementById('api-test');
        const result = document.getElementById('api-result');

        button.addEventListener('click', async () => {
            try {
                const response = await fetch('/api/hello');
                const data = await response.json();
                result.innerHTML = `<p>API Response: ${data.message}</p>`;
            } catch (error) {
                result.innerHTML = `<p>Error: ${error.message}</p>`;
            }
        });
    }

    initApplicationInsights() {
        // Application Insights will be configured after resource creation
        if (window.appInsights) {
            appInsights.trackPageView();
        }
    }
}

// Initialize app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    new AzurePWA();
});
EOF

        # Create CSS styles
        cat > src/css/styles.css << 'EOF'
:root {
    --azure-blue: #0078d4;
    --azure-light: #e6f2ff;
    --text-dark: #323130;
    --background: #ffffff;
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    line-height: 1.6;
    color: var(--text-dark);
    background: var(--background);
}

header {
    background: var(--azure-blue);
    color: white;
    padding: 1rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

h1 {
    font-size: 1.5rem;
}

#install-button {
    background: white;
    color: var(--azure-blue);
    border: none;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    cursor: pointer;
    font-weight: bold;
}

main {
    padding: 2rem;
    max-width: 800px;
    margin: 0 auto;
}

#content {
    text-align: center;
}

#api-test {
    background: var(--azure-blue);
    color: white;
    border: none;
    padding: 1rem 2rem;
    border-radius: 4px;
    cursor: pointer;
    font-size: 1rem;
    margin: 1rem 0;
}

#api-result {
    margin-top: 1rem;
    padding: 1rem;
    background: var(--azure-light);
    border-radius: 4px;
    min-height: 60px;
}

@media (max-width: 768px) {
    header {
        flex-direction: column;
        gap: 1rem;
    }
    
    main {
        padding: 1rem;
    }
}

/* PWA specific styles */
@media (display-mode: standalone) {
    body {
        user-select: none;
    }
    
    header {
        padding-top: env(safe-area-inset-top);
    }
}
EOF

        # Create placeholder icons
        mkdir -p src/images
        cat > src/images/icon.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
    <rect width="512" height="512" fill="#0078d4"/>
    <text x="256" y="280" font-family="Arial" font-size="200" 
          fill="white" text-anchor="middle">PWA</text>
</svg>
EOF

        # Create API function
        cat > src/api/hello/function.json << 'EOF'
{
    "bindings": [
        {
            "authLevel": "anonymous",
            "type": "httpTrigger",
            "direction": "in",
            "name": "req",
            "methods": ["get", "post"]
        },
        {
            "type": "http",
            "direction": "out",
            "name": "res"
        }
    ]
}
EOF

        cat > src/api/hello/index.js << 'EOF'
module.exports = async function (context, req) {
    context.log('HTTP trigger function processed a request.');

    const name = req.query.name || req.body?.name || 'Azure PWA';
    const timestamp = new Date().toISOString();
    
    const responseMessage = {
        message: `Hello from ${name}! Server time: ${timestamp}`,
        version: '1.0.0',
        features: [
            'Progressive Web App',
            'Offline Capability',
            'Push Notifications',
            'Global CDN Distribution'
        ]
    };

    context.res = {
        status: 200,
        headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache'
        },
        body: responseMessage
    };
};
EOF

        cat > src/api/package.json << 'EOF'
{
    "name": "azure-pwa-api",
    "version": "1.0.0",
    "description": "Serverless API for Azure PWA",
    "main": "index.js",
    "dependencies": {},
    "engines": {
        "node": ">=18.0.0"
    }
}
EOF

        cat > src/package.json << 'EOF'
{
    "name": "azure-pwa-demo",
    "version": "1.0.0",
    "description": "Progressive Web App with Azure Static Web Apps and CDN",
    "main": "index.html",
    "scripts": {
        "build": "echo 'No build process needed for this demo'",
        "start": "echo 'Use Azure Static Web Apps for hosting'"
    },
    "dependencies": {
        "@microsoft/applicationinsights-web": "^3.0.0"
    },
    "devDependencies": {},
    "keywords": ["pwa", "azure", "static-web-apps", "cdn"],
    "author": "Azure PWA Demo",
    "license": "MIT"
}
EOF

        # Initialize Git repository
        git init
        git add .
        git commit -m "Initial PWA setup with Azure Static Web Apps"
        
        log "✅ PWA project structure created"
        cd ..
    else
        warning "PWA project directory already exists. Skipping creation."
    fi
}

# Create Application Insights
create_application_insights() {
    log "Creating Application Insights..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create Application Insights: $AI_NAME"
        return
    fi
    
    # Check if Application Insights already exists
    if az monitor app-insights component show --app "$AI_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "Application Insights '$AI_NAME' already exists. Skipping creation."
    else
        az monitor app-insights component create \
            --app "$AI_NAME" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --application-type web \
            --kind web \
            --output none
        
        if [[ $? -eq 0 ]]; then
            log "✅ Application Insights created: $AI_NAME"
        else
            error "Failed to create Application Insights"
            exit 1
        fi
    fi
    
    # Get Application Insights instrumentation key and connection string
    AI_INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --app "$AI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    
    AI_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "$AI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    export AI_INSTRUMENTATION_KEY
    export AI_CONNECTION_STRING
    
    info "Application Insights Instrumentation Key: $AI_INSTRUMENTATION_KEY"
}

# Create Static Web App
create_static_web_app() {
    log "Creating Azure Static Web App..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create Static Web App: $SWA_NAME"
        return
    fi
    
    # Check if Static Web App already exists
    if az staticwebapp show --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "Static Web App '$SWA_NAME' already exists. Skipping creation."
    else
        # Create Static Web App without GitHub integration first
        az staticwebapp create \
            --name "$SWA_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output none
        
        if [[ $? -eq 0 ]]; then
            log "✅ Static Web App created: $SWA_NAME"
        else
            error "Failed to create Static Web App"
            exit 1
        fi
    fi
    
    # Get the Static Web App URL
    SWA_URL=$(az staticwebapp show \
        --name "$SWA_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query defaultHostname --output tsv)
    
    export SWA_URL
    
    info "Static Web App URL: https://$SWA_URL"
}

# Create CDN Profile and Endpoint
create_cdn() {
    log "Creating Azure CDN..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create CDN Profile: $CDN_PROFILE"
        return
    fi
    
    # Check if CDN profile already exists
    if az cdn profile show --name "$CDN_PROFILE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "CDN Profile '$CDN_PROFILE' already exists. Skipping creation."
    else
        # Create CDN profile
        az cdn profile create \
            --name "$CDN_PROFILE" \
            --resource-group "$RESOURCE_GROUP" \
            --sku Standard_Microsoft \
            --location global \
            --output none
        
        if [[ $? -eq 0 ]]; then
            log "✅ CDN Profile created: $CDN_PROFILE"
        else
            error "Failed to create CDN Profile"
            exit 1
        fi
    fi
    
    local cdn_endpoint_name="cdn-${SWA_NAME}"
    
    # Check if CDN endpoint already exists
    if az cdn endpoint show --name "$cdn_endpoint_name" --profile-name "$CDN_PROFILE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "CDN Endpoint '$cdn_endpoint_name' already exists. Skipping creation."
    else
        # Create CDN endpoint
        az cdn endpoint create \
            --name "$cdn_endpoint_name" \
            --profile-name "$CDN_PROFILE" \
            --resource-group "$RESOURCE_GROUP" \
            --origin "$SWA_URL" \
            --origin-host-header "$SWA_URL" \
            --enable-compression true \
            --content-types-to-compress \
                "application/javascript" \
                "text/css" \
                "text/html" \
                "application/json" \
                "image/svg+xml" \
            --output none
        
        if [[ $? -eq 0 ]]; then
            log "✅ CDN Endpoint created: $cdn_endpoint_name"
        else
            error "Failed to create CDN Endpoint"
            exit 1
        fi
    fi
    
    # Get CDN endpoint URL
    CDN_URL=$(az cdn endpoint show \
        --name "$cdn_endpoint_name" \
        --profile-name "$CDN_PROFILE" \
        --resource-group "$RESOURCE_GROUP" \
        --query hostName --output tsv)
    
    export CDN_URL
    
    info "CDN URL: https://$CDN_URL"
}

# Create configuration file
create_config() {
    log "Creating configuration file..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create config.js file"
        return
    fi
    
    if [[ -d "pwa-demo/src" ]]; then
        cat > pwa-demo/src/config.js << EOF
window.CONFIG = {
    APPLICATION_INSIGHTS: {
        INSTRUMENTATION_KEY: '$AI_INSTRUMENTATION_KEY',
        CONNECTION_STRING: '$AI_CONNECTION_STRING'
    },
    CDN_ENDPOINT: 'https://$CDN_URL',
    API_BASE_URL: 'https://$SWA_URL/api'
};
EOF
        log "✅ Configuration file created"
    else
        warning "PWA project directory not found. Skipping config creation."
    fi
}

# Display deployment summary
deployment_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    echo ""
    echo "✅ Resource Group: $RESOURCE_GROUP"
    echo "✅ Static Web App: $SWA_NAME"
    echo "   URL: https://$SWA_URL"
    echo "✅ CDN Profile: $CDN_PROFILE"
    echo "   URL: https://$CDN_URL"
    echo "✅ Application Insights: $AI_NAME"
    echo "   Instrumentation Key: $AI_INSTRUMENTATION_KEY"
    echo ""
    echo "🎉 Progressive Web App deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Connect your GitHub repository to the Static Web App for CI/CD"
    echo "2. Push your PWA code to trigger automatic deployment"
    echo "3. Test PWA functionality and monitor with Application Insights"
    echo "4. Configure custom domain if needed"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure Progressive Web App deployment..."
    
    check_prerequisites
    set_defaults
    display_configuration
    
    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user."
            exit 0
        fi
    fi
    
    prompt_github_info
    create_resource_group
    create_pwa_project
    create_application_insights
    create_static_web_app
    create_cdn
    create_config
    deployment_summary
    
    log "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted! Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"