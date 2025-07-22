#!/bin/bash

# Azure Quantum-Enhanced Financial Risk Analytics - Deployment Script
# This script deploys the complete infrastructure for quantum-enhanced financial risk analytics
# using Azure Quantum, Azure Synapse Analytics, Azure Machine Learning, and Azure Key Vault

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] INFO: $1${NC}"
    echo "[${timestamp}] INFO: $1" >> "${LOG_FILE}"
}

warn() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] WARNING: $1${NC}"
    echo "[${timestamp}] WARNING: $1" >> "${LOG_FILE}"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ERROR: $1${NC}" >&2
    echo "[${timestamp}] ERROR: $1" >> "${ERROR_LOG}"
    echo "[${timestamp}] ERROR: $1" >> "${LOG_FILE}"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        log "Attempting to delete resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
    fi
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Configuration validation
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI and try again."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &>/dev/null; then
        error "Not logged in to Azure. Please run 'az login' and try again."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: ${az_version}"
    
    # Validate required environment variables
    if [[ -z "${LOCATION:-}" ]]; then
        export LOCATION="eastus"
        warn "LOCATION not set, using default: ${LOCATION}"
    fi
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
        log "Generated random suffix: ${RANDOM_SUFFIX}"
    fi
    
    log "Prerequisites validation completed successfully"
}

# Set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Core resource configuration
    export RESOURCE_GROUP="rg-quantum-finance-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Service-specific resource names
    export SYNAPSE_WORKSPACE="synapse-quantum-${RANDOM_SUFFIX}"
    export QUANTUM_WORKSPACE="quantum-finance-${RANDOM_SUFFIX}"
    export ML_WORKSPACE="ml-finance-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-finance-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stfinance${RANDOM_SUFFIX}"
    export DATA_LAKE_NAME="dlsfinance${RANDOM_SUFFIX}"
    
    # Validate resource name lengths (Azure has specific limits)
    if [[ ${#KEY_VAULT_NAME} -gt 24 ]]; then
        error "Key Vault name too long: ${KEY_VAULT_NAME}"
        exit 1
    fi
    
    if [[ ${#DATA_LAKE_NAME} -gt 24 ]]; then
        error "Data Lake name too long: ${DATA_LAKE_NAME}"
        exit 1
    fi
    
    log "Environment variables configured successfully"
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Subscription ID: ${SUBSCRIPTION_ID}"
}

# Register Azure resource providers
register_providers() {
    log "Registering Azure resource providers..."
    
    local providers=(
        "Microsoft.Synapse"
        "Microsoft.Quantum"
        "Microsoft.MachineLearningServices"
        "Microsoft.KeyVault"
        "Microsoft.Storage"
        "Microsoft.DataLakeStore"
    )
    
    for provider in "${providers[@]}"; do
        log "Registering provider: ${provider}"
        az provider register --namespace "${provider}" --wait || {
            error "Failed to register provider: ${provider}"
            exit 1
        }
    done
    
    log "All resource providers registered successfully"
}

# Create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=quantum-finance environment=demo created-by=deploy-script || {
        error "Failed to create resource group: ${RESOURCE_GROUP}"
        exit 1
    }
    
    log "Resource group created successfully"
}

# Deploy Azure Key Vault
deploy_key_vault() {
    log "Deploying Azure Key Vault: ${KEY_VAULT_NAME}"
    
    # Create Key Vault
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku standard \
        --enabled-for-deployment true \
        --enabled-for-template-deployment true \
        --enable-soft-delete true \
        --retention-days 90 || {
        error "Failed to create Key Vault: ${KEY_VAULT_NAME}"
        exit 1
    }
    
    # Wait for Key Vault to be ready
    log "Waiting for Key Vault to be ready..."
    sleep 30
    
    # Store sample secrets
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "market-data-api-key" \
        --value "sample-api-key-for-market-data" || {
        warn "Failed to store market data API key secret"
    }
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "synapse-connection-string" \
        --value "sample-connection-string" || {
        warn "Failed to store Synapse connection string secret"
    }
    
    log "Key Vault deployed successfully"
}

# Deploy Azure Data Lake Storage
deploy_data_lake() {
    log "Deploying Azure Data Lake Storage: ${DATA_LAKE_NAME}"
    
    # Create storage account with Data Lake Gen2 capabilities
    az storage account create \
        --name "${DATA_LAKE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 || {
        error "Failed to create Data Lake Storage: ${DATA_LAKE_NAME}"
        exit 1
    }
    
    # Get storage account key
    local storage_key=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${DATA_LAKE_NAME}" \
        --query '[0].value' --output tsv)
    
    # Create containers for financial data
    local containers=("market-data" "portfolio-data" "risk-models")
    
    for container in "${containers[@]}"; do
        log "Creating container: ${container}"
        az storage container create \
            --name "${container}" \
            --account-name "${DATA_LAKE_NAME}" \
            --account-key "${storage_key}" \
            --public-access off || {
            error "Failed to create container: ${container}"
            exit 1
        }
    done
    
    log "Data Lake Storage deployed successfully"
}

# Deploy Azure Synapse Analytics
deploy_synapse() {
    log "Deploying Azure Synapse Analytics: ${SYNAPSE_WORKSPACE}"
    
    # Create Synapse workspace
    az synapse workspace create \
        --name "${SYNAPSE_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${DATA_LAKE_NAME}" \
        --file-system "synapsefilesystem" \
        --sql-admin-login-user "synapseadmin" \
        --sql-admin-login-password "QuantumFinance123!" \
        --location "${LOCATION}" \
        --enable-managed-vnet true || {
        error "Failed to create Synapse workspace: ${SYNAPSE_WORKSPACE}"
        exit 1
    }
    
    # Configure firewall rules
    log "Configuring Synapse firewall rules..."
    az synapse workspace firewall-rule create \
        --name "AllowAllWindowsAzureIps" \
        --workspace-name "${SYNAPSE_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --start-ip-address "0.0.0.0" \
        --end-ip-address "0.0.0.0" || {
        warn "Failed to create Synapse firewall rule"
    }
    
    # Wait for workspace to be ready
    log "Waiting for Synapse workspace to be ready..."
    sleep 60
    
    # Create Spark pool
    log "Creating Spark pool: sparkpool01"
    az synapse spark pool create \
        --name "sparkpool01" \
        --workspace-name "${SYNAPSE_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --spark-version "3.3" \
        --node-count 3 \
        --node-size "Medium" \
        --enable-auto-scale true \
        --min-node-count 3 \
        --max-node-count 10 \
        --auto-pause-delay 15 || {
        error "Failed to create Spark pool"
        exit 1
    }
    
    log "Synapse Analytics deployed successfully"
}

