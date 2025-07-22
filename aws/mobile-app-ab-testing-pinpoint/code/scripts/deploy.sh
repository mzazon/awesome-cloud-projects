#!/bin/bash
set -e

# =============================================================================
# Deploy Script for A/B Testing Mobile Apps with Amazon Pinpoint
# =============================================================================
# This script deploys the complete A/B testing infrastructure for mobile apps
# using Amazon Pinpoint, including campaigns, segments, analytics, and monitoring.
# =============================================================================

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    # Run cleanup if it exists
    if [ -f "./destroy.sh" ]; then
        ./destroy.sh --force
    fi
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Prerequisites Check
# =============================================================================

log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    log_warning "jq is not installed. Some JSON parsing may be limited."
fi

log_success "Prerequisites check completed"

# =============================================================================
# Environment Setup
# =============================================================================

log "Setting up environment variables..."

# Set AWS environment variables
export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    log_error "AWS region not configured. Please set your default region."
    exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export PINPOINT_PROJECT_NAME="mobile-ab-testing-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="pinpoint-analytics-${RANDOM_SUFFIX}"
export IAM_ROLE_NAME="PinpointAnalyticsRole-${RANDOM_SUFFIX}"
export KINESIS_STREAM_NAME="pinpoint-events-${RANDOM_SUFFIX}"
export DASHBOARD_NAME="Pinpoint-AB-Testing-${RANDOM_SUFFIX}"

# Create environment file for cleanup
cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PINPOINT_PROJECT_NAME=${PINPOINT_PROJECT_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME}
DASHBOARD_NAME=${DASHBOARD_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF

log_success "Environment variables configured"
log "Project Name: ${PINPOINT_PROJECT_NAME}"
log "S3 Bucket: ${S3_BUCKET_NAME}"
log "Region: ${AWS_REGION}"

# =============================================================================
# Create S3 Bucket for Analytics
# =============================================================================

log "Creating S3 bucket for analytics exports..."

# Check if bucket already exists
if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
    log_warning "S3 bucket ${S3_BUCKET_NAME} already exists"
else
    aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
    
    # Enable versioning for analytics data
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    log_success "S3 bucket created: ${S3_BUCKET_NAME}"
fi

# =============================================================================
# Create IAM Role for Pinpoint
# =============================================================================

log "Creating IAM role for Pinpoint analytics..."

# Create trust policy document
cat > trust-policy.json << EOF
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
if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
    log_warning "IAM role ${IAM_ROLE_NAME} already exists"
else
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json
    
    log_success "IAM role created: ${IAM_ROLE_NAME}"
fi

# Create and attach policy for S3 and Kinesis access
cat > pinpoint-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${S3_BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:PutRecord",
                "kinesis:PutRecords"
            ],
            "Resource": "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME}"
        }
    ]
}
EOF

# Create policy
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PinpointAnalyticsPolicy-${RANDOM_SUFFIX}"
if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
    log_warning "Policy already exists: ${POLICY_ARN}"
else
    aws iam create-policy \
        --policy-name "PinpointAnalyticsPolicy-${RANDOM_SUFFIX}" \
        --policy-document file://pinpoint-policy.json
    
    log_success "IAM policy created: ${POLICY_ARN}"
fi

# Attach policy to role
aws iam attach-role-policy \
    --role-name "${IAM_ROLE_NAME}" \
    --policy-arn "${POLICY_ARN}"

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text)
echo "ROLE_ARN=${ROLE_ARN}" >> .env

log_success "IAM role configured with necessary permissions"

# Clean up temporary files
rm -f trust-policy.json pinpoint-policy.json

# =============================================================================
# Create Kinesis Stream
# =============================================================================

log "Creating Kinesis stream for real-time event processing..."

# Check if stream exists
if aws kinesis describe-stream --stream-name "${KINESIS_STREAM_NAME}" &>/dev/null; then
    log_warning "Kinesis stream ${KINESIS_STREAM_NAME} already exists"
