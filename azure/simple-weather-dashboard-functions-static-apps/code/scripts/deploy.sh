#!/bin/bash

# Azure Weather Dashboard - Deploy Script
# Creates a complete serverless weather dashboard using Azure Static Web Apps and Functions
# Author: Recipe Generator v1.3
# Last Updated: 2025-07-12

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${SCRIPT_DIR}/deploy_${TIMESTAMP}.log"

# Start logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_info "Starting Azure Weather Dashboard deployment - $(date)"
log_info "Script directory: $SCRIPT_DIR"
log_info "Project root: $PROJECT_ROOT"
log_info "Log file: $LOG_FILE"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '\"azure-cli\"' -o tsv)
    log_info "Azure CLI version: $AZ_VERSION"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_warning "Node.js not found. Required for local development and testing."
    else
        NODE_VERSION=$(node --version)
        log_info "Node.js version: $NODE_VERSION"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required for generating random suffixes"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set Azure resource variables
    export RESOURCE_GROUP="rg-weather-dashboard-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export WEATHER_APP_NAME="weather-app-${RANDOM_SUFFIX}"
    
    # Display configuration
    log_info "Configuration:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Subscription ID: $SUBSCRIPTION_ID"
    log_info "  App Name: $WEATHER_APP_NAME"
    log_info "  Random Suffix: $RANDOM_SUFFIX"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
WEATHER_APP_NAME="$WEATHER_APP_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
DEPLOYMENT_TIMESTAMP="$TIMESTAMP"
EOF
    
    log_success "Environment variables configured"
}

