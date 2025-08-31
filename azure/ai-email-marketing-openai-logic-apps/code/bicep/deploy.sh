#!/bin/bash

# AI-Powered Email Marketing Infrastructure Deployment Script
# This script deploys the complete Azure infrastructure for AI email marketing

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
LOCATION="eastus"
ENVIRONMENT="dev"
PROJECT_NAME="emailmarketing"
UNIQUE_SUFFIX=""
PARAMETERS_FILE="parameters.json"
TEMPLATE_FILE="main.bicep"
DRY_RUN=false
SKIP_PREREQUISITES=false

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AI-Powered Email Marketing Infrastructure

Options:
    -g, --resource-group RESOURCE_GROUP    Resource group name (required)
    -l, --location LOCATION               Azure region (default: eastus)
    -e, --environment ENVIRONMENT         Environment: dev|staging|prod (default: dev)
    -p, --project-name PROJECT_NAME       Project name (default: emailmarketing)
    -s, --suffix SUFFIX                   Unique suffix for resources
    -f, --parameters-file FILE            Parameters file (default: parameters.json)
    -t, --template-file FILE              Template file (default: main.bicep)
    -d, --dry-run                         Validate template without deploying
    --skip-prerequisites                  Skip prerequisite checks
    -h, --help                           Show this help message

Examples:
    $0 -g rg-email-marketing-dev
    $0 -g rg-email-marketing-prod -e prod -f parameters.prod.json
    $0 -g rg-email-marketing-test -d  # Dry run validation only

EOF
}

# Function to check prerequisites
check_prerequisites() {
    if [ "$SKIP_PREREQUISITES" = true ]; then
        print_message $YELLOW "⚠️  Skipping prerequisite checks"
        return 0
    fi

    print_message $BLUE "🔍 Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_message $RED "❌ Azure CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if Bicep CLI is installed
    if ! az bicep version &> /dev/null; then
        print_message $YELLOW "⚠️  Bicep CLI not found. Installing..."
        az bicep install
    fi

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_message $RED "❌ Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Check if template file exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_message $RED "❌ Template file '$TEMPLATE_FILE' not found."
        exit 1
    fi

    # Check if parameters file exists
    if [ ! -f "$PARAMETERS_FILE" ]; then
        print_message $RED "❌ Parameters file '$PARAMETERS_FILE' not found."
        exit 1
    fi

    print_message $GREEN "✅ Prerequisites check passed"
}

# Function to create resource group if it doesn't exist
create_resource_group() {
    print_message $BLUE "🏗️  Checking resource group '$RESOURCE_GROUP'..."

    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_message $YELLOW "📦 Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags Environment="$ENVIRONMENT" Project="AI Email Marketing" \
            --output none
        print_message $GREEN "✅ Resource group created successfully"
    else
        print_message $GREEN "✅ Resource group already exists"
    fi
}

# Function to validate template
validate_template() {
    print_message $BLUE "🔍 Validating Bicep template..."

    local validation_result
    validation_result=$(az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters @"$PARAMETERS_FILE" \
        --output json 2>&1)

    if [ $? -eq 0 ]; then
        print_message $GREEN "✅ Template validation successful"
        
        # Show what will be deployed
        print_message $BLUE "📋 Resources to be deployed:"
        echo "$validation_result" | jq -r '.properties.validatedResources[]? | "  - \(.type): \(.name)"' 2>/dev/null || echo "  (Unable to parse resource list)"
    else
        print_message $RED "❌ Template validation failed:"
        echo "$validation_result"
        exit 1
    fi
}

