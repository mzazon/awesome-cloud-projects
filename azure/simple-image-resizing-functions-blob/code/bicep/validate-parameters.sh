#!/bin/bash

# ===========================================
# Parameter Validation Script for Image Resizing Solution
# ===========================================
# This script validates parameter files and provides recommendations

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PARAMETER_FILE="parameters.json"
TEMPLATE_FILE="main.bicep"
VERBOSE="false"

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
Parameter Validation Script for Azure Image Resizing Solution

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --parameters        Parameter file to validate (default: parameters.json)
    -t, --template          Template file to validate against (default: main.bicep)
    -v, --verbose           Show detailed validation information
    -h, --help              Show this help message

EXAMPLES:
    # Validate default parameters.json
    $0

    # Validate custom parameter file
    $0 -p my-parameters.json

    # Verbose validation with recommendations
    $0 -v

VALIDATIONS PERFORMED:
    - JSON syntax validation
    - Parameter schema validation
    - Resource naming conventions
    - Cost optimization recommendations
    - Security best practices
    - Performance considerations

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parameters)
            PARAMETER_FILE="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
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

print_status "=== Parameter Validation for Image Resizing Solution ==="
print_status "Parameter file: $PARAMETER_FILE"
print_status "Template file: $TEMPLATE_FILE"

# Check if files exist
if [[ ! -f "$PARAMETER_FILE" ]]; then
    print_error "Parameter file not found: $PARAMETER_FILE"
    exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    print_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Validate JSON syntax
print_status "Validating JSON syntax..."
if ! jq empty "$PARAMETER_FILE" 2>/dev/null; then
    print_error "Invalid JSON syntax in parameter file"
    exit 1
fi
print_success "JSON syntax is valid"

# Extract parameters
PARAMS=$(jq -r '.parameters' "$PARAMETER_FILE")

# Validation functions
validate_environment() {
    local env=$(echo "$PARAMS" | jq -r '.environment.value // "dev"')
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Environment: $env"
    fi
    
    case $env in
        dev|test|staging|prod|production)
            print_success "Environment name follows best practices"
            ;;
        *)
            print_warning "Consider using standard environment names: dev, test, staging, prod"
            ;;
    esac
}

