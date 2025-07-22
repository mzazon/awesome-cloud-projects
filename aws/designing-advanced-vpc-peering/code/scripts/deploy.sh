#!/bin/bash

# Multi-Region VPC Peering with Complex Routing Scenarios - Deployment Script
# This script deploys a sophisticated multi-region VPC peering architecture
# with hub-and-spoke topology across AWS regions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="global-peering"
DEPLOYMENT_ID=$(date +%s)
STATE_FILE="${SCRIPT_DIR}/../.deployment_state"

# Default regions (can be overridden with environment variables)
PRIMARY_REGION=${PRIMARY_REGION:-"us-east-1"}
SECONDARY_REGION=${SECONDARY_REGION:-"us-west-2"}
EU_REGION=${EU_REGION:-"eu-west-1"}
APAC_REGION=${APAC_REGION:-"ap-southeast-1"}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy multi-region VPC peering architecture with complex routing"
    echo ""
    echo "Options:"
    echo "  --dry-run           Show what would be deployed without making changes"
    echo "  --skip-dns          Skip Route 53 Resolver configuration"
    echo "  --force             Force deployment even if state file exists"
    echo "  --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PRIMARY_REGION      Primary region (default: us-east-1)"
    echo "  SECONDARY_REGION    Secondary region (default: us-west-2)"
    echo "  EU_REGION          EU region (default: eu-west-1)"
    echo "  APAC_REGION        APAC region (default: ap-southeast-1)"
    echo ""
    echo "Examples:"
    echo "  $0                  Deploy with default regions"
    echo "  $0 --dry-run        Preview deployment without changes"
    echo "  PRIMARY_REGION=us-west-1 $0  Use custom primary region"
}

# Parse command line arguments
DRY_RUN=false
SKIP_DNS=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-dns)
            SKIP_DNS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    if [[ $major_version -lt 2 ]]; then
        log_warning "AWS CLI v1 detected. AWS CLI v2 is recommended."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check region availability
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$EU_REGION" "$APAC_REGION")
    for region in "${regions[@]}"; do
        if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
            log_error "Region $region is not available or accessible."
            exit 1
        fi
    done
    
    # Check permissions by testing a simple operation
    if ! aws ec2 describe-vpcs --region "$PRIMARY_REGION" --max-items 1 &> /dev/null; then
        log_error "Insufficient permissions to access EC2 in $PRIMARY_REGION."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Check if deployment already exists
check_existing_deployment() {
    if [[ -f "$STATE_FILE" ]] && [[ "$FORCE" != "true" ]]; then
        log_error "Deployment state file exists: $STATE_FILE"
        log_error "Use --force to override or run destroy.sh first"
        exit 1
    fi
}

# Generate unique resource identifiers
generate_identifiers() {
    log_info "Generating unique resource identifiers..."
    
    # Generate random suffix for unique naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --region "$PRIMARY_REGION" \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    # Get AWS Account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Set project name with suffix
    PROJECT_NAME_FULL="${PROJECT_NAME}-${RANDOM_SUFFIX}"
    
    log_success "Generated identifiers: Project=${PROJECT_NAME_FULL}, Account=${AWS_ACCOUNT_ID}"
}

# Create VPCs in all regions
create_vpcs() {
    log_info "Creating VPCs across multiple regions..."
    
    # VPC configurations: name:region:cidr
    local vpc_configs=(
        "hub:$PRIMARY_REGION:10.0.0.0/16"
        "prod:$PRIMARY_REGION:10.1.0.0/16"
        "dev:$PRIMARY_REGION:10.2.0.0/16"
        "dr-hub:$SECONDARY_REGION:10.10.0.0/16"
        "dr-prod:$SECONDARY_REGION:10.11.0.0/16"
        "eu-hub:$EU_REGION:10.20.0.0/16"
        "eu-prod:$EU_REGION:10.21.0.0/16"
        "apac:$APAC_REGION:10.30.0.0/16"
    )
    
    for config in "${vpc_configs[@]}"; do
        IFS=':' read -r name region cidr <<< "$config"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create VPC: $name in $region with CIDR $cidr"
            continue
        fi
        
        log_info "Creating VPC: $name in $region..."
        
        local vpc_id=$(aws ec2 create-vpc \
            --region "$region" \
            --cidr-block "$cidr" \
            --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME_FULL}-${name}-vpc},{Key=Region,Value=${region}},{Key=Role,Value=${name}},{Key=Project,Value=${PROJECT_NAME_FULL}}]" \
            --query 'Vpc.VpcId' --output text)
        
        # Wait for VPC to be available
        aws ec2 wait vpc-available --region "$region" --vpc-ids "$vpc_id"
        
        # Store VPC ID in state
        echo "${name}_VPC_ID=$vpc_id" >> "$STATE_FILE"
        echo "${name}_REGION=$region" >> "$STATE_FILE"
        
        log_success "Created VPC: $name ($vpc_id) in $region"
    done
}

