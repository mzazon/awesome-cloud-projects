# Infrastructure as Code for Pinpoint Mobile Push Notifications

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Pinpoint Mobile Push Notifications".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Pinpoint, SNS, IAM, Kinesis, and CloudWatch
- iOS Developer Account with valid APNs certificates or authentication keys
- Firebase project with FCM credentials for Android notifications
- Basic understanding of mobile push notification concepts
- Estimated cost: $10-50/month for 100,000 push notifications

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 16+ and npm
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8+ and pip
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0+
- AWS provider configured

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name pinpoint-push-notifications \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AppName,ParameterValue=my-mobile-app \
                ParameterKey=FCMServerKey,ParameterValue=YOUR_FCM_SERVER_KEY \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name pinpoint-push-notifications

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name pinpoint-push-notifications \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters appName=my-mobile-app \
           --parameters fcmServerKey=YOUR_FCM_SERVER_KEY

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters appName=my-mobile-app \
           --parameters fcmServerKey=YOUR_FCM_SERVER_KEY

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="app_name=my-mobile-app" \
               -var="fcm_server_key=YOUR_FCM_SERVER_KEY"

# Apply the configuration
terraform apply -var="app_name=my-mobile-app" \
                -var="fcm_server_key=YOUR_FCM_SERVER_KEY"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export APP_NAME="my-mobile-app"
export FCM_SERVER_KEY="YOUR_FCM_SERVER_KEY"

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
aws pinpoint get-apps --region us-east-1
```

## Configuration Options

### Required Parameters

- **App Name**: Unique name for your Pinpoint application
- **FCM Server Key**: Firebase Cloud Messaging server key for Android notifications

### Optional Parameters

- **AWS Region**: Target AWS region (default: us-east-1)
- **Segment Name**: Custom name for user segment (default: high-value-customers)
- **Campaign Name**: Custom name for push campaign (default: flash-sale-notification)

### Platform Configuration

#### iOS (APNs) Setup
1. Obtain APNs certificates or authentication keys from Apple Developer Console
2. Configure the APNs channel after deployment:
   ```bash
   aws pinpoint update-apns-channel \
       --application-id YOUR_PINPOINT_APP_ID \
       --apns-channel-request \
       Enabled=true,DefaultAuthenticationMethod=CERTIFICATE \
       --region us-east-1
   ```

#### Android (FCM) Setup
1. Create a Firebase project at https://console.firebase.google.com
2. Generate a server key from Project Settings > Cloud Messaging
3. Use the server key in the deployment configuration

## Post-Deployment Configuration

### 1. Register User Endpoints
```bash
# Create iOS endpoint
aws pinpoint update-endpoint \
    --application-id YOUR_PINPOINT_APP_ID \
    --endpoint-id "ios-user-001" \
    --endpoint-request '{
        "ChannelType": "APNS",
        "Address": "DEVICE_TOKEN_HERE",
        "User": {
            "UserId": "user-001",
            "UserAttributes": {
                "PurchaseHistory": ["high-value"]
            }
        }
    }'

# Create Android endpoint
aws pinpoint update-endpoint \
    --application-id YOUR_PINPOINT_APP_ID \
    --endpoint-id "android-user-002" \
    --endpoint-request '{
        "ChannelType": "GCM",
        "Address": "DEVICE_TOKEN_HERE",
        "User": {
            "UserId": "user-002",
            "UserAttributes": {
                "PurchaseHistory": ["high-value"]
            }
        }
    }'
```

### 2. Send Test Notifications
```bash
# Send test message to specific endpoints
aws pinpoint send-messages \
    --application-id YOUR_PINPOINT_APP_ID \
    --message-request '{
        "MessageConfiguration": {
            "APNSMessage": {
                "Action": "OPEN_APP",
                "Body": "Test notification - Your app is working!",
                "Title": "Test Push Notification",
                "Sound": "default"
            },
            "GCMMessage": {
                "Action": "OPEN_APP",
                "Body": "Test notification - Your app is working!",
                "Title": "Test Push Notification",
                "Sound": "default"
            }
        },
        "Endpoints": {
            "ios-user-001": {},
            "android-user-002": {}
        }
    }'
