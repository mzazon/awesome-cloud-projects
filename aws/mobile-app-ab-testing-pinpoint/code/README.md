# Infrastructure as Code for Mobile App A/B Testing with Pinpoint Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Mobile App A/B Testing with Pinpoint Analytics".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Pinpoint (full access)
  - IAM (role creation and policy attachment)
  - S3 (bucket creation and management)
  - CloudWatch (dashboard and metrics management)
  - Kinesis (stream creation and management)
- Firebase Server Key for Android push notifications (FCM)
- Apple Push Notification certificates for iOS (optional)
- Basic understanding of A/B testing concepts
- Estimated cost: $50-100/month for testing (depends on message volume and analytics export)

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name pinpoint-ab-testing \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=FirebaseServerKey,ParameterValue=YOUR_FIREBASE_KEY \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name pinpoint-ab-testing \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Configure Firebase key
export FIREBASE_SERVER_KEY="YOUR_FIREBASE_KEY"

# Deploy the infrastructure
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Configure Firebase key
export FIREBASE_SERVER_KEY="YOUR_FIREBASE_KEY"

# Deploy the infrastructure
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
cd terraform/
terraform init

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Firebase key

terraform plan
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh

# Set required environment variables
export FIREBASE_SERVER_KEY="YOUR_FIREBASE_KEY"
export AWS_REGION="us-east-1"

./scripts/deploy.sh
```

## Architecture Overview

The deployed infrastructure includes:

- **Amazon Pinpoint Project**: Central application for managing A/B tests
- **Push Notification Channels**: FCM (Android) and APNS (iOS) integration
- **User Segments**: Targeted user groups for testing
- **A/B Test Campaigns**: Multi-variant campaigns with control groups
- **Analytics Export**: S3 bucket for long-term data storage
- **Real-time Processing**: Kinesis stream for event processing
- **Monitoring**: CloudWatch dashboard and metrics
- **IAM Roles**: Secure access for Pinpoint analytics export

## Configuration

### Firebase Server Key Setup

1. Go to Firebase Console → Project Settings → Cloud Messaging
2. Copy the Server Key
3. Set the environment variable or parameter:
   ```bash
   export FIREBASE_SERVER_KEY="YOUR_ACTUAL_SERVER_KEY"
   ```

### Apple Push Notification Setup (Optional)

For iOS push notifications:

1. Generate Apple Push Notification certificate
2. Upload to Amazon Pinpoint console after deployment
3. Or use the AWS CLI to configure APNS channel

### Campaign Configuration

After deployment, you can:

1. Create custom user segments based on behavior
2. Set up A/B test campaigns with multiple treatments
3. Configure conversion tracking events
4. Monitor real-time analytics

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name pinpoint-ab-testing

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name pinpoint-ab-testing \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the appropriate CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### CloudFormation Parameters

- `ProjectName`: Name for the Pinpoint project
- `FirebaseServerKey`: Firebase server key for Android notifications
- `S3BucketName`: Name for analytics export bucket
- `EnableAPNS`: Enable Apple Push Notification Service

### CDK Environment Variables

- `FIREBASE_SERVER_KEY`: Firebase server key for push notifications
- `PROJECT_NAME`: Custom project name (optional)
- `ENABLE_APNS`: Enable Apple Push Notification Service (optional)

### Terraform Variables

Edit `terraform.tfvars` to customize:

```hcl
project_name = "my-mobile-ab-test"
firebase_server_key = "your-firebase-key"
aws_region = "us-east-1"
enable_apns = false
```

### Bash Script Variables

Set environment variables before running:

```bash
export PINPOINT_PROJECT_NAME="my-ab-test"
export FIREBASE_SERVER_KEY="your-firebase-key"
export AWS_REGION="us-east-1"
export ENABLE_APNS="false"
```

## Usage Examples

### Creating A/B Test Campaigns

After deployment, use the Pinpoint project ID to create campaigns:

```bash
# Get project ID from outputs
PROJECT_ID=$(aws cloudformation describe-stacks \
    --stack-name pinpoint-ab-testing \
    --query 'Stacks[0].Outputs[?OutputKey==`PinpointProjectId`].OutputValue' \
    --output text)

# Create a campaign (example)
aws pinpoint create-campaign \
    --application-id $PROJECT_ID \
    --write-campaign-request file://campaign-config.json
```

### Monitoring Campaign Performance

```bash
# View campaign metrics
aws pinpoint get-campaign-activities \
    --application-id $PROJECT_ID \
    --campaign-id $CAMPAIGN_ID

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Pinpoint \
    --metric-name DirectMessagesDelivered \
    --dimensions Name=ApplicationId,Value=$PROJECT_ID \
    --start-time 2023-01-01T00:00:00Z \
    --end-time 2023-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

### Event Tracking

```bash
# Send custom events for A/B test analysis
aws pinpoint put-events \
    --application-id $PROJECT_ID \
    --events-request '{
        "BatchItem": {
            "user-123": {
                "Endpoint": {
                    "Address": "user123@example.com",
                    "ChannelType": "EMAIL"
                },
                "Events": {
                    "app-open": {
                        "EventType": "conversion",
                        "Timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
                        "Attributes": {
                            "campaign_id": "'$CAMPAIGN_ID'",
                            "treatment": "variant_a"
                        }
                    }
                }
            }
        }
    }'
```

## Troubleshooting

### Common Issues

1. **Firebase Key Invalid**: Ensure the Firebase server key is correct and has proper permissions
2. **IAM Permissions**: Verify your AWS credentials have the required permissions
3. **Region Limitations**: Amazon Pinpoint is not available in all regions
4. **Cost Concerns**: Monitor CloudWatch billing alerts for unexpected charges

### Debugging Commands

```bash
# Check Pinpoint project status
aws pinpoint get-app --application-id $PROJECT_ID

# Verify S3 bucket exists
aws s3 ls s3://your-analytics-bucket

# Check CloudWatch dashboard
aws cloudwatch list-dashboards

# Verify Kinesis stream
aws kinesis describe-stream --stream-name pinpoint-events
```

## Security Considerations

- Firebase server keys are stored as secure parameters
- IAM roles follow least privilege principle
- S3 bucket has appropriate access controls
- Kinesis stream uses encryption at rest
- CloudWatch metrics are secured with IAM

## Support

For issues with this infrastructure code, refer to:

- [Amazon Pinpoint Documentation](https://docs.aws.amazon.com/pinpoint/)
- [AWS A/B Testing Best Practices](https://docs.aws.amazon.com/pinpoint/latest/developerguide/campaigns-abtest.html)
- [Firebase Cloud Messaging Setup](https://firebase.google.com/docs/cloud-messaging)
- Original recipe documentation for step-by-step guidance

## Additional Resources

- [Amazon Pinpoint Pricing](https://aws.amazon.com/pinpoint/pricing/)
- [Mobile Analytics with Pinpoint](https://docs.aws.amazon.com/pinpoint/latest/developerguide/analytics.html)
- [Segmentation Best Practices](https://docs.aws.amazon.com/pinpoint/latest/developerguide/segments-dynamic.html)
- [Campaign Management Guide](https://docs.aws.amazon.com/pinpoint/latest/developerguide/campaigns.html)