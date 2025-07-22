#!/bin/bash

# Supply Chain Analytics with Cloud Bigtable and Cloud Dataproc - Deployment Script
# This script deploys the complete supply chain analytics infrastructure on Google Cloud Platform

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error "Google Cloud SDK (gcloud) is not installed. Please install it first."
        error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command_exists gsutil; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if cbt is installed
    if ! command_exists cbt; then
        warning "cbt (Cloud Bigtable command-line tool) is not installed."
        log "Installing cbt..."
        gcloud components install cbt --quiet || {
            error "Failed to install cbt"
            exit 1
        }
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command_exists python3; then
        error "Python 3 is required but not installed."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-supply-chain-analytics-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export BIGTABLE_INSTANCE_ID="${BIGTABLE_INSTANCE_ID:-supply-chain-bt-${RANDOM_SUFFIX}}"
    export DATAPROC_CLUSTER_NAME="${DATAPROC_CLUSTER_NAME:-supply-analytics-cluster-${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-supply-chain-data-${RANDOM_SUFFIX}}"
    export TOPIC_NAME="${TOPIC_NAME:-sensor-data-topic-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-process-sensor-data}"
    export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-supply-chain-analytics-job}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
    log "Bigtable Instance: ${BIGTABLE_INSTANCE_ID}"
    log "Dataproc Cluster: ${DATAPROC_CLUSTER_NAME}"
    log "Storage Bucket: ${BUCKET_NAME}"
    log "Pub/Sub Topic: ${TOPIC_NAME}"
}

# Function to enable APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "bigtable.googleapis.com"
        "dataproc.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "monitoring.googleapis.com"
        "storage.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" --quiet || {
            error "Failed to enable ${api}"
            exit 1
        }
    done
    
    success "All required APIs enabled"
}

# Function to create storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        warning "Storage bucket gs://${BUCKET_NAME} already exists"
    else
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}" || {
            error "Failed to create storage bucket"
            exit 1
        }
        success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
}

# Function to create Pub/Sub topic
create_pubsub_topic() {
    log "Creating Pub/Sub topic..."
    
    # Check if topic already exists
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        warning "Pub/Sub topic ${TOPIC_NAME} already exists"
    else
        gcloud pubsub topics create "${TOPIC_NAME}" --quiet || {
            error "Failed to create Pub/Sub topic"
            exit 1
        }
        success "Pub/Sub topic created: ${TOPIC_NAME}"
    fi
}

