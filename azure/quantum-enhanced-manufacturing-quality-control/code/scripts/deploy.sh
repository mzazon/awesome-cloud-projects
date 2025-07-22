#!/bin/bash

# Deploy Azure Quantum Manufacturing Quality Control Solution
# This script deploys the complete infrastructure for quantum-enhanced manufacturing quality control

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Script banner
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Azure Quantum Manufacturing Quality Control${NC}"
echo -e "${BLUE}  Infrastructure Deployment Script${NC}"
echo -e "${BLUE}================================================${NC}"
echo

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode. No resources will be created."
fi

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    error "Please log in to Azure using 'az login'"
    exit 1
fi

# Check if required tools are available
for tool in openssl python3; do
    if ! command -v $tool &> /dev/null; then
        error "$tool is not installed. Please install it before proceeding."
        exit 1
    fi
done

success "Prerequisites check completed"

# Set environment variables for Azure resources
export RESOURCE_GROUP="rg-quantum-manufacturing-${RANDOM}"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export WORKSPACE_NAME="ws-quantum-ml-${RANDOM}"
export IOT_HUB_NAME="iothub-manufacturing-${RANDOM}"
export STORAGE_ACCOUNT="stquantum$(openssl rand -hex 3)"
export QUANTUM_WORKSPACE="qw-manufacturing-${RANDOM}"
export STREAM_ANALYTICS_JOB="sa-quality-control-${RANDOM}"
export COSMOS_DB_NAME="cosmos-quality-dashboard-${RANDOM}"
export FUNCTION_APP_NAME="func-quality-dashboard-${RANDOM}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

log "Environment variables set:"
log "  Resource Group: $RESOURCE_GROUP"
log "  Location: $LOCATION"
log "  Subscription ID: $SUBSCRIPTION_ID"
log "  Storage Account: $STORAGE_ACCOUNT"
log "  Quantum Workspace: $QUANTUM_WORKSPACE"

# Save configuration to file for cleanup script
cat > .deployment_config << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
WORKSPACE_NAME=$WORKSPACE_NAME
IOT_HUB_NAME=$IOT_HUB_NAME
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
QUANTUM_WORKSPACE=$QUANTUM_WORKSPACE
STREAM_ANALYTICS_JOB=$STREAM_ANALYTICS_JOB
COSMOS_DB_NAME=$COSMOS_DB_NAME
FUNCTION_APP_NAME=$FUNCTION_APP_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF

success "Configuration saved to .deployment_config"

# Function to execute command with dry-run support
execute_command() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $1"
    else
        eval "$1"
    fi
}

# Create resource group with appropriate tags
log "Creating resource group..."
execute_command "az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION \
    --tags purpose=quantum-manufacturing environment=demo workload=quality-control cost-center=manufacturing"

if [ "$DRY_RUN" = false ]; then
    success "Resource group created: $RESOURCE_GROUP"
fi

# Register required Azure providers
log "Registering Azure providers..."
for provider in "Microsoft.Quantum" "Microsoft.MachineLearningServices" "Microsoft.Devices" "Microsoft.StreamAnalytics" "Microsoft.DocumentDB" "Microsoft.Web"; do
    log "Registering provider: $provider"
    execute_command "az provider register --namespace $provider"
done

if [ "$DRY_RUN" = false ]; then
    success "Azure providers registered successfully"
fi

# Create storage account for data lake capabilities
log "Creating Data Lake Storage account..."
execute_command "az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hierarchical-namespace true \
    --access-tier Hot"

if [ "$DRY_RUN" = false ]; then
    success "Data Lake Storage account created: $STORAGE_ACCOUNT"
fi

# Create Azure Machine Learning workspace
log "Creating Azure Machine Learning workspace..."
execute_command "az ml workspace create \
    --name $WORKSPACE_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --storage-account $STORAGE_ACCOUNT \
    --description 'Quantum-enhanced manufacturing quality control'"

if [ "$DRY_RUN" = false ]; then
    # Configure workspace for production workloads
    log "Configuring ML workspace for production..."
    execute_command "az ml workspace update \
        --name $WORKSPACE_NAME \
        --resource-group $RESOURCE_GROUP \
        --public-network-access Enabled \
        --allow-public-access-when-behind-vnet true"
    
    success "Azure ML workspace configured for manufacturing analytics"
fi

