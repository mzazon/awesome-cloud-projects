# Interactive Data Analytics with Bedrock AgentCore Code Interpreter - CDK Python

This AWS CDK Python application implements a comprehensive interactive data analytics system that combines natural language processing with secure code execution capabilities using AWS Bedrock AgentCore Code Interpreter.

## 🏗️ Architecture Overview

The solution creates a serverless, scalable analytics platform with the following components:

- **AWS S3 Buckets**: Secure data storage for raw datasets and analysis results
- **AWS Lambda Function**: Orchestrates analytics workflows and manages AI interactions
- **AWS Bedrock AgentCore Code Interpreter**: Executes Python code in secure sandboxed environments
- **API Gateway**: Provides secure REST API endpoints with rate limiting and monitoring
- **CloudWatch**: Comprehensive monitoring, logging, and alerting
- **IAM Roles**: Least privilege access controls for enterprise security
- **SQS Dead Letter Queue**: Robust error handling and message recovery

## 🚀 Features

### Analytics Capabilities
- **Natural Language Queries**: Submit analytics requests in plain English
- **Secure Code Execution**: Python code runs in isolated Bedrock sandboxes
- **Multi-format Data Support**: Process CSV, JSON, Excel, and other data formats
- **Advanced Visualizations**: Automatic chart and dashboard generation
- **Statistical Analysis**: Comprehensive statistical insights and trends
- **Performance Monitoring**: Real-time execution metrics and alerting

### Enterprise Features
- **Security**: End-to-end encryption and least privilege access
- **Scalability**: Serverless architecture scales automatically
- **Cost Optimization**: S3 lifecycle policies and Lambda concurrency controls
- **Monitoring**: CloudWatch dashboards and custom metrics
- **Error Handling**: Dead letter queues and retry mechanisms
- **API Management**: Rate limiting, usage plans, and API keys

## 📋 Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS Account**: Active AWS account with appropriate permissions
2. **AWS CLI**: Version 2.x installed and configured
3. **Python**: Version 3.8 or higher
4. **Node.js**: Version 18.x or higher (for CDK CLI)
5. **AWS CDK**: Version 2.165.0 or higher
6. **Docker**: For containerized builds (optional)

### Required AWS Permissions

Your AWS credentials must have permissions for:
- S3 bucket creation and management
- Lambda function deployment and configuration
- API Gateway creation and management
- IAM role and policy management
- CloudWatch logs and metrics
- Bedrock AgentCore access (preview feature)
- SQS queue management

### AWS Services and Regions

This application uses the following AWS services:
- **AWS S3**: Data storage and lifecycle management
- **AWS Lambda**: Serverless compute and orchestration
- **AWS Bedrock**: AgentCore Code Interpreter (preview)
- **AWS API Gateway**: REST API management
- **AWS CloudWatch**: Monitoring and alerting
- **AWS IAM**: Identity and access management
- **AWS SQS**: Message queuing and error handling

**Supported Regions**: This application can be deployed in any AWS region that supports Bedrock AgentCore (currently in preview).

## 🛠️ Installation and Setup

### 1. Clone and Navigate to Directory

```bash
cd aws/interactive-data-analytics-bedrock-codeinterpreter/code/cdk-python/
```

### 2. Create Python Virtual Environment

```bash
# Create virtual environment
python3 -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate
```

### 3. Install Dependencies

```bash
# Upgrade pip
python -m pip install --upgrade pip

# Install CDK dependencies
pip install -r requirements.txt

# Install development dependencies (optional)
pip install -e ".[dev]"
```

### 4. Install and Configure AWS CDK

```bash
# Install AWS CDK CLI globally
npm install -g aws-cdk@latest

# Verify CDK installation
cdk --version

# Bootstrap CDK (one-time setup per region/account)
cdk bootstrap
```

### 5. Configure AWS Environment

```bash
# Set AWS region (optional, defaults to us-east-1)
export CDK_DEFAULT_REGION=us-east-1

# Verify AWS configuration
aws sts get-caller-identity
```

## 🚀 Deployment

### 1. Synthesize CloudFormation Template

```bash
# Generate CloudFormation template
cdk synth

# Review the generated template
cdk synth > template.yaml
```

### 2. Deploy the Stack

```bash
# Deploy with confirmation prompts
cdk deploy

# Deploy without confirmation (use with caution)
cdk deploy --require-approval never

# Deploy with specific stack name
cdk deploy InteractiveDataAnalyticsStack
```

### 3. Post-Deployment Configuration

After successful deployment, you'll need to:

1. **Create Bedrock Code Interpreter**:
   ```bash
   # Get the execution role ARN from stack outputs
   EXECUTION_ROLE_ARN=$(aws cloudformation describe-stacks \
       --stack-name InteractiveDataAnalyticsStack \
       --query 'Stacks[0].Outputs[?OutputKey==`ExecutionRoleArn`].OutputValue' \
       --output text)
   
   # Create Code Interpreter
   aws bedrock-agentcore create-code-interpreter \
       --name analytics-interpreter \
       --description "Interactive data analytics interpreter" \
       --execution-role-arn ${EXECUTION_ROLE_ARN}
   ```

2. **Update Lambda Environment Variables**:
   ```bash
   # Update Lambda function with Code Interpreter ID
   aws lambda update-function-configuration \
       --function-name analytics-orchestrator \
       --environment Variables="{CODE_INTERPRETER_ID=your-interpreter-id}"
   ```

3. **Upload Sample Data**:
   ```bash
   # Upload sample dataset
   aws s3 cp sample-data.csv s3://your-raw-data-bucket/datasets/
   ```

## 📊 Usage

### 1. API Gateway Integration

Once deployed, you can interact with the analytics system through the API Gateway endpoint:

```bash
# Get API Gateway URL from stack outputs
API_URL=$(aws cloudformation describe-stacks \
    --stack-name InteractiveDataAnalyticsStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text)

# Submit analytics query
curl -X POST ${API_URL}/analytics \
    -H "Content-Type: application/json" \
    -H "x-api-key: YOUR_API_KEY" \
    -d '{
        "query": "Analyze sales trends by region and create visualizations"
    }'
```

### 2. Direct Lambda Invocation

For testing and development:

```bash
# Invoke Lambda function directly
aws lambda invoke \
    --function-name analytics-orchestrator \
    --payload '{"query": "Calculate total revenue by product category"}' \
    response.json

# View response
cat response.json | jq '.'
```

### 3. Monitoring and Observability

Access monitoring through:

1. **CloudWatch Dashboard**: Monitor real-time metrics and performance
2. **CloudWatch Logs**: View detailed execution logs and debugging information
3. **CloudWatch Alarms**: Receive alerts for errors or performance issues
4. **X-Ray Tracing**: Distributed tracing for complex workflows (if enabled)

## 🔧 Configuration

### Environment Variables

The Lambda function uses these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `BUCKET_RAW_DATA` | S3 bucket for input data | Set by CDK |
| `BUCKET_RESULTS` | S3 bucket for results | Set by CDK |
| `CODE_INTERPRETER_ID` | Bedrock Code Interpreter ID | Requires manual setup |
| `LOG_LEVEL` | Logging level | INFO |

### Customization Options

#### 1. Modify Lambda Configuration

```python
# In app.py, update Lambda function properties
self.analytics_function = lambda_.Function(
    # ... existing configuration
    timeout=Duration.minutes(10),  # Increase timeout
    memory_size=2048,              # Increase memory
    reserved_concurrent_executions=20  # Adjust concurrency
)
```

#### 2. Update S3 Lifecycle Policies

```python
# Modify lifecycle rules in _create_s3_buckets method
lifecycle_rules=[
    s3.LifecycleRule(
        transitions=[
            s3.Transition(
                storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                transition_after=Duration.days(14)  # Faster transition
            )
        ]
    )
]
```

#### 3. Configure API Gateway Throttling

```python
# Adjust API Gateway throttling limits
throttling_rate_limit=200,  # Increase requests per second
throttling_burst_limit=400,  # Increase burst capacity
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Bedrock AgentCore Not Available

**Error**: `bedrock-agentcore` service not found
**Solution**: Ensure you're in a region where Bedrock AgentCore is available and your account has preview access.

#### 2. Lambda Timeout

**Error**: Lambda function times out during execution
**Solution**: Increase Lambda timeout or optimize analytics code.

```bash
# Update Lambda timeout
aws lambda update-function-configuration \
    --function-name analytics-orchestrator \
    --timeout 600
```

#### 3. S3 Access Denied

**Error**: S3 access denied errors
**Solution**: Verify IAM roles have correct S3 permissions.

```bash
# Check Lambda execution role
aws iam get-role-policy \
    --role-name analytics-lambda-role \
    --policy-name AnalyticsPolicy
```

#### 4. API Gateway 429 Errors

**Error**: Too many requests (429)
**Solution**: Adjust API Gateway throttling limits or implement client-side retry logic.

### Debugging Commands

```bash
# View CloudWatch logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/analytics-orchestrator

# Get recent log events
aws logs get-log-events \
    --log-group-name /aws/lambda/analytics-orchestrator \
    --log-stream-name LATEST

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace Analytics/CodeInterpreter \
    --metric-name ExecutionCount \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

