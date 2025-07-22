#!/bin/bash

# Deploy script for MLflow Model Lifecycle Management with Azure ML and Container Apps
# This script deploys the complete infrastructure for orchestrating MLflow model lifecycle management

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_error "Run ./destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.45.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.8 or later."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker from https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check pip packages
    local required_packages=("mlflow" "scikit-learn" "pandas" "numpy" "flask")
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import ${package}" &> /dev/null; then
            log_warning "Python package '${package}' not found. Installing..."
            pip3 install ${package} || {
                log_error "Failed to install ${package}. Please install manually."
                exit 1
            }
        fi
    done
    
    log_success "Prerequisites check completed successfully"
}

# Configuration
setup_configuration() {
    log_info "Setting up configuration..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-mlflow-lifecycle-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set service-specific variables
    export ML_WORKSPACE_NAME="${ML_WORKSPACE_NAME:-mlws-${RANDOM_SUFFIX}}"
    export CONTAINER_APP_ENV="${CONTAINER_APP_ENV:-cae-mlflow-${RANDOM_SUFFIX}}"
    export CONTAINER_APP_NAME="${CONTAINER_APP_NAME:-ca-model-serve-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stmlflow${RANDOM_SUFFIX}}"
    export KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-mlflow-${RANDOM_SUFFIX}}"
    export CONTAINER_REGISTRY_NAME="${CONTAINER_REGISTRY_NAME:-acrmlflow${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME:-law-mlflow-${RANDOM_SUFFIX}}"
    
    # Save configuration for cleanup script
    cat > "${SCRIPT_DIR}/deployment_config.env" << EOF
# Deployment configuration - $(date)
export RESOURCE_GROUP="${RESOURCE_GROUP}"
export LOCATION="${LOCATION}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export ML_WORKSPACE_NAME="${ML_WORKSPACE_NAME}"
export CONTAINER_APP_ENV="${CONTAINER_APP_ENV}"
export CONTAINER_APP_NAME="${CONTAINER_APP_NAME}"
export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME}"
export KEY_VAULT_NAME="${KEY_VAULT_NAME}"
export CONTAINER_REGISTRY_NAME="${CONTAINER_REGISTRY_NAME}"
export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    log_info "Configuration saved to deployment_config.env"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Unique Suffix: ${RANDOM_SUFFIX}"
    
    log_success "Configuration setup completed"
}

# Create foundational resources
create_foundational_resources() {
    log_info "Creating foundational resources..."
    
    # Create resource group
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=mlflow-lifecycle environment=demo deployment_timestamp="${TIMESTAMP}" || {
        log_error "Failed to create resource group"
        exit 1
    }
    log_success "Resource group created: ${RESOURCE_GROUP}"
    
    # Create storage account for ML workspace
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags purpose=mlflow-storage || {
        log_error "Failed to create storage account"
        exit 1
    }
    log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    
    # Create Key Vault for secrets management
    log_info "Creating Key Vault: ${KEY_VAULT_NAME}"
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku standard \
        --tags purpose=mlflow-secrets || {
        log_error "Failed to create Key Vault"
        exit 1
    }
    log_success "Key Vault created: ${KEY_VAULT_NAME}"
    
    # Create Container Registry for model images
    log_info "Creating Container Registry: ${CONTAINER_REGISTRY_NAME}"
    az acr create \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Basic \
        --admin-enabled true \
        --tags purpose=mlflow-containers || {
        log_error "Failed to create Container Registry"
        exit 1
    }
    log_success "Container Registry created: ${CONTAINER_REGISTRY_NAME}"
    
    log_success "Foundational resources created successfully"
}

# Create Azure ML workspace
create_ml_workspace() {
    log_info "Creating Azure Machine Learning workspace..."
    
    # Create Log Analytics workspace for monitoring
    log_info "Creating Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --location "${LOCATION}" \
        --tags purpose=mlflow-monitoring || {
        log_error "Failed to create Log Analytics workspace"
        exit 1
    }
    
    # Get Log Analytics workspace ID
    local log_analytics_id=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --query id --output tsv)
    
    # Create ML workspace with MLflow integration
    log_info "Creating ML workspace: ${ML_WORKSPACE_NAME}"
    az ml workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ML_WORKSPACE_NAME}" \
        --location "${LOCATION}" \
        --storage-account "${STORAGE_ACCOUNT_NAME}" \
        --key-vault "${KEY_VAULT_NAME}" \
        --container-registry "${CONTAINER_REGISTRY_NAME}" \
        --application-insights "${log_analytics_id}" \
        --tags purpose=mlflow-workspace || {
        log_error "Failed to create ML workspace"
        exit 1
    }
    
    log_success "ML Workspace created with MLflow integration: ${ML_WORKSPACE_NAME}"
}

