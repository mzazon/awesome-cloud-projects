# Infrastructure as Code for Developing Secure Multi-Tenant SaaS with Amplify and Fine-Grained Authorization

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developing Secure Multi-Tenant SaaS with Amplify and Fine-Grained Authorization".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a comprehensive multi-tenant SaaS platform with:

- **AWS Amplify** for full-stack application hosting
- **Amazon Cognito** for tenant-aware authentication and user management
- **AWS AppSync** for multi-tenant GraphQL API with fine-grained authorization
- **Amazon DynamoDB** for tenant-isolated data storage
- **AWS Lambda** for tenant management and business logic
- **Amazon S3** for tenant-specific and shared asset storage
- **Amazon CloudWatch** for monitoring and audit trails

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- Appropriate AWS permissions for:
  - Amplify (full access)
  - Cognito (full access)
  - AppSync (full access)
  - DynamoDB (full access)
  - Lambda (full access)
  - IAM (policy and role management)
  - S3 (bucket and object management)
  - CloudWatch (logs and metrics)
- Estimated cost: $50-150/month depending on tenant count and usage

### CDK-Specific Prerequisites

- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- CDK bootstrapping completed in target region:
  ```bash
  cdk bootstrap aws://ACCOUNT-NUMBER/REGION
  ```

### Terraform-Specific Prerequisites

- Terraform v1.0+ installed
- AWS provider credentials configured

## Quick Start

### Using CloudFormation

```bash
# Deploy the multi-tenant infrastructure
aws cloudformation create-stack \
    --stack-name multitenant-saas-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-saas-platform \
                 ParameterKey=Environment,ParameterValue=development \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name multitenant-saas-stack \
    --query 'Stacks[0].StackStatus'

# Get deployment outputs
aws cloudformation describe-stacks \
    --stack-name multitenant-saas-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Preview deployment
cdk diff

# Deploy the multi-tenant infrastructure
cdk deploy MultiTenantSaaSStack \
    --parameters projectName=my-saas-platform \
    --parameters environment=development \
    --require-approval never

# List deployed stacks
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Preview deployment
cdk diff

# Deploy the multi-tenant infrastructure
cdk deploy MultiTenantSaaSStack \
    --parameters projectName=my-saas-platform \
    --parameters environment=development \
    --require-approval never
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_name=my-saas-platform" \
    -var="environment=development" \
    -var="aws_region=us-east-1"

# Apply the configuration
terraform apply \
    -var="project_name=my-saas-platform" \
    -var="environment=development" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set environment variables
export PROJECT_NAME="my-saas-platform"
export ENVIRONMENT="development"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws amplify list-apps --query 'apps[?name==`${PROJECT_NAME}`]'
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `project_name` | Name for the SaaS platform project | `multitenant-saas` | Yes |
| `environment` | Environment (dev, staging, prod) | `development` | Yes |
| `aws_region` | AWS region for deployment | `us-east-1` | Yes |

### Advanced Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `cognito_password_policy` | Password policy configuration | Complex policy | No |
| `dynamodb_billing_mode` | DynamoDB billing mode | `PAY_PER_REQUEST` | No |
| `lambda_memory_size` | Memory allocation for Lambda functions | `512` | No |
| `api_throttle_rate` | API Gateway throttle rate limit | `1000` | No |
| `enable_xray_tracing` | Enable X-Ray tracing | `true` | No |

## Post-Deployment Setup

After successful infrastructure deployment:

### 1. Configure Amplify Application

```bash
# Get Amplify app details
AMPLIFY_APP_ID=$(aws amplify list-apps \
    --query 'apps[?name==`${PROJECT_NAME}`].appId' \
    --output text)

echo "Amplify App ID: ${AMPLIFY_APP_ID}"

# Set up Amplify hosting
aws amplify create-branch \
    --app-id $AMPLIFY_APP_ID \
    --branch-name main \
    --description "Main production branch"
```

### 2. Initialize Cognito User Groups

```bash
# Get User Pool ID
USER_POOL_ID=$(aws cognito-idp list-user-pools \
    --max-results 50 \
    --query "UserPools[?contains(Name, '${PROJECT_NAME}')].Id" \
    --output text)

# Create super admin group
aws cognito-idp create-group \
    --group-name SuperAdmins \
    --user-pool-id $USER_POOL_ID \
    --description "Super administrators with platform-wide access"

# Create sample tenant admin group
aws cognito-idp create-group \
    --group-name TenantAdmins \
    --user-pool-id $USER_POOL_ID \
    --description "Tenant administrators"
```

### 3. Create Initial Super Admin User

```bash
# Create super admin user
aws cognito-idp admin-create-user \
    --user-pool-id $USER_POOL_ID \
    --username superadmin \
    --user-attributes Name=email,Value=admin@yourcompany.com \
                      Name=given_name,Value=Super \
                      Name=family_name,Value=Admin \
    --temporary-password TempPass123! \
    --message-action SUPPRESS

# Add user to super admin group
aws cognito-idp admin-add-user-to-group \
    --user-pool-id $USER_POOL_ID \
    --username superadmin \
    --group-name SuperAdmins
```

### 4. Configure Custom Domain (Optional)

```bash
# Create custom domain for Amplify app
aws amplify create-domain-association \
    --app-id $AMPLIFY_APP_ID \
    --domain-name yourdomain.com \
    --sub-domain-settings prefix=app,branch-name=main
