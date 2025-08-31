#!/bin/bash

#
# Azure Maps Store Locator Deployment Script
#
# This script deploys a complete Azure Maps store locator solution including:
# - Azure Maps account with Gen2 pricing tier
# - Web application files (HTML, CSS, JavaScript)
# - Sample store data
#
# Author: Recipe Infrastructure Generator
# Version: 1.0
# Last Updated: 2025-01-12
#

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_DIR="${SCRIPT_DIR}/../app"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Default configuration (can be overridden by environment variables)
readonly DEFAULT_LOCATION="eastus"
readonly DEFAULT_RESOURCE_PREFIX="storemaps"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

#
# Logging and output functions
#
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

#
# Print script header
#
print_header() {
    echo ""
    echo "================================================================"
    echo "       Azure Maps Store Locator Deployment Script"
    echo "================================================================"
    echo "This script will deploy:"
    echo "  • Azure Maps account (Gen2 pricing tier)"
    echo "  • Interactive web application"
    echo "  • Sample store location data"
    echo "  • Local development server setup"
    echo ""
    echo "Estimated deployment time: 3-5 minutes"
    echo "Estimated cost: \$0 (Gen2 includes 1,000 free transactions/month)"
    echo "================================================================"
    echo ""
}

#
# Display usage information
#
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -l, --location LOCATION Azure region (default: ${DEFAULT_LOCATION})"
    echo "  -p, --prefix PREFIX     Resource name prefix (default: ${DEFAULT_RESOURCE_PREFIX})"
    echo "  -r, --resource-group RG Resource group name (auto-generated if not specified)"
    echo "  -d, --dry-run           Show what would be deployed without executing"
    echo "  -v, --verbose           Enable verbose logging"
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_LOCATION         Override default Azure region"
    echo "  RESOURCE_PREFIX        Override default resource prefix"
    echo "  SKIP_CONFIRMATION      Skip deployment confirmation (set to 'true')"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Deploy with defaults"
    echo "  $0 --location westus2 --prefix mystore     # Custom location and prefix"
    echo "  $0 --dry-run                               # Preview deployment"
    echo ""
}

#
# Prerequisite checks
#
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required for generating unique resource names."
        exit 1
    fi
    
    # Check for Python (for local web server)
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        log_warning "Python is not available. You'll need to use an alternative web server for testing."
    fi
    
    log_success "Prerequisites check completed"
}

#
# Initialize deployment variables
#
initialize_variables() {
    log_info "Initializing deployment variables..."
    
    # Set location from parameter, environment, or default
    LOCATION="${AZURE_LOCATION:-${DEFAULT_LOCATION}}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    RESOURCE_PREFIX="${RESOURCE_PREFIX:-${DEFAULT_RESOURCE_PREFIX}}"
    RESOURCE_GROUP="${RESOURCE_GROUP_NAME:-rg-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}}"
    MAPS_ACCOUNT_NAME="maps${RESOURCE_PREFIX}${RANDOM_SUFFIX}"
    
    # Get Azure subscription information
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    log_info "Deployment configuration:"
    log_info "  Subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    log_info "  Location: ${LOCATION}"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Maps Account: ${MAPS_ACCOUNT_NAME}"
    log_info "  Random Suffix: ${RANDOM_SUFFIX}"
}

#
# Validate Azure region and services
#
validate_azure_environment() {
    log_info "Validating Azure environment..."
    
    # Check if the specified location is valid
    if ! az account list-locations --query "[?name=='${LOCATION}'].name" --output tsv | grep -q "${LOCATION}"; then
        log_error "Invalid Azure location: ${LOCATION}"
        log_info "Available locations can be listed with: az account list-locations --output table"
        exit 1
    fi
    
    # Check if Azure Maps is available in the region
    if ! az provider show --namespace Microsoft.Maps --query "registrationState" --output tsv | grep -q "Registered"; then
        log_warning "Azure Maps provider may not be registered. Attempting to register..."
        az provider register --namespace Microsoft.Maps
        log_info "Provider registration initiated. This may take a few minutes to complete."
    fi
    
    log_success "Azure environment validation completed"
}

