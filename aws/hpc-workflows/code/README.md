# Infrastructure as Code for Fault-Tolerant HPC with Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Fault-Tolerant HPC with Step Functions".

## Architecture Overview

The solution deploys a comprehensive fault-tolerant HPC workflow system that includes:

- **Step Functions State Machine**: Central orchestration engine for workflow management
- **Lambda Functions**: Serverless compute for resource management, checkpointing, and workflow parsing
- **EC2 Spot Fleet**: Cost-optimized compute resources with automatic failover
- **AWS Batch**: Job queuing and execution service
- **S3 Storage**: Checkpoint and workflow data persistence
- **DynamoDB**: Workflow state and metadata management
- **CloudWatch**: Monitoring, alerting, and operational dashboards
- **EventBridge**: Event-driven architecture for Spot interruption handling

## Key Features

### Fault Tolerance
- Automatic checkpoint creation and restoration
- Spot instance interruption handling with 2-minute grace period
- Progressive fallback from Spot to On-Demand instances
- Circuit breaker patterns and exponential backoff retry strategies

### Cost Optimization
- Intelligent Spot Fleet management with diversified instance types
- Automatic scaling based on workload demands
- Cost estimation and optimization recommendations
- Multi-AZ deployment for high availability

### Workflow Management
- Complex dependency resolution with topological sorting
- Parallel execution with configurable concurrency limits
- Real-time monitoring and progress tracking
- Comprehensive error handling and recovery

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for:
  - Step Functions
  - Lambda
  - EC2 (including Spot Fleet)
  - AWS Batch
  - S3
  - DynamoDB
  - CloudWatch
  - EventBridge
  - SNS
  - IAM
- Docker (for containerizing HPC applications)
- Estimated cost: $5-25/hour depending on workload size and instance types

### Required AWS Permissions

The deploying user/role needs permissions for:
- Step Functions (create, update, delete state machines)
- Lambda (create, update, delete functions)
- IAM (create, update, delete roles and policies)
- EC2 (create, manage Spot Fleet requests)
- Batch (create, manage compute environments and job queues)
- S3 (create, manage buckets and objects)
- DynamoDB (create, manage tables)
- CloudWatch (create dashboards, alarms, and metrics)
- EventBridge (create rules and targets)
- SNS (create topics and subscriptions)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name hpc-workflow-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-hpc-project \
                 ParameterKey=SpotFleetTargetCapacity,ParameterValue=4

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name hpc-workflow-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name hpc-workflow-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy infrastructure
cdk deploy --all

# View outputs
cdk ls
```

### Using CDK Python

```bash
# Set up Python environment
cd cdk-python/
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy infrastructure
cdk deploy --all

