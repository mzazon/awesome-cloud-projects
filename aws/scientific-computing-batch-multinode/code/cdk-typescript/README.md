# Scientific Computing with Batch Multi-Node - CDK TypeScript

This CDK TypeScript application deploys the complete infrastructure for distributed scientific computing using AWS Batch multi-node parallel jobs with MPI support.

## Architecture

The CDK application creates:

- **VPC Infrastructure**: Custom VPC with public and private subnets for isolated networking
- **Amazon EFS**: Shared storage with provisioned throughput for multi-node data access
- **Amazon ECR**: Container registry for storing MPI-enabled scientific computing images
- **AWS Batch**: Managed compute environment, job queue, and multi-node job definition
- **IAM Roles**: Service roles and instance profiles with least-privilege permissions
- **CloudWatch**: Monitoring dashboard and alarms for job tracking and alerting
- **Security Groups**: Network security allowing MPI communication between nodes

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Docker installed for building container images
- Appropriate AWS permissions for creating VPC, EC2, Batch, EFS, ECR, and IAM resources

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not done previously)**:
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   npm run deploy
   ```

4. **Build and push MPI container image** (after deployment):
   ```bash
   # Get ECR repository URI from CDK outputs
   ECR_URI=$(aws cloudformation describe-stacks \
       --stack-name DistributedScientificComputing-dev \
       --query 'Stacks[0].Outputs[?OutputKey==`EcrRepositoryUri`].OutputValue' \
       --output text)
   
   # Login to ECR
   aws ecr get-login-password --region us-east-1 | \
       docker login --username AWS --password-stdin $ECR_URI
   
   # Build and push your MPI container image
   # (See main recipe documentation for Dockerfile examples)
   ```

## Customization

You can customize the deployment using CDK context variables:

```bash
# Deploy with custom configuration
cdk deploy \
    -c envName=production \
    -c nodeCount=4 \
    -c maxvCpus=512 \
    -c instanceTypes='["c5.2xlarge","c5.4xlarge"]'
```

### Available Context Variables

- `envName`: Environment name (default: 'dev')
- `nodeCount`: Default number of nodes for multi-node jobs (default: 2)
- `maxvCpus`: Maximum vCPUs for compute environment (default: 256)
- `instanceTypes`: Array of EC2 instance types (default: ['c5.large', 'c5.xlarge'])

## Deployment Commands

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and compile
- `npm run test`: Run unit tests
- `npm run deploy`: Build and deploy the stack
- `npm run destroy`: Destroy the stack
- `cdk diff`: Compare deployed stack with current state
- `cdk synth`: Synthesize CloudFormation template

## Submitting Jobs

After deployment, submit multi-node parallel jobs using the AWS CLI:

```bash
# Get job queue and definition names from CDK outputs
JOB_QUEUE=$(aws cloudformation describe-stacks \
    --stack-name DistributedScientificComputing-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`JobQueueName`].OutputValue' \
    --output text)

JOB_DEFINITION=$(aws cloudformation describe-stacks \
    --stack-name DistributedScientificComputing-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`JobDefinitionArn`].OutputValue' \
    --output text)

# Submit a multi-node job
aws batch submit-job \
    --job-name scientific-test-job \
    --job-queue $JOB_QUEUE \
    --job-definition $JOB_DEFINITION
```

## Monitoring

Access the CloudWatch dashboard created by the stack to monitor:

- Job submission, runnable, and running counts
- Compute environment scaling metrics
- Job execution logs and performance data

## Cost Optimization

- The compute environment scales from 0 to maximum vCPUs based on demand
- EFS uses Intelligent Tiering for automatic cost optimization
- ECR lifecycle policies limit stored image versions
- Use appropriate instance types for your workload requirements

## Security Features

- All resources deployed in private subnets with NAT Gateway for internet access
- Security groups configured for MPI communication while restricting external access
- EFS encrypted at rest with AWS managed keys
- IAM roles follow least-privilege principles
- ECR image scanning enabled for vulnerability detection

## Cleanup

To avoid ongoing charges, destroy the stack when finished:

```bash
npm run destroy
```

**Note**: Ensure all Batch jobs are completed before destroying the stack, as running jobs may prevent clean deletion.

## Troubleshooting

### Common Issues

1. **Job stays in RUNNABLE state**: Check compute environment capacity and instance limits
2. **Container image pull errors**: Verify ECR repository permissions and image tags
3. **EFS mount failures**: Check security group rules and VPC configuration
4. **Node communication issues**: Verify security group allows all traffic between nodes

### Useful Commands

```bash
# Check job status
aws batch describe-jobs --jobs JOB_ID

# View job logs
aws logs describe-log-streams --log-group-name /aws/batch/job

# Monitor compute environment
aws batch describe-compute-environments --compute-environments COMPUTE_ENV_NAME
```

## Next Steps

1. Customize the MPI container image for your specific scientific applications
2. Implement job parameter templates for different workload types
3. Set up automated job submission workflows using Step Functions
4. Configure cost alerts and budget controls for large-scale computations
5. Integrate with scientific workflow management systems

For detailed implementation guidance, refer to the main recipe documentation.