#
# Confirm deployment with user
#
confirm_deployment() {
    if [[ "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "Ready to deploy Azure Maps Store Locator with the following configuration:"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  Location: ${LOCATION}"
    echo "  Maps Account: ${MAPS_ACCOUNT_NAME}"
    echo ""
    echo "This deployment will:"
    echo "  • Create Azure Maps account (Gen2 - includes 1,000 free transactions/month)"
    echo "  • Generate web application files"
    echo "  • Set up local development environment"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

#
# Create Azure resource group
#
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
        return 0
    fi
    
    # Create resource group with appropriate tags
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags \
            purpose=recipe \
            environment=demo \
            application=store-locator \
            created-by=deployment-script \
            created-date="$(date '+%Y-%m-%d')" \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

#
# Create Azure Maps account
#
create_azure_maps_account() {
    log_info "Creating Azure Maps account: ${MAPS_ACCOUNT_NAME}"
    
    # Check if Maps account already exists
    if az maps account show --resource-group "${RESOURCE_GROUP}" --account-name "${MAPS_ACCOUNT_NAME}" &> /dev/null; then
        log_warning "Azure Maps account ${MAPS_ACCOUNT_NAME} already exists"
        return 0
    fi
    
    # Create Azure Maps account with Gen2 pricing tier
    az maps account create \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${MAPS_ACCOUNT_NAME}" \
        --sku Gen2 \
        --tags \
            application=store-locator \
            environment=demo \
            tier=Gen2 \
        --output none
    
    # Wait for account to be fully provisioned
    log_info "Waiting for Azure Maps account to be ready..."
    local retry_count=0
    local max_retries=30
    
    while [ $retry_count -lt $max_retries ]; do
        if az maps account show --resource-group "${RESOURCE_GROUP}" --account-name "${MAPS_ACCOUNT_NAME}" --query "properties.provisioningState" --output tsv | grep -q "Succeeded"; then
            break
        fi
        log_info "  Account still provisioning... (attempt $((retry_count + 1))/${max_retries})"
        sleep 10
        ((retry_count++))
    done
    
    if [ $retry_count -eq $max_retries ]; then
        log_error "Azure Maps account creation timed out"
        exit 1
    fi
    
    log_success "Azure Maps account created: ${MAPS_ACCOUNT_NAME}"
}

#
# Retrieve Azure Maps subscription key
#
get_maps_subscription_key() {
    log_info "Retrieving Azure Maps subscription key..."
    
    # Get the primary subscription key
    MAPS_KEY=$(az maps account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${MAPS_ACCOUNT_NAME}" \
        --query primaryKey \
        --output tsv)
    
    if [[ -z "${MAPS_KEY}" ]]; then
        log_error "Failed to retrieve Azure Maps subscription key"
        exit 1
    fi
    
    log_success "Azure Maps subscription key retrieved"
    log_info "Key starts with: ${MAPS_KEY:0:8}..."
}

#
# Create application directory structure
#
create_app_directory() {
    log_info "Creating application directory structure..."
    
    # Create application directory
    mkdir -p "${APP_DIR}"
    
    # Create subdirectories for organized file structure
    mkdir -p "${APP_DIR}/assets"
    mkdir -p "${APP_DIR}/css"
    mkdir -p "${APP_DIR}/js"
    mkdir -p "${APP_DIR}/data"
    
    log_success "Application directory created: ${APP_DIR}"
}

#
# Generate store data JSON file
#
create_store_data() {
    log_info "Creating sample store location data..."
    
    cat > "${APP_DIR}/data/stores.json" << 'EOF'
[
  {
    "name": "Downtown Coffee Shop",
    "address": "123 Main St, Seattle, WA 98101",
    "phone": "(206) 555-0101",
    "hours": "Mon-Fri 6:00AM-8:00PM, Sat-Sun 7:00AM-9:00PM",
    "latitude": 47.6062,
    "longitude": -122.3321,
    "services": ["WiFi", "Drive-through", "Outdoor Seating"]
  },
  {
    "name": "University District Cafe",
    "address": "456 University Way, Seattle, WA 98105",
    "phone": "(206) 555-0102",
    "hours": "Daily 5:30AM-10:00PM",
    "latitude": 47.6587,
    "longitude": -122.3138,
    "services": ["WiFi", "Study Area", "Pastries"]
  },
  {
    "name": "Capitol Hill Roastery",
    "address": "789 Pine St, Seattle, WA 98122",
    "phone": "(206) 555-0103",
    "hours": "Mon-Fri 6:30AM-7:00PM, Sat-Sun 7:30AM-8:00PM",
    "latitude": 47.6149,
    "longitude": -122.3194,
    "services": ["Fresh Roasted", "Live Music", "Art Gallery"]
  },
  {
    "name": "Fremont Specialty Coffee",
    "address": "321 N 36th St, Seattle, WA 98103",
    "phone": "(206) 555-0104",
    "hours": "Mon-Fri 7:00AM-6:00PM, Sat-Sun 8:00AM-7:00PM",
    "latitude": 47.6517,
    "longitude": -122.3493,
    "services": ["Organic Options", "Meeting Rooms", "Catering"]
  },
  {
    "name": "Ballard Waterfront Cafe",
    "address": "987 NW Market St, Seattle, WA 98107",
    "phone": "(206) 555-0105",
    "hours": "Daily 6:00AM-9:00PM",
    "latitude": 47.6686,
    "longitude": -122.3838,
    "services": ["Waterfront View", "Live Music", "Pet Friendly"]
  }
]
EOF
    
    log_success "Store location data created with 5 sample locations"
}

#
# Generate HTML application file
#
create_html_file() {
    log_info "Creating HTML application file..."
    
    cat > "${APP_DIR}/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="IE=Edge">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>Store Locator - Find Our Locations</title>
    
    <!-- Azure Maps SDK CSS and JavaScript -->
    <link rel="stylesheet" href="https://atlas.microsoft.com/sdk/javascript/mapcontrol/3/atlas.min.css" type="text/css">
    <script src="https://atlas.microsoft.com/sdk/javascript/mapcontrol/3/atlas.min.js"></script>
    
    <!-- Application styles -->
    <link rel="stylesheet" href="css/styles.css" type="text/css">
</head>
<body>
    <header>
        <h1>🏪 Our Store Locations</h1>
        <p>Find the nearest store location with our interactive map</p>
    </header>
    
    <main>
        <div class="search-panel">
            <input id="searchBox" type="search" placeholder="Search for a location..." />
            <button id="searchButton" title="Search">🔍</button>
            <button id="myLocationButton" title="My Location">📍</button>
            <button id="resetButton" title="Reset View">🔄</button>
        </div>
        
        <div class="content-container">
            <div id="listPanel" class="list-panel">
                <div class="list-header">
                    <h3>Store Locations</h3>
                    <span id="storeCount" class="store-count"></span>
                </div>
                <div id="storeList" class="store-list"></div>
            </div>
            <div id="mapContainer" class="map-container"></div>
        </div>
    </main>
    
    <footer>
        <div class="footer-content">
            <p>Powered by Azure Maps | Built with ❤️ for demo purposes</p>
        </div>
    </footer>
    
    <script src="js/app.js"></script>
</body>
</html>
EOF
    
    log_success "HTML application file created"
}

#
# Generate CSS styling file
#
create_css_file() {
    log_info "Creating CSS styling file..."
    
    cat > "${APP_DIR}/css/styles.css" << 'EOF'
* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background-color: #f5f5f5;
    color: #333;
    line-height: 1.6;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
}

header {
    background: linear-gradient(135deg, #0078d4, #005a9e);
    color: white;
    padding: 2rem;
    text-align: center;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
}

header h1 {
    font-size: 2.5rem;
    margin-bottom: 0.5rem;
    font-weight: 600;
}

header p {
    font-size: 1.1rem;
    opacity: 0.9;
}

.search-panel {
    display: flex;
    gap: 10px;
    padding: 1rem;
    background: white;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    justify-content: center;
    align-items: center;
    flex-wrap: wrap;
}

#searchBox {
    flex: 1;
    max-width: 400px;
    min-width: 200px;
    padding: 12px 16px;
    border: 2px solid #ddd;
    border-radius: 25px;
    font-size: 16px;
    outline: none;
    transition: border-color 0.3s, box-shadow 0.3s;
}

#searchBox:focus {
    border-color: #0078d4;
    box-shadow: 0 0 0 3px rgba(0, 120, 212, 0.1);
}

button {
    padding: 12px 20px;
    border: none;
    border-radius: 25px;
    background: #0078d4;
    color: white;
    cursor: pointer;
    font-size: 16px;
    transition: background-color 0.3s, transform 0.1s;
    min-width: 50px;
}

button:hover {
    background: #005a9e;
    transform: translateY(-1px);
}

button:active {
    transform: translateY(0);
}

main {
    flex: 1;
    display: flex;
    flex-direction: column;
}

.content-container {
    display: flex;
    flex: 1;
    min-height: 500px;
}

.list-panel {
    width: 350px;
    background: white;
    border-right: 1px solid #ddd;
    display: flex;
    flex-direction: column;
}

.list-header {
    padding: 1rem;
    background: #f8f9fa;
    border-bottom: 2px solid #dee2e6;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.list-header h3 {
    color: #0078d4;
    font-size: 1.1rem;
}

.store-count {
    background: #0078d4;
    color: white;
    padding: 4px 8px;
    border-radius: 12px;
    font-size: 0.8rem;
    font-weight: bold;
}

.store-list {
    flex: 1;
    overflow-y: auto;
}

.map-container {
    flex: 1;
    position: relative;
    min-height: 400px;
}

.store-item {
    padding: 1rem;
    border-bottom: 1px solid #eee;
    cursor: pointer;
    transition: background-color 0.2s, border-left 0.2s;
    border-left: 4px solid transparent;
}

.store-item:hover {
    background-color: #f8f9fa;
    border-left-color: #0078d4;
}

.store-item.selected {
    background-color: #e3f2fd;
    border-left-color: #0078d4;
}

.store-name {
    font-weight: bold;
    color: #0078d4;
    margin-bottom: 0.5rem;
    font-size: 1rem;
}

.store-address {
    color: #666;
    font-size: 0.9rem;
    margin-bottom: 0.25rem;
}

.store-phone {
    color: #666;
    font-size: 0.85rem;
    margin-bottom: 0.25rem;
}

.store-distance {
    color: #0078d4;
    font-size: 0.8rem;
    font-weight: bold;
}

.store-services {
    margin-top: 0.5rem;
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
}

.service-tag {
    background: #e3f2fd;
    color: #0078d4;
    padding: 2px 6px;
    border-radius: 8px;
    font-size: 0.7rem;
    font-weight: 500;
}

footer {
    background: #333;
    color: white;
    padding: 1rem;
    text-align: center;
    margin-top: auto;
}

.footer-content p {
    font-size: 0.9rem;
    opacity: 0.8;
}

/* Loading states */
.loading {
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 2rem;
    color: #666;
}

.error-message {
    background: #ffebee;
    color: #c62828;
    padding: 1rem;
    border-radius: 4px;
    margin: 1rem;
    border-left: 4px solid #c62828;
}

/* Mobile responsive design */
@media (max-width: 768px) {
    header h1 {
        font-size: 2rem;
    }
    
    .search-panel {
        flex-direction: column;
        gap: 8px;
    }
    
    #searchBox {
        max-width: none;
        width: 100%;
    }
    
    .content-container {
        flex-direction: column;
    }
    
    .list-panel {
        width: 100%;
        max-height: 250px;
        order: 2;
    }
    
    .map-container {
        min-height: 300px;
        order: 1;
    }
}

@media (max-width: 480px) {
    header {
        padding: 1rem;
    }
    
    header h1 {
        font-size: 1.5rem;
    }
    
    .search-panel {
        padding: 0.5rem;
    }
    
    button {
        padding: 10px 16px;
        font-size: 14px;
    }
    
    .store-item {
        padding: 0.75rem;
    }
}

/* Print styles */
@media print {
    .search-panel,
    .map-container,
    footer {
        display: none;
    }
    
    .content-container {
        flex-direction: column;
    }
    
    .list-panel {
        width: 100%;
        max-height: none;
    }
}
EOF
    
    log_success "CSS styling file created"
}

#
# Generate JavaScript application file
#
create_javascript_file() {
    log_info "Creating JavaScript application file..."
    
    cat > "${APP_DIR}/js/app.js" << EOF
//
// Azure Maps Store Locator Application
// Generated by Azure Maps Recipe Deployment Script
//

// Azure Maps configuration
const MAPS_KEY = '${MAPS_KEY}';
let map, dataSource, searchServiceClient, popup, stores = [];
let selectedStoreId = null;

// Application state
const appState = {
    isLoading: false,
    lastSearchQuery: '',
    userLocation: null
};

// Initialize the application when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    log('🚀 Initializing Azure Maps Store Locator...');
    
    initializeMap();
    loadStoreData();
    setupEventListeners();
    
    log('✅ Application initialized successfully');
});

