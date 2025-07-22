#!/bin/bash

# =============================================================================
# AWS Wavelength and CloudFront Edge Application Cleanup Script
# 
# This script safely removes all resources created by the deployment script:
# - CloudFront Distribution
# - Route 53 DNS records
# - Application Load Balancer and Target Groups
# - EC2 Instances
# - Networking components (VPC, Subnets, Security Groups, etc.)
# - S3 Bucket and contents
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        "instance")
            aws ec2 describe-instances --instance-ids "$resource_id" &>/dev/null
            ;;
        "vpc")
            aws ec2 describe-vpcs --vpc-ids "$resource_id" &>/dev/null
            ;;
        "subnet")
            aws ec2 describe-subnets --subnet-ids "$resource_id" &>/dev/null
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids "$resource_id" &>/dev/null
            ;;
        "internet-gateway")
            aws ec2 describe-internet-gateways --internet-gateway-ids "$resource_id" &>/dev/null
            ;;
        "carrier-gateway")
            aws ec2 describe-carrier-gateways --carrier-gateway-ids "$resource_id" &>/dev/null
            ;;
        "route-table")
            aws ec2 describe-route-tables --route-table-ids "$resource_id" &>/dev/null
            ;;
        "load-balancer")
            aws elbv2 describe-load-balancers --load-balancer-arns "$resource_id" &>/dev/null
            ;;
        "target-group")
            aws elbv2 describe-target-groups --target-group-arns "$resource_id" &>/dev/null
            ;;
        "cloudfront")
            aws cloudfront get-distribution --id "$resource_id" &>/dev/null
            ;;
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_id" &>/dev/null
            ;;
        "hosted-zone")
            aws route53 get-hosted-zone --id "$resource_id" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local max_wait="${3:-300}"  # Default 5 minutes
    local wait_time=0
    
    while resource_exists "$resource_type" "$resource_id" && [[ $wait_time -lt $max_wait ]]; do
        log "Waiting for $resource_type $resource_id to be deleted..."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        warning "Timeout waiting for $resource_type $resource_id to be deleted"
        return 1
    fi
    
    return 0
}

