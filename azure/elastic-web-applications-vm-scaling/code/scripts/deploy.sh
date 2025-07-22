#!/bin/bash

# Deploy Auto-Scaling Web Applications with Azure VMSS and Load Balancer
# Recipe: deploying-auto-scaling-web-applications-with-azure-virtual-machine-scale-sets-and-azure-load-balancer
# Version: 1.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/../deploy.log"
ERROR_LOG="${SCRIPT_DIR}/../error.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_RESOURCE_GROUP="rg-autoscale-web-app"
DEFAULT_LOCATION="East US"
DEFAULT_VM_SIZE="Standard_B2s"
DEFAULT_MIN_INSTANCES=2
DEFAULT_MAX_INSTANCES=10

# Functions
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" "$ERROR_LOG"
            ;;
        DEBUG)
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log ERROR "$1"
    echo -e "${RED}Deployment failed. Check logs at: $LOG_FILE and $ERROR_LOG${NC}"
    exit 1
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if subscription is set
    local subscription_id=$(az account show --query id --output tsv 2>/dev/null || echo "")
    if [[ -z "$subscription_id" ]]; then
        error_exit "No Azure subscription found. Please set a subscription with 'az account set --subscription <subscription-id>'"
    fi
    
    log INFO "Prerequisites check passed. Using subscription: $subscription_id"
}

validate_inputs() {
    log INFO "Validating input parameters..."
    
    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        log WARN "Location '$LOCATION' may not be valid. Proceeding anyway..."
    fi
    
    # Validate VM size
    local available_sizes=$(az vm list-sizes --location "$LOCATION" --query "[?name=='$VM_SIZE']" --output tsv 2>/dev/null || echo "")
    if [[ -z "$available_sizes" ]]; then
        log WARN "VM size '$VM_SIZE' may not be available in location '$LOCATION'. Proceeding anyway..."
    fi
    
    # Validate instance counts
    if [[ $MIN_INSTANCES -lt 1 ]] || [[ $MAX_INSTANCES -lt $MIN_INSTANCES ]]; then
        error_exit "Invalid instance counts. MIN_INSTANCES must be >= 1 and MAX_INSTANCES must be >= MIN_INSTANCES"
    fi
    
    log INFO "Input validation completed"
}

generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        echo $(openssl rand -hex 3)
    else
        echo $(date +%s | tail -c 6)
    fi
}

set_environment_variables() {
    log INFO "Setting up environment variables..."
    
    # Core configuration
    export RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}
    export LOCATION=${LOCATION:-$DEFAULT_LOCATION}
    export VM_SIZE=${VM_SIZE:-$DEFAULT_VM_SIZE}
    export MIN_INSTANCES=${MIN_INSTANCES:-$DEFAULT_MIN_INSTANCES}
    export MAX_INSTANCES=${MAX_INSTANCES:-$DEFAULT_MAX_INSTANCES}
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(generate_unique_suffix)
    export VMSS_NAME="vmss-webapp-${RANDOM_SUFFIX}"
    export LB_NAME="lb-webapp-${RANDOM_SUFFIX}"
    export VNET_NAME="vnet-webapp-${RANDOM_SUFFIX}"
    export SUBNET_NAME="subnet-webapp"
    export NSG_NAME="nsg-webapp-${RANDOM_SUFFIX}"
    export PUBLIC_IP_NAME="pip-webapp-${RANDOM_SUFFIX}"
    export AUTOSCALE_NAME="autoscale-webapp-${RANDOM_SUFFIX}"
    export INSIGHTS_NAME="webapp-insights-${RANDOM_SUFFIX}"
    
    # Save variables to file for cleanup script
    cat > "${SCRIPT_DIR}/../.env" << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
