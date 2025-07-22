#!/bin/bash

# Deploy script for Mobile Push Notifications with Pinpoint
# This script creates the complete infrastructure for mobile push notifications

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
log "Starting Mobile Push Notifications with Pinpoint deployment"
log "Recipe: Pinpoint Mobile Push Notifications"
log "Estimated time: 120 minutes"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Get AWS account information
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    
    # Check required permissions
    log "Checking IAM permissions..."
    
    # Test Pinpoint access
    if ! aws pinpoint get-apps --region $AWS_REGION &> /dev/null; then
        error "Missing Pinpoint permissions. Please ensure you have full Pinpoint access."
        exit 1
    fi
    
    # Test IAM access
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        error "Missing IAM permissions. Please ensure you have IAM role creation permissions."
        exit 1
    fi
    
    # Test Kinesis access
    if ! aws kinesis list-streams --region $AWS_REGION &> /dev/null; then
        error "Missing Kinesis permissions. Please ensure you have Kinesis access."
        exit 1
    fi
    
    # Test CloudWatch access
    if ! aws cloudwatch list-metrics --region $AWS_REGION --max-records 1 &> /dev/null; then
        error "Missing CloudWatch permissions. Please ensure you have CloudWatch access."
        exit 1
    fi
    
    success "All prerequisites check passed"
}

# Create unique resource names
generate_resource_names() {
    log "Generating unique resource names..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Export resource names
    export AWS_REGION
    export AWS_ACCOUNT_ID
    export APP_NAME="ecommerce-mobile-app-${RANDOM_SUFFIX}"
    export SEGMENT_NAME="high-value-customers"
    export CAMPAIGN_NAME="flash-sale-notification"
    export PINPOINT_ROLE_NAME="PinpointServiceRole-${RANDOM_SUFFIX}"
    export KINESIS_STREAM_NAME="pinpoint-events-${RANDOM_SUFFIX}"
    export ALARM_NAME_PREFIX="Pinpoint-${RANDOM_SUFFIX}"
    
    log "Resource names generated:"
    log "  App Name: $APP_NAME"
    log "  IAM Role: $PINPOINT_ROLE_NAME"
    log "  Kinesis Stream: $KINESIS_STREAM_NAME"
    log "  Random Suffix: $RANDOM_SUFFIX"
}

# Create IAM role for Pinpoint
create_iam_role() {
    log "Creating IAM role for Pinpoint..."
    
    # Create trust policy document
    cat > /tmp/pinpoint-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "pinpoint.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$PINPOINT_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/pinpoint-trust-policy.json \
        --description "Service role for Amazon Pinpoint" || {
        warning "IAM role might already exist or creation failed"
    }
    
    # Attach basic policy to the role
    aws iam attach-role-policy \
        --role-name "$PINPOINT_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonPinpointServiceRole" || {
        warning "Policy attachment might have failed"
    }
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    export PINPOINT_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PINPOINT_ROLE_NAME}"
    
    success "IAM role created: $PINPOINT_ROLE_ARN"
    
    # Clean up temporary file
    rm -f /tmp/pinpoint-trust-policy.json
}

# Create Pinpoint application
create_pinpoint_application() {
    log "Creating Pinpoint application..."
    
    # Create the main Pinpoint application
    aws pinpoint create-app \
        --create-application-request Name="$APP_NAME" \
        --region $AWS_REGION || {
        warning "Pinpoint application might already exist"
    }
    
    # Store the application ID
    PINPOINT_APP_ID=$(aws pinpoint get-apps \
        --query "ApplicationsResponse.Item[?Name=='$APP_NAME'].Id" \
        --output text --region $AWS_REGION)
    
    if [ -z "$PINPOINT_APP_ID" ] || [ "$PINPOINT_APP_ID" = "None" ]; then
        error "Failed to create or retrieve Pinpoint application ID"
        exit 1
    fi
    
    export PINPOINT_APP_ID
    
    success "Pinpoint application created: $PINPOINT_APP_ID"
}

