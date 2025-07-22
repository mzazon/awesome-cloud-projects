# Infrastructure as Code for Implementing DataSync for Data Transfer Automation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing DataSync for Data Transfer Automation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - DataSync tasks and locations
  - S3 buckets and objects
  - IAM roles and policies
  - CloudWatch log groups and dashboards
  - EventBridge rules and targets
- For CDK implementations: Node.js 16+ or Python 3.8+
- For Terraform: Terraform 1.0+

### Required AWS Permissions

Your AWS credentials must have permissions to create and manage:
- `datasync:*` - DataSync service operations
- `s3:*` - S3 bucket and object operations
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PutRolePolicy` - IAM management
- `logs:CreateLogGroup`, `logs:CreateLogStream` - CloudWatch logging
- `events:PutRule`, `events:PutTargets` - EventBridge scheduling
- `cloudwatch:PutDashboard` - CloudWatch dashboards

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name datasync-automation-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SourceBucketName,ParameterValue=my-source-bucket \
                 ParameterKey=DestinationBucketName,ParameterValue=my-dest-bucket \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name datasync-automation-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name datasync-automation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy DataSyncAutomationStack

# View outputs
npx cdk deploy DataSyncAutomationStack --outputs-file outputs.json
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy DataSyncAutomationStack

# View deployment info
cdk ls
cdk diff
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# Check deployment status
echo "Deployment completed. Check AWS Console for DataSync task status."
```

## Configuration Options

### CloudFormation Parameters

- `SourceBucketName`: Name for the source S3 bucket (default: auto-generated)
- `DestinationBucketName`: Name for the destination S3 bucket (default: auto-generated)
- `DataSyncTaskName`: Name for the DataSync task (default: auto-generated)
- `ScheduleExpression`: EventBridge schedule expression (default: "rate(1 day)")
- `LogLevel`: DataSync log level (default: "TRANSFER")
- `VerifyMode`: Data verification mode (default: "POINT_IN_TIME_CONSISTENT")

### CDK Configuration

Modify the configuration in the CDK app files:

```typescript
// CDK TypeScript - app.ts
const config = {
  sourceBucketName: 'my-source-bucket',
  destinationBucketName: 'my-dest-bucket',
  scheduleExpression: 'rate(1 day)',
  logLevel: 'TRANSFER'
};
```

```python
# CDK Python - app.py
config = {
    "source_bucket_name": "my-source-bucket",
    "destination_bucket_name": "my-dest-bucket",
    "schedule_expression": "rate(1 day)",
    "log_level": "TRANSFER"
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
source_bucket_name = "my-source-bucket"
destination_bucket_name = "my-dest-bucket"
schedule_expression = "rate(1 day)"
log_level = "TRANSFER"
verify_mode = "POINT_IN_TIME_CONSISTENT"
aws_region = "us-east-1"
```

## Deployment Architecture

The infrastructure creates the following resources:

### Core Components
- **DataSync Task**: Configured for S3-to-S3 transfer with optimal settings
- **Source Location**: S3 bucket configured as DataSync source
- **Destination Location**: S3 bucket configured as DataSync destination
- **IAM Service Role**: Least-privilege role for DataSync operations

### Monitoring and Logging
- **CloudWatch Log Group**: Detailed transfer logging
- **CloudWatch Dashboard**: Performance metrics visualization
- **Task Reports**: Detailed transfer reports stored in S3

### Automation
- **EventBridge Rule**: Scheduled task execution
- **EventBridge IAM Role**: Service role for automated task triggering

### Security Features
- **IAM Policies**: Least privilege access controls
- **S3 Bucket Policies**: Secure bucket access configuration
- **Encryption**: Server-side encryption for data at rest

## Validation & Testing

After deployment, validate the infrastructure:

### 1. Verify DataSync Task Creation

```bash
# List DataSync tasks
aws datasync list-tasks --query 'Tasks[?contains(Name, `datasync-task`)]'

# Check task status
aws datasync describe-task --task-arn <TASK_ARN>
```

### 2. Test Data Transfer

```bash
# Upload test data to source bucket
echo "Test data for DataSync" > test-file.txt
aws s3 cp test-file.txt s3://<SOURCE_BUCKET>/

# Execute DataSync task
aws datasync start-task-execution --task-arn <TASK_ARN>

# Monitor execution
aws datasync list-task-executions --task-arn <TASK_ARN>
```

### 3. Verify Monitoring Setup

```bash
# Check CloudWatch log group
aws logs describe-log-groups --log-group-name-prefix "/aws/datasync"

# View dashboard
aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `DataSync`)]'
```

### 4. Test Scheduled Execution

```bash
# Check EventBridge rule
aws events list-rules --name-prefix "DataSync"

# View rule targets
aws events list-targets-by-rule --rule <RULE_NAME>
```

## Monitoring and Operations

### CloudWatch Metrics

Monitor these key metrics:
- `BytesTransferred`: Total data transferred
- `FilesTransferred`: Number of files processed
- `Duration`: Task execution time
- `Status`: Task execution status