else
    aws kinesis create-stream \
        --stream-name "${KINESIS_STREAM_NAME}" \
        --shard-count 1
    
    log "Waiting for Kinesis stream to be active..."
    aws kinesis wait stream-exists --stream-name "${KINESIS_STREAM_NAME}"
    
    log_success "Kinesis stream created: ${KINESIS_STREAM_NAME}"
fi

# =============================================================================
# Create Pinpoint Application
# =============================================================================

log "Creating Amazon Pinpoint application..."

# Create Pinpoint application
PINPOINT_APP_ID=$(aws pinpoint create-app \
    --create-application-request Name="${PINPOINT_PROJECT_NAME}" \
    --query 'ApplicationResponse.Id' --output text)

echo "PINPOINT_APP_ID=${PINPOINT_APP_ID}" >> .env

log_success "Pinpoint application created with ID: ${PINPOINT_APP_ID}"

# Configure application settings
aws pinpoint update-application-settings \
    --application-id "${PINPOINT_APP_ID}" \
    --write-application-settings-request '{
        "CloudWatchMetricsEnabled": true,
        "EventTaggingEnabled": true,
        "Limits": {
            "Daily": 1000,
            "MaximumDuration": 86400,
            "MessagesPerSecond": 100,
            "Total": 10000
        }
    }'

log_success "Pinpoint application settings configured"

# =============================================================================
# Configure Event Stream
# =============================================================================

log "Configuring Pinpoint event stream..."

# Wait a moment for IAM propagation
sleep 10

aws pinpoint put-event-stream \
    --application-id "${PINPOINT_APP_ID}" \
    --write-event-stream "{
        \"DestinationStreamArn\": \"arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME}\",
        \"RoleArn\": \"${ROLE_ARN}\"
    }"

log_success "Event stream configured for real-time analytics"

# =============================================================================
# Create User Segments
# =============================================================================

log "Creating user segments for A/B testing..."

# Create active users segment
ACTIVE_USERS_SEGMENT=$(aws pinpoint create-segment \
    --application-id "${PINPOINT_APP_ID}" \
    --write-segment-request '{
        "Name": "ActiveUsers",
        "SegmentGroups": {
            "Groups": [
                {
                    "Type": "ALL",
                    "SourceType": "ALL",
                    "Dimensions": {
                        "Demographic": {
                            "AppVersion": {
                                "DimensionType": "INCLUSIVE",
                                "Values": ["1.0.0", "1.1.0", "1.2.0"]
                            }
                        }
                    }
                }
            ]
        }
    }' \
    --query 'SegmentResponse.Id' --output text)

echo "ACTIVE_USERS_SEGMENT=${ACTIVE_USERS_SEGMENT}" >> .env

log_success "Active users segment created: ${ACTIVE_USERS_SEGMENT}"

# Create high-value users segment
HIGH_VALUE_SEGMENT=$(aws pinpoint create-segment \
    --application-id "${PINPOINT_APP_ID}" \
    --write-segment-request '{
        "Name": "HighValueUsers",
        "SegmentGroups": {
            "Groups": [
                {
                    "Type": "ALL",
                    "SourceType": "ALL",
                    "Dimensions": {
                        "Behavior": {
                            "Recency": {
                                "Duration": "DAY_7",
                                "RecencyType": "ACTIVE"
                            }
                        },
                        "Metrics": {
                            "session_count": {
                                "ComparisonOperator": "GREATER_THAN",
                                "Value": 5.0
                            }
                        }
                    }
                }
            ]
        }
    }' \
    --query 'SegmentResponse.Id' --output text)

echo "HIGH_VALUE_SEGMENT=${HIGH_VALUE_SEGMENT}" >> .env

log_success "High-value users segment created: ${HIGH_VALUE_SEGMENT}"

# =============================================================================
# Create A/B Test Campaign
# =============================================================================

log "Creating A/B test campaign..."

