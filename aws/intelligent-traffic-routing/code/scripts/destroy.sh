#!/bin/bash

# Global Load Balancing with Route53 and CloudFront - Cleanup Script
# This script safely removes all resources created by the deployment script
# including CloudFront distributions, Route53 records, ALBs, and VPC infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Usage information
usage() {
    echo "Usage: $0 [DEPLOYMENT_STATE_DIR]"
    echo
    echo "This script destroys the global load balancing infrastructure."
    echo
    echo "Arguments:"
    echo "  DEPLOYMENT_STATE_DIR    Path to the deployment state directory"
    echo "                         (optional if running from same session)"
    echo
    echo "Examples:"
    echo "  $0 /tmp/global-lb-deployment-abc12345"
    echo "  $0  # Uses environment variables from current session"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Skip confirmation prompts"
    echo "  -d, --dry-run  Show what would be deleted without actually deleting"
    exit 1
}

# Parse command line arguments
FORCE_DELETE=false
DRY_RUN=false
DEPLOYMENT_STATE_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            if [[ -z "$DEPLOYMENT_STATE_DIR" ]]; then
                DEPLOYMENT_STATE_DIR="$1"
            else
                error "Too many arguments. Use --help for usage information."
            fi
            shift
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
    fi
    
    # Check required tools
    for tool in jq; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install $tool."
        fi
    done
    
    log "Prerequisites check completed successfully"
}

# Load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    # Try to find deployment state directory
    if [[ -z "$DEPLOYMENT_STATE_DIR" ]]; then
        if [[ -n "${DEPLOYMENT_STATE_DIR:-}" ]]; then
            # Use environment variable if available
            log "Using deployment state directory from environment: $DEPLOYMENT_STATE_DIR"
        else
            # Try to find the most recent deployment
            local recent_dir=$(find /tmp -maxdepth 1 -name "global-lb-deployment-*" -type d 2>/dev/null | sort | tail -n 1)
            if [[ -n "$recent_dir" ]]; then
                DEPLOYMENT_STATE_DIR="$recent_dir"
                warn "No deployment state directory specified, using most recent: $DEPLOYMENT_STATE_DIR"
            else
                error "No deployment state directory found. Please specify the path as an argument."
            fi
        fi
    fi
    
    # Verify deployment state directory exists
    if [[ ! -d "$DEPLOYMENT_STATE_DIR" ]]; then
        error "Deployment state directory not found: $DEPLOYMENT_STATE_DIR"
    fi
    
    # Load deployment configuration
    local config_file="$DEPLOYMENT_STATE_DIR/deployment-config.sh"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        log "Loaded deployment configuration from: $config_file"
    else
        error "Deployment configuration file not found: $config_file"
    fi
    
    # Load regional variables
    local vars_file="$DEPLOYMENT_STATE_DIR/regional-vars.sh"
    if [[ -f "$vars_file" ]]; then
        source "$vars_file"
        log "Loaded regional variables from: $vars_file"
    else
        warn "Regional variables file not found: $vars_file"
    fi
    
    # Verify essential variables are set
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        error "PROJECT_NAME not found in deployment configuration"
    fi
    
    log "Deployment configuration loaded for project: ${PROJECT_NAME}"
}

