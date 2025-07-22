#!/bin/bash

# Deploy DNS-Based Load Balancing with Route 53
# This script automates the deployment of multi-region DNS load balancing infrastructure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
        error "Unable to get AWS account information. Check your credentials."
        exit 1
    }
    
    log "AWS Account ID: ${account_id}"
    
    # Check for required tools
    if ! command -v dig &> /dev/null; then
        warning "dig command not found. DNS testing will be limited."
    fi
    
    success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Core configuration
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Region configuration
    export PRIMARY_REGION=${PRIMARY_REGION:-"us-east-1"}
    export SECONDARY_REGION=${SECONDARY_REGION:-"eu-west-1"}
    export TERTIARY_REGION=${TERTIARY_REGION:-"ap-southeast-1"}
    
    # Generate unique identifier
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null) || \
        random_suffix=$(date +%s | tail -c 7)
    
    export RANDOM_SUFFIX=${RANDOM_SUFFIX:-$random_suffix}
    
    # Domain configuration
    export DOMAIN_NAME=${DOMAIN_NAME:-"lb-demo-${RANDOM_SUFFIX}.com"}
    export SUBDOMAIN="api.${DOMAIN_NAME}"
    
    # Network configuration
    export VPC_CIDR="10.0.0.0/16"
    export SUBNET_CIDR="10.0.1.0/24"
    
    # Resource state file
    export STATE_FILE="/tmp/route53-lb-state-${RANDOM_SUFFIX}.env"
    
    log "Domain: ${DOMAIN_NAME}"
    log "Subdomain: ${SUBDOMAIN}"
    log "Regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
    log "State file: ${STATE_FILE}"
    
    success "Environment initialization completed"
}

# Save state for cleanup
save_state() {
    log "Saving deployment state..."
    cat > "${STATE_FILE}" << EOF
# Route 53 DNS Load Balancing Deployment State
# Generated: $(date)
export DOMAIN_NAME="${DOMAIN_NAME}"
export SUBDOMAIN="${SUBDOMAIN}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export PRIMARY_REGION="${PRIMARY_REGION}"
export SECONDARY_REGION="${SECONDARY_REGION}"
export TERTIARY_REGION="${TERTIARY_REGION}"
export HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}"
export VPC_ID_PRIMARY="${VPC_ID_PRIMARY:-}"
export VPC_ID_SECONDARY="${VPC_ID_SECONDARY:-}"
export VPC_ID_TERTIARY="${VPC_ID_TERTIARY:-}"
export ALB_ARN_PRIMARY="${ALB_ARN_PRIMARY:-}"
export ALB_ARN_SECONDARY="${ALB_ARN_SECONDARY:-}"
export ALB_ARN_TERTIARY="${ALB_ARN_TERTIARY:-}"
export ALB_DNS_PRIMARY="${ALB_DNS_PRIMARY:-}"
export ALB_DNS_SECONDARY="${ALB_DNS_SECONDARY:-}"
export ALB_DNS_TERTIARY="${ALB_DNS_TERTIARY:-}"
export HC_ID_PRIMARY="${HC_ID_PRIMARY:-}"
export HC_ID_SECONDARY="${HC_ID_SECONDARY:-}"
export HC_ID_TERTIARY="${HC_ID_TERTIARY:-}"
export SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-}"
EOF
    success "State saved to ${STATE_FILE}"
}

# Create Route 53 hosted zone
create_hosted_zone() {
    log "Creating Route 53 hosted zone for ${DOMAIN_NAME}..."
    
    # Check if hosted zone already exists
    local existing_zone
    existing_zone=$(aws route53 list-hosted-zones-by-name \
        --dns-name "${DOMAIN_NAME}" \
        --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$existing_zone" ]]; then
        warning "Hosted zone already exists: ${existing_zone}"
        export HOSTED_ZONE_ID=$(echo "$existing_zone" | sed 's|/hostedzone/||')
    else
        export HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
            --name "${DOMAIN_NAME}" \
            --caller-reference "$(date +%s)" \
            --query 'HostedZone.Id' --output text | sed 's|/hostedzone/||')
        
        success "Created hosted zone: ${HOSTED_ZONE_ID}"
    fi
    
    save_state
}

