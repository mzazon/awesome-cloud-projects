#!/bin/bash

# Destroy DNS-Based Load Balancing with Route 53
# This script safely removes all resources created by the deploy.sh script

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

# Global variables for confirmation
FORCE_DESTROY=${FORCE_DESTROY:-false}
DRY_RUN=${DRY_RUN:-false}

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force      Skip confirmation prompts (dangerous)"
    echo "  -d, --dry-run    Show what would be deleted without actually deleting"
    echo "  -s, --state-file Specify custom state file path"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive cleanup"
    echo "  $0 --dry-run                 # Show what would be deleted"
    echo "  $0 --force                   # Skip confirmations"
    echo "  $0 --state-file /path/file   # Use custom state file"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DESTROY=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--state-file)
                STATE_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
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
    
    success "Prerequisites check completed"
}

# Load deployment state
load_state() {
    log "Loading deployment state..."
    
    # Find state file if not specified
    if [[ -z "${STATE_FILE:-}" ]]; then
        # Look for state files in /tmp
        local state_files
        state_files=$(find /tmp -name "route53-lb-state-*.env" -type f 2>/dev/null || true)
        
        if [[ -z "$state_files" ]]; then
            error "No state file found. Cannot proceed with cleanup."
            error "If you know the resource identifiers, you can delete them manually."
            exit 1
        elif [[ $(echo "$state_files" | wc -l) -gt 1 ]]; then
            error "Multiple state files found:"
            echo "$state_files"
            error "Please specify which one to use with --state-file option."
            exit 1
        else
            STATE_FILE="$state_files"
        fi
    fi
    
    if [[ ! -f "$STATE_FILE" ]]; then
        error "State file not found: $STATE_FILE"
        exit 1
    fi
    
    # Source the state file
    log "Loading state from: $STATE_FILE"
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    
    # Verify required variables are set
    local required_vars=(
        "DOMAIN_NAME"
        "SUBDOMAIN"
        "RANDOM_SUFFIX"
        "PRIMARY_REGION"
        "SECONDARY_REGION"
        "TERTIARY_REGION"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var not found in state file"
            exit 1
        fi
    done
    
    success "State loaded successfully"
    log "Domain: ${DOMAIN_NAME}"
    log "Random suffix: ${RANDOM_SUFFIX}"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This will permanently delete the following resources:"
    echo "- Route 53 hosted zone: ${HOSTED_ZONE_ID:-unknown}"
    echo "- DNS records in domain: ${DOMAIN_NAME}"
    echo "- Health checks in Route 53"
    echo "- Application Load Balancers in 3 regions"
    echo "- VPC infrastructure in 3 regions"
    echo "- SNS topic: ${SNS_TOPIC_ARN:-unknown}"
    echo ""
    echo "Regions affected:"
    echo "- Primary: ${PRIMARY_REGION}"
    echo "- Secondary: ${SECONDARY_REGION}"
    echo "- Tertiary: ${TERTIARY_REGION}"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No resources will actually be deleted"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ $REPLY != "yes" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Execute command with dry-run support
execute() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: $cmd"
        echo "  Description: $description"
        return 0
    else
        log "$description"
        eval "$cmd" || {
            warning "Command failed: $cmd"
            return 1
        }
    fi
}

# Delete Route 53 DNS records
delete_dns_records() {
    log "Deleting Route 53 DNS records..."
    
    if [[ -z "${HOSTED_ZONE_ID:-}" ]]; then
        warning "Hosted zone ID not found in state, skipping DNS records deletion"
        return 0
    fi
    
    # Set to primary region for Route 53 operations
    aws configure set region "$PRIMARY_REGION"
    
    # Get all A records with routing policies
    local records
    records=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query 'ResourceRecordSets[?Type==`A` && SetIdentifier!=null]' \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$records" == "[]" ]]; then
        log "No routing policy records found to delete"
    else
        # Delete weighted routing records
        if [[ -n "${HC_ID_PRIMARY:-}" ]]; then
            execute "aws route53 change-resource-record-sets \
                --hosted-zone-id '$HOSTED_ZONE_ID' \
                --change-batch '{
                  \"Changes\": [
                    {
                      \"Action\": \"DELETE\",
                      \"ResourceRecordSet\": {
                        \"Name\": \"'$SUBDOMAIN'\",
                        \"Type\": \"A\",
                        \"SetIdentifier\": \"Primary-Weighted\",
                        \"Weight\": 50,
                        \"TTL\": 60,
                        \"ResourceRecords\": [{\"Value\": \"192.0.2.1\"}],
                        \"HealthCheckId\": \"'$HC_ID_PRIMARY'\"
                      }
                    }
                  ]
                }' > /dev/null" "Deleting primary weighted record"
        fi
        
        if [[ -n "${HC_ID_SECONDARY:-}" ]]; then
            execute "aws route53 change-resource-record-sets \
                --hosted-zone-id '$HOSTED_ZONE_ID' \
                --change-batch '{
                  \"Changes\": [
                    {
                      \"Action\": \"DELETE\",
                      \"ResourceRecordSet\": {
                        \"Name\": \"'$SUBDOMAIN'\",
                        \"Type\": \"A\",
                        \"SetIdentifier\": \"Secondary-Weighted\",
                        \"Weight\": 30,
                        \"TTL\": 60,
                        \"ResourceRecords\": [{\"Value\": \"192.0.2.2\"}],
                        \"HealthCheckId\": \"'$HC_ID_SECONDARY'\"
                      }
                    }
                  ]
                }' > /dev/null" "Deleting secondary weighted record"
        fi
        
        if [[ -n "${HC_ID_TERTIARY:-}" ]]; then
            execute "aws route53 change-resource-record-sets \
                --hosted-zone-id '$HOSTED_ZONE_ID' \
                --change-batch '{
                  \"Changes\": [
                    {
                      \"Action\": \"DELETE\",
                      \"ResourceRecordSet\": {
                        \"Name\": \"'$SUBDOMAIN'\",
                        \"Type\": \"A\",
                        \"SetIdentifier\": \"Tertiary-Weighted\",
                        \"Weight\": 20,
                        \"TTL\": 60,
                        \"ResourceRecords\": [{\"Value\": \"192.0.2.3\"}],
                        \"HealthCheckId\": \"'$HC_ID_TERTIARY'\"
                      }
                    }
                  ]
                }' > /dev/null" "Deleting tertiary weighted record"
        fi
        
        # Delete latency-based records
        for region_var in "PRIMARY_REGION" "SECONDARY_REGION" "TERTIARY_REGION"; do
            local region="${!region_var}"
            local hc_var="HC_ID_${region_var%_REGION}"
            local hc_id="${!hc_var:-}"
            local ip_suffix
            
            case "$region_var" in
                "PRIMARY_REGION") ip_suffix="1" ;;
                "SECONDARY_REGION") ip_suffix="2" ;;
                "TERTIARY_REGION") ip_suffix="3" ;;
            esac
            
            if [[ -n "$hc_id" ]]; then
                execute "aws route53 change-resource-record-sets \
                    --hosted-zone-id '$HOSTED_ZONE_ID' \
                    --change-batch '{
                      \"Changes\": [
                        {
                          \"Action\": \"DELETE\",
                          \"ResourceRecordSet\": {
                            \"Name\": \"latency.'$SUBDOMAIN'\",
                            \"Type\": \"A\",
                            \"SetIdentifier\": \"'${region_var%_REGION}'-Latency\",
                            \"Region\": \"'$region'\",
                            \"TTL\": 60,
                            \"ResourceRecords\": [{\"Value\": \"192.0.2.'$ip_suffix'\"}],
                            \"HealthCheckId\": \"'$hc_id'\"
                          }
                        }
                      ]
                    }' > /dev/null" "Deleting latency record for $region"
            fi
        done
        
        # Delete failover records
        if [[ -n "${HC_ID_PRIMARY:-}" ]]; then
            execute "aws route53 change-resource-record-sets \
                --hosted-zone-id '$HOSTED_ZONE_ID' \
                --change-batch '{
                  \"Changes\": [
                    {
                      \"Action\": \"DELETE\",
                      \"ResourceRecordSet\": {
                        \"Name\": \"failover.'$SUBDOMAIN'\",
                        \"Type\": \"A\",
                        \"SetIdentifier\": \"Primary-Failover\",
                        \"Failover\": \"PRIMARY\",
                        \"TTL\": 60,
                        \"ResourceRecords\": [{\"Value\": \"192.0.2.1\"}],
                        \"HealthCheckId\": \"'$HC_ID_PRIMARY'\"
                      }
                    }
                  ]
                }' > /dev/null" "Deleting primary failover record"
        fi
        
        if [[ -n "${HC_ID_SECONDARY:-}" ]]; then
            execute "aws route53 change-resource-record-sets \
                --hosted-zone-id '$HOSTED_ZONE_ID' \
                --change-batch '{
                  \"Changes\": [
                    {
                      \"Action\": \"DELETE\",
                      \"ResourceRecordSet\": {
                        \"Name\": \"failover.'$SUBDOMAIN'\",
                        \"Type\": \"A\",
                        \"SetIdentifier\": \"Secondary-Failover\",
                        \"Failover\": \"SECONDARY\",
                        \"TTL\": 60,
                        \"ResourceRecords\": [{\"Value\": \"192.0.2.2\"}],
                        \"HealthCheckId\": \"'$HC_ID_SECONDARY'\"
                      }
                    }
                  ]
                }' > /dev/null" "Deleting secondary failover record"
        fi
    fi
    
    success "DNS records deletion completed"
}