# Create subnets in each VPC
create_subnets() {
    log_info "Creating subnets in each VPC..."
    
    # Load VPC IDs from state
    source "$STATE_FILE"
    
    # Subnet configurations: vpc_name:subnet_cidr:az_suffix
    local subnet_configs=(
        "hub:10.0.1.0/24:a"
        "prod:10.1.1.0/24:a"
        "dev:10.2.1.0/24:a"
        "dr-hub:10.10.1.0/24:a"
        "dr-prod:10.11.1.0/24:a"
        "eu-hub:10.20.1.0/24:a"
        "eu-prod:10.21.1.0/24:a"
        "apac:10.30.1.0/24:a"
    )
    
    for config in "${subnet_configs[@]}"; do
        IFS=':' read -r vpc_name subnet_cidr az_suffix <<< "$config"
        
        # Get VPC ID and region from state
        local vpc_id_var="${vpc_name}_VPC_ID"
        local region_var="${vpc_name}_REGION"
        local vpc_id="${!vpc_id_var}"
        local region="${!region_var}"
        local az="${region}${az_suffix}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create subnet: $subnet_cidr in $vpc_name ($az)"
            continue
        fi
        
        log_info "Creating subnet in $vpc_name VPC..."
        
        local subnet_id=$(aws ec2 create-subnet \
            --region "$region" \
            --vpc-id "$vpc_id" \
            --cidr-block "$subnet_cidr" \
            --availability-zone "$az" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME_FULL}-${vpc_name}-subnet},{Key=Project,Value=${PROJECT_NAME_FULL}}]" \
            --query 'Subnet.SubnetId' --output text)
        
        # Store subnet ID in state
        echo "${vpc_name}_SUBNET_ID=$subnet_id" >> "$STATE_FILE"
        
        log_success "Created subnet: $subnet_id in $vpc_name VPC"
    done
}

# Create VPC peering connections
create_peering_connections() {
    log_info "Creating VPC peering connections..."
    
    # Load state
    source "$STATE_FILE"
    
    # Peering configurations: requester_vpc:accepter_vpc:requester_region:accepter_region:name
    local peering_configs=(
        # Inter-region hub-to-hub
        "hub:dr-hub:$PRIMARY_REGION:$SECONDARY_REGION:hub-to-dr-hub"
        "hub:eu-hub:$PRIMARY_REGION:$EU_REGION:hub-to-eu-hub"
        "dr-hub:eu-hub:$SECONDARY_REGION:$EU_REGION:dr-hub-to-eu-hub"
        # Intra-region hub-to-spoke
        "hub:prod:$PRIMARY_REGION:$PRIMARY_REGION:hub-to-prod"
        "hub:dev:$PRIMARY_REGION:$PRIMARY_REGION:hub-to-dev"
        "dr-hub:dr-prod:$SECONDARY_REGION:$SECONDARY_REGION:dr-hub-to-dr-prod"
        "eu-hub:eu-prod:$EU_REGION:$EU_REGION:eu-hub-to-eu-prod"
        # Cross-region spoke-to-hub
        "apac:eu-hub:$APAC_REGION:$EU_REGION:apac-to-eu-hub"
    )
    
    for config in "${peering_configs[@]}"; do
        IFS=':' read -r req_vpc acc_vpc req_region acc_region name <<< "$config"
        
        # Get VPC IDs
        local req_vpc_id_var="${req_vpc}_VPC_ID"
        local acc_vpc_id_var="${acc_vpc}_VPC_ID"
        local req_vpc_id="${!req_vpc_id_var}"
        local acc_vpc_id="${!acc_vpc_id_var}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create peering: $name ($req_vpc -> $acc_vpc)"
            continue
        fi
        
        log_info "Creating peering connection: $name..."
        
        # Create peering connection
        local peering_id=$(aws ec2 create-vpc-peering-connection \
            --region "$req_region" \
            --vpc-id "$req_vpc_id" \
            --peer-vpc-id "$acc_vpc_id" \
            --peer-region "$acc_region" \
            --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=${PROJECT_NAME_FULL}-${name}},{Key=Project,Value=${PROJECT_NAME_FULL}}]" \
            --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)
        
        # Accept peering connection
        aws ec2 accept-vpc-peering-connection \
            --region "$acc_region" \
            --vpc-peering-connection-id "$peering_id" > /dev/null
        
        # Wait for connection to be active
        aws ec2 wait vpc-peering-connection-exists \
            --region "$req_region" \
            --vpc-peering-connection-ids "$peering_id"
        
        # Store peering ID in state
        local peering_var="${name//-/_}_PEERING_ID"
        echo "${peering_var}=$peering_id" >> "$STATE_FILE"
        
        log_success "Created peering connection: $name ($peering_id)"
    done
}

