#!/bin/bash

# IoT Security with Device Certificates and Policies - Cleanup Script
# This script removes all resources created by the IoT security deployment
# Exit on any error, treat undefined variables as errors
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
PROJECT_NAME=${PROJECT_NAME:-"iot-security-demo"}
THING_TYPE_NAME=${THING_TYPE_NAME:-"IndustrialSensor"}
DEVICE_PREFIX=${DEVICE_PREFIX:-"sensor"}
NUM_DEVICES=${NUM_DEVICES:-3}
FORCE_DELETE=${FORCE_DELETE:-false}

# Display header
echo "=============================================================="
echo "🧹 IoT Security Infrastructure Cleanup"
echo "=============================================================="
echo "Project Name: $PROJECT_NAME"
echo "Thing Type: $THING_TYPE_NAME"
echo "Device Prefix: $DEVICE_PREFIX"
echo "Number of Devices: $NUM_DEVICES"
echo "=============================================================="

# Confirmation prompt
confirm_deletion() {
    if [ "$FORCE_DELETE" != "true" ]; then
        echo ""
        warning "This will permanently delete ALL IoT security resources including:"
        echo "  • IoT Things and certificates"
        echo "  • IoT policies and security profiles"
        echo "  • DynamoDB table and all data"
        echo "  • CloudWatch dashboards and log groups"
        echo "  • EventBridge rules"
        echo "  • Local certificate files"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region set. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    success "Environment configured - Region: $AWS_REGION, Account: $AWS_ACCOUNT_ID"
}

# List resources before deletion
list_resources() {
    log "Listing resources to be deleted..."
    
    echo "Things to delete:"
    aws iot list-things --thing-type-name "$THING_TYPE_NAME" --query 'things[].thingName' --output table 2>/dev/null || echo "  No things found"
    
    echo ""
    echo "Policies to delete:"
    local policies=("RestrictiveSensorPolicy" "TimeBasedAccessPolicy" "LocationBasedAccessPolicy" "DeviceQuarantinePolicy")
    for policy in "${policies[@]}"; do
        if aws iot get-policy --policy-name "$policy" &>/dev/null; then
            echo "  • $policy"
        fi
    done
    
    echo ""
    echo "Security profiles to delete:"
    if aws iot describe-security-profile --security-profile-name "IndustrialSensorSecurity" &>/dev/null; then
        echo "  • IndustrialSensorSecurity"
    fi
    
    echo ""
    echo "Thing groups to delete:"
    if aws iot describe-thing-group --thing-group-name "IndustrialSensors" &>/dev/null; then
        echo "  • IndustrialSensors"
    fi
    
    echo ""
    echo "DynamoDB tables to delete:"
    if aws dynamodb describe-table --table-name "IoTSecurityEvents" &>/dev/null; then
        echo "  • IoTSecurityEvents"
    fi
    
    echo ""
}

# Clean up IoT devices and certificates
cleanup_iot_devices() {
    log "Cleaning up IoT devices and certificates..."
    
    # Get list of things
    local things=$(aws iot list-things --thing-type-name "$THING_TYPE_NAME" --query 'things[].thingName' --output text 2>/dev/null || echo "")
    
    if [ -n "$things" ]; then
        for thing_name in $things; do
            log "Processing device: $thing_name"
            
            # Get certificate ARN
            local cert_arns=$(aws iot list-thing-principals --thing-name "$thing_name" --query 'principals' --output text 2>/dev/null || echo "")
            
            for cert_arn in $cert_arns; do
                if [ -n "$cert_arn" ] && [ "$cert_arn" != "None" ]; then
                    local cert_id=$(echo "$cert_arn" | cut -d'/' -f2)
                    
                    # List and detach all policies from certificate
                    local attached_policies=$(aws iot list-attached-policies --target "$cert_arn" --query 'policies[].policyName' --output text 2>/dev/null || echo "")
                    
                    for policy in $attached_policies; do
                        if [ -n "$policy" ] && [ "$policy" != "None" ]; then
                            aws iot detach-policy --policy-name "$policy" --target "$cert_arn" 2>/dev/null || warning "Failed to detach policy $policy from certificate"
                        fi
                    done
                    
                    # Detach certificate from thing
                    aws iot detach-thing-principal --thing-name "$thing_name" --principal "$cert_arn" 2>/dev/null || warning "Failed to detach certificate from thing $thing_name"
                    
                    # Deactivate certificate
                    aws iot update-certificate --certificate-id "$cert_id" --new-status INACTIVE 2>/dev/null || warning "Failed to deactivate certificate $cert_id"
                    
                    # Delete certificate
                    aws iot delete-certificate --certificate-id "$cert_id" 2>/dev/null || warning "Failed to delete certificate $cert_id"
                    
                    success "Certificate $cert_id cleaned up"
                fi
            done
            
            # Remove thing from thing group
            aws iot remove-thing-from-thing-group --thing-group-name "IndustrialSensors" --thing-name "$thing_name" 2>/dev/null || warning "Failed to remove $thing_name from thing group"
            
            # Delete thing
            aws iot delete-thing --thing-name "$thing_name" 2>/dev/null || warning "Failed to delete thing $thing_name"
            
            success "Device $thing_name cleaned up"
        done
    else
        warning "No IoT things found to delete"
    fi
}

