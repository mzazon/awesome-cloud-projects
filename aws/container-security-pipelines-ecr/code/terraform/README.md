# Container Security Scanning Pipeline - Terraform Infrastructure

This Terraform configuration deploys a comprehensive container security scanning pipeline using Amazon ECR, AWS Inspector, CodeBuild, and third-party security tools.

## Architecture Overview

The infrastructure creates:
- **ECR Repository** with enhanced scanning enabled
- **CodeBuild Project** for multi-stage security scanning
- **Lambda Function** for processing scan results
- **EventBridge Rules** for automated scan result processing
- **SNS Topic** for security notifications
- **CloudWatch Dashboard** for monitoring
- **AWS Config Rules** for compliance checking
- **IAM Roles** with least-privilege permissions

## Prerequisites

1. **AWS CLI** installed and configured
2. **Terraform** v1.0+ installed
3. **Docker** installed (for testing)
4. **AWS Account** with appropriate permissions
5. **Third-party tool accounts** (Snyk, Prisma Cloud - optional)

## Required AWS Permissions

Your AWS user/role needs permissions for:
- ECR (create repositories, manage scanning)
- CodeBuild (create projects, manage builds)
- Lambda (create functions, manage execution)
- IAM (create roles and policies)
- EventBridge (create rules and targets)
- SNS (create topics and subscriptions)
- CloudWatch (create dashboards and log groups)
- Config (create rules and configuration)
- Secrets Manager (create and read secrets)

## Quick Start

### 1. Clone and Initialize

```bash
git clone <your-repo>
cd aws/container-security-scanning-pipelines-ecr-third-party-tools/code/terraform/
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Basic configuration
aws_region = "us-east-1"
environment = "dev"
project_name = "my-security-scanning"

# ECR configuration
ecr_repository_name = "my-secure-app"
enable_enhanced_scanning = true
scan_frequency = "CONTINUOUS_SCAN"

# CodeBuild configuration
github_repo_url = "https://github.com/your-org/your-repo.git"

# Notification configuration
notification_email = "security-team@yourcompany.com"

# Third-party scanners
enable_snyk_scanning = true
enable_prisma_scanning = false

# Security thresholds
critical_vulnerability_threshold = 0
high_vulnerability_threshold = 5
```

### 3. Deploy Infrastructure

```bash
# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Post-Deployment Setup

#### Configure Third-Party Scanner Credentials

**For Snyk:**
```bash
aws secretsmanager create-secret \
    --name "snyk-token" \
    --secret-string "your-snyk-token-here"
```

**For Prisma Cloud:**
```bash
aws secretsmanager create-secret \
    --name "prisma-credentials" \
    --secret-string '{
        "console": "your-prisma-console-url",
        "username": "your-prisma-username",
        "password": "your-prisma-password"
    }'
```

#### Confirm SNS Subscription

Check your email for the SNS subscription confirmation and confirm it.

### 5. Test the Pipeline

#### Create a Test Application

```bash
# Create a simple test application
mkdir test-app && cd test-app

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM ubuntu:18.04
RUN apt-get update && apt-get install -y curl nodejs npm
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
    "name": "test-app",
    "version": "1.0.0",
    "dependencies": {
        "express": "4.16.0",
        "lodash": "4.17.4"
    }
}
EOF

# Create simple app
cat > app.js << 'EOF'
const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('Hello World!'));
app.listen(3000, () => console.log('Server running on port 3000'));
EOF

# Copy buildspec.yml from terraform directory
cp ../buildspec.yml .
```

#### Build and Push Image

```bash
# Get ECR repository URL from terraform output
ECR_URL=$(terraform output -raw ecr_repository_url)

# Build and push image
docker build -t test-app:latest .
docker tag test-app:latest $ECR_URL:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

# Push image (this will trigger scanning)
docker push $ECR_URL:latest
```

#### Monitor Results

```bash
# Check CloudWatch dashboard
DASHBOARD_URL=$(terraform output -raw cloudwatch_dashboard_url)
echo "Dashboard: $DASHBOARD_URL"

# Check Security Hub findings
aws securityhub get-findings \
    --filters '{"ProductName": [{"Value": "custom/container-security-scanner", "Comparison": "EQUALS"}]}'

# Check Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow
```

## Configuration Options

### Security Scanning Configuration

```hcl
# Enhanced scanning settings
enable_enhanced_scanning = true        # Enable Amazon Inspector enhanced scanning
scan_frequency = "CONTINUOUS_SCAN"     # CONTINUOUS_SCAN or SCAN_ON_PUSH

# Third-party scanner settings
enable_snyk_scanning = true            # Enable Snyk vulnerability scanning
enable_prisma_scanning = false         # Enable Prisma Cloud scanning

# Security thresholds
critical_vulnerability_threshold = 0   # Block deployment if critical > 0
high_vulnerability_threshold = 5       # Require review if high > 5
```

### Notification Configuration

```hcl
# Email notifications
notification_email = "security@company.com"

# Slack integration (optional)
slack_webhook_url = "https://hooks.slack.com/services/..."

# CloudWatch log retention
log_retention_days = 30
```

### Compliance Configuration

```hcl
# AWS Config rules
enable_config_rules = true

