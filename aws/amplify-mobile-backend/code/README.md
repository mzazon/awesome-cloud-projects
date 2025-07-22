# Infrastructure as Code for Amplify Mobile Backend with Authentication and APIs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Amplify Mobile Backend with Authentication and APIs".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a complete mobile backend using AWS Amplify with:
- Amazon Cognito for user authentication and authorization
- AWS AppSync for GraphQL API with real-time subscriptions
- Amazon DynamoDB for NoSQL data storage
- Amazon S3 for file storage with user-specific access controls
- Amazon Pinpoint for analytics and push notifications
- AWS Lambda for custom business logic processing

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 16.x or later and npm installed
- Amplify CLI installed globally (`npm install -g @aws-amplify/cli`)
- Appropriate AWS permissions for:
  - Amplify
  - Cognito (User Pools and Identity Pools)
  - AppSync
  - DynamoDB
  - S3
  - Lambda
  - Pinpoint
  - CloudFormation
  - IAM

## Quick Start

### Using CloudFormation
```bash
# Set environment variables
export PROJECT_NAME="mobile-backend-$(date +%s)"
export AWS_REGION="us-east-1"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name ${PROJECT_NAME}-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=${PROJECT_NAME} \
               ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region ${AWS_REGION}

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name ${PROJECT_NAME}-stack \
    --region ${AWS_REGION}

echo "✅ CloudFormation stack deployed successfully"
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done before)
cdk bootstrap

# Set environment variables
export PROJECT_NAME="mobile-backend-$(date +%s)"
export CDK_DEFAULT_REGION="us-east-1"

# Deploy the stack
cdk deploy --require-approval never

echo "✅ CDK TypeScript stack deployed successfully"
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done before)
cdk bootstrap

# Set environment variables
export PROJECT_NAME="mobile-backend-$(date +%s)"
export CDK_DEFAULT_REGION="us-east-1"

# Deploy the stack
cdk deploy --require-approval never

echo "✅ CDK Python stack deployed successfully"
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Set variables
export TF_VAR_project_name="mobile-backend-$(date +%s)"
export TF_VAR_aws_region="us-east-1"
export TF_VAR_environment="dev"

# Plan deployment
terraform plan

# Apply configuration
terraform apply -auto-approve

echo "✅ Terraform infrastructure deployed successfully"
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_NAME="mobile-backend-$(date +%s)"
export AWS_REGION="us-east-1"
export ENVIRONMENT="dev"

# Deploy infrastructure
./scripts/deploy.sh

echo "✅ Bash script deployment completed successfully"
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to configure your mobile application:

### 1. Install Amplify Libraries
```bash
# For React Native
npm install aws-amplify aws-amplify-react-native \
    amazon-cognito-identity-js @react-native-async-storage/async-storage \
    @react-native-community/netinfo react-native-get-random-values

# For iOS apps using React Native
cd ios && pod install && cd ..
```

### 2. Configure Amplify in Your App
```javascript
import { Amplify } from 'aws-amplify';
import config from './aws-exports'; // Generated after deployment

Amplify.configure(config);
```

### 3. Configure Push Notifications (Optional)
```bash
# For FCM (Android)
# Add your FCM server key to Amazon Pinpoint console

# For APNS (iOS)
# Upload your APNs certificate or key to Amazon Pinpoint console
```

## Validation & Testing

### Test Authentication
```bash
# Get User Pool details
aws cognito-idp list-user-pools --max-results 50 \
    --query "UserPools[?contains(Name, '${PROJECT_NAME}')]"

# Test user registration (replace with actual pool ID)
aws cognito-idp admin-create-user \
    --user-pool-id YOUR_USER_POOL_ID \
    --username testuser \
    --user-attributes Name=email,Value=test@example.com \
    --temporary-password TempPass123! \
    --message-action SUPPRESS
```

### Test GraphQL API
```bash
# Get AppSync API details
aws appsync list-graphql-apis \
    --query "graphqlApis[?contains(name, '${PROJECT_NAME}')]"

# Download schema
aws appsync get-introspection-schema \
    --api-id YOUR_API_ID \
    --format SDL \
    --output text > schema.graphql

echo "GraphQL schema downloaded to schema.graphql"
```

### Test File Storage
```bash
# List S3 buckets created
aws s3 ls | grep ${PROJECT_NAME}

# Test bucket access (replace with actual bucket name)
aws s3 ls s3://YOUR_BUCKET_NAME/
```

### Test Analytics and Notifications
```bash
# Get Pinpoint application details
aws pinpoint get-apps \
    --query "ApplicationsResponse.Item[?contains(Name, '${PROJECT_NAME}')]"
```

## Monitoring and Observability

### CloudWatch Dashboards
Each implementation creates CloudWatch dashboards for monitoring:
- API request metrics and error rates
- Authentication success/failure rates
- Lambda function performance
- DynamoDB read/write capacity utilization
- S3 storage metrics

### Accessing Logs
```bash
# View AppSync logs
aws logs describe-log-groups --log-group-name-prefix "/aws/appsync"

# View Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda"

