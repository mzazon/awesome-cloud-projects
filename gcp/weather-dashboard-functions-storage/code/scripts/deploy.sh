#!/bin/bash

##############################################################################
# Weather Dashboard with Cloud Functions and Storage - Deployment Script
# 
# This script deploys a complete serverless weather dashboard using:
# - Google Cloud Functions for weather API proxy
# - Google Cloud Storage for static website hosting
# 
# Prerequisites:
# - Google Cloud SDK (gcloud) installed and authenticated
# - OpenWeatherMap API key
# - Appropriate GCP permissions (Cloud Functions Developer, Storage Admin)
##############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-weather-dashboard-$(date +%s)}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-weather-api}"
BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-weather-dashboard}"
WEATHER_API_KEY="${WEATHER_API_KEY:-}"

##############################################################################
# Utility Functions
##############################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy a serverless weather dashboard on Google Cloud Platform.

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (default: auto-generated)
    -r, --region REGION             GCP Region (default: us-central1)
    -f, --function-name NAME        Cloud Function name (default: weather-api)
    -b, --bucket-name NAME          Storage bucket name (default: auto-generated)
    -k, --weather-api-key KEY       OpenWeatherMap API key (required)
    -h, --help                      Show this help message
    --dry-run                       Show what would be deployed without actually deploying
    --skip-project-creation         Skip project creation (use existing project)

EXAMPLES:
    $0 --weather-api-key "your-api-key-here"
    $0 --project-id "my-project" --weather-api-key "your-api-key-here"
    $0 --dry-run --weather-api-key "your-api-key-here"

ENVIRONMENT VARIABLES:
    PROJECT_ID                      GCP Project ID
    REGION                          GCP Region
    FUNCTION_NAME                   Cloud Function name
    BUCKET_NAME                     Storage bucket name
    WEATHER_API_KEY                 OpenWeatherMap API key (required)

EOF
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log "ERROR" "Google Cloud SDK (gcloud) is not installed or not in PATH"
        log "INFO" "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log "ERROR" "Not authenticated with Google Cloud"
        log "INFO" "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if required APIs can be enabled (will be done later)
    local current_user=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
    log "INFO" "Authenticated as: $current_user"
    
    # Check for required tools
    local missing_tools=()
    for tool in curl jq openssl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "ERROR" "Missing required tools: ${missing_tools[*]}"
        log "INFO" "Please install the missing tools and try again"
        exit 1
    fi
    
    # Validate OpenWeatherMap API key
    if [ -z "$WEATHER_API_KEY" ]; then
        log "ERROR" "OpenWeatherMap API key is required"
        log "INFO" "Get a free API key from: https://openweathermap.org/api"
        log "INFO" "Set via --weather-api-key option or WEATHER_API_KEY environment variable"
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

save_deployment_state() {
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
PROJECT_ID="$PROJECT_ID"
REGION="$REGION"
FUNCTION_NAME="$FUNCTION_NAME"
BUCKET_NAME="$BUCKET_NAME"
DEPLOYMENT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DEPLOYED_BY="$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)"
EOF
    log "INFO" "Deployment state saved to: $DEPLOYMENT_STATE_FILE"
}

load_deployment_state() {
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        source "$DEPLOYMENT_STATE_FILE"
        log "INFO" "Loaded existing deployment state"
        return 0
    fi
    return 1
}

create_or_configure_project() {
    if [ "$SKIP_PROJECT_CREATION" = "true" ]; then
        log "INFO" "Skipping project creation, using existing project: $PROJECT_ID"
        gcloud config set project "$PROJECT_ID"
    else
        log "INFO" "Creating GCP project: $PROJECT_ID"
        
        # Check if project already exists
        if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            log "WARN" "Project $PROJECT_ID already exists, using existing project"
        else
            # Create new project
            if ! gcloud projects create "$PROJECT_ID" --name="Weather Dashboard"; then
                log "ERROR" "Failed to create project $PROJECT_ID"
                exit 1
            fi
            log "INFO" "Project $PROJECT_ID created successfully"
        fi
        
        gcloud config set project "$PROJECT_ID"
    fi
    
    gcloud config set compute/region "$REGION"
    log "INFO" "Project configuration completed"
}

enable_apis() {
    log "INFO" "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "INFO" "Enabling $api..."
        if ! gcloud services enable "$api" --quiet; then
            log "ERROR" "Failed to enable API: $api"
            exit 1
        fi
    done
    
    log "INFO" "Waiting for APIs to be fully enabled..."
    sleep 30  # Allow time for APIs to be fully enabled
    
    log "INFO" "All required APIs enabled successfully"
}

