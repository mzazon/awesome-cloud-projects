# Infrastructure as Code for Container Registry Replication with ECR

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Registry Replication with ECR".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for ECR, IAM, CloudWatch, and SNS
- Docker installed for testing image operations
- Basic understanding of container registries and IAM policies
- Access to multiple AWS regions (us-east-1, us-west-2, eu-west-1)
- Estimated cost: $5-15 per month for storage and data transfer

> **Note**: Cross-region replication incurs data transfer charges between regions. Monitor costs using CloudWatch metrics.

## Architecture Overview

This solution implements automated container registry replication using Amazon ECR's native cross-region replication capabilities. The infrastructure includes:

- **Source ECR Registry** (us-east-1): Primary repositories for production and testing images
- **Destination ECR Registry** (us-west-2): Replicated repositories for regional deployments
- **Secondary ECR Registry** (eu-west-1): Replicated repositories for disaster recovery
- **CloudWatch Monitoring**: Dashboards and alarms for replication health
- **Lifecycle Policies**: Automated image cleanup and retention management
- **Repository Policies**: Fine-grained access control for container operations
- **SNS Notifications**: Alerting for replication failures

## Quick Start

### Using CloudFormation

```bash
# Deploy the ECR replication infrastructure
aws cloudformation create-stack \
    --stack-name ecr-replication-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SourceRegion,ParameterValue=us-east-1 \
                 ParameterKey=DestinationRegion,ParameterValue=us-west-2 \
                 ParameterKey=SecondaryRegion,ParameterValue=eu-west-1 \
                 ParameterKey=RepoPrefix,ParameterValue=enterprise-apps \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name ecr-replication-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ecr-replication-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment context
npm run cdk -- deploy \
    --context sourceRegion=us-east-1 \
    --context destinationRegion=us-west-2 \
    --context secondaryRegion=eu-west-1 \
    --context repoPrefix=enterprise-apps

# Alternative: Deploy with confirmation
npm run cdk -- deploy --require-approval never
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .env
source .env/bin/activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy \
    --context sourceRegion=us-east-1 \
    --context destinationRegion=us-west-2 \
    --context secondaryRegion=eu-west-1 \
    --context repoPrefix=enterprise-apps

# Alternative: Deploy with parameters
cdk deploy --parameters sourceRegion=us-east-1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="source_region=us-east-1" \
    -var="destination_region=us-west-2" \
    -var="secondary_region=eu-west-1" \
    -var="repo_prefix=enterprise-apps"

# Apply the configuration
terraform apply \
    -var="source_region=us-east-1" \
    -var="destination_region=us-west-2" \
    -var="secondary_region=eu-west-1" \
    -var="repo_prefix=enterprise-apps"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set environment variables
export SOURCE_REGION="us-east-1"
export DESTINATION_REGION="us-west-2"
export SECONDARY_REGION="eu-west-1"
export REPO_PREFIX="enterprise-apps"

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
aws ecr describe-registry --region $SOURCE_REGION
```

## Configuration Options

### Key Parameters

- **Source Region**: Primary region for ECR repositories (default: us-east-1)
- **Destination Region**: Primary replication target (default: us-west-2)
- **Secondary Region**: Secondary replication target for DR (default: eu-west-1)
- **Repository Prefix**: Prefix for repository names (default: enterprise-apps)
- **Production Repository**: Repository for production images
- **Testing Repository**: Repository for development/testing images

### Lifecycle Policy Configuration

The infrastructure includes optimized lifecycle policies:

**Production Repository Policy**:
- Keeps last 10 production images (tagged with 'prod', 'release')
- Deletes untagged images older than 1 day
- Prioritizes production image retention

**Testing Repository Policy**:
- Keeps last 5 testing images (tagged with 'test', 'dev', 'staging')
- Deletes all images older than 7 days
- Aggressive cleanup for cost optimization

### Repository Access Control

Repository policies implement role-based access:
- **Production Role**: Read-only access for deployments
- **CI Pipeline Role**: Push access for automated builds
- **Cross-account access**: Configurable for multi-account scenarios

## Monitoring and Alerting

### CloudWatch Dashboard

The deployment creates a monitoring dashboard that tracks:
- Repository pull and push activity
- Replication success rates
- Storage utilization across regions
- Image scan results and vulnerabilities

### CloudWatch Alarms

Automated alarms monitor:
- **Replication Failure Rate**: Triggers when failures exceed 10%
- **Repository Activity**: Monitors unusual push/pull patterns
- **Storage Costs**: Alerts on unexpected storage growth

