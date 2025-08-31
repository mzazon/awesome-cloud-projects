#!/bin/bash

# Deploy script for AI Application Testing with Evaluation Flows and AI Foundry
# This script creates Azure resources for automated AI quality testing and evaluation

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script metadata
SCRIPT_NAME="deploy.sh"
SCRIPT_VERSION="1.0"
RECIPE_NAME="ai-application-testing-evaluation-flows-foundry"

# Logging configuration
LOG_FILE="/tmp/${RECIPE_NAME}_deploy_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number. Check $LOG_FILE for details."
    log_error "Deployment failed. Resources may be partially created."
    log_error "Run destroy.sh to clean up any created resources."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Display script header
echo "=========================================="
echo "Azure AI Testing Recipe Deployment Script"
echo "Recipe: $RECIPE_NAME"
echo "Version: $SCRIPT_VERSION"
echo "Log file: $LOG_FILE"
echo "=========================================="

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required tools are available
    for tool in openssl python3 pip; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "All prerequisites validated"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RESOURCE_GROUP="rg-ai-testing-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export AI_SERVICES_NAME="ai-testing-svc-${RANDOM_SUFFIX}"
    export MODEL_DEPLOYMENT_NAME="gpt-4o-mini-eval"
    export STORAGE_ACCOUNT="aitesting${RANDOM_SUFFIX}"
    
    log_info "Environment variables:"
    log_info "  RESOURCE_GROUP: $RESOURCE_GROUP"
    log_info "  LOCATION: $LOCATION"
    log_info "  AI_SERVICES_NAME: $AI_SERVICES_NAME"
    log_info "  STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
    log_info "  SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    
    # Save environment variables for cleanup script
    cat > /tmp/${RECIPE_NAME}_env.sh << EOF
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export AI_SERVICES_NAME="$AI_SERVICES_NAME"
export MODEL_DEPLOYMENT_NAME="$MODEL_DEPLOYMENT_NAME"
export STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=ai-testing environment=demo recipe="$RECIPE_NAME" \
        --output table
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