# Create campaign configuration
cat > ab-test-campaign.json << EOF
{
    "Name": "Push Notification A/B Test",
    "Description": "Testing different push notification messages for user engagement",
    "Schedule": {
        "StartTime": "IMMEDIATE",
        "IsLocalTime": false,
        "Timezone": "UTC"
    },
    "SegmentId": "${ACTIVE_USERS_SEGMENT}",
    "MessageConfiguration": {
        "DefaultMessage": {
            "Body": "🎯 Control Message: Check out our new features!",
            "Title": "New Updates Available",
            "Action": "OPEN_APP"
        }
    },
    "AdditionalTreatments": [
        {
            "TreatmentName": "Personalized",
            "TreatmentDescription": "Personalized message variant",
            "SizePercent": 45,
            "MessageConfiguration": {
                "DefaultMessage": {
                    "Body": "🚀 Hi {{User.FirstName}}, discover features made just for you!",
                    "Title": "Personalized Updates",
                    "Action": "OPEN_APP"
                }
            }
        },
        {
            "TreatmentName": "Urgent",
            "TreatmentDescription": "Urgent tone message variant",
            "SizePercent": 45,
            "MessageConfiguration": {
                "DefaultMessage": {
                    "Body": "⚡ Don't miss out! Limited time features available now!",
                    "Title": "Limited Time Offer",
                    "Action": "OPEN_APP"
                }
            }
        }
    ],
    "HoldoutPercent": 10
}
EOF

# Create the campaign
CAMPAIGN_ID=$(aws pinpoint create-campaign \
    --application-id "${PINPOINT_APP_ID}" \
    --write-campaign-request file://ab-test-campaign.json \
    --query 'CampaignResponse.Id' --output text)

echo "CAMPAIGN_ID=${CAMPAIGN_ID}" >> .env

log_success "A/B test campaign created: ${CAMPAIGN_ID}"

# Clean up temporary file
rm -f ab-test-campaign.json

# =============================================================================
# Create CloudWatch Dashboard
# =============================================================================

log "Creating CloudWatch dashboard for monitoring..."

# Create dashboard configuration
cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Pinpoint", "DirectMessagesSent", "ApplicationId", "${PINPOINT_APP_ID}"],
                    [".", "DirectMessagesDelivered", ".", "."],
                    [".", "DirectMessagesBounced", ".", "."],
                    [".", "DirectMessagesOpened", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Campaign Delivery Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Pinpoint", "CustomEvents", "ApplicationId", "${PINPOINT_APP_ID}", "EventType", "conversion"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Conversion Events",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Kinesis", "IncomingRecords", "StreamName", "${KINESIS_STREAM_NAME}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Event Stream Activity",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        }
    ]
}
EOF

# Create the dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "${DASHBOARD_NAME}" \
    --dashboard-body file://dashboard-config.json

log_success "CloudWatch dashboard created: ${DASHBOARD_NAME}"

# Clean up temporary file
rm -f dashboard-config.json

# =============================================================================
# Create Test Endpoint
# =============================================================================

log "Creating test endpoint for validation..."

# Create test endpoint for validation
aws pinpoint update-endpoint \
    --application-id "${PINPOINT_APP_ID}" \
    --endpoint-id "test-endpoint-001" \
    --endpoint-request '{
        "Address": "test@example.com",
        "ChannelType": "EMAIL",
        "User": {
            "UserId": "test-user-001",
            "UserAttributes": {
                "FirstName": ["TestUser"],
                "LastName": ["Demo"]
            }
        },
        "Demographic": {
            "AppVersion": "1.0.0",
            "Platform": "iOS"
        }
    }'

log_success "Test endpoint created for validation"

# =============================================================================
# Create Winner Selection Lambda Function
# =============================================================================

log "Creating winner selection Lambda function template..."

# Create Lambda function code
cat > winner-selection-lambda.py << 'EOF'
import json
import boto3
from datetime import datetime, timedelta
import os