# Security Hub integration
enable_security_hub = true
```

## Monitoring and Alerting

### CloudWatch Dashboard

The deployment creates a CloudWatch dashboard that shows:
- ECR repository metrics
- Critical security findings
- Lambda function performance
- Scan completion rates

### Security Hub Integration

All security findings are automatically sent to AWS Security Hub for:
- Centralized security management
- Compliance reporting
- Integration with other security tools

### SNS Notifications

Automatic notifications are sent for:
- Critical vulnerabilities detected
- High vulnerability count exceeded
- Scan failures or errors
- Policy violations

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Container Security Scan
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v1
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: us-east-1
    
    - name: Start CodeBuild
      run: |
        aws codebuild start-build \
          --project-name $(terraform output -raw codebuild_project_name) \
          --source-version ${{ github.sha }}
```

### GitLab CI Example

```yaml
stages:
  - security-scan

container-security-scan:
  stage: security-scan
  script:
    - aws codebuild start-build \
        --project-name $(terraform output -raw codebuild_project_name) \
        --source-version $CI_COMMIT_SHA
  only:
    - main
    - merge_requests
```

## Security Best Practices

### IAM Permissions

The Terraform configuration follows least-privilege principles:
- CodeBuild role has minimal ECR and logging permissions
- Lambda role has only Security Hub and SNS permissions
- Cross-service permissions are explicitly defined

### Secrets Management

All sensitive credentials should be stored in AWS Secrets Manager:
- Snyk API tokens
- Prisma Cloud credentials
- Third-party API keys

### Network Security

Consider implementing:
- VPC endpoints for ECR access
- Private subnets for CodeBuild
- Security groups for Lambda functions

## Troubleshooting

### Common Issues

1. **ECR Push Failures**
   ```bash
   # Check ECR permissions
   aws ecr describe-repositories --repository-names your-repo-name
   
   # Verify Docker login
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin your-ecr-url
   ```

2. **Scan Results Not Appearing**
   ```bash
   # Check EventBridge rule status
   aws events describe-rule --name $(terraform output -raw eventbridge_rule_name)
   
   # Check Lambda logs
   aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name)
   ```

3. **Third-Party Scanner Issues**
   ```bash
   # Verify secrets exist
   aws secretsmanager get-secret-value --secret-id snyk-token
   
   # Check CodeBuild logs
   aws logs tail /aws/codebuild/$(terraform output -raw codebuild_project_name)
   ```

### Debug Mode

Enable debug logging by setting environment variable:
```bash
export TF_LOG=DEBUG
terraform apply
```

### Support Commands

```bash
# Check all resources
terraform state list

# Show specific resource details
terraform state show aws_ecr_repository.main

# Validate configuration
terraform validate

# Format code
terraform fmt
```

## Cleanup

To remove all resources:

```bash
# Delete all container images first
aws ecr batch-delete-image \
    --repository-name $(terraform output -raw ecr_repository_name) \
    --image-ids imageTag=latest

# Destroy infrastructure
terraform destroy
```

## Cost Optimization

### Estimated Costs

- ECR Enhanced Scanning: ~$0.09 per image scan
- Lambda execution: ~$0.20 per 1M requests
- CodeBuild: ~$0.005 per build minute
- CloudWatch logs: ~$0.50 per GB
- SNS notifications: ~$0.50 per 1M notifications

### Cost Reduction Tips

1. **Optimize scan frequency**
   ```hcl
   scan_frequency = "SCAN_ON_PUSH"  # Instead of CONTINUOUS_SCAN
   ```

2. **Filter repositories**
   ```hcl
   # Only scan production repositories
   repository_filter = "prod-*"
   ```

3. **Adjust log retention**
   ```hcl
   log_retention_days = 7  # Reduce from 30 days
   ```

## Advanced Configuration

### Custom Security Policies

Create custom security policies by modifying the Lambda function:

```python
# Custom vulnerability thresholds
def assess_risk(critical, high, medium, low):
    if critical > 0:
        return "CRITICAL"
    elif high > 3:  # Custom threshold
        return "HIGH"
    elif medium > 20:  # Custom threshold
        return "MEDIUM"
    else:
        return "LOW"
```

### Integration with JIRA

Add JIRA integration for automatic ticket creation:

```python
import requests

def create_jira_ticket(security_report):
    jira_url = os.environ.get('JIRA_URL')
    jira_user = os.environ.get('JIRA_USER')
    jira_token = os.environ.get('JIRA_TOKEN')
    
    ticket_data = {
        "fields": {
            "project": {"key": "SEC"},
            "summary": f"Security vulnerabilities in {security_report['repository']}",
            "description": f"Found {security_report['scan_results']['critical_vulnerabilities']} critical vulnerabilities",
            "issuetype": {"name": "Bug"},
            "priority": {"name": "Critical" if security_report['scan_results']['critical_vulnerabilities'] > 0 else "High"}
        }
    }
    
    response = requests.post(
        f"{jira_url}/rest/api/2/issue",
        json=ticket_data,
        auth=(jira_user, jira_token)
    )
    
    return response.json()
```

## Contributing

To contribute to this Terraform configuration:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This Terraform configuration is provided under the MIT License.