VM_SIZE=$VM_SIZE
MIN_INSTANCES=$MIN_INSTANCES
MAX_INSTANCES=$MAX_INSTANCES
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
VMSS_NAME=$VMSS_NAME
LB_NAME=$LB_NAME
VNET_NAME=$VNET_NAME
SUBNET_NAME=$SUBNET_NAME
NSG_NAME=$NSG_NAME
PUBLIC_IP_NAME=$PUBLIC_IP_NAME
AUTOSCALE_NAME=$AUTOSCALE_NAME
INSIGHTS_NAME=$INSIGHTS_NAME
EOF
    
    log INFO "Environment variables configured with suffix: $RANDOM_SUFFIX"
}

create_resource_group() {
    log INFO "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Resource group '$RESOURCE_GROUP' already exists. Proceeding..."
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo deployment=auto-scale-webapp \
            || error_exit "Failed to create resource group"
        
        log INFO "✅ Resource group created successfully"
    fi
}

create_network_infrastructure() {
    log INFO "Creating network infrastructure..."
    
    # Create Virtual Network and subnet
    log DEBUG "Creating virtual network: $VNET_NAME"
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix 10.0.0.0/16 \
        --subnet-name "$SUBNET_NAME" \
        --subnet-prefix 10.0.1.0/24 \
        --location "$LOCATION" \
        || error_exit "Failed to create virtual network"
    
    # Create Network Security Group
    log DEBUG "Creating network security group: $NSG_NAME"
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_NAME" \
        --location "$LOCATION" \
        || error_exit "Failed to create network security group"
    
    # Allow HTTP traffic
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name Allow-HTTP \
        --protocol tcp \
        --priority 100 \
        --destination-port-range 80 \
        --access allow \
        || error_exit "Failed to create HTTP NSG rule"
    
    # Allow HTTPS traffic
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name Allow-HTTPS \
        --protocol tcp \
        --priority 110 \
        --destination-port-range 443 \
        --access allow \
        || error_exit "Failed to create HTTPS NSG rule"
    
    log INFO "✅ Network infrastructure created successfully"
}

create_public_ip() {
    log INFO "Creating public IP address: $PUBLIC_IP_NAME"
    
    az network public-ip create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PUBLIC_IP_NAME" \
        --allocation-method Static \
        --sku Standard \
        --location "$LOCATION" \
        || error_exit "Failed to create public IP"
    
    # Get the public IP address for reference
    PUBLIC_IP_ADDRESS=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PUBLIC_IP_NAME" \
        --query ipAddress \
        --output tsv)
    
    log INFO "✅ Public IP created: $PUBLIC_IP_ADDRESS"
    echo "PUBLIC_IP_ADDRESS=$PUBLIC_IP_ADDRESS" >> "${SCRIPT_DIR}/../.env"
}

create_load_balancer() {
    log INFO "Creating Azure Load Balancer: $LB_NAME"
    
    # Create Standard Load Balancer
    az network lb create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LB_NAME" \
        --sku Standard \
        --public-ip-address "$PUBLIC_IP_NAME" \
        --frontend-ip-name frontend-ip \
        --backend-pool-name backend-pool \
        --location "$LOCATION" \
        || error_exit "Failed to create load balancer"
    
    # Create health probe for HTTP traffic
    log DEBUG "Creating health probe for load balancer"
    az network lb probe create \
        --resource-group "$RESOURCE_GROUP" \
        --lb-name "$LB_NAME" \
        --name http-probe \
        --protocol http \
        --port 80 \
        --path / \
        --interval 15 \
        --threshold 3 \
        || error_exit "Failed to create health probe"
    
    # Create load balancing rule
    log DEBUG "Creating load balancing rule"
    az network lb rule create \
        --resource-group "$RESOURCE_GROUP" \
        --lb-name "$LB_NAME" \
        --name http-rule \
        --protocol tcp \
        --frontend-port 80 \
        --backend-port 80 \
        --frontend-ip-name frontend-ip \
        --backend-pool-name backend-pool \
        --probe-name http-probe \
        --load-distribution Default \
        || error_exit "Failed to create load balancing rule"
    
    log INFO "✅ Load Balancer created and configured successfully"
}