# Configure route tables
configure_routing() {
    log_info "Configuring complex route tables..."
    
    # Load state
    source "$STATE_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure route tables for transit routing"
        return
    fi
    
    # Get route table IDs for each VPC
    local vpcs=("hub" "prod" "dev" "dr-hub" "dr-prod" "eu-hub" "eu-prod" "apac")
    
    for vpc in "${vpcs[@]}"; do
        local vpc_id_var="${vpc}_VPC_ID"
        local region_var="${vpc}_REGION"
        local vpc_id="${!vpc_id_var}"
        local region="${!region_var}"
        
        local rt_id=$(aws ec2 describe-route-tables \
            --region "$region" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'RouteTables[0].RouteTableId' --output text)
        
        echo "${vpc}_RT_ID=$rt_id" >> "$STATE_FILE"
    done
    
    # Reload state with route table IDs
    source "$STATE_FILE"
    
    # Configure hub route tables
    configure_hub_routes
    
    # Configure spoke route tables
    configure_spoke_routes
    
    log_success "Route table configuration completed"
}

# Configure hub route tables for transit routing
configure_hub_routes() {
    log_info "Configuring hub route tables..."
    
    # US-East-1 Hub routes (primary transit hub)
    log_info "Configuring US-East-1 Hub routes..."
    
    # Routes to other regions via inter-hub peering
    local hub_routes=(
        "$hub_RT_ID:$PRIMARY_REGION:10.10.0.0/16:$hub_to_dr_hub_PEERING_ID"  # To DR Hub
        "$hub_RT_ID:$PRIMARY_REGION:10.11.0.0/16:$hub_to_dr_hub_PEERING_ID"  # To DR Prod via DR Hub
        "$hub_RT_ID:$PRIMARY_REGION:10.20.0.0/16:$hub_to_eu_hub_PEERING_ID"  # To EU Hub
        "$hub_RT_ID:$PRIMARY_REGION:10.21.0.0/16:$hub_to_eu_hub_PEERING_ID"  # To EU Prod via EU Hub
        "$hub_RT_ID:$PRIMARY_REGION:10.30.0.0/16:$hub_to_eu_hub_PEERING_ID"  # To APAC via EU Hub
        "$hub_RT_ID:$PRIMARY_REGION:10.1.0.0/16:$hub_to_prod_PEERING_ID"     # To local Prod
        "$hub_RT_ID:$PRIMARY_REGION:10.2.0.0/16:$hub_to_dev_PEERING_ID"      # To local Dev
    )
    
    for route in "${hub_routes[@]}"; do
        IFS=':' read -r rt_id region cidr peering_id <<< "$route"
        
        aws ec2 create-route \
            --region "$region" \
            --route-table-id "$rt_id" \
            --destination-cidr-block "$cidr" \
            --vpc-peering-connection-id "$peering_id" > /dev/null || true
    done
    
    # Configure other hub routes similarly
    configure_dr_hub_routes
    configure_eu_hub_routes
}

