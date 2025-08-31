# Service Catalog Portfolio with CloudFormation Templates - CDK TypeScript

This CDK TypeScript application implements a Service Catalog portfolio containing CloudFormation templates for standardized infrastructure deployment. It creates a governance framework that enables self-service infrastructure deployment while maintaining security controls and organizational standards.

## Architecture

The CDK application creates:

- **Service Catalog Portfolio**: A logical container for organizing related products
- **S3 Bucket Product**: Secure S3 bucket template with encryption, versioning, and public access blocking
- **Lambda Function Product**: Lambda function template with proper IAM roles and CloudWatch logging
- **Launch Constraints**: IAM role with least-privilege permissions for resource provisioning
- **Template Storage**: S3 bucket for storing CloudFormation templates
- **Access Controls**: Portfolio access for specified principals

## Prerequisites

1. **AWS CLI**: Install and configure AWS CLI v2 with appropriate credentials
2. **Node.js**: Version 18.0.0 or later
3. **AWS CDK**: Install globally with `npm install -g aws-cdk`
4. **Permissions**: Your AWS credentials must have permissions to:
   - Create Service Catalog portfolios and products
   - Create IAM roles and policies
   - Create S3 buckets and deploy objects
   - Use CloudFormation

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment (Optional)

Set environment variables for customization:

```bash
export PORTFOLIO_NAME="my-enterprise-infrastructure"
export S3_PRODUCT_NAME="my-managed-s3-bucket"
export LAMBDA_PRODUCT_NAME="my-serverless-function"
export PRINCIPAL_ARN="arn:aws:iam::123456789012:user/developer"
```

### 3. Bootstrap CDK (First time only)

```bash
npm run bootstrap
```

### 4. Deploy the Stack

```bash
npm run deploy
```

The deployment will:
- Create an S3 bucket for CloudFormation templates
- Upload the S3 bucket and Lambda function templates
- Create the Service Catalog portfolio and products
- Set up launch constraints with a dedicated IAM role
- Associate the specified principal with the portfolio (if provided)

### 5. Verify Deployment

After deployment, you can verify the Service Catalog setup:

```bash
# List portfolios
aws servicecatalog list-portfolios

# Search for available products
aws servicecatalog search-products

# Get portfolio details
aws servicecatalog describe-portfolio --id <portfolio-id>
```

## Configuration Options

### Context Parameters

You can pass configuration through CDK context:

```bash
cdk deploy -c portfolioName="MyPortfolio" -c s3ProductName="MyS3Product"
```

### Available Context Parameters

- `portfolioName`: Name of the Service Catalog portfolio
- `s3ProductName`: Display name for the S3 bucket product
- `lambdaProductName`: Display name for the Lambda function product
- `principalArn`: ARN of the user/role to grant portfolio access

### Environment Variables

The application also reads from environment variables:
- `PORTFOLIO_NAME`
- `S3_PRODUCT_NAME`
- `LAMBDA_PRODUCT_NAME`
- `PRINCIPAL_ARN`

## CloudFormation Templates

### S3 Bucket Template

Creates a secure S3 bucket with:
- Server-side encryption (AES256)
- Versioning enabled
- Public access blocked
- Environment-based tagging

**Parameters:**
- `BucketName`: Name for the S3 bucket (lowercase alphanumeric with hyphens)
- `Environment`: Environment tag (development, staging, production)

### Lambda Function Template

Creates a Lambda function with:
- Dedicated IAM execution role
- CloudWatch logging permissions
- Runtime flexibility
- Environment-based tagging

**Parameters:**
- `FunctionName`: Name for the Lambda function
- `Runtime`: Runtime environment (Python 3.11/3.12, Node.js 20.x/22.x)
- `Environment`: Environment tag (development, staging, production)

## Using the Products

Once deployed, end users can:

1. **Access AWS Console**: Navigate to Service Catalog in the AWS Console
2. **Browse Products**: View available products in the portfolio
3. **Launch Products**: Deploy infrastructure using the standardized templates
4. **Manage Resources**: View and manage provisioned products

### Example: Launching S3 Bucket Product

```bash
# Get product details
aws servicecatalog describe-product --id <s3-product-id>

# Launch the product
aws servicecatalog provision-product \
    --product-id <s3-product-id> \
    --provisioning-artifact-id <artifact-id> \
    --provisioned-product-name "my-test-bucket" \
    --provisioning-parameters \
        Key=BucketName,Value=my-test-bucket-12345 \
        Key=Environment,Value=development
```

## Development

### Build and Test

```bash
# Compile TypeScript
npm run build

# Run tests
npm run test

# Watch for changes
npm run watch

# Lint code
npm run lint

# Format code
npm run format
```

### CDK Commands

```bash
# Synthesize CloudFormation template
npm run synth

# Compare deployed stack with current state
npm run diff

# Deploy the stack
npm run deploy

# Destroy the stack
npm run destroy
```

## Security Considerations

### Launch Role Permissions

The CDK creates a launch role with minimal permissions required for:
- Creating and managing S3 buckets
- Creating and managing Lambda functions
- Creating and managing IAM roles

### Template Security

Both CloudFormation templates implement security best practices:
- S3 buckets have encryption and public access blocking
- Lambda functions use dedicated IAM roles
- All resources are tagged for governance

### Access Control

Portfolio access is controlled through IAM principals. Only associated users, groups, or roles can:
- View products in the portfolio
- Launch products
- Manage provisioned products

## Cost Considerations

**Service Catalog**: No additional charges beyond underlying AWS resources

**S3 Bucket**: 
- Storage costs for CloudFormation templates (minimal)
- Request costs for template downloads during product launches

**IAM Roles**: No charges for IAM roles and policies

**Provisioned Products**: Standard AWS charges apply for resources created through the products (S3 buckets, Lambda functions, etc.)

## Cleanup

To remove all resources created by this CDK application:

```bash
npm run destroy
```

This will:
1. Remove the Service Catalog portfolio and products
2. Delete the launch role and policies
3. Remove the templates bucket and its contents
4. Clean up all CDK-created resources

**Note**: Any products provisioned by end users through the Service Catalog will need to be terminated separately before destroying the stack.

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your AWS credentials have the required permissions
2. **Template Upload Failed**: Check S3 bucket permissions and network connectivity
3. **Product Launch Failed**: Verify launch role permissions and template syntax
4. **Stack Deployment Failed**: Review CloudFormation events in the AWS Console

### Useful Commands

```bash
# View CDK logs
cdk deploy --verbose

# Debug synthesis
cdk synth --debug

# View stack events
aws cloudformation describe-stack-events --stack-name ServiceCatalogPortfolioStack
```

## Additional Resources

- [AWS Service Catalog Developer Guide](https://docs.aws.amazon.com/servicecatalog/latest/dg/)
- [AWS CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/api/v2/typescript/)
- [CloudFormation Template Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/)
- [Service Catalog Best Practices](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/best-practices.html)

## Support

For issues related to this CDK application, please review the AWS CDK documentation and Service Catalog guides. For AWS service-specific questions, consult the official AWS documentation or AWS Support.