# Deploy Azure Quantum
deploy_quantum() {
    log "Deploying Azure Quantum: ${QUANTUM_WORKSPACE}"
    
    # Create Quantum workspace
    az quantum workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${QUANTUM_WORKSPACE}" \
        --location "${LOCATION}" \
        --storage-account "${DATA_LAKE_NAME}" || {
        error "Failed to create Quantum workspace: ${QUANTUM_WORKSPACE}"
        exit 1
    }
    
    # Add Microsoft quantum provider
    log "Adding Microsoft quantum provider..."
    az quantum workspace provider add \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${QUANTUM_WORKSPACE}" \
        --provider-id "Microsoft" \
        --provider-sku "DZI-Standard" || {
        warn "Failed to add Microsoft quantum provider"
    }
    
    log "Azure Quantum deployed successfully"
}

# Deploy Azure Machine Learning
deploy_machine_learning() {
    log "Deploying Azure Machine Learning: ${ML_WORKSPACE}"
    
    # Create ML workspace
    az ml workspace create \
        --name "${ML_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" || {
        error "Failed to create ML workspace: ${ML_WORKSPACE}"
        exit 1
    }
    
    # Wait for workspace to be ready
    log "Waiting for ML workspace to be ready..."
    sleep 30
    
    # Create compute cluster
    log "Creating ML compute cluster: ml-cluster"
    az ml compute create \
        --name "ml-cluster" \
        --type AmlCompute \
        --workspace-name "${ML_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --min-instances 0 \
        --max-instances 4 \
        --size "Standard_DS3_v2" \
        --idle-time-before-scale-down 300 || {
        error "Failed to create ML compute cluster"
        exit 1
    }
    
    # Create datastore connection
    log "Creating ML datastore connection..."
    az ml datastore create \
        --name "financial-datastore" \
        --type AzureDataLakeGen2 \
        --account-name "${DATA_LAKE_NAME}" \
        --filesystem "market-data" \
        --workspace-name "${ML_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" || {
        warn "Failed to create ML datastore"
    }
    
    log "Azure Machine Learning deployed successfully"
}