# Delete Route 53 health checks
delete_health_checks() {
    log "Deleting Route 53 health checks..."
    
    # Set to primary region for Route 53 operations
    aws configure set region "$PRIMARY_REGION"
    
    for hc_var in "HC_ID_PRIMARY" "HC_ID_SECONDARY" "HC_ID_TERTIARY"; do
        local hc_id="${!hc_var:-}"
        if [[ -n "$hc_id" ]]; then
            execute "aws route53 delete-health-check --health-check-id '$hc_id'" \
                "Deleting health check: $hc_id"
        fi
    done
    
    success "Health checks deletion completed"
}

# Delete SNS topic
delete_sns_topic() {
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        log "Deleting SNS topic..."
        
        # Set to primary region
        aws configure set region "$PRIMARY_REGION"
        
        execute "aws sns delete-topic --topic-arn '$SNS_TOPIC_ARN'" \
            "Deleting SNS topic: $SNS_TOPIC_ARN"
        
        success "SNS topic deletion completed"
    else
        log "No SNS topic ARN found in state"
    fi
}

# Delete Load Balancers in a region
delete_load_balancers() {
    local region=$1
    local alb_arn_var=$2
    
    log "Deleting load balancers in $region..."
    
    # Set region
    aws configure set region "$region"
    
    local alb_arn="${!alb_arn_var:-}"
    if [[ -n "$alb_arn" ]]; then
        # Wait for DNS records to be deleted first
        if [[ "$DRY_RUN" != "true" ]]; then
            log "Waiting for DNS changes to propagate before deleting ALB..."
            sleep 30
        fi
        
        execute "aws elbv2 delete-load-balancer --load-balancer-arn '$alb_arn'" \
            "Deleting ALB: $alb_arn"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log "Waiting for ALB deletion to complete..."
            sleep 60
        fi
    else
        log "No ALB ARN found for $region"
    fi
    
    success "Load balancer deletion completed for $region"
}