# Function to create Bigtable instance
create_bigtable_instance() {
    log "Creating Cloud Bigtable instance..."
    
    # Check if instance already exists
    if gcloud bigtable instances describe "${BIGTABLE_INSTANCE_ID}" >/dev/null 2>&1; then
        warning "Bigtable instance ${BIGTABLE_INSTANCE_ID} already exists"
    else
        gcloud bigtable instances create "${BIGTABLE_INSTANCE_ID}" \
            --display-name="Supply Chain Analytics Instance" \
            --cluster-config="id=supply-chain-cluster,zone=${ZONE},nodes=3,type=PRODUCTION" \
            --project="${PROJECT_ID}" \
            --quiet || {
            error "Failed to create Bigtable instance"
            exit 1
        }
        success "Bigtable instance created: ${BIGTABLE_INSTANCE_ID}"
    fi
    
    # Create table and column families
    log "Creating Bigtable table and column families..."
    echo 'create "sensor_data", "sensor_readings", "device_metadata", "location_data"' | \
        cbt -project="${PROJECT_ID}" -instance="${BIGTABLE_INSTANCE_ID}" shell || {
        warning "Table creation failed (may already exist)"
    }
    success "Bigtable table and column families configured"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log "Deploying Cloud Function for sensor data processing..."
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    # Create function code
    cat > main.py << 'EOF'
import json
import base64
import os
from datetime import datetime
from google.cloud import bigtable
from google.cloud.bigtable import column_family

def process_sensor_data(event, context):
    """Process sensor data from Pub/Sub and store in Bigtable"""
    
    # Decode Pub/Sub message
    if 'data' in event:
        message_data = base64.b64decode(event['data']).decode('utf-8')
        try:
            sensor_data = json.loads(message_data)
        except json.JSONDecodeError:
            print(f"Invalid JSON data: {message_data}")
            return
    else:
        print("No data in event")
        return
    
    # Get Bigtable instance ID from environment
    instance_id = os.environ.get('BIGTABLE_INSTANCE_ID')
    if not instance_id:
        print("BIGTABLE_INSTANCE_ID environment variable not set")
        return
    
    try:
        # Initialize Bigtable client
        client = bigtable.Client()
        instance = client.instance(instance_id)
        table = instance.table('sensor_data')
        
        # Create row key: device_id#timestamp_reversed for efficient querying
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S%f')
        device_id = sensor_data.get('device_id', 'unknown')
        row_key = f"{device_id}#{timestamp}"
        
        # Write data to Bigtable
        row = table.direct_row(row_key)
        
        # Store sensor readings
        if 'temperature' in sensor_data:
            row.set_cell('sensor_readings', 'temperature', str(sensor_data['temperature']))
        if 'humidity' in sensor_data:
            row.set_cell('sensor_readings', 'humidity', str(sensor_data['humidity']))
        if 'inventory_level' in sensor_data:
            row.set_cell('sensor_readings', 'inventory_level', str(sensor_data['inventory_level']))
        
        # Store device metadata
        if 'device_type' in sensor_data:
            row.set_cell('device_metadata', 'device_type', sensor_data['device_type'])
        if 'timestamp' in sensor_data:
            row.set_cell('device_metadata', 'timestamp', sensor_data['timestamp'])
        
        # Store location data
        if 'warehouse_id' in sensor_data:
            row.set_cell('location_data', 'warehouse_id', sensor_data['warehouse_id'])
        if 'zone' in sensor_data:
            row.set_cell('location_data', 'zone', sensor_data['zone'])
        
        row.commit()
        
        print(f"Successfully processed sensor data for device: {device_id}")
        
    except Exception as e:
        print(f"Error processing sensor data: {str(e)}")
        raise
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
google-cloud-bigtable==2.21.0
google-cloud-pubsub==2.18.4
EOF
    
    # Deploy Cloud Function
    gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-topic "${TOPIC_NAME}" \
        --source . \
        --entry-point process_sensor_data \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "BIGTABLE_INSTANCE_ID=${BIGTABLE_INSTANCE_ID}" \
        --region="${REGION}" \
        --quiet || {
        error "Failed to deploy Cloud Function"
        cd - >/dev/null
        rm -rf "${temp_dir}"
        exit 1
    }
    
    # Clean up temporary directory
    cd - >/dev/null
    rm -rf "${temp_dir}"
    
    success "Cloud Function deployed: ${FUNCTION_NAME}"
}

# Function to create Dataproc cluster
create_dataproc_cluster() {
    log "Creating Cloud Dataproc cluster..."
    
    # Check if cluster already exists
    if gcloud dataproc clusters describe "${DATAPROC_CLUSTER_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        warning "Dataproc cluster ${DATAPROC_CLUSTER_NAME} already exists"
    else
        gcloud dataproc clusters create "${DATAPROC_CLUSTER_NAME}" \
            --region="${REGION}" \
            --zone="${ZONE}" \
            --master-machine-type=n1-standard-4 \
            --master-boot-disk-size=50GB \
            --num-workers=3 \
            --worker-machine-type=n1-standard-2 \
            --worker-boot-disk-size=50GB \
            --num-preemptible-workers=3 \
            --preemptible-worker-boot-disk-size=50GB \
            --image-version=2.0-debian10 \
            --enable-autoscaling \
            --max-workers=8 \
            --secondary-worker-type=preemptible \
            --optional-components=JUPYTER \
            --enable-ip-alias \
            --metadata=enable-cloud-sql-hbase-connector=true \
            --quiet || {
            error "Failed to create Dataproc cluster"
            exit 1
        }
        
        # Wait for cluster to be ready
        log "Waiting for Dataproc cluster to be ready..."
        gcloud dataproc clusters wait "${DATAPROC_CLUSTER_NAME}" \
            --region="${REGION}" \
            --timeout=600 || {
            error "Dataproc cluster failed to start within timeout"
            exit 1
        }
        
        success "Dataproc cluster created: ${DATAPROC_CLUSTER_NAME}"
    fi
}