# Setup MLflow and train sample model
setup_mlflow_model() {
    log_info "Setting up MLflow and training sample model..."
    
    # Install required Python packages
    log_info "Installing required Python packages..."
    pip3 install --quiet mlflow azureml-mlflow scikit-learn pandas numpy azureml-core || {
        log_error "Failed to install Python packages"
        exit 1
    }
    
    # Create working directory
    mkdir -p "${SCRIPT_DIR}/../mlflow-work"
    cd "${SCRIPT_DIR}/../mlflow-work"
    
    # Create MLflow configuration file
    cat > mlflow_config.py << 'EOF'
import mlflow
import os
from azureml.core import Workspace

# Connect to Azure ML workspace
try:
    ws = Workspace.get(
        name=os.environ['ML_WORKSPACE_NAME'], 
        subscription_id=os.environ['SUBSCRIPTION_ID'],
        resource_group=os.environ['RESOURCE_GROUP']
    )
    
    # Set MLflow tracking URI to Azure ML workspace
    mlflow.set_tracking_uri(ws.get_mlflow_tracking_uri())
    
    print(f"✅ MLflow configured for workspace: {ws.name}")
    print(f"Tracking URI: {mlflow.get_tracking_uri()}")
except Exception as e:
    print(f"❌ Error configuring MLflow: {e}")
    exit(1)
EOF
    
    # Create sample model training script
    cat > train_model.py << 'EOF'
import mlflow
import mlflow.sklearn
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, r2_score
import os

# Import configuration
exec(open('mlflow_config.py').read())

# Set experiment name
mlflow.set_experiment("model-lifecycle-demo")

# Generate sample data
np.random.seed(42)
n_samples = 1000
X = np.random.randn(n_samples, 4)
y = X[:, 0] + 2 * X[:, 1] - X[:, 2] + 0.5 * X[:, 3] + np.random.randn(n_samples) * 0.1

# Split data
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# Start MLflow run
with mlflow.start_run():
    # Train model
    model = RandomForestRegressor(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    
    # Make predictions
    y_pred = model.predict(X_test)
    
    # Calculate metrics
    mse = mean_squared_error(y_test, y_pred)
    r2 = r2_score(y_test, y_pred)
    
    # Log parameters and metrics
    mlflow.log_param("n_estimators", 100)
    mlflow.log_param("random_state", 42)
    mlflow.log_metric("mse", mse)
    mlflow.log_metric("r2_score", r2)
    
    # Log model
    mlflow.sklearn.log_model(
        model, 
        "model",
        registered_model_name="demo-regression-model",
        input_example=X_train[:5],
        signature=mlflow.models.infer_signature(X_train, y_train)
    )
    
    print(f"✅ Model trained and logged - MSE: {mse:.4f}, R2: {r2:.4f}")
EOF
    
    # Execute model training
    log_info "Training and registering sample model..."
    python3 train_model.py || {
        log_error "Failed to train and register model"
        exit 1
    }
    
    cd "${SCRIPT_DIR}"
    log_success "MLflow model training and registration completed"
}

# Create container app environment
create_container_environment() {
    log_info "Creating Container App environment..."
    
    # Get Log Analytics workspace ID
    local log_analytics_id=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --query id --output tsv)
    
    # Create Container Apps environment
    az containerapp env create \
        --name "${CONTAINER_APP_ENV}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --logs-workspace-id "${log_analytics_id}" \
        --tags purpose=mlflow-container-env || {
        log_error "Failed to create Container App environment"
        exit 1
    }
    
    log_success "Container App environment created: ${CONTAINER_APP_ENV}"
}

