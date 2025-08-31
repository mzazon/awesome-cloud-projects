# Infrastructure as Code for Service Catalog Portfolio with CloudFormation Templates

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Service Catalog Portfolio with CloudFormation Templates".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- Service Catalog administrator permissions (servicecatalog:*)
- IAM permissions to create roles and policies for product launch constraints
- Basic understanding of CloudFormation template structure and AWS resource management
- Estimated cost: $0.50-2.00 for testing (S3 storage, Lambda invocations, minimal CloudFormation stack usage)

> **Note**: Service Catalog itself has no additional charges beyond the underlying AWS resources provisioned through the catalog products.

## Architecture Overview

This solution creates:
- Service Catalog Portfolio for organizing infrastructure templates
- S3 Bucket Product with security best practices (encryption, versioning, access blocking)
- Lambda Function Product with proper IAM roles and CloudWatch logging
- Launch constraints with dedicated IAM roles for secure provisioning
- Portfolio access controls for development teams

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the Service Catalog portfolio and products
aws cloudformation create-stack \
    --stack-name service-catalog-portfolio \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=PortfolioName,ParameterValue=enterprise-infrastructure \
                 ParameterKey=Environment,ParameterValue=development

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name service-catalog-portfolio

# Get portfolio ID from outputs
aws cloudformation describe-stacks \
    --stack-name service-catalog-portfolio \
    --query 'Stacks[0].Outputs[?OutputKey==`PortfolioId`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy ServiceCatalogPortfolioStack

# View deployed resources
cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy ServiceCatalogPortfolioStack

# View stack outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output important resource IDs and ARNs
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PortfolioName` | `enterprise-infrastructure` | Name for the Service Catalog portfolio |
| `Environment` | `development` | Environment tag for all resources |
| `S3ProductName` | `managed-s3-bucket` | Name for the S3 bucket product |
| `LambdaProductName` | `serverless-function` | Name for the Lambda function product |

### CDK Configuration

Both CDK implementations support these configuration options:

```typescript
// In cdk-typescript/app.ts
const config = {
  portfolioName: 'enterprise-infrastructure',
  environment: 'development',
  s3ProductName: 'managed-s3-bucket',
  lambdaProductName: 'serverless-function'
};
```

```python
# In cdk-python/app.py
config = {
    "portfolio_name": "enterprise-infrastructure",
    "environment": "development",
    "s3_product_name": "managed-s3-bucket",
    "lambda_product_name": "serverless-function"
}
```

### Terraform Variables

Configure the deployment by modifying `terraform/terraform.tfvars`:

```hcl
portfolio_name     = "enterprise-infrastructure"
environment       = "development"
s3_product_name   = "managed-s3-bucket"
lambda_product_name = "serverless-function"
aws_region        = "us-east-1"
```

## Validation & Testing

After deployment, validate the Service Catalog setup:

```bash
# List portfolios (replace PORTFOLIO_ID with actual ID from outputs)
aws servicecatalog list-portfolios \
    --query "PortfolioDetails[?DisplayName=='enterprise-infrastructure']"

# Search for available products as end user
aws servicecatalog search-products \
    --query 'ProductViewSummaries[].Name'

# Get launch paths for products
aws servicecatalog list-launch-paths \
    --product-id <PRODUCT_ID> \
    --query 'LaunchPathSummaries[0].Id' --output text
```

## Testing Product Deployment

Test deploying resources through Service Catalog:

```bash
# Launch an S3 bucket through Service Catalog
aws servicecatalog provision-product \
    --product-id <S3_PRODUCT_ID> \
    --provisioning-artifact-id <ARTIFACT_ID> \
    --provisioned-product-name "test-s3-bucket" \
    --provisioning-parameters Key=BucketName,Value=test-bucket-unique-name \
                              Key=Environment,Value=development

# Launch a Lambda function through Service Catalog
aws servicecatalog provision-product \
    --product-id <LAMBDA_PRODUCT_ID> \
    --provisioning-artifact-id <ARTIFACT_ID> \
    --provisioned-product-name "test-lambda-function" \
    --provisioning-parameters Key=FunctionName,Value=test-function \
                              Key=Runtime,Value=python3.12 \
                              Key=Environment,Value=development
