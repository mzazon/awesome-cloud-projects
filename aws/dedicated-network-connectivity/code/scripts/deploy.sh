#!/bin/bash

# Deploy script for AWS Direct Connect Hybrid Cloud Connectivity
# This script creates the infrastructure for hybrid cloud connectivity using AWS Direct Connect

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Cleanup function for signals
cleanup() {
    log "WARN" "Script interrupted. Cleaning up..."
    exit 1
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Save deployment state
save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "$STATE_FILE"
}

# Load deployment state
load_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d'/' -f2)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure'."
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON processing."
    fi
    
    # Verify AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not configured. Please set a default region."
    fi
    
    log "INFO" "AWS Region: $AWS_REGION"
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    
    log "SUCCESS" "Prerequisites check completed"
}

# Initialize environment variables
initialize_variables() {
    log "INFO" "Initializing environment variables..."
    
    # Generate unique project identifier
    if [[ -z "$(load_state 'PROJECT_ID')" ]]; then
        PROJECT_ID=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 8 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
        save_state "PROJECT_ID" "$PROJECT_ID"
    else
        PROJECT_ID=$(load_state 'PROJECT_ID')
    fi
    
    # Resource naming
    export DX_CONNECTION_NAME="corp-datacenter-${PROJECT_ID}"
    export DX_GATEWAY_NAME="corporate-dx-gateway-${PROJECT_ID}"
    export TRANSIT_GATEWAY_NAME="corporate-tgw-${PROJECT_ID}"
    
    # Network configuration
    export ON_PREM_ASN="65000"
    export ON_PREM_CIDR="10.0.0.0/8"
    export AWS_ASN="64512"
    
    # VLAN IDs for virtual interfaces
    export PRIVATE_VIF_VLAN="100"
    export TRANSIT_VIF_VLAN="200"
    
    log "INFO" "Project ID: $PROJECT_ID"
    log "INFO" "DX Gateway Name: $DX_GATEWAY_NAME"
    log "INFO" "Transit Gateway Name: $TRANSIT_GATEWAY_NAME"
    log "SUCCESS" "Environment variables initialized"
}

# Create VPC infrastructure
create_vpc_infrastructure() {
    log "INFO" "Creating VPC infrastructure..."
    
    # Check if VPCs already exist
    if [[ -n "$(load_state 'PROD_VPC_ID')" ]]; then
        log "INFO" "VPC infrastructure already exists, skipping creation"
        PROD_VPC_ID=$(load_state 'PROD_VPC_ID')
        DEV_VPC_ID=$(load_state 'DEV_VPC_ID')
        SHARED_VPC_ID=$(load_state 'SHARED_VPC_ID')
        return
    fi
    
    # Create production VPC
    log "INFO" "Creating production VPC..."
    PROD_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.1.0.0/16 \
        --tag-specifications \
            "ResourceType=vpc,Tags=[{Key=Name,Value=Production-VPC-${PROJECT_ID}},{Key=Environment,Value=Production},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'Vpc.VpcId' --output text)
    
    save_state "PROD_VPC_ID" "$PROD_VPC_ID"
    
    # Create development VPC
    log "INFO" "Creating development VPC..."
    DEV_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.2.0.0/16 \
        --tag-specifications \
            "ResourceType=vpc,Tags=[{Key=Name,Value=Development-VPC-${PROJECT_ID}},{Key=Environment,Value=Development},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'Vpc.VpcId' --output text)
    
    save_state "DEV_VPC_ID" "$DEV_VPC_ID"
    
    # Create shared services VPC
    log "INFO" "Creating shared services VPC..."
    SHARED_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.3.0.0/16 \
        --tag-specifications \
            "ResourceType=vpc,Tags=[{Key=Name,Value=Shared-Services-VPC-${PROJECT_ID}},{Key=Environment,Value=Shared},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'Vpc.VpcId' --output text)
    
    save_state "SHARED_VPC_ID" "$SHARED_VPC_ID"
    
    # Enable DNS hostnames and resolution for all VPCs
    for vpc_id in "$PROD_VPC_ID" "$DEV_VPC_ID" "$SHARED_VPC_ID"; do
        aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames
        aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-support
    done
    
    log "SUCCESS" "VPC infrastructure created"
    log "INFO" "Production VPC: $PROD_VPC_ID"
    log "INFO" "Development VPC: $DEV_VPC_ID"
    log "INFO" "Shared Services VPC: $SHARED_VPC_ID"
}