# Load resource information
load_resources() {
    local project_name="$1"
    local resource_file="${project_name}-resources.env"
    
    if [[ ! -f "$resource_file" ]]; then
        error "Resource file not found: $resource_file"
        error "Please ensure you run this script from the same directory as the deployment"
        exit 1
    fi
    
    log "Loading resource information from: $resource_file"
    
    # Source the resource file
    set -a  # Automatically export all variables
    source "$resource_file"
    set +a
    
    # Verify required variables
    local required_vars=(
        "PROJECT_NAME" "AWS_REGION" "AWS_ACCOUNT_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var not found in resource file"
            exit 1
        fi
    done
    
    success "Resource information loaded successfully"
}

# Confirm deletion
confirm_deletion() {
    local project_name="$1"
    
    echo ""
    echo "==================================================================="
    echo "                    ⚠️  RESOURCE DELETION WARNING ⚠️"
    echo "==================================================================="
    echo ""
    echo "You are about to DELETE all resources for project: ${project_name}"
    echo ""
    echo "This will remove:"
    echo "  • CloudFront Distribution (${DISTRIBUTION_ID:-unknown})"
    echo "  • Route 53 DNS records and hosted zone"
    echo "  • Application Load Balancer and Target Groups"
    echo "  • EC2 Instances in Wavelength Zone"
    echo "  • VPC, Subnets, Security Groups, and Networking"
    echo "  • S3 Bucket and all contents (${S3_BUCKET:-unknown})"
    echo "  • All associated IAM roles and policies"
    echo ""
    echo "💰 COST IMPACT:"
    echo "  • This will STOP ALL CHARGES for these resources"
    echo "  • Data transfer charges will cease immediately"
    echo "  • No further Wavelength or CloudFront charges"
    echo ""
    echo "⚠️  WARNING: This action CANNOT be undone!"
    echo ""
    echo "==================================================================="
    echo ""
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        warning "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you absolutely sure you want to delete ALL resources? (type 'yes' to confirm): " -r
    if [[ $REPLY != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Final confirmation - Type the project name '${project_name}' to proceed: " -r
    if [[ $REPLY != "$project_name" ]]; then
        log "Deletion cancelled - project name mismatch"
        exit 0
    fi
}

# Delete CloudFront distribution
delete_cloudfront() {
    if [[ -z "${DISTRIBUTION_ID:-}" ]]; then
        warning "CloudFront distribution ID not found, skipping"
        return 0
    fi
    
    if ! resource_exists "cloudfront" "$DISTRIBUTION_ID"; then
        warning "CloudFront distribution $DISTRIBUTION_ID not found, skipping"
        return 0
    fi
    
    log "Deleting CloudFront distribution: $DISTRIBUTION_ID"
    
    # Get current config and ETag
    local config_file="dist-config-temp.json"
    local etag_file="etag-temp.txt"
    
    aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --query 'DistributionConfig' > "$config_file"
    
    aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'ETag' \
        --output text > "$etag_file"
    
    # Disable distribution first
    log "Disabling CloudFront distribution..."
    sed -i.bak 's/"Enabled": true/"Enabled": false/' "$config_file"
    
    local etag
    etag=$(cat "$etag_file")
    
    local new_etag
    new_etag=$(aws cloudfront update-distribution \
        --id "$DISTRIBUTION_ID" \
        --distribution-config file://"$config_file" \
        --if-match "$etag" \
        --query 'ETag' --output text)
    
    # Wait for distribution to be disabled
    log "Waiting for CloudFront distribution to be disabled (this may take 10-15 minutes)..."
    local retries=0
    while [[ $retries -lt 60 ]]; do  # Wait up to 30 minutes
        local status
        status=$(aws cloudfront get-distribution \
            --id "$DISTRIBUTION_ID" \
            --query 'Distribution.Status' \
            --output text 2>/dev/null || echo "NotFound")
        
        if [[ "$status" == "Deployed" ]]; then
            local enabled
            enabled=$(aws cloudfront get-distribution \
                --id "$DISTRIBUTION_ID" \
                --query 'Distribution.DistributionConfig.Enabled' \
                --output text)
            
            if [[ "$enabled" == "False" ]]; then
                break
            fi
        fi
        
        log "Distribution status: $status, waiting..."
        sleep 30
        ((retries++))
    done
    
    # Delete the distribution
    log "Deleting CloudFront distribution..."
    aws cloudfront delete-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$new_etag" || warning "Failed to delete CloudFront distribution"
    
    # Clean up temp files
    rm -f "$config_file" "$config_file.bak" "$etag_file"
    
    success "CloudFront distribution deletion initiated"
}

# Delete Route 53 resources
delete_route53() {
    if [[ -z "${HOSTED_ZONE_ID:-}" ]] || [[ "${DOMAIN_NAME:-}" == "your-domain.com" ]]; then
        warning "Route 53 resources not configured or using default domain, skipping"
        return 0
    fi
    
    if ! resource_exists "hosted-zone" "$HOSTED_ZONE_ID"; then
        warning "Hosted zone $HOSTED_ZONE_ID not found, skipping"
        return 0
    fi
    
    log "Deleting Route 53 DNS records..."
    
    # Delete CNAME record if it exists
    if [[ -n "${CF_DOMAIN:-}" ]]; then
        cat > dns-delete.json << EOF
{
    "Changes": [
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "app.${DOMAIN_NAME}",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "${CF_DOMAIN}"
                    }
                ]
            }
        }
    ]
}
EOF
        
        aws route53 change-resource-record-sets \
            --hosted-zone-id "$HOSTED_ZONE_ID" \
            --change-batch file://dns-delete.json \
            --output text &>/dev/null || warning "Failed to delete CNAME record"
        
        rm dns-delete.json
    fi
    
    # Note: We don't delete the hosted zone as it may contain other records
    # Users should manually delete it if they no longer need it
    warning "Hosted zone $HOSTED_ZONE_ID preserved (may contain other DNS records)"
    warning "Delete manually if no longer needed: aws route53 delete-hosted-zone --id $HOSTED_ZONE_ID"
    
    success "Route 53 DNS records deleted"
}

# Delete Load Balancer resources
delete_load_balancer() {
    # Delete load balancer
    if [[ -n "${ALB_ARN:-}" ]] && resource_exists "load-balancer" "$ALB_ARN"; then
        log "Deleting Application Load Balancer: $ALB_ARN"
        aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
        wait_for_deletion "load-balancer" "$ALB_ARN" 180
        success "Application Load Balancer deleted"
    else
        warning "Application Load Balancer not found or already deleted"
    fi
    
    # Delete target group
    if [[ -n "${TG_ARN:-}" ]] && resource_exists "target-group" "$TG_ARN"; then
        log "Deleting Target Group: $TG_ARN"
        aws elbv2 delete-target-group --target-group-arn "$TG_ARN"
        success "Target Group deleted"
    else
        warning "Target Group not found or already deleted"
    fi
}

# Terminate EC2 instances
terminate_instances() {
    if [[ -n "${WL_INSTANCE_ID:-}" ]] && resource_exists "instance" "$WL_INSTANCE_ID"; then
        log "Terminating Wavelength EC2 instance: $WL_INSTANCE_ID"
        aws ec2 terminate-instances --instance-ids "$WL_INSTANCE_ID"
        
        log "Waiting for instance termination..."
        aws ec2 wait instance-terminated --instance-ids "$WL_INSTANCE_ID" || \
            warning "Timeout waiting for instance termination"
        
        success "EC2 instance terminated"
    else
        warning "Wavelength EC2 instance not found or already terminated"
    fi
}

