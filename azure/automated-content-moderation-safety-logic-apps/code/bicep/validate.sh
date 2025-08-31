#!/bin/bash

# Azure Deployment Validation Script for Automated Content Moderation
# This script validates and tests the deployed content moderation solution

set -e  # Exit on error

# Default values
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
VERBOSE=false
FULL_TEST=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[VALIDATE]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 -g <resource-group> [OPTIONS]

This script validates the deployed Azure content moderation solution.

Required Parameters:
  -g, --resource-group    Name of the Azure resource group

Optional Parameters:
  -s, --subscription      Azure subscription ID (uses default if not specified)
  -t, --full-test         Run full end-to-end tests including content upload
  --verbose               Enable verbose output
  -h, --help              Show this help message

Validation Checks:
  ✓ Resource group exists
  ✓ All required resources are deployed
  ✓ Content Safety service is accessible
  ✓ Storage account and container exist
  ✓ Logic App is enabled and configured
  ✓ Blob storage connection is working
  ✓ (Optional) End-to-end workflow test

Examples:
  # Basic validation
  $0 -g rg-content-moderation-demo

  # Full validation with end-to-end test
  $0 -g rg-content-moderation-demo -t

  # Verbose validation output
  $0 -g rg-content-moderation-demo --verbose

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -t|--full-test)
            FULL_TEST=true
            shift
            ;;
        --verbose)
            VERBOSE=true
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

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    print_error "Resource group name is required"
    show_usage
    exit 1
fi

# Print validation information
print_header "Azure Content Moderation Solution Validation"
echo "=========================================================="
print_status "Resource Group: $RESOURCE_GROUP"
if [[ "$FULL_TEST" == true ]]; then
    print_status "Full end-to-end testing enabled"
fi
echo "=========================================================="

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first:"
    print_error "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
print_status "Checking Azure CLI authentication..."
if ! az account show &> /dev/null; then
    print_error "You are not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Set subscription if provided
if [[ -n "$SUBSCRIPTION_ID" ]]; then
    print_status "Setting subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Display current subscription
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
print_status "Using subscription: $CURRENT_SUBSCRIPTION"

# Validation counters
TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0

# Function to run validation test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    print_status "Testing: $test_name"
    
    if [[ "$VERBOSE" == true ]]; then
        echo "  Command: $test_command"
    fi
    
    if eval "$test_command" &> /dev/null; then
        print_success "✓ $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "✗ $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to run validation test with output
run_test_with_output() {
    local test_name="$1"
    local test_command="$2"
    local output_var="$3"
    
    print_status "Testing: $test_name"
    
    if [[ "$VERBOSE" == true ]]; then
        echo "  Command: $test_command"
    fi
    
    local result=$(eval "$test_command" 2>/dev/null)
    
    if [[ -n "$result" && "$result" != "null" ]]; then
        print_success "✓ $test_name"
        if [[ -n "$output_var" ]]; then
            eval "$output_var=\"$result\""
        fi
        if [[ "$VERBOSE" == true ]]; then
            echo "  Result: $result"
        fi
        ((TESTS_PASSED++))
        return 0
    else
        print_error "✗ $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 1: Resource Group Exists
print_header "1. Validating Resource Group"
run_test "Resource group exists" "az group show --name '$RESOURCE_GROUP'"

# Test 2: List All Resources
print_header "2. Listing All Resources"
RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, State:properties.provisioningState}" -o table 2>/dev/null)

if [[ -n "$RESOURCES" ]]; then
    print_success "✓ Resources found in resource group"
    echo "$RESOURCES"
    ((TESTS_PASSED++))
else
    print_error "✗ No resources found in resource group"
    ((TESTS_FAILED++))
fi

# Test 3: Content Safety Service
print_header "3. Validating Content Safety Service"
run_test_with_output "Content Safety account exists" \
    "az cognitiveservices account list --resource-group '$RESOURCE_GROUP' --query '[?kind==\`ContentSafety\`].name | [0]' -o tsv" \
    "CONTENT_SAFETY_NAME"

if [[ -n "$CONTENT_SAFETY_NAME" ]]; then
    run_test_with_output "Content Safety endpoint accessible" \
        "az cognitiveservices account show --name '$CONTENT_SAFETY_NAME' --resource-group '$RESOURCE_GROUP' --query 'properties.endpoint' -o tsv" \
        "CONTENT_SAFETY_ENDPOINT"
    
    run_test "Content Safety key available" \
        "az cognitiveservices account keys list --name '$CONTENT_SAFETY_NAME' --resource-group '$RESOURCE_GROUP' --query 'key1' -o tsv"
fi

# Test 4: Storage Account
print_header "4. Validating Storage Account"
run_test_with_output "Storage account exists" \
    "az storage account list --resource-group '$RESOURCE_GROUP' --query '[0].name' -o tsv" \
    "STORAGE_ACCOUNT_NAME"

if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
    run_test "Storage account is accessible" \
        "az storage account show --name '$STORAGE_ACCOUNT_NAME' --resource-group '$RESOURCE_GROUP'"
    
    # Check for container
    STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --query "[0].value" -o tsv 2>/dev/null)
    
    if [[ -n "$STORAGE_KEY" ]]; then
        run_test "Content uploads container exists" \
            "az storage container show --name 'content-uploads' --account-name '$STORAGE_ACCOUNT_NAME' --account-key '$STORAGE_KEY'"
    fi
fi

# Test 5: Logic App
print_header "5. Validating Logic App"
run_test_with_output "Logic App exists" \
    "az logic workflow list --resource-group '$RESOURCE_GROUP' --query '[0].name' -o tsv" \
    "LOGIC_APP_NAME"