## 🧪 Testing

### Unit Tests

```bash
# Run unit tests
python -m pytest tests/ -v

# Run with coverage
python -m pytest tests/ --cov=app --cov-report=html

# Run specific test
python -m pytest tests/test_stack.py::TestAnalyticsStack::test_s3_buckets
```

### Integration Tests

```bash
# Test Lambda function
python scripts/test_lambda.py

# Test API Gateway endpoint
python scripts/test_api.py

# Load testing
python scripts/load_test.py
```

### CDK Testing

```bash
# Test CDK synthesis
cdk synth --quiet

# Validate CloudFormation template
aws cloudformation validate-template \
    --template-body file://cdk.out/InteractiveDataAnalyticsStack.template.json

# CDK diff (compare with deployed stack)
cdk diff
```

## 🔒 Security Best Practices

### 1. IAM Roles and Policies

- ✅ Least privilege access principles
- ✅ Service-specific IAM roles
- ✅ Resource-level permissions
- ✅ Regular access review and rotation

### 2. Data Protection

- ✅ S3 server-side encryption (AES-256)
- ✅ API Gateway with API keys
- ✅ VPC endpoints for private access (optional)
- ✅ CloudTrail logging for audit trails

### 3. Network Security

- ✅ API Gateway regional endpoints
- ✅ CORS configuration for web access
- ✅ Rate limiting and throttling
- ✅ DDoS protection through AWS Shield

### 4. Code Security

```bash
# Run security scans
bandit -r app.py

# Check for vulnerabilities
safety check

# Validate CDK Nag rules
cdk synth --app "python app.py" --strict
```

## 💰 Cost Optimization

### Cost Factors

| Service | Cost Factor | Optimization |
|---------|-------------|--------------|
| Lambda | Execution time & memory | Optimize code, right-size memory |
| S3 | Storage & requests | Lifecycle policies, intelligent tiering |
| API Gateway | API calls | Caching, efficient endpoints |
| Bedrock | Inference requests | Batch processing, prompt optimization |
| CloudWatch | Logs & metrics | Log retention policies, metric filters |

### Cost Monitoring

```bash
# Set up billing alerts
aws budgets create-budget \
    --account-id YOUR_ACCOUNT_ID \
    --budget file://budget.json

# Monitor costs by service
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## 🧹 Cleanup

### Option 1: CDK Destroy

```bash
# Destroy the entire stack
cdk destroy

# Destroy with confirmation
cdk destroy --force

# Remove CDK bootstrap (optional, affects other CDK apps)
aws cloudformation delete-stack --stack-name CDKToolkit
```

### Option 2: Manual Cleanup

```bash
# Empty S3 buckets before deletion
aws s3 rm s3://your-raw-data-bucket --recursive
aws s3 rm s3://your-results-bucket --recursive

# Delete specific resources
aws lambda delete-function --function-name analytics-orchestrator
aws s3 rb s3://your-raw-data-bucket
aws s3 rb s3://your-results-bucket
```

### Verification

```bash
# Verify stack deletion
aws cloudformation describe-stacks \
    --stack-name InteractiveDataAnalyticsStack

# Check for remaining resources
aws resourcegroupstaggingapi get-resources \
    --tag-filters Key=Project,Values=InteractiveDataAnalytics
```

## 📚 Additional Resources

### AWS Documentation
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS Bedrock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/s3/latest/userguide/)
- [Amazon API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)

### Best Practices
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Security Best Practices](https://aws.amazon.com/security/security-learning/)
- [CDK Best Practices](https://docs.aws.amazon.com/cdk/v2/guide/best-practices.html)
- [Serverless Application Lens](https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/)

### Community Resources
- [AWS CDK Examples](https://github.com/aws-samples/aws-cdk-examples)
- [AWS Bedrock Samples](https://github.com/aws-samples/amazon-bedrock-samples)
- [CDK Patterns](https://cdkpatterns.com/)
- [AWS Solutions Constructs](https://docs.aws.amazon.com/solutions/latest/constructs/)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- Code style and formatting
- Testing requirements
- Pull request process
- Issue reporting
- Security disclosures

## 📄 License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This solution is provided as a sample implementation for educational and demonstration purposes. For production deployments:

- Review and adjust security configurations
- Implement proper monitoring and alerting
- Conduct thorough testing and validation
- Follow your organization's deployment practices
- Consider compliance and regulatory requirements

The costs associated with running this solution will vary based on usage patterns, data volumes, and AWS region. Monitor your AWS billing dashboard and set up appropriate cost alerts.