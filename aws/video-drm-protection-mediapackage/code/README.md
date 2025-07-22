# Infrastructure as Code for Video DRM Protection with MediaPackage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Video DRM Protection with MediaPackage".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements comprehensive video content protection using:

- **AWS Elemental MediaLive**: Live video encoding and streaming
- **AWS Elemental MediaPackage**: Content packaging with multi-DRM support
- **AWS Lambda**: SPEKE key provider for DRM license management
- **Amazon CloudFront**: Global content delivery with security features
- **AWS Secrets Manager**: Secure DRM configuration storage
- **AWS KMS**: Encryption key management
- **Multi-DRM Support**: Widevine, PlayReady, and FairPlay integration

## Prerequisites

### AWS Account Requirements
- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - MediaLive and MediaPackage services
  - Lambda function creation and management
  - CloudFront distribution management
  - Secrets Manager and KMS operations
  - IAM role and policy management
  - S3 bucket operations

### Required Permissions
The deploying user/role needs permissions for:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "medialive:*",
                "mediapackage:*",
                "lambda:*",
                "cloudfront:*",
                "secretsmanager:*",
                "kms:*",
                "iam:*",
                "s3:*"
            ],
            "Resource": "*"
        }
    ]
}
```

### Technical Requirements
- Understanding of DRM concepts (Widevine, PlayReady, FairPlay)
- Knowledge of SPEKE API and content encryption principles
- SSL certificate for HTTPS endpoints (optional for testing)
- DRM service provider account or SPEKE-compatible solution

### Cost Considerations
- **Estimated cost**: $100-300/hour for protected streaming
- **MediaLive**: ~$5-15/hour depending on input resolution
- **MediaPackage**: $0.065/GB for origin egress
- **CloudFront**: $0.085/GB for data transfer (varies by region)
- **Lambda**: $0.20 per 1M requests + compute time
- **KMS**: $1/month per key + API calls
- **Secrets Manager**: $0.40/month per secret

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete DRM-protected streaming infrastructure
aws cloudformation create-stack \
    --stack-name drm-video-protection-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=drm-protected-streaming \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=DRMProvider,ParameterValue=speke-reference
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time in region)
cdk bootstrap

# Deploy the infrastructure
cdk deploy DRMVideoProtectionStack \
    --parameters projectName=drm-protected-streaming \
    --parameters environment=production

# Get stack outputs
cdk output
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the infrastructure
cdk deploy DRMVideoProtectionStack \
    --parameters projectName=drm-protected-streaming \
    --parameters environment=production
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_name=drm-protected-streaming" \
    -var="environment=production"

# Apply the configuration
terraform apply -var="project_name=drm-protected-streaming" \
    -var="environment=production"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure with interactive configuration
./scripts/deploy.sh

# Or deploy with environment variables
export PROJECT_NAME="drm-protected-streaming"
export ENVIRONMENT="production"
export AWS_REGION="us-east-1"
./scripts/deploy.sh
```

## Configuration Options

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `project_name` | Project identifier for resource naming | `drm-streaming` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `drm_provider` | DRM provider type | `speke-reference` | No |
| `enable_geo_blocking` | Enable geographic restrictions | `true` | No |
| `blocked_countries` | Countries to block (comma-separated) | `CN,RU` | No |
| `key_rotation_interval` | DRM key rotation in seconds | `3600` | No |
| `channel_resolution` | MediaLive input resolution | `HD` | No |

### DRM Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `widevine_enabled` | Enable Widevine DRM | `true` |
| `playready_enabled` | Enable PlayReady DRM | `true` |
| `fairplay_enabled` | Enable FairPlay DRM | `true` |
| `license_duration_seconds` | License validity duration | `86400` |
| `offline_license_duration` | Offline license duration | `2592000` |

### Advanced Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cloudfront_price_class` | CloudFront price class | `PriceClass_All` |
| `enable_waf` | Enable AWS WAF protection | `false` |
| `lambda_timeout` | SPEKE Lambda timeout | `30` |
| `segment_duration` | Video segment duration | `6` |
| `manifest_window_seconds` | Manifest window size | `300` |

## Post-Deployment Configuration

### 1. Configure Streaming Source
After deployment, configure your streaming source (OBS, hardware encoder, etc.):

```bash
# Get RTMP endpoints from deployment outputs
# Primary RTMP: rtmp://[MEDIALIVE-INPUT-URL]/live
# Stream Key: live
```

### 2. Test DRM Protection
Use the generated test player to verify DRM functionality:

```bash
# Access the DRM test player (output from deployment)
# URL: http://[S3-BUCKET].s3-website.[REGION].amazonaws.com/drm-player.html
```

### 3. Validate Multi-DRM Support
Test across different devices and browsers:
- **Chrome/Android**: Widevine DRM
- **Edge/Windows**: PlayReady DRM  
- **Safari/iOS**: FairPlay DRM

### 4. Monitor System Health
Set up monitoring for key components:

```bash
# Monitor MediaLive channel health
aws medialive describe-channel --channel-id [CHANNEL-ID]

# Monitor SPEKE Lambda performance
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=[SPEKE-FUNCTION-NAME]
```

## Security Best Practices

### 1. DRM Key Management
- **Key Rotation**: Keys rotate every hour by default
- **Secret Storage**: DRM configuration stored in Secrets Manager
- **Encryption**: All secrets encrypted with customer-managed KMS keys
- **Access Control**: Least-privilege IAM policies for service access