```

## Multi-Tenant Features

### Tenant Isolation

- **Data Isolation**: DynamoDB tables with tenant-based partitioning
- **Authorization**: AppSync authorization rules preventing cross-tenant access
- **User Management**: Cognito groups for tenant-specific access control
- **Storage**: S3 bucket policies for tenant-specific object access

### Fine-Grained Authorization

- **Role-Based Access**: Multiple user roles per tenant (Admin, Manager, User, Viewer)
- **Permission System**: Granular permissions for actions and resources
- **Feature Flags**: Subscription-based feature availability
- **Dynamic Authorization**: JWT token claims for client-side authorization

### Subscription Management

- **Multiple Plans**: Trial, Basic, Professional, Enterprise tiers
- **Usage Tracking**: Real-time monitoring of API calls, storage, and users
- **Billing Integration**: Ready for Stripe/payment processor integration
- **Limit Enforcement**: Automatic enforcement of subscription limits

## Monitoring and Observability

### CloudWatch Integration

```bash
# View application logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/${PROJECT_NAME}"

# Monitor API Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

### Custom Metrics

The infrastructure automatically creates custom metrics for:
- Tenant creation rate
- User registration rate per tenant
- API usage per tenant
- Storage consumption per tenant
- Billing events and revenue tracking

## Security Best Practices

### Implemented Security Features

- **Least Privilege IAM**: Minimal required permissions for all services
- **Encryption**: Data encrypted at rest and in transit
- **VPC Security**: Optional VPC deployment for enhanced network security
- **Audit Logging**: Comprehensive CloudTrail and CloudWatch logging
- **Input Validation**: Lambda function input sanitization
- **CORS Configuration**: Proper cross-origin resource sharing setup

### Additional Security Recommendations

1. **Enable AWS Config** for compliance monitoring
2. **Set up AWS GuardDuty** for threat detection
3. **Configure AWS WAF** for application layer protection
4. **Implement AWS Secrets Manager** for API keys and secrets
5. **Enable AWS Shield** for DDoS protection

## Scaling Considerations

### Automatic Scaling

- **Lambda**: Automatic scaling based on request volume
- **DynamoDB**: On-demand billing with automatic scaling
- **AppSync**: Managed scaling for GraphQL operations
- **Cognito**: Automatic scaling for authentication requests

### Performance Optimization

- **DynamoDB Indexes**: Optimized for multi-tenant query patterns
- **Lambda Memory**: Tuned for optimal cost/performance ratio
- **AppSync Caching**: Configurable query result caching
- **CloudFront**: CDN for static asset delivery

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name multitenant-saas-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name multitenant-saas-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy all resources
cdk destroy MultiTenantSaaSStack --force

# Clean up CDK context
cdk context --clear
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_name=my-saas-platform" \
    -var="environment=development" \
    -var="aws_region=us-east-1"

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
aws amplify list-apps \
    --query 'apps[?name==`${PROJECT_NAME}`]'
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining S3 buckets
aws s3 ls | grep ${PROJECT_NAME} | awk '{print $3}' | \
    xargs -I {} aws s3 rb s3://{} --force

# Delete CloudWatch log groups
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/${PROJECT_NAME}" \
    --query "logGroups[].logGroupName" --output text | \
    xargs -I {} aws logs delete-log-group --log-group-name {}

# Remove IAM roles and policies (if not removed by stack)
aws iam list-roles \
    --query "Roles[?contains(RoleName, '${PROJECT_NAME}')].RoleName" \
    --output text | xargs -I {} aws iam delete-role --role-name {}
```

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Error**
   ```bash
   # Solution: Bootstrap CDK in the target region
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Insufficient Permissions**
   ```bash
   # Verify IAM permissions
   aws sts get-caller-identity
   aws iam simulate-principal-policy \
       --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
       --action-names amplify:CreateApp cognito-idp:CreateUserPool
   ```

3. **Resource Limit Exceeded**
   ```bash
   # Check service quotas
   aws service-quotas get-service-quota \
       --service-code lambda \
       --quota-code L-B99A9384  # Concurrent executions
   ```

4. **Amplify Build Failures**
   ```bash
   # Check build logs
   aws amplify list-jobs \
       --app-id $AMPLIFY_APP_ID \
       --branch-name main
   ```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# For CDK
export CDK_DEBUG=true

# For Terraform
export TF_LOG=DEBUG

# For AWS CLI
export AWS_CLI_FILE_ENCODING=UTF-8
aws configure set cli_follow_redirects false
aws configure set max_bandwidth 1GB/s
aws configure set max_concurrent_requests 20
```

## Cost Optimization

### Expected Monthly Costs (Development)

- **Amplify**: ~$5-15 (hosting and builds)
- **Cognito**: ~$0-25 (based on monthly active users)
- **AppSync**: ~$4-12 (based on requests and operations)
- **DynamoDB**: ~$5-20 (on-demand pricing)
- **Lambda**: ~$2-10 (based on invocations)
- **S3**: ~$1-5 (storage and requests)
- **CloudWatch**: ~$2-8 (logs and metrics)

### Cost Optimization Tips

1. **Use DynamoDB On-Demand**: Pay only for actual usage
2. **Optimize Lambda Memory**: Right-size for your workload
3. **Enable S3 Intelligent Tiering**: Automatic cost optimization
4. **Set CloudWatch Log Retention**: Prevent indefinite log storage
5. **Monitor with AWS Cost Explorer**: Track spending patterns

## Support and Documentation

### Additional Resources

- [AWS Amplify Documentation](https://docs.amplify.aws/)
- [Amazon Cognito Developer Guide](https://docs.aws.amazon.com/cognito/)
- [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/)
- [Multi-Tenant SaaS Best Practices](https://aws.amazon.com/solutions/guidance/saas-on-aws/)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Check AWS service health dashboard
4. Refer to the original recipe documentation
5. Contact AWS support for service-specific issues

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any parameter changes
4. Validate with multiple deployment methods
5. Test cleanup procedures thoroughly