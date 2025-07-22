#!/bin/bash
set -e

# Climate Risk Assessment Earth Engine BigQuery Deployment Script
# This script deploys the complete climate risk assessment solution including:
# - Google Earth Engine integration
# - BigQuery datasets and tables
# - Cloud Functions for data processing
# - Cloud Storage buckets
# - Cloud Monitoring resources

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running on supported OS
check_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
        log "Operating system supported: $OSTYPE"
    else
        error "Unsupported operating system: $OSTYPE"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "Google Cloud Storage CLI (gsutil) is not installed. Please install it first."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    fi
    
    # Check if Python is installed
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install it first."
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to get current timestamp
get_timestamp() {
    date +%s
}

# Function to generate random suffix
generate_random_suffix() {
    openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)"
}

# Set default configuration
set_default_config() {
    log "Setting default configuration..."
    
    # Set default project ID if not provided
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID="climate-risk-$(get_timestamp)"
        warn "PROJECT_ID not set. Using default: $PROJECT_ID"
    fi
    
    # Set default region if not provided
    if [ -z "$REGION" ]; then
        REGION="us-central1"
        warn "REGION not set. Using default: $REGION"
    fi
    
    # Set default zone if not provided
    if [ -z "$ZONE" ]; then
        ZONE="us-central1-a"
        warn "ZONE not set. Using default: $ZONE"
    fi
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(generate_random_suffix)
    
    # Set resource names
    DATASET_ID="climate_risk_${RANDOM_SUFFIX}"
    BUCKET_NAME="climate-data-${RANDOM_SUFFIX}"
    FUNCTION_NAME="climate-processor-${RANDOM_SUFFIX}"
    MONITOR_FUNCTION_NAME="climate-monitor-${RANDOM_SUFFIX}"
    
    # Export variables for use in functions
    export PROJECT_ID REGION ZONE DATASET_ID BUCKET_NAME FUNCTION_NAME MONITOR_FUNCTION_NAME RANDOM_SUFFIX
    
    log "Configuration set:"
    info "  Project ID: $PROJECT_ID"
    info "  Region: $REGION"
    info "  Zone: $ZONE"
    info "  Dataset ID: $DATASET_ID"
    info "  Bucket Name: $BUCKET_NAME"
    info "  Function Name: $FUNCTION_NAME"
    info "  Monitor Function Name: $MONITOR_FUNCTION_NAME"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "earthengine.googleapis.com"
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --project="$PROJECT_ID"; then
            log "Successfully enabled $api"
        else
            error "Failed to enable $api"
        fi
    done
    
    log "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to set up Google Cloud project configuration
setup_project() {
    log "Setting up Google Cloud project configuration..."
    
    # Set default project
    gcloud config set project "$PROJECT_ID" || error "Failed to set project"
    
    # Set default region
    gcloud config set compute/region "$REGION" || error "Failed to set region"
    
    # Set default zone
    gcloud config set compute/zone "$ZONE" || error "Failed to set zone"
    
    log "Project configuration completed"
}

# Function to create BigQuery dataset
create_bigquery_dataset() {
    log "Creating BigQuery dataset..."
    
    # Create dataset
    if bq mk --dataset \
        --description="Climate risk assessment data" \
        --location="$REGION" \
        "${PROJECT_ID}:${DATASET_ID}"; then
        log "Successfully created BigQuery dataset: $DATASET_ID"
    else
        warn "Dataset $DATASET_ID may already exist or failed to create"
    fi
}

# Function to create BigQuery tables
create_bigquery_tables() {
    log "Creating BigQuery tables..."
    
    # Create climate indicators table
    log "Creating climate_indicators table..."
    bq query --use_legacy_sql=false << EOF
    CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.climate_indicators\` (
        longitude FLOAT64,
        latitude FLOAT64,
        location GEOGRAPHY,
        avg_day_temp_c FLOAT64,
        avg_night_temp_c FLOAT64,
        total_precipitation_mm FLOAT64,
        avg_ndvi FLOAT64,
        avg_evi FLOAT64,
        analysis_date TIMESTAMP,
        analysis_period_start DATE,
        analysis_period_end DATE
    )
    PARTITION BY DATE(analysis_date)
    CLUSTER BY location
EOF
    
    # Create climate extremes table
    log "Creating climate_extremes table..."
    bq query --use_legacy_sql=false << EOF
    CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.climate_extremes\` (
        location GEOGRAPHY,
        region_name STRING,
        extreme_heat_days INT64,
        extreme_cold_days INT64,
        drought_severity_index FLOAT64,
        flood_risk_score FLOAT64,
        temperature_trend_slope FLOAT64,
        precipitation_trend_slope FLOAT64,
        vegetation_stress_indicator FLOAT64,
        risk_level STRING,
        confidence_score FLOAT64,
        last_updated TIMESTAMP,
        data_source STRING
    )
    PARTITION BY DATE(last_updated)
    CLUSTER BY risk_level, region_name
EOF
    
    # Create risk assessments table
    log "Creating risk_assessments table..."
    bq query --use_legacy_sql=false << EOF
    CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.risk_assessments\` (
        assessment_id STRING,
        location GEOGRAPHY,
        assessment_date TIMESTAMP,
        overall_risk_score FLOAT64,
        heat_risk_component FLOAT64,
        drought_risk_component FLOAT64,
        flood_risk_component FLOAT64,
        ecosystem_risk_component FLOAT64,
        adaptation_priority STRING,
        recommended_actions ARRAY<STRING>,
        confidence_interval STRUCT<lower_bound FLOAT64, upper_bound FLOAT64>
    )
    PARTITION BY DATE(assessment_date)
    CLUSTER BY adaptation_priority
EOF
    
    log "BigQuery tables created successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    if gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://${BUCKET_NAME}"; then
        log "Successfully created storage bucket: gs://$BUCKET_NAME"
    else
        warn "Bucket gs://$BUCKET_NAME may already exist or failed to create"
    fi
    
    # Set lifecycle policy for cost optimization
    log "Setting lifecycle policy for storage bucket..."
    cat > /tmp/lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}" || warn "Failed to set lifecycle policy"
    rm -f /tmp/lifecycle.json
}

# Function to create Cloud Functions
create_cloud_functions() {
    log "Creating Cloud Functions..."
    
    # Create temporary directories for function code
    local temp_dir=$(mktemp -d)
    local processor_dir="$temp_dir/climate-processor"
    local monitor_dir="$temp_dir/climate-monitor"
    
    # Create climate processor function
    log "Creating climate processor function..."
    mkdir -p "$processor_dir"
    
    # Create requirements.txt for processor
    cat > "$processor_dir/requirements.txt" << 'EOF'
earthengine-api>=0.1.360
google-cloud-bigquery>=3.11.0
google-cloud-storage>=2.10.0
pandas>=2.0.0
geopandas>=0.13.0
functions-framework>=3.4.0
EOF
    
    # Create main.py for processor
    cat > "$processor_dir/main.py" << 'EOF'
import ee
import functions_framework
from google.cloud import bigquery
from google.cloud import storage
import json
import pandas as pd
from datetime import datetime, timedelta
import os

# Initialize Earth Engine
try:
    ee.Initialize()
except Exception as e:
    print(f"Earth Engine initialization failed: {e}")
    # Try to authenticate with service account
    try:
        service_account = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
        if service_account:
            credentials = ee.ServiceAccountCredentials(service_account, service_account)
            ee.Initialize(credentials)
        else:
            ee.Authenticate()
            ee.Initialize()
    except Exception as auth_error:
        print(f"Earth Engine authentication failed: {auth_error}")

@functions_framework.http
def process_climate_data(request):
    """Process climate data from Earth Engine and load to BigQuery"""
    try:
        # Parse request parameters
        request_json = request.get_json() or {}
        region_bounds = request_json.get('region_bounds', 
            [-125, 25, -66, 49])  # Default: Continental US
        start_date = request_json.get('start_date', '2020-01-01')
        end_date = request_json.get('end_date', '2023-12-31')
        
        # Define region of interest
        region = ee.Geometry.Rectangle(region_bounds)
        
        # Load climate datasets
        # MODIS Land Surface Temperature
        lst_collection = ee.ImageCollection('MODIS/006/MOD11A1') \
            .filterDate(start_date, end_date) \
            .filterBounds(region) \
            .select(['LST_Day_1km', 'LST_Night_1km'])
        
        # CHIRPS Precipitation Data
        precip_collection = ee.ImageCollection('UCSB-CHG/CHIRPS/DAILY') \
            .filterDate(start_date, end_date) \
            .filterBounds(region) \
            .select('precipitation')
        
        # MODIS Vegetation Indices
        ndvi_collection = ee.ImageCollection('MODIS/006/MOD13Q1') \
            .filterDate(start_date, end_date) \
            .filterBounds(region) \
            .select(['NDVI', 'EVI'])
        
        # Calculate climate statistics
        lst_mean = lst_collection.mean().multiply(0.02).subtract(273.15)
        precip_total = precip_collection.sum()
        ndvi_mean = ndvi_collection.mean()
        
        # Create composite image with all climate indicators
        climate_composite = lst_mean.addBands(precip_total) \
                                   .addBands(ndvi_mean)
        
        # Sample climate data at regular intervals
        sample_points = region.coveringGrid(0.1)  # ~10km grid
        
        # Extract values at sample points
        climate_samples = climate_composite.sampleRegions(
            collection=sample_points,
            scale=1000,
            geometries=True
        )
        
        # Convert to DataFrame format for BigQuery
        features = climate_samples.getInfo()['features']
        
        data_rows = []
        for feature in features:
            properties = feature['properties']
            geometry = feature['geometry']['coordinates']
            
            row = {
                'longitude': geometry[0],
                'latitude': geometry[1],
                'location': f"POINT({geometry[0]} {geometry[1]})",
                'avg_day_temp_c': properties.get('LST_Day_1km', None),
                'avg_night_temp_c': properties.get('LST_Night_1km', None),
                'total_precipitation_mm': properties.get('precipitation', None),
                'avg_ndvi': properties.get('NDVI', None),
                'avg_evi': properties.get('EVI', None),
                'analysis_date': datetime.now().isoformat(),
                'analysis_period_start': start_date,
                'analysis_period_end': end_date
            }
            data_rows.append(row)
        
        # Load data to BigQuery
        client = bigquery.Client()
        table_id = f"{client.project}.{request_json.get('dataset_id', 'climate_risk')}.climate_indicators"
        
        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",
            schema=[
                bigquery.SchemaField("longitude", "FLOAT"),
                bigquery.SchemaField("latitude", "FLOAT"),
                bigquery.SchemaField("location", "GEOGRAPHY"),
                bigquery.SchemaField("avg_day_temp_c", "FLOAT"),
                bigquery.SchemaField("avg_night_temp_c", "FLOAT"),
                bigquery.SchemaField("total_precipitation_mm", "FLOAT"),
                bigquery.SchemaField("avg_ndvi", "FLOAT"),
                bigquery.SchemaField("avg_evi", "FLOAT"),
                bigquery.SchemaField("analysis_date", "TIMESTAMP"),
                bigquery.SchemaField("analysis_period_start", "DATE"),
                bigquery.SchemaField("analysis_period_end", "DATE"),
            ]
        )
        
        df = pd.DataFrame(data_rows)
        job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
        job.result()  # Wait for job completion
        
        return {
            'status': 'success',
            'records_processed': len(data_rows),
            'table_id': table_id,
            'message': f'Processed {len(data_rows)} climate data points'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e),
            'message': 'Failed to process climate data'
        }, 500
EOF
    
    # Create climate monitor function
    log "Creating climate monitor function..."
    mkdir -p "$monitor_dir"
    
    # Create requirements.txt for monitor
    cat > "$monitor_dir/requirements.txt" << 'EOF'
google-cloud-bigquery>=3.11.0
google-cloud-monitoring>=2.15.0
functions-framework>=3.4.0
pandas>=2.0.0
EOF
    
    # Create main.py for monitor
    cat > "$monitor_dir/main.py" << 'EOF'
import functions_framework
from google.cloud import bigquery
from google.cloud import monitoring_v3
import json
from datetime import datetime, timedelta
import os

@functions_framework.http
def monitor_climate_risks(request):
    """Monitor climate risk levels and generate alerts"""
    try:
        client = bigquery.Client()
        request_json = request.get_json() or {}
        
        # Query current risk levels
        query = f"""
        WITH climate_stats AS (
          SELECT 
            location,
            AVG(avg_day_temp_c) as mean_temp,
            STDDEV(avg_day_temp_c) as temp_variability,
            SUM(total_precipitation_mm) as total_precip,
            AVG(avg_ndvi) as mean_vegetation_health,
            COUNT(*) as data_points,
            COUNTIF(avg_day_temp_c > 35) as extreme_heat_days,
            COUNTIF(avg_day_temp_c < -10) as extreme_cold_days,
            COUNTIF(total_precipitation_mm < 10 AND avg_ndvi < 0.3) as drought_indicators,
            ST_CENTROID(ST_UNION_AGG(location)) as region_center
          FROM `{client.project}.{request_json.get('dataset_id', 'climate_risk')}.climate_indicators`
          WHERE avg_day_temp_c IS NOT NULL 
            AND total_precipitation_mm IS NOT NULL
            AND avg_ndvi IS NOT NULL
          GROUP BY location
        ),
        risk_scoring AS (
          SELECT *,
            LEAST(100, GREATEST(0, 
              (extreme_heat_days * 2.5) + 
              (drought_indicators * 3.0) + 
              (extreme_cold_days * 1.5) +
              (ABS(temp_variability - 10) * 2.0)
            )) as composite_risk_score,
            CASE 
              WHEN (extreme_heat_days + drought_indicators) > 20 THEN 'HIGH'
              WHEN (extreme_heat_days + drought_indicators) > 10 THEN 'MEDIUM'
              ELSE 'LOW'
            END as risk_category
          FROM climate_stats
        )
        SELECT 
          risk_category,
          COUNT(*) as location_count,
          AVG(composite_risk_score) as avg_risk_score,
          MAX(composite_risk_score) as max_risk_score,
          ST_CENTROID(ST_UNION_AGG(region_center)) as risk_center
        FROM risk_scoring
        GROUP BY risk_category
        ORDER BY avg_risk_score DESC
        """
        
        results = client.query(query).to_dataframe()
        
        # Calculate system metrics
        total_locations = results['location_count'].sum()
        high_risk_locations = results[results['risk_category'] == 'HIGH']['location_count'].sum()
        high_risk_percentage = (high_risk_locations / total_locations) * 100 if total_locations > 0 else 0
        
        # Create custom metrics for Cloud Monitoring
        monitoring_client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{client.project}"
        
        # Create time series for high risk percentage
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/climate_risk/high_risk_percentage"
        series.resource.type = "global"
        
        point = monitoring_v3.Point()
        point.value.double_value = high_risk_percentage
        point.interval.end_time.seconds = int(datetime.now().timestamp())
        series.points = [point]
        
        try:
            monitoring_client.create_time_series(
                name=project_name, 
                time_series=[series]
            )
        except Exception as monitoring_error:
            print(f"Failed to create monitoring metric: {monitoring_error}")
        
        # Generate response with risk summary
        response = {
            'timestamp': datetime.now().isoformat(),
            'total_locations_analyzed': int(total_locations),
            'high_risk_locations': int(high_risk_locations),
            'high_risk_percentage': round(high_risk_percentage, 2),
            'risk_distribution': results.to_dict('records'),
            'alerts': []
        }
        
        # Generate alerts for high risk conditions
        if high_risk_percentage > 25:
            response['alerts'].append({
                'level': 'WARNING',
                'message': f'{high_risk_percentage:.1f}% of monitored locations show high climate risk',
                'action': 'Review adaptation strategies for high-risk areas'
            })
        
        return response
        
    except Exception as e:
        return {
            'status': 'error',
            'error': str(e),
            'message': 'Failed to monitor climate risks'
        }, 500
EOF
    
    # Deploy climate processor function
    log "Deploying climate processor function..."
    (cd "$processor_dir" && gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python311 \
        --trigger http \
        --entry-point process_climate_data \
        --memory 2048MB \
        --timeout 540s \
        --region "$REGION" \
        --allow-unauthenticated \
        --project "$PROJECT_ID") || error "Failed to deploy climate processor function"
    
    # Deploy climate monitor function
    log "Deploying climate monitor function..."
    (cd "$monitor_dir" && gcloud functions deploy "$MONITOR_FUNCTION_NAME" \
        --runtime python311 \
        --trigger http \
        --entry-point monitor_climate_risks \
        --memory 1024MB \
        --timeout 300s \
        --region "$REGION" \
        --allow-unauthenticated \
        --project "$PROJECT_ID") || error "Failed to deploy climate monitor function"
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log "Cloud Functions deployed successfully"
}

# Function to create BigQuery views
create_bigquery_views() {
    log "Creating BigQuery views..."
    
    # Create climate risk analysis view
    log "Creating climate_risk_analysis view..."
    bq query --use_legacy_sql=false << EOF
    CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.climate_risk_analysis\` AS
    WITH climate_stats AS (
      SELECT 
        location,
        AVG(avg_day_temp_c) as mean_temp,
        STDDEV(avg_day_temp_c) as temp_variability,
        SUM(total_precipitation_mm) as total_precip,
        AVG(avg_ndvi) as mean_vegetation_health,
        COUNT(*) as data_points,
        -- Temperature extremes (above 35°C or below -10°C)
        COUNTIF(avg_day_temp_c > 35) as extreme_heat_days,
        COUNTIF(avg_day_temp_c < -10) as extreme_cold_days,
        -- Drought indicator (low precipitation + low vegetation)
        COUNTIF(total_precipitation_mm < 10 AND avg_ndvi < 0.3) as drought_indicators,
        -- Calculate geographic centroid for regional analysis
        ST_CENTROID(ST_UNION_AGG(location)) as region_center
      FROM \`${PROJECT_ID}.${DATASET_ID}.climate_indicators\`
      WHERE avg_day_temp_c IS NOT NULL 
        AND total_precipitation_mm IS NOT NULL
        AND avg_ndvi IS NOT NULL
      GROUP BY location
    ),
    risk_scoring AS (
      SELECT *,
        -- Composite risk score (0-100 scale)
        LEAST(100, GREATEST(0, 
          (extreme_heat_days * 2.5) + 
          (drought_indicators * 3.0) + 
          (extreme_cold_days * 1.5) +
          (ABS(temp_variability - 10) * 2.0)
        )) as composite_risk_score,
        -- Risk categorization
        CASE 
          WHEN (extreme_heat_days + drought_indicators) > 20 THEN 'HIGH'
          WHEN (extreme_heat_days + drought_indicators) > 10 THEN 'MEDIUM'
          ELSE 'LOW'
        END as risk_category
      FROM climate_stats
    )
    SELECT 
      location,
      region_center,
      mean_temp,
      temp_variability,
      total_precip,
      mean_vegetation_health,
      extreme_heat_days,
      extreme_cold_days,
      drought_indicators,
      composite_risk_score,
      risk_category,
      -- Confidence based on data completeness
      ROUND((data_points / 1460.0) * 100, 1) as data_confidence_pct
    FROM risk_scoring
    ORDER BY composite_risk_score DESC
EOF
    
    # Create dashboard summary view
    log "Creating risk_dashboard_summary view..."
    bq query --use_legacy_sql=false << EOF
    CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.risk_dashboard_summary\` AS
    WITH temporal_trends AS (
      SELECT 
        DATE_TRUNC(DATE(analysis_date), MONTH) as analysis_month,
        AVG(avg_day_temp_c) as monthly_avg_temp,
        SUM(total_precipitation_mm) as monthly_total_precip,
        AVG(avg_ndvi) as monthly_avg_vegetation,
        COUNT(*) as monthly_observations
      FROM \`${PROJECT_ID}.${DATASET_ID}.climate_indicators\`
      WHERE analysis_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 YEAR)
      GROUP BY analysis_month
    ),
    spatial_risk_summary AS (
      SELECT 
        risk_category,
        COUNT(*) as location_count,
        AVG(composite_risk_score) as avg_risk_score,
        MIN(composite_risk_score) as min_risk_score,
        MAX(composite_risk_score) as max_risk_score,
        -- Create geographic bounds for each risk category
        ST_ENVELOPE(ST_UNION_AGG(location)) as risk_region_bounds
      FROM \`${PROJECT_ID}.${DATASET_ID}.climate_risk_analysis\`
      GROUP BY risk_category
    )
    SELECT 
      'TEMPORAL_TRENDS' as summary_type,
      analysis_month as period,
      monthly_avg_temp as temperature_c,
      monthly_total_precip as precipitation_mm,
      monthly_avg_vegetation as vegetation_index,
      monthly_observations as data_points,
      NULL as risk_category,
      NULL as location_count,
      NULL as risk_bounds
    FROM temporal_trends
    UNION ALL
    SELECT 
      'SPATIAL_RISK' as summary_type,
      NULL as period,
      NULL as temperature_c,
      NULL as precipitation_mm,
      NULL as vegetation_index,
      NULL as data_points,
      risk_category,
      location_count,
      ST_ASGEOJSON(risk_region_bounds) as risk_bounds
    FROM spatial_risk_summary
    ORDER BY summary_type, period DESC, temperature_c DESC
EOF
    
    log "BigQuery views created successfully"
}

# Function to test the deployment
test_deployment() {
    log "Testing deployment..."
    
    # Get function URLs
    local processor_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)" \
        --project="$PROJECT_ID")
    
    local monitor_url=$(gcloud functions describe "$MONITOR_FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)" \
        --project="$PROJECT_ID")
    
    info "Function URLs:"
    info "  Processor: $processor_url"
    info "  Monitor: $monitor_url"
    
    # Test BigQuery dataset access
    log "Testing BigQuery dataset access..."
    if bq ls "${PROJECT_ID}:${DATASET_ID}" > /dev/null 2>&1; then
        log "BigQuery dataset access verified"
    else
        warn "BigQuery dataset access test failed"
    fi
    
    # Test Cloud Storage bucket access
    log "Testing Cloud Storage bucket access..."
    if gsutil ls "gs://${BUCKET_NAME}" > /dev/null 2>&1; then
        log "Cloud Storage bucket access verified"
    else
        warn "Cloud Storage bucket access test failed"
    fi
    
    # Test function accessibility
    log "Testing function accessibility..."
    if curl -s -o /dev/null -w "%{http_code}" "$processor_url" | grep -q "200\|405"; then
        log "Climate processor function is accessible"
    else
        warn "Climate processor function accessibility test failed"
    fi
    
    if curl -s -o /dev/null -w "%{http_code}" "$monitor_url" | grep -q "200\|405"; then
        log "Climate monitor function is accessible"
    else
        warn "Climate monitor function accessibility test failed"
    fi
    
    log "Deployment testing completed"
}

# Function to save deployment configuration
save_deployment_config() {
    log "Saving deployment configuration..."
    
    local config_file="./deployment_config.json"
    
    cat > "$config_file" << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "project_id": "$PROJECT_ID",
    "region": "$REGION",
    "zone": "$ZONE",
    "dataset_id": "$DATASET_ID",
    "bucket_name": "$BUCKET_NAME",
    "function_name": "$FUNCTION_NAME",
    "monitor_function_name": "$MONITOR_FUNCTION_NAME",
    "random_suffix": "$RANDOM_SUFFIX",
    "function_urls": {
        "processor": "$(gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --format="value(httpsTrigger.url)" --project="$PROJECT_ID" 2>/dev/null || echo "Not available")",
        "monitor": "$(gcloud functions describe "$MONITOR_FUNCTION_NAME" --region="$REGION" --format="value(httpsTrigger.url)" --project="$PROJECT_ID" 2>/dev/null || echo "Not available")"
    },
    "bigquery_tables": [
        "$PROJECT_ID.$DATASET_ID.climate_indicators",
        "$PROJECT_ID.$DATASET_ID.climate_extremes",
        "$PROJECT_ID.$DATASET_ID.risk_assessments"
    ],
    "bigquery_views": [
        "$PROJECT_ID.$DATASET_ID.climate_risk_analysis",
        "$PROJECT_ID.$DATASET_ID.risk_dashboard_summary"
    ],
    "storage_bucket": "gs://$BUCKET_NAME"
}
EOF
    
    log "Deployment configuration saved to: $config_file"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary"
    echo "===================="
    info "Project ID: $PROJECT_ID"
    info "Region: $REGION"
    info "Zone: $ZONE"
    info "Dataset ID: $DATASET_ID"
    info "Bucket Name: $BUCKET_NAME"
    info "Function Name: $FUNCTION_NAME"
    info "Monitor Function Name: $MONITOR_FUNCTION_NAME"
    echo ""
    info "BigQuery Dataset: https://console.cloud.google.com/bigquery?project=$PROJECT_ID&ws=!1m4!1m3!8m2!1s$PROJECT_ID!2s$DATASET_ID"
    info "Cloud Storage Bucket: https://console.cloud.google.com/storage/browser/$BUCKET_NAME?project=$PROJECT_ID"
    info "Cloud Functions: https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
    echo ""
    info "Next Steps:"
    info "1. Register for Earth Engine access at https://earthengine.google.com"
    info "2. Test the functions with sample data"
    info "3. Create Data Studio dashboards for visualization"
    info "4. Set up monitoring alerts for high-risk conditions"
    echo ""
    info "Estimated monthly cost: \$25-50 for BigQuery analysis, \$10-20 for Cloud Functions, \$5-10 for storage"
    warn "Remember to run ./destroy.sh to clean up resources when done to avoid ongoing charges"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted. Cleaning up temporary files..."
    rm -rf /tmp/lifecycle.json 2>/dev/null || true
    exit 1
}

# Main deployment function
main() {
    log "Starting Climate Risk Assessment Earth Engine BigQuery deployment"
    
    # Set up interrupt handler
    trap cleanup_on_interrupt INT TERM
    
    # Check OS compatibility
    check_os
    
    # Check prerequisites
    check_prerequisites
    
    # Set default configuration
    set_default_config
    
    # Set up Google Cloud project
    setup_project
    
    # Enable required APIs
    enable_apis
    
    # Create BigQuery dataset
    create_bigquery_dataset
    
    # Create BigQuery tables
    create_bigquery_tables
    
    # Create Cloud Storage bucket
    create_storage_bucket
    
    # Create Cloud Functions
    create_cloud_functions
    
    # Create BigQuery views
    create_bigquery_views
    
    # Test deployment
    test_deployment
    
    # Save deployment configuration
    save_deployment_config
    
    # Display deployment summary
    display_deployment_summary
    
    log "Deployment completed successfully!"
    log "Total deployment time: $(($(date +%s) - START_TIME)) seconds"
}

# Record start time
START_TIME=$(date +%s)

# Run main function
main "$@"