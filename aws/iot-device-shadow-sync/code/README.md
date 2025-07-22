# Infrastructure as Code for IoT Device Shadow Synchronization

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Device Shadow Synchronization".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements advanced IoT device shadow synchronization with sophisticated conflict resolution, offline-capable caching, and comprehensive audit trails. The infrastructure includes:

- **Lambda Functions**: Conflict resolution and shadow sync management
- **DynamoDB Tables**: Shadow history, device configuration, and sync metrics
- **IoT Core Integration**: Device shadows, rules, and policies
- **EventBridge**: Event routing for monitoring and alerts
- **CloudWatch**: Comprehensive monitoring, logging, and dashboards
- **IAM Roles**: Secure access policies following least privilege principles

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IoT Core (things, shadows, policies, rules)
  - Lambda (functions, permissions, environment variables)
  - DynamoDB (tables, indexes, streams)
  - EventBridge (buses, rules, targets)
  - CloudWatch (dashboards, log groups, metrics)
  - IAM (roles, policies, trust relationships)
- Python 3.9+ for Lambda function development
- Understanding of IoT device shadows and MQTT protocol
- Estimated cost: $20-35 per month for shadow operations, Lambda executions, and DynamoDB storage

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete shadow synchronization infrastructure
aws cloudformation create-stack \
    --stack-name iot-shadow-sync-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=IoTShadowSync \
                 ParameterKey=Environment,ParameterValue=dev

# Monitor stack creation progress
aws cloudformation wait stack-create-complete \
    --stack-name iot-shadow-sync-stack

# Get stack outputs (endpoints, resource names)
aws cloudformation describe-stacks \
    --stack-name iot-shadow-sync-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy IoTShadowSyncStack

# View deployment outputs
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy IoTShadowSyncStack

# View deployment outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan -var="project_name=IoTShadowSync" \
               -var="environment=dev"

# Deploy infrastructure
terraform apply -var="project_name=IoTShadowSync" \
                -var="environment=dev"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration options
# The script will:
# 1. Create DynamoDB tables for shadow management
# 2. Deploy Lambda functions for conflict resolution
# 3. Set up IoT rules and policies
# 4. Configure EventBridge for monitoring
# 5. Create CloudWatch dashboard
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to:

1. **Create IoT Things and Certificates**:
   ```bash
   # Create demo IoT thing
   aws iot create-thing --thing-name demo-device-001
   
   # Generate device certificates
   aws iot create-keys-and-certificate \
       --set-as-active \
       --certificate-pem-outfile device-cert.pem \
       --private-key-outfile device-private-key.pem
   ```

2. **Configure Device-Specific Settings**:
   ```bash
   # Set conflict resolution strategy
   aws dynamodb put-item \
       --table-name shadow-sync-history-[suffix] \
       --item '{
           "thingName": {"S": "demo-device-001"},
           "configType": {"S": "conflict_resolution"},
           "config": {
               "M": {
                   "strategy": {"S": "field_level_merge"},
                   "auto_resolve_threshold": {"N": "5"}
               }
           }
       }'
   ```

3. **Initialize Named Shadows**:
   ```bash
   # Create configuration shadow
   aws iot-data update-thing-shadow \
       --thing-name demo-device-001 \
       --shadow-name configuration \
       --payload '{"state":{"desired":{"samplingRate":30,"alertThreshold":80}}}'
   ```

## Testing the Solution

### 1. Test Conflict Detection
```bash
# Simulate concurrent updates to trigger conflicts
aws iot-data update-thing-shadow \
    --thing-name demo-device-001 \
    --shadow-name configuration \
    --payload '{"state":{"desired":{"samplingRate":60}}}'

# Device reports different value (creates conflict)
aws iot-data update-thing-shadow \
    --thing-name demo-device-001 \
    --shadow-name configuration \
    --payload '{"state":{"reported":{"samplingRate":30}}}'
```

### 2. Test Offline Synchronization
```bash
# Get the sync manager function name from outputs
SYNC_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name iot-shadow-sync-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`SyncManagerFunction`].OutputValue' \
    --output text)

# Simulate offline sync scenario
aws lambda invoke \
    --function-name $SYNC_FUNCTION \
    --payload '{
        "operation": "offline_sync",
        "thingName": "demo-device-001",
        "offlineDurationSeconds": 3600,
        "cachedChanges": [{
            "shadowName": "telemetry",
            "state": {"temperature": 25.5, "humidity": 65.0},
            "timestamp": '$(date -d '1 hour ago' +%s)'
        }]
    }' \
    response.json
```

### 3. Monitor Shadow Health
```bash
# Generate health report
aws lambda invoke \
    --function-name $SYNC_FUNCTION \
    --payload '{
        "operation": "health_report",
        "thingNames": ["demo-device-001"]
    }' \
    health-report.json

# View the results
cat health-report.json | jq '.body' | jq '.'
```

## Monitoring and Observability

### CloudWatch Dashboard
Access the IoT Shadow Synchronization dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=IoT-Shadow-Synchronization
```

### Key Metrics to Monitor
- **ConflictDetected**: Number of shadow conflicts detected
- **SyncCompleted**: Successful synchronization operations
- **OfflineSync**: Offline synchronization events
- **Lambda Duration**: Function execution times
- **DynamoDB Throttles**: Database performance issues

### Log Analysis
```bash
# View conflict resolution logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/shadow-conflict-resolver-[suffix]" \
    --filter-pattern "conflict"