# Create VPC infrastructure in a region
create_vpc_infrastructure() {
    local region=$1
    local vpc_id_var=$2
    
    log "Creating VPC infrastructure in ${region}..."
    
    # Set region
    aws configure set region "$region"
    
    # Create VPC
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$VPC_CIDR" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=dns-lb-vpc-${RANDOM_SUFFIX}}]" \
        --query 'Vpc.VpcId' --output text)
    
    # Store VPC ID in the specified variable
    export "${vpc_id_var}=$vpc_id"
    
    # Enable DNS resolution
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-support
    
    # Create internet gateway
    local igw_id
    igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=dns-lb-igw-${RANDOM_SUFFIX}}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$igw_id" \
        --vpc-id "$vpc_id"
    
    # Get availability zones
    local az1 az2
    az1=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[0].ZoneName' --output text)
    az2=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[1].ZoneName' --output text)
    
    # Create subnets
    local subnet_id_1 subnet_id_2
    subnet_id_1=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.1.0/24" \
        --availability-zone "$az1" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=dns-lb-subnet-1-${RANDOM_SUFFIX}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    subnet_id_2=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "10.0.2.0/24" \
        --availability-zone "$az2" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=dns-lb-subnet-2-${RANDOM_SUFFIX}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    # Configure public subnets
    aws ec2 modify-subnet-attribute --subnet-id "$subnet_id_1" --map-public-ip-on-launch
    aws ec2 modify-subnet-attribute --subnet-id "$subnet_id_2" --map-public-ip-on-launch
    
    # Create route table
    local rt_id
    rt_id=$(aws ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=dns-lb-rt-${RANDOM_SUFFIX}}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    # Create route to internet
    aws ec2 create-route \
        --route-table-id "$rt_id" \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id "$igw_id"
    
    # Associate route table with subnets
    aws ec2 associate-route-table --route-table-id "$rt_id" --subnet-id "$subnet_id_1"
    aws ec2 associate-route-table --route-table-id "$rt_id" --subnet-id "$subnet_id_2"
    
    # Create security group for ALB
    local sg_id
    sg_id=$(aws ec2 create-security-group \
        --group-name "alb-sg-${RANDOM_SUFFIX}" \
        --description "Security group for ALB" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=dns-lb-alb-sg-${RANDOM_SUFFIX}}]" \
        --query 'GroupId' --output text)
    
    # Allow HTTP and HTTPS traffic
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr "0.0.0.0/0"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr "0.0.0.0/0"
    
    # Return values for ALB creation
    echo "$vpc_id $subnet_id_1 $subnet_id_2 $sg_id"
    
    success "Created VPC infrastructure in ${region}: ${vpc_id}"
}

# Create Application Load Balancer
create_load_balancer() {
    local region=$1
    local alb_arn_var=$2
    local alb_dns_var=$3
    
    log "Creating Application Load Balancer in ${region}..."
    
    # Set region
    aws configure set region "$region"
    
    # Get VPC infrastructure details
    local vpc_info
    case "$region" in
        "$PRIMARY_REGION")
            vpc_info=$(create_vpc_infrastructure "$region" "VPC_ID_PRIMARY")
            ;;
        "$SECONDARY_REGION")
            vpc_info=$(create_vpc_infrastructure "$region" "VPC_ID_SECONDARY")
            ;;
        "$TERTIARY_REGION")
            vpc_info=$(create_vpc_infrastructure "$region" "VPC_ID_TERTIARY")
            ;;
    esac
    
    read -r vpc_id subnet_id_1 subnet_id_2 sg_id <<< "$vpc_info"
    
    # Create Application Load Balancer
    local alb_arn
    alb_arn=$(aws elbv2 create-load-balancer \
        --name "alb-${region}-${RANDOM_SUFFIX}" \
        --subnets "$subnet_id_1" "$subnet_id_2" \
        --security-groups "$sg_id" \
        --tags Key=Name,Value="dns-lb-alb-${region}-${RANDOM_SUFFIX}" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Get ALB DNS name
    local alb_dns
    alb_dns=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    # Create target group
    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "tg-${region}-${RANDOM_SUFFIX}" \
        --protocol HTTP \
        --port 80 \
        --vpc-id "$vpc_id" \
        --health-check-path "/health" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags Key=Name,Value="dns-lb-tg-${region}-${RANDOM_SUFFIX}" \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create listener
    aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$tg_arn" \
        --tags Key=Name,Value="dns-lb-listener-${region}-${RANDOM_SUFFIX}" \
        > /dev/null
    
    # Export variables
    export "${alb_arn_var}=$alb_arn"
    export "${alb_dns_var}=$alb_dns"
    
    success "Created ALB in ${region}: ${alb_dns}"
    save_state
}