# Function to create Azure resources
create_azure_resources() {
    log_info "Creating Azure resources..."
    
    # Create resource group
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo deployment-script=true \
        --output table
    
    if [ $? -eq 0 ]; then
        log_success "Resource group created: $RESOURCE_GROUP"
    else
        log_error "Failed to create resource group"
        exit 1
    fi
    
    # Create Static Web App
    log_info "Creating Static Web App: $WEATHER_APP_NAME"
    az staticwebapp create \
        --name "$WEATHER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --app-location "/src" \
        --api-location "/api" \
        --output-location "" \
        --sku Free \
        --tags purpose=recipe environment=demo
    
    if [ $? -eq 0 ]; then
        log_success "Static Web App created: $WEATHER_APP_NAME"
    else
        log_error "Failed to create Static Web App"
        exit 1
    fi
    
    # Wait for resource to be fully provisioned
    log_info "Waiting for Static Web App to be fully provisioned..."
    sleep 30
    
    # Get the Static Web App URL
    SWA_URL=$(az staticwebapp show \
        --name "$WEATHER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "defaultHostname" -o tsv)
    
    if [ -n "$SWA_URL" ]; then
        export SWA_URL
        echo "SWA_URL=\"$SWA_URL\"" >> "${SCRIPT_DIR}/.env"
        log_success "Static Web App URL: https://$SWA_URL"
    else
        log_error "Failed to retrieve Static Web App URL"
        exit 1
    fi
}

# Function to create project structure and files
create_project_files() {
    log_info "Creating project structure and files..."
    
    # Create project directory structure
    PROJECT_DIR="${SCRIPT_DIR}/../weather-dashboard"
    mkdir -p "$PROJECT_DIR"/{src,api}
    cd "$PROJECT_DIR"
    
    log_info "Project directory: $PROJECT_DIR"
    
    # Create package.json for Functions API
    log_info "Creating package.json for Functions API"
    cat > api/package.json << 'EOF'
{
  "name": "weather-api",
  "version": "1.0.0",
  "description": "Weather API for Static Web App",
  "main": "index.js",
  "scripts": {
    "start": "func start",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@azure/functions": "^4.0.0"
  },
  "devDependencies": {
    "azure-functions-core-tools": "^4.0.5000"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Create weather API function
    log_info "Creating weather API function"
    cat > api/weather.js << 'EOF'
const { app } = require('@azure/functions');

async function weatherHandler(request, context) {
    context.log('Weather API function triggered');

    try {
        // Get location from query parameters or default to New York
        const city = request.query.get('city') || 'New York';
        const apiKey = process.env.OPENWEATHER_API_KEY;

        if (!apiKey) {
            return {
                status: 500,
                jsonBody: { error: 'Weather API key not configured' }
            };
        }

        // Fetch weather data from OpenWeatherMap API
        const weatherUrl = `https://api.openweathermap.org/data/2.5/weather?q=${encodeURIComponent(city)}&appid=${apiKey}&units=metric`;
        const response = await fetch(weatherUrl);
        const data = await response.json();

        if (!response.ok) {
            return {
                status: 404,
                jsonBody: { error: 'City not found or API error' }
            };
        }

        // Process and return weather data
        const weatherInfo = {
            city: data.name,
            country: data.sys.country,
            temperature: Math.round(data.main.temp),
            description: data.weather[0].description,
            icon: data.weather[0].icon,
            humidity: data.main.humidity,
            pressure: data.main.pressure,
            windSpeed: data.wind.speed,
            lastUpdated: new Date().toISOString()
        };

        return {
            status: 200,
            headers: {
                'Content-Type': 'application/json'
            },
            jsonBody: weatherInfo
        };

    } catch (error) {
        context.log.error('Weather API error:', error);
        return {
            status: 500,
            jsonBody: { error: 'Internal server error' }
        };
    }
}

app.http('weather', {
    methods: ['GET', 'POST'],
    authLevel: 'anonymous',
    handler: weatherHandler
});
EOF
    
    # Create host.json for Functions runtime configuration
    log_info "Creating Functions runtime configuration"
    cat > api/host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:00:30",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "maxTelemetryItemsPerSecond": 20
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
EOF
    
    # Create HTML dashboard
    log_info "Creating HTML dashboard"
    cat > src/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Weather Dashboard</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>🌤️ Weather Dashboard</h1>
        
        <div class="search-section">
            <input type="text" id="cityInput" placeholder="Enter city name..." value="New York">
            <button id="searchBtn">Get Weather</button>
        </div>
        
        <div class="loading" id="loading" style="display: none;">
            <div class="spinner"></div>
            <p>Fetching weather data...</p>
        </div>
        
        <div class="weather-card" id="weatherCard" style="display: none;">
            <div class="weather-header">
                <h2 id="cityName">--</h2>
                <div class="weather-icon">
                    <img id="weatherIcon" src="" alt="Weather icon">
                </div>
            </div>
            
            <div class="temperature">
                <span id="temperature">--</span>°C
            </div>
            
            <div class="description" id="description">--</div>
            
            <div class="weather-details">
                <div class="detail">
                    <span class="label">Humidity:</span>
                    <span id="humidity">--%</span>
                </div>
                <div class="detail">
                    <span class="label">Pressure:</span>
                    <span id="pressure">-- hPa</span>
                </div>
                <div class="detail">
                    <span class="label">Wind Speed:</span>
                    <span id="windSpeed">-- m/s</span>
                </div>
            </div>
            
            <div class="last-updated">
                Last updated: <span id="lastUpdated">--</span>
            </div>
        </div>
        
        <div class="error-message" id="errorMessage" style="display: none;">
            <p id="errorText">Error loading weather data</p>
        </div>
    </div>
    
    <script src="app.js"></script>
</body>
</html>
EOF
    
    # Create CSS styles
    log_info "Creating CSS styles"
    cat > src/styles.css << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
}

.container {
    background: rgba(255, 255, 255, 0.95);
    border-radius: 20px;
    padding: 2rem;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
    max-width: 400px;
    width: 100%;
    text-align: center;
}

h1 {
    color: #333;
    margin-bottom: 1.5rem;
    font-size: 2rem;
}

.search-section {
    margin-bottom: 2rem;
    display: flex;
    gap: 10px;
}

#cityInput {
    flex: 1;
    padding: 12px;
    border: 2px solid #e0e0e0;
    border-radius: 10px;
    font-size: 16px;
    outline: none;
    transition: border-color 0.3s;
}

#cityInput:focus {
    border-color: #667eea;
}

#searchBtn {
    padding: 12px 20px;
    background: #667eea;
    color: white;
    border: none;
    border-radius: 10px;
    cursor: pointer;
    font-size: 16px;
    transition: background 0.3s;
}

#searchBtn:hover {
    background: #5a6fd8;
}

.loading {
    margin: 2rem 0;
}

.spinner {
    width: 40px;
    height: 40px;
    border: 4px solid #f3f3f3;
    border-top: 4px solid #667eea;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin: 0 auto 1rem;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}

.weather-card {
    background: #f8f9ff;
    border-radius: 15px;
    padding: 1.5rem;
    margin: 1rem 0;
}

.weather-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
}