### 2. Network Security
- **HTTPS Only**: All content delivery over HTTPS
- **Geographic Blocking**: CloudFront geo-restrictions enabled
- **Origin Protection**: Custom headers for origin authentication
- **Input Security**: MediaLive input security groups configured

### 3. Monitoring and Alerting
- **Failed License Requests**: Monitor SPEKE Lambda errors
- **Unauthorized Access**: CloudFront access logging
- **Geographic Violations**: WAF geo-blocking logs
- **Key Rotation Health**: KMS key usage monitoring

## Troubleshooting

### Common Issues

#### 1. DRM License Acquisition Failures
```bash
# Check SPEKE Lambda logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/[FUNCTION-NAME]

# Test SPEKE endpoint manually
curl -X POST [SPEKE-ENDPOINT] \
    -H "Content-Type: application/json" \
    -d '{"content_id":"test","drm_systems":[{"system_id":"edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"}]}'
```

#### 2. MediaLive Channel Issues
```bash
# Check channel state
aws medialive describe-channel --channel-id [CHANNEL-ID] --query 'State'

# Review channel alerts
aws medialive list-channel-alerts --channel-id [CHANNEL-ID]
```

#### 3. CloudFront Distribution Problems
```bash
# Check distribution status
aws cloudfront get-distribution --id [DISTRIBUTION-ID] --query 'Distribution.Status'

# Verify origin configuration
aws cloudfront get-distribution-config --id [DISTRIBUTION-ID]
```

#### 4. Permission Issues
```bash
# Verify MediaLive role permissions
aws iam get-role-policy --role-name [MEDIALIVE-ROLE] --policy-name [POLICY-NAME]

# Check Lambda execution role
aws iam get-role-policy --role-name [LAMBDA-ROLE] --policy-name [POLICY-NAME]
```

### Performance Optimization

#### 1. CloudFront Optimization
- **Cache Behaviors**: Optimized for manifests vs. segments
- **Origin Shield**: Enable for high-traffic scenarios
- **HTTP/2**: Enabled by default for better performance

#### 2. MediaPackage Optimization
- **Segment Duration**: 6-second segments for optimal quality/latency balance
- **Manifest Window**: 5-minute window for live streaming
- **Bitrate Ladder**: Multi-quality adaptive streaming

#### 3. Lambda Optimization
- **Memory Allocation**: 256MB for SPEKE provider
- **Timeout**: 30 seconds for license requests
- **Concurrent Executions**: Monitor and adjust limits

## Cleanup

### Using CloudFormation
```bash
# Delete the complete stack
aws cloudformation delete-stack --stack-name drm-video-protection-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name drm-video-protection-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the infrastructure
cdk destroy DRMVideoProtectionStack --force

# Remove CDK bootstrap (optional, affects other CDK projects)
# cdk bootstrap --toolkit-stack-name CDKToolkit --destroy
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_name=drm-protected-streaming" \
    -var="environment=production"

# Clean up Terraform state (optional)
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Note: Some resources (KMS keys) have mandatory retention periods
```

### Manual Cleanup Verification
After automated cleanup, verify these resources are removed:

```bash
# Check MediaLive resources
aws medialive list-channels --query 'Channels[?Name==`[PROJECT-NAME]*`]'

# Check MediaPackage resources  
aws mediapackage list-channels --query 'Channels[?Id==`[PROJECT-NAME]*`]'

# Check CloudFront distributions
aws cloudfront list-distributions --query 'DistributionList.Items[?Comment==`[PROJECT-NAME]*`]'

# Check Lambda functions
aws lambda list-functions --query 'Functions[?FunctionName==`[PROJECT-NAME]*`]'
```

## Integration with Production Systems

### 1. CI/CD Pipeline Integration
```yaml
# Example GitHub Actions workflow
name: Deploy DRM Streaming Infrastructure
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Deploy with Terraform
        working-directory: terraform/
        run: |
          terraform init
          terraform apply -auto-approve
```

### 2. Monitoring Integration
```bash
# CloudWatch custom metrics
aws cloudwatch put-metric-data \
    --namespace "DRM/Streaming" \
    --metric-data MetricName=LicenseRequests,Value=1,Unit=Count

# Integration with external monitoring (DataDog, New Relic, etc.)
```

### 3. External DRM Provider Integration
Replace the reference SPEKE implementation with commercial providers:
- **Verimatrix**: Enterprise DRM with forensic watermarking
- **Irdeto**: Multi-DRM with advanced security features
- **BuyDRM**: KeyOS DRM platform integration
- **EZDRM**: Cloud-based DRM solution

## Support and Resources

### AWS Documentation
- [AWS Elemental MediaPackage SPEKE Guide](https://docs.aws.amazon.com/mediapackage/latest/ug/what-is-speke.html)
- [DRM and Encryption](https://docs.aws.amazon.com/mediapackage/latest/ug/drm.html)
- [MediaLive User Guide](https://docs.aws.amazon.com/medialive/latest/ug/)
- [CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/latest/APIReference/)

### DRM Technology Resources
- [Google Widevine](https://www.widevine.com/)
- [Microsoft PlayReady](https://www.microsoft.com/playready/)
- [Apple FairPlay](https://developer.apple.com/streaming/fps/)
- [SPEKE Specification](https://dashif.org/docs/SPEKE/)

### Community and Support
- AWS Media Services Forum
- DASH Industry Forum
- Video Technology Slack Communities
- AWS Solution Architects (for enterprise support)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support channels.