# Build and deploy model serving container
deploy_model_serving() {
    log_info "Building and deploying model serving container..."
    
    # Create model serving application directory
    mkdir -p "${SCRIPT_DIR}/../model-serving"
    cd "${SCRIPT_DIR}/../model-serving"
    
    # Create model serving application
    cat > app.py << 'EOF'
import os
import json
import mlflow
import mlflow.sklearn
import numpy as np
from flask import Flask, request, jsonify
from azureml.core import Workspace
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Initialize model
model = None
model_version = None

def load_model():
    global model, model_version
    try:
        # Connect to Azure ML workspace
        ws = Workspace.get(
            name=os.environ.get('ML_WORKSPACE_NAME', 'default'),
            subscription_id=os.environ.get('SUBSCRIPTION_ID'),
            resource_group=os.environ.get('RESOURCE_GROUP')
        )
        
        # Set MLflow tracking URI
        mlflow.set_tracking_uri(ws.get_mlflow_tracking_uri())
        
        # Load model from Azure ML registry
        model_name = os.environ.get('MODEL_NAME', 'demo-regression-model')
        model_version = os.environ.get('MODEL_VERSION', 'latest')
        
        # Load model using MLflow
        model_uri = f"models:/{model_name}/{model_version}"
        model = mlflow.sklearn.load_model(model_uri)
        
        logger.info(f"✅ Model loaded: {model_name} version {model_version}")
        return True
    except Exception as e:
        logger.error(f"❌ Error loading model: {e}")
        return False

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'healthy',
        'model_loaded': model is not None,
        'model_version': model_version,
        'service': 'mlflow-model-serving'
    })

@app.route('/predict', methods=['POST'])
def predict():
    try:
        if model is None:
            return jsonify({'error': 'Model not loaded'}), 500
        
        # Get input data
        data = request.get_json()
        if 'features' not in data:
            return jsonify({'error': 'Missing features in request'}), 400
            
        features = np.array(data['features']).reshape(1, -1)
        
        # Make prediction
        prediction = model.predict(features)
        
        return jsonify({
            'prediction': prediction.tolist(),
            'model_version': model_version,
            'status': 'success'
        })
    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/model-info', methods=['GET'])
def model_info():
    return jsonify({
        'model_name': os.environ.get('MODEL_NAME', 'demo-regression-model'),
        'model_version': model_version,
        'framework': 'sklearn',
        'status': 'active' if model is not None else 'inactive',
        'service': 'mlflow-model-serving'
    })

if __name__ == '__main__':
    load_model()
    app.run(host='0.0.0.0', port=8080)
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run application
CMD ["python", "app.py"]
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
flask==2.3.3
mlflow==2.8.0
azureml-mlflow==1.54.0
scikit-learn==1.3.0
numpy==1.24.3
pandas==2.0.3
azureml-core==1.54.0
gunicorn==21.2.0
EOF
    
    # Get ACR details
    local acr_login_server=$(az acr show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query loginServer --output tsv)
    
    # Log into ACR
    az acr login --name "${CONTAINER_REGISTRY_NAME}" || {
        log_error "Failed to login to Container Registry"
        exit 1
    }
    
    # Build container image
    log_info "Building container image..."
    docker build -t "${acr_login_server}/model-serving:latest" . || {
        log_error "Failed to build container image"
        exit 1
    }
    
    # Push image to ACR
    log_info "Pushing image to Container Registry..."
    docker push "${acr_login_server}/model-serving:latest" || {
        log_error "Failed to push container image"
        exit 1
    }
    
    # Get ACR credentials
    local acr_username=$(az acr credential show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --query username --output tsv)
    
    local acr_password=$(az acr credential show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --query passwords[0].value --output tsv)
    
    # Create container app
    log_info "Deploying container app..."
    az containerapp create \
        --name "${CONTAINER_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --environment "${CONTAINER_APP_ENV}" \
        --image "${acr_login_server}/model-serving:latest" \
        --registry-server "${acr_login_server}" \
        --registry-username "${acr_username}" \
        --registry-password "${acr_password}" \
        --target-port 8080 \
        --ingress external \
        --min-replicas 1 \
        --max-replicas 10 \
        --cpu 1.0 \
        --memory 2.0Gi \
        --env-vars \
            MODEL_NAME=demo-regression-model \
            MODEL_VERSION=latest \
            ML_WORKSPACE_NAME="${ML_WORKSPACE_NAME}" \
            SUBSCRIPTION_ID="${SUBSCRIPTION_ID}" \
            RESOURCE_GROUP="${RESOURCE_GROUP}" \
        --tags purpose=mlflow-model-serving || {
        log_error "Failed to create container app"
        exit 1
    }
    
    cd "${SCRIPT_DIR}"
    log_success "Model serving container deployed successfully"
}