# Configure push notification channels
configure_channels() {
    log "Configuring push notification channels..."
    
    # Note: APNs and FCM configuration requires actual certificates/keys
    # This is a placeholder configuration that would need real credentials
    
    log "Configuring APNs channel for iOS..."
    warning "APNs channel configuration requires valid APNs certificates"
    warning "Please update the APNs configuration manually in the AWS Console"
    
    # Placeholder APNs channel configuration
    aws pinpoint update-apns-channel \
        --application-id $PINPOINT_APP_ID \
        --apns-channel-request \
        Enabled=false \
        --region $AWS_REGION 2>/dev/null || {
        warning "APNs channel configuration skipped - requires valid certificates"
    }
    
    log "Configuring FCM channel for Android..."
    warning "FCM channel configuration requires valid Firebase server key"
    warning "Please update the FCM configuration manually in the AWS Console"
    
    # Placeholder FCM channel configuration
    aws pinpoint update-gcm-channel \
        --application-id $PINPOINT_APP_ID \
        --gcm-channel-request \
        Enabled=false \
        --region $AWS_REGION 2>/dev/null || {
        warning "FCM channel configuration skipped - requires valid server key"
    }
    
    success "Channel configuration completed (manual setup required)"
}

# Create test user endpoints
create_test_endpoints() {
    log "Creating test user endpoints..."
    
    # Create iOS endpoint for testing
    aws pinpoint update-endpoint \
        --application-id $PINPOINT_APP_ID \
        --endpoint-id "ios-user-001" \
        --endpoint-request '{
            "ChannelType": "APNS",
            "Address": "device-token-ios-user-001-demo",
            "Attributes": {
                "PlatformType": ["iOS"],
                "AppVersion": ["1.0.0"]
            },
            "Demographic": {
                "Platform": "iOS",
                "PlatformVersion": "15.0"
            },
            "Location": {
                "Country": "US",
                "City": "Seattle"
            },
            "User": {
                "UserId": "user-001",
                "UserAttributes": {
                    "PurchaseHistory": ["high-value"],
                    "Category": ["electronics"]
                }
            }
        }' \
        --region $AWS_REGION
    
    # Create Android endpoint for testing
    aws pinpoint update-endpoint \
        --application-id $PINPOINT_APP_ID \
        --endpoint-id "android-user-002" \
        --endpoint-request '{
            "ChannelType": "GCM",
            "Address": "device-token-android-user-002-demo",
            "Attributes": {
                "PlatformType": ["Android"],
                "AppVersion": ["1.0.0"]
            },
            "Demographic": {
                "Platform": "Android",
                "PlatformVersion": "12.0"
            },
            "Location": {
                "Country": "US",
                "City": "San Francisco"
            },
            "User": {
                "UserId": "user-002",
                "UserAttributes": {
                    "PurchaseHistory": ["medium-value"],
                    "Category": ["clothing"]
                }
            }
        }' \
        --region $AWS_REGION
    
    success "Test user endpoints created"
}

# Create user segment
create_user_segment() {
    log "Creating user segment for high-value customers..."
    
    # Create segment for high-value customers
    aws pinpoint create-segment \
        --application-id $PINPOINT_APP_ID \
        --write-segment-request '{
            "Name": "'$SEGMENT_NAME'",
            "Dimensions": {
                "UserAttributes": {
                    "PurchaseHistory": {
                        "AttributeType": "INCLUSIVE",
                        "Values": ["high-value"]
                    }
                },
                "Demographic": {
                    "Platform": {
                        "DimensionType": "INCLUSIVE",
                        "Values": ["iOS", "Android"]
                    }
                }
            }
        }' \
        --region $AWS_REGION
    
    # Store segment ID
    sleep 5  # Wait for segment creation
    SEGMENT_ID=$(aws pinpoint get-segments \
        --application-id $PINPOINT_APP_ID \
        --query "SegmentsResponse.Item[?Name=='$SEGMENT_NAME'].Id" \
        --output text --region $AWS_REGION)
    
    if [ -z "$SEGMENT_ID" ] || [ "$SEGMENT_ID" = "None" ]; then
        error "Failed to create or retrieve segment ID"
        exit 1
    fi
    
    export SEGMENT_ID
    
    success "User segment created: $SEGMENT_ID"
}