# Create health checks
create_health_checks() {
    log "Creating Route 53 health checks..."
    
    # Set to primary region for Route 53 operations
    aws configure set region "$PRIMARY_REGION"
    
    # Create health check for primary region
    export HC_ID_PRIMARY=$(aws route53 create-health-check \
        --caller-reference "hc-primary-$(date +%s)" \
        --health-check-config '{
          "Type": "HTTP",
          "ResourcePath": "/health",
          "FullyQualifiedDomainName": "'$ALB_DNS_PRIMARY'",
          "Port": 80,
          "RequestInterval": 30,
          "FailureThreshold": 3
        }' \
        --query 'HealthCheck.Id' --output text)
    
    # Create health check for secondary region
    export HC_ID_SECONDARY=$(aws route53 create-health-check \
        --caller-reference "hc-secondary-$(date +%s)" \
        --health-check-config '{
          "Type": "HTTP",
          "ResourcePath": "/health",
          "FullyQualifiedDomainName": "'$ALB_DNS_SECONDARY'",
          "Port": 80,
          "RequestInterval": 30,
          "FailureThreshold": 3
        }' \
        --query 'HealthCheck.Id' --output text)
    
    # Create health check for tertiary region
    export HC_ID_TERTIARY=$(aws route53 create-health-check \
        --caller-reference "hc-tertiary-$(date +%s)" \
        --health-check-config '{
          "Type": "HTTP",
          "ResourcePath": "/health",
          "FullyQualifiedDomainName": "'$ALB_DNS_TERTIARY'",
          "Port": 80,
          "RequestInterval": 30,
          "FailureThreshold": 3
        }' \
        --query 'HealthCheck.Id' --output text)
    
    # Add tags to health checks
    aws route53 change-tags-for-resource \
        --resource-type healthcheck \
        --resource-id "$HC_ID_PRIMARY" \
        --add-tags Key=Environment,Value=Demo \
                   Key=Region,Value="$PRIMARY_REGION" \
                   Key=Application,Value=DNS-LoadBalancing
    
    aws route53 change-tags-for-resource \
        --resource-type healthcheck \
        --resource-id "$HC_ID_SECONDARY" \
        --add-tags Key=Environment,Value=Demo \
                   Key=Region,Value="$SECONDARY_REGION" \
                   Key=Application,Value=DNS-LoadBalancing
    
    aws route53 change-tags-for-resource \
        --resource-type healthcheck \
        --resource-id "$HC_ID_TERTIARY" \
        --add-tags Key=Environment,Value=Demo \
                   Key=Region,Value="$TERTIARY_REGION" \
                   Key=Application,Value=DNS-LoadBalancing
    
    success "Created health checks: ${HC_ID_PRIMARY}, ${HC_ID_SECONDARY}, ${HC_ID_TERTIARY}"
    save_state
}