create_function_code() {
    log "INFO" "Creating Cloud Function source code..."
    
    local function_dir="${PROJECT_ROOT}/function-source"
    mkdir -p "$function_dir"
    
    # Create main.py
    cat > "${function_dir}/main.py" << 'EOF'
import functions_framework
import requests
import json
import os
from flask import jsonify

@functions_framework.http
def get_weather(request):
    """HTTP Cloud Function to fetch weather data."""
    
    # Enable CORS for browser requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual request
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    try:
        # Get city from query parameter, default to San Francisco
        city = request.args.get('city', 'San Francisco')
        api_key = os.environ.get('WEATHER_API_KEY')
        
        if not api_key:
            return jsonify({'error': 'API key not configured'}), 500
        
        # Call OpenWeatherMap API using city name query
        url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={api_key}&units=imperial"
        response = requests.get(url, timeout=10)
        
        if response.status_code == 200:
            weather_data = response.json()
            
            # Transform data for frontend
            simplified_data = {
                'city': weather_data['name'],
                'country': weather_data['sys']['country'],
                'temperature': round(weather_data['main']['temp']),
                'description': weather_data['weather'][0]['description'].title(),
                'humidity': weather_data['main']['humidity'],
                'pressure': weather_data['main']['pressure'],
                'wind_speed': weather_data['wind']['speed'],
                'icon': weather_data['weather'][0]['icon'],
                'timestamp': weather_data['dt']
            }
            
            return (jsonify(simplified_data), 200, headers)
        else:
            return (jsonify({'error': 'Weather data not found'}), 404, headers)
            
    except Exception as e:
        return (jsonify({'error': str(e)}), 500, headers)
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
requests==2.*
flask==2.*
EOF
    
    log "INFO" "Cloud Function source code created in: $function_dir"
}

deploy_cloud_function() {
    log "INFO" "Deploying Cloud Function: $FUNCTION_NAME"
    
    local function_dir="${PROJECT_ROOT}/function-source"
    
    # Deploy the function
    if ! gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime python311 \
        --region "$REGION" \
        --source "$function_dir" \
        --entry-point get_weather \
        --trigger-http \
        --allow-unauthenticated \
        --set-env-vars "WEATHER_API_KEY=$WEATHER_API_KEY" \
        --memory 256Mi \
        --timeout 60s \
        --quiet; then
        log "ERROR" "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    if [ -z "$function_url" ]; then
        log "ERROR" "Failed to get function URL"
        exit 1
    fi
    
    log "INFO" "Cloud Function deployed successfully"
    log "INFO" "Function URL: $function_url"
    
    # Save function URL for website creation
    echo "$function_url" > "${PROJECT_ROOT}/function_url.txt"
}

create_storage_bucket() {
    log "INFO" "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    # Create bucket
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        # Check if bucket already exists
        if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
            log "WARN" "Bucket $BUCKET_NAME already exists, using existing bucket"
        else
            log "ERROR" "Failed to create bucket $BUCKET_NAME"
            exit 1
        fi
    fi
    
    # Enable public access
    if ! gsutil iam ch allUsers:objectViewer "gs://$BUCKET_NAME"; then
        log "ERROR" "Failed to enable public access for bucket"
        exit 1
    fi
    
    # Configure for static website hosting
    if ! gsutil web set -m index.html -e 404.html "gs://$BUCKET_NAME"; then
        log "ERROR" "Failed to configure bucket for static website hosting"
        exit 1
    fi
    
    log "INFO" "Storage bucket created and configured successfully"
}