# Function to create and upload Spark job
create_spark_job() {
    log "Creating and uploading Spark job for supply chain analytics..."
    
    # Create temporary file for Spark job
    local temp_file
    temp_file=$(mktemp)
    
    cat > "${temp_file}" << 'EOF'
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
from pyspark.ml.feature import VectorAssembler
from pyspark.ml.regression import LinearRegression
from pyspark.ml.evaluation import RegressionEvaluator
import sys
import random
from datetime import datetime, timedelta

def create_spark_session():
    """Create Spark session with Bigtable connector"""
    return SparkSession.builder \
        .appName("SupplyChainAnalytics") \
        .config("spark.jars.packages", "com.google.cloud.bigtable:bigtable-hbase-2.x-hadoop:2.0.0") \
        .getOrCreate()

def generate_sample_data(spark, num_records=1000):
    """Generate sample sensor data for demonstration"""
    
    schema = StructType([
        StructField("device_id", StringType(), True),
        StructField("timestamp", TimestampType(), True),
        StructField("temperature", DoubleType(), True),
        StructField("humidity", DoubleType(), True),
        StructField("inventory_level", DoubleType(), True),
        StructField("warehouse_id", StringType(), True),
        StructField("zone", StringType(), True)
    ])
    
    # Generate sample data
    sample_data = []
    base_time = datetime.now()
    
    for i in range(num_records):
        sample_data.append((
            f"device_{i % 10}",
            base_time - timedelta(hours=i),
            20.0 + random.uniform(-5, 15),  # Temperature variation
            50.0 + random.uniform(-20, 30), # Humidity variation
            100.0 - (i % 50) + random.uniform(-10, 10), # Inventory with trend
            f"warehouse_{i % 5}",
            f"zone_{i % 3}"
        ))
    
    return spark.createDataFrame(sample_data, schema)

def analyze_inventory_patterns(df):
    """Analyze inventory patterns and trends"""
    print("Analyzing inventory patterns...")
    
    # Calculate inventory trends by warehouse and zone
    inventory_trends = df.groupBy("warehouse_id", "zone") \
        .agg(
            avg("inventory_level").alias("avg_inventory"),
            min("inventory_level").alias("min_inventory"),
            max("inventory_level").alias("max_inventory"),
            stddev("inventory_level").alias("inventory_stddev"),
            count("*").alias("reading_count")
        ) \
        .orderBy("warehouse_id", "zone")
    
    print("Inventory Analysis Results:")
    inventory_trends.show(20, False)
    
    return inventory_trends

def environmental_analysis(df):
    """Analyze environmental conditions"""
    print("Analyzing environmental conditions...")
    
    env_analysis = df.groupBy("warehouse_id") \
        .agg(
            avg("temperature").alias("avg_temperature"),
            avg("humidity").alias("avg_humidity"),
            min("temperature").alias("min_temperature"),
            max("temperature").alias("max_temperature"),
            min("humidity").alias("min_humidity"),
            max("humidity").alias("max_humidity")
        ) \
        .orderBy("warehouse_id")
    
    print("Environmental Analysis Results:")
    env_analysis.show(20, False)
    
    return env_analysis

def demand_forecasting(df):
    """Perform demand forecasting using linear regression"""
    print("Performing demand forecasting...")
    
    try:
        # Prepare features for ML model
        feature_cols = ["temperature", "humidity"]
        assembler = VectorAssembler(inputCols=feature_cols, outputCol="features")
        
        # Add time-based features
        df_with_features = df.withColumn("hour", hour("timestamp")) \
            .withColumn("day_of_week", dayofweek("timestamp")) \
            .withColumn("day_of_year", dayofyear("timestamp"))
        
        # Filter out null values
        df_clean = df_with_features.filter(
            col("temperature").isNotNull() & 
            col("humidity").isNotNull() & 
            col("inventory_level").isNotNull()
        )
        
        if df_clean.count() == 0:
            print("No valid data for forecasting")
            return None, None, None
        
        # Assemble features
        df_assembled = assembler.transform(df_clean)
        
        # Split data for training and testing
        train_data, test_data = df_assembled.randomSplit([0.8, 0.2], seed=42)
        
        if train_data.count() == 0 or test_data.count() == 0:
            print("Insufficient data for train/test split")
            return None, None, None
        
        # Train linear regression model
        lr = LinearRegression(featuresCol="features", labelCol="inventory_level")
        model = lr.fit(train_data)
        
        # Make predictions
        predictions = model.transform(test_data)
        
        # Evaluate model
        evaluator = RegressionEvaluator(labelCol="inventory_level", predictionCol="prediction")
        rmse = evaluator.evaluate(predictions)
        
        print(f"Demand Forecasting Model RMSE: {rmse:.2f}")
        print("Sample Predictions:")
        predictions.select("warehouse_id", "zone", "inventory_level", "prediction") \
            .show(10, False)
        
        return model, rmse, predictions
    
    except Exception as e:
        print(f"Error in demand forecasting: {str(e)}")
        return None, None, None

def main():
    # Initialize Spark session
    spark = create_spark_session()
    
    try:
        # Read command line arguments
        project_id = sys.argv[1] if len(sys.argv) > 1 else "default-project"
        instance_id = sys.argv[2] if len(sys.argv) > 2 else "default-instance"
        bucket_name = sys.argv[3] if len(sys.argv) > 3 else f"{project_id}-analytics"
        
        print(f"Starting supply chain analytics for project: {project_id}")
        print(f"Using Bigtable instance: {instance_id}")
        print(f"Output bucket: {bucket_name}")
        
        # Generate sample data (in production, this would read from Bigtable)
        sensor_data = generate_sample_data(spark, 1000)
        
        # Analyze inventory patterns
        inventory_analysis = analyze_inventory_patterns(sensor_data)
        
        # Analyze environmental conditions
        env_analysis = environmental_analysis(sensor_data)
        
        # Perform demand forecasting
        model, rmse, predictions = demand_forecasting(sensor_data)
        
        # Save results to Cloud Storage
        try:
            inventory_analysis.write.mode("overwrite") \
                .option("header", "true") \
                .csv(f"gs://{bucket_name}/analytics/inventory_analysis")
            
            env_analysis.write.mode("overwrite") \
                .option("header", "true") \
                .csv(f"gs://{bucket_name}/analytics/environmental_analysis")
            
            if predictions is not None:
                predictions.select("warehouse_id", "zone", "inventory_level", "prediction") \
                    .write.mode("overwrite") \
                    .option("header", "true") \
                    .csv(f"gs://{bucket_name}/analytics/demand_forecasts")
            
            print("Analytics results saved to Cloud Storage successfully")
            
        except Exception as e:
            print(f"Error saving results: {str(e)}")
        
        print("Supply chain analytics completed successfully")
        
    except Exception as e:
        print(f"Error in main execution: {str(e)}")
        raise
    
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
EOF
    
    # Upload Spark job to Cloud Storage
    gsutil cp "${temp_file}" "gs://${BUCKET_NAME}/jobs/supply_chain_analytics.py" || {
        error "Failed to upload Spark job"
        rm -f "${temp_file}"
        exit 1
    }
    
    # Clean up temporary file
    rm -f "${temp_file}"
    
    success "Spark job uploaded to gs://${BUCKET_NAME}/jobs/supply_chain_analytics.py"
}