```

## Managing Portfolio Access

Grant access to additional users or groups:

```bash
# Associate a user with the portfolio
aws servicecatalog associate-principal-with-portfolio \
    --portfolio-id <PORTFOLIO_ID> \
    --principal-arn "arn:aws:iam::ACCOUNT-ID:user/USERNAME" \
    --principal-type "IAM"

# Associate a group with the portfolio
aws servicecatalog associate-principal-with-portfolio \
    --portfolio-id <PORTFOLIO_ID> \
    --principal-arn "arn:aws:iam::ACCOUNT-ID:group/GROUPNAME" \
    --principal-type "IAM"
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name service-catalog-portfolio

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name service-catalog-portfolio
```

### Using CDK (AWS)

```bash
# Destroy the CDK stack
cdk destroy ServiceCatalogPortfolioStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deletion
```

## Customization

### Adding New Products

To add additional products to the portfolio:

1. Create new CloudFormation templates for your infrastructure patterns
2. Upload templates to the S3 bucket created by the infrastructure
3. Add the new products to your IaC configuration
4. Update launch constraints with appropriate IAM permissions
5. Associate the new products with the portfolio

### Modifying Launch Constraints

Update the launch role permissions in the IAM policy to support additional AWS services:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "rds:*",
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### Template Constraints

Add template constraints to enforce governance policies:

```bash
# Create a template constraint
aws servicecatalog create-constraint \
    --portfolio-id <PORTFOLIO_ID> \
    --product-id <PRODUCT_ID> \
    --type "TEMPLATE" \
    --parameters '{"Rules": {"Rule1": {"Assertions": [{"Assert": {"Fn::Contains": [["t2.micro", "t2.small"], {"Ref": "InstanceType"}]}, "AssertDescription": "Instance type must be t2.micro or t2.small"}]}}}'
```

## Advanced Configuration

### Multi-Environment Setup

Configure different portfolios for different environments:

```bash
# Create environment-specific portfolios
aws servicecatalog create-portfolio \
    --display-name "Production Infrastructure" \
    --description "Production-approved infrastructure templates"

aws servicecatalog create-portfolio \
    --display-name "Development Infrastructure" \
    --description "Development environment templates"
```

### Cross-Account Sharing

Share portfolios across AWS accounts:

```bash
# Create portfolio share
aws servicecatalog create-portfolio-share \
    --portfolio-id <PORTFOLIO_ID> \
    --account-id <TARGET_ACCOUNT_ID>

# Accept share in target account
aws servicecatalog accept-portfolio-share \
    --portfolio-id <PORTFOLIO_ID>
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**
   - Ensure the launch role has permissions for all resources in your templates
   - Verify Service Catalog service role permissions

2. **Template Validation Errors**
   - Validate CloudFormation templates before uploading
   - Check parameter constraints and allowed values

3. **Product Launch Failures**
   - Review CloudFormation stack events for detailed error messages
   - Ensure launch constraints are properly configured

### Debugging Commands

```bash
# Check portfolio access
aws servicecatalog list-accepted-portfolio-shares

# Review product launch history
aws servicecatalog list-provisioned-product-plans

# Check constraint details
aws servicecatalog list-constraints-for-portfolio \
    --portfolio-id <PORTFOLIO_ID>
```

## Security Best Practices

- Use least privilege IAM policies for launch constraints
- Enable CloudTrail logging for Service Catalog actions
- Implement template constraints to enforce security policies
- Regularly review portfolio access and permissions
- Use parameter validation to prevent misconfigurations
- Enable encryption for all S3 buckets storing templates

## Support

For issues with this infrastructure code, refer to:
- [AWS Service Catalog Administrator Guide](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/)
- [CloudFormation Template Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/)
- [Service Catalog Best Practices](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/best-practices.html)
- Original recipe documentation for architectural guidance

## Cost Optimization

- Use S3 Intelligent Tiering for template storage
- Implement lifecycle policies for CloudFormation template versions
- Monitor provisioned product usage and implement cleanup policies
- Use AWS Cost Explorer to track Service Catalog resource costs

## Monitoring and Compliance

Set up monitoring for Service Catalog activities:

```bash
# Create CloudWatch dashboard for Service Catalog metrics
aws cloudwatch put-dashboard \
    --dashboard-name "ServiceCatalog-Dashboard" \
    --dashboard-body file://dashboard-config.json

# Set up SNS notifications for product launch events
aws sns create-topic --name service-catalog-notifications
```