create_website_files() {
    log "INFO" "Creating website files..."
    
    local website_dir="${PROJECT_ROOT}/website"
    mkdir -p "$website_dir"
    
    # Get function URL
    local function_url
    if [ -f "${PROJECT_ROOT}/function_url.txt" ]; then
        function_url=$(cat "${PROJECT_ROOT}/function_url.txt")
    else
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(serviceConfig.uri)")
    fi
    
    # Create index.html
    cat > "${website_dir}/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Weather Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #74b9ff, #0984e3);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .dashboard {
            background: rgba(255, 255, 255, 0.9);
            border-radius: 20px;
            padding: 2rem;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            backdrop-filter: blur(10px);
            max-width: 500px;
            width: 90%;
        }
        
        .header {
            text-align: center;
            margin-bottom: 2rem;
        }
        
        .header h1 {
            color: #2d3436;
            margin-bottom: 1rem;
        }
        
        .search-box {
            display: flex;
            margin-bottom: 2rem;
        }
        
        .search-box input {
            flex: 1;
            padding: 12px;
            border: 2px solid #ddd;
            border-radius: 10px 0 0 10px;
            font-size: 16px;
            outline: none;
        }
        
        .search-box button {
            padding: 12px 20px;
            background: #0984e3;
            color: white;
            border: none;
            border-radius: 0 10px 10px 0;
            cursor: pointer;
            font-size: 16px;
        }
        
        .weather-info {
            text-align: center;
            display: none;
        }
        
        .temperature {
            font-size: 4rem;
            font-weight: bold;
            color: #2d3436;
            margin: 1rem 0;
        }
        
        .description {
            font-size: 1.5rem;
            color: #636e72;
            margin-bottom: 2rem;
        }
        
        .details {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1rem;
            margin-top: 2rem;
        }
        
        .detail-item {
            background: rgba(116, 185, 255, 0.1);
            padding: 1rem;
            border-radius: 10px;
            text-align: center;
        }
        
        .detail-label {
            font-size: 0.9rem;
            color: #636e72;
            margin-bottom: 0.5rem;
        }
        
        .detail-value {
            font-size: 1.2rem;
            font-weight: bold;
            color: #2d3436;
        }
        
        .loading {
            text-align: center;
            padding: 2rem;
            display: none;
        }
        
        .error {
            background: #ff6b6b;
            color: white;
            padding: 1rem;
            border-radius: 10px;
            margin: 1rem 0;
            display: none;
        }
    </style>