# Function to deploy template
deploy_template() {
    if [ "$DRY_RUN" = true ]; then
        print_message $YELLOW "🔍 Dry run mode - skipping actual deployment"
        return 0
    fi

    print_message $BLUE "🚀 Starting deployment..."

    local deployment_name="email-marketing-$(date +%Y%m%d-%H%M%S)"
    
    print_message $YELLOW "📊 Deployment name: $deployment_name"
    print_message $YELLOW "📍 Resource group: $RESOURCE_GROUP"
    print_message $YELLOW "🌍 Location: $LOCATION"
    print_message $YELLOW "🏷️  Environment: $ENVIRONMENT"

    # Start deployment
    local deployment_result
    deployment_result=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$deployment_name" \
        --template-file "$TEMPLATE_FILE" \
        --parameters @"$PARAMETERS_FILE" \
        --mode Incremental \
        --output json)

    if [ $? -eq 0 ]; then
        print_message $GREEN "✅ Deployment completed successfully!"
        
        # Extract and display outputs
        print_message $BLUE "📤 Deployment outputs:"
        echo "$deployment_result" | jq -r '.properties.outputs | to_entries[] | "  \(.key): \(.value.value)"' 2>/dev/null || echo "  (Unable to parse outputs)"
        
        # Display post-deployment instructions
        show_post_deployment_instructions
    else
        print_message $RED "❌ Deployment failed"
        echo "$deployment_result"
        exit 1
    fi
}

# Function to show post-deployment instructions
show_post_deployment_instructions() {
    print_message $BLUE "📋 Post-deployment configuration steps:"
    
    cat << EOF

1. 🔑 Verify Azure OpenAI Service:
   az cognitiveservices account deployment list \\
       --name "${PROJECT_NAME}-openai-${UNIQUE_SUFFIX}" \\
       --resource-group "$RESOURCE_GROUP" \\
       --output table

2. 📧 Check email domain status:
   az communication email domain show \\
       --domain-name "AzureManagedDomain" \\
       --resource-group "$RESOURCE_GROUP" \\
       --email-service-name "${PROJECT_NAME}-email-${UNIQUE_SUFFIX}" \\
       --output table

3. 🔧 Deploy Logic App workflows:
   - Open Azure Portal
   - Navigate to Logic Apps Standard resource
   - Create and configure email marketing workflows

4. 📊 Set up monitoring:
   - Configure Application Insights alerts
   - Create custom dashboards for campaign metrics

5. 🧪 Test the system:
   - Test OpenAI content generation
   - Send test emails through Communication Services
   - Verify end-to-end workflow execution

6. 💰 Monitor costs:
   - Set up budget alerts
   - Review Azure OpenAI token usage
   - Monitor email delivery metrics

EOF

    print_message $GREEN "🎉 Deployment completed! Check the resources in the Azure Portal."
}

# Function to show resource information
show_resource_info() {
    print_message $BLUE "📋 Listing deployed resources..."
    
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name,Type:type,Location:location,Status:properties.provisioningState}" \
        --output table
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
                print_message $RED "❌ Environment must be one of: dev, staging, prod"
                exit 1
            fi
            shift 2
            ;;
        -p|--project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -s|--suffix)
            UNIQUE_SUFFIX="$2"
            shift 2
            ;;
        -f|--parameters-file)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -t|--template-file)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_message $RED "❌ Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$RESOURCE_GROUP" ]; then
    print_message $RED "❌ Resource group name is required"
    print_usage
    exit 1
fi

# Generate unique suffix if not provided
if [ -z "$UNIQUE_SUFFIX" ]; then
    UNIQUE_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
fi

# Main execution
print_message $GREEN "🚀 AI-Powered Email Marketing Infrastructure Deployment"
print_message $BLUE "=================================================="

print_message $YELLOW "Configuration:"
print_message $YELLOW "  Resource Group: $RESOURCE_GROUP"
print_message $YELLOW "  Location: $LOCATION"
print_message $YELLOW "  Environment: $ENVIRONMENT"
print_message $YELLOW "  Project Name: $PROJECT_NAME"
print_message $YELLOW "  Unique Suffix: $UNIQUE_SUFFIX"
print_message $YELLOW "  Parameters File: $PARAMETERS_FILE"
print_message $YELLOW "  Template File: $TEMPLATE_FILE"
print_message $YELLOW "  Dry Run: $DRY_RUN"

echo ""

# Execute deployment steps
check_prerequisites
create_resource_group
validate_template
deploy_template

if [ "$DRY_RUN" = false ]; then
    show_resource_info
fi

print_message $GREEN "🎉 Script completed successfully!"