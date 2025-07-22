# Multi-Tenant SaaS Infrastructure with Terraform

This Terraform configuration deploys a complete multi-tenant SaaS application infrastructure on AWS, featuring fine-grained authorization, tenant isolation, and enterprise-grade security.

## Architecture Overview

The infrastructure implements a comprehensive multi-tenant SaaS platform with:

- **Amazon Cognito** for tenant-aware authentication and user management
- **AWS AppSync** for GraphQL API with fine-grained authorization rules
- **DynamoDB** tables with tenant partitioning for data isolation
- **Lambda functions** for tenant management and authentication triggers
- **S3 buckets** for tenant-specific asset storage
- **CloudWatch** for monitoring and logging
- **KMS** for encryption at rest

## Features

### Multi-Tenancy
- Complete tenant isolation with data partitioning
- Tenant-specific user management and role-based access control
- Subscription plan enforcement and usage tracking
- Custom tenant branding and configuration

### Security
- Fine-grained authorization rules at the GraphQL level
- Tenant-aware Lambda triggers for authentication flow
- Encryption at rest using AWS KMS
- Comprehensive audit logging and activity tracking

### Scalability
- Serverless architecture with automatic scaling
- Pay-per-request DynamoDB billing (configurable)
- CloudWatch monitoring with custom metrics
- X-Ray tracing for performance optimization

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5 installed
- Sufficient AWS permissions for:
  - IAM roles and policies
  - DynamoDB table creation
  - Lambda function deployment
  - Cognito User Pool management
  - AppSync API creation
  - S3 bucket management
  - KMS key management
  - CloudWatch resources

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize for your environment:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:

```hcl
# Core Configuration
project_name = "my-saas-platform"
environment  = "dev"
aws_region   = "us-east-1"

# Cognito Configuration
cognito_domain_prefix = "my-saas-auth"
cognito_callback_urls = ["https://my-app.com/auth/callback"]
cognito_logout_urls   = ["https://my-app.com/"]

# Security Configuration
enable_deletion_protection = false  # Set to true for production
enable_xray_tracing       = true
enable_enhanced_monitoring = true

# Cost Optimization
enable_cost_optimization = true
dynamodb_billing_mode    = "PAY_PER_REQUEST"
```

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Configure Your Application

After successful deployment, use the outputs to configure your frontend application:

```bash
# Get the Amplify configuration
terraform output amplify_configuration
```

## Configuration

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Name of the project | `"multitenant-saas"` | No |
| `environment` | Deployment environment | `"dev"` | No |
| `aws_region` | AWS region | `"us-east-1"` | No |
| `cognito_domain_prefix` | Cognito hosted UI domain prefix | `null` | No |
| `enable_deletion_protection` | Enable deletion protection | `false` | No |
| `enable_xray_tracing` | Enable X-Ray tracing | `true` | No |
| `lambda_runtime` | Lambda runtime version | `"nodejs18.x"` | No |
| `dynamodb_billing_mode` | DynamoDB billing mode | `"PAY_PER_REQUEST"` | No |

### Default Tenant Settings

The infrastructure includes configurable tenant limits:

```hcl
default_tenant_settings = {
  max_users_trial        = 5
  max_users_basic        = 25
  max_users_professional = 100
  max_users_enterprise   = 1000
  max_projects_trial     = 3
  max_projects_basic     = 10
  max_projects_professional = 50
  max_projects_enterprise   = 500
  # ... additional settings
}
```

## Security Considerations

### Authentication & Authorization
- Multi-factor authentication enforced through Cognito
- Tenant-aware JWT tokens with custom claims
- Fine-grained GraphQL authorization rules
- Role-based access control with permission granularity

### Data Protection
- All data encrypted at rest using AWS KMS
- S3 buckets configured with public access blocks
- DynamoDB point-in-time recovery enabled
- Comprehensive audit logging with TTL

### Network Security
- VPC endpoints can be configured for private API access
- CloudFront integration supported for CDN and WAF protection
- Rate limiting enforced at API Gateway level

## Monitoring & Observability

### CloudWatch Integration
- Structured logging for all Lambda functions
- Custom metrics for tenant usage tracking
- Automated alarms for error rates and throttling
- Dashboard creation for operational visibility

### X-Ray Tracing
- End-to-end request tracing enabled
- Performance bottleneck identification
- Service map visualization
- Error rate analysis

## Cost Optimization

### DynamoDB
- Pay-per-request billing by default
- Auto-scaling for provisioned mode
- TTL configured for log data cleanup

### Lambda
- Right-sized memory allocation
- Efficient code packaging
- CloudWatch log retention policies

### S3
- Lifecycle policies for cost optimization
- Intelligent tiering for automatic cost optimization
- Versioning with cleanup policies

## Deployment Patterns

### Development Environment
```bash
terraform workspace new dev
terraform apply -var="environment=dev" -var="enable_deletion_protection=false"
```

### Staging Environment
```bash
terraform workspace new staging
terraform apply -var="environment=staging" -var="enable_deletion_protection=true"
```

### Production Environment
```bash
terraform workspace new prod
terraform apply -var="environment=prod" -var="enable_deletion_protection=true"
```

## Multi-Tenant Operations

### Creating a New Tenant

Use the GraphQL API to create tenants:

```graphql
mutation CreateTenant {
  createTenant(input: {
    name: "Acme Corporation"
    domain: "acme.com"
    subdomain: "acme"
    plan: PROFESSIONAL
    adminEmail: "admin@acme.com"
    adminName: "John Admin"
  }) {
    id
    name
    status
    subdomain
  }
}
```

### User Management

Provision users for tenants:

```graphql
mutation ProvisionUser {
  provisionTenantUser(input: {
    tenantId: "tenant-id"
    email: "user@acme.com"
    firstName: "Jane"
    lastName: "Doe"
    role: DEVELOPER
    tempPassword: "TempPass123!"
  }) {
    id
    email
    role
  }
}
```

### Tenant Configuration

Update tenant settings:

```graphql
mutation UpdateTenantSettings {
  updateTenantSettings(
    tenantId: "tenant-id"
    settings: {
      maxUsers: 50
      apiRateLimit: 1000
      allowedFeatures: ["advanced_analytics", "integrations"]
    }
  ) {
    id
    settings {
      maxUsers
      apiRateLimit
      allowedFeatures
    }
  }
}
```

## Troubleshooting

### Common Issues

#### Lambda Function Errors
```bash
# Check Lambda logs
aws logs describe-log-streams --log-group-name "/aws/lambda/tenant-resolver"
aws logs get-log-events --log-group-name "/aws/lambda/tenant-resolver" --log-stream-name "STREAM_NAME"
```

#### DynamoDB Access Issues
```bash
# Verify table permissions
aws dynamodb describe-table --table-name tenant-table-name
aws iam simulate-principal-policy --policy-source-arn ROLE_ARN --action-names dynamodb:GetItem
```

#### Cognito Authentication Issues
```bash
# Check user pool configuration
aws cognito-idp describe-user-pool --user-pool-id USER_POOL_ID
aws cognito-idp list-users --user-pool-id USER_POOL_ID
```

### Performance Optimization

#### DynamoDB
- Monitor read/write capacity metrics
- Optimize GSI design for query patterns
- Use DynamoDB Accelerator (DAX) for high-traffic scenarios

#### Lambda
- Monitor cold start metrics
- Optimize package size and dependencies
- Consider provisioned concurrency for critical functions

## Maintenance

### Backup Strategy
- DynamoDB point-in-time recovery (7-35 days)
- S3 versioning for critical assets
- Lambda function versioning and aliases

### Updates and Patches
- Regular Terraform provider updates
- Lambda runtime updates
- Security patch application

### Capacity Planning
- Monitor tenant growth and usage patterns
- Plan for DynamoDB scaling requirements
- Review Lambda concurrency limits

## Cleanup

To destroy all resources:

```bash
# Disable deletion protection first if enabled
terraform apply -var="enable_deletion_protection=false"

# Destroy all resources
terraform destroy
```

**Warning**: This will permanently delete all data. Ensure you have proper backups before proceeding.

## Support and Documentation

### AWS Services Documentation
- [Amazon Cognito Developer Guide](https://docs.aws.amazon.com/cognito/)
- [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)

### Multi-Tenant Best Practices
- [AWS Multi-Tenant SaaS Architecture](https://aws.amazon.com/solutions/multi-tenant-saas/)
- [SaaS Tenant Isolation Strategies](https://docs.aws.amazon.com/whitepapers/latest/saas-tenant-isolation-strategies/)

## Contributing

This infrastructure is designed to be extensible and customizable. Key areas for enhancement:

1. **Additional Authentication Providers**: SAML, OIDC integration
2. **Advanced Analytics**: Enhanced usage tracking and reporting
3. **Geographic Distribution**: Multi-region deployment patterns
4. **Compliance Features**: GDPR, SOX, HIPAA compliance modules
5. **Performance Optimizations**: Caching layers, CDN integration

## License

This infrastructure code is provided as-is for educational and production use. Please review and test thoroughly before deploying to production environments.