# Clean up Device Defender resources
cleanup_device_defender() {
    log "Cleaning up Device Defender resources..."
    
    # Detach security profile from thing group
    local target_arn="arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thinggroup/IndustrialSensors"
    
    if aws iot describe-security-profile --security-profile-name "IndustrialSensorSecurity" &>/dev/null; then
        aws iot detach-security-profile \
            --security-profile-name "IndustrialSensorSecurity" \
            --security-profile-target-arn "$target_arn" 2>/dev/null || warning "Failed to detach security profile"
        
        # Delete security profile
        aws iot delete-security-profile \
            --security-profile-name "IndustrialSensorSecurity" 2>/dev/null || warning "Failed to delete security profile"
        
        success "Security profile cleaned up"
    else
        warning "Security profile not found"
    fi
}

# Clean up thing group
cleanup_thing_group() {
    log "Cleaning up thing group..."
    
    if aws iot describe-thing-group --thing-group-name "IndustrialSensors" &>/dev/null; then
        # Remove any remaining things from group (safety check)
        local things_in_group=$(aws iot list-things-in-thing-group --thing-group-name "IndustrialSensors" --query 'things' --output text 2>/dev/null || echo "")
        
        for thing in $things_in_group; do
            if [ -n "$thing" ] && [ "$thing" != "None" ]; then
                aws iot remove-thing-from-thing-group --thing-group-name "IndustrialSensors" --thing-name "$thing" 2>/dev/null || warning "Failed to remove $thing from thing group"
            fi
        done
        
        # Delete thing group
        aws iot delete-thing-group --thing-group-name "IndustrialSensors" 2>/dev/null || warning "Failed to delete thing group"
        
        success "Thing group cleaned up"
    else
        warning "Thing group not found"
    fi
}

# Clean up IoT policies
cleanup_iot_policies() {
    log "Cleaning up IoT policies..."
    
    local policies=("RestrictiveSensorPolicy" "TimeBasedAccessPolicy" "LocationBasedAccessPolicy" "DeviceQuarantinePolicy")
    
    for policy in "${policies[@]}"; do
        if aws iot get-policy --policy-name "$policy" &>/dev/null; then
            # List and detach any remaining policy attachments
            local targets=$(aws iot list-targets-for-policy --policy-name "$policy" --query 'targets' --output text 2>/dev/null || echo "")
            
            for target in $targets; do
                if [ -n "$target" ] && [ "$target" != "None" ]; then
                    aws iot detach-policy --policy-name "$policy" --target "$target" 2>/dev/null || warning "Failed to detach policy $policy from $target"
                fi
            done
            
            # Delete policy
            aws iot delete-policy --policy-name "$policy" 2>/dev/null || warning "Failed to delete policy $policy"
            
            success "Policy $policy cleaned up"
        else
            warning "Policy $policy not found"
        fi
    done
}

# Clean up thing type
cleanup_thing_type() {
    log "Cleaning up thing type..."
    
    if aws iot describe-thing-type --thing-type-name "$THING_TYPE_NAME" &>/dev/null; then
        # Check if any things still use this type
        local things_with_type=$(aws iot list-things --thing-type-name "$THING_TYPE_NAME" --query 'things | length(@)' 2>/dev/null || echo "0")
        
        if [ "$things_with_type" -eq 0 ]; then
            # Deprecate first (required before deletion)
            aws iot deprecate-thing-type --thing-type-name "$THING_TYPE_NAME" 2>/dev/null || warning "Failed to deprecate thing type"
            
            # Delete thing type
            aws iot delete-thing-type --thing-type-name "$THING_TYPE_NAME" 2>/dev/null || warning "Failed to delete thing type"
            
            success "Thing type cleaned up"
        else
            warning "Cannot delete thing type - $things_with_type things still exist"
        fi
    else
        warning "Thing type not found"
    fi
}