# Delete VPC infrastructure in a region
delete_vpc_infrastructure() {
    local region=$1
    local vpc_id_var=$2
    
    log "Deleting VPC infrastructure in $region..."
    
    # Set region
    aws configure set region "$region"
    
    local vpc_id="${!vpc_id_var:-}"
    if [[ -z "$vpc_id" ]]; then
        log "No VPC ID found for $region, skipping"
        return 0
    fi
    
    # Find and delete target groups
    local target_groups
    target_groups=$(aws elbv2 describe-target-groups \
        --query "TargetGroups[?VpcId=='$vpc_id'].TargetGroupArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$target_groups" ]]; then
        for tg_arn in $target_groups; do
            execute "aws elbv2 delete-target-group --target-group-arn '$tg_arn'" \
                "Deleting target group: $tg_arn"
        done
    fi
    
    # Find and delete security groups (except default)
    local security_groups
    security_groups=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$security_groups" ]]; then
        for sg_id in $security_groups; do
            execute "aws ec2 delete-security-group --group-id '$sg_id'" \
                "Deleting security group: $sg_id"
        done
    fi
    
    # Find and delete subnets
    local subnets
    subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "Subnets[].SubnetId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$subnets" ]]; then
        for subnet_id in $subnets; do
            execute "aws ec2 delete-subnet --subnet-id '$subnet_id'" \
                "Deleting subnet: $subnet_id"
        done
    fi
    
    # Find and delete route tables (except main)
    local route_tables
    route_tables=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$route_tables" ]]; then
        for rt_id in $route_tables; do
            execute "aws ec2 delete-route-table --route-table-id '$rt_id'" \
                "Deleting route table: $rt_id"
        done
    fi
    
    # Find and detach/delete internet gateways
    local igws
    igws=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$vpc_id" \
        --query "InternetGateways[].InternetGatewayId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$igws" ]]; then
        for igw_id in $igws; do
            execute "aws ec2 detach-internet-gateway --internet-gateway-id '$igw_id' --vpc-id '$vpc_id'" \
                "Detaching internet gateway: $igw_id"
            execute "aws ec2 delete-internet-gateway --internet-gateway-id '$igw_id'" \
                "Deleting internet gateway: $igw_id"
        done
    fi
    
    # Finally, delete the VPC
    execute "aws ec2 delete-vpc --vpc-id '$vpc_id'" \
        "Deleting VPC: $vpc_id"
    
    success "VPC infrastructure deletion completed for $region"
}

