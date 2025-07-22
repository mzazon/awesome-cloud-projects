# Terraform Infrastructure for A/B Testing Mobile Apps with Amazon Pinpoint

This Terraform configuration deploys a comprehensive A/B testing infrastructure for mobile applications using Amazon Pinpoint, enabling sophisticated campaign management, real-time analytics, and automated winner selection.

## Architecture Overview

The infrastructure includes:

- **Amazon Pinpoint Application**: Central hub for campaign management and analytics
- **Push Notification Channels**: GCM/FCM for Android and APNS for iOS
- **User Segmentation**: Active users and high-value user segments
- **Analytics Export**: S3 bucket for long-term analytics storage
- **Real-time Processing**: Kinesis stream for event processing
- **Monitoring**: CloudWatch dashboard for campaign metrics
- **Automation**: Lambda function for automated winner selection

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - Amazon Pinpoint
  - IAM roles and policies
  - S3 buckets
  - Kinesis streams
  - Lambda functions
  - CloudWatch dashboards

## Mobile App Credentials

For push notifications to work, you'll need to obtain:

### Android (GCM/FCM)
- Firebase server key from your Firebase project console
- Configure the `firebase_server_key` variable

### iOS (APNS)
- Apple Push Notification certificate and private key
- Bundle ID, Team ID, and Key ID from Apple Developer account
- Configure the APNS-related variables

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Configure Variables**:
   ```bash
   # Copy example variables file
   cp terraform.tfvars.example terraform.tfvars
   
   # Edit with your specific values
   vim terraform.tfvars
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

6. **Get Outputs**:
   ```bash
   terraform output
   ```

## Configuration Options

### Basic Configuration

```hcl
# terraform.tfvars
aws_region = "us-east-1"
environment = "dev"
project_name = "my-mobile-ab-testing"
```

### Push Notification Configuration

```hcl
# Android
firebase_server_key = "your-firebase-server-key"

# iOS
apns_certificate = "base64-encoded-certificate"
apns_private_key = "base64-encoded-private-key"
apns_bundle_id = "com.yourcompany.yourapp"
apns_team_id = "your-team-id"
apns_key_id = "your-key-id"
enable_apns_sandbox = true  # Set to false for production
```

### Campaign Configuration

```hcl
campaign_name = "My A/B Test Campaign"
campaign_description = "Testing message variations"
holdout_percentage = 10
treatment_percentage = 45

# Message content
control_message_title = "New Updates Available"
control_message_body = "Check out our new features!"
personalized_message_title = "Personalized Updates"
personalized_message_body = "Hi {{User.FirstName}}, discover features made just for you!"
urgent_message_title = "Limited Time Offer"
urgent_message_body = "Don't miss out! Limited time features available now!"
```

### Advanced Configuration

```hcl
# Analytics and monitoring
enable_analytics_export = true
enable_event_stream = true
create_cloudwatch_dashboard = true
create_winner_selection_lambda = true

# Kinesis configuration
kinesis_shard_count = 1
kinesis_retention_period = 24

# Segment configuration
app_versions = ["1.0.0", "1.1.0", "1.2.0"]
high_value_session_threshold = 5
high_value_recency_days = 7

# Campaign limits
campaign_daily_limit = 1000
campaign_total_limit = 10000
campaign_messages_per_second = 100
```

## Key Resources Created

| Resource | Purpose | Notes |
|----------|---------|--------|
| `aws_pinpoint_app` | Main application container | Central hub for all campaigns |
| `aws_pinpoint_segment` | User segmentation | Active users and high-value segments |
| `aws_pinpoint_gcm_channel` | Android push notifications | Requires Firebase server key |
| `aws_pinpoint_apns_channel` | iOS push notifications | Requires APNS certificate |
| `aws_s3_bucket` | Analytics export storage | Long-term analytics data |
| `aws_kinesis_stream` | Real-time event processing | Streams user interactions |
| `aws_lambda_function` | Automated winner selection | Analyzes campaign performance |
| `aws_cloudwatch_dashboard` | Monitoring and visualization | Real-time campaign metrics |

## Mobile App Integration

After deployment, integrate the Pinpoint SDK in your mobile applications:

### Android Integration

```java
// Add to build.gradle
implementation 'com.amazonaws:aws-android-sdk-pinpoint:2.+'

// Initialize Pinpoint
PinpointConfiguration config = new PinpointConfiguration(
    context,
    "YOUR_APPLICATION_ID",  // From terraform output
    Regions.US_EAST_1
);
PinpointManager pinpointManager = new PinpointManager(config);
```

### iOS Integration

```swift
// Add to Podfile
pod 'AWSPinpoint'

