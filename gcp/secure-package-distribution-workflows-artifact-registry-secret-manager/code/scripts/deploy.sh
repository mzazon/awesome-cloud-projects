#!/bin/bash

# Deploy script for Secure Package Distribution Workflows with Artifact Registry and Secret Manager
# This script implements the complete infrastructure deployment for the GCP recipe

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud CLI is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_warning "Docker is not installed. You may need it for container package testing."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes. Please install it."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables for the project
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export ZONE="us-central1-a"
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No project ID found. Please set a default project with 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export REPO_NAME="secure-packages-${RANDOM_SUFFIX}"
    export SECRET_NAME="registry-credentials-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB="package-distribution-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="package-distributor-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="package-distributor-sa-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID}
    gcloud config set artifacts/location ${REGION}
    gcloud config set compute/region ${REGION}
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Repository name: ${REPO_NAME}"
    log_info "Random suffix: ${RANDOM_SUFFIX}"
    
    # Save environment variables to file for destroy script
    cat > .env <<EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
REPO_NAME=${REPO_NAME}
SECRET_NAME=${SECRET_NAME}
SCHEDULER_JOB=${SCHEDULER_JOB}
FUNCTION_NAME=${FUNCTION_NAME}
SERVICE_ACCOUNT_NAME=${SERVICE_ACCOUNT_NAME}
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_EMAIL}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables saved to .env file"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "artifactregistry.googleapis.com"
        "secretmanager.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudtasks.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable ${api}
    done
    
    log_success "All required APIs enabled"
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to create Artifact Registry repositories
create_artifact_registry() {
    log_info "Creating Artifact Registry repositories..."
    
    # Create Docker repository for container packages
    log_info "Creating Docker repository..."
    gcloud artifacts repositories create ${REPO_NAME} \
        --repository-format=docker \
        --location=${REGION} \
        --description="Secure package distribution repository"
    
    # Create additional repositories for different package types
    log_info "Creating NPM repository..."
    gcloud artifacts repositories create ${REPO_NAME}-npm \
        --repository-format=npm \
        --location=${REGION} \
        --description="NPM packages repository"
    
    log_info "Creating Maven repository..."
    gcloud artifacts repositories create ${REPO_NAME}-maven \
        --repository-format=maven \
        --location=${REGION} \
        --description="Maven packages repository"
    
    log_success "Artifact Registry repositories created successfully"
}

# Function to create Secret Manager secrets
create_secrets() {
    log_info "Creating Secret Manager secrets..."
    
    # Create secrets for different environment credentials
    log_info "Creating development environment secret..."
    echo -n "dev-registry-token-placeholder" | \
        gcloud secrets create ${SECRET_NAME}-dev \
        --data-file=- \
        --labels="environment=development,purpose=registry-auth"
    
    log_info "Creating staging environment secret..."
    echo -n "staging-registry-token-placeholder" | \
        gcloud secrets create ${SECRET_NAME}-staging \
        --data-file=- \
        --labels="environment=staging,purpose=registry-auth"
    
    log_info "Creating production environment secret..."
    echo -n "prod-registry-token-placeholder" | \
        gcloud secrets create ${SECRET_NAME}-prod \
        --data-file=- \
        --labels="environment=production,purpose=registry-auth"
    
    # Create secret for distribution configuration
    log_info "Creating distribution configuration secret..."
    cat <<EOF | gcloud secrets create distribution-config-${RANDOM_SUFFIX} \
        --data-file=- \
        --labels="purpose=distribution-config"
{
  "environments": {
    "development": {
      "endpoint": "dev.example.com",
      "timeout": 30
    },
    "staging": {
      "endpoint": "staging.example.com", 
      "timeout": 60
    },
    "production": {
      "endpoint": "prod.example.com",
      "timeout": 120
    }
  }
}
EOF
    
    log_success "Secret Manager secrets created and encrypted"
}