# Delete hosted zone
delete_hosted_zone() {
    if [[ -n "${HOSTED_ZONE_ID:-}" ]]; then
        log "Deleting Route 53 hosted zone..."
        
        # Set to primary region
        aws configure set region "$PRIMARY_REGION"
        
        execute "aws route53 delete-hosted-zone --id '$HOSTED_ZONE_ID'" \
            "Deleting hosted zone: $HOSTED_ZONE_ID"
        
        success "Hosted zone deletion completed"
    else
        log "No hosted zone ID found in state"
    fi
}

# Clean up state file
cleanup_state_file() {
    if [[ -f "$STATE_FILE" && "$DRY_RUN" != "true" ]]; then
        log "Removing state file: $STATE_FILE"
        rm -f "$STATE_FILE"
        success "State file removed"
    fi
}

# Print destruction summary
print_summary() {
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN SUMMARY"
        echo "==============="
        echo "The following resources would be deleted:"
    else
        log "DESTRUCTION SUMMARY"
        echo "==================="
        echo "The following resources have been deleted:"
    fi
    
    echo "- Route 53 hosted zone: ${HOSTED_ZONE_ID:-unknown}"
    echo "- DNS records for domain: ${DOMAIN_NAME}"
    echo "- Health checks: ${HC_ID_PRIMARY:-unknown}, ${HC_ID_SECONDARY:-unknown}, ${HC_ID_TERTIARY:-unknown}"
    echo "- Load balancers in regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
    echo "- VPC infrastructure in all regions"
    echo "- SNS topic: ${SNS_TOPIC_ARN:-unknown}"
    echo "- State file: ${STATE_FILE}"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "This was a dry run - no resources were actually deleted"
        echo "Run without --dry-run to perform actual deletion"
    else
        success "Cleanup completed successfully!"
        warning "All Route 53 DNS load balancing resources have been removed"
    fi
}

# Main destruction function
main() {
    local start_time
    start_time=$(date +%s)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Starting DNS-based Load Balancing cleanup (DRY RUN)..."
    else
        log "Starting DNS-based Load Balancing cleanup..."
    fi
    
    # Run destruction steps
    check_prerequisites
    load_state
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_dns_records
    delete_health_checks
    delete_sns_topic
    
    # Delete load balancers in all regions
    delete_load_balancers "$PRIMARY_REGION" "ALB_ARN_PRIMARY"
    delete_load_balancers "$SECONDARY_REGION" "ALB_ARN_SECONDARY"
    delete_load_balancers "$TERTIARY_REGION" "ALB_ARN_TERTIARY"
    
    # Delete VPC infrastructure in all regions
    delete_vpc_infrastructure "$PRIMARY_REGION" "VPC_ID_PRIMARY"
    delete_vpc_infrastructure "$SECONDARY_REGION" "VPC_ID_SECONDARY"
    delete_vpc_infrastructure "$TERTIARY_REGION" "VPC_ID_TERTIARY"
    
    # Delete hosted zone last
    delete_hosted_zone
    
    # Clean up state file
    cleanup_state_file
    
    # Show summary
    print_summary
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log "Total cleanup time: ${duration} seconds"
}

# Handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted. Cleanup may be incomplete."
    error "Some resources may still exist and incur charges."
    error "Re-run the script to continue cleanup."
    exit 1
}

trap cleanup_on_interrupt INT TERM

# Parse arguments and run main function
parse_arguments "$@"
main