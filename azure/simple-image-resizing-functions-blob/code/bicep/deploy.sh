#!/bin/bash

# ===========================================
# Azure Image Resizing Solution Deployment Script
# ===========================================
# This script deploys the complete image resizing infrastructure using Bicep

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
LOCATION="East US"
ENVIRONMENT="dev"
UNIQUE_SUFFIX=""
FUNCTION_PLAN_SKU="Y1"
STORAGE_SKU="Standard_LRS"
ENABLE_INSIGHTS="true"
DEPLOY_FUNCTION_CODE="false"
DRY_RUN="false"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Azure Image Resizing Solution Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -g, --resource-group     Resource group name (required)
    -l, --location          Azure region (default: East US)
    -e, --environment       Environment name (default: dev)
    -s, --suffix           Unique suffix for resource names
    -p, --plan-sku         Function App plan SKU (Y1|EP1|EP2|EP3, default: Y1)
    -t, --storage-sku      Storage account SKU (Standard_LRS|Standard_ZRS|Standard_GRS|Premium_LRS, default: Standard_LRS)
    -i, --insights         Enable Application Insights (true|false, default: true)
    -f, --function-code    Deploy function code after infrastructure (true|false, default: false)
    -d, --dry-run          Validate template without deploying (default: false)
    -h, --help             Show this help message

EXAMPLES:
    # Basic deployment
    $0 -g rg-image-resize-demo

    # Production deployment with Premium plan
    $0 -g rg-image-resize-prod -e prod -p EP1 -t Standard_ZRS

    # Development deployment without Application Insights
    $0 -g rg-image-resize-dev -e dev -i false

    # Validate template without deploying
    $0 -g rg-image-resize-test -d true

    # Full deployment including function code
    $0 -g rg-image-resize-demo -f true

PREREQUISITES:
    - Azure CLI installed and configured (az login)
    - Contributor access to Azure subscription
    - For function code deployment: Azure Functions Core Tools (func)

EOF
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
            shift 2
            ;;
        -s|--suffix)
            UNIQUE_SUFFIX="$2"
            shift 2
            ;;
        -p|--plan-sku)
            FUNCTION_PLAN_SKU="$2"
            shift 2
            ;;
        -t|--storage-sku)
            STORAGE_SKU="$2"
            shift 2
            ;;
        -i|--insights)
            ENABLE_INSIGHTS="$2"
            shift 2
            ;;
        -f|--function-code)
            DEPLOY_FUNCTION_CODE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    print_error "Resource group name is required"
    show_usage
    exit 1
fi

# Validate Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Generate unique suffix if not provided
if [[ -z "$UNIQUE_SUFFIX" ]]; then
    UNIQUE_SUFFIX=$(date +%s | tail -c 4)$(printf "%02d" $((RANDOM % 100)))
    print_status "Generated unique suffix: $UNIQUE_SUFFIX"
fi

# Validate function plan SKU
case $FUNCTION_PLAN_SKU in
    Y1|EP1|EP2|EP3)
        ;;
    *)
        print_error "Invalid function plan SKU: $FUNCTION_PLAN_SKU. Must be Y1, EP1, EP2, or EP3"
        exit 1
        ;;
esac

# Validate storage SKU
case $STORAGE_SKU in
    Standard_LRS|Standard_ZRS|Standard_GRS|Premium_LRS)
        ;;
    *)
        print_error "Invalid storage SKU: $STORAGE_SKU"
        exit 1
        ;;
esac

print_status "=== Azure Image Resizing Solution Deployment ==="
print_status "Resource Group: $RESOURCE_GROUP"
print_status "Location: $LOCATION"
print_status "Environment: $ENVIRONMENT"
print_status "Unique Suffix: $UNIQUE_SUFFIX"
print_status "Function Plan: $FUNCTION_PLAN_SKU"
print_status "Storage SKU: $STORAGE_SKU"
print_status "Application Insights: $ENABLE_INSIGHTS"
print_status "Deploy Function Code: $DEPLOY_FUNCTION_CODE"
print_status "Dry Run: $DRY_RUN"

# Confirm deployment
if [[ "$DRY_RUN" != "true" ]]; then
    echo
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled by user"
        exit 0
    fi
fi

# Create resource group if it doesn't exist
print_status "Checking resource group: $RESOURCE_GROUP"
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_status "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags Environment="$ENVIRONMENT" Purpose="ImageResizing" CreatedBy="DeployScript"
    print_success "Resource group created"
else
    print_status "Resource group already exists"
fi

# Prepare deployment parameters
DEPLOYMENT_NAME="image-resize-$(date +%Y%m%d-%H%M%S)"
TEMPLATE_FILE="main.bicep"

