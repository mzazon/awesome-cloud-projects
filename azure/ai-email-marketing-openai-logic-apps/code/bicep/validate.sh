#!/bin/bash

# AI-Powered Email Marketing Infrastructure Validation Script
# This script validates Bicep templates and checks deployment readiness

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TEMPLATE_FILE="main.bicep"
PARAMETERS_FILE="parameters.json"
VERBOSE=false

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

Validate AI-Powered Email Marketing Bicep Templates

Options:
    -t, --template-file FILE      Template file to validate (default: main.bicep)
    -p, --parameters-file FILE    Parameters file to use (default: parameters.json)
    -v, --verbose                 Enable verbose output
    -h, --help                   Show this help message

Examples:
    $0                           # Validate with default files
    $0 -p parameters.prod.json   # Validate with production parameters
    $0 -v                        # Verbose validation output

EOF
}

# Function to check prerequisites
check_prerequisites() {
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

    # Display versions
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    local bicep_version=$(az bicep version --query 'bicepVersion' -o tsv 2>/dev/null || echo "Unknown")
    
    print_message $GREEN "✅ Azure CLI version: $az_version"
    print_message $GREEN "✅ Bicep CLI version: $bicep_version"
}

# Function to validate file existence
validate_files() {
    print_message $BLUE "📁 Checking file existence..."

    # Check template file
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_message $RED "❌ Template file '$TEMPLATE_FILE' not found."
        exit 1
    fi
    print_message $GREEN "✅ Template file found: $TEMPLATE_FILE"

    # Check parameters file
    if [ ! -f "$PARAMETERS_FILE" ]; then
        print_message $RED "❌ Parameters file '$PARAMETERS_FILE' not found."
        exit 1
    fi
    print_message $GREEN "✅ Parameters file found: $PARAMETERS_FILE"

    # Check modules directory
    if [ -d "modules" ]; then
        local module_count=$(find modules -name "*.bicep" | wc -l)
        print_message $GREEN "✅ Modules directory found with $module_count module(s)"
        
        # List modules
        if [ "$VERBOSE" = true ]; then
            find modules -name "*.bicep" | while read -r module; do
                print_message $BLUE "   📄 Module: $module"
            done
        fi
    fi

    # Check workflows directory
    if [ -d "workflows" ]; then
        local workflow_count=$(find workflows -name "*.json" | wc -l)
        print_message $GREEN "✅ Workflows directory found with $workflow_count workflow(s)"
    fi
}

# Function to validate Bicep syntax
validate_bicep_syntax() {
    print_message $BLUE "🔍 Validating Bicep syntax..."

    # Build the template
    local build_output
    if [ "$VERBOSE" = true ]; then
        build_output=$(az bicep build --file "$TEMPLATE_FILE" --stdout 2>&1)
        local build_result=$?
    else
        build_output=$(az bicep build --file "$TEMPLATE_FILE" --stdout 2>&1 >/dev/null)
        local build_result=$?
    fi

    if [ $build_result -eq 0 ]; then
        print_message $GREEN "✅ Bicep template syntax is valid"
        
        if [ "$VERBOSE" = true ]; then
            print_message $BLUE "📊 Template analysis:"
            # Count resources, parameters, outputs
            local template_json=$(az bicep build --file "$TEMPLATE_FILE" --stdout)
            local resource_count=$(echo "$template_json" | jq '.resources | length' 2>/dev/null || echo "Unknown")
            local param_count=$(echo "$template_json" | jq '.parameters | length' 2>/dev/null || echo "Unknown")
            local output_count=$(echo "$template_json" | jq '.outputs | length' 2>/dev/null || echo "Unknown")
            
            print_message $BLUE "   📦 Resources: $resource_count"
            print_message $BLUE "   ⚙️  Parameters: $param_count"
            print_message $BLUE "   📤 Outputs: $output_count"
        fi
    else
        print_message $RED "❌ Bicep template syntax validation failed:"
        echo "$build_output"
        exit 1
    fi
}