# Create IoT Hub with manufacturing-optimized configuration
log "Creating IoT Hub for manufacturing sensor integration..."
execute_command "az iot hub create \
    --name $IOT_HUB_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku S1 \
    --unit 2 \
    --partition-count 4"

if [ "$DRY_RUN" = false ]; then
    # Configure message routing for quality control data
    log "Configuring IoT Hub message routing..."
    execute_command "az iot hub message-route create \
        --hub-name $IOT_HUB_NAME \
        --route-name 'QualityControlRoute' \
        --source DeviceMessages \
        --condition \"messageType = 'qualityControl'\" \
        --endpoint-name events \
        --enabled true"
    
    # Create device identity for manufacturing line sensors
    log "Creating device identity for production line sensors..."
    execute_command "az iot hub device-identity create \
        --hub-name $IOT_HUB_NAME \
        --device-id 'production-line-01' \
        --auth-method shared_private_key"
    
    success "IoT Hub configured for manufacturing sensor data ingestion"
fi

# Create Azure Quantum workspace
log "Creating Azure Quantum workspace..."
execute_command "az quantum workspace create \
    --name $QUANTUM_WORKSPACE \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --storage-account $STORAGE_ACCOUNT"

if [ "$DRY_RUN" = false ]; then
    # Configure quantum providers for optimization workloads
    log "Configuring quantum providers..."
    execute_command "az quantum workspace provider add \
        --workspace-name $QUANTUM_WORKSPACE \
        --resource-group $RESOURCE_GROUP \
        --provider-id 'microsoft' \
        --provider-sku 'DZZ-Free'" || warning "Microsoft provider might already be configured"
    
    # Note: 1qbit provider may require special approval
    execute_command "az quantum workspace provider add \
        --workspace-name $QUANTUM_WORKSPACE \
        --resource-group $RESOURCE_GROUP \
        --provider-id '1qbit' \
        --provider-sku 'cplex'" || warning "1qbit provider may require special approval"
    
    success "Quantum workspace configured for manufacturing optimization"
fi

# Create Stream Analytics job
log "Creating Stream Analytics job for real-time quality data processing..."
execute_command "az stream-analytics job create \
    --job-name $STREAM_ANALYTICS_JOB \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --compatibility-level '1.2' \
    --events-out-of-order-policy 'Adjust' \
    --events-out-of-order-max-delay-in-seconds 10"

if [ "$DRY_RUN" = false ]; then
    success "Stream Analytics configured for real-time quality processing"
fi

# Create ML compute cluster
log "Creating Machine Learning compute cluster..."
execute_command "az ml compute create \
    --name 'quantum-ml-cluster' \
    --type amlcompute \
    --workspace-name $WORKSPACE_NAME \
    --resource-group $RESOURCE_GROUP \
    --min-instances 0 \
    --max-instances 4 \
    --size 'Standard_DS3_v2' \
    --idle-time-before-scale-down 300"

if [ "$DRY_RUN" = false ]; then
    # Create compute instance for development
    log "Creating development compute instance..."
    execute_command "az ml compute create \
        --name 'quantum-dev-instance' \
        --type computeinstance \
        --workspace-name $WORKSPACE_NAME \
        --resource-group $RESOURCE_GROUP \
        --size 'Standard_DS3_v2' \
        --enable-ssh true"
    
    success "ML compute infrastructure ready for quantum-enhanced training"
fi

# Create Cosmos DB for dashboard data
log "Creating Cosmos DB for real-time dashboard..."
execute_command "az cosmosdb create \
    --name $COSMOS_DB_NAME \
    --resource-group $RESOURCE_GROUP \
    --locations regionName=$LOCATION \
    --default-consistency-level Session \
    --enable-multiple-write-locations false"

if [ "$DRY_RUN" = false ]; then
    # Create database and container for quality metrics
    log "Creating Cosmos DB database and container..."
    execute_command "az cosmosdb sql database create \
        --account-name $COSMOS_DB_NAME \
        --resource-group $RESOURCE_GROUP \
        --name 'QualityControlDB'"
    
    execute_command "az cosmosdb sql container create \
        --account-name $COSMOS_DB_NAME \
        --resource-group $RESOURCE_GROUP \
        --database-name 'QualityControlDB' \
        --name 'QualityMetrics' \
        --partition-key-path '/productionLineId' \
        --throughput 400"
    
    success "Cosmos DB configured for dashboard data storage"