# Build parameters
PARAMETERS="environment=$ENVIRONMENT"
PARAMETERS="$PARAMETERS location=$LOCATION"
PARAMETERS="$PARAMETERS uniqueSuffix=$UNIQUE_SUFFIX"
PARAMETERS="$PARAMETERS functionAppPlanSku=$FUNCTION_PLAN_SKU"
PARAMETERS="$PARAMETERS storageAccountSku=$STORAGE_SKU"
PARAMETERS="$PARAMETERS enableApplicationInsights=$ENABLE_INSIGHTS"

print_status "Deployment name: $DEPLOYMENT_NAME"
print_status "Template file: $TEMPLATE_FILE"

# Validate template
print_status "Validating Bicep template..."
if ! az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters $PARAMETERS > /dev/null; then
    print_error "Template validation failed"
    exit 1
fi
print_success "Template validation passed"

# Exit if dry run
if [[ "$DRY_RUN" == "true" ]]; then
    print_success "Dry run completed successfully"
    exit 0
fi

# Deploy the template
print_status "Starting deployment..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --template-file "$TEMPLATE_FILE" \
    --parameters $PARAMETERS \
    --output json)

if [[ $? -eq 0 ]]; then
    print_success "Infrastructure deployment completed successfully"
    
    # Extract outputs
    STORAGE_ACCOUNT=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.storageAccountName.value')
    FUNCTION_APP=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.functionAppName.value')
    FUNCTION_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.functionAppUrl.value')
    
    print_success "Storage Account: $STORAGE_ACCOUNT"
    print_success "Function App: $FUNCTION_APP"
    print_success "Function URL: $FUNCTION_URL"
    
    # Save outputs to file
    OUTPUT_FILE="deployment-outputs-$(date +%Y%m%d-%H%M%S).json"
    echo "$DEPLOYMENT_OUTPUT" | jq '.properties.outputs' > "$OUTPUT_FILE"
    print_success "Deployment outputs saved to: $OUTPUT_FILE"
    
else
    print_error "Infrastructure deployment failed"
    exit 1
fi

# Deploy function code if requested
if [[ "$DEPLOY_FUNCTION_CODE" == "true" ]]; then
    print_status "Deploying function code..."
    
    # Check if func CLI is available
    if ! command -v func &> /dev/null; then
        print_warning "Azure Functions Core Tools not found. Skipping function code deployment."
        print_warning "Install Azure Functions Core Tools and run: func azure functionapp publish $FUNCTION_APP"
    else
        # Look for function project
        if [[ -f "../../../simple-image-resizing-functions-blob.md" ]]; then
            FUNCTION_PROJECT_DIR="../../function-app"
            if [[ ! -d "$FUNCTION_PROJECT_DIR" ]]; then
                print_warning "Function project directory not found at: $FUNCTION_PROJECT_DIR"
                print_warning "Please create the function project and run: func azure functionapp publish $FUNCTION_APP"
            else
                print_status "Deploying from: $FUNCTION_PROJECT_DIR"
                cd "$FUNCTION_PROJECT_DIR"
                
                if func azure functionapp publish "$FUNCTION_APP" --javascript; then
                    print_success "Function code deployed successfully"
                else
                    print_error "Function code deployment failed"
                fi
                
                cd - > /dev/null
            fi
        else
            print_warning "Function project not found. Please deploy manually:"
            print_warning "func azure functionapp publish $FUNCTION_APP"
        fi
    fi
fi

# Display post-deployment information
echo
print_success "=== Deployment Complete ==="
cat << EOF

Next Steps:
1. Deploy the function code (if not done already):
   func azure functionapp publish $FUNCTION_APP

2. Test the solution by uploading an image:
   az storage blob upload \\
     --account-name $STORAGE_ACCOUNT \\
     --container-name original-images \\
     --name test-image.jpg \\
     --file /path/to/your/image.jpg \\
     --auth-mode login

3. Check processed images:
   az storage blob list \\
     --account-name $STORAGE_ACCOUNT \\
     --container-name thumbnails \\
     --auth-mode login

4. Monitor function execution:
   az webapp log tail --name $FUNCTION_APP --resource-group $RESOURCE_GROUP

5. Access containers directly:
   Original Images: https://$STORAGE_ACCOUNT.blob.core.windows.net/original-images/
   Thumbnails: https://$STORAGE_ACCOUNT.blob.core.windows.net/thumbnails/
   Medium Images: https://$STORAGE_ACCOUNT.blob.core.windows.net/medium-images/

EOF

if [[ "$ENABLE_INSIGHTS" == "true" ]]; then
    print_status "Application Insights is enabled for monitoring and troubleshooting"
fi

print_success "Deployment script completed successfully!"