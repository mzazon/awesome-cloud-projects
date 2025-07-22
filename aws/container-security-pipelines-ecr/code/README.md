# Infrastructure as Code for Container Security Scanning Pipelines

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Security Scanning Pipelines".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive container security scanning pipeline that combines:

- **Amazon ECR** with enhanced scanning capabilities
- **Amazon Inspector** for continuous vulnerability detection
- **AWS CodeBuild** for CI/CD pipeline integration
- **AWS EventBridge** for event-driven automation
- **AWS Lambda** for security scan result processing
- **AWS Security Hub** for centralized security findings management
- **Third-party security tools** integration (Snyk, Prisma Cloud)

## Prerequisites

### General Requirements

- AWS CLI v2 installed and configured
- AWS account with Administrator permissions
- Docker installed locally for container image testing
- Node.js and npm (for CDK TypeScript implementation)
- Python 3.8+ (for CDK Python implementation)
- Terraform 1.0+ (for Terraform implementation)

### Required AWS Permissions

Your AWS credentials must have permissions for:
- ECR repository management and enhanced scanning configuration
- Inspector service configuration and findings access
- CodeBuild project creation and IAM role management
- EventBridge rule creation and target configuration
- Lambda function deployment and execution
- Security Hub integration and findings management
- SNS topic creation and notification management
- CloudWatch dashboard creation and log group access

### Third-Party Tool Requirements

- **Snyk Account**: For application dependency vulnerability scanning
- **Prisma Cloud Account**: For runtime security and compliance scanning
- **Slack/JIRA Integration**: For security alert notifications (optional)

### Estimated Costs

- **ECR Enhanced Scanning**: $0.09 per image scan
- **Inspector Continuous Scanning**: $0.30 per image per month
- **CodeBuild**: $0.005 per build minute
- **Lambda**: $0.20 per 1M requests
- **EventBridge**: $1.00 per million events
- **Estimated Monthly Cost**: $50-150 for scanning 100-500 images

## Quick Start

### Using CloudFormation

```bash
# Deploy the security scanning pipeline
aws cloudformation create-stack \
    --stack-name container-security-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-security-pipeline \
                 ParameterKey=ECRRepositoryName,ParameterValue=secure-app-repo \
                 ParameterKey=SnykToken,ParameterValue=your-snyk-token \
                 ParameterKey=NotificationEmail,ParameterValue=security@company.com

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name container-security-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export SNYK_TOKEN=your-snyk-token
export NOTIFICATION_EMAIL=security@company.com

# Deploy the stack
cdk deploy ContainerSecurityPipelineStack

# View outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export SNYK_TOKEN=your-snyk-token
export NOTIFICATION_EMAIL=security@company.com

# Deploy the stack
cdk deploy ContainerSecurityPipelineStack

# View stack outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_name = "my-security-pipeline"
ecr_repository_name = "secure-app-repo"
snyk_token = "your-snyk-token"
notification_email = "security@company.com"
aws_region = "us-east-1"
EOF

# Review deployment plan
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_NAME=my-security-pipeline
export ECR_REPOSITORY_NAME=secure-app-repo
export SNYK_TOKEN=your-snyk-token
export NOTIFICATION_EMAIL=security@company.com

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `ProjectName` | Unique identifier for the project | `security-pipeline` | Yes |
| `ECRRepositoryName` | Name for the ECR repository | `secure-app-repo` | Yes |
| `SnykToken` | Snyk API token for dependency scanning | - | Yes |
| `PrismaCloudConsole` | Prisma Cloud console URL | - | No |
| `NotificationEmail` | Email for security alerts | - | Yes |
| `ScanningFrequency` | Continuous or on-push scanning | `CONTINUOUS_SCAN` | No |
| `Environment` | Deployment environment | `production` | No |

### CDK Configuration

Both TypeScript and Python CDK implementations support these configuration options:

```typescript
// TypeScript example
const config = {
  projectName: process.env.PROJECT_NAME || 'security-pipeline',
  ecrRepositoryName: process.env.ECR_REPOSITORY_NAME || 'secure-app-repo',
  snykToken: process.env.SNYK_TOKEN,
  notificationEmail: process.env.NOTIFICATION_EMAIL,
  scanningFrequency: process.env.SCANNING_FREQUENCY || 'CONTINUOUS_SCAN',
  environment: process.env.ENVIRONMENT || 'production'
};
```

### Terraform Variables

```hcl
variable "project_name" {
  description = "Unique identifier for the project"
  type        = string
  default     = "security-pipeline"
}