# View outputs
cdk ls
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
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
./scripts/deploy.sh --status
```

## Configuration

### Key Parameters

| Parameter | Description | Default | CloudFormation | CDK | Terraform |
|-----------|-------------|---------|---------------|-----|-----------|
| ProjectName | Unique identifier for resources | `hpc-workflow` | ✅ | ✅ | ✅ |
| SpotFleetTargetCapacity | Initial Spot Fleet capacity | `4` | ✅ | ✅ | ✅ |
| MaxSpotPrice | Maximum Spot instance price | `0.50` | ✅ | ✅ | ✅ |
| CheckpointRetentionDays | Checkpoint retention period | `7` | ✅ | ✅ | ✅ |
| NotificationEmail | Email for alerts | None | ✅ | ✅ | ✅ |
| InstanceTypes | Spot Fleet instance types | `c5.large,c5.xlarge,m5.large` | ✅ | ✅ | ✅ |

### Environment Variables

The deployment sets up the following environment variables for workflow execution:

```bash
export HPC_PROJECT_NAME="your-project-name"
export HPC_STATE_MACHINE_ARN="arn:aws:states:region:account:stateMachine:name"
export HPC_S3_BUCKET="your-checkpoint-bucket"
export HPC_DYNAMODB_TABLE="your-workflow-state-table"
export HPC_BATCH_QUEUE="your-batch-queue"
```

## Usage

### 1. Workflow Definition

Create a workflow definition file (JSON):

```json
{
  "name": "My HPC Workflow",
  "description": "Multi-stage computational workflow",
  "global_config": {
    "checkpoint_interval": 600,
    "max_retry_attempts": 3,
    "spot_strategy": "diversified"
  },
  "tasks": [
    {
      "id": "preprocessing",
      "name": "Data Preprocessing",
      "type": "batch",
      "container_image": "my-account.dkr.ecr.us-west-2.amazonaws.com/preprocessing:latest",
      "command": ["python", "/app/preprocess.py"],
      "vcpus": 2,
      "memory": 4096,
      "nodes": 1,
      "checkpoint_enabled": true,
      "spot_enabled": true
    },
    {
      "id": "simulation",
      "name": "Main Simulation",
      "type": "batch",
      "container_image": "my-account.dkr.ecr.us-west-2.amazonaws.com/simulation:latest",
      "command": ["mpirun", "./simulation"],
      "vcpus": 16,
      "memory": 32768,
      "nodes": 4,
      "depends_on": ["preprocessing"],
      "checkpoint_enabled": true,
      "spot_enabled": true
    }
  ]
}
```

### 2. Submit the Workflow

```bash
# Using the generated execution script
aws stepfunctions start-execution \
    --state-machine-arn $HPC_STATE_MACHINE_ARN \
    --name "my-workflow-$(date +%s)" \
    --input file://my-workflow.json
```

### 3. Monitor Execution

```bash
# Check execution status
aws stepfunctions describe-execution \
    --execution-arn $EXECUTION_ARN

# View CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name ${HPC_PROJECT_NAME}-monitoring
```

### Handling Spot Interruptions

The system automatically handles Spot instance interruptions through:

- **Proactive Monitoring**: EventBridge rules detect interruption warnings
- **Automatic Checkpointing**: Lambda functions save workflow state to S3
- **Graceful Failover**: Automatic migration to On-Demand instances when needed
- **State Recovery**: Workflows resume from last checkpoint after interruption

### Cost Optimization

- **Spot Fleet Diversification**: Multiple instance types reduce interruption risk
- **Intelligent Scaling**: Dynamic capacity adjustment based on workload
- **Checkpoint Strategy**: Configurable checkpoint frequency to balance cost and recovery time
- **Resource Tagging**: Comprehensive cost allocation and tracking

## Monitoring and Alerting

### CloudWatch Dashboards

The deployment creates comprehensive dashboards showing:
- Workflow execution metrics
- Resource utilization
- Cost optimization metrics
- Error rates and retry statistics

### Alarms

Automated alarms for:
- Workflow failures
- High Spot interruption rates
- Resource utilization thresholds
- Cost anomalies

### Metrics

Key metrics tracked:
- `ExecutionTime`: Workflow execution duration
- `ExecutionsFailed`: Number of failed executions
- `SpotInterruptions`: Spot instance interruptions
- `CheckpointsSaved`: Number of checkpoints created
- `CostOptimization`: Cost savings from Spot usage

## Security Considerations

### IAM Roles
- All services use least-privilege IAM roles
- Cross-service access is properly scoped
- No hardcoded credentials in code

### Network Security
- Security groups restrict access to necessary ports
- VPC endpoints recommended for production use
- Encryption in transit and at rest

### Data Protection
- S3 bucket encryption enabled
- DynamoDB encryption at rest
- CloudWatch Logs encryption
- No sensitive data in logs

## Troubleshooting

### Common Issues

1. **Workflow Parsing Errors**
   - Check CloudWatch logs for the workflow-parser Lambda
   - Validate JSON syntax in workflow definition
   - Ensure all task dependencies are valid

2. **Spot Fleet Creation Failures**
   - Verify IAM permissions for Spot Fleet
   - Check availability of requested instance types
   - Review VPC and subnet configurations

3. **Job Execution Failures**
   - Check Batch job logs in CloudWatch
   - Verify container images are accessible
   - Ensure proper resource allocation

### Debugging Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/$(terraform output -raw project_name)-spot-fleet-manager

# Describe Spot Fleet status
aws ec2 describe-spot-fleet-requests \
  --spot-fleet-request-ids <fleet-id>

# Check Batch job status
aws batch describe-jobs --jobs <job-id>

# View Step Functions execution history
aws stepfunctions get-execution-history \
  --execution-arn <execution-arn>
```