# Function to validate parameters JSON
validate_parameters() {
    print_message $BLUE "🔍 Validating parameters file..."

    # Check JSON syntax
    if jq empty "$PARAMETERS_FILE" 2>/dev/null; then
        print_message $GREEN "✅ Parameters file JSON syntax is valid"
    else
        print_message $RED "❌ Parameters file has invalid JSON syntax"
        exit 1
    fi

    # Check parameters structure
    local schema_version=$(jq -r '."$schema"' "$PARAMETERS_FILE" 2>/dev/null)
    local content_version=$(jq -r '.contentVersion' "$PARAMETERS_FILE" 2>/dev/null)
    
    if [ "$schema_version" != "null" ] && [ "$content_version" != "null" ]; then
        print_message $GREEN "✅ Parameters file has valid structure"
        
        if [ "$VERBOSE" = true ]; then
            print_message $BLUE "   📋 Schema: $schema_version"
            print_message $BLUE "   📦 Version: $content_version"
            
            # List parameters
            local param_names=$(jq -r '.parameters | keys[]' "$PARAMETERS_FILE" 2>/dev/null)
            print_message $BLUE "   ⚙️  Parameters:"
            echo "$param_names" | while read -r param; do
                local param_value=$(jq -r ".parameters.\"$param\".value" "$PARAMETERS_FILE" 2>/dev/null)
                if [ ${#param_value} -gt 50 ]; then
                    param_value="${param_value:0:47}..."
                fi
                print_message $BLUE "      $param: $param_value"
            done
        fi
    else
        print_message $RED "❌ Parameters file missing required schema or contentVersion"
        exit 1
    fi
}

# Function to validate Logic Apps workflows
validate_workflows() {
    if [ ! -d "workflows" ]; then
        print_message $YELLOW "⚠️  No workflows directory found"
        return 0
    fi

    print_message $BLUE "🔍 Validating Logic Apps workflows..."

    local workflow_files=$(find workflows -name "*.json" 2>/dev/null)
    
    if [ -z "$workflow_files" ]; then
        print_message $YELLOW "⚠️  No workflow files found in workflows directory"
        return 0
    fi

    echo "$workflow_files" | while read -r workflow_file; do
        if [ -f "$workflow_file" ]; then
            local workflow_name=$(basename "$workflow_file" .json)
            
            # Validate JSON syntax
            if jq empty "$workflow_file" 2>/dev/null; then
                print_message $GREEN "✅ Workflow '$workflow_name' has valid JSON syntax"
                
                if [ "$VERBOSE" = true ]; then
                    # Check workflow structure
                    local has_definition=$(jq -r '.definition' "$workflow_file" 2>/dev/null)
                    local trigger_count=$(jq -r '.definition.triggers | length' "$workflow_file" 2>/dev/null || echo "0")
                    local action_count=$(jq -r '.definition.actions | length' "$workflow_file" 2>/dev/null || echo "0")
                    
                    if [ "$has_definition" != "null" ]; then
                        print_message $BLUE "   📋 Definition: Valid"
                        print_message $BLUE "   🔔 Triggers: $trigger_count"
                        print_message $BLUE "   ⚡ Actions: $action_count"
                    fi
                fi
            else
                print_message $RED "❌ Workflow '$workflow_name' has invalid JSON syntax"
            fi
        fi
    done
}

# Function to check resource naming conventions
validate_naming_conventions() {
    print_message $BLUE "🏷️  Validating naming conventions..."

    # Extract resource names from parameters
    local project_name=$(jq -r '.parameters.projectName.value' "$PARAMETERS_FILE" 2>/dev/null)
    local unique_suffix=$(jq -r '.parameters.uniqueSuffix.value' "$PARAMETERS_FILE" 2>/dev/null)
    local environment=$(jq -r '.parameters.environment.value' "$PARAMETERS_FILE" 2>/dev/null)

    # Check naming patterns
    local naming_issues=0

    if [ ${#project_name} -lt 3 ] || [ ${#project_name} -gt 15 ]; then
        print_message $YELLOW "⚠️  Project name should be 3-15 characters"
        ((naming_issues++))
    fi

    if [[ ! "$project_name" =~ ^[a-z0-9]+$ ]]; then
        print_message $YELLOW "⚠️  Project name should contain only lowercase letters and numbers"
        ((naming_issues++))
    fi

    if [[ ! "$environment" =~ ^(dev|staging|prod)$ ]]; then
        print_message $YELLOW "⚠️  Environment should be dev, staging, or prod"
        ((naming_issues++))
    fi

    if [ "$naming_issues" -eq 0 ]; then
        print_message $GREEN "✅ Naming conventions look good"
    else
        print_message $YELLOW "⚠️  Found $naming_issues naming convention issue(s)"
    fi
}

# Function to check security configuration
validate_security() {
    print_message $BLUE "🔒 Checking security configuration..."

    local security_issues=0

    # Check for secure parameters
    local secure_params=$(jq -r '.parameters | to_entries[] | select(.value.type == "securestring") | .key' "$PARAMETERS_FILE" 2>/dev/null | wc -l)
    
    # Check template for security features
    local template_json=$(az bicep build --file "$TEMPLATE_FILE" --stdout 2>/dev/null)
    
    # Check for HTTPS enforcement
    local https_only=$(echo "$template_json" | jq -r '.resources[] | select(.type == "Microsoft.Web/sites") | .properties.httpsOnly' 2>/dev/null | grep -c "true" || echo "0")
    
    # Check for managed identity
    local managed_identity=$(echo "$template_json" | jq -r '.resources[] | select(.identity.type == "SystemAssigned") | .name' 2>/dev/null | wc -l)
    
    # Check for Key Vault references
    local keyvault_refs=$(echo "$template_json" | jq -r '.. | strings | select(contains("@Microsoft.KeyVault"))' 2>/dev/null | wc -l)

    print_message $BLUE "   🔐 Security features found:"
    print_message $BLUE "      Secure parameters: $secure_params"
    print_message $BLUE "      HTTPS-only resources: $https_only"
    print_message $BLUE "      Managed identities: $managed_identity"
    print_message $BLUE "      Key Vault references: $keyvault_refs"

    if [ "$https_only" -gt 0 ] && [ "$managed_identity" -gt 0 ] && [ "$keyvault_refs" -gt 0 ]; then
        print_message $GREEN "✅ Good security practices detected"
    else
        print_message $YELLOW "⚠️  Consider enhancing security configuration"
    fi
}

# Function to estimate deployment cost
estimate_costs() {
    if [ "$VERBOSE" = false ]; then
        return 0
    fi

    print_message $BLUE "💰 Estimating deployment costs..."

    cat << EOF

Estimated Monthly Costs (USD):
┌─────────────────────────────────┬──────────────────┐
│ Resource Type                   │ Estimated Cost   │
├─────────────────────────────────┼──────────────────┤
│ Azure OpenAI Service (S0)       │ \$10-50          │
│ Logic Apps Standard (WS1)       │ \$80-150         │
│ Communication Services          │ \$5-20           │
│ Storage Account (Standard_LRS)  │ \$1-5            │
│ Application Insights            │ \$2-10           │
│ Key Vault                       │ \$1              │
│ Log Analytics Workspace        │ \$2-20           │
├─────────────────────────────────┼──────────────────┤
│ Total Estimated Monthly Cost    │ \$101-256        │
└─────────────────────────────────┴──────────────────┘

Note: Actual costs depend on usage patterns and may vary.
      Azure OpenAI costs scale with token usage.
      Email costs scale with volume sent.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--template-file)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        -p|--parameters-file)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
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

# Main execution
print_message $GREEN "🔍 AI-Powered Email Marketing Infrastructure Validation"
print_message $GREEN "===================================================="

print_message $YELLOW "Configuration:"
print_message $YELLOW "  Template File: $TEMPLATE_FILE"
print_message $YELLOW "  Parameters File: $PARAMETERS_FILE"
print_message $YELLOW "  Verbose Mode: $VERBOSE"

echo ""

# Run validation steps
check_prerequisites
validate_files
validate_bicep_syntax
validate_parameters
validate_workflows
validate_naming_conventions
validate_security
estimate_costs

print_message $GREEN "🎉 Validation completed successfully!"
print_message $BLUE "✨ Your Bicep templates are ready for deployment!"

# Show next steps
cat << EOF

Next Steps:
1. Review any warnings above
2. Customize parameters in $PARAMETERS_FILE
3. Run deployment: ./deploy.sh -g <resource-group-name>
4. Monitor deployment progress in Azure portal

EOF