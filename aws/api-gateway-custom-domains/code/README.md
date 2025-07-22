# Infrastructure as Code for API Gateway with Custom Domain Names

This directory contains Infrastructure as Code (IaC) implementations for the recipe "API Gateway with Custom Domain Names".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate IAM permissions for creating API Gateway, Lambda, Certificate Manager, and Route 53 resources
- A registered domain name that you control
- Basic knowledge of REST APIs and DNS concepts
- For CDK implementations: Node.js 14.x or later (TypeScript) or Python 3.7+ (Python)
- For Terraform: Terraform v1.0 or later

### Required AWS Permissions

Your AWS credentials need permissions for:
- API Gateway (create/manage REST APIs, custom domains, stages)
- AWS Lambda (create/manage functions and permissions)
- AWS Certificate Manager (request/manage SSL certificates)
- Route 53 (manage DNS records and hosted zones)
- IAM (create/manage roles and policies)
- CloudWatch Logs (create/manage log groups)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name api-gateway-custom-domain \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=example.com \
                 ParameterKey=ApiSubdomain,ParameterValue=api.example.com \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name api-gateway-custom-domain

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name api-gateway-custom-domain \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure your domain (edit cdk.json or pass as context)
npx cdk deploy \
    --context domainName=example.com \
    --context apiSubdomain=api.example.com

# View outputs
npx cdk deploy --outputs-file outputs.json
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt

# Deploy with domain configuration
cdk deploy \
    --context domainName=example.com \
    --context apiSubdomain=api.example.com

# View stack outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review and customize terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your domain settings

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export DOMAIN_NAME="example.com"
export API_SUBDOMAIN="api.example.com"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment outputs
./scripts/deploy.sh --show-outputs
```

## Important Notes

### SSL Certificate Validation

After deployment, you must validate your SSL certificate:

1. **Manual DNS Validation**: Add the DNS validation record provided in the outputs to your domain's DNS settings
2. **Automatic Validation**: If using Route 53 for DNS, the certificate validation may be automated depending on your implementation

### Domain Configuration

- Ensure your domain's DNS is configured to use the Route 53 name servers if you're using Route 53 for DNS management
- For domains managed outside Route 53, you'll need to manually create the required DNS records as shown in the deployment outputs

### API Testing

Once deployed, test your API endpoints:

```bash
# Test unauthorized access (should return 401)
curl -v https://api.example.com/pets

# Test authorized access
curl -v -H "Authorization: Bearer valid-token" \
    https://api.example.com/pets

# Test POST request
curl -v -X POST \
    -H "Authorization: Bearer valid-token" \
    -H "Content-Type: application/json" \
    -d '{"name":"Fluffy","type":"cat"}' \
    https://api.example.com/pets
```

## Customization

### CloudFormation Parameters

- `DomainName`: Your root domain name (e.g., example.com)
- `ApiSubdomain`: API subdomain (e.g., api.example.com)
- `Environment`: Deployment environment (dev, staging, prod)
- `EnableLogging`: Enable CloudWatch logging for API Gateway

### CDK Context Variables

- `domainName`: Your root domain name
- `apiSubdomain`: API subdomain
- `environment`: Deployment environment
- `enableXRayTracing`: Enable AWS X-Ray tracing

### Terraform Variables

Edit `terraform.tfvars` to customize:

```hcl
domain_name     = "example.com"
api_subdomain   = "api.example.com"
environment     = "production"
enable_logging  = true
rate_limit      = 100
burst_limit     = 200
```

### Bash Script Environment Variables

```bash
export DOMAIN_NAME="example.com"
export API_SUBDOMAIN="api.example.com"
export AWS_REGION="us-east-1"
export ENVIRONMENT="production"
export ENABLE_THROTTLING="true"
export RATE_LIMIT="100"
export BURST_LIMIT="200"
```

## Architecture Overview

The deployed infrastructure includes:

- **API Gateway REST API** with custom domain configuration
- **Lambda Functions** for API backend logic and custom authorization
- **SSL Certificate** managed by AWS Certificate Manager
- **Route 53 DNS Records** for domain routing
- **IAM Roles and Policies** following least privilege principles
- **CloudWatch Log Groups** for monitoring and debugging
- **API Gateway Stages** for environment separation (dev/prod)

## Monitoring and Logs

### CloudWatch Logs

- API Gateway execution logs: `/aws/apigateway/{api-name}`
- Lambda function logs: `/aws/lambda/{function-name}`

### CloudWatch Metrics

Monitor these key metrics:
- API Gateway: `4XXError`, `5XXError`, `Count`, `Latency`
- Lambda: `Duration`, `Errors`, `Throttles`

### X-Ray Tracing

If enabled, view distributed tracing in the AWS X-Ray console to analyze request flows and performance bottlenecks.

## Security Considerations

- **SSL/TLS**: All API traffic is encrypted using AWS-managed SSL certificates
- **Authentication**: Custom authorizer validates bearer tokens
- **Throttling**: Rate limiting protects against abuse
- **IAM**: Least privilege access for all AWS resources
- **CORS**: Configured for secure cross-origin requests

## Troubleshooting

### Common Issues

1. **Certificate Validation Pending**: Ensure DNS validation record is added to your domain
2. **Domain Not Resolving**: Check DNS propagation (may take up to 48 hours)
3. **403 Forbidden**: Verify custom authorizer logic and token format
4. **5XX Errors**: Check Lambda function logs in CloudWatch

### Debug Commands

```bash
# Check certificate status
aws acm describe-certificate --certificate-arn <certificate-arn>

# Test API Gateway endpoint
aws apigateway test-invoke-method \
    --rest-api-id <api-id> \
    --resource-id <resource-id> \
    --http-method GET

# Check DNS resolution
nslookup api.example.com
dig api.example.com CNAME
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name api-gateway-custom-domain

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name api-gateway-custom-domain
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
source venv/bin/activate
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup

If automated cleanup fails, manually delete these resources in order:

1. API Gateway custom domain name mappings
2. API Gateway custom domain name
3. API Gateway REST API
4. Lambda functions
5. IAM roles and policies
6. SSL certificate (ACM)
7. Route 53 DNS records
8. CloudWatch log groups

## Cost Optimization

- **API Gateway**: Pay per API call and data transfer
- **Lambda**: Pay per invocation and execution time
- **Route 53**: $0.50 per hosted zone per month + query charges
- **Certificate Manager**: Free for ACM certificates used with AWS services
- **CloudWatch Logs**: Pay for log ingestion and storage

### Cost Monitoring

Set up billing alerts for:
- API Gateway request charges
- Lambda invocation costs
- Data transfer costs
- CloudWatch log retention costs

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architectural guidance
2. Check AWS service documentation for specific service configurations
3. Review CloudFormation/CDK/Terraform documentation for syntax and best practices
4. Check AWS support forums and Stack Overflow for common issues

## Additional Resources

- [AWS API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [AWS Certificate Manager User Guide](https://docs.aws.amazon.com/acm/latest/userguide/)
- [Amazon Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [API Gateway Custom Domain Setup](https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-custom-domains.html)