# Create push notification template
create_push_template() {
    log "Creating push notification template..."
    
    # Create a reusable push notification template
    aws pinpoint create-push-template \
        --template-name "flash-sale-template" \
        --push-notification-template-request '{
            "ADM": {
                "Action": "OPEN_APP",
                "Body": "Don'\''t miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
                "Title": "🔥 Flash Sale Alert",
                "Sound": "default"
            },
            "APNS": {
                "Action": "OPEN_APP",
                "Body": "Don'\''t miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
                "Title": "🔥 Flash Sale Alert",
                "Sound": "default"
            },
            "GCM": {
                "Action": "OPEN_APP",
                "Body": "Don'\''t miss out! {{User.FirstName}}, exclusive flash sale ends in 2 hours!",
                "Title": "🔥 Flash Sale Alert",
                "Sound": "default"
            },
            "Default": {
                "Action": "OPEN_APP",
                "Body": "Don'\''t miss out! Exclusive flash sale ends in 2 hours!",
                "Title": "🔥 Flash Sale Alert"
            }
        }' \
        --region $AWS_REGION || {
        warning "Push template might already exist"
    }
    
    success "Push notification template created"
}

# Create push campaign
create_push_campaign() {
    log "Creating push notification campaign..."
    
    # Create a push notification campaign
    aws pinpoint create-campaign \
        --application-id $PINPOINT_APP_ID \
        --write-campaign-request '{
            "Name": "'$CAMPAIGN_NAME'",
            "Description": "Flash sale notification for high-value customers",
            "MessageConfiguration": {
                "APNSMessage": {
                    "Action": "OPEN_APP",
                    "Body": "Don'\''t miss out! Flash sale ends in 2 hours - Up to 50% off!",
                    "Title": "🔥 Flash Sale Alert",
                    "Sound": "default"
                },
                "GCMMessage": {
                    "Action": "OPEN_APP",
                    "Body": "Don'\''t miss out! Flash sale ends in 2 hours - Up to 50% off!",
                    "Title": "🔥 Flash Sale Alert",
                    "Sound": "default"
                },
                "DefaultMessage": {
                    "Body": "Don'\''t miss out! Flash sale ends in 2 hours - Up to 50% off!"
                }
            },
            "Schedule": {
                "IsLocalTime": true,
                "QuietTime": {
                    "Start": "22:00",
                    "End": "08:00"
                },
                "StartTime": "IMMEDIATE",
                "Timezone": "America/New_York"
            },
            "SegmentId": "'$SEGMENT_ID'",
            "SegmentVersion": 1
        }' \
        --region $AWS_REGION
    
    # Store campaign ID
    sleep 5  # Wait for campaign creation
    CAMPAIGN_ID=$(aws pinpoint get-campaigns \
        --application-id $PINPOINT_APP_ID \
        --query "CampaignsResponse.Item[?Name=='$CAMPAIGN_NAME'].Id" \
        --output text --region $AWS_REGION)
    
    if [ -z "$CAMPAIGN_ID" ] || [ "$CAMPAIGN_ID" = "None" ]; then
        error "Failed to create or retrieve campaign ID"
        exit 1
    fi
    
    export CAMPAIGN_ID
    
    success "Push campaign created: $CAMPAIGN_ID"
}

# Create Kinesis stream for event streaming
create_kinesis_stream() {
    log "Creating Kinesis stream for event analytics..."
    
    # Create Kinesis stream for Pinpoint events
    aws kinesis create-stream \
        --stream-name "$KINESIS_STREAM_NAME" \
        --shard-count 1 \
        --region $AWS_REGION || {
        warning "Kinesis stream might already exist"
    }
    
    # Wait for stream to be active
    log "Waiting for Kinesis stream to become active..."
    aws kinesis wait stream-exists \
        --stream-name "$KINESIS_STREAM_NAME" \
        --region $AWS_REGION
    
    success "Kinesis stream created: $KINESIS_STREAM_NAME"
}

# Configure event streaming
configure_event_streaming() {
    log "Configuring event streaming..."
    
    # Configure event streaming
    aws pinpoint put-event-stream \
        --application-id $PINPOINT_APP_ID \
        --write-event-stream '{
            "DestinationStreamArn": "arn:aws:kinesis:'$AWS_REGION':'$AWS_ACCOUNT_ID':stream/'$KINESIS_STREAM_NAME'",
            "RoleArn": "'$PINPOINT_ROLE_ARN'"
        }' \
        --region $AWS_REGION
    
    success "Event streaming configured"
}