# Configure monitoring and alerts
setup_monitoring() {
    log_info "Setting up monitoring and alerts..."
    
    # Get container app URL
    local container_app_url=$(az containerapp show \
        --name "${CONTAINER_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.configuration.ingress.fqdn --output tsv)
    
    # Create alert for high latency
    az monitor metrics alert create \
        --name "model-high-latency-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --description "Alert when model prediction latency exceeds threshold" \
        --condition "avg HttpResponseTime > 5000" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${CONTAINER_APP_NAME}" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --severity 2 \
        --tags purpose=mlflow-monitoring || {
        log_warning "Failed to create latency alert - continuing deployment"
    }
    
    # Create alert for container health
    az monitor metrics alert create \
        --name "container-app-unhealthy-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --description "Alert when container app replicas are unhealthy" \
        --condition "avg Replicas < 1" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${CONTAINER_APP_NAME}" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --severity 1 \
        --tags purpose=mlflow-monitoring || {
        log_warning "Failed to create health alert - continuing deployment"
    }
    
    # Save deployment info
    cat >> "${SCRIPT_DIR}/deployment_config.env" << EOF

# Deployment endpoints
export CONTAINER_APP_URL="https://${container_app_url}"
EOF
    
    log_success "Monitoring setup completed"
    log_info "Container App URL: https://${container_app_url}"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Source configuration
    source "${SCRIPT_DIR}/deployment_config.env"
    
    # Test container app health
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Testing container app health (attempt ${attempt}/${max_attempts})..."
        
        if curl -s -f "${CONTAINER_APP_URL}/health" > /dev/null 2>&1; then
            log_success "Container app health check passed"
            break
        else
            if [ $attempt -eq $max_attempts ]; then
                log_warning "Container app health check failed after ${max_attempts} attempts"
                log_warning "The app may still be starting up. Check manually: ${CONTAINER_APP_URL}/health"
            else
                log_info "Health check failed, retrying in 30 seconds..."
                sleep 30
            fi
        fi
        
        ((attempt++))
    done
    
    # Test model info endpoint
    if curl -s -f "${CONTAINER_APP_URL}/model-info" > /dev/null 2>&1; then
        log_success "Model info endpoint accessible"
    else
        log_warning "Model info endpoint not yet accessible"
    fi
    
    # Verify Azure ML workspace
    if az ml workspace show --name "${ML_WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        log_success "Azure ML workspace is accessible"
    else
        log_error "Azure ML workspace validation failed"
        exit 1
    fi
    
    log_success "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=============================================="
    echo "MLflow Model Lifecycle Management Deployment"
    echo "=============================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "ML Workspace: ${ML_WORKSPACE_NAME}"
    echo "Container App: ${CONTAINER_APP_NAME}"
    echo "Container Registry: ${CONTAINER_REGISTRY_NAME}"
    echo "Key Vault: ${KEY_VAULT_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo ""
    echo "Endpoints:"
    echo "- Model Serving: ${CONTAINER_APP_URL}"
    echo "- Health Check: ${CONTAINER_APP_URL}/health"
    echo "- Model Info: ${CONTAINER_APP_URL}/model-info"
    echo "- Predictions: ${CONTAINER_APP_URL}/predict (POST)"
    echo ""
    echo "Configuration saved to: ${SCRIPT_DIR}/deployment_config.env"
    echo "Logs available at: ${LOG_FILE}"
    echo ""
    echo "To test the deployment:"
    echo "curl ${CONTAINER_APP_URL}/health"
    echo "curl ${CONTAINER_APP_URL}/model-info"
    echo ""
    echo "To clean up resources:"
    echo "./destroy.sh"
    echo "=============================================="
}

# Main deployment function
main() {
    log_info "Starting MLflow Model Lifecycle Management deployment"
    log_info "Deployment started at: $(date)"
    
    check_prerequisites
    setup_configuration
    create_foundational_resources
    create_ml_workspace
    setup_mlflow_model
    create_container_environment
    deploy_model_serving
    setup_monitoring
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully at: $(date)"
    log_info "Total deployment time: $SECONDS seconds"
}

# Execute main function
main "$@"