# Function to create IAM service account with least privilege access
create_service_account() {
    log_info "Creating IAM service account..."
    
    # Create service account for package distribution
    gcloud iam service-accounts create ${SERVICE_ACCOUNT_NAME} \
        --display-name="Package Distribution Service Account" \
        --description="Service account for automated package distribution workflows"
    
    # Grant necessary permissions for Artifact Registry
    log_info "Granting Artifact Registry permissions..."
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="roles/artifactregistry.reader"
    
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="roles/artifactregistry.writer"
    
    # Grant Secret Manager access
    log_info "Granting Secret Manager permissions..."
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="roles/secretmanager.secretAccessor"
    
    # Grant Cloud Functions and Cloud Tasks permissions
    log_info "Granting Cloud Functions and Tasks permissions..."
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="roles/cloudfunctions.invoker"
    
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="roles/cloudtasks.enqueuer"
    
    log_success "Service account created with appropriate permissions"
}

# Function to create Cloud Function
create_cloud_function() {
    log_info "Creating Cloud Function for package distribution..."
    
    # Create the function source code directory
    mkdir -p package-distributor-function
    cd package-distributor-function
    
    # Create requirements.txt for Python dependencies
    cat <<EOF > requirements.txt
google-cloud-artifactregistry==1.11.3
google-cloud-secret-manager==2.18.1
google-cloud-tasks==2.16.1
google-cloud-logging==3.8.0
docker==6.1.3
requests==2.31.0
google-auth==2.23.4
EOF
    
    # Create the main function code
    cat <<'EOF' > main.py
import json
import logging
import os
import time
from google.cloud import secretmanager
from google.cloud import tasks_v2
from google.cloud import logging as cloud_logging
import requests
from google.auth import default

# Initialize Cloud Logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def distribute_package(request):
    """Main function to handle package distribution requests."""
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'No JSON body provided'}, 400
        
        package_name = request_json.get('package_name')
        package_version = request_json.get('package_version', 'latest')
        target_environment = request_json.get('environment', 'development')
        
        if not package_name:
            return {'error': 'package_name is required'}, 400
        
        logger.info(f"Starting distribution of {package_name}:{package_version} to {target_environment}")
        
        # Retrieve credentials from Secret Manager
        credentials = get_environment_credentials(target_environment)
        if not credentials:
            return {'error': f'Failed to retrieve credentials for {target_environment}'}, 500
        
        # Get distribution configuration
        config = get_distribution_config()
        if not config:
            return {'error': 'Failed to retrieve distribution configuration'}, 500
        
        # Perform package distribution
        result = perform_distribution(package_name, package_version, target_environment, credentials, config)
        
        if result['success']:
            logger.info(f"Successfully distributed {package_name}:{package_version} to {target_environment}")
            return {
                'status': 'success',
                'message': f'Package {package_name}:{package_version} distributed to {target_environment}',
                'details': result
            }, 200
        else:
            logger.error(f"Failed to distribute {package_name}:{package_version}: {result['error']}")
            return {'error': result['error']}, 500
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {'error': f'Internal server error: {str(e)}'}, 500

def get_environment_credentials(environment):
    """Retrieve credentials for the specified environment from Secret Manager."""
    try:
        client = secretmanager.SecretManagerServiceClient()
        secret_name = f"projects/{os.environ.get('GCP_PROJECT')}/secrets/registry-credentials-{os.environ.get('RANDOM_SUFFIX')}-{environment}/versions/latest"
        
        response = client.access_secret_version(request={"name": secret_name})
        credentials = response.payload.data.decode("UTF-8")
        
        return credentials
    except Exception as e:
        logger.error(f"Failed to retrieve credentials for {environment}: {str(e)}")
        return None

def get_distribution_config():
    """Retrieve distribution configuration from Secret Manager."""
    try:
        client = secretmanager.SecretManagerServiceClient()
        secret_name = f"projects/{os.environ.get('GCP_PROJECT')}/secrets/distribution-config-{os.environ.get('RANDOM_SUFFIX')}/versions/latest"
        
        response = client.access_secret_version(request={"name": secret_name})
        config_json = response.payload.data.decode("UTF-8")
        
        return json.loads(config_json)
    except Exception as e:
        logger.error(f"Failed to retrieve distribution config: {str(e)}")
        return None

def perform_distribution(package_name, package_version, environment, credentials, config):
    """Perform the actual package distribution."""
    try:
        # Simulate package distribution logic
        env_config = config['environments'].get(environment)
        if not env_config:
            return {'success': False, 'error': f'No configuration for environment {environment}'}
        
        # Here you would implement actual distribution logic
        # This could include:
        # - Pulling from Artifact Registry
        # - Pushing to target registry
        # - Deploying to Kubernetes
        # - Updating service configurations
        
        logger.info(f"Distributing to endpoint: {env_config['endpoint']}")
        logger.info(f"Using timeout: {env_config['timeout']} seconds")
        
        # Simulate successful distribution
        return {
            'success': True,
            'package': f"{package_name}:{package_version}",
            'environment': environment,
            'endpoint': env_config['endpoint'],
            'timestamp': str(int(time.time()))
        }
        
    except Exception as e:
        return {'success': False, 'error': str(e)}
EOF
    
    # Deploy the Cloud Function
    log_info "Deploying Cloud Function..."
    gcloud functions deploy ${FUNCTION_NAME} \
        --runtime=python311 \
        --trigger=http \
        --entry-point=distribute_package \
        --service-account=${SERVICE_ACCOUNT_EMAIL} \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID},RANDOM_SUFFIX=${RANDOM_SUFFIX}" \
        --memory=512MB \
        --timeout=300s \
        --region=${REGION} \
        --allow-unauthenticated
    
    cd ..
    
    log_success "Cloud Function deployed successfully"
}

# Function to create Cloud Tasks queues
create_task_queues() {
    log_info "Creating Cloud Tasks queues..."
    
    # Create Cloud Tasks queue for package distribution
    log_info "Creating standard distribution queue..."
    gcloud tasks queues create package-distribution-queue \
        --location=${REGION} \
        --max-dispatches-per-second=10 \
        --max-concurrent-dispatches=5 \
        --max-attempts=3 \
        --max-retry-duration=3600s
    
    # Create queue for high-priority production distributions
    log_info "Creating production distribution queue..."
    gcloud tasks queues create prod-distribution-queue \
        --location=${REGION} \
        --max-dispatches-per-second=5 \
        --max-concurrent-dispatches=2 \
        --max-attempts=5 \
        --max-retry-duration=7200s
    
    log_success "Cloud Tasks queues created with appropriate retry policies"
}

# Function to create Cloud Scheduler jobs
create_scheduler_jobs() {
    log_info "Creating Cloud Scheduler jobs..."
    
    # Get the Cloud Function URL
    FUNCTION_URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    
    # Create scheduled job for nightly package updates
    log_info "Creating nightly distribution job..."
    gcloud scheduler jobs create http ${SCHEDULER_JOB}-nightly \
        --location=${REGION} \
        --schedule="0 2 * * *" \
        --time-zone="America/New_York" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"package_name":"webapp","package_version":"latest","environment":"development"}' \
        --description="Nightly package distribution to development environment"
    
    # Create job for weekly staging deployments
    log_info "Creating weekly staging deployment job..."
    gcloud scheduler jobs create http ${SCHEDULER_JOB}-weekly-staging \
        --location=${REGION} \
        --schedule="0 6 * * 1" \
        --time-zone="America/New_York" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"package_name":"webapp","package_version":"stable","environment":"staging"}' \
        --description="Weekly package distribution to staging environment"
    
    # Create job for production deployment (manual trigger recommended)
    log_info "Creating production deployment job template..."
    gcloud scheduler jobs create http ${SCHEDULER_JOB}-prod-manual \
        --location=${REGION} \
        --schedule="0 0 1 1 *" \
        --time-zone="America/New_York" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"package_name":"webapp","package_version":"release","environment":"production"}' \
        --description="Production package distribution (manual trigger recommended)"
    
    log_success "Cloud Scheduler jobs created for automated distribution"
}

# Function to set up monitoring and alerting
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."
    
    # Create log-based metric for distribution failures
    log_info "Creating distribution failure metric..."
    gcloud logging metrics create package_distribution_failures \
        --description="Count of package distribution failures" \
        --log-filter="resource.type=\"cloud_function\" 
                     resource.labels.function_name=\"${FUNCTION_NAME}\" 
                     severity=\"ERROR\"" \
        --value-extractor='EXTRACT(jsonPayload.error)'
    
    # Create log-based metric for successful distributions
    log_info "Creating distribution success metric..."
    gcloud logging metrics create package_distribution_success \
        --description="Count of successful package distributions" \
        --log-filter="resource.type=\"cloud_function\" 
                     resource.labels.function_name=\"${FUNCTION_NAME}\" 
                     jsonPayload.status=\"success\""
    
    # Create alerting policy for distribution failures
    log_info "Creating alerting policy..."
    cat <<EOF > alerting-policy.json
{
  "displayName": "Package Distribution Failures",
  "documentation": {
    "content": "Alert when package distribution failures exceed threshold"
  },
  "conditions": [
    {
      "displayName": "Distribution failure rate",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/package_distribution_failures\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 2,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF
    
    gcloud alpha monitoring policies create --policy-from-file=alerting-policy.json
    
    log_success "Monitoring and alerting configured for distribution workflows"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Artifact Registry repositories
    log_info "Validating Artifact Registry repositories..."
    gcloud artifacts repositories list \
        --location=${REGION} \
        --filter="name:${REPO_NAME}" \
        --format="table(name,format,createTime)"
    
    # Check Secret Manager secrets
    log_info "Validating Secret Manager secrets..."
    gcloud secrets list --filter="name:${SECRET_NAME}" --format="table(name,createTime)"
    
    # Check Cloud Function
    log_info "Validating Cloud Function..."
    gcloud functions describe ${FUNCTION_NAME} \
        --region=${REGION} \
        --format="table(name,status,runtime)"
    
    # Check Cloud Tasks queues
    log_info "Validating Cloud Tasks queues..."
    gcloud tasks queues list --location=${REGION} --format="table(name,state)"
    
    # Check Cloud Scheduler jobs
    log_info "Validating Cloud Scheduler jobs..."
    gcloud scheduler jobs list \
        --location=${REGION} \
        --filter="name:${SCHEDULER_JOB}" \
        --format="table(name,schedule,state)"
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Repository Name: ${REPO_NAME}"
    echo "Function Name: ${FUNCTION_NAME}"
    echo "Service Account: ${SERVICE_ACCOUNT_EMAIL}"
    echo "Random Suffix: ${RANDOM_SUFFIX}"
    echo
    echo "=== Next Steps ==="
    echo "1. Update the placeholder secrets in Secret Manager with actual credentials"
    echo "2. Test the Cloud Function with a sample request"
    echo "3. Configure the scheduler jobs for your specific requirements"
    echo "4. Set up notification channels for monitoring alerts"
    echo
    echo "=== Important Files ==="
    echo "- Environment variables saved in: .env"
    echo "- Function source code in: package-distributor-function/"
    echo "- Alerting policy in: alerting-policy.json"
    echo
    echo "=== Function URL ==="
    echo "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
    echo
    echo "To clean up all resources, run: ./destroy.sh"
}

# Main execution
main() {
    log_info "Starting secure package distribution workflow deployment..."
    
    check_prerequisites
    setup_environment
    enable_apis
    create_artifact_registry
    create_secrets
    create_service_account
    create_cloud_function
    create_task_queues
    create_scheduler_jobs
    setup_monitoring
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function
main "$@"