def lambda_handler(event, context):
    """
    Lambda function for automated A/B test winner selection
    """
    pinpoint = boto3.client('pinpoint')
    
    application_id = event.get('application_id') or os.environ.get('PINPOINT_APP_ID')
    campaign_id = event.get('campaign_id') or os.environ.get('CAMPAIGN_ID')
    
    if not application_id or not campaign_id:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Missing required parameters: application_id and campaign_id'
            })
        }
    
    try:
        # Get campaign analytics
        response = pinpoint.get_campaign_activities(
            ApplicationId=application_id,
            CampaignId=campaign_id
        )
        
        # Analyze conversion rates for each treatment
        activities = response.get('ActivitiesResponse', {}).get('Item', [])
        
        best_treatment = None
        best_conversion_rate = 0
        results = []
        
        for activity in activities:
            delivered = activity.get('DeliveredCount', 0)
            conversions = activity.get('ConversionsCount', 0)
            treatment_name = activity.get('TreatmentName', 'Control')
            
            if delivered > 0:
                conversion_rate = conversions / delivered
                results.append({
                    'treatment': treatment_name,
                    'delivered': delivered,
                    'conversions': conversions,
                    'conversion_rate': conversion_rate
                })
                
                if conversion_rate > best_conversion_rate:
                    best_conversion_rate = conversion_rate
                    best_treatment = treatment_name
        
        # Log results
        print(f"Campaign Analysis Results: {json.dumps(results, indent=2)}")
        print(f"Best performing treatment: {best_treatment}")
        print(f"Best conversion rate: {best_conversion_rate:.2%}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'best_treatment': best_treatment,
                'best_conversion_rate': best_conversion_rate,
                'all_results': results,
                'recommendation': f"Consider using '{best_treatment}' treatment for future campaigns"
            })
        }
        
    except Exception as e:
        print(f"Error analyzing campaign: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to analyze campaign: {str(e)}'
            })
        }
EOF

log_success "Winner selection Lambda function template created"

# =============================================================================
# Final Validation
# =============================================================================

log "Performing final validation..."

# Check campaign status
CAMPAIGN_STATUS=$(aws pinpoint get-campaign \
    --application-id "${PINPOINT_APP_ID}" \
    --campaign-id "${CAMPAIGN_ID}" \
    --query 'CampaignResponse.State.CampaignStatus' --output text)

log "Campaign status: ${CAMPAIGN_STATUS}"

# Check segments
ACTIVE_SEGMENT_SIZE=$(aws pinpoint get-segment \
    --application-id "${PINPOINT_APP_ID}" \
    --segment-id "${ACTIVE_USERS_SEGMENT}" \
    --query 'SegmentResponse.SegmentGroups.Groups[0].Dimensions' --output text)

log "Active users segment configured"

# Check S3 bucket
if aws s3 ls "s3://${S3_BUCKET_NAME}" &>/dev/null; then
    log_success "S3 bucket accessible"
else
    log_warning "S3 bucket not accessible"
fi

# =============================================================================
# Deployment Summary
# =============================================================================

log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
echo
echo "📊 A/B Testing Infrastructure Summary:"
echo "  • Pinpoint Application ID: ${PINPOINT_APP_ID}"
echo "  • Campaign ID: ${CAMPAIGN_ID}"
echo "  • Active Users Segment: ${ACTIVE_USERS_SEGMENT}"
echo "  • High-Value Users Segment: ${HIGH_VALUE_SEGMENT}"
echo "  • S3 Analytics Bucket: ${S3_BUCKET_NAME}"
echo "  • Kinesis Stream: ${KINESIS_STREAM_NAME}"
echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME}"
echo
echo "🔗 Quick Access Links:"
echo "  • Pinpoint Console: https://${AWS_REGION}.console.aws.amazon.com/pinpoint/home?region=${AWS_REGION}#/apps/${PINPOINT_APP_ID}"
echo "  • CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
echo "  • S3 Bucket: https://s3.console.aws.amazon.com/s3/buckets/${S3_BUCKET_NAME}"
echo
echo "⚡ Next Steps:"
echo "  1. Configure push notification channels (FCM/APNS) in the Pinpoint console"
echo "  2. Launch the A/B test campaign from the Pinpoint console"
echo "  3. Monitor results in the CloudWatch dashboard"
echo "  4. Use the winner-selection-lambda.py template for automated analysis"
echo
echo "📋 Configuration saved to .env file for cleanup"
echo "🧹 To clean up resources, run: ./destroy.sh"
echo
log_success "Deployment completed successfully!"