validate_location() {
    local location=$(echo "$PARAMS" | jq -r '.location.value // "East US"')
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Location: $location"
    fi
    
    # Check if location is valid (basic check)
    if [[ ${#location} -lt 4 ]]; then
        print_warning "Location seems too short, verify it's a valid Azure region"
    else
        print_success "Location format looks valid"
    fi
}

validate_unique_suffix() {
    local suffix=$(echo "$PARAMS" | jq -r '.uniqueSuffix.value // ""')
    if [[ -n "$suffix" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_status "Unique suffix: $suffix"
        fi
        
        if [[ ${#suffix} -lt 3 ]]; then
            print_warning "Unique suffix is very short, may cause naming conflicts"
        elif [[ ${#suffix} -gt 10 ]]; then
            print_warning "Unique suffix is long, may cause resource name length issues"
        else
            print_success "Unique suffix length is appropriate"
        fi
        
        # Check for special characters
        if [[ ! "$suffix" =~ ^[a-zA-Z0-9]+$ ]]; then
            print_error "Unique suffix should only contain alphanumeric characters"
        fi
    else
        print_status "No unique suffix provided, will be auto-generated"
    fi
}

validate_function_plan_sku() {
    local sku=$(echo "$PARAMS" | jq -r '.functionAppPlanSku.value // "Y1"')
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Function App plan SKU: $sku"
    fi
    
    case $sku in
        Y1)
            print_success "Consumption plan selected - cost-effective for variable workloads"
            print_status "Recommendation: Good for development and low-traffic scenarios"
            ;;
        EP1|EP2|EP3)
            print_success "Premium plan selected - provides consistent performance"
            print_status "Recommendation: Good for production workloads with predictable traffic"
            if [[ "$sku" == "EP3" ]]; then
                print_warning "EP3 is the highest tier - ensure this level of performance is needed"
            fi
            ;;
        *)
            print_error "Invalid function plan SKU: $sku. Must be Y1, EP1, EP2, or EP3"
            ;;
    esac
}

validate_storage_sku() {
    local sku=$(echo "$PARAMS" | jq -r '.storageAccountSku.value // "Standard_LRS"')
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Storage account SKU: $sku"
    fi
    
    case $sku in
        Standard_LRS)
            print_success "Standard LRS selected - most cost-effective option"
            print_status "Recommendation: Good for development and non-critical workloads"
            ;;
        Standard_ZRS)
            print_success "Standard ZRS selected - good balance of durability and cost"
            print_status "Recommendation: Good for production workloads within a region"
            ;;
        Standard_GRS)
            print_success "Standard GRS selected - highest durability"
            print_status "Recommendation: Good for critical data requiring geo-redundancy"
            print_warning "Higher cost than LRS/ZRS - ensure geo-redundancy is needed"
            ;;
        Premium_LRS)
            print_success "Premium LRS selected - highest performance"
            print_warning "Premium storage is significantly more expensive"
            print_status "Recommendation: Only use for high-performance scenarios"
            ;;
        *)
            print_error "Invalid storage SKU: $sku"
            ;;
    esac
}

validate_image_processing_config() {
    local config=$(echo "$PARAMS" | jq -r '.imageProcessingConfig.value // {}')
    
    if [[ "$config" == "{}" ]]; then
        print_status "Using default image processing configuration"
        return
    fi
    
    local thumb_width=$(echo "$config" | jq -r '.thumbnailWidth // 150')
    local thumb_height=$(echo "$config" | jq -r '.thumbnailHeight // 150')
    local medium_width=$(echo "$config" | jq -r '.mediumWidth // 800')
    local medium_height=$(echo "$config" | jq -r '.mediumHeight // 600')
    local jpeg_quality=$(echo "$config" | jq -r '.jpegQuality // 85')
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Image processing configuration:"
        print_status "  Thumbnail: ${thumb_width}x${thumb_height}"
        print_status "  Medium: ${medium_width}x${medium_height}"
        print_status "  JPEG Quality: ${jpeg_quality}"
    fi
    
    # Validate dimensions
    if [[ $thumb_width -lt 50 || $thumb_width -gt 500 ]]; then
        print_warning "Thumbnail width ($thumb_width) outside typical range (50-500px)"
    fi
    
    if [[ $medium_width -lt 400 || $medium_width -gt 2000 ]]; then
        print_warning "Medium width ($medium_width) outside typical range (400-2000px)"
    fi
    
    # Validate JPEG quality
    if [[ $jpeg_quality -lt 60 ]]; then
        print_warning "JPEG quality ($jpeg_quality) is quite low, may result in poor image quality"
    elif [[ $jpeg_quality -gt 95 ]]; then
        print_warning "JPEG quality ($jpeg_quality) is very high, may result in large file sizes"
    else
        print_success "Image processing configuration looks reasonable"
    fi
}

validate_application_insights() {
    local enabled=$(echo "$PARAMS" | jq -r '.enableApplicationInsights.value // true')
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Application Insights enabled: $enabled"
    fi
    
    if [[ "$enabled" == "true" ]]; then
        print_success "Application Insights enabled - good for monitoring and troubleshooting"
    else
        print_warning "Application Insights disabled - consider enabling for production workloads"
    fi
}

validate_resource_tags() {
    local tags=$(echo "$PARAMS" | jq -r '.resourceTags.value // {}')
    local tag_count=$(echo "$tags" | jq 'length')
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "Resource tags count: $tag_count"
        if [[ $tag_count -gt 0 ]]; then
            echo "$tags" | jq -r 'to_entries[] | "  \(.key): \(.value)"' | while read line; do
                print_status "$line"
            done
        fi
    fi
    
    if [[ $tag_count -eq 0 ]]; then
        print_warning "No resource tags defined - consider adding tags for cost management"
    elif [[ $tag_count -lt 3 ]]; then
        print_warning "Few resource tags defined - consider adding Environment, Owner, CostCenter"
    else
        print_success "Good number of resource tags for organization"
    fi
    
    # Check for recommended tags
    local has_environment=$(echo "$tags" | jq -r '.Environment // .environment // empty')
    local has_owner=$(echo "$tags" | jq -r '.Owner // .owner // empty')
    local has_cost_center=$(echo "$tags" | jq -r '.CostCenter // .costCenter // "CostCenter" // empty')
    
    if [[ -z "$has_environment" ]]; then
        print_warning "Consider adding Environment tag"
    fi
    if [[ -z "$has_owner" ]]; then
        print_warning "Consider adding Owner tag"
    fi
    if [[ -z "$has_cost_center" ]]; then
        print_warning "Consider adding CostCenter tag"
    fi
}

# Cost estimation
estimate_costs() {
    local func_sku=$(echo "$PARAMS" | jq -r '.functionAppPlanSku.value // "Y1"')
    local storage_sku=$(echo "$PARAMS" | jq -r '.storageAccountSku.value // "Standard_LRS"')
    local insights_enabled=$(echo "$PARAMS" | jq -r '.enableApplicationInsights.value // true')
    
    print_status "=== Cost Estimation (USD/month) ==="
    
    case $func_sku in
        Y1)
            echo "Function App (Consumption): ~$5-20 (depends on usage)"
            ;;
        EP1)
            echo "Function App (Premium EP1): ~$146"
            ;;
        EP2)
            echo "Function App (Premium EP2): ~$292"
            ;;
        EP3)
            echo "Function App (Premium EP3): ~$584"
            ;;
    esac
    
    case $storage_sku in
        Standard_LRS)
            echo "Storage Account (LRS): ~$2-5 (depends on usage)"
            ;;
        Standard_ZRS)
            echo "Storage Account (ZRS): ~$3-7 (depends on usage)"
            ;;
        Standard_GRS)
            echo "Storage Account (GRS): ~$4-10 (depends on usage)"
            ;;
        Premium_LRS)
            echo "Storage Account (Premium): ~$20-50 (depends on usage)"
            ;;
    esac
    
    if [[ "$insights_enabled" == "true" ]]; then
        echo "Application Insights: ~$2-10 (depends on usage)"
    fi
    
    echo "Event Grid: ~$0.60 per million events"
    echo
    print_status "Note: Costs are estimates and depend on actual usage patterns"
}

# Run all validations
print_status "Running parameter validations..."
echo

validate_environment
validate_location
validate_unique_suffix
validate_function_plan_sku
validate_storage_sku
validate_image_processing_config
validate_application_insights
validate_resource_tags

echo
if [[ "$VERBOSE" == "true" ]]; then
    estimate_costs
fi

# Template validation with Azure CLI (if available)
if command -v az &> /dev/null && az account show &> /dev/null 2>&1; then
    print_status "Running Azure template validation..."
    
    # Create a temporary resource group name for validation
    TEMP_RG="temp-validation-$(date +%s)"
    
    if az deployment sub validate \
        --location "East US" \
        --template-file "$TEMPLATE_FILE" \
        --parameters @"$PARAMETER_FILE" \
        --parameters resourceGroupName="$TEMP_RG" &> /dev/null; then
        print_success "Azure template validation passed"
    else
        print_warning "Azure template validation failed - check your parameters"
    fi
else
    print_status "Azure CLI not available or not logged in - skipping template validation"
fi

echo
print_success "=== Parameter Validation Complete ==="

# Recommendations
cat << EOF

RECOMMENDATIONS:
1. Review cost estimates before deployment
2. Use Consumption plan (Y1) for development environments
3. Enable Application Insights for production workloads
4. Add comprehensive resource tags for cost management
5. Test with a small resource group first
6. Consider backup strategy for production images

For deployment, run:
./deploy.sh -g your-resource-group-name

EOF

print_success "Validation script completed successfully!"