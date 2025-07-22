# Infrastructure as Code for Simulating Cities with SimSpace Weaver and IoT

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simulating Cities with SimSpace Weaver and IoT".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a comprehensive smart city digital twin that combines real-time IoT sensor data ingestion through AWS IoT Core with large-scale spatial simulations using AWS SimSpace Weaver. The infrastructure includes:

- **IoT Core**: Device connectivity and message routing
- **DynamoDB**: High-performance sensor data storage with streams
- **Lambda Functions**: Serverless data processing and analytics
- **SimSpace Weaver**: Large-scale spatial simulations
- **S3**: Simulation package storage
- **IAM Roles**: Secure service permissions

## Prerequisites

### General Requirements
- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for IoT Core, SimSpace Weaver, DynamoDB, Lambda, S3, and IAM
- Basic understanding of IoT protocols, spatial computing concepts, and urban planning principles

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Understanding of YAML syntax

#### CDK TypeScript
- Node.js 14.x or later
- npm or yarn package manager
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.9 or later
- pip package manager
- AWS CDK CLI: `pip install aws-cdk-lib`

#### Terraform
- Terraform 1.0 or later
- AWS provider knowledge

#### Bash Scripts
- Bash shell environment
- jq for JSON processing
- zip utility for package creation

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name smart-city-digital-twin \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=smartcity-demo \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for deployment completion
aws cloudformation wait stack-create-complete \
    --stack-name smart-city-digital-twin

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name smart-city-digital-twin \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list --long
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list --long
```

### Using Terraform
```bash
# Navigate to Terraform directory
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will output important values like:
# - DynamoDB table name
# - Lambda function names
# - IoT thing group name
# - S3 bucket name
```

## Post-Deployment Setup

After deploying the infrastructure, follow these steps to complete the setup:

### 1. Test IoT Data Ingestion
```bash
# Get the IoT endpoint
aws iot describe-endpoint --endpoint-type iot:Data-ATS

# Publish test sensor data
aws iot-data publish \
    --topic "smartcity/sensors/traffic-001/data" \
    --payload '{
        "sensor_id": "traffic-001",
        "sensor_type": "traffic",
        "location": {"lat": 37.7749, "lon": -122.4194},
        "data": {
            "vehicle_count": 15,
            "average_speed": 35,
            "congestion_level": "moderate"
        },
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }'
```

### 2. Verify Data Processing
```bash
# Check DynamoDB for processed data
aws dynamodb scan --table-name <DYNAMODB_TABLE_NAME> --limit 5

# View Lambda function logs
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/<LAMBDA_FUNCTION_NAME>" \
    --order-by LastEventTime --descending
```

### 3. Test Analytics Functions
```bash
# Generate traffic analytics report
aws lambda invoke \
    --function-name <PROJECT_NAME>-analytics \
    --payload '{"type": "traffic_summary", "time_range": "24h"}' \
    --output text analytics_output.json