create_cloud_init_script() {
    log DEBUG "Creating cloud-init script for VM configuration"
    
    cat > "${SCRIPT_DIR}/../cloud-init.txt" << 'EOF'
#cloud-config
package_upgrade: true
packages:
  - nginx
  - htop
  - curl
runcmd:
  - systemctl start nginx
  - systemctl enable nginx
  - echo "<h1>Web Server $(hostname)</h1><p>Server Time: $(date)</p><p>Instance ID: $(curl -s -H Metadata:true http://169.254.169.254/metadata/instance/compute/vmId?api-version=2017-08-01)</p>" > /var/www/html/index.html
  - systemctl restart nginx
  - echo "Web server setup completed" > /var/log/cloud-init-output.log
EOF
    
    log DEBUG "Cloud-init script created successfully"
}

create_vmss() {
    log INFO "Creating Virtual Machine Scale Set: $VMSS_NAME"
    
    # Create cloud-init script
    create_cloud_init_script
    
    # Create Virtual Machine Scale Set
    az vmss create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --image UbuntuLTS \
        --instance-count "$MIN_INSTANCES" \
        --admin-username azureuser \
        --generate-ssh-keys \
        --upgrade-policy-mode automatic \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --nsg "$NSG_NAME" \
        --lb "$LB_NAME" \
        --backend-pool-name backend-pool \
        --custom-data "${SCRIPT_DIR}/../cloud-init.txt" \
        --vm-sku "$VM_SIZE" \
        --location "$LOCATION" \
        || error_exit "Failed to create Virtual Machine Scale Set"
    
    # Clean up cloud-init file
    rm -f "${SCRIPT_DIR}/../cloud-init.txt"
    
    log INFO "✅ Virtual Machine Scale Set created successfully"
}

configure_autoscaling() {
    log INFO "Configuring auto-scaling rules..."
    
    # Create auto-scale profile
    log DEBUG "Creating auto-scale profile: $AUTOSCALE_NAME"
    az monitor autoscale create \
        --resource-group "$RESOURCE_GROUP" \
        --resource "$VMSS_NAME" \
        --resource-type Microsoft.Compute/virtualMachineScaleSets \
        --name "$AUTOSCALE_NAME" \
        --min-count "$MIN_INSTANCES" \
        --max-count "$MAX_INSTANCES" \
        --count "$MIN_INSTANCES" \
        || error_exit "Failed to create auto-scale profile"
    
    # Create scale-out rule (CPU > 70%)
    log DEBUG "Creating scale-out rule"
    az monitor autoscale rule create \
        --resource-group "$RESOURCE_GROUP" \
        --autoscale-name "$AUTOSCALE_NAME" \
        --condition "Percentage CPU > 70 avg 5m" \
        --scale out 2 \
        --cooldown 5 \
        || error_exit "Failed to create scale-out rule"
    
    # Create scale-in rule (CPU < 30%)
    log DEBUG "Creating scale-in rule"
    az monitor autoscale rule create \
        --resource-group "$RESOURCE_GROUP" \
        --autoscale-name "$AUTOSCALE_NAME" \
        --condition "Percentage CPU < 30 avg 5m" \
        --scale in 1 \
        --cooldown 5 \
        || error_exit "Failed to create scale-in rule"
    
    log INFO "✅ Auto-scaling rules configured successfully"
}

setup_monitoring() {
    log INFO "Setting up Application Insights and monitoring..."
    
    # Create Application Insights resource
    log DEBUG "Creating Application Insights: $INSIGHTS_NAME"
    az monitor app-insights component create \
        --resource-group "$RESOURCE_GROUP" \
        --app "$INSIGHTS_NAME" \
        --location "$LOCATION" \
        --kind web \
        --application-type web \
        || error_exit "Failed to create Application Insights"
    
    # Get instrumentation key
    INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --resource-group "$RESOURCE_GROUP" \
        --app "$INSIGHTS_NAME" \
        --query instrumentationKey \
        --output tsv)
    
    log DEBUG "Application Insights configured with key: ${INSTRUMENTATION_KEY:0:8}..."
    echo "INSTRUMENTATION_KEY=$INSTRUMENTATION_KEY" >> "${SCRIPT_DIR}/../.env"
    
    # Create alert rule for high CPU usage
    log DEBUG "Creating CPU alert rule"
    az monitor metrics alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name high-cpu-alert-${RANDOM_SUFFIX} \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachineScaleSets/${VMSS_NAME}" \
        --condition "avg Percentage CPU > 80" \
        --description "Alert when CPU usage exceeds 80%" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --severity 2 \
        || log WARN "Failed to create CPU alert rule, continuing..."
    
    log INFO "✅ Monitoring and alerting configured successfully"
}