### SNS Notifications

The infrastructure includes SNS topics for:
- Replication failure alerts
- Lifecycle policy actions
- Security scan results

## Testing and Validation

### Testing Image Replication

```bash
# Build and push a test image
docker build -t test-app .
docker tag test-app ${AWS_ACCOUNT_ID}.dkr.ecr.${SOURCE_REGION}.amazonaws.com/production-repo:test-1.0

# Push to trigger replication
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${SOURCE_REGION}.amazonaws.com/production-repo:test-1.0

# Wait for replication (5-10 minutes)
sleep 600

# Verify replication in destination region
aws ecr describe-images \
    --region $DESTINATION_REGION \
    --repository-name production-repo
```

### Performance Testing

```bash
# Test cross-region pull performance
aws ecr get-login-password --region $DESTINATION_REGION | \
    docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${DESTINATION_REGION}.amazonaws.com

# Time the pull operation
time docker pull ${AWS_ACCOUNT_ID}.dkr.ecr.${DESTINATION_REGION}.amazonaws.com/production-repo:test-1.0
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name ecr-replication-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ecr-replication-stack
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
# Answer 'y' to proceed with deletion
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="source_region=us-east-1" \
    -var="destination_region=us-west-2" \
    -var="secondary_region=eu-west-1" \
    -var="repo_prefix=enterprise-apps"

# Confirm destruction when prompted
# Enter 'yes' to proceed
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
# Follow the interactive prompts to clean up resources
```

## Customization

### Multi-Account Replication

To enable cross-account replication, modify the repository policies:

```json
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "CrossAccountReplication",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::TARGET-ACCOUNT-ID:root"
      },
      "Action": [
        "ecr:CreateRepository",
        "ecr:BatchImportLayerPart",
        "ecr:PutImage"
      ]
    }
  ]
}
```

### Custom Lifecycle Policies

Modify the lifecycle policies to match your retention requirements:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last N images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["prod", "release"],
        "countType": "imageCountMoreThan",
        "countNumber": 20
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

### Additional Regions

To add more replication regions, update the replication configuration:

```json
{
  "rules": [
    {
      "destinations": [
        {
          "region": "us-west-2",
          "registryId": "123456789012"
        },
        {
          "region": "eu-west-1",
          "registryId": "123456789012"
        },
        {
          "region": "ap-southeast-1",
          "registryId": "123456789012"
        }
      ],
      "repositoryFilters": [
        {
          "filter": "enterprise-apps",
          "filterType": "PREFIX_MATCH"
        }
      ]
    }
  ]
}
```

## Cost Optimization

### Storage Cost Management

- **Lifecycle Policies**: Automatically clean up old images
- **Repository Filtering**: Replicate only necessary images
- **Regional Strategy**: Balance availability with storage costs

### Data Transfer Optimization

- **Selective Replication**: Use repository filters to minimize data transfer
- **Regional Deployment**: Deploy applications in the same region as registries
- **Batch Operations**: Group image pushes to minimize transfer frequency

## Security Considerations

### Access Control

- **IAM Roles**: Use specific roles for different operations
- **Repository Policies**: Implement fine-grained access control
- **Cross-Account Access**: Secure multi-account scenarios

### Image Security

- **Vulnerability Scanning**: Automatically scan images on push
- **Image Signing**: Implement container image signing
- **Compliance Policies**: Enforce organizational compliance requirements

## Troubleshooting

### Common Issues

1. **Replication Delays**: Normal latency is 5-30 minutes
2. **Permission Errors**: Verify IAM roles and repository policies
3. **Cost Spikes**: Check lifecycle policies and data transfer patterns
4. **Failed Replication**: Review CloudWatch logs and SNS notifications

### Debugging Commands

```bash
# Check replication status
aws ecr describe-registry --region $SOURCE_REGION

# Review replication metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ECR \
    --metric-name ReplicationLatency \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Average

# Check repository policies
aws ecr get-repository-policy \
    --repository-name production-repo
```

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../container-registry-replication-strategies-ecr.md)
- [AWS ECR documentation](https://docs.aws.amazon.com/ecr/)
- [ECR replication documentation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html)
- [ECR lifecycle policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)

## Additional Resources

- [ECR Best Practices](https://docs.aws.amazon.com/AmazonECR/latest/userguide/best-practices.html)
- [Container Image Security](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html)
- [AWS Container Blog](https://aws.amazon.com/blogs/containers/)
- [ECR Pricing](https://aws.amazon.com/ecr/pricing/)