variable "ecr_repository_name" {
  description = "Name for the ECR repository"
  type        = string
  default     = "secure-app-repo"
}

variable "snyk_token" {
  description = "Snyk API token for dependency scanning"
  type        = string
  sensitive   = true
}

variable "notification_email" {
  description = "Email address for security alerts"
  type        = string
}

variable "scanning_frequency" {
  description = "Scanning frequency for enhanced scanning"
  type        = string
  default     = "CONTINUOUS_SCAN"
  validation {
    condition     = contains(["CONTINUOUS_SCAN", "SCAN_ON_PUSH"], var.scanning_frequency)
    error_message = "Scanning frequency must be either CONTINUOUS_SCAN or SCAN_ON_PUSH."
  }
}
```

## Testing the Deployment

### 1. Deploy Test Application

```bash
# Create test application with vulnerabilities
mkdir test-app && cd test-app

# Create Dockerfile with known vulnerabilities
cat > Dockerfile << 'EOF'
FROM ubuntu:18.04
RUN apt-get update && apt-get install -y \
    curl \
    nodejs \
    npm
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "app.js"]
EOF

# Create package.json with vulnerable dependencies
cat > package.json << 'EOF'
{
  "name": "security-test-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.16.0",
    "lodash": "4.17.4"
  }
}
EOF

# Build and push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ECR_URI
docker build -t secure-app-repo:test .
docker tag secure-app-repo:test YOUR_ECR_URI:test
docker push YOUR_ECR_URI:test
```

### 2. Verify Security Scanning

```bash
# Check scan results
aws ecr describe-image-scan-findings \
    --repository-name secure-app-repo \
    --image-id imageTag=test

# Check Security Hub findings
aws securityhub get-findings \
    --filters '{"ProductName": [{"Value": "custom/container-security-scanner", "Comparison": "EQUALS"}]}'

# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/SecurityScanProcessor-SUFFIX \
    --start-time $(date -d "1 hour ago" +%s)000
```

### 3. Test EventBridge Integration

```bash
# Trigger a new scan by pushing another image
docker tag secure-app-repo:test YOUR_ECR_URI:test2
docker push YOUR_ECR_URI:test2

# Monitor EventBridge rule executions
aws events list-rule-names-by-target \
    --target-arn arn:aws:lambda:REGION:ACCOUNT:function:SecurityScanProcessor-SUFFIX