# View Cognito logs
aws logs describe-log-groups --log-group-name-prefix "/aws/cognito"
```

## Cost Optimization

### Estimated Monthly Costs (Development Environment)
- **Amazon Cognito**: $0 (50,000 MAUs free tier)
- **AWS AppSync**: ~$5-10 (100,000 requests/month)
- **Amazon DynamoDB**: ~$2-5 (25 GB storage, on-demand pricing)
- **Amazon S3**: ~$1-3 (10 GB storage)
- **AWS Lambda**: ~$1-2 (100,000 requests/month)
- **Amazon Pinpoint**: ~$1-2 (basic analytics)

**Total Estimated**: $10-22/month for development workloads

### Cost Optimization Tips
- Use DynamoDB on-demand billing for unpredictable workloads
- Configure S3 lifecycle policies for long-term storage
- Set up CloudWatch billing alarms
- Use AWS Cost Explorer to track spending

## Security Considerations

### Authentication & Authorization
- Cognito User Pools provide secure user authentication
- Fine-grained access controls through IAM roles
- JWT tokens for secure API access
- Multi-factor authentication support

### Data Protection
- Encryption at rest for DynamoDB tables
- S3 bucket encryption with AWS KMS
- TLS 1.2+ for data in transit
- User-specific data isolation

### Best Practices Implemented
- Least privilege IAM policies
- Resource-based access controls
- CloudTrail logging for audit trails
- VPC endpoints for private communication (where applicable)

## Troubleshooting

### Common Issues

1. **Deployment Timeout**
   ```bash
   # Check CloudFormation events
   aws cloudformation describe-stack-events --stack-name ${PROJECT_NAME}-stack
   ```

2. **Permission Errors**
   ```bash
   # Verify IAM permissions
   aws sts get-caller-identity
   aws iam get-user
   ```

3. **Resource Limits**
   ```bash
   # Check service quotas
   aws service-quotas list-service-quotas --service-code cognito-idp
   aws service-quotas list-service-quotas --service-code appsync
   ```

### Debug Mode
Enable debug logging for troubleshooting:
```bash
export AWS_CLI_FILE_ENCODING=UTF-8
export AWS_DEFAULT_OUTPUT=json
aws configure set cli_pager ""
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ${PROJECT_NAME}-stack \
    --region ${AWS_REGION}

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ${PROJECT_NAME}-stack \
    --region ${AWS_REGION}

echo "✅ CloudFormation stack deleted successfully"
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force

echo "✅ CDK TypeScript stack destroyed successfully"
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy --force

echo "✅ CDK Python stack destroyed successfully"
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve

echo "✅ Terraform infrastructure destroyed successfully"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh

echo "✅ Bash script cleanup completed successfully"
```

## Customization

### Environment-Specific Configuration

#### Development Environment
```bash
export ENVIRONMENT="dev"
export DDB_BILLING_MODE="PAY_PER_REQUEST"
export S3_VERSIONING="Disabled"
```

#### Production Environment
```bash
export ENVIRONMENT="prod"
export DDB_BILLING_MODE="PROVISIONED"
export S3_VERSIONING="Enabled"
export ENABLE_BACKUP="true"
export ENABLE_MONITORING="true"
```

### Custom Domain Configuration
To use custom domains with your mobile backend:

1. Register domain in Route 53 or configure DNS
2. Request SSL certificate in ACM
3. Configure custom domain in AppSync
4. Update mobile app configuration

### Multi-Environment Deployment
```bash
# Deploy to different environments
export ENVIRONMENT="staging"
terraform workspace new staging
terraform apply -var="environment=staging"

export ENVIRONMENT="production"
terraform workspace new production
terraform apply -var="environment=production"
```

## Integration with Mobile Frameworks

### React Native Integration
```javascript
// App.js
import { Amplify } from 'aws-amplify';
import { withAuthenticator } from 'aws-amplify-react-native';
import awsExports from './aws-exports';

Amplify.configure(awsExports);

const App = () => {
  // Your app component
};

export default withAuthenticator(App);
```

### iOS Swift Integration
```swift
import Amplify
import AmplifyPlugins

func configureAmplify() {
    do {
        try Amplify.add(plugin: AWSCognitoAuthPlugin())
        try Amplify.add(plugin: AWSAPIPlugin())
        try Amplify.add(plugin: AWSS3StoragePlugin())
        try Amplify.configure()
    } catch {
        print("Failed to initialize Amplify: \(error)")
    }
}
```

### Android Kotlin Integration
```kotlin
import com.amplifyframework.AmplifyException
import com.amplifyframework.auth.cognito.AWSCognitoAuthPlugin
import com.amplifyframework.api.aws.AWSApiPlugin
import com.amplifyframework.storage.s3.AWSS3StoragePlugin

fun configureAmplify() {
    try {
        Amplify.addPlugin(AWSCognitoAuthPlugin())
        Amplify.addPlugin(AWSApiPlugin())
        Amplify.addPlugin(AWSS3StoragePlugin())
        Amplify.configure(applicationContext)
    } catch (error: AmplifyException) {
        Log.e("Tutorial", "Could not initialize Amplify", error)
    }
}
```

## Advanced Features

### GraphQL Subscriptions
```graphql
subscription OnCreatePost {
  onCreatePost {
    id
    title
    content
    author
    createdAt
  }
}
```

### Offline Data Sync
```javascript
import { DataStore } from 'aws-amplify';
import { Post } from './models';

// Enable DataStore for offline sync
await DataStore.start();

// Query with offline support
const posts = await DataStore.query(Post);
```

### Custom Authentication Flows
Configure Lambda triggers for custom authentication logic:
- Pre-signup validation
- Post-confirmation actions
- Custom challenge generation
- Pre-authentication checks

## Support

### Documentation References
- [AWS Amplify Documentation](https://docs.amplify.aws/)
- [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/)
- [Amazon Cognito Developer Guide](https://docs.aws.amazon.com/cognito/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)

### Community Resources
- [AWS Amplify GitHub](https://github.com/aws-amplify)
- [Amplify Discord Community](https://discord.gg/amplify)
- [AWS Developer Forums](https://forums.aws.amazon.com/)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.