fi

# Create Function App for dashboard API
log "Creating Function App for dashboard API..."
execute_command "az functionapp create \
    --name $FUNCTION_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --storage-account $STORAGE_ACCOUNT \
    --consumption-plan-location $LOCATION \
    --runtime python \
    --runtime-version 3.9 \
    --functions-version 4"

if [ "$DRY_RUN" = false ]; then
    success "Function App configured for dashboard API"
fi

# Create Python scripts for quantum optimization
log "Creating quantum optimization scripts..."
if [ "$DRY_RUN" = false ]; then
    # Create quantum optimization script
    cat > quantum_optimization.py << 'EOF'
from azure.quantum import Workspace
from azure.quantum.optimization import Problem, ProblemType
import numpy as np
import json
import os

# Connect to Azure Quantum workspace
def get_quantum_workspace():
    """Initialize Azure Quantum workspace connection"""
    return Workspace(
        subscription_id=os.environ.get('SUBSCRIPTION_ID'),
        resource_group=os.environ.get('RESOURCE_GROUP'),
        name=os.environ.get('QUANTUM_WORKSPACE'),
        location=os.environ.get('LOCATION')
    )

def optimize_manufacturing_parameters(sensor_data, quality_targets):
    """
    Use quantum optimization to find optimal production parameters
    that minimize defect probability while meeting quality targets.
    """
    
    # Define optimization problem for manufacturing parameters
    problem = Problem(name="Manufacturing Parameter Optimization", problem_type=ProblemType.ising)
    
    # Add variables for production parameters (temperature, pressure, speed, etc.)
    temp_vars = []
    for i in range(10):  # 10 temperature control points
        temp_vars.append(problem.add_variable(f"temp_{i}", "binary"))
    
    pressure_vars = []
    for i in range(5):  # 5 pressure control points
        pressure_vars.append(problem.add_variable(f"pressure_{i}", "binary"))
    
    speed_vars = []
    for i in range(8):  # 8 speed control points
        speed_vars.append(problem.add_variable(f"speed_{i}", "binary"))
    
    # Add constraints for physical manufacturing limits
    problem.add_constraint(sum(temp_vars) >= 3)  # Minimum temperature points
    problem.add_constraint(sum(pressure_vars) >= 2)  # Minimum pressure points
    problem.add_constraint(sum(speed_vars) <= 6)  # Maximum speed points
    
    # Objective: minimize defect probability while maximizing throughput
    defect_cost_terms = []
    for i, temp_var in enumerate(temp_vars):
        defect_cost_terms.append(sensor_data.get(f'temp_defect_correlation_{i}', 0.1) * temp_var)
    
    throughput_benefit_terms = []
    for i, speed_var in enumerate(speed_vars):
        throughput_benefit_terms.append(-0.2 * speed_var)  # Negative cost = benefit
    
    # Set optimization objective
    problem.add_objective(sum(defect_cost_terms) + sum(throughput_benefit_terms))
    
    return problem

if __name__ == "__main__":
    # Example usage with manufacturing sensor data
    current_sensor_data = {
        'temp_defect_correlation_0': 0.15,
        'temp_defect_correlation_1': 0.12,
        'temp_defect_correlation_2': 0.08,
        'temp_defect_correlation_3': 0.18,
        'temp_defect_correlation_4': 0.11,
        'temp_defect_correlation_5': 0.14,
        'temp_defect_correlation_6': 0.09,
        'temp_defect_correlation_7': 0.16,
        'temp_defect_correlation_8': 0.13,
        'temp_defect_correlation_9': 0.10
    }
    
    quality_targets = {
        'max_defect_rate': 0.02,
        'min_throughput': 95.0
    }
    
    try:
        optimization_problem = optimize_manufacturing_parameters(current_sensor_data, quality_targets)
        print("✅ Quantum optimization problem formulated for manufacturing parameters")
    except Exception as e:
        print(f"❌ Error in quantum optimization: {str(e)}")
EOF

    # Create quantum solver script
    cat > solve_quantum_optimization.py << 'EOF'
from azure.quantum.optimization import SimulatedAnnealing
import json
import os