```

## Security Considerations

### IAM Permissions

The solution implements least privilege access principles:

- **CodeBuild Role**: Limited to ECR operations and CloudWatch logging
- **Lambda Role**: Security Hub integration and SNS publishing only
- **EventBridge**: Restricted to Lambda function invocation

### Data Protection

- **ECR Encryption**: All images encrypted at rest with AES256
- **Lambda Environment Variables**: Sensitive data handled securely
- **CloudWatch Logs**: Retention policies configured for compliance

### Network Security

- **VPC Configuration**: Optional VPC deployment for enhanced isolation
- **Security Groups**: Restrictive rules for inter-service communication
- **NAT Gateway**: Secure internet access for third-party tool integration

## Monitoring and Alerting

### CloudWatch Dashboards

The solution includes dashboards for:
- ECR repository metrics and scan results
- Lambda function performance and errors
- Security Hub findings trends
- Critical vulnerability alerts

### SNS Notifications

Automated notifications for:
- Critical vulnerability detection
- Scan completion events
- System errors and failures
- Compliance violations

### Security Hub Integration

Centralized security findings management:
- Consolidated vulnerability reporting
- Compliance status tracking
- Integration with other security tools
- Automated remediation workflows

## Troubleshooting

### Common Issues

1. **ECR Enhanced Scanning Not Enabled**
   ```bash
   # Check registry configuration
   aws ecr describe-registry --query 'registryConfiguration.scanningConfiguration'
   
   # Enable enhanced scanning
   aws ecr put-registry-scanning-configuration --scan-type ENHANCED
   ```

2. **Lambda Function Timeout**
   ```bash
   # Increase timeout in configuration
   aws lambda update-function-configuration \
       --function-name SecurityScanProcessor \
       --timeout 300
   ```

3. **Third-Party Scanner Authentication**
   ```bash
   # Update environment variables
   aws lambda update-function-configuration \
       --function-name SecurityScanProcessor \
       --environment Variables='{SNYK_TOKEN=new-token}'
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# CloudFormation
aws cloudformation create-stack \
    --parameters ParameterKey=DebugMode,ParameterValue=true

# CDK
export DEBUG_MODE=true
cdk deploy

# Terraform
terraform apply -var="debug_mode=true"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name container-security-pipeline

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name container-security-pipeline

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name container-security-pipeline
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy ContainerSecurityPipelineStack

# Clean up CDK assets
cdk destroy --all
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Clean up state files
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual cleanup verification
aws ecr describe-repositories --query 'repositories[?repositoryName==`secure-app-repo`]'
aws lambda list-functions --query 'Functions[?FunctionName==`SecurityScanProcessor`]'
```

## Advanced Configuration

### Multi-Environment Deployment

```bash
# Deploy to multiple environments
for env in dev staging prod; do
    aws cloudformation create-stack \
        --stack-name container-security-pipeline-$env \
        --template-body file://cloudformation.yaml \
        --parameters ParameterKey=Environment,ParameterValue=$env
done
```

### Custom Security Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "ecr:PutImage",
      "Resource": "*",
      "Condition": {
        "NumericGreaterThan": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    }
  ]
}
```

### Third-Party Tool Integration

```bash
# Configure additional scanners
export CLAIR_SERVER_URL=https://clair.company.com
export ANCHORE_URL=https://anchore.company.com
export TWISTLOCK_CONSOLE=https://twistlock.company.com

# Update buildspec.yml for additional tools
```

## Support and Documentation

### AWS Documentation

- [Amazon ECR Enhanced Scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-enhanced.html)
- [Amazon Inspector Container Scanning](https://docs.aws.amazon.com/inspector/latest/user/scanning-ecr.html)
- [AWS Security Hub](https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub.html)
- [AWS EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html)

### Third-Party Tools

- [Snyk Container Scanning](https://snyk.io/product/container-vulnerability-management/)
- [Prisma Cloud](https://docs.paloaltonetworks.com/prisma/prisma-cloud)
- [Aqua Security](https://docs.aquasec.com/)

### Community Resources

- [AWS Security Blog](https://aws.amazon.com/blogs/security/)
- [Container Security Best Practices](https://aws.amazon.com/blogs/containers/amazon-ecr-native-container-image-scanning/)
- [DevSecOps with AWS](https://aws.amazon.com/solutions/implementations/devsecops-on-aws/)

## Contributing

For issues with this infrastructure code, please:

1. Review the troubleshooting section
2. Check AWS service status
3. Verify your AWS permissions
4. Consult the original recipe documentation
5. Review provider-specific documentation

---

**Note**: This infrastructure code is generated from the recipe "Container Security Scanning Pipelines". For the complete implementation guide and background information, refer to the original recipe documentation.