run_validation_tests() {
    log INFO "Running validation tests..."
    
    # Wait for VMSS instances to be ready
    log DEBUG "Waiting for VMSS instances to be ready..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local instance_count=$(az vmss list-instances \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --query "length([?provisioningState=='Succeeded'])" \
            --output tsv 2>/dev/null || echo "0")
        
        if [[ "$instance_count" -ge "$MIN_INSTANCES" ]]; then
            log INFO "VMSS instances are ready ($instance_count running)"
            break
        fi
        
        log DEBUG "Waiting for VMSS instances... ($instance_count/$MIN_INSTANCES ready)"
        sleep 30
        wait_time=$((wait_time + 30))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log WARN "VMSS instances may not be fully ready yet. Continuing with validation..."
    fi
    
    # Test load balancer connectivity
    log DEBUG "Testing load balancer connectivity..."
    local test_attempts=0
    local max_attempts=10
    
    while [[ $test_attempts -lt $max_attempts ]]; do
        if curl -f -s --connect-timeout 10 "http://${PUBLIC_IP_ADDRESS}" > /dev/null 2>&1; then
            log INFO "✅ Load balancer is responding successfully"
            break
        fi
        
        test_attempts=$((test_attempts + 1))
        log DEBUG "Load balancer test attempt $test_attempts/$max_attempts failed, retrying..."
        sleep 15
    done
    
    if [[ $test_attempts -ge $max_attempts ]]; then
        log WARN "Load balancer connectivity test failed. The deployment may need more time to fully initialize."
    fi
    
    log INFO "✅ Validation tests completed"
}

create_test_scripts() {
    log INFO "Creating test and monitoring scripts..."
    
    # Create load test script
    cat > "${SCRIPT_DIR}/../load-test.sh" << EOF
#!/bin/bash
# Load test script for auto-scaling validation

PUBLIC_IP="${PUBLIC_IP_ADDRESS}"
DURATION=\${1:-300}  # Default 5 minutes

if [[ -z "\$PUBLIC_IP" ]]; then
    echo "Error: PUBLIC_IP not set"
    exit 1
fi

echo "Starting load test against \$PUBLIC_IP for \$DURATION seconds..."
echo "This will generate load to trigger auto-scaling."

# Function to make requests
make_requests() {
    local end_time=\$((SECONDS + DURATION))
    local request_count=0
    
    while [[ SECONDS -lt end_time ]]; do
        curl -s "http://\$PUBLIC_IP" > /dev/null &
        request_count=\$((request_count + 1))
        
        if [[ \$((request_count % 100)) -eq 0 ]]; then
            echo "Sent \$request_count requests..."
        fi
        
        sleep 0.1
    done
    
    wait
    echo "Load test completed. Sent \$request_count requests."
}

make_requests
EOF

    # Create monitoring script
    cat > "${SCRIPT_DIR}/../monitor.sh" << EOF
#!/bin/bash
# Monitoring script for auto-scaling behavior

RESOURCE_GROUP="$RESOURCE_GROUP"
VMSS_NAME="$VMSS_NAME"

echo "Monitoring auto-scaling behavior..."
echo "Press Ctrl+C to stop monitoring"

while true; do
    INSTANCE_COUNT=\$(az vmss show \\
        --resource-group "\$RESOURCE_GROUP" \\
        --name "\$VMSS_NAME" \\
        --query "sku.capacity" \\
        --output tsv 2>/dev/null || echo "Unknown")
    
    CPU_USAGE=\$(az monitor metrics list \\
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachineScaleSets/$VMSS_NAME" \\
        --metric "Percentage CPU" \\
        --interval PT1M \\
        --query "value[0].timeseries[0].data[-1].average" \\
        --output tsv 2>/dev/null || echo "Unknown")
    
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - Instances: \$INSTANCE_COUNT, CPU: \${CPU_USAGE}%"
    sleep 30
done
EOF

    chmod +x "${SCRIPT_DIR}/../load-test.sh"
    chmod +x "${SCRIPT_DIR}/../monitor.sh"
    
    log INFO "✅ Test scripts created successfully"
}

