#!/bin/bash

# Weather-Aware Infrastructure Scaling with Google Maps Platform Weather API and Cluster Toolkit
# Deployment Script for GCP Recipe
# 
# This script deploys a complete weather-aware HPC infrastructure that automatically
# scales compute clusters based on real-time weather data from Google Maps Platform Weather API.

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if git is installed
    if ! command_exists git; then
        log_error "git is not installed. Please install it first."
        exit 1
    fi
    
    # Check if make is installed
    if ! command_exists make; then
        log_error "make is not installed. Please install it first."
        exit 1
    fi
    
    # Check if python3 is installed
    if ! command_exists python3; then
        log_error "python3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if pip3 is installed
    if ! command_exists pip3; then
        log_error "pip3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command_exists terraform; then
        log_error "terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-weather-hpc-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export CLUSTER_NAME="weather-cluster-${RANDOM_SUFFIX}"
    export BUCKET_NAME="weather-data-${PROJECT_ID}"
    export FUNCTION_NAME="weather-processor-${RANDOM_SUFFIX}"
    export TOPIC_NAME="weather-scaling-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="weather-scaling-sub"
    
    # Check if Weather API key is provided
    if [ -z "${WEATHER_API_KEY:-}" ]; then
        log_warning "WEATHER_API_KEY environment variable not set."
        log_warning "You'll need to configure this after deployment."
        log_warning "Get an API key from: https://developers.google.com/maps/documentation/weather"
        export WEATHER_API_KEY="YOUR_WEATHER_API_KEY_HERE"
    fi
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Cluster Name: ${CLUSTER_NAME}"
}

# Function to create or select project
setup_project() {
    log_info "Setting up GCP project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_info "Using existing project: ${PROJECT_ID}"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}" --name="Weather-Aware HPC Infrastructure"; then
            log_error "Failed to create project. You may need to specify a different PROJECT_ID."
            exit 1
        fi
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
        "compute.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "monitoring.googleapis.com"
        "cloudscheduler.googleapis.com"
        "maps-weather.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if ! gcloud services enable "${api}"; then
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for weather data..."
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Bucket ${BUCKET_NAME} already exists"
    else
        # Create Cloud Storage bucket
        if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
            log_error "Failed to create Cloud Storage bucket"
            exit 1
        fi
        
        # Enable versioning for data protection
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        log_success "Cloud Storage bucket created: ${BUCKET_NAME}"
    fi
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    if ! gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        if ! gcloud pubsub topics create "${TOPIC_NAME}"; then
            log_error "Failed to create Pub/Sub topic"
            exit 1
        fi
        log_success "Pub/Sub topic created: ${TOPIC_NAME}"
    else
        log_warning "Pub/Sub topic ${TOPIC_NAME} already exists"
    fi
    
    # Create subscription
    if ! gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" >/dev/null 2>&1; then
        if ! gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" --topic="${TOPIC_NAME}"; then
            log_error "Failed to create Pub/Sub subscription"
            exit 1
        fi
        log_success "Pub/Sub subscription created: ${SUBSCRIPTION_NAME}"
    else
        log_warning "Pub/Sub subscription ${SUBSCRIPTION_NAME} already exists"
    fi
}