// Initialize Pinpoint
let pinpointConfiguration = AWSPinpointConfiguration.defaultPinpointConfiguration(
    launchOptions: launchOptions
)
pinpointConfiguration.appId = "YOUR_APPLICATION_ID"  // From terraform output
pinpointConfiguration.region = AWSRegionType.USEast1
let pinpoint = AWSPinpoint(configuration: pinpointConfiguration)
```

### Event Tracking

```javascript
// Track custom conversion events
pinpoint.record({
    name: 'conversion',
    attributes: {
        campaign_id: 'your-campaign-id',
        treatment: 'control'
    },
    metrics: {
        conversion_value: 1.0
    }
});
```

## Creating A/B Test Campaigns

After infrastructure deployment, create campaigns using the AWS CLI:

```bash
# Get the application ID from Terraform output
PINPOINT_APP_ID=$(terraform output -raw pinpoint_application_id)

# Create a campaign
aws pinpoint create-campaign \
    --application-id $PINPOINT_APP_ID \
    --write-campaign-request file://campaign-config.json
```

Example campaign configuration:

```json
{
    "Name": "Push Notification A/B Test",
    "Description": "Testing different message variations",
    "Schedule": {
        "StartTime": "IMMEDIATE",
        "IsLocalTime": false,
        "Timezone": "UTC"
    },
    "SegmentId": "SEGMENT_ID_FROM_OUTPUT",
    "MessageConfiguration": {
        "GCMMessage": {
            "Body": "Control message content",
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
                "GCMMessage": {
                    "Body": "Hi {{User.FirstName}}, personalized content!",
                    "Title": "Personalized Updates",
                    "Action": "OPEN_APP"
                }
            }
        }
    ],
    "HoldoutPercent": 10
}
```

## Monitoring and Analytics

### CloudWatch Dashboard

Access the dashboard URL from Terraform output:
```bash
terraform output cloudwatch_dashboard_url
```

### Key Metrics to Monitor

- **DeliveredCount**: Messages successfully delivered
- **OpenedCount**: Messages opened by users
- **ClickedCount**: Messages clicked/tapped
- **ConversionCount**: Custom conversion events
- **OptOutCount**: Users who opted out

### Winner Selection Lambda

The Lambda function automatically analyzes campaign performance:

```bash
# Invoke winner selection manually
aws lambda invoke \
    --function-name $(terraform output -raw winner_selection_lambda_function_name) \
    --payload '{"application_id":"'$PINPOINT_APP_ID'","campaign_id":"YOUR_CAMPAIGN_ID"}' \
    response.json
```

## Security Considerations

- All S3 buckets have public access blocked
- IAM roles follow least privilege principle
- Push notification credentials are stored securely
- Kinesis streams are encrypted with KMS
- Lambda functions have minimal required permissions

## Cost Optimization

- Use appropriate Kinesis shard counts for your volume
- Configure S3 lifecycle policies for analytics data
- Set reasonable campaign limits to control costs
- Monitor CloudWatch metrics usage

## Troubleshooting

### Common Issues

1. **Push notifications not working**:
   - Verify Firebase server key is correct
   - Check APNS certificate validity
   - Ensure mobile app is properly configured

2. **Campaign not delivering**:
   - Check segment has users
   - Verify campaign is not paused
   - Review campaign limits

3. **Analytics not exporting**:
   - Verify IAM role permissions
   - Check S3 bucket policy
   - Confirm export configuration

### Debug Commands

```bash
# Check Pinpoint application status
aws pinpoint get-app --application-id $PINPOINT_APP_ID

# List segments
aws pinpoint get-segments --application-id $PINPOINT_APP_ID

# Check campaign status
aws pinpoint get-campaign --application-id $PINPOINT_APP_ID --campaign-id $CAMPAIGN_ID

# View Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw winner_selection_lambda_function_name)
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will delete all campaign data, analytics exports, and configuration. Ensure you have backups of any important data before destroying.

## Support and Documentation

- [Amazon Pinpoint Developer Guide](https://docs.aws.amazon.com/pinpoint/latest/developerguide/)
- [Pinpoint A/B Testing](https://docs.aws.amazon.com/pinpoint/latest/developerguide/campaigns-abtest.html)
- [Pinpoint SDK Documentation](https://docs.aws.amazon.com/pinpoint/latest/developerguide/integrate.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

## License

This Terraform configuration is provided as-is for educational and reference purposes. Modify as needed for your specific use case.