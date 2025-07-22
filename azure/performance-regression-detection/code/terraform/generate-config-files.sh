#!/bin/bash

# Script to generate configuration files from Terraform outputs
# Usage: ./generate-config-files.sh

set -e

echo "Generating configuration files from Terraform outputs..."

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo "Error: Terraform not initialized. Run 'terraform init' first."
    exit 1
fi

# Check if terraform state exists
if ! terraform state list > /dev/null 2>&1; then
    echo "Error: No Terraform state found. Run 'terraform apply' first."
    exit 1
fi

# Create configuration files from outputs
echo "Creating loadtest-config.yaml..."
terraform output -raw load_test_config_content > loadtest-config.yaml

echo "Creating loadtest.jmx..."
terraform output -raw jmeter_test_script_content > loadtest.jmx

echo "Creating azure-pipelines.yml..."
terraform output -raw azure_pipeline_content > azure-pipelines.yml

echo "Configuration files generated successfully:"
echo "  - loadtest-config.yaml"
echo "  - loadtest.jmx"
echo "  - azure-pipelines.yml"

# Show application URL
echo ""
echo "Application URL: $(terraform output -raw container_app_url)"
echo ""

# Show useful commands
echo "Next steps:"
echo "1. Test the application:"
echo "   curl -s $(terraform output -raw container_app_url)"
echo ""
echo "2. Run a load test:"
echo "   az load test create --load-test-resource $(terraform output -raw load_test_name) \\"
echo "                       --resource-group $(terraform output -raw resource_group_name) \\"
echo "                       --test-plan loadtest.jmx \\"
echo "                       --test-plan-config loadtest-config.yaml"
echo ""
echo "3. View monitoring dashboard:"
echo "   $(terraform output -json performance_testing_urls | jq -r '.azure_portal_app_insights')"
echo ""
echo "Configuration files generated successfully!"