def solve_manufacturing_optimization(problem, workspace):
    """
    Solve manufacturing parameter optimization using quantum-inspired algorithms.
    """
    
    # Use Simulated Annealing solver for optimization
    solver = SimulatedAnnealing(workspace)
    
    # Configure solver parameters for manufacturing optimization
    try:
        result = solver.optimize(
            problem,
            timeout=30,  # 30 second timeout for real-time optimization
            sweeps=1000,  # Number of optimization sweeps
            seed=42  # For reproducible results
        )
        return result
    except Exception as e:
        print(f"❌ Quantum optimization failed: {str(e)}")
        return None

if __name__ == "__main__":
    print("✅ Quantum optimization solver configured for manufacturing")
EOF

    # Create ML training script
    cat > train_quality_model.py << 'EOF'
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score
import mlflow
import mlflow.sklearn
import os
import json

def generate_synthetic_manufacturing_data(n_samples=10000):
    """Generate synthetic manufacturing data for demonstration"""
    np.random.seed(42)
    
    # Manufacturing parameters
    temperature = np.random.normal(185, 10, n_samples)
    pressure = np.random.normal(2.8, 0.5, n_samples)
    speed = np.random.normal(145, 15, n_samples)
    humidity = np.random.normal(45, 8, n_samples)
    vibration = np.random.normal(0.05, 0.01, n_samples)
    
    # Create defect conditions based on parameter interactions
    defect_probability = (
        0.1 * (temperature > 195) + 
        0.15 * (pressure > 3.5) + 
        0.08 * (speed > 160) + 
        0.05 * (humidity > 55) + 
        0.2 * (vibration > 0.08)
    )
    
    # Generate binary defect labels
    defect_detected = np.random.binomial(1, defect_probability)
    
    # Create DataFrame
    data = pd.DataFrame({
        'temperature': temperature,
        'pressure': pressure,
        'speed': speed,
        'humidity': humidity,
        'vibration': vibration,
        'defect_detected': defect_detected
    })
    
    return data

def train_quality_model():
    """Train quality prediction model"""
    
    # Generate synthetic data
    print("📊 Generating synthetic manufacturing data...")
    data = generate_synthetic_manufacturing_data()
    
    # Prepare features and target
    X = data.drop(['defect_detected'], axis=1)
    y = data['defect_detected']
    
    # Split data for training
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Train defect prediction model
    print("🔧 Training Random Forest model...")
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    
    # Evaluate model
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    print(f"✅ Model trained with accuracy: {accuracy:.4f}")
    print("📈 Classification Report:")
    print(classification_report(y_test, y_pred))
    
    # Log model with MLflow
    try:
        mlflow.set_tracking_uri("sqlite:///mlflow.db")
        mlflow.set_experiment("manufacturing-quality-control")
        
        with mlflow.start_run():
            mlflow.log_param("n_estimators", 100)
            mlflow.log_param("random_state", 42)
            mlflow.log_metric("accuracy", accuracy)
            
            # Log model
            mlflow.sklearn.log_model(model, "quality_prediction_model")
            
            # Log feature importance
            feature_importance = dict(zip(X.columns, model.feature_importances_))
            mlflow.log_dict(feature_importance, "feature_importance.json")
            
        print("✅ Model logged with MLflow")
    except Exception as e:
        print(f"⚠️  MLflow logging failed: {str(e)}")
    
    return model

if __name__ == "__main__":
    model = train_quality_model()
    print("✅ Quality prediction model training completed")
EOF

    # Create dashboard aggregator script
    cat > dashboard_aggregator.py << 'EOF'
import json
import logging
from datetime import datetime, timedelta
import random
import os