```

### 3. Create and Launch Campaigns
```bash
# Create a campaign targeting the high-value customer segment
aws pinpoint create-campaign \
    --application-id YOUR_PINPOINT_APP_ID \
    --write-campaign-request '{
        "Name": "flash-sale-campaign",
        "MessageConfiguration": {
            "APNSMessage": {
                "Action": "OPEN_APP",
                "Body": "Limited time offer - 50% off your favorite items!",
                "Title": "🔥 Flash Sale Alert",
                "Sound": "default"
            },
            "GCMMessage": {
                "Action": "OPEN_APP",
                "Body": "Limited time offer - 50% off your favorite items!",
                "Title": "🔥 Flash Sale Alert",
                "Sound": "default"
            }
        },
        "Schedule": {
            "IsLocalTime": true,
            "QuietTime": {
                "Start": "22:00",
                "End": "08:00"
            },
            "StartTime": "IMMEDIATE"
        },
        "SegmentId": "YOUR_SEGMENT_ID"
    }'
```

## Monitoring and Analytics

### CloudWatch Metrics
Monitor your push notification performance:
- `DirectSendMessagePermanentFailure`: Failed notifications
- `DirectSendMessageDeliveryRate`: Successful delivery rate
- `CampaignSendMessageLatency`: Campaign delivery latency

### Event Streaming
The infrastructure includes Kinesis event streaming for real-time analytics:
```bash
# View event stream data
aws kinesis describe-stream \
    --stream-name pinpoint-events-SUFFIX

# Get records from the stream
aws kinesis get-shard-iterator \
    --stream-name pinpoint-events-SUFFIX \
    --shard-id shardId-000000000000 \
    --shard-iterator-type LATEST
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name pinpoint-push-notifications

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name pinpoint-push-notifications
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="app_name=my-mobile-app" \
                  -var="fcm_server_key=YOUR_FCM_SERVER_KEY"
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup
aws pinpoint get-apps --region us-east-1
```

## Troubleshooting

### Common Issues

1. **APNs Certificate Issues**
   - Ensure certificates are valid and not expired
   - Verify bundle ID matches your mobile application
   - Check Apple Developer Console for certificate status

2. **FCM Authentication Failures**
   - Verify FCM server key is correct and active
   - Ensure Firebase project has Cloud Messaging enabled
   - Check Firebase console for any configuration issues

3. **Device Token Problems**
   - Device tokens must be current and valid
   - iOS tokens change when app is restored from backup
   - Android tokens can change during app updates

4. **Delivery Issues**
   - Check CloudWatch logs for error details
   - Verify quiet time settings aren't blocking delivery
   - Ensure endpoints are registered with correct channel type

### Validation Commands

```bash
# Check application status
aws pinpoint get-app --application-id YOUR_PINPOINT_APP_ID

# Verify channels are enabled
aws pinpoint get-channels --application-id YOUR_PINPOINT_APP_ID

# Check endpoint registration
aws pinpoint get-endpoint \
    --application-id YOUR_PINPOINT_APP_ID \
    --endpoint-id YOUR_ENDPOINT_ID

# View campaign analytics
aws pinpoint get-campaign-activities \
    --application-id YOUR_PINPOINT_APP_ID \
    --campaign-id YOUR_CAMPAIGN_ID
```

## Security Considerations

- Store FCM server keys securely using AWS Secrets Manager
- Use least privilege IAM policies for Pinpoint access
- Enable CloudTrail logging for audit compliance
- Regularly rotate APNs certificates and FCM keys
- Implement proper user consent mechanisms for push notifications

## Cost Optimization

- Use Pinpoint's built-in analytics to optimize send times
- Implement user preference management to reduce unwanted notifications
- Monitor delivery rates and adjust targeting to improve efficiency
- Use segments to avoid sending to inactive users
- Consider message batching for large campaigns

## Customization

### Extending the Solution

1. **Add Email/SMS Channels**: Extend campaigns to include email and SMS
2. **Implement A/B Testing**: Use Pinpoint's holdout and treatment groups
3. **Add Machine Learning**: Integrate with Amazon Personalize for recommendations
4. **Create Custom Analytics**: Process Kinesis events in real-time
5. **Build User Preferences**: Implement preference centers for notification management

### Variable Customization

Refer to the variable definitions in each implementation:
- CloudFormation: Parameters section
- CDK: Constructor parameters and context values
- Terraform: variables.tf file

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS Pinpoint documentation
3. Verify mobile SDK integration
4. Contact AWS support for service-specific issues

## Additional Resources

- [AWS End User Messaging Push Documentation](https://docs.aws.amazon.com/pinpoint/)
- [Apple Push Notification Service Guide](https://developer.apple.com/documentation/usernotifications)
- [Firebase Cloud Messaging Documentation](https://firebase.google.com/docs/cloud-messaging)
- [Mobile Push Notification Best Practices](https://docs.aws.amazon.com/pinpoint/latest/userguide/channels-mobile-best-practices.html)