# Set up CloudWatch monitoring
setup_cloudwatch_monitoring() {
    log "Setting up CloudWatch monitoring..."
    
    # Create CloudWatch alarm for failed push notifications
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ALARM_NAME_PREFIX}-PushFailures" \
        --alarm-description "Alert when push notification failures exceed threshold" \
        --metric-name "DirectSendMessagePermanentFailure" \
        --namespace "AWS/Pinpoint" \
        --statistic "Sum" \
        --period 300 \
        --threshold 5 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=ApplicationId,Value=$PINPOINT_APP_ID \
        --region $AWS_REGION
    
    # Create alarm for delivery rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ALARM_NAME_PREFIX}-DeliveryRate" \
        --alarm-description "Alert when delivery rate falls below 90%" \
        --metric-name "DirectSendMessageDeliveryRate" \
        --namespace "AWS/Pinpoint" \
        --statistic "Average" \
        --period 300 \
        --threshold 0.9 \
        --comparison-operator "LessThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=ApplicationId,Value=$PINPOINT_APP_ID \
        --region $AWS_REGION
    
    success "CloudWatch monitoring alarms created"
}

# Send test notification (optional)
send_test_notification() {
    log "Sending test push notification..."
    
    warning "Test notification requires valid device tokens in endpoints"
    
    # Send a direct test message to a specific endpoint
    aws pinpoint send-messages \
        --application-id $PINPOINT_APP_ID \
        --message-request '{
            "MessageConfiguration": {
                "APNSMessage": {
                    "Action": "OPEN_APP",
                    "Body": "Test notification - Your Pinpoint setup is working!",
                    "Title": "Test Push Notification",
                    "Sound": "default"
                },
                "GCMMessage": {
                    "Action": "OPEN_APP",
                    "Body": "Test notification - Your Pinpoint setup is working!",
                    "Title": "Test Push Notification",
                    "Sound": "default"
                }
            },
            "Endpoints": {
                "ios-user-001": {},
                "android-user-002": {}
            }
        }' \
        --region $AWS_REGION 2>/dev/null || {
        warning "Test notification failed - this is expected with demo device tokens"
    }
    
    log "Test notification attempted (check CloudWatch for delivery status)"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    cat > /tmp/pinpoint-deployment-info.json << EOF
{
    "deployment_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "pinpoint_app_id": "$PINPOINT_APP_ID",
    "pinpoint_app_name": "$APP_NAME",
    "segment_id": "$SEGMENT_ID",
    "segment_name": "$SEGMENT_NAME",
    "campaign_id": "$CAMPAIGN_ID",
    "campaign_name": "$CAMPAIGN_NAME",
    "iam_role_name": "$PINPOINT_ROLE_NAME",
    "iam_role_arn": "$PINPOINT_ROLE_ARN",
    "kinesis_stream_name": "$KINESIS_STREAM_NAME",
    "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    # Save to current directory
    cp /tmp/pinpoint-deployment-info.json ./pinpoint-deployment-info.json
    
    success "Deployment information saved to pinpoint-deployment-info.json"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Pinpoint Application ID: $PINPOINT_APP_ID"
    echo "Pinpoint Application Name: $APP_NAME"
    echo "Segment ID: $SEGMENT_ID"
    echo "Campaign ID: $CAMPAIGN_ID"
    echo "IAM Role: $PINPOINT_ROLE_NAME"
    echo "Kinesis Stream: $KINESIS_STREAM_NAME"
    echo "AWS Region: $AWS_REGION"
    echo ""
    warning "Next Steps:"
    echo "1. Configure APNs certificates in the AWS Console"
    echo "2. Configure FCM server key in the AWS Console"
    echo "3. Update mobile app with actual device tokens"
    echo "4. Test push notifications with real devices"
    echo ""
    success "Mobile Push Notifications with Pinpoint deployment completed!"
}

# Main execution
main() {
    check_prerequisites
    generate_resource_names
    create_iam_role
    create_pinpoint_application
    configure_channels
    create_test_endpoints
    create_user_segment
    create_push_template
    create_push_campaign
    create_kinesis_stream
    configure_event_streaming
    setup_cloudwatch_monitoring
    send_test_notification
    save_deployment_info
    print_summary
}

# Execute main function
main "$@"