# View results
cat analytics_output.json
```

## Configuration Options

### Environment Variables
All implementations support these customization options:

- `PROJECT_NAME`: Base name for all resources (default: auto-generated)
- `AWS_REGION`: AWS region for deployment (default: current CLI region)
- `IOT_THING_GROUP_NAME`: Name for IoT device group
- `DYNAMODB_TABLE_NAME`: Name for sensor data table
- `SIMULATION_BUCKET_NAME`: S3 bucket for simulation packages

### Resource Configuration
Key configurable parameters include:

- **DynamoDB**: Read/write capacity units, stream configuration
- **Lambda**: Memory allocation, timeout settings, environment variables
- **IoT Core**: Thing group policies, message routing rules
- **S3**: Bucket configuration, lifecycle policies
- **IAM**: Role permissions, policy attachments

## Monitoring and Observability

### CloudWatch Metrics
Monitor these key metrics:

- **IoT Core**: Message ingestion rate, rule execution success
- **DynamoDB**: Read/write capacity utilization, throttling events
- **Lambda**: Invocation count, duration, error rates
- **SimSpace Weaver**: Simulation status, compute utilization

### Logging
Key log groups to monitor:

- `/aws/lambda/<function-name>`: Lambda function execution logs
- `/aws/iot/rules/<rule-name>`: IoT Rules Engine logs
- `SimSpaceWeaver/<simulation-name>`: Simulation execution logs

### Alarms
Consider setting up CloudWatch alarms for:

- Lambda function errors
- DynamoDB throttling
- IoT rule failures
- High data ingestion rates

## Cost Optimization

### Expected Costs
Estimated monthly costs for moderate usage:

- **IoT Core**: $0.08 per 100K messages
- **DynamoDB**: $25-50 for provisioned capacity
- **Lambda**: $5-15 for processing functions
- **S3**: $5-10 for simulation storage
- **SimSpace Weaver**: $50-200 based on simulation complexity

### Cost Optimization Tips

1. **DynamoDB**: Use on-demand billing for variable workloads
2. **Lambda**: Right-size memory allocation based on usage patterns
3. **IoT Core**: Implement message filtering to reduce processing costs
4. **S3**: Use Intelligent Tiering for simulation data
5. **SimSpace Weaver**: Schedule simulations during off-peak hours

## Security Considerations

### Implemented Security Measures

- **IoT Device Authentication**: Certificate-based authentication
- **IAM Roles**: Least privilege access principles
- **Data Encryption**: Encryption at rest for DynamoDB and S3
- **Network Security**: VPC endpoints for private connectivity
- **API Security**: Resource-based policies for Lambda functions

### Additional Security Recommendations

1. **IoT Device Security**: Implement AWS IoT Device Defender
2. **Data Governance**: Use AWS Config for compliance monitoring
3. **Access Logging**: Enable CloudTrail for API auditing
4. **Secret Management**: Use AWS Secrets Manager for credentials
5. **Network Isolation**: Deploy Lambda functions in VPC when needed

## Troubleshooting

### Common Issues

#### IoT Messages Not Processing
```bash
# Check IoT rule status
aws iot get-topic-rule --rule-name <rule-name>

# Verify Lambda permissions
aws lambda get-policy --function-name <function-name>

# Check CloudWatch logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/<function-name>" \
    --start-time $(date -d '1 hour ago' +%s)000
```

#### DynamoDB Write Failures
```bash
# Check table status
aws dynamodb describe-table --table-name <table-name>

# Monitor throttling metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedWriteCapacityUnits \
    --dimensions Name=TableName,Value=<table-name> \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

#### Simulation Startup Issues
```bash
# Check SimSpace Weaver status
aws simspaceweaver list-simulations

# Verify S3 bucket permissions
aws s3api get-bucket-policy --bucket <bucket-name>

# Check simulation logs
aws logs describe-log-groups --log-group-name-prefix "SimSpaceWeaver"
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name smart-city-digital-twin

# Wait for deletion completion
aws cloudformation wait stack-delete-complete \
    --stack-name smart-city-digital-twin
```

### Using CDK
```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy --force
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Extending the Solution

### Adding New Sensor Types
1. Update IoT policies to include new topic patterns
2. Modify Lambda functions to handle new data schemas
3. Extend analytics functions for new sensor metrics
4. Update simulation models to incorporate new data types

### Scaling for Production
1. **High Availability**: Deploy across multiple AZs
2. **Auto Scaling**: Configure DynamoDB auto-scaling
3. **Load Balancing**: Distribute IoT connections across regions
4. **Disaster Recovery**: Implement cross-region backups
5. **Performance Monitoring**: Set up detailed CloudWatch dashboards

### Integration Options
- **Amazon QuickSight**: Business intelligence dashboards
- **Amazon SageMaker**: Machine learning predictions
- **AWS IoT Device Management**: Fleet management
- **Amazon Kinesis**: Real-time streaming analytics
- **AWS Step Functions**: Workflow orchestration

## Support and Documentation

### AWS Documentation
- [AWS SimSpace Weaver User Guide](https://docs.aws.amazon.com/simspaceweaver/latest/userguide/)
- [AWS IoT Core Developer Guide](https://docs.aws.amazon.com/iot/latest/developerguide/)
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/latest/developerguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)

### Community Resources
- [AWS re:Invent Sessions](https://aws.amazon.com/events/reinvent/sessions/)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

### Getting Help
For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Consult the original recipe documentation
4. Contact AWS Support for service-specific issues

## Important Notes

> **Warning**: AWS SimSpace Weaver will reach end of support on May 20, 2026. Consider planning migration to alternative simulation platforms for long-term production deployments.

> **Note**: This infrastructure creates AWS resources that will incur charges. Review the cost optimization section and monitor your AWS billing dashboard.

> **Tip**: Start with the bash scripts for quick testing, then move to IaC tools like Terraform or CDK for production deployments.