# Get user confirmation for deletion
get_confirmation() {
    if [[ "$FORCE_DELETE" == true ]]; then
        log "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        info "DRY RUN MODE - No resources will be actually deleted"
        return 0
    fi
    
    echo
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    info "This script will DELETE the following infrastructure:"
    info "• CloudFront distribution: ${CF_DISTRIBUTION_ID:-unknown}"
    info "• Route53 hosted zone: ${HOSTED_ZONE_ID:-unknown}"
    info "• Application Load Balancers in 3 regions"
    info "• Auto Scaling Groups and EC2 instances"
    info "• VPCs and networking infrastructure"
    info "• S3 bucket: ${S3_FALLBACK_BUCKET:-unknown}"
    info "• CloudWatch alarms and dashboards"
    info "• SNS topic: ${SNS_TOPIC_ARN:-unknown}"
    echo
    warn "This action CANNOT be undone!"
    echo
    read -p "Are you sure you want to delete all resources? Type 'DELETE' to confirm: " -r
    echo
    if [[ "$REPLY" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "This is your final confirmation. Type 'YES' to proceed: " -r
    echo
    if [[ "$REPLY" != "YES" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Execute or simulate command based on dry run mode
execute_command() {
    local description="$1"
    shift
    local cmd=("$@")
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] $description"
        info "[DRY RUN] Command: ${cmd[*]}"
    else
        log "$description"
        "${cmd[@]}" || warn "Command failed: ${cmd[*]}"
    fi
}

# Disable and delete CloudFront distribution
delete_cloudfront_distribution() {
    if [[ -z "${CF_DISTRIBUTION_ID:-}" ]]; then
        warn "CloudFront distribution ID not found, skipping CloudFront cleanup"
        return 0
    fi
    
    log "Deleting CloudFront distribution: ${CF_DISTRIBUTION_ID}"
    
    # Get current distribution config
    local dist_config_file="$DEPLOYMENT_STATE_DIR/current-dist-config.json"
    local etag_file="$DEPLOYMENT_STATE_DIR/current-etag.txt"
    
    if [[ "$DRY_RUN" == false ]]; then
        local dist_output=$(aws cloudfront get-distribution-config --id "${CF_DISTRIBUTION_ID}" 2>/dev/null || echo "")
        if [[ -n "$dist_output" ]]; then
            echo "$dist_output" | jq '.DistributionConfig' > "$dist_config_file"
            echo "$dist_output" | jq -r '.ETag' > "$etag_file"
            
            # Check if already disabled
            local enabled=$(jq -r '.Enabled' "$dist_config_file")
            if [[ "$enabled" == "true" ]]; then
                log "Disabling CloudFront distribution..."
                
                # Create disabled config
                jq '.Enabled = false' "$dist_config_file" > "$DEPLOYMENT_STATE_DIR/disabled-dist-config.json"
                
                # Update distribution to disable it
                aws cloudfront update-distribution \
                    --id "${CF_DISTRIBUTION_ID}" \
                    --distribution-config "file://$DEPLOYMENT_STATE_DIR/disabled-dist-config.json" \
                    --if-match "$(cat "$etag_file")"
                
                log "Waiting for CloudFront distribution to be disabled..."
                aws cloudfront wait distribution-deployed --id "${CF_DISTRIBUTION_ID}"
                
                # Get new ETag after disable
                local new_dist_output=$(aws cloudfront get-distribution --id "${CF_DISTRIBUTION_ID}")
                echo "$new_dist_output" | jq -r '.ETag' > "$etag_file"
            else
                log "CloudFront distribution is already disabled"
            fi
            
            # Delete the distribution
            execute_command "Deleting CloudFront distribution" \
                aws cloudfront delete-distribution \
                --id "${CF_DISTRIBUTION_ID}" \
                --if-match "$(cat "$etag_file")"
            
        else
            warn "CloudFront distribution ${CF_DISTRIBUTION_ID} not found or already deleted"
        fi
    else
        info "[DRY RUN] Would disable and delete CloudFront distribution: ${CF_DISTRIBUTION_ID}"
    fi
    
    log "CloudFront distribution cleanup completed"
}

# Delete Route53 resources
delete_route53_resources() {
    if [[ -z "${HOSTED_ZONE_ID:-}" ]]; then
        warn "Route53 hosted zone ID not found, skipping Route53 cleanup"
        return 0
    fi
    
    log "Deleting Route53 resources for hosted zone: ${HOSTED_ZONE_ID}"
    
    # Delete DNS records
    if [[ "$DRY_RUN" == false ]]; then
        # Get all CNAME records
        local records_file="$DEPLOYMENT_STATE_DIR/records-to-delete.json"
        aws route53 list-resource-record-sets \
            --hosted-zone-id "${HOSTED_ZONE_ID}" \
            --query 'ResourceRecordSets[?Type==`CNAME`]' > "$records_file" 2>/dev/null || echo "[]" > "$records_file"
        
        # Delete each CNAME record
        local record_count=$(jq length "$records_file")
        if [[ "$record_count" -gt 0 ]]; then
            log "Deleting $record_count DNS records..."
            jq -c '.[]' "$records_file" | while read -r record; do
                local record_name=$(echo "$record" | jq -r '.Name')
                log "Deleting DNS record: $record_name"
                
                local delete_batch_file="$DEPLOYMENT_STATE_DIR/delete-record-batch.json"
                echo "{\"Changes\": [{\"Action\": \"DELETE\", \"ResourceRecordSet\": $record}]}" > "$delete_batch_file"
                
                aws route53 change-resource-record-sets \
                    --hosted-zone-id "${HOSTED_ZONE_ID}" \
                    --change-batch "file://$delete_batch_file" || warn "Failed to delete record: $record_name"
            done
        else
            log "No CNAME records found to delete"
        fi
    else
        info "[DRY RUN] Would delete all CNAME records in hosted zone: ${HOSTED_ZONE_ID}"
    fi
    
    # Delete health checks
    for region_code in "10" "20" "30"; do
        local hc_var="HC_ID_${region_code}"
        if [[ -n "${!hc_var:-}" ]]; then
            execute_command "Deleting health check for region code ${region_code}" \
                aws route53 delete-health-check --health-check-id "${!hc_var}"
        fi
    done
    
    # Delete hosted zone
    execute_command "Deleting Route53 hosted zone" \
        aws route53 delete-hosted-zone --id "${HOSTED_ZONE_ID}"
    
    log "Route53 resources cleanup completed"
}

# Delete Auto Scaling Groups and Launch Templates
delete_compute_resources() {
    log "Deleting compute resources across all regions..."
    
    # Function to cleanup region compute resources
    cleanup_region_compute() {
        local region=$1
        local region_code=$2
        
        log "Cleaning up compute resources in ${region}..."
        
        local asg_name="${PROJECT_NAME}-asg-${region_code}"
        local lt_var="LT_ID_${region_code}"
        
        # Delete Auto Scaling Group
        if [[ "$DRY_RUN" == false ]]; then
            # Check if ASG exists
            if aws autoscaling describe-auto-scaling-groups \
                --region "${region}" \
                --auto-scaling-group-names "$asg_name" \
                --query 'AutoScalingGroups[0]' --output text 2>/dev/null | grep -q "None"; then
                log "Auto Scaling Group $asg_name not found in ${region}"
            else
                log "Deleting Auto Scaling Group in ${region}..."
                aws autoscaling delete-auto-scaling-group \
                    --region "${region}" \
                    --auto-scaling-group-name "$asg_name" \
                    --force-delete || warn "Failed to delete ASG in ${region}"
                
                # Wait for ASG deletion
                log "Waiting for ASG deletion in ${region}..."
                local wait_count=0
                while [[ $wait_count -lt 12 ]]; do  # Wait up to 6 minutes
                    if aws autoscaling describe-auto-scaling-groups \
                        --region "${region}" \
                        --auto-scaling-group-names "$asg_name" \
                        --query 'AutoScalingGroups[0]' --output text 2>/dev/null | grep -q "None"; then
                        log "ASG deleted successfully in ${region}"
                        break
                    fi
                    sleep 30
                    ((wait_count++))
                done
            fi
        else
            info "[DRY RUN] Would delete Auto Scaling Group: $asg_name in ${region}"
        fi
        
        # Delete Launch Template
        if [[ -n "${!lt_var:-}" ]]; then
            execute_command "Deleting launch template in ${region}" \
                aws ec2 delete-launch-template \
                --region "${region}" \
                --launch-template-id "${!lt_var}"
        fi
        
        log "Compute resources cleanup completed in ${region}"
    }
    
    # Cleanup all regions
    cleanup_region_compute "${PRIMARY_REGION}" "10"
    cleanup_region_compute "${SECONDARY_REGION}" "20"
    cleanup_region_compute "${TERTIARY_REGION}" "30"
    
    log "Compute resources cleanup completed across all regions"
}

# Delete Application Load Balancers
delete_alb_resources() {
    log "Deleting Application Load Balancers across all regions..."
    
    # Function to delete ALB resources in a region
    delete_alb_region() {
        local region=$1
        local region_code=$2
        local alb_arn_var="ALB_ARN_${region_code}"
        
        if [[ -n "${!alb_arn_var:-}" ]]; then
            log "Deleting ALB in ${region}..."
            
            if [[ "$DRY_RUN" == false ]]; then
                # Delete ALB (this will also delete associated target groups and listeners)
                aws elbv2 delete-load-balancer \
                    --region "${region}" \
                    --load-balancer-arn "${!alb_arn_var}" || warn "Failed to delete ALB in ${region}"
                
                log "ALB deletion initiated in ${region}"
            else
                info "[DRY RUN] Would delete ALB: ${!alb_arn_var} in ${region}"
            fi
        else
            warn "ALB ARN not found for region ${region}"
        fi
    }
    
    # Delete ALBs in all regions
    delete_alb_region "${PRIMARY_REGION}" "10"
    delete_alb_region "${SECONDARY_REGION}" "20"
    delete_alb_region "${TERTIARY_REGION}" "30"
    
    # Wait for ALBs to be deleted
    if [[ "$DRY_RUN" == false ]]; then
        log "Waiting for ALB deletion to complete..."
        sleep 120
    fi
    
    log "ALB resources cleanup completed"
}

# Delete VPC and networking resources
delete_vpc_resources() {
    log "Deleting VPC and networking resources across all regions..."
    
    # Function to delete VPC and associated resources
    delete_vpc_region() {
        local region=$1
        local region_code=$2
        
        log "Deleting VPC resources in ${region}..."
        
        local vpc_var="VPC_ID_${region_code}"
        local igw_var="IGW_ID_${region_code}"
        local rt_var="RT_ID_${region_code}"
        local subnet1_var="SUBNET1_ID_${region_code}"
        local subnet2_var="SUBNET2_ID_${region_code}"
        local sg_var="SG_ID_${region_code}"
        
        if [[ -z "${!vpc_var:-}" ]]; then
            warn "VPC ID not found for region ${region}, skipping"
            return 0
        fi
        
        local vpc_id="${!vpc_var}"
        
        if [[ "$DRY_RUN" == false ]]; then
            # Delete security groups (except default)
            log "Deleting security groups in ${region}..."
            if [[ -n "${!sg_var:-}" ]]; then
                aws ec2 delete-security-group \
                    --region "${region}" \
                    --group-id "${!sg_var}" || warn "Failed to delete security group in ${region}"
            fi
            
            # Find and delete any remaining non-default security groups
            aws ec2 describe-security-groups \
                --region "${region}" \
                --filters "Name=vpc-id,Values=${vpc_id}" \
                --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
                --output text | xargs -n1 -I {} aws ec2 delete-security-group \
                --region "${region}" --group-id {} 2>/dev/null || true
            
            # Delete subnets
            log "Deleting subnets in ${region}..."
            for subnet_var in "subnet1_var" "subnet2_var"; do
                if [[ -n "${!subnet_var:-}" ]]; then
                    aws ec2 delete-subnet \
                        --region "${region}" \
                        --subnet-id "${!subnet_var}" || warn "Failed to delete subnet ${!subnet_var}"
                fi
            done
            
            # Find and delete any remaining subnets
            aws ec2 describe-subnets \
                --region "${region}" \
                --filters "Name=vpc-id,Values=${vpc_id}" \
                --query 'Subnets[].SubnetId' \
                --output text | xargs -n1 -I {} aws ec2 delete-subnet \
                --region "${region}" --subnet-id {} 2>/dev/null || true
            
            # Delete route tables (except main)
            log "Deleting route tables in ${region}..."
            if [[ -n "${!rt_var:-}" ]]; then
                aws ec2 delete-route-table \
                    --region "${region}" \
                    --route-table-id "${!rt_var}" || warn "Failed to delete route table in ${region}"
            fi
            
            # Find and delete any remaining non-main route tables
            aws ec2 describe-route-tables \
                --region "${region}" \
                --filters "Name=vpc-id,Values=${vpc_id}" \
                --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
                --output text | xargs -n1 -I {} aws ec2 delete-route-table \
                --region "${region}" --route-table-id {} 2>/dev/null || true
            
            # Detach and delete internet gateway
            if [[ -n "${!igw_var:-}" ]]; then
                log "Detaching and deleting internet gateway in ${region}..."
                aws ec2 detach-internet-gateway \
                    --region "${region}" \
                    --internet-gateway-id "${!igw_var}" \
                    --vpc-id "${vpc_id}" || warn "Failed to detach IGW in ${region}"
                
                aws ec2 delete-internet-gateway \
                    --region "${region}" \
                    --internet-gateway-id "${!igw_var}" || warn "Failed to delete IGW in ${region}"
            fi
            
            # Find and delete any remaining internet gateways
            local remaining_igws=$(aws ec2 describe-internet-gateways \
                --region "${region}" \
                --filters "Name=attachment.vpc-id,Values=${vpc_id}" \
                --query 'InternetGateways[].InternetGatewayId' \
                --output text)
            
            for igw in $remaining_igws; do
                if [[ "$igw" != "None" && -n "$igw" ]]; then
                    aws ec2 detach-internet-gateway \
                        --region "${region}" \
                        --internet-gateway-id "$igw" \
                        --vpc-id "${vpc_id}" 2>/dev/null || true
                    
                    aws ec2 delete-internet-gateway \
                        --region "${region}" \
                        --internet-gateway-id "$igw" 2>/dev/null || true
                fi
            done
            
            # Delete VPC
            log "Deleting VPC in ${region}..."
            aws ec2 delete-vpc \
                --region "${region}" \
                --vpc-id "${vpc_id}" || warn "Failed to delete VPC in ${region}"
            
        else
            info "[DRY RUN] Would delete VPC and all associated resources in ${region}"
            info "[DRY RUN] VPC ID: ${vpc_id}"
        fi
        
        log "VPC resources cleanup completed in ${region}"
    }
    
    # Delete VPC resources in all regions
    delete_vpc_region "${PRIMARY_REGION}" "10"
    delete_vpc_region "${SECONDARY_REGION}" "20"
    delete_vpc_region "${TERTIARY_REGION}" "30"
    
    log "VPC resources cleanup completed across all regions"
}

# Delete CloudWatch and SNS resources
delete_monitoring_resources() {
    log "Deleting CloudWatch and SNS resources..."
    
    # Delete CloudWatch alarms
    local alarm_names=(
        "${PROJECT_NAME}-health-${PRIMARY_REGION}"
        "${PROJECT_NAME}-health-${SECONDARY_REGION}"
        "${PROJECT_NAME}-health-${TERTIARY_REGION}"
        "${PROJECT_NAME}-cloudfront-errors"
    )
    
    if [[ "$DRY_RUN" == false ]]; then
        # Check which alarms exist and delete them
        for alarm_name in "${alarm_names[@]}"; do
            if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "None"; then
                log "Alarm $alarm_name not found"
            else
                log "Deleting CloudWatch alarm: $alarm_name"
                aws cloudwatch delete-alarms --alarm-names "$alarm_name" || warn "Failed to delete alarm: $alarm_name"
            fi
        done
    else
        for alarm_name in "${alarm_names[@]}"; do
            info "[DRY RUN] Would delete CloudWatch alarm: $alarm_name"
        done
    fi
    
    # Delete CloudWatch dashboard
    local dashboard_name="Global-LoadBalancer-${PROJECT_NAME}"
    execute_command "Deleting CloudWatch dashboard" \
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
    
    # Delete SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        execute_command "Deleting SNS topic" \
            aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}"
    fi
    
    log "CloudWatch and SNS resources cleanup completed"
}

# Delete S3 resources
delete_s3_resources() {
    if [[ -z "${S3_FALLBACK_BUCKET:-}" ]]; then
        warn "S3 fallback bucket name not found, skipping S3 cleanup"
        return 0
    fi
    
    log "Deleting S3 resources..."
    
    if [[ "$DRY_RUN" == false ]]; then
        # Check if bucket exists
        if aws s3api head-bucket --bucket "${S3_FALLBACK_BUCKET}" 2>/dev/null; then
            log "Deleting S3 bucket contents: ${S3_FALLBACK_BUCKET}"
            aws s3 rm "s3://${S3_FALLBACK_BUCKET}" --recursive || warn "Failed to delete S3 bucket contents"
            
            log "Deleting S3 bucket: ${S3_FALLBACK_BUCKET}"
            aws s3 rb "s3://${S3_FALLBACK_BUCKET}" || warn "Failed to delete S3 bucket"
        else
            log "S3 bucket ${S3_FALLBACK_BUCKET} not found or already deleted"
        fi
    else
        info "[DRY RUN] Would delete S3 bucket and contents: ${S3_FALLBACK_BUCKET}"
    fi
    
    log "S3 resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == false ]]; then
        if [[ -d "$DEPLOYMENT_STATE_DIR" ]]; then
            log "Removing deployment state directory: $DEPLOYMENT_STATE_DIR"
            rm -rf "$DEPLOYMENT_STATE_DIR" || warn "Failed to remove deployment state directory"
        fi
    else
        info "[DRY RUN] Would remove deployment state directory: $DEPLOYMENT_STATE_DIR"
    fi
    
    log "Local files cleanup completed"
}

# Display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    
    echo
    echo "========================================"
    echo "🧹 GLOBAL LOAD BALANCING CLEANUP SUMMARY"
    echo "========================================"
    echo
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 DRY RUN COMPLETED"
        echo "   • No resources were actually deleted"
        echo "   • Review the log above to see what would be deleted"
        echo "   • Run without --dry-run flag to perform actual deletion"
    else
        echo "✅ RESOURCES DELETED:"
        echo "   • CloudFront distribution: ${CF_DISTRIBUTION_ID:-N/A}"
        echo "   • Route53 hosted zone: ${HOSTED_ZONE_ID:-N/A}"
        echo "   • Application Load Balancers in 3 regions"
        echo "   • Auto Scaling Groups and EC2 instances"
        echo "   • VPCs and networking infrastructure"
        echo "   • S3 bucket: ${S3_FALLBACK_BUCKET:-N/A}"
        echo "   • CloudWatch alarms and dashboards"
        echo "   • SNS topic: ${SNS_TOPIC_ARN:-N/A}"
        echo "   • Deployment state directory"
    fi
    
    echo
    echo "📋 Project Details:"
    echo "   • Project Name: ${PROJECT_NAME:-N/A}"
    echo "   • Domain Name: ${DOMAIN_NAME:-N/A}"
    echo
    
    if [[ "$DRY_RUN" == false ]]; then
        echo "⚠️  Important Notes:"
        echo "   • Some resources may take additional time to be fully removed"
        echo "   • CloudFront distribution deletion can take 15-20 minutes"
        echo "   • DNS records may take up to 48 hours to fully propagate"
        echo "   • Check AWS Console to verify all resources are deleted"
        echo "   • Monitor AWS billing to ensure no unexpected charges"
    fi
    
    echo
    echo "========================================"
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    log "Verifying cleanup completion..."
    
    local verification_issues=0
    
    # Check CloudFront distribution
    if [[ -n "${CF_DISTRIBUTION_ID:-}" ]]; then
        if aws cloudfront get-distribution --id "${CF_DISTRIBUTION_ID}" &>/dev/null; then
            warn "CloudFront distribution ${CF_DISTRIBUTION_ID} still exists (may take time to delete)"
            ((verification_issues++))
        fi
    fi
    
    # Check S3 bucket
    if [[ -n "${S3_FALLBACK_BUCKET:-}" ]]; then
        if aws s3api head-bucket --bucket "${S3_FALLBACK_BUCKET}" &>/dev/null; then
            warn "S3 bucket ${S3_FALLBACK_BUCKET} still exists"
            ((verification_issues++))
        fi
    fi
    
    # Check Route53 hosted zone
    if [[ -n "${HOSTED_ZONE_ID:-}" ]]; then
        if aws route53 get-hosted-zone --id "${HOSTED_ZONE_ID}" &>/dev/null; then
            warn "Route53 hosted zone ${HOSTED_ZONE_ID} still exists"
            ((verification_issues++))
        fi
    fi
    
    if [[ $verification_issues -eq 0 ]]; then
        log "Cleanup verification completed successfully"
    else
        warn "Cleanup verification found $verification_issues potential issues"
        warn "Some resources may still be in the process of deletion"
    fi
}

# Main cleanup function
main() {
    log "Starting Global Load Balancing cleanup..."
    
    # Run all cleanup steps in order
    check_prerequisites
    load_deployment_config
    get_confirmation
    
    # CloudFront must be deleted first (takes longest)
    delete_cloudfront_distribution
    
    # Delete DNS and health checks
    delete_route53_resources
    
    # Delete compute resources
    delete_compute_resources
    
    # Delete load balancers
    delete_alb_resources
    
    # Delete VPC and networking
    delete_vpc_resources
    
    # Delete monitoring and alerting
    delete_monitoring_resources
    
    # Delete S3 resources
    delete_s3_resources
    
    # Verify cleanup
    verify_cleanup
    
    # Clean up local files
    cleanup_local_files
    
    # Display summary
    display_cleanup_summary
    
    if [[ "$DRY_RUN" == false ]]; then
        log "Global Load Balancing cleanup completed successfully!"
    else
        log "Global Load Balancing cleanup dry run completed!"
    fi
}

# Handle script termination
trap 'error "Script interrupted"' INT TERM

# Run main function
main "$@"