# Function to create AI Services resource
create_ai_services() {
    log_info "Creating Azure AI Services resource: $AI_SERVICES_NAME"
    
    # Check if AI Services is available in the region
    local available_kinds=$(az cognitiveservices account list-kinds --location "$LOCATION" --query "[?contains(@, 'AIServices')]" -o tsv)
    if [[ -z "$available_kinds" ]]; then
        log_warning "AIServices not available in $LOCATION, trying OpenAI instead"
        local kind="OpenAI"
    else
        local kind="AIServices"
    fi
    
    az cognitiveservices account create \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind "$kind" \
        --sku S0 \
        --custom-domain "$AI_SERVICES_NAME" \
        --output table
    
    # Wait for resource to be ready
    log_info "Waiting for AI Services resource to be ready..."
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        local state=$(az cognitiveservices account show \
            --name "$AI_SERVICES_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "properties.provisioningState" -o tsv)
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        fi
        
        log_info "Attempt $attempt/$max_attempts: AI Services state is $state"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "AI Services resource failed to become ready"
        exit 1
    fi
    
    # Get AI Services endpoint
    export AI_ENDPOINT=$(az cognitiveservices account show \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.endpoint" --output tsv)
    
    log_success "AI Services resource created: $AI_SERVICES_NAME"
    log_info "AI Services endpoint: $AI_ENDPOINT"
}

# Function to create model deployment
create_model_deployment() {
    log_info "Creating GPT-4O-mini model deployment: $MODEL_DEPLOYMENT_NAME"
    
    # Create the model deployment
    az cognitiveservices account deployment create \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$MODEL_DEPLOYMENT_NAME" \
        --model-name gpt-4o-mini \
        --model-version "2024-07-18" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        --output table
    
    # Wait for deployment to be ready
    log_info "Waiting for model deployment to be ready..."
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        local state=$(az cognitiveservices account deployment show \
            --name "$AI_SERVICES_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "$MODEL_DEPLOYMENT_NAME" \
            --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        fi
        
        log_info "Attempt $attempt/$max_attempts: Model deployment state is $state"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Model deployment failed to become ready"
        exit 1
    fi
    
    log_success "Model deployment created: $MODEL_DEPLOYMENT_NAME"
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --output table
    
    # Wait for storage account to be ready
    log_info "Waiting for storage account to be ready..."
    local max_attempts=20
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        local state=$(az storage account show \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query "provisioningState" -o tsv)
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        fi
        
        log_info "Attempt $attempt/$max_attempts: Storage account state is $state"
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Storage account failed to become ready"
        exit 1
    fi
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query '[0].value' --output tsv)
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

# Function to create storage container and upload test data
setup_test_data() {
    log_info "Setting up test data and storage container..."
    
    # Create container for test data
    az storage container create \
        --name test-datasets \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --output table
    
    # Create test dataset
    cat > /tmp/test_data.jsonl << 'EOF'
{"query": "What is the capital of France?", "context": "France is a country in Western Europe with Paris as its capital city.", "ground_truth": "Paris"}
{"query": "How does photosynthesis work?", "context": "Photosynthesis is the process by which plants convert sunlight into chemical energy using chlorophyll.", "ground_truth": "Plants use chlorophyll to convert sunlight, carbon dioxide, and water into glucose and oxygen"}
{"query": "What is machine learning?", "context": "Machine learning is a subset of artificial intelligence that enables computers to learn from data.", "ground_truth": "A branch of AI that allows systems to automatically learn and improve from experience without explicit programming"}
{"query": "Explain quantum computing", "context": "Quantum computing uses quantum mechanical phenomena like superposition and entanglement to process information.", "ground_truth": "A computing paradigm that leverages quantum mechanics principles to perform calculations exponentially faster than classical computers for certain problems"}
{"query": "What causes climate change?", "context": "Climate change is primarily caused by human activities that increase greenhouse gas concentrations in the atmosphere.", "ground_truth": "Human activities, particularly burning fossil fuels and deforestation, increase greenhouse gases leading to global warming"}
EOF
    
    # Upload test dataset
    az storage blob upload \
        --file /tmp/test_data.jsonl \
        --container-name test-datasets \
        --name ai-test-dataset.jsonl \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --output table
    
    log_success "Test data uploaded to storage container"
}

# Function to create evaluation flow files
create_evaluation_flow() {
    log_info "Creating evaluation flow structure..."
    
    # Create evaluation flow directory
    mkdir -p evaluation_flow
    
    # Create flow configuration
    cat > evaluation_flow/flow.dag.yaml << 'EOF'
$schema: https://azuremlschemas.azureedge.net/promptflow/1.0.0/flow.schema.json
inputs:
  query:
    type: string
  response:
    type: string
  context:
    type: string
  ground_truth:
    type: string
outputs:
  groundedness_score:
    type: object
    reference: ${evaluate_groundedness.output}
  relevance_score:
    type: object
    reference: ${evaluate_relevance.output}
  coherence_score:
    type: object
    reference: ${evaluate_coherence.output}
  overall_score:
    type: object
    reference: ${calculate_overall.output}
nodes:
- name: evaluate_groundedness
  type: python
  source:
    type: code
    path: groundedness_evaluator.py
  inputs:
    query: ${inputs.query}
    response: ${inputs.response}
    context: ${inputs.context}
- name: evaluate_relevance
  type: python
  source:
    type: code
    path: relevance_evaluator.py
  inputs:
    query: ${inputs.query}
    response: ${inputs.response}
    context: ${inputs.context}
- name: evaluate_coherence
  type: python
  source:
    type: code
    path: coherence_evaluator.py
  inputs:
    query: ${inputs.query}
    response: ${inputs.response}
- name: calculate_overall
  type: python
  source:
    type: code
    path: overall_calculator.py
  inputs:
    groundedness: ${evaluate_groundedness.output}
    relevance: ${evaluate_relevance.output}
    coherence: ${evaluate_coherence.output}
EOF
    
    # Create Python evaluation scripts
    create_evaluation_scripts
    
    # Create requirements file
    cat > evaluation_flow/requirements.txt << 'EOF'
azure-ai-evaluation>=1.0.0
azure-identity>=1.12.0
openai>=1.0.0
azure-ai-projects>=1.0.0
promptflow>=1.0.0
EOF
    
    log_success "Evaluation flow structure created"
}

# Function to create evaluation Python scripts
create_evaluation_scripts() {
    log_info "Creating evaluation Python scripts..."
    
    # Groundedness evaluator
    cat > evaluation_flow/groundedness_evaluator.py << 'EOF'
from azure.ai.evaluation import GroundednessEvaluator
import os

def main(query: str, response: str, context: str):
    """Evaluate groundedness of AI response against provided context."""
    try:
        # Initialize evaluator with model configuration
        model_config = {
            "azure_endpoint": os.environ.get("AZURE_OPENAI_ENDPOINT"),
            "api_key": os.environ.get("AZURE_OPENAI_API_KEY"),
            "azure_deployment": os.environ.get("AZURE_OPENAI_DEPLOYMENT")
        }
        
        evaluator = GroundednessEvaluator(model_config=model_config)
        
        # Evaluate groundedness
        result = evaluator(
            query=query,
            response=response,
            context=context
        )
        
        return {
            "groundedness": result.get("groundedness", 0),
            "reasoning": result.get("reasoning", ""),
            "status": "success"
        }
    except Exception as e:
        return {
            "groundedness": 0,
            "reasoning": f"Evaluation failed: {str(e)}",
            "status": "error"
        }
EOF
    
    # Relevance evaluator
    cat > evaluation_flow/relevance_evaluator.py << 'EOF'
from azure.ai.evaluation import RelevanceEvaluator
import os

def main(query: str, response: str, context: str):
    """Evaluate relevance of AI response to the query."""
    try:
        model_config = {
            "azure_endpoint": os.environ.get("AZURE_OPENAI_ENDPOINT"),
            "api_key": os.environ.get("AZURE_OPENAI_API_KEY"),
            "azure_deployment": os.environ.get("AZURE_OPENAI_DEPLOYMENT")
        }
        
        evaluator = RelevanceEvaluator(model_config=model_config)
        
        result = evaluator(
            query=query,
            response=response,
            context=context
        )
        
        return {
            "relevance": result.get("relevance", 0),
            "reasoning": result.get("reasoning", ""),
            "status": "success"
        }
    except Exception as e:
        return {
            "relevance": 0,
            "reasoning": f"Evaluation failed: {str(e)}",
            "status": "error"
        }
EOF
    
    # Coherence evaluator
    cat > evaluation_flow/coherence_evaluator.py << 'EOF'
from azure.ai.evaluation import CoherenceEvaluator
import os

def main(query: str, response: str):
    """Evaluate coherence and logical flow of AI response."""
    try:
        model_config = {
            "azure_endpoint": os.environ.get("AZURE_OPENAI_ENDPOINT"),
            "api_key": os.environ.get("AZURE_OPENAI_API_KEY"),
            "azure_deployment": os.environ.get("AZURE_OPENAI_DEPLOYMENT")
        }
        
        evaluator = CoherenceEvaluator(model_config=model_config)
        
        result = evaluator(
            query=query,
            response=response
        )
        
        return {
            "coherence": result.get("coherence", 0),
            "reasoning": result.get("reasoning", ""),
            "status": "success"
        }
    except Exception as e:
        return {
            "coherence": 0,
            "reasoning": f"Evaluation failed: {str(e)}",
            "status": "error"
        }
EOF
    
    # Overall calculator
    cat > evaluation_flow/overall_calculator.py << 'EOF'
def main(groundedness, relevance, coherence):
    """Calculate weighted overall score from individual evaluation metrics."""
    try:
        # Extract scores (handling both dict and direct numeric values)
        groundedness_score = groundedness.get("groundedness", 0) if isinstance(groundedness, dict) else groundedness
        relevance_score = relevance.get("relevance", 0) if isinstance(relevance, dict) else relevance
        coherence_score = coherence.get("coherence", 0) if isinstance(coherence, dict) else coherence
        
        # Calculate weighted overall score
        # Groundedness is most critical for factual accuracy
        weights = {
            "groundedness": 0.5,
            "relevance": 0.3,
            "coherence": 0.2
        }
        
        overall_score = (
            groundedness_score * weights["groundedness"] +
            relevance_score * weights["relevance"] +
            coherence_score * weights["coherence"]
        )
        
        # Determine quality tier and threshold pass
        if overall_score >= 4.0:
            quality_tier = "Excellent"
            pass_threshold = True
        elif overall_score >= 3.0:
            quality_tier = "Good"
            pass_threshold = True
        elif overall_score >= 2.0:
            quality_tier = "Fair"
            pass_threshold = False
        else:
            quality_tier = "Poor"
            pass_threshold = False
        
        return {
            "overall_score": round(overall_score, 2),
            "quality_tier": quality_tier,
            "pass_threshold": pass_threshold,
            "individual_scores": {
                "groundedness": groundedness_score,
                "relevance": relevance_score,
                "coherence": coherence_score
            },
            "weights_used": weights,
            "status": "success"
        }
    except Exception as e:
        return {
            "overall_score": 0,
            "quality_tier": "Error",
            "pass_threshold": False,
            "individual_scores": {},
            "status": f"error: {str(e)}"
        }
EOF
    
    log_success "Evaluation Python scripts created"
}

# Function to create CI/CD pipeline files
create_pipeline_files() {
    log_info "Creating Azure DevOps pipeline configuration..."
    
    # Create pipeline directory
    mkdir -p .azuredevops/pipelines
    
    # Create Azure DevOps pipeline
    cat > .azuredevops/pipelines/ai-testing-pipeline.yml << 'EOF'
trigger:
  branches:
    include:
    - main
    - develop

variables:
  azureServiceConnection: 'azure-service-connection'
  resourceGroup: '$(RESOURCE_GROUP)'
  aiServicesName: '$(AI_SERVICES_NAME)'
  storageAccount: '$(STORAGE_ACCOUNT)'
  modelDeploymentName: '$(MODEL_DEPLOYMENT_NAME)'

stages:
- stage: Test
  displayName: 'AI Quality Testing'
  jobs:
  - job: EvaluateAIApplication
    displayName: 'Run Evaluation Flow'
    pool:
      vmImage: 'ubuntu-latest'
    
    steps:
    - task: UsePythonVersion@0
      inputs:
        versionSpec: '3.9'
        addToPath: true
      displayName: 'Setup Python 3.9'
    
    - task: AzureCLI@2
      displayName: 'Install AI Evaluation SDK'
      inputs:
        azureSubscription: $(azureServiceConnection)
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          pip install azure-ai-evaluation[remote] \
                      azure-identity azure-ai-projects \
                      promptflow azure-core
    
    - task: AzureCLI@2
      displayName: 'Run AI Evaluation'
      inputs:
        azureSubscription: $(azureServiceConnection)
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          # Set environment variables for evaluation
          export AZURE_OPENAI_ENDPOINT=$(az cognitiveservices account show \
              --name $(aiServicesName) \
              --resource-group $(resourceGroup) \
              --query "properties.endpoint" --output tsv)
          export AZURE_OPENAI_API_KEY=$(az cognitiveservices account keys list \
              --name $(aiServicesName) \
              --resource-group $(resourceGroup) \
              --query "key1" --output tsv)
          export AZURE_OPENAI_DEPLOYMENT=$(modelDeploymentName)
          
          # Download test data
          az storage blob download \
              --container-name test-datasets \
              --name ai-test-dataset.jsonl \
              --file test_data.jsonl \
              --account-name $(storageAccount) \
              --auth-mode login
          
          # Run Python evaluation script
          python run_evaluation.py \
              --data-path test_data.jsonl \
              --output-path evaluation_results.json
          
          # Check quality gates
          python check_quality_gates.py evaluation_results.json
    
    - task: PublishTestResults@2
      displayName: 'Publish Evaluation Results'
      inputs:
        testResultsFormat: 'JUnit'
        testResultsFiles: 'evaluation_results.xml'
        failTaskOnFailedTests: true
      condition: always()

- stage: Deploy
  displayName: 'Deploy to Production'
  dependsOn: Test
  condition: succeeded()
  jobs:
  - deployment: DeployAIApplication
    displayName: 'Deploy AI Application'
    environment: 'production'
    strategy:
      runOnce:
        deploy:
          steps:
          - script: |
              echo "Deploying AI application to production"
              echo "All quality gates passed successfully"
            displayName: 'Deploy Application'
EOF
    
    log_success "Azure DevOps pipeline configuration created"
}

# Function to create evaluation runner and quality gate scripts
create_evaluation_scripts_main() {
    log_info "Creating evaluation runner and quality gate scripts..."
    
    # Create evaluation runner script
    cat > run_evaluation.py << 'EOF'
#!/usr/bin/env python3
"""
AI Application Evaluation Runner
Executes evaluation flow against test data and generates quality metrics.
"""

import argparse
import json
import os
import sys
from pathlib import Path
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def mock_ai_application(query: str, context: str = "") -> str:
    """
    Mock AI application for demonstration purposes.
    In production, this would call your actual AI application.
    """
    # Simple mock responses based on query content
    mock_responses = {
        "capital of France": "Paris is the capital and largest city of France.",
        "photosynthesis": "Photosynthesis is the process by which plants convert light energy into chemical energy using chlorophyll.",
        "machine learning": "Machine learning is a subset of artificial intelligence that enables computers to learn and make decisions from data.",
        "quantum computing": "Quantum computing is a type of computation that harnesses quantum mechanical phenomena like superposition and entanglement.",
        "climate change": "Climate change is primarily caused by human activities that increase greenhouse gas concentrations in the atmosphere."
    }
    
    # Find best matching response
    query_lower = query.lower()
    for key, response in mock_responses.items():
        if key in query_lower:
            return response
    
    # Default response if no match found
    return f"This is a mock response to the query: {query}"

def run_simple_evaluation(data_path: str, output_path: str) -> dict:
    """Run a simplified evaluation without Azure AI SDK for demonstration."""
    logger.info(f"Running simplified evaluation on {data_path}")
    
    # Read test data
    test_cases = []
    with open(data_path, 'r') as f:
        for line in f:
            if line.strip():
                test_cases.append(json.loads(line))
    
    logger.info(f"Loaded {len(test_cases)} test cases")
    
    # Run evaluation on each test case
    results = []
    for i, test_case in enumerate(test_cases):
        logger.info(f"Evaluating test case {i+1}/{len(test_cases)}")
        
        query = test_case['query']
        context = test_case.get('context', '')
        ground_truth = test_case.get('ground_truth', '')
        
        # Get AI application response
        response = mock_ai_application(query, context)
        
        # Simple scoring based on keyword matching and response quality
        scores = calculate_simple_scores(query, response, context, ground_truth)
        
        result = {
            'query': query,
            'response': response,
            'context': context,
            'ground_truth': ground_truth,
            'scores': scores
        }
        results.append(result)
    
    # Calculate overall metrics
    overall_results = calculate_overall_metrics(results)
    
    # Save results
    with open(output_path, 'w') as f:
        json.dump(overall_results, f, indent=2)
    
    logger.info(f"Evaluation completed. Results saved to {output_path}")
    return overall_results

def calculate_simple_scores(query: str, response: str, context: str, ground_truth: str) -> dict:
    """Calculate simple evaluation scores based on text similarity and quality heuristics."""
    
    # Simple groundedness score (how well response relates to context)
    groundedness = calculate_text_similarity(response, context)
    
    # Simple relevance score (how well response answers the query)
    relevance = calculate_text_similarity(response, query) + calculate_text_similarity(response, ground_truth)
    relevance = min(relevance, 5.0)  # Cap at 5.0
    
    # Simple coherence score (response length and structure quality)
    coherence = calculate_coherence_score(response)
    
    return {
        'groundedness': round(groundedness, 2),
        'relevance': round(relevance, 2),
        'coherence': round(coherence, 2)
    }

def calculate_text_similarity(text1: str, text2: str) -> float:
    """Simple text similarity based on common words."""
    words1 = set(text1.lower().split())
    words2 = set(text2.lower().split())
    
    if not words1 or not words2:
        return 0.0
    
    common_words = words1.intersection(words2)
    similarity = len(common_words) / max(len(words1), len(words2))
    
    # Scale to 1-5 range
    return 1.0 + (similarity * 4.0)

def calculate_coherence_score(response: str) -> float:
    """Simple coherence score based on response structure."""
    if not response or len(response.strip()) < 10:
        return 1.0
    
    # Basic coherence indicators
    words = response.split()
    sentences = response.split('.')
    
    # Score based on response length and structure
    length_score = min(len(words) / 20.0, 1.0)  # Optimal around 20 words
    sentence_score = min(len(sentences) / 3.0, 1.0)  # Good to have 2-3 sentences
    
    coherence = 2.0 + (length_score * 2.0) + (sentence_score * 1.0)
    return min(coherence, 5.0)

def calculate_overall_metrics(results: list) -> dict:
    """Calculate overall metrics from individual test results."""
    if not results:
        return {"error": "No results to calculate metrics from"}
    
    # Calculate average scores
    total_groundedness = sum(r['scores']['groundedness'] for r in results)
    total_relevance = sum(r['scores']['relevance'] for r in results)
    total_coherence = sum(r['scores']['coherence'] for r in results)
    
    avg_groundedness = total_groundedness / len(results)
    avg_relevance = total_relevance / len(results)
    avg_coherence = total_coherence / len(results)
    
    # Calculate weighted overall score
    weights = {"groundedness": 0.5, "relevance": 0.3, "coherence": 0.2}
    overall_score = (
        avg_groundedness * weights["groundedness"] +
        avg_relevance * weights["relevance"] +
        avg_coherence * weights["coherence"]
    )
    
    # Determine quality tier
    if overall_score >= 4.0:
        quality_tier = "Excellent"
        pass_threshold = True
    elif overall_score >= 3.0:
        quality_tier = "Good"
        pass_threshold = True
    elif overall_score >= 2.0:
        quality_tier = "Fair"
        pass_threshold = False
    else:
        quality_tier = "Poor"
        pass_threshold = False
    
    return {
        "overall_score": round(overall_score, 2),
        "quality_tier": quality_tier,
        "pass_threshold": pass_threshold,
        "individual_scores": {
            "groundedness": round(avg_groundedness, 2),
            "relevance": round(avg_relevance, 2),
            "coherence": round(avg_coherence, 2)
        },
        "weights_used": weights,
        "test_cases_evaluated": len(results),
        "detailed_results": results
    }

def main():
    parser = argparse.ArgumentParser(description='Run AI application evaluation')
    parser.add_argument('--data-path', required=True, help='Path to test data JSONL file')
    parser.add_argument('--output-path', required=True, help='Path to save evaluation results')
    args = parser.parse_args()
    
    try:
        # Check if test data file exists
        if not os.path.exists(args.data_path):
            logger.error(f"Test data file not found: {args.data_path}")
            sys.exit(1)
        
        # Run evaluation
        results = run_simple_evaluation(args.data_path, args.output_path)
        
        logger.info("Evaluation Summary:")
        logger.info(f"  Overall Score: {results['overall_score']}")
        logger.info(f"  Quality Tier: {results['quality_tier']}")
        logger.info(f"  Pass Threshold: {results['pass_threshold']}")
        logger.info(f"  Test Cases: {results['test_cases_evaluated']}")
        
        if results['pass_threshold']:
            logger.info("✅ Evaluation passed quality thresholds")
        else:
            logger.warning("⚠️  Evaluation did not meet quality thresholds")
            
    except Exception as e:
        logger.error(f"Evaluation failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    
    # Create quality gate checker script  
    cat > check_quality_gates.py << 'EOF'
#!/usr/bin/env python3
"""
Quality Gate Checker for AI Application Testing
Validates evaluation results against defined quality thresholds.
"""

import json
import sys
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def check_quality_gates(results_file: str) -> bool:
    """Check if evaluation results meet quality thresholds."""
    
    # Define quality thresholds
    THRESHOLDS = {
        "overall_score": 3.0,
        "groundedness": 3.0,
        "relevance": 2.5,
        "coherence": 2.5
    }
    
    try:
        # Load evaluation results
        with open(results_file, 'r') as f:
            results = json.load(f)
        
        logger.info("=== Quality Gate Assessment ===")
        
        # Extract scores from results
        overall_score = results.get("overall_score", 0)
        individual_scores = results.get("individual_scores", {})
        quality_tier = results.get("quality_tier", "Unknown")
        test_cases = results.get("test_cases_evaluated", 0)
        
        logger.info(f"Test Cases Evaluated: {test_cases}")
        logger.info(f"Overall Score: {overall_score}")
        logger.info(f"Quality Tier: {quality_tier}")
        logger.info(f"Individual Scores: {individual_scores}")
        
        # Check overall threshold
        passed_gates = []
        failed_gates = []
        
        if overall_score >= THRESHOLDS["overall_score"]:
            passed_gates.append(f"Overall Score: {overall_score} >= {THRESHOLDS['overall_score']}")
            logger.info(f"✅ Overall score threshold passed: {overall_score}")
        else:
            failed_gates.append(f"Overall Score: {overall_score} < {THRESHOLDS['overall_score']}")
            logger.error(f"❌ Overall score {overall_score} below threshold {THRESHOLDS['overall_score']}")
        
        # Check individual score thresholds
        for metric, threshold in THRESHOLDS.items():
            if metric == "overall_score":
                continue
                
            score = individual_scores.get(metric, 0)
            if score >= threshold:
                passed_gates.append(f"{metric.title()}: {score} >= {threshold}")
                logger.info(f"✅ {metric} threshold passed: {score}")
            else:
                failed_gates.append(f"{metric.title()}: {score} < {threshold}")
                logger.error(f"❌ {metric} score {score} below threshold {threshold}")
        
        # Summary
        logger.info(f"\n=== Quality Gate Summary ===")
        logger.info(f"Passed Gates: {len(passed_gates)}")
        logger.info(f"Failed Gates: {len(failed_gates)}")
        
        if failed_gates:
            logger.error("❌ Quality gate check failed!")
            logger.error("Failed gates:")
            for gate in failed_gates:
                logger.error(f"  - {gate}")
            logger.error("🚫 Deployment blocked due to quality issues")
            return False
        else:
            logger.info("✅ All quality gates passed!")
            logger.info("Passed gates:")
            for gate in passed_gates:
                logger.info(f"  - {gate}")
            logger.info("🚀 Proceeding with deployment")
            return True
            
    except FileNotFoundError:
        logger.error(f"❌ Results file not found: {results_file}")
        return False
    except json.JSONDecodeError as e:
        logger.error(f"❌ Invalid JSON in results file: {str(e)}")
        return False
    except Exception as e:
        logger.error(f"❌ Error checking quality gates: {str(e)}")
        return False

def main():
    if len(sys.argv) != 2:
        logger.error("Usage: python check_quality_gates.py <results_file>")
        sys.exit(1)
    
    results_file = sys.argv[1]
    
    # Check if results file exists
    if not os.path.exists(results_file):
        logger.error(f"Results file does not exist: {results_file}")
        sys.exit(1)
    
    # Run quality gate check
    passed = check_quality_gates(results_file)
    
    # Exit with appropriate code
    sys.exit(0 if passed else 1)

if __name__ == "__main__":
    main()
EOF
    
    # Make scripts executable
    chmod +x run_evaluation.py check_quality_gates.py
    
    log_success "Evaluation runner and quality gate scripts created"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_success "Resource group verified: $RESOURCE_GROUP"
    else
        log_error "Resource group not found: $RESOURCE_GROUP"
        exit 1
    fi
    
    # Check AI Services
    local ai_state=$(az cognitiveservices account show \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" -o tsv)
    if [[ "$ai_state" == "Succeeded" ]]; then
        log_success "AI Services verified: $AI_SERVICES_NAME"
    else
        log_error "AI Services not ready: $AI_SERVICES_NAME (state: $ai_state)"
        exit 1
    fi
    
    # Check model deployment
    local model_state=$(az cognitiveservices account deployment show \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$MODEL_DEPLOYMENT_NAME" \
        --query "properties.provisioningState" -o tsv)
    if [[ "$model_state" == "Succeeded" ]]; then
        log_success "Model deployment verified: $MODEL_DEPLOYMENT_NAME"
    else
        log_error "Model deployment not ready: $MODEL_DEPLOYMENT_NAME (state: $model_state)"
        exit 1
    fi
    
    # Check storage account
    local storage_state=$(az storage account show \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "provisioningState" -o tsv)
    if [[ "$storage_state" == "Succeeded" ]]; then
        log_success "Storage account verified: $STORAGE_ACCOUNT"
    else
        log_error "Storage account not ready: $STORAGE_ACCOUNT (state: $storage_state)"
        exit 1
    fi
    
    # Test evaluation scripts
    if [[ -f "run_evaluation.py" && -f "check_quality_gates.py" ]]; then
        log_success "Evaluation scripts created and ready"
    else
        log_error "Evaluation scripts not found"
        exit 1
    fi
    
    log_success "All deployment verifications passed"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "=========================================="
    echo ""
    echo "📋 Deployed Resources:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • AI Services: $AI_SERVICES_NAME"
    echo "  • Model Deployment: $MODEL_DEPLOYMENT_NAME"
    echo "  • Storage Account: $STORAGE_ACCOUNT"
    echo "  • Test Data Container: test-datasets"
    echo ""
    echo "📁 Created Files:"
    echo "  • evaluation_flow/ - Evaluation flow structure"
    echo "  • .azuredevops/pipelines/ - CI/CD pipeline configuration"
    echo "  • run_evaluation.py - Evaluation runner script"
    echo "  • check_quality_gates.py - Quality gate checker"
    echo "  • /tmp/test_data.jsonl - Test dataset"
    echo ""
    echo "🔧 Environment Variables (saved to /tmp/${RECIPE_NAME}_env.sh):"
    echo "  • RESOURCE_GROUP=$RESOURCE_GROUP"
    echo "  • AI_SERVICES_NAME=$AI_SERVICES_NAME"
    echo "  • STORAGE_ACCOUNT=$STORAGE_ACCOUNT"
    echo ""
    echo "🧪 Next Steps:"
    echo "  1. Test the evaluation system:"
    echo "     python run_evaluation.py --data-path /tmp/test_data.jsonl --output-path results.json"
    echo "  2. Check quality gates:"
    echo "     python check_quality_gates.py results.json"
    echo "  3. Set up Azure DevOps service connection to use the pipeline"
    echo "  4. Customize evaluation thresholds in check_quality_gates.py"
    echo ""
    echo "💰 Estimated Monthly Cost: $15-25 USD"
    echo "   (Based on minimal usage of OpenAI models and storage)"
    echo ""
    echo "📜 Log file: $LOG_FILE"
    echo "🧹 To clean up: ./destroy.sh"
    echo "=========================================="
}

# Main execution
main() {
    log_info "Starting deployment of AI Application Testing with Evaluation Flows"
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_ai_services
    create_model_deployment
    create_storage_account
    setup_test_data
    create_evaluation_flow
    create_pipeline_files
    create_evaluation_scripts_main
    verify_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function
main "$@"