# Function to configure Cloud Scheduler
configure_scheduler() {
    log "Configuring Cloud Scheduler for automated analytics..."
    
    # Check if scheduler job already exists
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" >/dev/null 2>&1; then
        warning "Scheduler job ${SCHEDULER_JOB_NAME} already exists"
    else
        # Get the default service account email
        local service_account
        service_account=$(gcloud iam service-accounts list \
            --filter="displayName:Compute Engine default service account" \
            --format="value(email)")
        
        if [[ -z "${service_account}" ]]; then
            service_account="${PROJECT_ID}-compute@developer.gserviceaccount.com"
        fi
        
        gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
            --location="${REGION}" \
            --schedule="0 */6 * * *" \
            --uri="https://dataproc.googleapis.com/v1/projects/${PROJECT_ID}/regions/${REGION}/jobs:submit" \
            --http-method=POST \
            --headers="Content-Type=application/json" \
            --oauth-service-account-email="${service_account}" \
            --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
            --message-body="{
              \"job\": {
                \"placement\": {
                  \"clusterName\": \"${DATAPROC_CLUSTER_NAME}\"
                },
                \"pysparkJob\": {
                  \"mainPythonFileUri\": \"gs://${BUCKET_NAME}/jobs/supply_chain_analytics.py\",
                  \"args\": [\"${PROJECT_ID}\", \"${BIGTABLE_INSTANCE_ID}\", \"${BUCKET_NAME}\"]
                }
              }
            }" \
            --quiet || {
            error "Failed to create scheduler job"
            exit 1
        }
        
        success "Cloud Scheduler job created: ${SCHEDULER_JOB_NAME}"
    fi
}