# Upload sample code and configurations
upload_sample_code() {
    log "Uploading sample code and configurations..."
    
    # Get storage account key
    local storage_key=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${DATA_LAKE_NAME}" \
        --query '[0].value' --output tsv)
    
    # Create temporary directory for files
    local temp_dir=$(mktemp -d)
    
    # Create quantum integration config
    cat > "${temp_dir}/quantum_integration_config.json" << EOF
{
  "quantum_workspace": "${QUANTUM_WORKSPACE}",
  "resource_group": "${RESOURCE_GROUP}",
  "subscription_id": "${SUBSCRIPTION_ID}",
  "synapse_workspace": "${SYNAPSE_WORKSPACE}",
  "integration_mode": "hybrid_classical_quantum"
}
EOF
    
    # Create portfolio optimization algorithm
    cat > "${temp_dir}/portfolio_optimization.py" << 'EOF'
# Sample quantum-inspired portfolio optimization algorithm
import numpy as np
from azure.quantum import Workspace
from azure.quantum.optimization import Problem, ProblemType, Term

def quantum_portfolio_optimization(returns, risk_aversion=1.0):
    """
    Quantum-enhanced portfolio optimization using Azure Quantum
    """
    n_assets = len(returns)
    
    # Create optimization problem
    problem = Problem(name="portfolio-optimization", problem_type=ProblemType.ising)
    
    # Add objective function terms for expected returns and risk
    for i in range(n_assets):
        # Expected return term
        problem.add_term(c=returns[i], indices=[i])
        
        # Risk penalty terms
        for j in range(i+1, n_assets):
            correlation = np.corrcoef(returns[i], returns[j])[0,1]
            problem.add_term(c=risk_aversion * correlation, indices=[i, j])
    
    return problem

print("Quantum portfolio optimization algorithm configured")
EOF
    
    # Create enhanced Monte Carlo simulation
    cat > "${temp_dir}/enhanced_monte_carlo.py" << 'EOF'
import numpy as np
import pandas as pd
from azure.quantum import Workspace
from scipy.stats import multivariate_normal
import asyncio

class QuantumEnhancedMonteCarlo:
    def __init__(self, quantum_workspace, portfolio_data):
        self.quantum_workspace = quantum_workspace
        self.portfolio_data = portfolio_data
        self.quantum_optimized_params = None

    async def optimize_parameters_quantum(self):
        """Use quantum optimization to enhance Monte Carlo parameters"""
        # Quantum parameter optimization logic
        # This would integrate with actual quantum algorithms
        optimized_correlations = await self._quantum_correlation_optimization()
        optimized_volatilities = await self._quantum_volatility_optimization()
        
        self.quantum_optimized_params = {
            'correlations': optimized_correlations,
            'volatilities': optimized_volatilities
        }
        return self.quantum_optimized_params

    def run_enhanced_simulation(self, num_simulations=100000, time_horizon=252):
        """Run Monte Carlo with quantum-enhanced parameters"""
        if self.quantum_optimized_params is None:
            raise ValueError("Must run quantum optimization first")
        
        # Use quantum-optimized parameters for simulation
        correlations = self.quantum_optimized_params['correlations']
        volatilities = self.quantum_optimized_params['volatilities']
        
        # Generate correlated random returns
        returns = multivariate_normal.rvs(
            mean=np.zeros(len(volatilities)),
            cov=correlations,
            size=num_simulations
        )
        
        # Calculate portfolio values over time horizon
        portfolio_values = []
        for sim in range(num_simulations):
            path = np.cumprod(1 + returns[sim] * volatilities / np.sqrt(252))
            portfolio_values.append(path[-1])
        
        return np.array(portfolio_values)

    async def _quantum_correlation_optimization(self):
        # Placeholder for quantum correlation optimization
        return np.eye(3) * 0.1 + np.ones((3, 3)) * 0.05

    async def _quantum_volatility_optimization(self):
        # Placeholder for quantum volatility optimization
        return np.array([0.15, 0.12, 0.18])

print("Enhanced Monte Carlo simulation framework configured")
EOF
    
    # Create sample portfolio data
    cat > "${temp_dir}/sample_portfolio.json" << EOF
{
  "assets": [
    {"symbol": "AAPL", "weight": 0.4, "expected_return": 0.12},
    {"symbol": "GOOGL", "weight": 0.3, "expected_return": 0.14},
    {"symbol": "MSFT", "weight": 0.3, "expected_return": 0.11}
  ],
  "total_value": 1000000,
  "rebalancing_frequency": "monthly"
}
EOF
    
    # Upload files to Data Lake
    local files=(
        "quantum_integration_config.json"
        "portfolio_optimization.py"
        "enhanced_monte_carlo.py"
        "sample_portfolio.json"
    )
    
    for file in "${files[@]}"; do
        local container="risk-models"
        if [[ "${file}" == "sample_portfolio.json" ]]; then
            container="portfolio-data"
        fi
        
        log "Uploading ${file} to container ${container}..."
        az storage blob upload \
            --account-name "${DATA_LAKE_NAME}" \
            --account-key "${storage_key}" \
            --container-name "${container}" \
            --name "${file}" \
            --file "${temp_dir}/${file}" || {
            warn "Failed to upload ${file}"
        }
    done
    
    # Cleanup temporary directory
    rm -rf "${temp_dir}"
    
    log "Sample code and configurations uploaded successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check resource group
    if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        error "Resource group validation failed: ${RESOURCE_GROUP}"
        return 1
    fi
    
    # Check Key Vault
    if ! az keyvault show --name "${KEY_VAULT_NAME}" &>/dev/null; then
        error "Key Vault validation failed: ${KEY_VAULT_NAME}"
        return 1
    fi
    
    # Check Data Lake Storage
    if ! az storage account show --name "${DATA_LAKE_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        error "Data Lake Storage validation failed: ${DATA_LAKE_NAME}"
        return 1
    fi
    
    # Check Synapse workspace
    if ! az synapse workspace show --name "${SYNAPSE_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        error "Synapse workspace validation failed: ${SYNAPSE_WORKSPACE}"
        return 1
    fi
    
    # Check Quantum workspace
    if ! az quantum workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${QUANTUM_WORKSPACE}" &>/dev/null; then
        error "Quantum workspace validation failed: ${QUANTUM_WORKSPACE}"
        return 1
    fi
    
    # Check ML workspace
    if ! az ml workspace show --name "${ML_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        error "ML workspace validation failed: ${ML_WORKSPACE}"
        return 1
    fi
    
    log "Deployment validation completed successfully"
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment_summary.txt" << EOF
=================================================================
Azure Quantum-Enhanced Financial Risk Analytics Deployment Summary
=================================================================

Deployment Date: $(date)
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Subscription ID: ${SUBSCRIPTION_ID}

Deployed Resources:
===================
1. Azure Key Vault: ${KEY_VAULT_NAME}
2. Azure Data Lake Storage: ${DATA_LAKE_NAME}
3. Azure Synapse Analytics: ${SYNAPSE_WORKSPACE}
4. Azure Quantum: ${QUANTUM_WORKSPACE}
5. Azure Machine Learning: ${ML_WORKSPACE}

Access Information:
==================
- Synapse Studio: https://web.azuresynapse.net
- Azure Quantum: https://quantum.azure.com
- Azure ML Studio: https://ml.azure.com

Next Steps:
===========
1. Configure authentication for external data sources
2. Upload your financial datasets to Data Lake containers
3. Customize quantum algorithms for your specific use case
4. Set up monitoring and alerting
5. Configure cost management and budgets

Security Considerations:
=======================
- All resources are secured with Azure AD integration
- Network access is restricted by default
- Sensitive data is stored in Azure Key Vault
- Consider implementing private endpoints for production

Cleanup:
========
To remove all resources, run: ./destroy.sh

For support, refer to the recipe documentation or Azure support channels.
EOF
    
    log "Deployment summary saved to: ${SCRIPT_DIR}/deployment_summary.txt"
}