# Clean up DynamoDB resources
cleanup_dynamodb() {
    log "Cleaning up DynamoDB resources..."
    
    if aws dynamodb describe-table --table-name "IoTSecurityEvents" &>/dev/null; then
        aws dynamodb delete-table --table-name "IoTSecurityEvents" 2>/dev/null || warning "Failed to delete DynamoDB table"
        
        log "Waiting for DynamoDB table deletion..."
        aws dynamodb wait table-not-exists --table-name "IoTSecurityEvents" 2>/dev/null || warning "Timeout waiting for table deletion"
        
        success "DynamoDB table cleaned up"
    else
        warning "DynamoDB table not found"
    fi
}

# Clean up CloudWatch resources
cleanup_cloudwatch() {
    log "Cleaning up CloudWatch resources..."
    
    # Delete dashboard
    if aws cloudwatch get-dashboard --dashboard-name "IoT-Security-Dashboard" &>/dev/null; then
        aws cloudwatch delete-dashboard --dashboard-name "IoT-Security-Dashboard" 2>/dev/null || warning "Failed to delete CloudWatch dashboard"
        success "CloudWatch dashboard cleaned up"
    else
        warning "CloudWatch dashboard not found"
    fi
    
    # Delete alarms
    local alarms=$(aws cloudwatch describe-alarms --alarm-name-prefix "IoT-" --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null || echo "")
    
    if [ -n "$alarms" ]; then
        for alarm in $alarms; do
            if [ -n "$alarm" ] && [ "$alarm" != "None" ]; then
                aws cloudwatch delete-alarms --alarm-names "$alarm" 2>/dev/null || warning "Failed to delete alarm $alarm"
                success "Alarm $alarm cleaned up"
            fi
        done
    else
        warning "No IoT-related alarms found"
    fi
    
    # Delete log group
    if aws logs describe-log-groups --log-group-name-prefix "/aws/iot/security-events" --query "logGroups[?logGroupName=='/aws/iot/security-events']" --output text | grep -q "/aws/iot/security-events"; then
        aws logs delete-log-group --log-group-name "/aws/iot/security-events" 2>/dev/null || warning "Failed to delete log group"
        success "CloudWatch log group cleaned up"
    else
        warning "CloudWatch log group not found"
    fi
}

# Clean up EventBridge resources
cleanup_eventbridge() {
    log "Cleaning up EventBridge resources..."
    
    if aws events describe-rule --name "IoT-Certificate-Rotation-Check" &>/dev/null; then
        # Remove targets first
        local targets=$(aws events list-targets-by-rule --rule "IoT-Certificate-Rotation-Check" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
        
        if [ -n "$targets" ]; then
            for target_id in $targets; do
                if [ -n "$target_id" ] && [ "$target_id" != "None" ]; then
                    aws events remove-targets --rule "IoT-Certificate-Rotation-Check" --ids "$target_id" 2>/dev/null || warning "Failed to remove target $target_id"
                fi
            done
        fi
        
        # Delete rule
        aws events delete-rule --name "IoT-Certificate-Rotation-Check" 2>/dev/null || warning "Failed to delete EventBridge rule"
        
        success "EventBridge rule cleaned up"
    else
        warning "EventBridge rule not found"
    fi
}

# Clean up IAM resources
cleanup_iam() {
    log "Cleaning up IAM resources..."
    
    if aws iam get-role --role-name "IoTLoggingRole" &>/dev/null; then
        read -p "Delete IoTLoggingRole? This may affect other IoT deployments (y/N): " -r
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Detach policies
            local attached_policies=$(aws iam list-attached-role-policies --role-name "IoTLoggingRole" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
                    aws iam detach-role-policy --role-name "IoTLoggingRole" --policy-arn "$policy_arn" 2>/dev/null || warning "Failed to detach policy $policy_arn"
                fi
            done
            
            # Delete role
            aws iam delete-role --role-name "IoTLoggingRole" 2>/dev/null || warning "Failed to delete IAM role"
            
            success "IAM role cleaned up"
        else
            warning "IAM role kept (user choice)"
        fi
    else
        warning "IAM role not found"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove certificate files
    if [ -d "./certificates" ]; then
        read -p "Delete local certificate files? This cannot be undone (y/N): " -r
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "./certificates"
            success "Certificate files deleted"
        else
            warning "Certificate files kept (user choice)"
        fi
    else
        warning "Certificate directory not found"
    fi
    
    # Remove log files
    if [ -d "./logs" ]; then
        read -p "Delete log files? (y/N): " -r
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "./logs"
            success "Log files deleted"
        else
            warning "Log files kept (user choice)"
        fi
    else
        warning "Log directory not found"
    fi
    
    # Remove temporary files
    rm -f /tmp/iot-*.json /tmp/*-policy.json 2>/dev/null || true
    
    success "Temporary files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local issues=0
    
    # Check things
    local remaining_things=$(aws iot list-things --thing-type-name "$THING_TYPE_NAME" --query 'things | length(@)' 2>/dev/null || echo "0")
    if [ "$remaining_things" -gt 0 ]; then
        warning "$remaining_things IoT things still exist"
        ((issues++))
    fi
    
    # Check policies
    local policies=("RestrictiveSensorPolicy" "TimeBasedAccessPolicy" "LocationBasedAccessPolicy" "DeviceQuarantinePolicy")
    for policy in "${policies[@]}"; do
        if aws iot get-policy --policy-name "$policy" &>/dev/null; then
            warning "Policy $policy still exists"
            ((issues++))
        fi
    done
    
    # Check security profile
    if aws iot describe-security-profile --security-profile-name "IndustrialSensorSecurity" &>/dev/null; then
        warning "Security profile still exists"
        ((issues++))
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "IoTSecurityEvents" &>/dev/null; then
        warning "DynamoDB table still exists"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        success "Cleanup validation completed - all resources removed"
    else
        warning "Cleanup completed with $issues remaining resources"
        echo "You may need to manually remove some resources or wait for eventual consistency"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    mkdir -p ./logs 2>/dev/null || true
    
    cat > ./logs/cleanup-summary.txt << EOF
===============================================
IoT Security Cleanup Summary
===============================================
Cleanup Date: $(date)
Project Name: $PROJECT_NAME
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID

Resources Removed:
- Thing Type: $THING_TYPE_NAME
- IoT Things: All devices with prefix $DEVICE_PREFIX
- Thing Group: IndustrialSensors
- IoT Policies: RestrictiveSensorPolicy, TimeBasedAccessPolicy, LocationBasedAccessPolicy, DeviceQuarantinePolicy
- Device Certificates: All X.509 certificates
- Security Profile: IndustrialSensorSecurity
- DynamoDB Table: IoTSecurityEvents
- CloudWatch Dashboard: IoT-Security-Dashboard
- CloudWatch Log Group: /aws/iot/security-events
- EventBridge Rule: IoT-Certificate-Rotation-Check

Manual Verification Recommended:
1. Check AWS IoT Console for any remaining resources
2. Verify CloudWatch for any remaining alarms or dashboards
3. Check billing for any ongoing charges
4. Review IAM roles if kept for other deployments

Cleanup completed at: $(date)
===============================================
EOF
    
    success "Cleanup summary saved to ./logs/cleanup-summary.txt"
}

# Main cleanup function
main() {
    log "Starting IoT Security infrastructure cleanup..."
    
    setup_environment
    list_resources
    confirm_deletion
    
    # Cleanup in reverse order of creation
    cleanup_device_defender
    cleanup_iot_devices
    cleanup_thing_group
    cleanup_iot_policies
    cleanup_thing_type
    cleanup_dynamodb
    cleanup_cloudwatch
    cleanup_eventbridge
    cleanup_iam
    cleanup_local_files
    
    validate_cleanup
    generate_cleanup_summary
    
    echo ""
    echo "=============================================================="
    success "🎉 IoT Security infrastructure cleanup completed!"
    echo "=============================================================="
    echo ""
    echo "📋 Summary:"
    echo "   • All IoT devices and certificates removed"
    echo "   • Security policies and profiles deleted"
    echo "   • Monitoring resources cleaned up"
    echo "   • Local files handled per user choice"
    echo ""
    echo "⚠️  Important Notes:"
    echo "   • Some resources may take time to fully delete (eventual consistency)"
    echo "   • Check AWS billing for any remaining charges"
    echo "   • Review IAM roles if shared with other deployments"
    echo ""
    echo "📁 Cleanup log:"
    echo "   • Summary: ./logs/cleanup-summary.txt"
    echo ""
    echo "=============================================================="
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --force                 Skip confirmation prompts"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_NAME           Project name prefix (default: iot-security-demo)"
        echo "  THING_TYPE_NAME        IoT Thing Type name (default: IndustrialSensor)"
        echo "  DEVICE_PREFIX          Device name prefix (default: sensor)"
        echo "  NUM_DEVICES            Number of devices to clean up (default: 3)"
        echo "  FORCE_DELETE           Skip confirmation prompts (default: false)"
        echo ""
        echo "Examples:"
        echo "  $0                     # Interactive cleanup"
        echo "  $0 --force             # Automated cleanup"
        echo "  FORCE_DELETE=true $0   # Automated cleanup via env var"
        exit 0
        ;;
    --force)
        FORCE_DELETE=true
        ;;
    *)
        if [ -n "${1:-}" ]; then
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
        fi
        ;;
esac

# Run main cleanup
main "$@"