# Function to set up monitoring
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    # Create custom monitoring dashboard
    local temp_config
    temp_config=$(mktemp)
    
    cat > "${temp_config}" << EOF
{
  "displayName": "Supply Chain Analytics Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Bigtable Operations",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"bigtable_table\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["resource.label.table_id"]
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Dataproc Job Status",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"dataproc_cluster\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "crossSeriesReducer": "REDUCE_MEAN"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create monitoring dashboard
    gcloud monitoring dashboards create --config-from-file="${temp_config}" --quiet || {
        warning "Failed to create monitoring dashboard (may already exist)"
    }
    
    # Clean up temp file
    rm -f "${temp_config}"
    
    success "Monitoring dashboard configured"
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Test Bigtable connectivity
    log "Testing Bigtable connectivity..."
    cbt -project="${PROJECT_ID}" -instance="${BIGTABLE_INSTANCE_ID}" ls >/dev/null 2>&1 || {
        error "Failed to connect to Bigtable instance"
        exit 1
    }
    success "Bigtable connectivity test passed"
    
    # Test Dataproc cluster
    log "Testing Dataproc cluster status..."
    local cluster_state
    cluster_state=$(gcloud dataproc clusters describe "${DATAPROC_CLUSTER_NAME}" \
        --region="${REGION}" \
        --format="value(status.state)" 2>/dev/null)
    
    if [[ "${cluster_state}" != "RUNNING" ]]; then
        error "Dataproc cluster is not in RUNNING state: ${cluster_state}"
        exit 1
    fi
    success "Dataproc cluster test passed"
    
    # Test Cloud Function
    log "Testing Cloud Function..."
    gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1 || {
        error "Cloud Function is not accessible"
        exit 1
    }
    success "Cloud Function test passed"
    
    # Test Storage bucket
    log "Testing Cloud Storage bucket..."
    gsutil ls "gs://${BUCKET_NAME}/" >/dev/null 2>&1 || {
        error "Cannot access storage bucket"
        exit 1
    }
    success "Storage bucket test passed"
    
    success "All deployment tests passed!"
}

# Function to run a sample analytics job
run_sample_job() {
    log "Running sample analytics job..."
    
    local job_id
    job_id=$(gcloud dataproc jobs submit pyspark \
        --cluster="${DATAPROC_CLUSTER_NAME}" \
        --region="${REGION}" \
        "gs://${BUCKET_NAME}/jobs/supply_chain_analytics.py" \
        --args="${PROJECT_ID}" --args="${BIGTABLE_INSTANCE_ID}" --args="${BUCKET_NAME}" \
        --format="value(reference.jobId)")
    
    if [[ -n "${job_id}" ]]; then
        log "Sample job submitted with ID: ${job_id}"
        log "You can monitor the job in the Google Cloud Console"
        success "Sample analytics job submitted successfully"
    else
        warning "Failed to submit sample job, but deployment is complete"
    fi
}

# Function to display deployment summary
display_summary() {
    echo
    success "Supply Chain Analytics Platform Deployment Complete!"
    echo
    echo "📊 Resources Created:"
    echo "   • Project ID: ${PROJECT_ID}"
    echo "   • Bigtable Instance: ${BIGTABLE_INSTANCE_ID}"
    echo "   • Dataproc Cluster: ${DATAPROC_CLUSTER_NAME}"
    echo "   • Storage Bucket: gs://${BUCKET_NAME}"
    echo "   • Pub/Sub Topic: ${TOPIC_NAME}"
    echo "   • Cloud Function: ${FUNCTION_NAME}"
    echo "   • Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo
    echo "🔗 Useful Commands:"
    echo "   • View Bigtable data: cbt -project=${PROJECT_ID} -instance=${BIGTABLE_INSTANCE_ID} read sensor_data count=10"
    echo "   • Check Dataproc jobs: gcloud dataproc jobs list --cluster=${DATAPROC_CLUSTER_NAME} --region=${REGION}"
    echo "   • View analytics results: gsutil ls gs://${BUCKET_NAME}/analytics/"
    echo
    echo "🌐 Console Links:"
    echo "   • Bigtable: https://console.cloud.google.com/bigtable/instances/${BIGTABLE_INSTANCE_ID}"
    echo "   • Dataproc: https://console.cloud.google.com/dataproc/clusters/${DATAPROC_CLUSTER_NAME}"
    echo "   • Storage: https://console.cloud.google.com/storage/browser/${BUCKET_NAME}"
    echo "   • Monitoring: https://console.cloud.google.com/monitoring"
    echo
    warning "💰 Remember to run ./destroy.sh when you're done to avoid ongoing charges!"
    echo
}

# Main deployment function
main() {
    echo "🚀 Starting Supply Chain Analytics Platform Deployment"
    echo "=================================================="
    
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    create_pubsub_topic
    create_bigtable_instance
    deploy_cloud_function
    create_dataproc_cluster
    create_spark_job
    configure_scheduler
    setup_monitoring
    test_deployment
    run_sample_job
    display_summary
    
    success "Deployment completed successfully! 🎉"
}

# Handle script interruption
trap 'error "Deployment interrupted. You may need to clean up resources manually."; exit 1' INT TERM

# Run main function
main "$@"