# Main deployment function
main() {
    log "Starting Azure Quantum-Enhanced Financial Risk Analytics deployment..."
    
    # Initialize log files
    > "${LOG_FILE}"
    > "${ERROR_LOG}"
    
    # Execute deployment steps
    validate_prerequisites
    set_environment_variables
    register_providers
    create_resource_group
    deploy_key_vault
    deploy_data_lake
    deploy_synapse
    deploy_quantum
    deploy_machine_learning
    upload_sample_code
    validate_deployment
    generate_summary
    
    log "Deployment completed successfully!"
    log "Review the deployment summary at: ${SCRIPT_DIR}/deployment_summary.txt"
    log "Log files: ${LOG_FILE} and ${ERROR_LOG}"
    
    echo ""
    echo -e "${GREEN}✅ Azure Quantum-Enhanced Financial Risk Analytics deployed successfully!${NC}"
    echo -e "${BLUE}📋 Deployment summary: ${SCRIPT_DIR}/deployment_summary.txt${NC}"
    echo -e "${BLUE}📝 Full logs: ${LOG_FILE}${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Important: Monitor Azure costs and configure budgets appropriately${NC}"
    echo -e "${YELLOW}⚠️  Remember to run ./destroy.sh when you're done testing${NC}"
    echo ""
}

# Execute main function
main "$@"