# View shadow audit trail
aws logs filter-log-events \
    --log-group-name "/aws/iot/shadow-audit" \
    --filter-pattern "shadow"
```

## Customization

### Key Variables/Parameters

**CloudFormation Parameters:**
- `ProjectName`: Prefix for all resource names
- `Environment`: Environment tag (dev/staging/prod)
- `ConflictResolutionStrategy`: Default strategy (last_writer_wins/field_level_merge)
- `AutoResolveThreshold`: Maximum auto-resolution attempts

**Terraform Variables:**
- `project_name`: Project identifier for resource naming
- `environment`: Deployment environment
- `aws_region`: Target AWS region
- `lambda_timeout`: Lambda function timeout (default: 300s)
- `lambda_memory_size`: Lambda memory allocation (default: 512MB)

**CDK Context Variables:**
- `projectName`: Application name prefix
- `environment`: Deployment environment
- `enableDetailedMonitoring`: Enhanced CloudWatch monitoring
- `retentionDays`: Log retention period

### Conflict Resolution Strategies

Customize conflict resolution by modifying device configuration:

```bash
# Set priority-based resolution
aws dynamodb put-item \
    --table-name device-configuration-[suffix] \
    --item '{
        "thingName": {"S": "your-device"},
        "configType": {"S": "conflict_resolution"},
        "config": {
            "M": {
                "strategy": {"S": "priority_based"},
                "field_priorities": {
                    "M": {
                        "firmware_version": {"S": "high"},
                        "configuration": {"S": "high"},
                        "telemetry": {"S": "low"}
                    }
                }
            }
        }
    }'
```

### Scaling Configuration

For large-scale deployments, adjust:

- **DynamoDB**: Switch to provisioned billing mode for predictable costs
- **Lambda**: Increase memory and timeout for complex conflict resolution
- **EventBridge**: Add additional rules for specific device types
- **CloudWatch**: Implement custom metrics for business KPIs

## Security Considerations

### IAM Permissions
All implementations follow the principle of least privilege:
- Lambda execution roles have minimal required permissions
- IoT policies restrict device access to specific shadow operations
- DynamoDB access is limited to specific tables and operations

### Data Protection
- Shadow data is encrypted at rest in DynamoDB
- Lambda environment variables are encrypted with AWS KMS
- IoT communication uses TLS 1.2 encryption
- Audit logs are retained for compliance requirements

### Network Security
- All communication occurs within AWS network
- No public endpoints for sensitive operations
- VPC endpoints can be added for enhanced network isolation

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**
   - Increase timeout in function configuration
   - Optimize conflict resolution algorithms
   - Implement batch processing for large conflict sets

2. **DynamoDB Throttling**
   - Monitor read/write capacity utilization
   - Implement exponential backoff in Lambda functions
   - Consider switching to on-demand billing mode

3. **IoT Rule Failures**
   - Check CloudWatch Logs for rule execution errors
   - Verify Lambda function permissions
   - Validate message format and structure

4. **Shadow Delta Events Not Processing**
   - Verify IoT rules are enabled and properly configured
   - Check Lambda function permissions for IoT invocation
   - Validate shadow update message structure

### Debugging Steps

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/shadow-conflict-resolver-[suffix] --follow

# Verify IoT rule metrics
aws iot get-topic-rule --rule-name ShadowDeltaProcessingRule

# Check DynamoDB table status
aws dynamodb describe-table --table-name shadow-sync-history-[suffix]

# Monitor EventBridge rule invocations
aws events describe-rule --name shadow-conflict-notifications
```

## Cleanup

### Using CloudFormation
```bash
# Delete the entire stack
aws cloudformation delete-stack --stack-name iot-shadow-sync-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name iot-shadow-sync-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy IoTShadowSyncStack
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_name=IoTShadowSync" \
                  -var="environment=dev"
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# The script will remove resources in the correct order
```

### Manual Cleanup (if needed)
```bash
# Delete any remaining IoT certificates
aws iot list-certificates --query 'certificates[].certificateId' \
    --output text | xargs -I {} aws iot delete-certificate --certificate-id {}

# Remove any orphaned log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/shadow" \
    --query 'logGroups[].logGroupName' --output text | \
    xargs -I {} aws logs delete-log-group --log-group-name {}
```

## Advanced Features

### Multi-Region Deployment
For global IoT deployments, consider:
- Cross-region shadow replication
- Regional conflict resolution strategies
- Global device registry management

### Integration Patterns
- **SageMaker**: ML-based conflict prediction
- **Kinesis**: Real-time shadow event streaming
- **Step Functions**: Complex workflow orchestration
- **SNS**: Multi-channel alerting and notifications

### Performance Optimization
- Implement connection pooling for DynamoDB
- Use Lambda provisioned concurrency for consistent performance
- Optimize shadow document structure for minimal network overhead
- Implement intelligent caching strategies for frequently accessed shadows

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS IoT Core documentation for shadow-specific guidance
3. Review CloudWatch logs for detailed error information
4. Consult AWS Lambda best practices for performance optimization

## Version Information

- **Recipe Version**: 1.2
- **AWS CDK Version**: ^2.100.0
- **Terraform AWS Provider**: ~> 5.0
- **CloudFormation Template Version**: 2010-09-09
- **Last Updated**: 2025-07-12

## License

This infrastructure code is provided under the same license as the recipe collection.