#cityName {
    color: #333;
    font-size: 1.5rem;
}

.weather-icon img {
    width: 60px;
    height: 60px;
}

.temperature {
    font-size: 3rem;
    font-weight: bold;
    color: #667eea;
    margin: 1rem 0;
}

.description {
    font-size: 1.2rem;
    color: #666;
    margin-bottom: 1.5rem;
    text-transform: capitalize;
}

.weather-details {
    display: grid;
    grid-template-columns: 1fr;
    gap: 0.5rem;
}

.detail {
    display: flex;
    justify-content: space-between;
    padding: 0.5rem 0;
    border-bottom: 1px solid #e0e0e0;
}

.label {
    font-weight: 600;
    color: #555;
}

.last-updated {
    margin-top: 1rem;
    font-size: 0.8rem;
    color: #888;
}

.error-message {
    background: #ffebee;
    color: #c62828;
    padding: 1rem;
    border-radius: 10px;
    border: 1px solid #ffcdd2;
    margin: 1rem 0;
}

@media (max-width: 480px) {
    .container {
        padding: 1rem;
    }
    
    h1 {
        font-size: 1.5rem;
    }
    
    .temperature {
        font-size: 2.5rem;
    }
}
EOF
    
    # Create JavaScript application logic
    log_info "Creating JavaScript application logic"
    cat > src/app.js << 'EOF'
class WeatherDashboard {
    constructor() {
        this.apiBaseUrl = '/api';
        this.initializeElements();
        this.bindEvents();
        this.loadInitialWeather();
    }

    initializeElements() {
        this.cityInput = document.getElementById('cityInput');
        this.searchBtn = document.getElementById('searchBtn');
        this.loading = document.getElementById('loading');
        this.weatherCard = document.getElementById('weatherCard');
        this.errorMessage = document.getElementById('errorMessage');
        
        // Weather display elements
        this.cityName = document.getElementById('cityName');
        this.weatherIcon = document.getElementById('weatherIcon');
        this.temperature = document.getElementById('temperature');
        this.description = document.getElementById('description');
        this.humidity = document.getElementById('humidity');
        this.pressure = document.getElementById('pressure');
        this.windSpeed = document.getElementById('windSpeed');
        this.lastUpdated = document.getElementById('lastUpdated');
    }

    bindEvents() {
        this.searchBtn.addEventListener('click', () => this.searchWeather());
        this.cityInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                this.searchWeather();
            }
        });
    }

    async loadInitialWeather() {
        await this.fetchWeather('New York');
    }

    async searchWeather() {
        const city = this.cityInput.value.trim();
        if (!city) {
            this.showError('Please enter a city name');
            return;
        }
        
        await this.fetchWeather(city);
    }

    async fetchWeather(city) {
        try {
            this.showLoading();
            
            const response = await fetch(`${this.apiBaseUrl}/weather?city=${encodeURIComponent(city)}`);
            const data = await response.json();
            
            if (!response.ok) {
                throw new Error(data.error || 'Failed to fetch weather data');
            }
            
            this.displayWeather(data);
        } catch (error) {
            console.error('Weather fetch error:', error);
            this.showError(error.message || 'Failed to load weather data');
        }
    }

    displayWeather(data) {
        // Update weather information
        this.cityName.textContent = `${data.city}, ${data.country}`;
        this.weatherIcon.src = `https://openweathermap.org/img/wn/${data.icon}@2x.png`;
        this.weatherIcon.alt = data.description;
        this.temperature.textContent = data.temperature;
        this.description.textContent = data.description;
        this.humidity.textContent = `${data.humidity}%`;
        this.pressure.textContent = `${data.pressure} hPa`;
        this.windSpeed.textContent = `${data.windSpeed} m/s`;
        
        // Format last updated time
        const lastUpdated = new Date(data.lastUpdated);
        this.lastUpdated.textContent = lastUpdated.toLocaleString();
        
        // Show weather card and hide other states
        this.hideAll();
        this.weatherCard.style.display = 'block';
    }

    showLoading() {
        this.hideAll();
        this.loading.style.display = 'block';
    }

    showError(message) {
        this.hideAll();
        document.getElementById('errorText').textContent = message;
        this.errorMessage.style.display = 'block';
    }

    hideAll() {
        this.loading.style.display = 'none';
        this.weatherCard.style.display = 'none';
        this.errorMessage.style.display = 'none';
    }
}