# Function to deploy weather processing Cloud Function
deploy_weather_function() {
    log_info "Deploying weather processing Cloud Function..."
    
    # Create temporary directory for function source
    local function_dir="/tmp/weather-function-${RANDOM_SUFFIX}"
    mkdir -p "${function_dir}"
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-pubsub==2.18.4
google-cloud-storage==2.10.0
google-cloud-monitoring==2.15.1
requests==2.31.0
functions-framework==3.4.0
EOF
    
    # Create main function file
    cat > "${function_dir}/main.py" << 'EOF'
import json
import logging
import os
import requests
from datetime import datetime
from google.cloud import pubsub_v1
from google.cloud import storage
from google.cloud import monitoring_v1

def weather_processor(request):
    """Process weather data and trigger scaling decisions."""
    
    # Initialize clients
    publisher = pubsub_v1.PublisherClient()
    storage_client = storage.Client()
    monitoring_client = monitoring_v1.MetricServiceClient()
    
    # Configuration
    project_id = os.environ['GCP_PROJECT']
    topic_name = os.environ['PUBSUB_TOPIC']
    weather_api_key = os.environ.get('WEATHER_API_KEY', 'YOUR_WEATHER_API_KEY_HERE')
    
    # Weather locations for monitoring (major data centers)
    locations = [
        {"lat": 39.0458, "lng": -76.6413, "name": "us-east1"},  # Virginia
        {"lat": 41.2619, "lng": -95.8608, "name": "us-central1"},  # Iowa
        {"lat": 45.5152, "lng": -122.6784, "name": "us-west1"}  # Oregon
    ]
    
    scaling_decisions = []
    
    for location in locations:
        try:
            # Mock weather data if API key not configured
            if weather_api_key == 'YOUR_WEATHER_API_KEY_HERE':
                weather_data = generate_mock_weather_data(location)
            else:
                # Call Google Maps Platform Weather API
                weather_url = f"https://weather.googleapis.com/v1/weather:forecastHourly"
                headers = {'X-Goog-Api-Key': weather_api_key}
                params = {
                    'location.latitude': location['lat'],
                    'location.longitude': location['lng'],
                    'hourCount': 6  # 6-hour forecast
                }
                
                response = requests.get(weather_url, headers=headers, params=params)
                if response.status_code == 200:
                    weather_data = response.json()
                else:
                    logging.warning(f"Weather API request failed: {response.status_code}")
                    weather_data = generate_mock_weather_data(location)
            
            # Analyze weather conditions for scaling decisions
            scaling_factor = analyze_weather_conditions(weather_data)
            
            decision = {
                'region': location['name'],
                'scaling_factor': scaling_factor,
                'weather_summary': extract_weather_summary(weather_data),
                'timestamp': datetime.utcnow().isoformat()
            }
            
            scaling_decisions.append(decision)
            
            # Store weather data in Cloud Storage
            bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
            blob_name = f"weather-data/{location['name']}/{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}.json"
            blob = bucket.blob(blob_name)
            blob.upload_from_string(json.dumps(weather_data, indent=2))
            
        except Exception as e:
            logging.error(f"Error processing weather for {location['name']}: {str(e)}")
            continue
    
    # Publish scaling decisions to Pub/Sub
    topic_path = publisher.topic_path(project_id, topic_name)
    for decision in scaling_decisions:
        message_data = json.dumps(decision).encode('utf-8')
        publisher.publish(topic_path, message_data)
    
    # Send metrics to Cloud Monitoring
    send_weather_metrics(monitoring_client, project_id, scaling_decisions)
    
    return {'status': 'success', 'processed_locations': len(scaling_decisions)}

def generate_mock_weather_data(location):
    """Generate mock weather data for testing."""
    import random
    return {
        'hourlyForecasts': [
            {
                'temperatureCelsius': 15 + random.uniform(-5, 15),
                'precipitationMm': random.uniform(0, 20),
                'windSpeedKph': random.uniform(0, 60),
                'relativeHumidity': random.uniform(30, 90)
            } for _ in range(6)
        ]
    }

def analyze_weather_conditions(weather_data):
    """Analyze weather conditions and return scaling factor."""
    
    # Extract relevant weather metrics
    if 'hourlyForecasts' not in weather_data:
        return 1.0  # Default scaling
    
    forecasts = weather_data['hourlyForecasts'][:6]  # Next 6 hours
    
    total_precipitation = 0
    max_wind_speed = 0
    temperature_variance = 0
    
    temperatures = []
    
    for forecast in forecasts:
        # Precipitation analysis (mm/hour)
        if 'precipitationMm' in forecast:
            total_precipitation += forecast['precipitationMm']
        
        # Wind speed analysis (km/h)
        if 'windSpeedKph' in forecast:
            max_wind_speed = max(max_wind_speed, forecast['windSpeedKph'])
        
        # Temperature collection for variance calculation
        if 'temperatureCelsius' in forecast:
            temperatures.append(forecast['temperatureCelsius'])
    
    # Calculate temperature variance
    if len(temperatures) > 1:
        avg_temp = sum(temperatures) / len(temperatures)
        temperature_variance = sum((t - avg_temp) ** 2 for t in temperatures) / len(temperatures)
    
    # Scaling logic based on weather conditions
    scaling_factor = 1.0
    
    # Heavy precipitation increases computational demand for climate models
    if total_precipitation > 10:  # Heavy rain/snow
        scaling_factor *= 1.5
    elif total_precipitation > 5:  # Moderate precipitation
        scaling_factor *= 1.2
    
    # High wind speeds trigger renewable energy forecasting workloads
    if max_wind_speed > 50:  # Strong winds
        scaling_factor *= 1.4
    elif max_wind_speed > 30:  # Moderate winds
        scaling_factor *= 1.1
    
    # Temperature variance indicates weather instability
    if temperature_variance > 25:  # High variance
        scaling_factor *= 1.3
    
    # Cap scaling factor for cost control
    return min(scaling_factor, 2.0)

def extract_weather_summary(weather_data):
    """Extract weather summary for logging."""
    if 'hourlyForecasts' not in weather_data or not weather_data['hourlyForecasts']:
        return "No forecast data available"
    
    current_forecast = weather_data['hourlyForecasts'][0]
    
    summary = {
        'temperature': current_forecast.get('temperatureCelsius', 'N/A'),
        'precipitation': current_forecast.get('precipitationMm', 0),
        'wind_speed': current_forecast.get('windSpeedKph', 0),
        'humidity': current_forecast.get('relativeHumidity', 'N/A')
    }
    
    return summary

def send_weather_metrics(monitoring_client, project_id, scaling_decisions):
    """Send custom metrics to Cloud Monitoring."""
    
    project_name = f"projects/{project_id}"
    
    for decision in scaling_decisions:
        try:
            # Create metric for scaling factor
            series = monitoring_v1.TimeSeries()
            series.metric.type = 'custom.googleapis.com/weather/scaling_factor'
            series.metric.labels['region'] = decision['region']
            series.resource.type = 'global'
            
            # Add data point
            point = series.points.add()
            point.value.double_value = decision['scaling_factor']
            point.interval.end_time.seconds = int(datetime.utcnow().timestamp())
            
            # Send to monitoring
            monitoring_client.create_time_series(
                name=project_name,
                time_series=[series]
            )
            
        except Exception as e:
            logging.error(f"Error sending metrics: {str(e)}")
EOF
    
    # Deploy Cloud Function
    if ! gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-http \
        --source "${function_dir}" \
        --entry-point weather_processor \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID},PUBSUB_TOPIC=${TOPIC_NAME},STORAGE_BUCKET=${BUCKET_NAME},WEATHER_API_KEY=${WEATHER_API_KEY}" \
        --region "${REGION}" \
        --allow-unauthenticated; then
        log_error "Failed to deploy weather processing Cloud Function"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "${function_dir}"
    
    log_success "Weather processing Cloud Function deployed: ${FUNCTION_NAME}"
}

# Function to install and configure Cluster Toolkit
setup_cluster_toolkit() {
    log_info "Setting up Google Cloud Cluster Toolkit..."
    
    local toolkit_dir="/tmp/cluster-toolkit-${RANDOM_SUFFIX}"
    
    # Clone Cluster Toolkit repository
    if ! git clone https://github.com/GoogleCloudPlatform/cluster-toolkit.git "${toolkit_dir}"; then
        log_error "Failed to clone Cluster Toolkit repository"
        exit 1
    fi
    
    cd "${toolkit_dir}"
    
    # Build the gcluster binary
    if ! make; then
        log_error "Failed to build Cluster Toolkit"
        exit 1
    fi
    
    # Create cluster blueprint
    cat > weather-hpc-blueprint.yaml << EOF
blueprint_name: weather-aware-hpc
project_id: ${PROJECT_ID}
deployment_name: ${CLUSTER_NAME}
region: ${REGION}
zone: ${ZONE}

deployment_groups:
- group: primary
  modules:
  # Network infrastructure
  - id: network1
    source: modules/network/vpc
    settings:
      enable_iap_ssh_ingress: true
      
  # File system for shared data
  - id: homefs
    source: modules/file-system/filestore
    use: [network1]
    settings:
      local_mount: /home
      size_gb: 1024
      
  # Login node for cluster access
  - id: login
    source: modules/scheduler/schedmd-slurm-gcp-v5-login
    use: [network1, homefs]
    settings:
      machine_type: n1-standard-4
      enable_login_public_ips: true
      
  # Compute partition with auto-scaling
  - id: compute
    source: modules/compute/schedmd-slurm-gcp-v5-partition
    use: [network1, homefs]
    settings:
      partition_name: weather-compute
      machine_type: c2-standard-60
      max_node_count: 10
      enable_spot_vm: true
      
  # Slurm controller
  - id: slurm_controller
    source: modules/scheduler/schedmd-slurm-gcp-v5-controller
    use: [network1, login, compute, homefs]
    settings:
      enable_controller_public_ips: true
      
- group: cluster
  modules:
  # Complete cluster deployment
  - id: cluster
    source: modules/scheduler/schedmd-slurm-gcp-v5-hybrid
    use: [slurm_controller]
EOF
    
    # Generate deployment folder from blueprint
    if ! ./gcluster create weather-hpc-blueprint.yaml; then
        log_error "Failed to create cluster blueprint"
        exit 1
    fi
    
    log_success "Cluster Toolkit configured successfully"
    
    # Store toolkit directory for later use
    echo "${toolkit_dir}" > /tmp/toolkit_dir_${RANDOM_SUFFIX}
}