if [[ -n "$LOGIC_APP_NAME" ]]; then
    run_test "Logic App is enabled" \
        "az logic workflow show --resource-group '$RESOURCE_GROUP' --name '$LOGIC_APP_NAME' --query 'state' -o tsv | grep -i enabled"
    
    # Check Logic App configuration
    LOGIC_APP_STATE=$(az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP_NAME" --query 'state' -o tsv 2>/dev/null)
    if [[ "$LOGIC_APP_STATE" == "Enabled" ]]; then
        print_success "✓ Logic App is enabled"
        ((TESTS_PASSED++))
    else
        print_warning "⚠ Logic App state: $LOGIC_APP_STATE"
        ((WARNINGS++))
    fi
fi

# Test 6: Blob Connection
print_header "6. Validating Blob Storage Connection"
run_test "Blob storage connection exists" \
    "az resource list --resource-group '$RESOURCE_GROUP' --resource-type 'Microsoft.Web/connections' --query '[?contains(name, \`blob\`)].name | [0]' -o tsv"

# Test 7: End-to-End Test (Optional)
if [[ "$FULL_TEST" == true && -n "$STORAGE_ACCOUNT_NAME" && -n "$STORAGE_KEY" ]]; then
    print_header "7. Running End-to-End Test"
    
    # Create a test file
    TEST_FILE="test-content-$(date +%s).txt"
    echo "This is a test message for content moderation validation." > "$TEST_FILE"
    
    print_status "Uploading test file: $TEST_FILE"
    if az storage blob upload \
        --file "$TEST_FILE" \
        --name "$TEST_FILE" \
        --container-name "content-uploads" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --no-progress &> /dev/null; then
        
        print_success "✓ Test file uploaded successfully"
        ((TESTS_PASSED++))
        
        # Wait for workflow to process
        print_status "Waiting 30 seconds for workflow processing..."
        sleep 30
        
        # Check Logic App runs
        RECENT_RUNS=$(az logic workflow list-runs \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOGIC_APP_NAME" \
            --top 3 \
            --query "value[].status" -o tsv 2>/dev/null)
        
        if echo "$RECENT_RUNS" | grep -q "Succeeded"; then
            print_success "✓ Logic App workflow executed successfully"
            ((TESTS_PASSED++))
        else
            print_warning "⚠ No successful workflow runs detected"
            ((WARNINGS++))
            
            if [[ "$VERBOSE" == true ]]; then
                print_status "Recent run statuses: $RECENT_RUNS"
            fi
        fi
        
        # Clean up test file
        az storage blob delete \
            --name "$TEST_FILE" \
            --container-name "content-uploads" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --account-key "$STORAGE_KEY" &> /dev/null
        
        rm -f "$TEST_FILE"
        
    else
        print_error "✗ Failed to upload test file"
        ((TESTS_FAILED++))
    fi
fi

# Test 8: API Connectivity Test (Optional)
if [[ -n "$CONTENT_SAFETY_ENDPOINT" && -n "$CONTENT_SAFETY_NAME" ]]; then
    print_header "8. Testing Content Safety API"
    
    CONTENT_SAFETY_KEY=$(az cognitiveservices account keys list \
        --name "$CONTENT_SAFETY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "key1" -o tsv 2>/dev/null)
    
    if [[ -n "$CONTENT_SAFETY_KEY" ]]; then
        print_status "Testing Content Safety API connectivity..."
        
        API_TEST=$(curl -s -X POST "${CONTENT_SAFETY_ENDPOINT}contentsafety/text:analyze?api-version=2024-09-01" \
            -H "Ocp-Apim-Subscription-Key: $CONTENT_SAFETY_KEY" \
            -H "Content-Type: application/json" \
            -d '{"text": "This is a test message for API validation.", "outputType": "FourSeverityLevels"}' \
            --write-out "%{http_code}" \
            --output /dev/null)
        
        if [[ "$API_TEST" == "200" ]]; then
            print_success "✓ Content Safety API is responding correctly"
            ((TESTS_PASSED++))
        else
            print_error "✗ Content Safety API test failed (HTTP $API_TEST)"
            ((TESTS_FAILED++))
        fi
    fi
fi

# Print validation summary
echo
print_header "Validation Summary"
echo "=========================================================="
print_success "Tests Passed: $TESTS_PASSED"
if [[ $TESTS_FAILED -gt 0 ]]; then
    print_error "Tests Failed: $TESTS_FAILED"
fi
if [[ $WARNINGS -gt 0 ]]; then
    print_warning "Warnings: $WARNINGS"
fi
echo "=========================================================="

# Provide recommendations
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo
    print_header "Recommendations"
    print_status "• Check the Azure portal for detailed error messages"
    print_status "• Verify all resources are fully provisioned"
    print_status "• Review Logic App run history for workflow issues"
    print_status "• Ensure all required permissions are configured"
    
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo
    print_header "Next Steps"
    print_status "• Review warnings above and address if necessary"
    print_status "• Test content upload manually to verify workflow"
    print_status "• Monitor Logic App runs for proper operation"
    print_status "• Adjust content safety thresholds as needed"
    
    exit 0
else
    echo
    print_success "All validations passed! Your content moderation solution is ready."
    print_header "Next Steps"
    print_status "• Upload content to test the complete workflow"
    print_status "• Monitor Logic App runs in the Azure portal"
    print_status "• Configure additional notifications as needed"
    print_status "• Review and adjust content safety thresholds"
    
    exit 0
fi