## Cost Optimization

### Spot Instance Savings
- Typically 60-90% cost reduction vs On-Demand
- Automatic instance type diversification
- Intelligent capacity management

### Resource Right-Sizing
- Automatic instance type recommendations
- Memory and CPU utilization monitoring
- Cost per job tracking

### Operational Efficiency
- Reduced manual intervention
- Automated scaling and healing
- Optimized resource utilization

## Customization

### Adding New Instance Types

Edit `variables.tf`:

```hcl
variable "instance_types" {
  default = ["c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge", "m5.large", "m5.xlarge"]
}
```

### Custom Monitoring Metrics

Add custom metrics in Lambda functions:

```python
# In Lambda function
cloudwatch.put_metric_data(
    Namespace=f'{PROJECT_NAME}/Custom',
    MetricData=[{
        'MetricName': 'CustomMetric',
        'Value': value,
        'Unit': 'Count'
    }]
)
```

### Workflow Templates

Create reusable workflow templates for common patterns:
- Molecular dynamics simulations
- Machine learning training
- Data processing pipelines
- Scientific computing workflows

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name hpc-workflow-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name hpc-workflow-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy all resources
cd cdk-typescript/  # or cdk-python/
cdk destroy --all

# Confirm deletion
cdk ls
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm cleanup
terraform show
```

### Using Bash Scripts

```bash
# Clean up all resources
./scripts/destroy.sh

# Verify cleanup
./scripts/destroy.sh --verify
```

## Customization

### Adding Custom Container Images

1. **Build and push images to ECR**:

```bash
# Create ECR repository
aws ecr create-repository --repository-name hpc-application

# Build and push image
docker build -t hpc-application .
docker tag hpc-application:latest \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/hpc-application:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/hpc-application:latest
```

2. **Update workflow definition** to reference your custom images.

### Modifying Instance Types

Update the `InstanceTypes` parameter in your deployment to include preferred instance families:

```yaml
# CloudFormation
Parameters:
  InstanceTypes:
    Type: CommaDelimitedList
    Default: "c5.large,c5.xlarge,c5.2xlarge,m5.large,m5.xlarge"
```

### Custom Checkpointing Logic

Modify the `checkpoint_manager.py` Lambda function to implement application-specific checkpointing:

```python
def save_application_checkpoint(checkpoint_data):
    # Custom checkpointing logic for your HPC application
    # Save intermediate results, model state, etc.
    pass
```

## Best Practices

1. **Workflow Design**:
   - Design workflows with checkpointing in mind
   - Minimize task dependencies for better parallelization
   - Use appropriate resource sizing for each task

2. **Cost Management**:
   - Monitor Spot pricing trends in your region
   - Use mixed instance types to reduce interruption risk
   - Implement cost alerts and budget controls

3. **Fault Tolerance**:
   - Test workflow recovery scenarios
   - Implement application-level checkpointing
   - Use appropriate retry strategies for different failure types

4. **Security**:
   - Regularly review IAM permissions
   - Enable CloudTrail for audit logging
   - Use encrypted storage for sensitive data

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../fault-tolerant-hpc-workflows-step-functions-spot-fleet.md)
- [AWS Step Functions documentation](https://docs.aws.amazon.com/step-functions/)
- [AWS Batch documentation](https://docs.aws.amazon.com/batch/)
- [AWS Spot Fleet documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-fleet.html)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow AWS best practices for security and cost optimization
3. Update documentation to reflect any changes
4. Ensure compatibility across all IaC implementations