print_deployment_summary() {
    log INFO "Deployment completed successfully!"
    
    echo ""
    echo "======================================"
    echo "  DEPLOYMENT SUMMARY"
    echo "======================================"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Public IP: $PUBLIC_IP_ADDRESS"
    echo "Web Application URL: http://$PUBLIC_IP_ADDRESS"
    echo ""
    echo "Resources Created:"
    echo "  - Virtual Machine Scale Set: $VMSS_NAME"
    echo "  - Load Balancer: $LB_NAME"
    echo "  - Virtual Network: $VNET_NAME"
    echo "  - Network Security Group: $NSG_NAME"
    echo "  - Application Insights: $INSIGHTS_NAME"
    echo ""
    echo "Auto-scaling Configuration:"
    echo "  - Min Instances: $MIN_INSTANCES"
    echo "  - Max Instances: $MAX_INSTANCES"
    echo "  - Scale-out: CPU > 70%"
    echo "  - Scale-in: CPU < 30%"
    echo ""
    echo "Available Scripts:"
    echo "  - Load test: ./load-test.sh [duration_seconds]"
    echo "  - Monitor: ./monitor.sh"
    echo "  - Cleanup: ./destroy.sh"
    echo ""
    echo "Next Steps:"
    echo "1. Test the web application: curl http://$PUBLIC_IP_ADDRESS"
    echo "2. Run load test to trigger auto-scaling: ./load-test.sh 300"
    echo "3. Monitor scaling behavior: ./monitor.sh"
    echo "4. Clean up resources when done: ./destroy.sh"
    echo "======================================"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy auto-scaling web application with Azure VMSS and Load Balancer"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group NAME     Resource group name (default: $DEFAULT_RESOURCE_GROUP)"
    echo "  -l, --location LOCATION       Azure location (default: $DEFAULT_LOCATION)"
    echo "  -s, --vm-size SIZE            VM size (default: $DEFAULT_VM_SIZE)"
    echo "  -m, --min-instances COUNT     Minimum instances (default: $DEFAULT_MIN_INSTANCES)"
    echo "  -M, --max-instances COUNT     Maximum instances (default: $DEFAULT_MAX_INSTANCES)"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 -g my-rg -l 'West US 2'          # Custom resource group and location"
    echo "  $0 -s Standard_B4ms -M 20            # Larger VMs with max 20 instances"
}

main() {
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    > "$LOG_FILE"  # Clear log file
    > "$ERROR_LOG"  # Clear error log file
    
    log INFO "Starting deployment of auto-scaling web application..."
    
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
            -s|--vm-size)
                VM_SIZE="$2"
                shift 2
                ;;
            -m|--min-instances)
                MIN_INSTANCES="$2"
                shift 2
                ;;
            -M|--max-instances)
                MAX_INSTANCES="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    validate_inputs
    create_resource_group
    create_network_infrastructure
    create_public_ip
    create_load_balancer
    create_vmss
    configure_autoscaling
    setup_monitoring
    run_validation_tests
    create_test_scripts
    print_deployment_summary
    
    log INFO "Deployment completed successfully in $(($SECONDS / 60)) minutes and $(($SECONDS % 60)) seconds"
}

# Handle script interruption
trap 'log ERROR "Deployment interrupted by user"; exit 130' INT TERM

# Run main function with all arguments
main "$@"