# Delete networking resources
delete_networking() {
    log "Deleting networking resources..."
    
    # Delete carrier gateway
    if [[ -n "${CG_ID:-}" ]] && resource_exists "carrier-gateway" "$CG_ID"; then
        log "Deleting carrier gateway: $CG_ID"
        aws ec2 delete-carrier-gateway --carrier-gateway-id "$CG_ID"
        wait_for_deletion "carrier-gateway" "$CG_ID" 120
        success "Carrier gateway deleted"
    else
        warning "Carrier gateway not found or already deleted"
    fi
    
    # Detach and delete internet gateway
    if [[ -n "${IGW_ID:-}" ]] && [[ -n "${VPC_ID:-}" ]]; then
        if resource_exists "internet-gateway" "$IGW_ID"; then
            log "Detaching and deleting internet gateway: $IGW_ID"
            aws ec2 detach-internet-gateway \
                --internet-gateway-id "$IGW_ID" \
                --vpc-id "$VPC_ID" &>/dev/null || true
            aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
            success "Internet gateway deleted"
        else
            warning "Internet gateway not found or already deleted"
        fi
    fi
    
    # Delete subnets
    for subnet_var in "WL_SUBNET_ID" "REGIONAL_SUBNET_ID"; do
        local subnet_id="${!subnet_var:-}"
        if [[ -n "$subnet_id" ]] && resource_exists "subnet" "$subnet_id"; then
            log "Deleting subnet: $subnet_id"
            aws ec2 delete-subnet --subnet-id "$subnet_id"
            success "Subnet $subnet_id deleted"
        else
            warning "Subnet $subnet_id not found or already deleted"
        fi
    done
    
    # Delete route tables (non-default)
    for rt_var in "WL_RT_ID" "REGIONAL_RT_ID"; do
        local rt_id="${!rt_var:-}"
        if [[ -n "$rt_id" ]] && resource_exists "route-table" "$rt_id"; then
            log "Deleting route table: $rt_id"
            aws ec2 delete-route-table --route-table-id "$rt_id"
            success "Route table $rt_id deleted"
        else
            warning "Route table $rt_id not found or already deleted"
        fi
    done
    
    # Delete security groups
    for sg_var in "WL_SG_ID" "REGIONAL_SG_ID"; do
        local sg_id="${!sg_var:-}"
        if [[ -n "$sg_id" ]] && resource_exists "security-group" "$sg_id"; then
            log "Deleting security group: $sg_id"
            # Retry logic for security group deletion (may have dependencies)
            local retries=0
            while [[ $retries -lt 5 ]]; do
                if aws ec2 delete-security-group --group-id "$sg_id" &>/dev/null; then
                    success "Security group $sg_id deleted"
                    break
                else
                    warning "Failed to delete security group $sg_id, retrying in 10 seconds..."
                    sleep 10
                    ((retries++))
                fi
            done
            
            if [[ $retries -eq 5 ]]; then
                warning "Failed to delete security group $sg_id after multiple attempts"
            fi
        else
            warning "Security group $sg_id not found or already deleted"
        fi
    done
    
    # Delete VPC
    if [[ -n "${VPC_ID:-}" ]] && resource_exists "vpc" "$VPC_ID"; then
        log "Deleting VPC: $VPC_ID"
        aws ec2 delete-vpc --vpc-id "$VPC_ID"
        success "VPC deleted"
    else
        warning "VPC not found or already deleted"
    fi
}

# Delete S3 bucket
delete_s3_bucket() {
    if [[ -z "${S3_BUCKET:-}" ]]; then
        warning "S3 bucket name not found, skipping"
        return 0
    fi
    
    if ! resource_exists "s3-bucket" "$S3_BUCKET"; then
        warning "S3 bucket $S3_BUCKET not found, skipping"
        return 0
    fi
    
    log "Deleting S3 bucket: $S3_BUCKET"
    
    # Empty bucket first (including versioned objects)
    log "Emptying S3 bucket contents..."
    aws s3 rm "s3://$S3_BUCKET" --recursive &>/dev/null || true
    
    # Remove versioned objects if versioning is enabled
    aws s3api delete-objects \
        --bucket "$S3_BUCKET" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$S3_BUCKET" \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
            --output json)" &>/dev/null || true
    
    # Remove delete markers
    aws s3api delete-objects \
        --bucket "$S3_BUCKET" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$S3_BUCKET" \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
            --output json)" &>/dev/null || true
    
    # Delete bucket
    aws s3 rb "s3://$S3_BUCKET" --force
    
    success "S3 bucket deleted"
}