# Configure DR hub routes
configure_dr_hub_routes() {
    log_info "Configuring DR Hub routes..."
    
    local dr_hub_routes=(
        "$dr_hub_RT_ID:$SECONDARY_REGION:10.0.0.0/16:$hub_to_dr_hub_PEERING_ID"    # To Primary Hub
        "$dr_hub_RT_ID:$SECONDARY_REGION:10.1.0.0/16:$hub_to_dr_hub_PEERING_ID"    # To Primary Prod via Hub
        "$dr_hub_RT_ID:$SECONDARY_REGION:10.2.0.0/16:$hub_to_dr_hub_PEERING_ID"    # To Primary Dev via Hub
        "$dr_hub_RT_ID:$SECONDARY_REGION:10.20.0.0/16:$dr_hub_to_eu_hub_PEERING_ID" # To EU Hub
        "$dr_hub_RT_ID:$SECONDARY_REGION:10.21.0.0/16:$dr_hub_to_eu_hub_PEERING_ID" # To EU Prod via EU Hub
        "$dr_hub_RT_ID:$SECONDARY_REGION:10.30.0.0/16:$dr_hub_to_eu_hub_PEERING_ID" # To APAC via EU Hub
        "$dr_hub_RT_ID:$SECONDARY_REGION:10.11.0.0/16:$dr_hub_to_dr_prod_PEERING_ID" # To local DR Prod
    )
    
    for route in "${dr_hub_routes[@]}"; do
        IFS=':' read -r rt_id region cidr peering_id <<< "$route"
        
        aws ec2 create-route \
            --region "$region" \
            --route-table-id "$rt_id" \
            --destination-cidr-block "$cidr" \
            --vpc-peering-connection-id "$peering_id" > /dev/null || true
    done
}

# Configure EU hub routes
configure_eu_hub_routes() {
    log_info "Configuring EU Hub routes..."
    
    local eu_hub_routes=(
        "$eu_hub_RT_ID:$EU_REGION:10.0.0.0/16:$hub_to_eu_hub_PEERING_ID"     # To Primary Hub
        "$eu_hub_RT_ID:$EU_REGION:10.1.0.0/16:$hub_to_eu_hub_PEERING_ID"     # To Primary Prod via Hub
        "$eu_hub_RT_ID:$EU_REGION:10.2.0.0/16:$hub_to_eu_hub_PEERING_ID"     # To Primary Dev via Hub
        "$eu_hub_RT_ID:$EU_REGION:10.10.0.0/16:$dr_hub_to_eu_hub_PEERING_ID" # To DR Hub
        "$eu_hub_RT_ID:$EU_REGION:10.11.0.0/16:$dr_hub_to_eu_hub_PEERING_ID" # To DR Prod via DR Hub
        "$eu_hub_RT_ID:$EU_REGION:10.30.0.0/16:$apac_to_eu_hub_PEERING_ID"   # To APAC (direct)
        "$eu_hub_RT_ID:$EU_REGION:10.21.0.0/16:$eu_hub_to_eu_prod_PEERING_ID" # To local EU Prod
    )
    
    for route in "${eu_hub_routes[@]}"; do
        IFS=':' read -r rt_id region cidr peering_id <<< "$route"
        
        aws ec2 create-route \
            --region "$region" \
            --route-table-id "$rt_id" \
            --destination-cidr-block "$cidr" \
            --vpc-peering-connection-id "$peering_id" > /dev/null || true
    done
}

# Configure spoke route tables
configure_spoke_routes() {
    log_info "Configuring spoke route tables..."
    
    # Spoke routing configurations: rt_id:region:hub_cidr:hub_peering_id:transit_cidr
    local spoke_routes=(
        "$prod_RT_ID:$PRIMARY_REGION:10.0.0.0/16:$hub_to_prod_PEERING_ID:10.10.0.0/8"
        "$dev_RT_ID:$PRIMARY_REGION:10.0.0.0/16:$hub_to_dev_PEERING_ID:10.10.0.0/8"
        "$dr_prod_RT_ID:$SECONDARY_REGION:10.10.0.0/16:$dr_hub_to_dr_prod_PEERING_ID:10.0.0.0/8"
        "$eu_prod_RT_ID:$EU_REGION:10.20.0.0/16:$eu_hub_to_eu_prod_PEERING_ID:10.0.0.0/8"
        "$apac_RT_ID:$APAC_REGION:10.20.0.0/16:$apac_to_eu_hub_PEERING_ID:10.0.0.0/8"
    )
    
    for route_config in "${spoke_routes[@]}"; do
        IFS=':' read -r rt_id region hub_cidr peering_id transit_cidr <<< "$route_config"
        
        # Route to local hub
        aws ec2 create-route \
            --region "$region" \
            --route-table-id "$rt_id" \
            --destination-cidr-block "$hub_cidr" \
            --vpc-peering-connection-id "$peering_id" > /dev/null || true
        
        # Route for transit traffic via hub
        aws ec2 create-route \
            --region "$region" \
            --route-table-id "$rt_id" \
            --destination-cidr-block "$transit_cidr" \
            --vpc-peering-connection-id "$peering_id" > /dev/null || true
    done
}