# Create DNS routing records
create_dns_records() {
    log "Creating DNS routing records..."
    
    # Set to primary region for Route 53 operations
    aws configure set region "$PRIMARY_REGION"
    
    # Wait for ALBs to be active
    log "Waiting for load balancers to become active..."
    sleep 60
    
    # Create weighted routing records
    log "Creating weighted routing records..."
    
    # Primary region - 50% weight
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
          "Changes": [
            {
              "Action": "CREATE",
              "ResourceRecordSet": {
                "Name": "'$SUBDOMAIN'",
                "Type": "A",
                "SetIdentifier": "Primary-Weighted",
                "Weight": 50,
                "TTL": 60,
                "ResourceRecords": [
                  {
                    "Value": "192.0.2.1"
                  }
                ],
                "HealthCheckId": "'$HC_ID_PRIMARY'"
              }
            }
          ]
        }' > /dev/null
    
    # Secondary region - 30% weight
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
          "Changes": [
            {
              "Action": "CREATE",
              "ResourceRecordSet": {
                "Name": "'$SUBDOMAIN'",
                "Type": "A",
                "SetIdentifier": "Secondary-Weighted",
                "Weight": 30,
                "TTL": 60,
                "ResourceRecords": [
                  {
                    "Value": "192.0.2.2"
                  }
                ],
                "HealthCheckId": "'$HC_ID_SECONDARY'"
              }
            }
          ]
        }' > /dev/null
    
    # Tertiary region - 20% weight
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
          "Changes": [
            {
              "Action": "CREATE",
              "ResourceRecordSet": {
                "Name": "'$SUBDOMAIN'",
                "Type": "A",
                "SetIdentifier": "Tertiary-Weighted",
                "Weight": 20,
                "TTL": 60,
                "ResourceRecords": [
                  {
                    "Value": "192.0.2.3"
                  }
                ],
                "HealthCheckId": "'$HC_ID_TERTIARY'"
              }
            }
          ]
        }' > /dev/null
    
    # Create latency-based routing
    log "Creating latency-based routing records..."
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
          "Changes": [
            {
              "Action": "CREATE",
              "ResourceRecordSet": {
                "Name": "latency.'$SUBDOMAIN'",
                "Type": "A",
                "SetIdentifier": "Primary-Latency",
                "Region": "'$PRIMARY_REGION'",
                "TTL": 60,
                "ResourceRecords": [
                  {
                    "Value": "192.0.2.1"
                  }
                ],
                "HealthCheckId": "'$HC_ID_PRIMARY'"
              }
            }
          ]
        }' > /dev/null
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
          "Changes": [
            {
              "Action": "CREATE",
              "ResourceRecordSet": {
                "Name": "latency.'$SUBDOMAIN'",
                "Type": "A",
                "SetIdentifier": "Secondary-Latency",
                "Region": "'$SECONDARY_REGION'",
                "TTL": 60,
                "ResourceRecords": [
                  {
                    "Value": "192.0.2.2"
                  }
                ],
                "HealthCheckId": "'$HC_ID_SECONDARY'"
              }
            }
          ]
        }' > /dev/null
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
          "Changes": [
            {
              "Action": "CREATE",
              "ResourceRecordSet": {
                "Name": "latency.'$SUBDOMAIN'",
                "Type": "A",
                "SetIdentifier": "Tertiary-Latency",
                "Region": "'$TERTIARY_REGION'",
                "TTL": 60,
                "ResourceRecords": [
                  {
                    "Value": "192.0.2.3"
                  }
                ],
                "HealthCheckId": "'$HC_ID_TERTIARY'"
              }
            }
          ]
        }' > /dev/null
    
    # Create failover routing
    log "Creating failover routing records..."
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
          "Changes": [
            {
              "Action": "CREATE",
              "ResourceRecordSet": {
                "Name": "failover.'$SUBDOMAIN'",
                "Type": "A",
                "SetIdentifier": "Primary-Failover",
                "Failover": "PRIMARY",
                "TTL": 60,
                "ResourceRecords": [
                  {
                    "Value": "192.0.2.1"
                  }
                ],
                "HealthCheckId": "'$HC_ID_PRIMARY'"
              }
            }
          ]
        }' > /dev/null
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
          "Changes": [
            {
              "Action": "CREATE",
              "ResourceRecordSet": {
                "Name": "failover.'$SUBDOMAIN'",
                "Type": "A",
                "SetIdentifier": "Secondary-Failover",
                "Failover": "SECONDARY",
                "TTL": 60,
                "ResourceRecords": [
                  {
                    "Value": "192.0.2.2"
                  }
                ],
                "HealthCheckId": "'$HC_ID_SECONDARY'"
              }
            }
          ]
        }' > /dev/null
    
    success "Created DNS routing records"
}

