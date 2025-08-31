#!/bin/bash

# Azure Health Bot Validation Script
# This script validates the deployed Azure Health Bot infrastructure

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if required parameters are provided
check_parameters() {
    if [ -z "$RESOURCE_GROUP" ]; then
        print_error "RESOURCE_GROUP environment variable is required"
        echo "Usage: RESOURCE_GROUP=your-rg-name ./validate.sh"
        echo "   or: ./validate.sh your-rg-name"
        exit 1
    fi
}

# Function to validate Azure CLI and authentication
validate_prerequisites() {
    print_status "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_success "Prerequisites validated"
}

# Function to validate resource group exists
validate_resource_group() {
    print_status "Validating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_success "Resource group exists"
        
        # Get resource group location
        RG_LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location --output tsv)
        print_status "Resource group location: $RG_LOCATION"
    else
        print_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
}

# Function to validate Health Bot deployment
validate_health_bot() {
    print_status "Validating Azure Health Bot resources..."
    
    # Get all Health Bot instances in the resource group
    HEALTH_BOTS=$(az healthbot list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    
    if [ -z "$HEALTH_BOTS" ]; then
        print_error "No Health Bot instances found in resource group"
        return 1
    fi
    
    for HEALTHBOT_NAME in $HEALTH_BOTS; do
        print_status "Validating Health Bot: $HEALTHBOT_NAME"
        
        # Get Health Bot details
        HEALTHBOT_INFO=$(az healthbot show \
            --name "$HEALTHBOT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --output json)
        
        # Extract important information
        PROVISIONING_STATE=$(echo "$HEALTHBOT_INFO" | jq -r '.properties.provisioningState')
        SKU=$(echo "$HEALTHBOT_INFO" | jq -r '.sku.name')
        LOCATION=$(echo "$HEALTHBOT_INFO" | jq -r '.location')
        BOT_MANAGEMENT_URL=$(echo "$HEALTHBOT_INFO" | jq -r '.properties.botManagementPortalLink')
        
        # Validate provisioning state
        if [ "$PROVISIONING_STATE" = "Succeeded" ]; then
            print_success "Health Bot provisioning state: $PROVISIONING_STATE"
        else
            print_error "Health Bot provisioning state: $PROVISIONING_STATE"
            return 1
        fi
        
        # Display Health Bot information
        echo "  ├── Name: $HEALTHBOT_NAME"
        echo "  ├── SKU: $SKU"
        echo "  ├── Location: $LOCATION"
        echo "  ├── Management Portal: $BOT_MANAGEMENT_URL"
        echo "  └── Status: Ready"
        
        print_success "Health Bot validation completed"
    done
}

# Function to validate monitoring resources
validate_monitoring() {
    print_status "Validating monitoring resources..."
    
    # Check for Log Analytics Workspaces
    WORKSPACES=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv)
    
    if [ -n "$WORKSPACES" ]; then
        for WORKSPACE in $WORKSPACES; do
            print_success "Found Log Analytics Workspace: $WORKSPACE"
            
            # Get workspace details
            WORKSPACE_INFO=$(az monitor log-analytics workspace show \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$WORKSPACE" \
                --output json)
            
            PROVISIONING_STATE=$(echo "$WORKSPACE_INFO" | jq -r '.provisioningState')
            RETENTION_DAYS=$(echo "$WORKSPACE_INFO" | jq -r '.retentionInDays')
            
            echo "  ├── Provisioning State: $PROVISIONING_STATE"
            echo "  └── Retention Days: $RETENTION_DAYS"
        done
    else
        print_warning "No Log Analytics Workspaces found (audit logging may be disabled)"
    fi
    
    # Check for Application Insights
    APP_INSIGHTS=$(az monitor app-insights component show \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$APP_INSIGHTS" ]; then
        for INSIGHTS in $APP_INSIGHTS; do
            print_success "Found Application Insights: $INSIGHTS"
        done
    else
        print_warning "No Application Insights found (monitoring may be disabled)"
    fi
}

# Function to test Health Bot connectivity
test_connectivity() {
    print_status "Testing Health Bot connectivity..."
    
    # Get Health Bot management URL
    MANAGEMENT_URL=$(az healthbot list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].properties.botManagementPortalLink' \
        --output tsv 2>/dev/null)
    
    if [ -n "$MANAGEMENT_URL" ] && [ "$MANAGEMENT_URL" != "null" ]; then
        print_status "Testing management portal accessibility..."
        
        # Test if the URL is reachable (basic connectivity test)
        if curl -s --head "$MANAGEMENT_URL" > /dev/null 2>&1; then
            print_success "Management portal is accessible"
        else
            print_warning "Management portal connectivity test failed (may require authentication)"
        fi
        
        echo "Management Portal URL: $MANAGEMENT_URL"
    else
        print_error "Could not retrieve management portal URL"
    fi
}

# Function to validate tags and compliance
validate_compliance() {
    print_status "Validating compliance and tagging..."
    
    # Check Health Bot tags
    HEALTH_BOTS=$(az healthbot list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    
    for HEALTHBOT_NAME in $HEALTH_BOTS; do
        TAGS=$(az healthbot show \
            --name "$HEALTHBOT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query 'tags' \
            --output json)
        
        # Check for required compliance tags
        ENVIRONMENT=$(echo "$TAGS" | jq -r '.environment // "missing"')
        PURPOSE=$(echo "$TAGS" | jq -r '.purpose // "missing"')
        COMPLIANCE=$(echo "$TAGS" | jq -r '.compliance // "missing"')
        
        print_status "Checking compliance tags for $HEALTHBOT_NAME:"
        echo "  ├── Environment: $ENVIRONMENT"
        echo "  ├── Purpose: $PURPOSE"
        echo "  └── Compliance: $COMPLIANCE"
        
        if [ "$COMPLIANCE" = "HIPAA" ]; then
            print_success "HIPAA compliance tag found"
        else
            print_warning "HIPAA compliance tag missing or incorrect"
        fi
    done
}

# Function to generate validation report
generate_report() {
    print_status "Generating validation report..."
    
    REPORT_FILE="healthbot-validation-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "=== Azure Health Bot Validation Report ==="
        echo "Generated: $(date)"
        echo "Resource Group: $RESOURCE_GROUP"
        echo ""
        
        echo "=== Health Bot Instances ==="
        az healthbot list --resource-group "$RESOURCE_GROUP" --output table
        echo ""
        
        echo "=== Resource Summary ==="
        az resource list --resource-group "$RESOURCE_GROUP" --output table
        echo ""
        
        echo "=== Cost Estimate ==="
        echo "Note: Use Azure Cost Management for accurate costs"
        az consumption usage list --top 10 --output table 2>/dev/null || echo "Cost data unavailable"
        
    } > "$REPORT_FILE"
    
    print_success "Validation report saved to: $REPORT_FILE"
}

# Function to show post-validation next steps
show_next_steps() {
    print_success "=== VALIDATION COMPLETED ==="
    echo ""
    print_status "Next Steps:"
    echo "1. Access the Health Bot Management Portal"
    echo "2. Configure healthcare scenarios:"
    echo "   - Enable symptom checker"
    echo "   - Configure disease information lookup"
    echo "   - Set up medication guidance"
    echo "3. Enable communication channels:"
    echo "   - Web chat for website integration"
    echo "   - Microsoft Teams for internal use"
    echo "   - SMS for patient outreach"
    echo "4. Customize branding and messaging"
    echo "5. Test with sample healthcare queries"
    echo "6. Review audit logs (if enabled)"
    echo "7. Monitor performance with Application Insights"
    echo ""
    print_warning "Remember to review HIPAA compliance settings before production use!"
}

# Main execution
main() {
    echo ""
    print_success "=== Azure Health Bot Validation Script ==="
    echo ""
    
    # Get resource group from parameter or environment
    if [ $# -eq 1 ]; then
        RESOURCE_GROUP="$1"
    fi
    
    check_parameters
    validate_prerequisites
    validate_resource_group
    
    # Run validation steps
    print_status "Starting comprehensive validation..."
    
    validate_health_bot
    validate_monitoring
    test_connectivity
    validate_compliance
    
    # Optional: Generate detailed report
    read -p "Generate detailed validation report? (y/N): " GENERATE_REPORT
    if [[ "$GENERATE_REPORT" =~ ^[Yy]$ ]]; then
        generate_report
    fi
    
    show_next_steps
    
    print_success "Health Bot validation completed successfully!"
}

# Run main function with all arguments
main "$@"