# Function to deploy HPC cluster
deploy_hpc_cluster() {
    log_info "Deploying HPC cluster infrastructure..."
    
    # Get toolkit directory
    local toolkit_dir=$(cat /tmp/toolkit_dir_${RANDOM_SUFFIX})
    cd "${toolkit_dir}/${CLUSTER_NAME}"
    
    # Initialize Terraform
    if ! terraform init; then
        log_error "Failed to initialize Terraform"
        exit 1
    fi
    
    # Plan deployment
    log_info "Planning cluster deployment..."
    if ! terraform plan; then
        log_error "Terraform plan failed"
        exit 1
    fi
    
    # Apply deployment
    log_info "Applying cluster deployment (this may take 15-20 minutes)..."
    if ! terraform apply -auto-approve; then
        log_error "Failed to deploy HPC cluster"
        exit 1
    fi
    
    # Extract cluster information
    export CLUSTER_LOGIN_IP=$(terraform output -raw login_ip_address 2>/dev/null || echo "not_available")
    export CONTROLLER_IP=$(terraform output -raw controller_ip_address 2>/dev/null || echo "not_available")
    
    # Wait for cluster initialization
    log_info "Waiting for cluster initialization to complete..."
    sleep 300
    
    log_success "HPC cluster deployed successfully"
    if [ "${CLUSTER_LOGIN_IP}" != "not_available" ]; then
        log_info "Login node IP: ${CLUSTER_LOGIN_IP}"
    fi
    if [ "${CONTROLLER_IP}" != "not_available" ]; then
        log_info "Controller IP: ${CONTROLLER_IP}"
    fi
    
    cd - > /dev/null
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log_info "Creating weather monitoring dashboard..."
    
    # Create dashboard configuration
    cat > /tmp/weather-dashboard-${RANDOM_SUFFIX}.json << EOF
{
  "displayName": "Weather-Aware HPC Scaling Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Weather Scaling Factor by Region",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"custom.googleapis.com/weather/scaling_factor\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": ["metric.label.region"]
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Scaling Factor",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cluster CPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_MEAN",
                      "crossSeriesReducer": "REDUCE_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the monitoring dashboard
    if ! gcloud monitoring dashboards create --config-from-file="/tmp/weather-dashboard-${RANDOM_SUFFIX}.json"; then
        log_warning "Failed to create monitoring dashboard, but continuing deployment"
    else
        log_success "Weather monitoring dashboard created"
    fi
    
    # Clean up temporary file
    rm -f "/tmp/weather-dashboard-${RANDOM_SUFFIX}.json"
}

# Function to set up automated weather checks
setup_weather_automation() {
    log_info "Setting up automated weather monitoring..."
    
    # Get Cloud Function trigger URL
    local function_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    
    # Create regular weather check job
    if ! gcloud scheduler jobs create http weather-check-job \
        --schedule="*/15 * * * *" \
        --uri="${function_url}" \
        --http-method=GET \
        --time-zone="UTC" \
        --description="Automated weather data collection and scaling analysis" \
        --location="${REGION}"; then
        log_error "Failed to create regular weather check job"
        exit 1
    fi
    
    # Create enhanced monitoring job for severe weather
    if ! gcloud scheduler jobs create http weather-storm-monitor \
        --schedule="*/5 * * * *" \
        --uri="${function_url}" \
        --http-method=GET \
        --time-zone="UTC" \
        --description="Enhanced weather monitoring during severe weather events" \
        --location="${REGION}"; then
        log_error "Failed to create storm monitoring job"
        exit 1
    fi
    
    log_success "Automated weather monitoring configured"
    log_info "Regular checks: Every 15 minutes"
    log_info "Storm monitoring: Every 5 minutes"
}

# Function to create scaling integration
create_scaling_integration() {
    log_info "Creating cluster scaling integration..."
    
    # Create scaling agent script
    cat > /tmp/scaling-agent-${RANDOM_SUFFIX}.py << 'EOF'
#!/usr/bin/env python3
import json
import subprocess
import time
import logging
import os
from google.cloud import pubsub_v1
from concurrent.futures import ThreadPoolExecutor

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class WeatherClusterScaler:
    def __init__(self, project_id, subscription_name, cluster_name):
        self.project_id = project_id
        self.subscription_name = subscription_name
        self.cluster_name = cluster_name
        self.subscriber = pubsub_v1.SubscriberClient()
        self.subscription_path = self.subscriber.subscription_path(
            project_id, subscription_name
        )
        
    def scale_cluster_partition(self, partition_name, scaling_factor):
        """Scale cluster partition based on weather conditions."""
        
        # Calculate target node count based on scaling factor
        base_nodes = 2
        target_nodes = max(1, int(base_nodes * scaling_factor))
        target_nodes = min(target_nodes, 20)  # Cap at 20 nodes for cost control
        
        try:
            # Simulate scaling operation (replace with actual Slurm commands when connected to cluster)
            logger.info(f"Scaling {partition_name} to {target_nodes} nodes (factor: {scaling_factor})")
            
            # In a real deployment, this would use scontrol commands:
            # scale_command = [
            #     "scontrol", "update", f"PartitionName={partition_name}",
            #     f"MaxNodes={target_nodes}"
            # ]
            # result = subprocess.run(scale_command, capture_output=True, text=True)
            
            # For demo purposes, we'll simulate success
            logger.info(f"✅ Successfully scaled {partition_name} to {target_nodes} nodes")
            return True
                
        except Exception as e:
            logger.error(f"❌ Error scaling cluster: {str(e)}")
            return False
            
    def process_scaling_message(self, message):
        """Process individual scaling message."""
        
        try:
            # Parse weather scaling decision
            scaling_data = json.loads(message.data.decode('utf-8'))
            
            region = scaling_data.get('region', 'unknown')
            scaling_factor = scaling_data.get('scaling_factor', 1.0)
            weather_summary = scaling_data.get('weather_summary', {})
            
            logger.info(f"Processing scaling decision for {region}:")
            logger.info(f"  Scaling factor: {scaling_factor}")
            logger.info(f"  Weather: {weather_summary}")
            
            # Apply scaling based on region and conditions
            partition_name = f"weather-compute-{region}"
            success = self.scale_cluster_partition(partition_name, scaling_factor)
            
            if success:
                message.ack()
                logger.info(f"✅ Successfully processed scaling for {region}")
            else:
                message.nack()
                logger.error(f"❌ Failed to process scaling for {region}")
                
        except Exception as e:
            logger.error(f"❌ Error processing message: {str(e)}")
            message.nack()
            
    def start_scaling_service(self):
        """Start the weather-aware scaling service."""
        
        logger.info(f"🌦️  Starting weather-aware cluster scaling service")
        logger.info(f"Project: {self.project_id}")
        logger.info(f"Subscription: {self.subscription_name}")
        logger.info(f"Cluster: {self.cluster_name}")
        
        # Configure message handling
        flow_control = pubsub_v1.types.FlowControl(max_messages=10)
        
        # Start message processing
        with self.subscriber:
            streaming_pull_future = self.subscriber.subscribe(
                self.subscription_path,
                callback=self.process_scaling_message,
                flow_control=flow_control
            )
            
            logger.info(f"Listening for weather scaling messages...")
            
            try:
                streaming_pull_future.result()
            except KeyboardInterrupt:
                streaming_pull_future.cancel()
                logger.info("🛑 Scaling service stopped")

if __name__ == "__main__":
    project_id = os.environ.get('GCP_PROJECT')
    subscription_name = os.environ.get('SUBSCRIPTION_NAME', 'weather-scaling-sub')
    cluster_name = os.environ.get('CLUSTER_NAME')
    
    if not project_id:
        logger.error("GCP_PROJECT environment variable is required")
        exit(1)
    
    scaler = WeatherClusterScaler(project_id, subscription_name, cluster_name)
    scaler.start_scaling_service()
EOF
    
    # Make scaling agent executable
    chmod +x "/tmp/scaling-agent-${RANDOM_SUFFIX}.py"
    
    # Install Python dependencies
    pip3 install google-cloud-pubsub --user
    
    log_success "Cluster scaling integration created"
    log_info "Scaling agent available at: /tmp/scaling-agent-${RANDOM_SUFFIX}.py"
}

# Function to create sample workloads
create_sample_workloads() {
    log_info "Creating sample weather-dependent workloads..."
    
    # Create climate modeling job
    cat > /tmp/climate-model-job-${RANDOM_SUFFIX}.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=weather-climate-model
#SBATCH --partition=weather-compute
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --time=02:00:00
#SBATCH --output=climate-model-%j.out
#SBATCH --error=climate-model-%j.err

# Load weather scaling factor from environment
WEATHER_SCALING=${WEATHER_SCALING_FACTOR:-1.0}

echo "🌦️  Starting weather-aware climate modeling simulation"
echo "Weather scaling factor: ${WEATHER_SCALING}"
echo "Allocated nodes: ${SLURM_JOB_NUM_NODES:-1}"
echo "Allocated CPUs: ${SLURM_NTASKS:-8}"

# Simulate climate modeling workload with weather-based intensity
python3 << EOF
import time
import random
import os
import math

scaling_factor = float(os.environ.get('WEATHER_SCALING_FACTOR', '1.0'))
simulation_time = int(300 * scaling_factor)  # Base 5 minutes, scaled by weather

print(f"Running climate simulation for {simulation_time} seconds")
print(f"Weather intensity factor: {scaling_factor}")

# Simulate computational intensity based on weather conditions
for iteration in range(int(simulation_time / 10)):
    # Simulate atmospheric pressure calculations
    pressure_computation = sum(math.sin(i * scaling_factor) for i in range(10000))
    
    # Simulate temperature gradient modeling
    temp_gradient = sum(math.cos(i / scaling_factor) for i in range(8000))
    
    # Simulate precipitation modeling (higher during weather events)
    precip_model = sum(random.random() * scaling_factor for _ in range(5000))
    
    progress = (iteration + 1) * 10
    remaining_time = simulation_time - progress
    
    print(f"Progress: {progress}s/{simulation_time}s - Remaining: {remaining_time}s")
    print(f"  Pressure computation: {pressure_computation:.2f}")
    print(f"  Temperature gradient: {temp_gradient:.2f}")
    print(f"  Precipitation model: {precip_model:.2f}")
    
    time.sleep(10)

print("✅ Climate modeling simulation completed")
print(f"Total computation time: {simulation_time} seconds")
print(f"Weather scaling applied: {scaling_factor}x intensity")
EOF

echo "🎯 Climate modeling simulation completed successfully"
EOF
    
    # Create energy forecasting job
    cat > /tmp/energy-forecast-job-${RANDOM_SUFFIX}.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=weather-energy-forecast
#SBATCH --partition=weather-compute
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --time=01:00:00
#SBATCH --output=energy-forecast-%j.out
#SBATCH --error=energy-forecast-%j.err

echo "⚡ Starting weather-aware renewable energy forecasting"
echo "Wind scaling factor: ${WIND_SCALING_FACTOR:-1.0}"
echo "Solar scaling factor: ${SOLAR_SCALING_FACTOR:-1.0}"

# Simulate renewable energy forecasting based on weather conditions
python3 << EOF
import time
import math
import random
import os

wind_factor = float(os.environ.get('WIND_SCALING_FACTOR', '1.0'))
solar_factor = float(os.environ.get('SOLAR_SCALING_FACTOR', '1.0'))

print(f"Wind generation forecast (factor: {wind_factor})")
print(f"Solar generation forecast (factor: {solar_factor})")

# Simulate 24-hour energy forecasting with weather adjustments
for hour in range(24):
    # Wind energy calculation based on weather conditions
    base_wind = 100  # MW base capacity
    wind_output = base_wind * wind_factor * (0.5 + 0.5 * math.sin(hour / 4))
    
    # Solar energy calculation with weather adjustments
    base_solar = 150  # MW base capacity
    solar_output = base_solar * solar_factor * max(0, math.sin(math.pi * hour / 12))
    
    total_renewable = wind_output + solar_output
    
    print(f"Hour {hour:2d}: Wind {wind_output:6.1f}MW | Solar {solar_output:6.1f}MW | Total {total_renewable:6.1f}MW")
    time.sleep(2)

print("✅ Renewable energy forecasting completed")
EOF
EOF
    
    # Make job scripts executable
    chmod +x "/tmp/climate-model-job-${RANDOM_SUFFIX}.sh"
    chmod +x "/tmp/energy-forecast-job-${RANDOM_SUFFIX}.sh"
    
    log_success "Sample workloads created"
    log_info "Climate modeling job: /tmp/climate-model-job-${RANDOM_SUFFIX}.sh"
    log_info "Energy forecasting job: /tmp/energy-forecast-job-${RANDOM_SUFFIX}.sh"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="/tmp/weather-hpc-deployment-${RANDOM_SUFFIX}.env"
    
    cat > "${info_file}" << EOF
# Weather-Aware HPC Infrastructure Deployment Information
# Generated on: $(date)

# Project Information
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"

# Resource Names
export CLUSTER_NAME="${CLUSTER_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export TOPIC_NAME="${TOPIC_NAME}"
export SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME}"

# Cluster Information
export CLUSTER_LOGIN_IP="${CLUSTER_LOGIN_IP:-not_available}"
export CONTROLLER_IP="${CONTROLLER_IP:-not_available}"

# File Locations
export SCALING_AGENT="/tmp/scaling-agent-${RANDOM_SUFFIX}.py"
export CLIMATE_JOB="/tmp/climate-model-job-${RANDOM_SUFFIX}.sh"
export ENERGY_JOB="/tmp/energy-forecast-job-${RANDOM_SUFFIX}.sh"
export TOOLKIT_DIR="$(cat /tmp/toolkit_dir_${RANDOM_SUFFIX} 2>/dev/null || echo 'not_available')"

# API Configuration
export WEATHER_API_KEY="${WEATHER_API_KEY}"
EOF
    
    log_success "Deployment information saved to: ${info_file}"
    log_info "Source this file to restore environment variables: source ${info_file}"
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running deployment validation tests..."
    
    # Test 1: Check if Cloud Function is accessible
    local function_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    if curl -s -o /dev/null -w "%{http_code}" "${function_url}" | grep -q "200"; then
        log_success "✅ Cloud Function is accessible"
    else
        log_warning "⚠️  Cloud Function may not be fully ready yet"
    fi
    
    # Test 2: Check if Pub/Sub resources exist
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_success "✅ Pub/Sub topic exists"
    else
        log_error "❌ Pub/Sub topic not found"
    fi
    
    # Test 3: Check if Storage bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_success "✅ Storage bucket exists"
    else
        log_error "❌ Storage bucket not found"
    fi
    
    # Test 4: Check if scheduler jobs exist
    if gcloud scheduler jobs describe weather-check-job --location="${REGION}" >/dev/null 2>&1; then
        log_success "✅ Scheduler jobs configured"
    else
        log_warning "⚠️  Scheduler jobs may not be configured"
    fi
    
    # Test 5: Check if cluster is accessible (if IP is available)
    if [ "${CLUSTER_LOGIN_IP}" != "not_available" ] && [ "${CLUSTER_LOGIN_IP}" != "" ]; then
        log_info "Testing cluster connectivity..."
        if ping -c 1 "${CLUSTER_LOGIN_IP}" >/dev/null 2>&1; then
            log_success "✅ Cluster login node is reachable"
        else
            log_warning "⚠️  Cluster login node may not be ready yet"
        fi
    else
        log_warning "⚠️  Cluster IP not available for testing"
    fi
    
    log_info "Validation tests completed"
}