# Create SNS notifications
create_sns_notifications() {
    log "Creating SNS topic for health check notifications..."
    
    # Set to primary region for Route 53 operations
    aws configure set region "$PRIMARY_REGION"
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "route53-health-alerts-${RANDOM_SUFFIX}" \
        --tags Key=Application,Value=DNS-LoadBalancing \
        --query 'TopicArn' --output text)
    
    success "Created SNS topic: ${SNS_TOPIC_ARN}"
    save_state
}

# Run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Set to primary region
    aws configure set region "$PRIMARY_REGION"
    
    # List resource record sets
    log "Checking DNS records..."
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query 'ResourceRecordSets[?Type==`A`].[Name,Type,SetIdentifier,Weight,Region]' \
        --output table
    
    # Check health check status
    log "Checking health check status..."
    if command -v dig &> /dev/null; then
        log "Testing DNS resolution..."
        dig +short "$SUBDOMAIN" @8.8.8.8 || warning "DNS resolution test failed"
        dig +short "latency.$SUBDOMAIN" @8.8.8.8 || warning "Latency DNS test failed"
        dig +short "failover.$SUBDOMAIN" @8.8.8.8 || warning "Failover DNS test failed"
    else
        warning "dig command not available, skipping DNS resolution tests"
    fi
    
    success "Validation completed"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary"
    echo "==================="
    echo "Domain: ${DOMAIN_NAME}"
    echo "Subdomain: ${SUBDOMAIN}"
    echo "Hosted Zone ID: ${HOSTED_ZONE_ID}"
    echo "Primary Region: ${PRIMARY_REGION}"
    echo "Secondary Region: ${SECONDARY_REGION}"
    echo "Tertiary Region: ${TERTIARY_REGION}"
    echo "State File: ${STATE_FILE}"
    echo ""
    echo "DNS Endpoints:"
    echo "- Weighted: ${SUBDOMAIN}"
    echo "- Latency: latency.${SUBDOMAIN}"
    echo "- Failover: failover.${SUBDOMAIN}"
    echo ""
    echo "Health Checks:"
    echo "- Primary: ${HC_ID_PRIMARY}"
    echo "- Secondary: ${HC_ID_SECONDARY}"
    echo "- Tertiary: ${HC_ID_TERTIARY}"
    echo ""
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo ""
    warning "Remember to update your domain's name servers to point to Route 53 if using an external registrar"
    warning "The health checks will fail until you deploy actual applications behind the load balancers"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting DNS-based Load Balancing deployment..."
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_hosted_zone
    
    # Create infrastructure in each region
    create_load_balancer "$PRIMARY_REGION" "ALB_ARN_PRIMARY" "ALB_DNS_PRIMARY"
    create_load_balancer "$SECONDARY_REGION" "ALB_ARN_SECONDARY" "ALB_DNS_SECONDARY"
    create_load_balancer "$TERTIARY_REGION" "ALB_ARN_TERTIARY" "ALB_DNS_TERTIARY"
    
    # Create Route 53 configuration
    create_health_checks
    create_dns_records
    create_sns_notifications
    
    # Validate deployment
    run_validation
    
    # Show summary
    print_summary
}

# Handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted. Deployment may be incomplete."
    error "Use destroy.sh to clean up any created resources."
    exit 1
}

trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"