/**
 * Logging utility function
 */
function log(message) {
    console.log(\`[\${new Date().toISOString()}] \${message}\`);
}

/**
 * Initialize Azure Maps with configuration
 */
function initializeMap() {
    log('🗺️  Initializing Azure Maps...');
    
    try {
        // Initialize Azure Maps with authentication
        map = new atlas.Map('mapContainer', {
            center: [-122.3321, 47.6062], // Seattle coordinates
            zoom: 10,
            language: 'en-US',
            authOptions: {
                authType: 'subscriptionKey',
                subscriptionKey: MAPS_KEY
            },
            style: 'road',
            showLogo: false
        });

        // Wait for map to be ready before adding components
        map.events.add('ready', function() {
            log('🗺️  Map ready, adding components...');
            
            // Create data source for store locations
            dataSource = new atlas.source.DataSource(null, {
                cluster: true,
                clusterRadius: 45,
                clusterMaxZoom: 15
            });
            
            map.sources.add(dataSource);

            // Create popup for store details
            popup = new atlas.Popup({
                pixelOffset: [0, -40],
                closeButton: true
            });

            // Add map controls
            map.controls.add([
                new atlas.control.ZoomControl(),
                new atlas.control.CompassControl(),
                new atlas.control.PitchControl(),
                new atlas.control.StyleControl({
                    mapStyles: ['road', 'satellite', 'hybrid', 'grayscale_dark']
                })
            ], {
                position: 'top-right'
            });

            // Create layers for displaying stores
            createMapLayers();
            
            // Initialize search service
            searchServiceClient = new atlas.service.SearchServiceClient(
                atlas.service.MapsURL.newPipeline(new atlas.service.SubscriptionKeyCredential(MAPS_KEY))
            );
            
            log('✅ Map components initialized');
        });
        
        // Handle map errors
        map.events.add('error', function(error) {
            log('❌ Map error: ' + error.error.message);
            showError('Map failed to load. Please check your internet connection and try again.');
        });
        
    } catch (error) {
        log('❌ Failed to initialize map: ' + error.message);
        showError('Failed to initialize Azure Maps. Please refresh the page and try again.');
    }
}

/**
 * Create map layers for displaying stores and clusters
 */
function createMapLayers() {
    // Bubble layer for clustered points
    const clusterBubbleLayer = new atlas.layer.BubbleLayer(dataSource, null, {
        radius: [
            'case',
            ['>=', ['get', 'point_count'], 10], 30,
            ['>=', ['get', 'point_count'], 5], 25,
            20
        ],
        color: '#0078d4',
        strokeColor: 'white',
        strokeWidth: 2,
        filter: ['has', 'point_count']
    });

    // Symbol layer for cluster count
    const clusterLabelLayer = new atlas.layer.SymbolLayer(dataSource, null, {
        iconOptions: {
            image: 'none'
        },
        textOptions: {
            textField: ['get', 'point_count_abbreviated'],
            color: 'white',
            font: ['StandardFont-Bold'],
            size: 12
        },
        filter: ['has', 'point_count']
    });

    // Symbol layer for individual stores
    const storeLayer = new atlas.layer.SymbolLayer(dataSource, null, {
        iconOptions: {
            image: 'marker-red',
            allowOverlap: true,
            ignorePlacement: true,
            size: 0.8
        },
        filter: ['!', ['has', 'point_count']]
    });

    // Add layers to map
    map.layers.add([clusterBubbleLayer, clusterLabelLayer, storeLayer]);

    // Add click events
    map.events.add('click', clusterBubbleLayer, clusterClicked);
    map.events.add('click', storeLayer, storeClicked);
    map.events.add('moveend', updateStoreList);
    
    // Add hover effects
    map.events.add('mouseenter', storeLayer, function() {
        map.getCanvasContainer().style.cursor = 'pointer';
    });
    
    map.events.add('mouseleave', storeLayer, function() {
        map.getCanvasContainer().style.cursor = 'grab';
    });
    
    log('✅ Map layers created and event handlers attached');
}

/**
 * Load store data from JSON file
 */
async function loadStoreData() {
    log('📍 Loading store location data...');
    setLoadingState(true);
    
    try {
        const response = await fetch('data/stores.json');
        if (!response.ok) {
            throw new Error(\`HTTP error! status: \${response.status}\`);
        }
        
        stores = await response.json();
        
        // Validate store data
        stores = stores.filter(store => {
            return store.name && store.latitude && store.longitude && 
                   typeof store.latitude === 'number' && typeof store.longitude === 'number';
        });
        
        // Convert stores to GeoJSON features
        const features = stores.map((store, index) => {
            const feature = new atlas.data.Feature(
                new atlas.data.Point([store.longitude, store.latitude]),
                { ...store, id: index }
            );
            return feature;
        });
        
        dataSource.add(features);
        updateStoreList();
        updateStoreCount();
        
        log(\`✅ Loaded \${stores.length} store locations\`);
        
    } catch (error) {
        log('❌ Error loading store data: ' + error.message);
        showError('Failed to load store locations. Please refresh the page and try again.');
    } finally {
        setLoadingState(false);
    }
}

/**
 * Set up event listeners for user interactions
 */
function setupEventListeners() {
    // Search functionality
    document.getElementById('searchButton').addEventListener('click', performSearch);
    document.getElementById('searchBox').addEventListener('keypress', function(e) {
        if (e.key === 'Enter') {
            performSearch();
        }
    });

    // My location functionality
    document.getElementById('myLocationButton').addEventListener('click', getUserLocation);
    
    // Reset view functionality
    document.getElementById('resetButton').addEventListener('click', resetMapView);

    // Clear search on escape key
    document.getElementById('searchBox').addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            this.value = '';
            resetMapView();
        }
    });
    
    log('✅ Event listeners configured');
}

/**
 * Perform search using Azure Maps Search API
 */
async function performSearch() {
    const query = document.getElementById('searchBox').value.trim();
    if (!query) {
        log('⚠️  Empty search query');
        return;
    }
    
    log(\`🔍 Searching for: \${query}\`);
    setLoadingState(true);

    try {
        const results = await searchServiceClient.searchPOI(
            atlas.service.Aborter.timeout(10000),
            query,
            {
                limit: 5,
                lat: map.getCamera().center[1],
                lon: map.getCamera().center[0],
                radius: 50000
            }
        );

        if (results.results && results.results.length > 0) {
            const result = results.results[0];
            map.setCamera({
                center: [result.position.lon, result.position.lat],
                zoom: 12,
                type: 'ease',
                duration: 1000
            });
            
            appState.lastSearchQuery = query;
            log(\`✅ Search completed, found: \${result.poi ? result.poi.name : 'location'}\`);
        } else {
            log('⚠️  No search results found');
            showError(\`No results found for "\${query}". Try a different search term.\`);
        }
    } catch (error) {
        log('❌ Search error: ' + error.message);
        showError('Search failed. Please check your internet connection and try again.');
    } finally {
        setLoadingState(false);
    }
}

/**
 * Get user's current location
 */
function getUserLocation() {
    log('📍 Requesting user location...');
    
    if (!navigator.geolocation) {
        log('❌ Geolocation not supported');
        showError('Geolocation is not supported by this browser.');
        return;
    }

    setLoadingState(true);
    
    navigator.geolocation.getCurrentPosition(
        function(position) {
            const coords = [position.coords.longitude, position.coords.latitude];
            appState.userLocation = coords;
            
            map.setCamera({
                center: coords,
                zoom: 12,
                type: 'ease',
                duration: 1000
            });
            
            log(\`✅ User location acquired: \${coords[1].toFixed(4)}, \${coords[0].toFixed(4)}\`);
        },
        function(error) {
            let message = 'Unable to get your location. ';
            switch(error.code) {
                case error.PERMISSION_DENIED:
                    message += 'Location access was denied.';
                    break;
                case error.POSITION_UNAVAILABLE:
                    message += 'Location information is unavailable.';
                    break;
                case error.TIMEOUT:
                    message += 'Location request timed out.';
                    break;
                default:
                    message += 'An unknown error occurred.';
                    break;
            }
            
            log('❌ Geolocation error: ' + message);
            showError(message + ' Please try searching instead.');
        },
        {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 60000
        }
    );
    
    setLoadingState(false);
}

/**
 * Reset map view to initial state
 */
function resetMapView() {
    log('🔄 Resetting map view...');
    
    map.setCamera({
        center: [-122.3321, 47.6062],
        zoom: 10,
        type: 'ease',
        duration: 1000
    });
    
    document.getElementById('searchBox').value = '';
    popup.close();
    selectedStoreId = null;
    updateStoreList();
    
    log('✅ Map view reset');
}

/**
 * Handle cluster click events
 */
function clusterClicked(e) {
    if (e.shapes && e.shapes.length > 0) {
        const clusterProperties = e.shapes[0].getProperties();
        log(\`🎯 Cluster clicked with \${clusterProperties.point_count} stores\`);
        
        map.setCamera({
            center: e.position,
            zoom: map.getCamera().zoom + 2,
            type: 'ease',
            duration: 800
        });
    }
}

/**
 * Handle individual store click events
 */
function storeClicked(e) {
    if (e.shapes && e.shapes.length > 0) {
        const properties = e.shapes[0].getProperties();
        selectedStoreId = properties.id;
        
        log(\`🏪 Store clicked: \${properties.name}\`);
        
        showStorePopup(e.position, properties);
        updateStoreList();
    }
}

/**
 * Show detailed popup for a store
 */
function showStorePopup(position, store) {
    const services = Array.isArray(store.services) ? store.services.join(', ') : 'Not specified';
    
    const content = \`
        <div style="padding: 15px; max-width: 300px;">
            <h3 style="color: #0078d4; margin-bottom: 10px; font-size: 1.1rem;">\${store.name}</h3>
            <div style="margin-bottom: 8px;">
                <strong>📍 Address:</strong><br>
                <span style="color: #666;">\${store.address}</span>
            </div>
            <div style="margin-bottom: 8px;">
                <strong>📞 Phone:</strong> 
                <a href="tel:\${store.phone}" style="color: #0078d4; text-decoration: none;">\${store.phone}</a>
            </div>
            <div style="margin-bottom: 8px;">
                <strong>🕒 Hours:</strong><br>
                <span style="color: #666;">\${store.hours}</span>
            </div>
            <div>
                <strong>🛠️ Services:</strong><br>
                <span style="color: #666;">\${services}</span>
            </div>
        </div>
    \`;
    
    popup.setOptions({
        content: content,
        position: position
    });
    
    popup.open(map);
}

/**
 * Update the store list based on current map view
 */
function updateStoreList() {
    const listContainer = document.getElementById('storeList');
    const bounds = map.getCamera().bounds;
    const centerPoint = map.getCamera().center;
    
    // Filter stores within current map bounds
    const visibleStores = stores.filter(store => {
        return store.longitude >= bounds[0] && 
               store.longitude <= bounds[2] && 
               store.latitude >= bounds[1] && 
               store.latitude <= bounds[3];
    });

    // Calculate distances and sort
    visibleStores.forEach((store, index) => {
        store.distance = atlas.math.getDistanceTo(
            new atlas.data.Position(centerPoint[0], centerPoint[1]),
            new atlas.data.Position(store.longitude, store.latitude),
            'miles'
        );
        store.id = stores.indexOf(store);
    });

    visibleStores.sort((a, b) => a.distance - b.distance);

    // Update list panel
    if (visibleStores.length === 0) {
        listContainer.innerHTML = '<div class="loading">No stores visible in current area</div>';
    } else {
        listContainer.innerHTML = visibleStores.map(store => {
            const isSelected = selectedStoreId === store.id;
            const services = Array.isArray(store.services) ? 
                store.services.map(service => \`<span class="service-tag">\${service}</span>\`).join('') : '';
            
            return \`
                <div class="store-item \${isSelected ? 'selected' : ''}" onclick="focusStore(\${store.latitude}, \${store.longitude}, \${store.id})">
                    <div class="store-name">\${store.name}</div>
                    <div class="store-address">\${store.address}</div>
                    <div class="store-phone">\${store.phone}</div>
                    <div class="store-distance">\${store.distance.toFixed(1)} miles away</div>
                    \${services ? \`<div class="store-services">\${services}</div>\` : ''}
                </div>
            \`;
        }).join('');
    }
    
    updateStoreCount(visibleStores.length);
}

/**
 * Focus on a specific store
 */
function focusStore(lat, lon, storeId) {
    selectedStoreId = storeId;
    
    map.setCamera({
        center: [lon, lat],
        zoom: 15,
        type: 'ease',
        duration: 800
    });
    
    // Find and show popup for the store
    const store = stores.find(s => stores.indexOf(s) === storeId);
    if (store) {
        showStorePopup([lon, lat], store);
        log(\`🎯 Focused on store: \${store.name}\`);
    }
    
    updateStoreList();
}

/**
 * Update store count display
 */
function updateStoreCount(visibleCount = null) {
    const countElement = document.getElementById('storeCount');
    const count = visibleCount !== null ? visibleCount : stores.length;
    const total = stores.length;
    
    if (visibleCount !== null && visibleCount < total) {
        countElement.textContent = \`\${count} of \${total}\`;
    } else {
        countElement.textContent = total.toString();
    }
}

/**
 * Show error message to user
 */
function showError(message) {
    // Remove existing error messages
    const existingErrors = document.querySelectorAll('.error-message');
    existingErrors.forEach(error => error.remove());
    
    // Create new error message
    const errorDiv = document.createElement('div');
    errorDiv.className = 'error-message';
    errorDiv.textContent = message;
    
    // Insert after search panel
    const searchPanel = document.querySelector('.search-panel');
    searchPanel.parentNode.insertBefore(errorDiv, searchPanel.nextSibling);
    
    // Remove error message after 5 seconds
    setTimeout(() => {
        if (errorDiv.parentNode) {
            errorDiv.parentNode.removeChild(errorDiv);
        }
    }, 5000);
}

/**
 * Set loading state for UI elements
 */
function setLoadingState(loading) {
    appState.isLoading = loading;
    const buttons = document.querySelectorAll('button');
    const searchBox = document.getElementById('searchBox');
    
    buttons.forEach(button => {
        button.disabled = loading;
        if (loading) {
            button.style.opacity = '0.6';
            button.style.cursor = 'not-allowed';
        } else {
            button.style.opacity = '1';
            button.style.cursor = 'pointer';
        }
    });
    
    searchBox.disabled = loading;
    if (loading) {
        searchBox.style.opacity = '0.6';
    } else {
        searchBox.style.opacity = '1';
    }
}

// Export functions for global access (useful for debugging)
window.storeLocator = {
    focusStore,
    resetMapView,
    performSearch,
    getUserLocation,
    stores: () => stores,
    appState: () => appState
};
EOF
    
    log_success "JavaScript application file created with integrated Azure Maps key"
}

#
# Create deployment summary and instructions
#
create_deployment_summary() {
    log_info "Creating deployment summary..."
    
    cat > "${APP_DIR}/DEPLOYMENT_SUMMARY.md" << EOF
# Azure Maps Store Locator - Deployment Summary

## Deployment Information

- **Deployment Date**: $(date '+%Y-%m-%d %H:%M:%S')
- **Azure Subscription**: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})
- **Resource Group**: ${RESOURCE_GROUP}
- **Location**: ${LOCATION}
- **Azure Maps Account**: ${MAPS_ACCOUNT_NAME}

## Created Resources

### Azure Resources
- **Resource Group**: ${RESOURCE_GROUP}
  - Purpose: Container for all store locator resources
  - Tags: purpose=recipe, environment=demo, application=store-locator

- **Azure Maps Account**: ${MAPS_ACCOUNT_NAME}
  - SKU: Gen2 (includes 1,000 free transactions/month)
  - Pricing: $0 for basic usage
  - Services: Maps, Search, Routing APIs

### Application Files
- **HTML**: \`index.html\` - Main application interface
- **CSS**: \`css/styles.css\` - Responsive styling
- **JavaScript**: \`js/app.js\` - Application logic with Azure Maps integration
- **Data**: \`data/stores.json\` - Sample store location data (5 locations)

## Quick Start

1. **Start Local Web Server**:
   \`\`\`bash
   cd "${APP_DIR}"
   python3 -m http.server 8000
   \`\`\`

2. **Open Application**:
   - Navigate to: http://localhost:8000
   - The map should load with store markers

3. **Test Features**:
   - Search for locations using the search box
   - Click "My Location" to center map on your location
   - Click store markers to see detailed information
   - Use the store list panel to navigate to locations

## Features Included

- **Interactive Map**: Azure Maps with clustering and responsive design
- **Store Search**: Location-based search functionality
- **Geolocation**: "My Location" button for user positioning
- **Store Details**: Popup information with contact details and services
- **Mobile Responsive**: Optimized for desktop, tablet, and mobile devices
- **Store List**: Side panel with distance calculations and filtering

## Cost Information

- **Azure Maps Gen2**: 1,000 free transactions per month
- **Typical Usage**: ~10-50 transactions per user session
- **Estimated Monthly Cost**: $0 for demo/small business usage

## Next Steps

1. **Customize Store Data**: Edit \`data/stores.json\` with your actual store locations
2. **Customize Styling**: Modify \`css/styles.css\` to match your brand
3. **Add Features**: Implement routing, advanced search, or admin interface
4. **Production Deployment**: Consider Azure Static Web Apps or App Service

## Security Notes

- The Azure Maps subscription key is embedded in the JavaScript for demo purposes
- For production, consider using Microsoft Entra ID authentication
- Implement proper key rotation and access controls

## Cleanup

To remove all resources created by this deployment:
\`\`\`bash
${SCRIPT_DIR}/destroy.sh
\`\`\`

## Support

- Recipe Documentation: See original recipe markdown file
- Azure Maps Documentation: https://docs.microsoft.com/azure/azure-maps/
- Azure Support: https://azure.microsoft.com/support/
EOF
    
    log_success "Deployment summary created"
}

#
# Test the deployed application
#
test_deployment() {
    log_info "Testing deployed application..."
    
    # Test Azure Maps account
    local maps_status=$(az maps account show \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${MAPS_ACCOUNT_NAME}" \
        --query "properties.provisioningState" \
        --output tsv 2>/dev/null)
    
    if [[ "${maps_status}" == "Succeeded" ]]; then
        log_success "✅ Azure Maps account is active and ready"
    else
        log_warning "⚠️  Azure Maps account status: ${maps_status}"
    fi
    
    # Test file structure
    local files_to_check=(
        "${APP_DIR}/index.html"
        "${APP_DIR}/css/styles.css"
        "${APP_DIR}/js/app.js"
        "${APP_DIR}/data/stores.json"
    )
    
    for file in "${files_to_check[@]}"; do
        if [[ -f "${file}" ]]; then
            log_success "✅ Found: $(basename "${file}")"
        else
            log_error "❌ Missing: $(basename "${file}")"
        fi
    done
    
    # Test that Maps key is properly embedded
    if grep -q "${MAPS_KEY:0:8}" "${APP_DIR}/js/app.js"; then
        log_success "✅ Azure Maps key properly configured in application"
    else
        log_warning "⚠️  Azure Maps key may not be properly configured"
    fi
    
    log_success "Deployment testing completed"
}

#
# Display next steps and instructions
#
show_next_steps() {
    echo ""
    echo "================================================================"
    echo "           🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"
    echo "================================================================"
    echo ""
    echo "Your Azure Maps Store Locator has been deployed with:"
    echo "  ✅ Azure Maps account (${MAPS_ACCOUNT_NAME}) - Gen2 pricing"
    echo "  ✅ Interactive web application with 5 sample stores"
    echo "  ✅ Responsive design for mobile and desktop"
    echo "  ✅ Search functionality and geolocation support"
    echo ""
    echo "📂 Application files are located at:"
    echo "   ${APP_DIR}"
    echo ""
    echo "🚀 To start using your store locator:"
    echo ""
    echo "   1. Start a local web server:"
    echo "      cd \"${APP_DIR}\""
    echo "      python3 -m http.server 8000"
    echo ""
    echo "   2. Open your browser to:"
    echo "      http://localhost:8000"
    echo ""
    echo "   3. Test the features:"
    echo "      • Search for locations"
    echo "      • Click 'My Location' button"
    echo "      • Click store markers for details"
    echo "      • Try the mobile view"
    echo ""
    echo "📋 Important files:"
    echo "   • Main app: ${APP_DIR}/index.html"
    echo "   • Store data: ${APP_DIR}/data/stores.json"
    echo "   • Deployment info: ${APP_DIR}/DEPLOYMENT_SUMMARY.md"
    echo ""
    echo "💰 Cost Information:"
    echo "   • Azure Maps Gen2: 1,000 free transactions/month"
    echo "   • Current estimated cost: \$0/month for demo usage"
    echo ""
    echo "🔧 To customize your store locator:"
    echo "   • Edit store data in: data/stores.json"
    echo "   • Customize styling in: css/styles.css"
    echo "   • Add features to: js/app.js"
    echo ""
    echo "🗑️  To clean up resources:"
    echo "   ${SCRIPT_DIR}/destroy.sh"
    echo ""
    echo "================================================================"
    echo ""
}

#
# Main deployment function
#
main() {
    local location="${DEFAULT_LOCATION}"
    local resource_prefix="${DEFAULT_RESOURCE_PREFIX}"
    local dry_run=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--location)
                location="$2"
                shift 2
                ;;
            -p|--prefix)
                resource_prefix="$2"
                shift 2
                ;;
            -r|--resource-group)
                RESOURCE_GROUP_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                set -x
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set environment variables for script execution
    export AZURE_LOCATION="${location}"
    export RESOURCE_PREFIX="${resource_prefix}"
    
    # Start deployment process
    print_header
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        echo ""
    fi
    
    # Execute deployment steps
    check_prerequisites
    initialize_variables
    validate_azure_environment
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "Dry run completed. The following would be created:"
        log_info "  Resource Group: ${RESOURCE_GROUP}"
        log_info "  Azure Maps Account: ${MAPS_ACCOUNT_NAME}"
        log_info "  Application Directory: ${APP_DIR}"
        exit 0
    fi
    
    confirm_deployment
    
    # Create Azure resources
    create_resource_group
    create_azure_maps_account
    get_maps_subscription_key
    
    # Create application files
    create_app_directory
    create_store_data
    create_html_file
    create_css_file
    create_javascript_file
    create_deployment_summary
    
    # Test and finalize
    test_deployment
    show_next_steps
    
    log_success "🎉 Azure Maps Store Locator deployment completed successfully!"
}

# Trap to handle script interruption
trap 'log_error "Script interrupted. Cleanup may be required."; exit 1' INT TERM

# Execute main function with all arguments
main "$@"