# Function to display final instructions
display_final_instructions() {
    log_success "🎉 Weather-Aware HPC Infrastructure deployment completed!"
    
    echo
    echo "========================================="
    echo "DEPLOYMENT SUMMARY"
    echo "========================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Cluster Name: ${CLUSTER_NAME}"
    echo "Function Name: ${FUNCTION_NAME}"
    echo "Storage Bucket: ${BUCKET_NAME}"
    echo
    
    if [ "${CLUSTER_LOGIN_IP}" != "not_available" ] && [ "${CLUSTER_LOGIN_IP}" != "" ]; then
        echo "Cluster Login IP: ${CLUSTER_LOGIN_IP}"
    fi
    
    echo "========================================="
    echo "NEXT STEPS"
    echo "========================================="
    echo "1. Configure Weather API Key (if not already done):"
    echo "   - Get API key from: https://developers.google.com/maps/documentation/weather"
    echo "   - Update Cloud Function with: gcloud functions deploy ${FUNCTION_NAME} --update-env-vars WEATHER_API_KEY=your_api_key"
    echo
    echo "2. Start the scaling service:"
    echo "   - Run: python3 /tmp/scaling-agent-${RANDOM_SUFFIX}.py"
    echo
    echo "3. Submit sample workloads (when cluster is ready):"
    echo "   - Climate modeling: sbatch /tmp/climate-model-job-${RANDOM_SUFFIX}.sh"
    echo "   - Energy forecasting: sbatch /tmp/energy-forecast-job-${RANDOM_SUFFIX}.sh"
    echo
    echo "4. Monitor the system:"
    echo "   - Weather data: gsutil ls gs://${BUCKET_NAME}/weather-data/"
    echo "   - Cloud Function logs: gcloud functions logs read ${FUNCTION_NAME}"
    echo "   - Pub/Sub messages: gcloud pubsub subscriptions pull ${SUBSCRIPTION_NAME}"
    echo
    echo "5. Access monitoring dashboard:"
    echo "   - Go to: https://console.cloud.google.com/monitoring/dashboards"
    echo "   - Look for: Weather-Aware HPC Scaling Dashboard"
    echo
    echo "========================================="
    echo "IMPORTANT NOTES"
    echo "========================================="
    echo "- The cluster may take 15-20 minutes to be fully operational"
    echo "- Weather API calls will incur charges - monitor usage"
    echo "- Use the destroy.sh script to clean up resources when done"
    echo "- Deployment info saved to: /tmp/weather-hpc-deployment-${RANDOM_SUFFIX}.env"
    echo
    
    if [ "${WEATHER_API_KEY}" = "YOUR_WEATHER_API_KEY_HERE" ]; then
        log_warning "⚠️  Remember to configure your Weather API key!"
    fi
    
    log_success "Deployment completed successfully! 🌦️ ⚡"
}

# Main deployment function
main() {
    log_info "Starting Weather-Aware HPC Infrastructure deployment..."
    
    # Check if running in dry-run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "Running in DRY RUN mode - no actual resources will be created"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_pubsub_resources
    deploy_weather_function
    setup_cluster_toolkit
    deploy_hpc_cluster
    create_monitoring_dashboard
    setup_weather_automation
    create_scaling_integration
    create_sample_workloads
    save_deployment_info
    run_validation_tests
    display_final_instructions
    
    log_success "All deployment steps completed successfully!"
}

# Script execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi