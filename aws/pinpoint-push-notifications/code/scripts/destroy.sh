#!/bin/bash

# Destroy script for Mobile Push Notifications with Pinpoint
# This script removes all infrastructure created by the deploy script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script information
log "Starting Mobile Push Notifications with Pinpoint cleanup"
log "This will remove all resources created by the deploy script"

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Check if deployment info file exists
    if [ -f "./pinpoint-deployment-info.json" ]; then
        log "Found pinpoint-deployment-info.json, loading resource identifiers..."
        
        # Extract values from deployment info
        export AWS_REGION=$(cat ./pinpoint-deployment-info.json | grep -o '"aws_region": "[^"]*"' | cut -d'"' -f4)
        export AWS_ACCOUNT_ID=$(cat ./pinpoint-deployment-info.json | grep -o '"aws_account_id": "[^"]*"' | cut -d'"' -f4)
        export PINPOINT_APP_ID=$(cat ./pinpoint-deployment-info.json | grep -o '"pinpoint_app_id": "[^"]*"' | cut -d'"' -f4)
        export APP_NAME=$(cat ./pinpoint-deployment-info.json | grep -o '"pinpoint_app_name": "[^"]*"' | cut -d'"' -f4)
        export SEGMENT_ID=$(cat ./pinpoint-deployment-info.json | grep -o '"segment_id": "[^"]*"' | cut -d'"' -f4)
        export SEGMENT_NAME=$(cat ./pinpoint-deployment-info.json | grep -o '"segment_name": "[^"]*"' | cut -d'"' -f4)
        export CAMPAIGN_ID=$(cat ./pinpoint-deployment-info.json | grep -o '"campaign_id": "[^"]*"' | cut -d'"' -f4)
        export CAMPAIGN_NAME=$(cat ./pinpoint-deployment-info.json | grep -o '"campaign_name": "[^"]*"' | cut -d'"' -f4)
        export PINPOINT_ROLE_NAME=$(cat ./pinpoint-deployment-info.json | grep -o '"iam_role_name": "[^"]*"' | cut -d'"' -f4)
        export KINESIS_STREAM_NAME=$(cat ./pinpoint-deployment-info.json | grep -o '"kinesis_stream_name": "[^"]*"' | cut -d'"' -f4)
        export RANDOM_SUFFIX=$(cat ./pinpoint-deployment-info.json | grep -o '"random_suffix": "[^"]*"' | cut -d'"' -f4)
        
        success "Deployment information loaded successfully"
    else
        warning "No deployment info file found. Will attempt to detect resources..."
        # Get AWS account information
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
        
        if [ -z "$AWS_REGION" ]; then
            error "AWS region not configured and no deployment info found."
            error "Please ensure AWS CLI is configured or provide region manually."
            exit 1
        fi
        
        export AWS_REGION
        export AWS_ACCOUNT_ID
    fi
}

# Interactive resource selection if deployment info not available
interactive_resource_selection() {
    if [ -z "$PINPOINT_APP_ID" ]; then
        log "Searching for Pinpoint applications..."
        
        # List existing Pinpoint applications
        APPS_JSON=$(aws pinpoint get-apps --region $AWS_REGION 2>/dev/null || echo '{"ApplicationsResponse":{"Item":[]}}')
        
        # Check if jq is available for better JSON parsing
        if command -v jq &> /dev/null; then
            APP_COUNT=$(echo "$APPS_JSON" | jq '.ApplicationsResponse.Item | length')
            
            if [ "$APP_COUNT" -gt 0 ]; then
                log "Found $APP_COUNT Pinpoint application(s):"
                echo "$APPS_JSON" | jq -r '.ApplicationsResponse.Item[] | "\(.Id) - \(.Name)"'
                
                echo ""
                read -p "Enter the Application ID to delete (or 'all' to delete all): " USER_INPUT
                
                if [ "$USER_INPUT" = "all" ]; then
                    PINPOINT_APP_IDS=($(echo "$APPS_JSON" | jq -r '.ApplicationsResponse.Item[].Id'))
                else
                    PINPOINT_APP_IDS=("$USER_INPUT")
                fi
            else
                warning "No Pinpoint applications found"
                PINPOINT_APP_IDS=()
            fi
        else
            warning "jq not available. Please install jq for better JSON parsing or provide deployment info file."
            PINPOINT_APP_IDS=()
        fi
    else
        PINPOINT_APP_IDS=("$PINPOINT_APP_ID")
    fi
}

# Confirmation prompt
confirm_deletion() {
    log "Resources to be deleted:"
    echo "========================"
    
    if [ ${#PINPOINT_APP_IDS[@]} -gt 0 ]; then
        echo "Pinpoint Applications:"
        for app_id in "${PINPOINT_APP_IDS[@]}"; do
            echo "  - $app_id"
        done
    fi
    
    if [ -n "$PINPOINT_ROLE_NAME" ]; then
        echo "IAM Role: $PINPOINT_ROLE_NAME"
    fi
    
    if [ -n "$KINESIS_STREAM_NAME" ]; then
        echo "Kinesis Stream: $KINESIS_STREAM_NAME"
    fi
    
    if [ -n "$RANDOM_SUFFIX" ]; then
        echo "CloudWatch Alarms: Pinpoint-${RANDOM_SUFFIX}-*"
    fi
    
    echo ""
    warning "This action cannot be undone!"
    
    read -p "Are you sure you want to delete these resources? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource deletion..."
}

# Delete campaigns and segments for a specific app
delete_campaigns_and_segments() {
    local app_id=$1
    
    log "Deleting campaigns and segments for app: $app_id"
    
    # Delete campaigns
    log "Deleting campaigns..."
    if [ -n "$CAMPAIGN_ID" ]; then
        aws pinpoint delete-campaign \
            --application-id $app_id \
            --campaign-id $CAMPAIGN_ID \
            --region $AWS_REGION 2>/dev/null || {
            warning "Campaign $CAMPAIGN_ID not found or already deleted"
        }
    else
        # Try to find and delete all campaigns for this app
        CAMPAIGNS_JSON=$(aws pinpoint get-campaigns \
            --application-id $app_id \
            --region $AWS_REGION 2>/dev/null || echo '{"CampaignsResponse":{"Item":[]}}')
        
        if command -v jq &> /dev/null; then
            CAMPAIGN_IDS=($(echo "$CAMPAIGNS_JSON" | jq -r '.CampaignsResponse.Item[].Id' 2>/dev/null || echo ""))
            
            for campaign_id in "${CAMPAIGN_IDS[@]}"; do
                if [ -n "$campaign_id" ] && [ "$campaign_id" != "null" ]; then
                    aws pinpoint delete-campaign \
                        --application-id $app_id \
                        --campaign-id $campaign_id \
                        --region $AWS_REGION 2>/dev/null || {
                        warning "Failed to delete campaign: $campaign_id"
                    }
                    log "Deleted campaign: $campaign_id"
                fi
            done
        fi
    fi
    
    # Delete segments
    log "Deleting segments..."
    if [ -n "$SEGMENT_ID" ]; then
        aws pinpoint delete-segment \
            --application-id $app_id \
            --segment-id $SEGMENT_ID \
            --region $AWS_REGION 2>/dev/null || {
            warning "Segment $SEGMENT_ID not found or already deleted"
        }
    else
        # Try to find and delete all segments for this app
        SEGMENTS_JSON=$(aws pinpoint get-segments \
            --application-id $app_id \
            --region $AWS_REGION 2>/dev/null || echo '{"SegmentsResponse":{"Item":[]}}')
        
        if command -v jq &> /dev/null; then
            SEGMENT_IDS=($(echo "$SEGMENTS_JSON" | jq -r '.SegmentsResponse.Item[].Id' 2>/dev/null || echo ""))
            
            for segment_id in "${SEGMENT_IDS[@]}"; do
                if [ -n "$segment_id" ] && [ "$segment_id" != "null" ]; then
                    aws pinpoint delete-segment \
                        --application-id $app_id \
                        --segment-id $segment_id \
                        --region $AWS_REGION 2>/dev/null || {
                        warning "Failed to delete segment: $segment_id"
                    }
                    log "Deleted segment: $segment_id"
                fi
            done
        fi
    fi
    
    success "Campaigns and segments deleted for app: $app_id"
}

# Delete push templates
delete_push_templates() {
    log "Deleting push notification templates..."
    
    # Delete specific template if we know the name
    aws pinpoint delete-push-template \
        --template-name "flash-sale-template" \
        --region $AWS_REGION 2>/dev/null || {
        warning "Template 'flash-sale-template' not found or already deleted"
    }
    
    success "Push notification templates deleted"
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch monitoring alarms..."
    
    if [ -n "$RANDOM_SUFFIX" ]; then
        # Delete alarms with known names
        aws cloudwatch delete-alarms \
            --alarm-names "Pinpoint-${RANDOM_SUFFIX}-PushFailures" \
                         "Pinpoint-${RANDOM_SUFFIX}-DeliveryRate" \
            --region $AWS_REGION 2>/dev/null || {
            warning "Some CloudWatch alarms not found or already deleted"
        }
    else
        # Try to find Pinpoint-related alarms
        log "Searching for Pinpoint-related alarms..."
        ALARMS=$(aws cloudwatch describe-alarms \
            --region $AWS_REGION \
            --query "MetricAlarms[?Namespace=='AWS/Pinpoint'].AlarmName" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$ALARMS" ]; then
            aws cloudwatch delete-alarms \
                --alarm-names $ALARMS \
                --region $AWS_REGION 2>/dev/null || {
                warning "Failed to delete some CloudWatch alarms"
            }
        fi
    fi
    
    success "CloudWatch alarms deleted"
}

# Delete event streaming and Kinesis
delete_event_streaming() {
    log "Deleting event streaming configuration..."
    
    # Delete event streaming for each app
    for app_id in "${PINPOINT_APP_IDS[@]}"; do
        if [ -n "$app_id" ]; then
            aws pinpoint delete-event-stream \
                --application-id $app_id \
                --region $AWS_REGION 2>/dev/null || {
                warning "Event stream for app $app_id not found or already deleted"
            }
        fi
    done
    
    # Delete Kinesis stream
    if [ -n "$KINESIS_STREAM_NAME" ]; then
        log "Deleting Kinesis stream: $KINESIS_STREAM_NAME"
        aws kinesis delete-stream \
            --stream-name "$KINESIS_STREAM_NAME" \
            --region $AWS_REGION 2>/dev/null || {
            warning "Kinesis stream $KINESIS_STREAM_NAME not found or already deleted"
        }
    else
        # Try to find Pinpoint-related streams
        log "Searching for Pinpoint-related Kinesis streams..."
        STREAMS=$(aws kinesis list-streams \
            --region $AWS_REGION \
            --query "StreamNames[?contains(@, 'pinpoint-events')]" \
            --output text 2>/dev/null || echo "")
        
        for stream in $STREAMS; do
            if [ -n "$stream" ]; then
                log "Deleting Kinesis stream: $stream"
                aws kinesis delete-stream \
                    --stream-name "$stream" \
                    --region $AWS_REGION 2>/dev/null || {
                    warning "Failed to delete Kinesis stream: $stream"
                }
            fi
        done
    fi
    
    success "Event streaming resources deleted"
}

# Delete Pinpoint applications
delete_pinpoint_applications() {
    log "Deleting Pinpoint applications..."
    
    for app_id in "${PINPOINT_APP_IDS[@]}"; do
        if [ -n "$app_id" ]; then
            log "Deleting Pinpoint application: $app_id"
            
            # First delete campaigns and segments
            delete_campaigns_and_segments $app_id
            
            # Wait a moment for cleanup
            sleep 2
            
            # Delete the application
            aws pinpoint delete-app \
                --application-id $app_id \
                --region $AWS_REGION 2>/dev/null || {
                warning "Pinpoint application $app_id not found or already deleted"
            }
            
            success "Pinpoint application deleted: $app_id"
        fi
    done
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [ -n "$PINPOINT_ROLE_NAME" ]; then
        # Detach policies from the role
        aws iam detach-role-policy \
            --role-name "$PINPOINT_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonPinpointServiceRole" \
            2>/dev/null || {
            warning "Policy detachment failed or already detached"
        }
        
        # Delete the IAM role
        aws iam delete-role \
            --role-name "$PINPOINT_ROLE_NAME" \
            2>/dev/null || {
            warning "IAM role $PINPOINT_ROLE_NAME not found or already deleted"
        }
        
        success "IAM role deleted: $PINPOINT_ROLE_NAME"
    else
        # Try to find Pinpoint-related roles
        log "Searching for Pinpoint-related IAM roles..."
        ROLES=$(aws iam list-roles \
            --query "Roles[?contains(RoleName, 'PinpointServiceRole')].RoleName" \
            --output text 2>/dev/null || echo "")
        
        for role in $ROLES; do
            if [ -n "$role" ]; then
                log "Found Pinpoint role: $role"
                read -p "Delete role $role? (yes/no): " DELETE_ROLE
                
                if [ "$DELETE_ROLE" = "yes" ]; then
                    # Detach policies
                    aws iam detach-role-policy \
                        --role-name "$role" \
                        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonPinpointServiceRole" \
                        2>/dev/null || true
                    
                    # Delete role
                    aws iam delete-role \
                        --role-name "$role" \
                        2>/dev/null || {
                        warning "Failed to delete IAM role: $role"
                    }
                    
                    success "IAM role deleted: $role"
                fi
            fi
        done
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "./pinpoint-deployment-info.json" ]; then
        rm -f ./pinpoint-deployment-info.json
        success "Removed pinpoint-deployment-info.json"
    fi
    
    # Clean up any temporary files
    rm -f /tmp/pinpoint-*
    
    success "Local cleanup completed"
}

# Verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Check if any Pinpoint apps remain
    REMAINING_APPS=$(aws pinpoint get-apps \
        --region $AWS_REGION \
        --query "ApplicationsResponse.Item | length(@)" \
        --output text 2>/dev/null || echo "0")
    
    log "Remaining Pinpoint applications: $REMAINING_APPS"
    
    # Check for remaining Kinesis streams
    REMAINING_STREAMS=$(aws kinesis list-streams \
        --region $AWS_REGION \
        --query "StreamNames[?contains(@, 'pinpoint-events')] | length(@)" \
        --output text 2>/dev/null || echo "0")
    
    log "Remaining Pinpoint-related Kinesis streams: $REMAINING_STREAMS"
    
    success "Deletion verification completed"
}

# Print cleanup summary
print_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been deleted:"
    echo "- Pinpoint applications and their components"
    echo "- Push notification templates"
    echo "- User segments and campaigns"
    echo "- CloudWatch monitoring alarms"
    echo "- Kinesis event streams"
    echo "- IAM service roles"
    echo "- Local deployment files"
    echo ""
    warning "Note: Some resources may take a few minutes to be fully removed from AWS"
    success "Mobile Push Notifications with Pinpoint cleanup completed!"
}

# Main execution
main() {
    load_deployment_info
    interactive_resource_selection
    confirm_deletion
    delete_push_templates
    delete_cloudwatch_alarms
    delete_event_streaming
    delete_pinpoint_applications
    delete_iam_resources
    cleanup_local_files
    verify_deletion
    print_cleanup_summary
}

# Execute main function
main "$@"