# Setup Route 53 Resolver for cross-region DNS
setup_dns_resolver() {
    if [[ "$SKIP_DNS" == "true" ]]; then
        log_info "Skipping DNS resolver configuration as requested"
        return
    fi
    
    log_info "Setting up Route 53 Resolver for cross-region DNS..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Route 53 Resolver for cross-region DNS"
        return
    fi
    
    # Load state
    source "$STATE_FILE"
    
    # Create resolver rule for internal domain resolution
    local resolver_rule_id=$(aws route53resolver create-resolver-rule \
        --region "$PRIMARY_REGION" \
        --creator-request-id "global-peering-$(date +%s)" \
        --name "${PROJECT_NAME_FULL}-internal-domain" \
        --rule-type FORWARD \
        --domain-name "internal.global.local" \
        --target-ips Ip=10.0.1.100,Port=53 \
        --tags Key=Name,Value=${PROJECT_NAME_FULL}-internal-resolver Key=Project,Value=${PROJECT_NAME_FULL} \
        --query 'ResolverRule.Id' --output text)
    
    echo "RESOLVER_RULE_ID=$resolver_rule_id" >> "$STATE_FILE"
    
    # Associate resolver rule with VPCs in primary region
    local primary_vpcs=("$hub_VPC_ID" "$prod_VPC_ID" "$dev_VPC_ID")
    for vpc_id in "${primary_vpcs[@]}"; do
        aws route53resolver associate-resolver-rule \
            --region "$PRIMARY_REGION" \
            --resolver-rule-id "$resolver_rule_id" \
            --vpc-id "$vpc_id" > /dev/null || true
    done
    
    # Create CloudWatch monitoring for DNS resolution
    aws cloudwatch put-metric-alarm \
        --region "$PRIMARY_REGION" \
        --alarm-name "${PROJECT_NAME_FULL}-Route53-Resolver-Query-Failures" \
        --alarm-description "High DNS query failures in Route53 Resolver" \
        --metric-name QueryCount \
        --namespace AWS/Route53Resolver \
        --statistic Sum \
        --period 300 \
        --threshold 100 \
        --comparison-operator LessThanThreshold \
        --dimensions Name=ResolverRuleId,Value=$resolver_rule_id > /dev/null || true
    
    log_success "Route 53 Resolver configuration completed"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment status"
        return
    fi
    
    # Load state
    source "$STATE_FILE"
    
    local validation_errors=0
    
    # Check VPC peering connections status
    log_info "Checking VPC peering connections..."
    local peering_vars=($(grep "_PEERING_ID=" "$STATE_FILE" | cut -d'=' -f1))
    
    for var in "${peering_vars[@]}"; do
        local peering_id="${!var}"
        local region="$PRIMARY_REGION"  # Default region for checking
        
        # Determine region based on peering connection name
        case "$var" in
            *dr_hub*) region="$SECONDARY_REGION" ;;
            *eu_hub*) region="$EU_REGION" ;;
            *apac*) region="$APAC_REGION" ;;
        esac
        
        local status=$(aws ec2 describe-vpc-peering-connections \
            --region "$region" \
            --vpc-peering-connection-ids "$peering_id" \
            --query 'VpcPeeringConnections[0].Status.Code' --output text 2>/dev/null || echo "error")
        
        if [[ "$status" == "active" ]]; then
            log_success "Peering connection $var is active"
        else
            log_error "Peering connection $var status: $status"
            ((validation_errors++))
        fi
    done
    
    # Check route tables have expected routes
    log_info "Checking route table configurations..."
    
    # Sample validation for hub route table
    local hub_route_count=$(aws ec2 describe-route-tables \
        --region "$PRIMARY_REGION" \
        --route-table-ids "$hub_RT_ID" \
        --query 'length(RouteTables[0].Routes[?VpcPeeringConnectionId])' --output text)
    
    if [[ "$hub_route_count" -ge 6 ]]; then
        log_success "Hub route table has expected number of peering routes"
    else
        log_warning "Hub route table may be missing routes (found: $hub_route_count)"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "Deployment validation passed"
    else
        log_warning "Deployment validation completed with $validation_errors warnings/errors"
    fi
}

# Generate deployment report
generate_report() {
    log_info "Generating deployment report..."
    
    local report_file="${SCRIPT_DIR}/../deployment_report_${DEPLOYMENT_ID}.txt"
    
    cat > "$report_file" << EOF
Multi-Region VPC Peering Deployment Report
==========================================

Deployment ID: $DEPLOYMENT_ID
Deployment Time: $(date)
Project Name: $PROJECT_NAME_FULL

Regions Deployed:
- Primary: $PRIMARY_REGION
- Secondary: $SECONDARY_REGION  
- EU: $EU_REGION
- APAC: $APAC_REGION

Resources Created:
EOF
    
    if [[ -f "$STATE_FILE" ]]; then
        echo "" >> "$report_file"
        echo "Resource IDs:" >> "$report_file"
        echo "=============" >> "$report_file"
        cat "$STATE_FILE" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

Architecture Summary:
- 8 VPCs across 4 regions
- Hub-and-spoke topology with transit routing
- Cross-region peering for global connectivity
- Route 53 Resolver for unified DNS (if enabled)

Management:
- State file: $STATE_FILE
- Destroy script: ${SCRIPT_DIR}/destroy.sh
- This report: $report_file

Cost Considerations:
- VPC peering connections: ~\$0.01/hour per connection
- Cross-region data transfer: \$0.02/GB
- Route 53 Resolver queries: \$0.40/million queries

Next Steps:
1. Test connectivity between regions
2. Deploy applications to validate routing
3. Configure monitoring and alerting
4. Review security groups and NACLs
EOF
    
    log_success "Deployment report saved to: $report_file"
}

# Cleanup on script exit
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        
        if [[ -f "$STATE_FILE" ]]; then
            log_info "Partial deployment state saved in: $STATE_FILE"
            log_info "You may need to run destroy.sh to clean up resources"
        fi
    fi
    
    exit $exit_code
}

# Main deployment function
main() {
    log_info "Starting multi-region VPC peering deployment..."
    log_info "Target regions: $PRIMARY_REGION, $SECONDARY_REGION, $EU_REGION, $APAC_REGION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Set up error handling
    trap cleanup EXIT
    
    # Create state file directory
    mkdir -p "$(dirname "$STATE_FILE")"
    
    # Initialize state file
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "# Multi-Region VPC Peering Deployment State" > "$STATE_FILE"
        echo "# Generated: $(date)" >> "$STATE_FILE"
        echo "DEPLOYMENT_ID=$DEPLOYMENT_ID" >> "$STATE_FILE"
        echo "PROJECT_NAME_FULL=$PROJECT_NAME_FULL" >> "$STATE_FILE"
        echo "PRIMARY_REGION=$PRIMARY_REGION" >> "$STATE_FILE"
        echo "SECONDARY_REGION=$SECONDARY_REGION" >> "$STATE_FILE"
        echo "EU_REGION=$EU_REGION" >> "$STATE_FILE"
        echo "APAC_REGION=$APAC_REGION" >> "$STATE_FILE"
    fi
    
    # Execute deployment steps
    check_prerequisites
    check_existing_deployment
    generate_identifiers
    create_vpcs
    create_subnets
    create_peering_connections
    configure_routing
    setup_dns_resolver
    validate_deployment
    
    if [[ "$DRY_RUN" != "true" ]]; then
        generate_report
        log_success "Multi-region VPC peering deployment completed successfully!"
        log_info "State file: $STATE_FILE"
        log_info "To destroy resources, run: ${SCRIPT_DIR}/destroy.sh"
    else
        log_info "Dry run completed - no resources were created"
    fi
}

# Run main function
main "$@"