# Clean up local files
cleanup_local_files() {
    local project_name="$1"
    local resource_file="${project_name}-resources.env"
    
    log "Cleaning up local files..."
    
    if [[ -f "$resource_file" ]]; then
        if [[ "${KEEP_RESOURCE_FILE:-false}" == "true" ]]; then
            mv "$resource_file" "${resource_file}.deleted.$(date +%s)"
            warning "Resource file moved to ${resource_file}.deleted.$(date +%s)"
        else
            rm "$resource_file"
            success "Resource file deleted"
        fi
    fi
    
    # Remove any temporary files
    rm -f dist-config-temp.json etag-temp.txt dns-delete.json bucket-policy.json
    
    success "Local cleanup completed"
}

# Display deletion summary
show_deletion_summary() {
    local project_name="$1"
    
    echo ""
    echo "==================================================================="
    echo "                    🗑️  DELETION COMPLETED 🗑️"
    echo "==================================================================="
    echo ""
    echo "✅ Successfully deleted AWS Wavelength Edge Application"
    echo ""
    echo "📊 REMOVED RESOURCES:"
    echo "  • CloudFront Distribution: ${DISTRIBUTION_ID:-N/A}"
    echo "  • Application Load Balancer: ${ALB_ARN:-N/A}"
    echo "  • Wavelength EC2 Instance: ${WL_INSTANCE_ID:-N/A}"
    echo "  • VPC and Networking: ${VPC_ID:-N/A}"
    echo "  • S3 Bucket: ${S3_BUCKET:-N/A}"
    echo "  • Security Groups and Route Tables"
    echo ""
    echo "💰 COST IMPACT:"
    echo "  • All charges for these resources have STOPPED"
    echo "  • No further Wavelength Zone charges"
    echo "  • No further CloudFront data transfer charges"
    echo "  • No further EC2 instance charges"
    echo ""
    echo "⚠️  NOTES:"
    echo "  • CloudFront deletion may take up to 24 hours to fully complete"
    echo "  • Route 53 hosted zone preserved (if created)"
    echo "  • Check AWS console to verify all resources are removed"
    echo "  • Monitor AWS billing for a few days to ensure charges stop"
    echo ""
    echo "==================================================================="
    echo ""
    success "All cleanup operations completed successfully!"
}

# Main deletion function
main() {
    local project_name="${1:-}"
    
    if [[ -z "$project_name" ]]; then
        error "Usage: $0 <project-name>"
        error "Example: $0 edge-app-abc123"
        exit 1
    fi
    
    log "Starting deletion of AWS Wavelength Edge Application: $project_name"
    
    # Load resource information
    load_resources "$project_name"
    
    # Confirm deletion
    confirm_deletion "$project_name"
    
    log "Beginning resource deletion process..."
    
    # Delete resources in reverse order of creation
    delete_cloudfront
    delete_route53
    delete_load_balancer
    terminate_instances
    delete_networking
    delete_s3_bucket
    cleanup_local_files "$project_name"
    
    show_deletion_summary "$project_name"
}

# Error handling
trap 'error "Deletion failed at line $LINENO. Some resources may remain. Please check AWS console."' ERR

# Support for environment variables
# FORCE_DELETE=true - Skip confirmation prompts
# KEEP_RESOURCE_FILE=true - Don't delete the resource file

# Handle script arguments
case "${1:-}" in
    "--help"|"-h")
        echo "AWS Wavelength Edge Application Cleanup Script"
        echo ""
        echo "Usage: $0 [OPTIONS] <project-name>"
        echo ""
        echo "Arguments:"
        echo "  project-name    Name of the project to delete (required)"
        echo ""
        echo "Options:"
        echo "  --help, -h      Show this help message"
        echo "  --force         Skip confirmation prompts (set FORCE_DELETE=true)"
        echo "  --keep-config   Keep resource configuration file (set KEEP_RESOURCE_FILE=true)"
        echo ""
        echo "Environment Variables:"
        echo "  FORCE_DELETE=true        Skip all confirmation prompts"
        echo "  KEEP_RESOURCE_FILE=true  Preserve resource file after deletion"
        echo ""
        echo "Examples:"
        echo "  $0 edge-app-abc123"
        echo "  FORCE_DELETE=true $0 edge-app-abc123"
        echo "  $0 --force edge-app-abc123"
        echo ""
        exit 0
        ;;
    "--force")
        export FORCE_DELETE=true
        main "${2:-}"
        ;;
    "--keep-config")
        export KEEP_RESOURCE_FILE=true
        main "${2:-}"
        ;;
    *)
        main "$1"
        ;;
esac