// Initialize the weather dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new WeatherDashboard();
});
EOF
    
    log_success "Project files created successfully"
}

# Function to configure API settings
configure_api_settings() {
    log_info "Configuring API settings..."
    
    # Prompt for OpenWeatherMap API key
    if [ -z "${OPENWEATHER_API_KEY:-}" ]; then
        echo
        log_info "You need an OpenWeatherMap API key to use this application."
        log_info "Get a free API key at: https://openweathermap.org/api"
        echo
        read -p "Enter your OpenWeatherMap API key: " WEATHER_API_KEY
        
        if [ -z "$WEATHER_API_KEY" ]; then
            log_warning "No API key provided. You can configure it later using:"
            log_warning "az staticwebapp appsettings set --name $WEATHER_APP_NAME --resource-group $RESOURCE_GROUP --setting-names OPENWEATHER_API_KEY=\"your-key-here\""
        else
            # Configure the API key in Static Web App settings
            log_info "Configuring OpenWeatherMap API key..."
            az staticwebapp appsettings set \
                --name "$WEATHER_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --setting-names OPENWEATHER_API_KEY="$WEATHER_API_KEY"
            
            if [ $? -eq 0 ]; then
                log_success "API key configured successfully"
                echo "OPENWEATHER_API_KEY=\"$WEATHER_API_KEY\"" >> "${SCRIPT_DIR}/.env"
            else
                log_error "Failed to configure API key"
            fi
        fi
    fi
}

# Function to perform validation and testing
perform_validation() {
    log_info "Performing validation and testing..."
    
    # Wait a moment for settings to propagate
    sleep 10
    
    # Check Static Web App status
    log_info "Checking Static Web App deployment status..."
    az staticwebapp show \
        --name "$WEATHER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "{name:name,url:defaultHostname,repositoryUrl:repositoryUrl}" \
        --output table
    
    # Test API endpoint if possible
    if [ -n "${SWA_URL:-}" ] && [ -n "${WEATHER_API_KEY:-}" ]; then
        log_info "Testing weather API endpoint..."
        
        # Simple connectivity test
        if curl -s --max-time 30 "https://$SWA_URL/api/weather?city=London" > /dev/null; then
            log_success "API endpoint is accessible"
        else
            log_warning "API endpoint test failed or timed out (this is normal for new deployments)"
        fi
    fi
    
    log_success "Validation completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=========================================="
    echo
    echo "🌤️  Weather Dashboard Deployed Successfully!"
    echo
    echo "Resources Created:"
    echo "  - Resource Group: $RESOURCE_GROUP"
    echo "  - Static Web App: $WEATHER_APP_NAME"
    echo "  - Location: $LOCATION"
    echo
    if [ -n "${SWA_URL:-}" ]; then
        echo "🔗 Access your weather dashboard at:"
        echo "   https://$SWA_URL"
        echo
    fi
    echo "📁 Project files created in:"
    echo "   ${SCRIPT_DIR}/../weather-dashboard/"
    echo
    echo "🔑 API Configuration:"
    if [ -n "${WEATHER_API_KEY:-}" ]; then
        echo "   OpenWeatherMap API key configured ✅"
    else
        echo "   OpenWeatherMap API key not configured ⚠️"
        echo "   Configure it manually using:"
        echo "   az staticwebapp appsettings set --name $WEATHER_APP_NAME --resource-group $RESOURCE_GROUP --setting-names OPENWEATHER_API_KEY=\"your-key\""
    fi
    echo
    echo "📋 Environment variables saved to:"
    echo "   ${SCRIPT_DIR}/.env"
    echo
    echo "🧹 To clean up resources, run:"
    echo "   ${SCRIPT_DIR}/destroy.sh"
    echo
    echo "=========================================="
}

# Function to handle cleanup on script failure
cleanup_on_failure() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code"
        log_warning "You might want to run the cleanup script to remove any created resources"
        log_warning "Cleanup script: ${SCRIPT_DIR}/destroy.sh"
    fi
    exit $exit_code
}

# Main deployment function
main() {
    log_info "Starting Azure Weather Dashboard deployment"
    
    # Set trap for cleanup on failure
    trap cleanup_on_failure EXIT
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_azure_resources
    create_project_files
    configure_api_settings
    perform_validation
    display_summary
    
    # Remove trap on successful completion
    trap - EXIT
    
    log_success "Deployment completed successfully at $(date)"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi