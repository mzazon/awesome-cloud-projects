# Infrastructure as Code for Developing Progressive Web Applications with AWS Amplify

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developing Progressive Web Applications with AWS Amplify".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- Amplify CLI installed globally (`npm install -g @aws-amplify/cli`)
- Git repository for version control
- Appropriate AWS permissions for:
  - AWS Amplify (full access)
  - Amazon Cognito (create user pools and identity pools)
  - AWS AppSync (create GraphQL APIs)
  - Amazon DynamoDB (create tables)
  - Amazon S3 (create buckets)
  - AWS CloudFormation (create stacks)
  - AWS IAM (create roles and policies)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name progressive-web-app-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AppName,ParameterValue=my-pwa-app \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name progressive-web-app-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name progressive-web-app-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters appName=my-pwa-app

# View outputs
cdk list
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters appName=my-pwa-app

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat > terraform.tfvars << 'EOF'
app_name = "my-pwa-app"
environment = "dev"
region = "us-east-1"
EOF

# Review the plan
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

# Set required environment variables
export APP_NAME="my-pwa-app"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Architecture Overview

This infrastructure deploys a complete Progressive Web Application stack including:

### Authentication Layer
- **Amazon Cognito User Pool**: User authentication and management
- **Amazon Cognito Identity Pool**: Federated identities for AWS service access
- **IAM Roles**: Fine-grained access control for authenticated and unauthenticated users

### API Layer
- **AWS AppSync**: Managed GraphQL API with real-time subscriptions
- **DynamoDB**: NoSQL database for application data
- **Lambda Functions**: Custom business logic and data processing

### Storage Layer
- **Amazon S3**: Object storage for file uploads and static assets
- **DynamoDB**: Primary data store with automatic scaling

### Frontend Layer
- **AWS Amplify Hosting**: Managed hosting with global CDN
- **CloudFront**: Content delivery network for optimal performance
- **Build Pipeline**: Automated deployment from Git repository

### Monitoring & Security
- **CloudWatch**: Logging and monitoring for all services
- **IAM Policies**: Least privilege access control
- **VPC Endpoints**: Secure communication between services

## Deployment Options

### Development Environment

```bash
# Deploy with development settings
export ENVIRONMENT=dev
export ENABLE_LOGGING=true
export CORS_ORIGIN="http://localhost:3000"

# For CloudFormation
aws cloudformation create-stack \
    --stack-name pwa-dev-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# For Terraform
terraform apply -var="environment=dev" -var="enable_logging=true"
```

### Production Environment

```bash
# Deploy with production settings
export ENVIRONMENT=prod
export ENABLE_LOGGING=false
export CORS_ORIGIN="https://your-domain.com"

# For CloudFormation
aws cloudformation create-stack \
    --stack-name pwa-prod-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=prod \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# For Terraform
terraform apply -var="environment=prod" -var="enable_logging=false"
```

## Configuration Options

### Common Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `app_name` | Application name used for resource naming | `progressive-web-app` | Yes |
| `environment` | Environment name (dev/staging/prod) | `dev` | Yes |
| `region` | AWS region for deployment | `us-east-1` | Yes |
| `enable_logging` | Enable detailed CloudWatch logging | `true` | No |
| `cors_origin` | CORS origin for API requests | `*` | No |

### Advanced Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cognito_password_policy` | Password policy for user pool | Standard | No |
| `dynamodb_billing_mode` | DynamoDB billing mode | `PAY_PER_REQUEST` | No |
| `appsync_log_level` | AppSync logging level | `ERROR` | No |
| `s3_versioning` | Enable S3 object versioning | `false` | No |

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name progressive-web-app-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name progressive-web-app-stack

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name progressive-web-app-stack
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm destruction when prompted
```

## Post-Deployment Setup

### Frontend Application Setup

1. **Clone your React application repository**:
   ```bash
   git clone https://github.com/your-username/your-pwa-app.git
   cd your-pwa-app
   ```

2. **Install Amplify CLI and initialize**:
   ```bash
   npm install -g @aws-amplify/cli
   amplify pull --appId YOUR_APP_ID --envName dev
   ```

3. **Configure Amplify in your application**:
   ```javascript
   import { Amplify } from 'aws-amplify';
   import awsExports from './aws-exports';
   
   Amplify.configure(awsExports);
   ```

### GraphQL Schema Setup

1. **Update your GraphQL schema**:
   ```graphql
   type Task @model @auth(rules: [{allow: owner}]) {
     id: ID!
     title: String!
     description: String
     completed: Boolean!
     priority: Priority!
     dueDate: AWSDate
     createdAt: AWSDateTime!
     updatedAt: AWSDateTime!
   }
   
   enum Priority {
     LOW
     MEDIUM
     HIGH
   }
   ```

2. **Deploy schema changes**:
   ```bash
   amplify push
   ```

### Testing the Deployment

1. **Test authentication**:
   ```bash
   # Test user signup
   aws cognito-idp admin-create-user \
       --user-pool-id YOUR_USER_POOL_ID \
       --username testuser \
       --temporary-password TempPassword123!
   ```

2. **Test GraphQL API**:
   ```bash
   # Test API endpoint
   curl -X POST \
       -H "Content-Type: application/json" \
       -H "Authorization: Bearer YOUR_JWT_TOKEN" \
       -d '{"query": "query { listTasks { items { id title } } }"}' \
       YOUR_GRAPHQL_ENDPOINT
   ```

3. **Test S3 storage**:
   ```bash
   # List bucket contents
   aws s3 ls s3://YOUR_BUCKET_NAME/
   ```

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View Amplify build logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/amplify"

# View AppSync logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/appsync"

# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda"
```

### Common Issues

1. **Authentication errors**: Check Cognito user pool configuration
2. **API errors**: Verify AppSync GraphQL schema and resolvers
3. **Storage errors**: Check S3 bucket permissions and CORS settings
4. **Build failures**: Review Amplify build settings and environment variables

### Health Checks

```bash
# Check Amplify app status
aws amplify get-app --app-id YOUR_APP_ID

# Check Cognito user pool status
aws cognito-idp describe-user-pool --user-pool-id YOUR_USER_POOL_ID

# Check AppSync API status
aws appsync get-graphql-api --api-id YOUR_API_ID
```

## Security Considerations

### IAM Policies

All IaC implementations follow the principle of least privilege:

- **Authenticated users**: Can create, read, update, and delete their own data
- **Unauthenticated users**: Read-only access to public resources
- **Service roles**: Minimal permissions required for operation

### Data Protection

- **Encryption at rest**: Enabled for DynamoDB and S3
- **Encryption in transit**: All API communications use HTTPS
- **Access logging**: CloudTrail logging enabled for audit trails

### Network Security

- **VPC configuration**: Optional VPC deployment for enhanced isolation
- **Security groups**: Restrictive inbound/outbound rules
- **CORS configuration**: Proper origin restrictions

## Cost Optimization

### Free Tier Usage

- **AWS Amplify**: 1,000 build minutes per month
- **Amazon Cognito**: 50,000 MAUs free
- **AWS AppSync**: 250,000 queries per month
- **Amazon DynamoDB**: 25 GB storage + 25 WCU/RCU
- **Amazon S3**: 5 GB storage + 20,000 GET requests

### Cost Monitoring

```bash
# Set up billing alerts
aws budgets create-budget \
    --account-id YOUR_ACCOUNT_ID \
    --budget file://budget.json
```

## Customization

### Environment Variables

Each implementation supports customization through environment variables:

```bash
# Development environment
export ENVIRONMENT=dev
export LOG_LEVEL=DEBUG
export CORS_ORIGIN=http://localhost:3000

# Production environment
export ENVIRONMENT=prod
export LOG_LEVEL=ERROR
export CORS_ORIGIN=https://your-domain.com
```

### Resource Naming

Resources are named using a consistent pattern:
- Format: `{app_name}-{environment}-{resource_type}-{random_suffix}`
- Example: `my-pwa-app-dev-user-pool-a1b2c3`

### Custom Domains

To use a custom domain:

1. **Register domain in Route 53**
2. **Request SSL certificate in ACM**
3. **Update Amplify domain settings**

```bash
# Add custom domain to Amplify app
aws amplify create-domain-association \
    --app-id YOUR_APP_ID \
    --domain-name your-domain.com \
    --sub-domain-settings prefix=www,branch-name=main
```

## Support

For issues with this infrastructure code:

1. **Check the original recipe documentation** for implementation details
2. **Review AWS documentation** for service-specific guidance
3. **Consult the troubleshooting section** for common issues
4. **Check CloudWatch logs** for detailed error messages

## Contributing

To contribute improvements to this IaC:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This infrastructure code is provided under the same license as the original recipe.