### Log Analysis

```bash
# View recent DataSync logs
aws logs filter-log-events \
    --log-group-name "/aws/datasync/<TASK_NAME>" \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Performance Tuning

- Adjust `BytesPerSecond` in task options for bandwidth control
- Use `TransferMode: CHANGED` for incremental transfers
- Configure appropriate `VerifyMode` based on data integrity requirements

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Verify IAM roles have necessary S3 and DataSync permissions
   - Check bucket policies allow DataSync service access

2. **Network Issues**
   - Ensure source and destination are in accessible regions
   - Verify VPC endpoints if using private networking

3. **Task Failures**
   - Check CloudWatch logs for detailed error messages
   - Verify source and destination locations are accessible
   - Ensure sufficient permissions for all operations

### Debug Commands

```bash
# Check task execution details
aws datasync describe-task-execution \
    --task-execution-arn <EXECUTION_ARN> \
    --query '{Status: Status, Result: Result}'

# View task configuration
aws datasync describe-task \
    --task-arn <TASK_ARN> \
    --query '{Options: Options, Status: Status}'
```

## Cost Optimization

### DataSync Pricing Considerations

- **Data Transfer**: Charged per GB transferred
- **Task Executions**: No additional charges for task management
- **Storage**: Standard S3 storage charges apply
- **Monitoring**: CloudWatch logs and metrics charges

### Cost Optimization Tips

1. **Use Incremental Transfers**: Configure `TransferMode: CHANGED`
2. **Schedule Wisely**: Align transfers with business requirements
3. **Monitor Usage**: Use CloudWatch to track transfer volumes
4. **Lifecycle Policies**: Implement S3 lifecycle rules for cost management

## Security Best Practices

### Implemented Security Measures

1. **Least Privilege IAM**: Minimal required permissions
2. **Service-Linked Roles**: AWS managed service access
3. **Encryption**: Server-side encryption for S3 data
4. **Audit Logging**: Comprehensive CloudWatch logging

### Additional Security Recommendations

1. **Enable VPC Endpoints**: For private network communication
2. **Use KMS**: Customer-managed encryption keys
3. **Monitor Access**: CloudTrail logging for API calls
4. **Network Segmentation**: VPC and security group controls

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name datasync-automation-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name datasync-automation-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
npx cdk destroy DataSyncAutomationStack

# Confirm destruction
# CDK will prompt for confirmation before deleting resources
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm destruction when prompted
# Review the destruction plan before confirming
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
echo "Cleanup completed. Verify in AWS Console that all resources are removed."
```

### Manual Cleanup Verification

After using any cleanup method, verify these resources are removed:

```bash
# Check DataSync tasks
aws datasync list-tasks

# Check S3 buckets
aws s3 ls | grep -E "(source|dest|datasync)"

# Check IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `DataSync`)]'

# Check CloudWatch resources
aws logs describe-log-groups --log-group-name-prefix "/aws/datasync"
aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `DataSync`)]'

# Check EventBridge rules
aws events list-rules --name-prefix "DataSync"
```

## Customization

### Extending the Solution

1. **Multi-Source Configuration**: Add multiple source locations
2. **Cross-Region Replication**: Configure destinations in different regions
3. **Advanced Filtering**: Implement include/exclude patterns
4. **Custom Notifications**: Add SNS integration for transfer notifications
5. **Data Validation**: Implement custom validation workflows

### Configuration Examples

#### Multiple Source Locations

```yaml
# CloudFormation example
AdditionalSourceLocation:
  Type: AWS::DataSync::LocationS3
  Properties:
    S3BucketArn: !Sub 'arn:aws:s3:::${AdditionalSourceBucket}'
    S3Config:
      BucketAccessRoleArn: !GetAtt DataSyncRole.Arn
```

#### Custom Transfer Options

```typescript
// CDK TypeScript example
const customTask = new datasync.CfnTask(this, 'CustomTask', {
  sourceLocationArn: sourceLocation.attrLocationArn,
  destinationLocationArn: destLocation.attrLocationArn,
  options: {
    verifyMode: 'ONLY_FILES_TRANSFERRED',
    overwriteMode: 'NEVER',
    transferMode: 'ALL',
    bytesPerSecond: 104857600 // 100 MB/s limit
  }
});
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for detailed explanations
2. **AWS Documentation**: [DataSync User Guide](https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html)
3. **Provider Documentation**: 
   - [CloudFormation DataSync Resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_DataSync.html)
   - [CDK DataSync Module](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_datasync-readme.html)
   - [Terraform AWS Provider DataSync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/datasync_task)
4. **Community Support**: AWS forums and Stack Overflow

## Version Information

- **Recipe Version**: 1.2
- **Last Updated**: 2025-07-12
- **Compatible AWS CLI**: v2.0+
- **Compatible CDK**: v2.0+
- **Compatible Terraform**: v1.0+
- **Infrastructure Types**: CloudFormation, CDK (TypeScript/Python), Terraform, Bash Scripts