# Create Transit Gateway
create_transit_gateway() {
    log "INFO" "Creating Transit Gateway..."
    
    # Check if Transit Gateway already exists
    if [[ -n "$(load_state 'TRANSIT_GATEWAY_ID')" ]]; then
        log "INFO" "Transit Gateway already exists, skipping creation"
        TRANSIT_GATEWAY_ID=$(load_state 'TRANSIT_GATEWAY_ID')
        return
    fi
    
    # Create Transit Gateway
    TRANSIT_GATEWAY_ID=$(aws ec2 create-transit-gateway \
        --description "Corporate hybrid connectivity gateway" \
        --options \
            "AmazonSideAsn=${AWS_ASN},AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable" \
        --tag-specifications \
            "ResourceType=transit-gateway,Tags=[{Key=Name,Value=${TRANSIT_GATEWAY_NAME}},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'TransitGateway.TransitGatewayId' --output text)
    
    save_state "TRANSIT_GATEWAY_ID" "$TRANSIT_GATEWAY_ID"
    
    # Wait for Transit Gateway to become available
    log "INFO" "Waiting for Transit Gateway to become available..."
    aws ec2 wait transit-gateway-available --transit-gateway-ids "$TRANSIT_GATEWAY_ID"
    
    log "SUCCESS" "Transit Gateway created: $TRANSIT_GATEWAY_ID"
}

# Create subnets and attach VPCs to Transit Gateway
attach_vpcs_to_transit_gateway() {
    log "INFO" "Creating subnets and attaching VPCs to Transit Gateway..."
    
    # Check if attachments already exist
    if [[ -n "$(load_state 'PROD_ATTACHMENT')" ]]; then
        log "INFO" "VPC attachments already exist, skipping creation"
        return
    fi
    
    # Create private subnets for TGW attachments
    log "INFO" "Creating Transit Gateway attachment subnets..."
    
    PROD_TGW_SUBNET=$(aws ec2 create-subnet \
        --vpc-id "$PROD_VPC_ID" \
        --cidr-block 10.1.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=Prod-TGW-Subnet-${PROJECT_ID}},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    DEV_TGW_SUBNET=$(aws ec2 create-subnet \
        --vpc-id "$DEV_VPC_ID" \
        --cidr-block 10.2.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=Dev-TGW-Subnet-${PROJECT_ID}},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    SHARED_TGW_SUBNET=$(aws ec2 create-subnet \
        --vpc-id "$SHARED_VPC_ID" \
        --cidr-block 10.3.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=Shared-TGW-Subnet-${PROJECT_ID}},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    save_state "PROD_TGW_SUBNET" "$PROD_TGW_SUBNET"
    save_state "DEV_TGW_SUBNET" "$DEV_TGW_SUBNET"
    save_state "SHARED_TGW_SUBNET" "$SHARED_TGW_SUBNET"
    
    # Attach VPCs to Transit Gateway
    log "INFO" "Attaching VPCs to Transit Gateway..."
    
    PROD_ATTACHMENT=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id "$TRANSIT_GATEWAY_ID" \
        --vpc-id "$PROD_VPC_ID" \
        --subnet-ids "$PROD_TGW_SUBNET" \
        --tag-specifications \
            "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=Prod-TGW-Attachment},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    
    DEV_ATTACHMENT=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id "$TRANSIT_GATEWAY_ID" \
        --vpc-id "$DEV_VPC_ID" \
        --subnet-ids "$DEV_TGW_SUBNET" \
        --tag-specifications \
            "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=Dev-TGW-Attachment},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    
    SHARED_ATTACHMENT=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id "$TRANSIT_GATEWAY_ID" \
        --vpc-id "$SHARED_VPC_ID" \
        --subnet-ids "$SHARED_TGW_SUBNET" \
        --tag-specifications \
            "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=Shared-TGW-Attachment},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    
    save_state "PROD_ATTACHMENT" "$PROD_ATTACHMENT"
    save_state "DEV_ATTACHMENT" "$DEV_ATTACHMENT"
    save_state "SHARED_ATTACHMENT" "$SHARED_ATTACHMENT"
    
    log "SUCCESS" "VPC attachments created"
}

# Create Direct Connect Gateway
create_direct_connect_gateway() {
    log "INFO" "Creating Direct Connect Gateway..."
    
    # Check if DX Gateway already exists
    if [[ -n "$(load_state 'DX_GATEWAY_ID')" ]]; then
        log "INFO" "Direct Connect Gateway already exists, skipping creation"
        DX_GATEWAY_ID=$(load_state 'DX_GATEWAY_ID')
        return
    fi
    
    # Create Direct Connect Gateway
    DX_GATEWAY_ID=$(aws directconnect create-direct-connect-gateway \
        --name "$DX_GATEWAY_NAME" \
        --amazon-side-asn "$AWS_ASN" \
        --query 'directConnectGateway.directConnectGatewayId' --output text)
    
    save_state "DX_GATEWAY_ID" "$DX_GATEWAY_ID"
    
    # Wait for DX Gateway to become available
    log "INFO" "Waiting for Direct Connect Gateway to become available..."
    sleep 30
    
    # Associate Direct Connect Gateway with Transit Gateway
    log "INFO" "Associating Direct Connect Gateway with Transit Gateway..."
    DX_TGW_ATTACHMENT=$(aws ec2 create-transit-gateway-direct-connect-gateway-attachment \
        --transit-gateway-id "$TRANSIT_GATEWAY_ID" \
        --direct-connect-gateway-id "$DX_GATEWAY_ID" \
        --tag-specifications \
            "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=DX-TGW-Attachment-${PROJECT_ID}},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'TransitGatewayDirectConnectGatewayAttachment.TransitGatewayAttachmentId' --output text)
    
    save_state "DX_TGW_ATTACHMENT" "$DX_TGW_ATTACHMENT"
    
    log "SUCCESS" "Direct Connect Gateway created: $DX_GATEWAY_ID"
    log "SUCCESS" "DX Gateway associated with Transit Gateway"
}

# Configure routing
configure_routing() {
    log "INFO" "Configuring routing..."
    
    # Get default Transit Gateway route table
    TGW_ROUTE_TABLE=$(aws ec2 describe-transit-gateways \
        --transit-gateway-ids "$TRANSIT_GATEWAY_ID" \
        --query 'TransitGateways[0].Options.DefaultRouteTableId' --output text)
    
    save_state "TGW_ROUTE_TABLE" "$TGW_ROUTE_TABLE"
    
    # Update VPC route tables to route traffic through Transit Gateway
    log "INFO" "Updating VPC route tables..."
    
    for VPC_ID in "$PROD_VPC_ID" "$DEV_VPC_ID" "$SHARED_VPC_ID"; do
        ROUTE_TABLE=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=true" \
            --query 'RouteTables[0].RouteTableId' --output text)
        
        # Add route for on-premises networks
        aws ec2 create-route \
            --route-table-id "$ROUTE_TABLE" \
            --destination-cidr-block "$ON_PREM_CIDR" \
            --transit-gateway-id "$TRANSIT_GATEWAY_ID" 2>/dev/null || true
    done
    
    log "SUCCESS" "Routing configured"
}

# Set up DNS resolution
setup_dns_resolution() {
    log "INFO" "Setting up DNS resolution..."
    
    # Check if DNS endpoints already exist
    if [[ -n "$(load_state 'INBOUND_ENDPOINT')" ]]; then
        log "INFO" "DNS resolver endpoints already exist, skipping creation"
        return
    fi
    
    # Create security group for resolver endpoints
    log "INFO" "Creating security group for DNS resolver endpoints..."
    
    RESOLVER_SG=$(aws ec2 create-security-group \
        --group-name "resolver-endpoints-sg-${PROJECT_ID}" \
        --description "Security group for Route 53 Resolver endpoints" \
        --vpc-id "$SHARED_VPC_ID" \
        --tag-specifications \
            "ResourceType=security-group,Tags=[{Key=Name,Value=Resolver-SG-${PROJECT_ID}},{Key=Project,Value=${PROJECT_ID}}]" \
        --query 'GroupId' --output text)
    
    save_state "RESOLVER_SG" "$RESOLVER_SG"
    
    # Allow DNS traffic from on-premises
    aws ec2 authorize-security-group-ingress \
        --group-id "$RESOLVER_SG" \
        --protocol udp \
        --port 53 \
        --cidr "$ON_PREM_CIDR"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$RESOLVER_SG" \
        --protocol tcp \
        --port 53 \
        --cidr "$ON_PREM_CIDR"
    
    # Create inbound resolver endpoint
    log "INFO" "Creating inbound DNS resolver endpoint..."
    
    INBOUND_ENDPOINT=$(aws route53resolver create-resolver-endpoint \
        --creator-request-id "inbound-${PROJECT_ID}" \
        --security-group-ids "$RESOLVER_SG" \
        --direction INBOUND \
        --ip-addresses SubnetId="$SHARED_TGW_SUBNET",Ip=10.3.1.100 \
        --name "Inbound-Resolver-${PROJECT_ID}" \
        --query 'ResolverEndpoint.Id' --output text)
    
    save_state "INBOUND_ENDPOINT" "$INBOUND_ENDPOINT"
    
    # Create outbound resolver endpoint
    log "INFO" "Creating outbound DNS resolver endpoint..."
    
    OUTBOUND_ENDPOINT=$(aws route53resolver create-resolver-endpoint \
        --creator-request-id "outbound-${PROJECT_ID}" \
        --security-group-ids "$RESOLVER_SG" \
        --direction OUTBOUND \
        --ip-addresses SubnetId="$SHARED_TGW_SUBNET",Ip=10.3.1.101 \
        --name "Outbound-Resolver-${PROJECT_ID}" \
        --query 'ResolverEndpoint.Id' --output text)
    
    save_state "OUTBOUND_ENDPOINT" "$OUTBOUND_ENDPOINT"
    
    log "SUCCESS" "DNS resolver endpoints created"
    log "INFO" "Inbound Endpoint: $INBOUND_ENDPOINT (10.3.1.100)"
    log "INFO" "Outbound Endpoint: $OUTBOUND_ENDPOINT (10.3.1.101)"
}

# Configure monitoring
configure_monitoring() {
    log "INFO" "Configuring monitoring and alerting..."
    
    # Create CloudWatch dashboard
    log "INFO" "Creating CloudWatch dashboard..."
    
    cat > "${SCRIPT_DIR}/dx-dashboard.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/DX", "ConnectionState", "ConnectionId", "dx-connection-placeholder"],
                    [".", "ConnectionBpsEgress", ".", "."],
                    [".", "ConnectionBpsIngress", ".", "."],
                    [".", "ConnectionPacketsInEgress", ".", "."],
                    [".", "ConnectionPacketsInIngress", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Direct Connect Connection Metrics",
                "view": "timeSeries"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/TransitGateway", "BytesIn", "TransitGateway", "${TRANSIT_GATEWAY_ID}"],
                    [".", "BytesOut", ".", "."],
                    [".", "PacketsIn", ".", "."],
                    [".", "PacketsOut", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Transit Gateway Traffic",
                "view": "timeSeries"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "DirectConnect-${PROJECT_ID}" \
        --dashboard-body file://"${SCRIPT_DIR}/dx-dashboard.json"
    
    log "SUCCESS" "CloudWatch dashboard created"
    
    # Create SNS topic for alerts
    log "INFO" "Creating SNS topic for alerts..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "dx-alerts-${PROJECT_ID}" \
        --query 'TopicArn' --output text)
    
    save_state "SNS_TOPIC_ARN" "$SNS_TOPIC_ARN"
    
    log "SUCCESS" "Monitoring configured"
}

# Create testing scripts
create_testing_scripts() {
    log "INFO" "Creating testing and validation scripts..."
    
    # Create connectivity testing script
    cat > "${SCRIPT_DIR}/test-hybrid-connectivity.sh" << 'EOF'
#!/bin/bash

# Test hybrid connectivity
echo "Testing Hybrid Connectivity..."

# Test 1: BGP session status
echo "1. Checking BGP session status..."
aws directconnect describe-virtual-interfaces \
    --query 'virtualInterfaces[*].{Name:virtualInterfaceName,State:virtualInterfaceState,BGP:bgpStatus}' \
    --output table

# Test 2: Route propagation
echo "2. Checking Transit Gateway route tables..."
aws ec2 describe-transit-gateway-route-tables \
    --query 'TransitGatewayRouteTables[*].{TableId:TransitGatewayRouteTableId,State:State}' \
    --output table

# Test 3: DNS resolution
echo "3. Testing DNS resolution..."
aws route53resolver list-resolver-endpoints \
    --query 'ResolverEndpoints[*].{Id:Id,Direction:Direction,Status:Status}' \
    --output table

echo "Connectivity tests completed."
EOF
    
    chmod +x "${SCRIPT_DIR}/test-hybrid-connectivity.sh"
    
    # Create BGP configuration template
    cat > "${SCRIPT_DIR}/bgp-config-template.txt" << EOF
# BGP Configuration Template for On-Premises Router

router bgp ${ON_PREM_ASN}
 bgp router-id 192.168.100.1
 neighbor 192.168.100.2 remote-as ${AWS_ASN}
 neighbor 192.168.100.2 password <BGP-AUTH-KEY>
 neighbor 192.168.100.2 timers 10 30
 neighbor 192.168.100.2 soft-reconfiguration inbound
 
 address-family ipv4
  network ${ON_PREM_CIDR}
  neighbor 192.168.100.2 activate
  neighbor 192.168.100.2 prefix-list ALLOWED-PREFIXES out
  neighbor 192.168.100.2 prefix-list AWS-PREFIXES in
 exit-address-family

# Prefix lists
ip prefix-list ALLOWED-PREFIXES seq 10 permit ${ON_PREM_CIDR}
ip prefix-list AWS-PREFIXES seq 10 permit 10.1.0.0/16
ip prefix-list AWS-PREFIXES seq 20 permit 10.2.0.0/16
ip prefix-list AWS-PREFIXES seq 30 permit 10.3.0.0/16
EOF
    
    log "SUCCESS" "Testing scripts created"
}

# Generate configuration summary
generate_summary() {
    log "INFO" "Generating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment-summary.txt" << EOF
AWS Direct Connect Hybrid Cloud Connectivity Deployment Summary
================================================================

Project ID: ${PROJECT_ID}
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

VPC Infrastructure:
- Production VPC: ${PROD_VPC_ID} (10.1.0.0/16)
- Development VPC: ${DEV_VPC_ID} (10.2.0.0/16)
- Shared Services VPC: ${SHARED_VPC_ID} (10.3.0.0/16)

Transit Gateway:
- Transit Gateway ID: ${TRANSIT_GATEWAY_ID}
- ASN: ${AWS_ASN}

Direct Connect Gateway:
- DX Gateway ID: ${DX_GATEWAY_ID}
- Name: ${DX_GATEWAY_NAME}

DNS Resolution:
- Inbound Resolver: ${INBOUND_ENDPOINT} (10.3.1.100)
- Outbound Resolver: ${OUTBOUND_ENDPOINT} (10.3.1.101)

Network Configuration:
- On-premises ASN: ${ON_PREM_ASN}
- On-premises CIDR: ${ON_PREM_CIDR}
- AWS ASN: ${AWS_ASN}

Next Steps:
1. Configure physical Direct Connect connection
2. Create virtual interfaces (VIFs)
3. Configure BGP on on-premises router using bgp-config-template.txt
4. Test connectivity using test-hybrid-connectivity.sh

Monitoring:
- CloudWatch Dashboard: DirectConnect-${PROJECT_ID}
- SNS Topic: dx-alerts-${PROJECT_ID}

Files Created:
- ${SCRIPT_DIR}/test-hybrid-connectivity.sh
- ${SCRIPT_DIR}/bgp-config-template.txt
- ${SCRIPT_DIR}/dx-dashboard.json
- ${SCRIPT_DIR}/deployment-summary.txt
- ${SCRIPT_DIR}/.deployment_state
EOF
    
    log "SUCCESS" "Deployment summary generated"
}

# Main deployment function
main() {
    log "INFO" "Starting AWS Direct Connect Hybrid Cloud Connectivity deployment..."
    
    # Initialize log file
    > "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    initialize_variables
    create_vpc_infrastructure
    create_transit_gateway
    attach_vpcs_to_transit_gateway
    create_direct_connect_gateway
    configure_routing
    setup_dns_resolution
    configure_monitoring
    create_testing_scripts
    generate_summary
    
    log "SUCCESS" "Deployment completed successfully!"
    log "INFO" "Check deployment-summary.txt for next steps"
    log "INFO" "Use destroy.sh to clean up resources when done"
    
    echo
    echo "=================================================="
    echo "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "=================================================="
    echo "Project ID: $PROJECT_ID"
    echo "Review deployment-summary.txt for detailed information"
    echo "Use './destroy.sh' to clean up resources"
    echo "=================================================="
}

# Run main function
main "$@"