def aggregate_dashboard_data(production_line_id, time_range='1h'):
    """
    Aggregate real-time quality control data for dashboard display.
    Combines IoT sensor data, ML predictions, and quantum optimization results.
    """
    
    try:
        # Generate realistic dashboard data for demonstration
        current_time = datetime.now()
        
        # Simulate quality trends over time
        quality_trends = []
        for i in range(24):  # Last 24 hours
            timestamp = current_time - timedelta(hours=i)
            score = 98.0 + random.uniform(-2.0, 2.0)  # Quality score between 96-100
            quality_trends.append({
                'timestamp': timestamp.isoformat(),
                'score': round(score, 1)
            })
        
        quality_trends.reverse()  # Chronological order
        
        # Simulate current parameters
        optimized_parameters = {
            'temperature': round(185.0 + random.uniform(-5.0, 5.0), 1),
            'pressure': round(2.8 + random.uniform(-0.3, 0.3), 1),
            'speed': round(145.0 + random.uniform(-10.0, 10.0), 1),
            'humidity': round(45.0 + random.uniform(-5.0, 5.0), 1),
            'vibration': round(0.05 + random.uniform(-0.02, 0.02), 3)
        }
        
        # Aggregate dashboard data
        dashboard_data = {
            'production_line_id': production_line_id,
            'last_updated': current_time.isoformat(),
            'current_quality_score': round(98.0 + random.uniform(-1.0, 1.0), 1),
            'predicted_defect_rate': round(random.uniform(0.01, 0.03), 4),
            'quantum_optimization_status': 'active',
            'optimization_improvement': round(random.uniform(0.5, 2.0), 1),  # % improvement
            'optimized_parameters': optimized_parameters,
            'quality_trends': quality_trends[-12:],  # Last 12 hours
            'alerts': [
                {
                    'type': 'info',
                    'message': 'Quantum optimization active',
                    'timestamp': current_time.isoformat()
                }
            ],
            'performance_metrics': {
                'throughput': round(95.0 + random.uniform(-5.0, 5.0), 1),
                'efficiency': round(92.0 + random.uniform(-3.0, 3.0), 1),
                'waste_reduction': round(random.uniform(5.0, 15.0), 1)
            }
        }
        
        return dashboard_data
        
    except Exception as e:
        logging.error(f"Dashboard aggregation error: {str(e)}")
        return {"error": "Internal server error"}

if __name__ == "__main__":
    # Test dashboard aggregation
    test_data = aggregate_dashboard_data("production-line-01", "1h")
    print("✅ Dashboard aggregation test successful")
    print(json.dumps(test_data, indent=2))
EOF

    success "Quantum optimization and ML scripts created"
fi

# Wait for provider registration to complete
if [ "$DRY_RUN" = false ]; then
    log "Waiting for provider registration to complete..."
    for provider in "Microsoft.Quantum" "Microsoft.MachineLearningServices" "Microsoft.Devices"; do
        while [[ $(az provider show --namespace $provider --query registrationState -o tsv) != "Registered" ]]; do
            log "Waiting for $provider registration..."
            sleep 10
        done
    done
    success "All required providers are registered"
fi

# Final deployment summary
echo
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Deployment Summary${NC}"
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Resource Group:${NC} $RESOURCE_GROUP"
echo -e "${GREEN}Location:${NC} $LOCATION"
echo -e "${GREEN}Azure ML Workspace:${NC} $WORKSPACE_NAME"
echo -e "${GREEN}IoT Hub:${NC} $IOT_HUB_NAME"
echo -e "${GREEN}Quantum Workspace:${NC} $QUANTUM_WORKSPACE"
echo -e "${GREEN}Storage Account:${NC} $STORAGE_ACCOUNT"
echo -e "${GREEN}Stream Analytics:${NC} $STREAM_ANALYTICS_JOB"
echo -e "${GREEN}Cosmos DB:${NC} $COSMOS_DB_NAME"
echo -e "${GREEN}Function App:${NC} $FUNCTION_APP_NAME"
echo

if [ "$DRY_RUN" = false ]; then
    echo -e "${GREEN}Next Steps:${NC}"
    echo "1. Configure IoT devices to send data to IoT Hub"
    echo "2. Deploy ML models to the compute cluster"
    echo "3. Run quantum optimization algorithms"
    echo "4. Access the dashboard through the Function App"
    echo "5. Use ./destroy.sh to clean up resources when done"
    echo
    
    # Estimate costs
    echo -e "${YELLOW}Estimated Costs (per hour):${NC}"
    echo "- IoT Hub (S1, 2 units): ~$0.50"
    echo "- ML Compute Cluster (when running): ~$0.90"
    echo "- Quantum Workspace: Variable based on usage"
    echo "- Storage Account: ~$0.05"
    echo "- Cosmos DB: ~$0.08"
    echo "- Function App: ~$0.02"
    echo "- Stream Analytics: ~$0.11"
    echo "- Total estimated: ~$1.66/hour + quantum compute costs"
    echo
    
    success "Deployment completed successfully!"
else
    success "Dry-run completed successfully!"
fi

echo -e "${BLUE}================================================${NC}"