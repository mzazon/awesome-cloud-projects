# Infrastructure as Code for Creating Progressive Web Apps with Amplify Hosting

This directory contains Infrastructure as Code (IaC) implementations for the recipe Creating Progressive Web Apps with Amplify Hosting.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Git repository with PWA source code
- Node.js 18+ installed locally
- Appropriate AWS permissions for:
  - AWS Amplify (amplify:*)
  - AWS Certificate Manager (acm:*)
  - Amazon Route 53 (route53:*)
  - Amazon CloudFront (cloudfront:*)
  - AWS CloudWatch (logs:*, cloudwatch:*)
  - IAM (iam:PassRole, iam:CreateRole, iam:AttachRolePolicy)
- Custom domain name (for production deployment)
- GitHub personal access token (for repository integration)

## Architecture Overview

This solution deploys:
- AWS Amplify Application with CI/CD pipeline
- CloudFront distribution for global content delivery
- Route 53 hosted zone and DNS records
- ACM SSL certificate for HTTPS
- CloudWatch monitoring and logging
- IAM roles and policies for service permissions

## Quick Start

### Using CloudFormation

```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name pwa-amplify-hosting \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AppName,ParameterValue=my-pwa-app \
                 ParameterKey=DomainName,ParameterValue=example.com \
                 ParameterKey=RepositoryURL,ParameterValue=https://github.com/username/repo \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor stack creation
aws cloudformation describe-stacks \
    --stack-name pwa-amplify-hosting \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name pwa-amplify-hosting \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (if not already done)
cdk bootstrap

# Review deployment plan
cdk diff

# Deploy the infrastructure
cdk deploy --parameters appName=my-pwa-app \
           --parameters domainName=example.com \
           --parameters repositoryUrl=https://github.com/username/repo

# View stack outputs
cdk ls --long
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
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (if not already done)
cdk bootstrap

# Review deployment plan
cdk diff

# Deploy the infrastructure
cdk deploy --parameters appName=my-pwa-app \
           --parameters domainName=example.com \
           --parameters repositoryUrl=https://github.com/username/repo

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
app_name = "my-pwa-app"
domain_name = "example.com"
repository_url = "https://github.com/username/repo"
github_token = "your-github-token"
aws_region = "us-east-1"
EOF

# Review deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export APP_NAME="my-pwa-app"
export DOMAIN_NAME="example.com"
export REPOSITORY_URL="https://github.com/username/repo"
export GITHUB_TOKEN="your-github-token"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws amplify get-app --app-id $(cat .amplify-app-id) --query 'app.{Name:name,Status:enableBranchAutoBuild,URL:defaultDomain}'
```

## Configuration Options

### CloudFormation Parameters

- `AppName`: Name for the Amplify application
- `DomainName`: Custom domain name for the PWA
- `RepositoryURL`: Git repository URL containing PWA source code
- `BranchName`: Git branch to deploy (default: main)
- `EnableAutoBuild`: Enable automatic builds on code changes (default: true)

### CDK Context Parameters

- `appName`: Name for the Amplify application
- `domainName`: Custom domain name for the PWA
- `repositoryUrl`: Git repository URL containing PWA source code
- `branchName`: Git branch to deploy (default: main)
- `enableAutoBuild`: Enable automatic builds on code changes (default: true)

### Terraform Variables

- `app_name`: Name for the Amplify application
- `domain_name`: Custom domain name for the PWA
- `repository_url`: Git repository URL containing PWA source code
- `github_token`: GitHub personal access token for repository access
- `branch_name`: Git branch to deploy (default: main)
- `aws_region`: AWS region for deployment

### Environment Variables for Scripts

- `APP_NAME`: Name for the Amplify application
- `DOMAIN_NAME`: Custom domain name for the PWA
- `REPOSITORY_URL`: Git repository URL containing PWA source code
- `GITHUB_TOKEN`: GitHub personal access token for repository access
- `BRANCH_NAME`: Git branch to deploy (default: main)
- `AWS_REGION`: AWS region for deployment

## Post-Deployment Steps

1. **Domain Verification**: Verify domain ownership through AWS Console or CLI
2. **Repository Connection**: Connect GitHub repository with appropriate permissions
3. **Build Configuration**: Review and customize amplify.yml build settings
4. **SSL Certificate**: Ensure ACM certificate validation completes
5. **DNS Configuration**: Update domain registrar to use Route 53 name servers

## Monitoring and Troubleshooting

### Check Application Status

```bash
# Get application details
aws amplify get-app --app-id YOUR_APP_ID

# Check build status
aws amplify list-jobs --app-id YOUR_APP_ID --branch-name main

# View build logs
aws amplify get-job --app-id YOUR_APP_ID --branch-name main --job-id JOB_ID
```

### Common Issues

1. **Domain Verification Pending**: Check DNS records and certificate validation
2. **Build Failures**: Review build logs and amplify.yml configuration
3. **Repository Access**: Verify GitHub token permissions and repository access
4. **SSL Certificate Issues**: Ensure domain validation is complete

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name pwa-amplify-hosting

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name pwa-amplify-hosting \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy

# Confirm deletion when prompted
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
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
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

- **IAM Permissions**: Use least privilege principle for all IAM roles
- **SSL/TLS**: All traffic encrypted with ACM-managed certificates
- **Access Control**: Repository access controlled through GitHub tokens
- **Monitoring**: CloudWatch logging enabled for security auditing
- **Domain Security**: DNS records managed through Route 53

## Cost Optimization

- **Amplify Hosting**: Pay-per-use pricing with generous free tier
- **CloudFront**: Edge caching reduces origin requests and costs
- **Build Minutes**: Monitor usage to stay within free tier limits
- **Data Transfer**: CloudFront reduces data transfer costs from origin

## Performance Features

- **Global CDN**: CloudFront edge locations for fast content delivery
- **Automatic Compression**: Gzip compression enabled by default
- **HTTP/2**: Modern protocol support for improved performance
- **Caching Strategy**: Optimized cache headers for static and dynamic content

## Customization

### Custom Build Commands

Modify `amplify.yml` in your repository:

```yaml
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: dist
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
```

### Environment Variables

Add environment variables through AWS Console or CLI:

```bash
aws amplify put-backend-environment \
    --app-id YOUR_APP_ID \
    --environment-name production \
    --deployment-artifacts bucket-name
```

### Custom Headers

Configure custom headers for security and performance:

```bash
aws amplify update-app \
    --app-id YOUR_APP_ID \
    --custom-headers file://custom-headers.json
```

## Advanced Features

### Preview Environments

Enable pull request previews:

```bash
aws amplify update-branch \
    --app-id YOUR_APP_ID \
    --branch-name main \
    --enable-pull-request-preview
```

### Password Protection

Add basic authentication:

```bash
aws amplify update-branch \
    --app-id YOUR_APP_ID \
    --branch-name main \
    --basic-auth-credentials username:password \
    --enable-basic-auth
```

### Webhook Integration

Set up build webhooks for external triggers:

```bash
aws amplify create-webhook \
    --app-id YOUR_APP_ID \
    --branch-name main \
    --description "External build trigger"
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS Amplify documentation: https://docs.aws.amazon.com/amplify/
3. Validate PWA requirements: https://web.dev/progressive-web-apps/
4. Submit issues to the repository maintainers

## Additional Resources

- [AWS Amplify Documentation](https://docs.aws.amazon.com/amplify/)
- [Progressive Web Apps Guide](https://web.dev/progressive-web-apps/)
- [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)