</head>
<body>
    <div class="dashboard">
        <div class="header">
            <h1>🌤️ Weather Dashboard</h1>
        </div>
        
        <div class="search-box">
            <input type="text" id="cityInput" placeholder="Enter city name..." value="San Francisco">
            <button onclick="getWeather()">Get Weather</button>
        </div>
        
        <div class="loading" id="loading">
            <p>Loading weather data...</p>
        </div>
        
        <div class="error" id="error"></div>
        
        <div class="weather-info" id="weatherInfo">
            <div class="temperature" id="temperature"></div>
            <div class="description" id="description"></div>
            <div class="city" id="cityName"></div>
            
            <div class="details">
                <div class="detail-item">
                    <div class="detail-label">Humidity</div>
                    <div class="detail-value" id="humidity"></div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Pressure</div>
                    <div class="detail-value" id="pressure"></div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Wind Speed</div>
                    <div class="detail-value" id="windSpeed"></div>
                </div>
                <div class="detail-item">
                    <div class="detail-label">Last Updated</div>
                    <div class="detail-value" id="timestamp"></div>
                </div>
            </div>
        </div>
    </div>

    <script>
        const FUNCTION_URL = '$function_url';
        
        async function getWeather() {
            const city = document.getElementById('cityInput').value;
            const loading = document.getElementById('loading');
            const error = document.getElementById('error');
            const weatherInfo = document.getElementById('weatherInfo');
            
            // Show loading state
            loading.style.display = 'block';
            error.style.display = 'none';
            weatherInfo.style.display = 'none';
            
            try {
                const response = await fetch(\`\${FUNCTION_URL}?city=\${encodeURIComponent(city)}\`);
                const data = await response.json();
                
                if (response.ok) {
                    displayWeather(data);
                } else {
                    showError(data.error || 'Failed to fetch weather data');
                }
            } catch (err) {
                showError('Network error: Please check your connection');
            } finally {
                loading.style.display = 'none';
            }
        }
        
        function displayWeather(data) {
            document.getElementById('temperature').textContent = \`\${data.temperature}°F\`;
            document.getElementById('description').textContent = data.description;
            document.getElementById('cityName').textContent = \`\${data.city}, \${data.country}\`;
            document.getElementById('humidity').textContent = \`\${data.humidity}%\`;
            document.getElementById('pressure').textContent = \`\${data.pressure} hPa\`;
            document.getElementById('windSpeed').textContent = \`\${data.wind_speed} mph\`;
            document.getElementById('timestamp').textContent = new Date().toLocaleTimeString();
            
            document.getElementById('weatherInfo').style.display = 'block';
        }
        
        function showError(message) {
            const errorDiv = document.getElementById('error');
            errorDiv.textContent = message;
            errorDiv.style.display = 'block';
        }
        
        // Allow Enter key to trigger search
        document.getElementById('cityInput').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                getWeather();
            }
        });
        
        // Load default weather on page load
        window.onload = function() {
            getWeather();
        };
    </script>
</body>
</html>
EOF
    
    # Create 404.html
    cat > "${website_dir}/404.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - Weather Dashboard</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #74b9ff, #0984e3);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0;
        }
        
        .error-container {
            background: rgba(255, 255, 255, 0.9);
            border-radius: 20px;
            padding: 3rem;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            backdrop-filter: blur(10px);
        }
        
        .error-code {
            font-size: 6rem;
            font-weight: bold;
            color: #ff6b6b;
            margin-bottom: 1rem;
        }
        
        .error-message {
            font-size: 1.5rem;
            color: #2d3436;
            margin-bottom: 2rem;
        }
        
        .back-button {
            background: #0984e3;
            color: white;
            padding: 12px 24px;
            border: none;
            border-radius: 10px;
            font-size: 1rem;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
        }
    </style>
</head>
<body>
    <div class="error-container">
        <div class="error-code">404</div>
        <div class="error-message">Oops! The weather page you're looking for doesn't exist.</div>
        <a href="/" class="back-button">Return to Weather Dashboard</a>
    </div>
</body>
</html>
EOF
    
    log "INFO" "Website files created in: $website_dir"
}

upload_website_files() {
    log "INFO" "Uploading website files to Cloud Storage..."
    
    local website_dir="${PROJECT_ROOT}/website"
    
    # Upload files
    if ! gsutil -m cp -r "${website_dir}/"*.html "gs://$BUCKET_NAME/"; then
        log "ERROR" "Failed to upload website files"
        exit 1
    fi
    
    # Set proper content types
    if ! gsutil -m setmeta -h "Content-Type:text/html" "gs://$BUCKET_NAME/"*.html; then
        log "ERROR" "Failed to set content types"
        exit 1
    fi
    
    log "INFO" "Website files uploaded successfully"
}

verify_deployment() {
    log "INFO" "Verifying deployment..."
    
    # Test Cloud Function
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    log "INFO" "Testing Cloud Function..."
    if curl -s "$function_url?city=London" > /dev/null; then
        log "INFO" "✅ Cloud Function is responding"
    else
        log "WARN" "⚠️  Cloud Function test failed, but deployment may still be successful"
    fi
    
    # Test website
    local website_url="https://storage.googleapis.com/$BUCKET_NAME/index.html"
    log "INFO" "Testing website..."
    if curl -s -I "$website_url" | grep -q "200 OK"; then
        log "INFO" "✅ Website is accessible"
    else
        log "WARN" "⚠️  Website test failed, but deployment may still be successful"
    fi
    
    log "INFO" "Deployment verification completed"
}

show_deployment_summary() {
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "N/A")
    
    local website_url="https://storage.googleapis.com/$BUCKET_NAME/index.html"
    
    cat << EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}                          DEPLOYMENT SUCCESSFUL!                             ${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

📊 Weather Dashboard Deployed Successfully

🔗 Access Your Dashboard:
   ${BLUE}$website_url${NC}

🔧 Resources Created:
   • Project ID:         $PROJECT_ID
   • Region:             $REGION
   • Cloud Function:     $FUNCTION_NAME
   • Function URL:       $function_url
   • Storage Bucket:     $BUCKET_NAME
   • Website URL:        $website_url

📝 Next Steps:
   1. Visit your weather dashboard at the website URL above
   2. Test different cities in the search box
   3. Monitor function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION
   4. Check costs in the GCP Console billing section

🗑️  To clean up all resources:
   $SCRIPT_DIR/destroy.sh

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF
}

cleanup_on_error() {
    log "ERROR" "Deployment failed, cleaning up partial resources..."
    
    # Try to clean up any resources that were created
    if [ -n "${FUNCTION_NAME:-}" ]; then
        gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --quiet 2>/dev/null || true
    fi
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        gsutil -m rm -r "gs://$BUCKET_NAME" 2>/dev/null || true
    fi
    
    log "INFO" "Partial cleanup completed"
    exit 1
}

##############################################################################
# Main Deployment Logic
##############################################################################

main() {
    # Initialize logging
    echo "=== Weather Dashboard Deployment Started at $(date) ===" >> "$LOG_FILE"
    
    # Parse command line arguments
    local dry_run=false
    SKIP_PROJECT_CREATION=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -k|--weather-api-key)
                WEATHER_API_KEY="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-project-creation)
                SKIP_PROJECT_CREATION=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    log "INFO" "Starting Weather Dashboard deployment..."
    log "INFO" "Project ID: $PROJECT_ID"
    log "INFO" "Region: $REGION"
    log "INFO" "Function Name: $FUNCTION_NAME"
    log "INFO" "Bucket Name: $BUCKET_NAME"
    
    if [ "$dry_run" = true ]; then
        log "INFO" "DRY RUN MODE - No resources will be created"
        log "INFO" "Would deploy weather dashboard with above configuration"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    create_or_configure_project
    enable_apis
    create_function_code
    deploy_cloud_function
    create_storage_bucket
    create_website_files
    upload_website_files
    verify_deployment
    save_deployment_state
    
    # Show success summary
    show_deployment_summary
    
    log "INFO" "Weather Dashboard deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"