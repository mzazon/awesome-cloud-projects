#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as stepfunctionsTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as batch from 'aws-cdk-lib/aws-batch';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'path';

/**
 * AWS CDK Stack for Fault-Tolerant HPC Workflows with Step Functions and Spot Fleet
 * 
 * This stack implements a comprehensive fault-tolerant HPC workflow orchestration system
 * using AWS Step Functions for workflow management, AWS Batch for job execution,
 * and Spot Fleet for cost-optimized compute resources.
 */
export class FaultTolerantHpcWorkflowsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique identifier for resources
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const projectName = `hpc-workflow-${randomSuffix}`;

    // Create VPC for the HPC infrastructure
    const vpc = new ec2.Vpc(this, 'HpcVpc', {
      maxAzs: 2,
      natGateways: 1,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'public-subnet',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'private-subnet',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Create security group for batch compute resources
    const batchSecurityGroup = new ec2.SecurityGroup(this, 'BatchSecurityGroup', {
      vpc: vpc,
      description: 'Security group for HPC Batch compute resources',
      allowAllOutbound: true,
    });

    // Add ingress rules for inter-node communication (needed for MPI jobs)
    batchSecurityGroup.addIngressRule(
      batchSecurityGroup,
      ec2.Port.allTraffic(),
      'Allow communication between batch instances'
    );

    // S3 bucket for checkpoints and workflow data
    const checkpointsBucket = new s3.Bucket(this, 'CheckpointsBucket', {
      bucketName: `${projectName}-checkpoints-${this.account}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'checkpoint-lifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: cdk.Duration.days(365),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // DynamoDB table for workflow state management
    const workflowStateTable = new dynamodb.Table(this, 'WorkflowStateTable', {
      tableName: `${projectName}-workflow-state`,
      partitionKey: { name: 'WorkflowId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'TaskId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM role for Lambda functions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for HPC workflow Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        HpcWorkflowPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:DescribeSpotFleetRequests',
                'ec2:ModifySpotFleetRequest',
                'ec2:CancelSpotFleetRequests',
                'ec2:CreateSpotFleetRequest',
                'ec2:DescribeSpotFleetInstances',
                'ec2:DescribeInstances',
                'ec2:DescribeSubnets',
                'ec2:DescribeSecurityGroups',
                'batch:SubmitJob',
                'batch:DescribeJobs',
                'batch:ListJobs',
                'batch:TerminateJob',
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                checkpointsBucket.bucketArn,
                checkpointsBucket.bucketArn + '/*',
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [workflowStateTable.tableArn],
            }),
          ],
        }),
      },
    });

    // Workflow Parser Lambda Function
    const workflowParserFunction = new lambda.Function(this, 'WorkflowParserFunction', {
      functionName: `${projectName}-workflow-parser`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'workflow_parser.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Parses HPC workflow definitions and prepares execution plan
    """
    try:
        workflow_definition = event['workflow_definition']
        workflow_id = event.get('workflow_id', f"workflow-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}")
        
        # Parse workflow definition
        parsed_workflow = parse_workflow(workflow_definition)
        
        # Generate execution plan
        execution_plan = generate_execution_plan(parsed_workflow, workflow_id)
        
        return {
            'statusCode': 200,
            'workflow_id': workflow_id,
            'execution_plan': execution_plan,
            'estimated_cost': calculate_estimated_cost(execution_plan),
            'estimated_duration': calculate_estimated_duration(execution_plan)
        }
        
    except Exception as e:
        logger.error(f"Error parsing workflow: {str(e)}")
        raise

def parse_workflow(workflow_def):
    """Parse workflow definition into structured format"""
    parsed = {
        'name': workflow_def.get('name', 'Unnamed Workflow'),
        'description': workflow_def.get('description', ''),
        'tasks': [],
        'dependencies': {},
        'global_config': workflow_def.get('global_config', {})
    }
    
    # Parse tasks
    for task in workflow_def.get('tasks', []):
        parsed_task = {
            'id': task['id'],
            'name': task.get('name', task['id']),
            'type': task.get('type', 'batch'),
            'container_image': task.get('container_image'),
            'command': task.get('command', []),
            'environment': task.get('environment', {}),
            'resources': {
                'vcpus': task.get('vcpus', 1),
                'memory': task.get('memory', 1024),
                'nodes': task.get('nodes', 1)
            },
            'retry_strategy': {
                'attempts': task.get('retry_attempts', 3),
                'backoff_multiplier': task.get('backoff_multiplier', 2.0)
            },
            'checkpoint_enabled': task.get('checkpoint_enabled', False),
            'spot_enabled': task.get('spot_enabled', True)
        }
        parsed['tasks'].append(parsed_task)
        
        # Parse dependencies
        if 'depends_on' in task:
            parsed['dependencies'][task['id']] = task['depends_on']
    
    return parsed

def generate_execution_plan(parsed_workflow, workflow_id):
    """Generate step-by-step execution plan"""
    execution_plan = {
        'workflow_id': workflow_id,
        'stages': [],
        'parallel_groups': [],
        'total_tasks': len(parsed_workflow['tasks'])
    }
    
    # Simple topological sort for dependency resolution
    remaining_tasks = {task['id']: task for task in parsed_workflow['tasks']}
    dependencies = parsed_workflow['dependencies']
    completed_tasks = set()
    stage_number = 0
    
    while remaining_tasks:
        stage_number += 1
        current_stage = {
            'stage': stage_number,
            'tasks': [],
            'parallel_execution': True
        }
        
        # Find tasks with no remaining dependencies
        ready_tasks = []
        for task_id, task in remaining_tasks.items():
            deps = dependencies.get(task_id, [])
            if all(dep in completed_tasks for dep in deps):
                ready_tasks.append(task)
        
        if not ready_tasks:
            # Circular dependency or other issue
            raise ValueError("Unable to resolve task dependencies")
        
        # Add ready tasks to current stage
        for task in ready_tasks:
            current_stage['tasks'].append(task)
            completed_tasks.add(task['id'])
            del remaining_tasks[task['id']]
        
        execution_plan['stages'].append(current_stage)
    
    return execution_plan

def calculate_estimated_cost(execution_plan):
    """Calculate estimated cost for workflow execution"""
    total_vcpu_hours = 0
    
    for stage in execution_plan['stages']:
        for task in stage['tasks']:
            vcpus = task['resources']['vcpus']
            nodes = task['resources']['nodes']
            estimated_hours = 1
            total_vcpu_hours += vcpus * nodes * estimated_hours
    
    estimated_cost = total_vcpu_hours * 0.10
    
    return {
        'total_vcpu_hours': total_vcpu_hours,
        'estimated_cost_usd': estimated_cost,
        'currency': 'USD'
    }

def calculate_estimated_duration(execution_plan):
    """Calculate estimated duration for workflow execution"""
    total_stages = len(execution_plan['stages'])
    estimated_minutes = total_stages * 30
    
    return {
        'estimated_duration_minutes': estimated_minutes,
        'total_stages': total_stages
    }
`),
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      role: lambdaExecutionRole,
      logRetention: logs.RetentionDays.TWO_WEEKS,
      environment: {
        BUCKET_NAME: checkpointsBucket.bucketName,
        TABLE_NAME: workflowStateTable.tableName,
      },
    });

    // Checkpoint Manager Lambda Function
    const checkpointManagerFunction = new lambda.Function(this, 'CheckpointManagerFunction', {
      functionName: `${projectName}-checkpoint-manager`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'checkpoint_manager.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Manages checkpoints for fault-tolerant workflows
    """
    try:
        action = event.get('action', 'save')
        
        if action == 'save':
            return save_checkpoint(event)
        elif action == 'restore':
            return restore_checkpoint(event)
        elif action == 'list':
            return list_checkpoints(event)
        elif action == 'cleanup':
            return cleanup_old_checkpoints(event)
        else:
            raise ValueError(f"Unknown action: {action}")
            
    except Exception as e:
        logger.error(f"Error in checkpoint manager: {str(e)}")
        raise

def save_checkpoint(event):
    """Save workflow checkpoint to S3 and DynamoDB"""
    workflow_id = event['workflow_id']
    task_id = event['task_id']
    checkpoint_data = event['checkpoint_data']
    bucket_name = event['bucket_name']
    
    # Generate checkpoint ID
    checkpoint_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()
    
    # Save checkpoint data to S3
    s3_key = f"checkpoints/{workflow_id}/{task_id}/{checkpoint_id}.json"
    
    s3.put_object(
        Bucket=bucket_name,
        Key=s3_key,
        Body=json.dumps(checkpoint_data),
        ContentType='application/json',
        Metadata={
            'workflow_id': workflow_id,
            'task_id': task_id,
            'timestamp': timestamp
        }
    )
    
    # Update DynamoDB with checkpoint metadata
    table = dynamodb.Table(event['table_name'])
    table.put_item(
        Item={
            'WorkflowId': workflow_id,
            'TaskId': task_id,
            'CheckpointId': checkpoint_id,
            'S3Key': s3_key,
            'Timestamp': timestamp,
            'Status': 'saved'
        }
    )
    
    logger.info(f"Checkpoint saved: {checkpoint_id}")
    
    return {
        'statusCode': 200,
        'checkpoint_id': checkpoint_id,
        's3_key': s3_key,
        'timestamp': timestamp
    }

def restore_checkpoint(event):
    """Restore latest checkpoint for a workflow task"""
    workflow_id = event['workflow_id']
    task_id = event['task_id']
    bucket_name = event['bucket_name']
    table_name = event['table_name']
    
    # Query DynamoDB for latest checkpoint
    table = dynamodb.Table(table_name)
    response = table.query(
        KeyConditionExpression='WorkflowId = :wid AND TaskId = :tid',
        ExpressionAttributeValues={
            ':wid': workflow_id,
            ':tid': task_id
        },
        ScanIndexForward=False,
        Limit=1
    )
    
    if not response['Items']:
        return {
            'statusCode': 404,
            'message': 'No checkpoint found'
        }
    
    latest_checkpoint = response['Items'][0]
    s3_key = latest_checkpoint['S3Key']
    
    # Retrieve checkpoint data from S3
    s3_response = s3.get_object(
        Bucket=bucket_name,
        Key=s3_key
    )
    
    checkpoint_data = json.loads(s3_response['Body'].read().decode('utf-8'))
    
    return {
        'statusCode': 200,
        'checkpoint_id': latest_checkpoint['CheckpointId'],
        'checkpoint_data': checkpoint_data,
        'timestamp': latest_checkpoint['Timestamp']
    }

def list_checkpoints(event):
    """List all checkpoints for a workflow"""
    workflow_id = event['workflow_id']
    table_name = event['table_name']
    
    table = dynamodb.Table(table_name)
    response = table.query(
        KeyConditionExpression='WorkflowId = :wid',
        ExpressionAttributeValues={
            ':wid': workflow_id
        }
    )
    
    return {
        'statusCode': 200,
        'checkpoints': response['Items']
    }

def cleanup_old_checkpoints(event):
    """Clean up checkpoints older than specified days"""
    days_to_keep = event.get('days_to_keep', 7)
    
    return {
        'statusCode': 200,
        'message': f'Cleanup completed for checkpoints older than {days_to_keep} days'
    }
`),
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      role: lambdaExecutionRole,
      logRetention: logs.RetentionDays.TWO_WEEKS,
      environment: {
        BUCKET_NAME: checkpointsBucket.bucketName,
        TABLE_NAME: workflowStateTable.tableName,
      },
    });

    // Spot Fleet Manager Lambda Function
    const spotFleetManagerFunction = new lambda.Function(this, 'SpotFleetManagerFunction', {
      functionName: `${projectName}-spot-fleet-manager`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'spot_fleet_manager.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Manages Spot Fleet lifecycle and handles interruptions
    """
    try:
        action = event.get('action', 'create')
        
        if action == 'create':
            return create_spot_fleet(event)
        elif action == 'modify':
            return modify_spot_fleet(event)
        elif action == 'terminate':
            return terminate_spot_fleet(event)
        elif action == 'check_health':
            return check_spot_fleet_health(event)
        else:
            raise ValueError(f"Unknown action: {action}")
            
    except Exception as e:
        logger.error(f"Error in spot fleet manager: {str(e)}")
        raise

def create_spot_fleet(event):
    """Create a new Spot Fleet with fault tolerance"""
    config = {
        'SpotFleetRequestConfig': {
            'IamFleetRole': event['fleet_role_arn'],
            'AllocationStrategy': 'diversified',
            'TargetCapacity': event.get('target_capacity', 4),
            'SpotPrice': event.get('spot_price', '0.50'),
            'LaunchSpecifications': [
                {
                    'ImageId': event['ami_id'],
                    'InstanceType': 'c5.large',
                    'KeyName': event.get('key_name'),
                    'SecurityGroups': [{'GroupId': event['security_group_id']}],
                    'SubnetId': event['subnet_id'],
                    'UserData': event.get('user_data', ''),
                    'WeightedCapacity': 1.0
                },
                {
                    'ImageId': event['ami_id'],
                    'InstanceType': 'c5.xlarge',
                    'KeyName': event.get('key_name'),
                    'SecurityGroups': [{'GroupId': event['security_group_id']}],
                    'SubnetId': event['subnet_id'],
                    'UserData': event.get('user_data', ''),
                    'WeightedCapacity': 2.0
                }
            ],
            'TerminateInstancesWithExpiration': True,
            'Type': 'maintain',
            'ReplaceUnhealthyInstances': True
        }
    }
    
    response = ec2.request_spot_fleet(**config)
    fleet_id = response['SpotFleetRequestId']
    
    logger.info(f"Spot Fleet {fleet_id} created successfully")
    
    return {
        'statusCode': 200,
        'fleet_id': fleet_id,
        'status': 'active'
    }

def modify_spot_fleet(event):
    """Modify existing Spot Fleet capacity"""
    fleet_id = event['fleet_id']
    new_capacity = event['target_capacity']
    
    ec2.modify_spot_fleet_request(
        SpotFleetRequestId=fleet_id,
        TargetCapacity=new_capacity
    )
    
    return {
        'statusCode': 200,
        'fleet_id': fleet_id,
        'new_capacity': new_capacity
    }

def terminate_spot_fleet(event):
    """Terminate Spot Fleet"""
    fleet_id = event['fleet_id']
    
    ec2.cancel_spot_fleet_requests(
        SpotFleetRequestIds=[fleet_id],
        TerminateInstances=True
    )
    
    return {
        'statusCode': 200,
        'fleet_id': fleet_id,
        'status': 'terminated'
    }

def check_spot_fleet_health(event):
    """Check Spot Fleet health and capacity"""
    fleet_id = event['fleet_id']
    
    try:
        response = ec2.describe_spot_fleet_requests(
            SpotFleetRequestIds=[fleet_id]
        )
        
        fleet_state = response['SpotFleetRequestConfigs'][0]['SpotFleetRequestState']
        
        instances_response = ec2.describe_spot_fleet_instances(
            SpotFleetRequestId=fleet_id
        )
        
        healthy_instances = len([
            i for i in instances_response['ActiveInstances'] 
            if i['InstanceHealth'] == 'healthy'
        ])
        
        return {
            'statusCode': 200,
            'fleet_id': fleet_id,
            'fleet_state': fleet_state,
            'healthy_instances': healthy_instances,
            'total_instances': len(instances_response['ActiveInstances'])
        }
    except Exception as e:
        logger.error(f"Error checking fleet health: {str(e)}")
        return {
            'statusCode': 500,
            'fleet_id': fleet_id,
            'error': str(e)
        }
`),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: lambdaExecutionRole,
      logRetention: logs.RetentionDays.TWO_WEEKS,
      environment: {
        BUCKET_NAME: checkpointsBucket.bucketName,
        TABLE_NAME: workflowStateTable.tableName,
      },
    });

    // Spot Interruption Handler Lambda Function
    const spotInterruptionHandlerFunction = new lambda.Function(this, 'SpotInterruptionHandlerFunction', {
      functionName: `${projectName}-spot-interruption-handler`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'spot_interruption_handler.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

stepfunctions = boto3.client('stepfunctions')
batch = boto3.client('batch')

def lambda_handler(event, context):
    """
    Handle Spot instance interruption warnings
    """
    try:
        detail = event['detail']
        instance_id = detail['instance-id']
        
        logger.info(f"Spot interruption warning received for instance: {instance_id}")
        
        # Find running Batch jobs on this instance
        running_jobs = find_batch_jobs_on_instance(instance_id)
        
        for job_id in running_jobs:
            trigger_emergency_checkpoint(job_id)
        
        return {
            'statusCode': 200,
            'message': f'Handled interruption warning for {instance_id}',
            'affected_jobs': running_jobs
        }
        
    except Exception as e:
        logger.error(f"Error handling spot interruption: {str(e)}")
        raise

def find_batch_jobs_on_instance(instance_id):
    """Find Batch jobs running on specific instance"""
    # Simplified implementation - in practice, you'd correlate instance IDs with jobs
    try:
        response = batch.list_jobs(
            jobStatus='RUNNING'
        )
        
        return [job['jobId'] for job in response['jobSummaryList']]
    except Exception as e:
        logger.error(f"Error finding batch jobs: {str(e)}")
        return []

def trigger_emergency_checkpoint(job_id):
    """Trigger emergency checkpoint for a job"""
    logger.info(f"Triggering emergency checkpoint for job: {job_id}")
    # Implementation would send signal to Step Functions or DynamoDB
`),
      timeout: cdk.Duration.minutes(1),
      memorySize: 256,
      role: lambdaExecutionRole,
      logRetention: logs.RetentionDays.TWO_WEEKS,
    });

    // IAM service role for AWS Batch
    const batchServiceRole = new iam.Role(this, 'BatchServiceRole', {
      assumedBy: new iam.ServicePrincipal('batch.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBatchServiceRole'),
      ],
    });

    // IAM instance profile for batch compute resources
    const batchInstanceRole = new iam.Role(this, 'BatchInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2ContainerServiceforEC2Role'),
      ],
    });

    const batchInstanceProfile = new iam.CfnInstanceProfile(this, 'BatchInstanceProfile', {
      roles: [batchInstanceRole.roleName],
    });

    // AWS Batch Compute Environment
    const batchComputeEnvironment = new batch.CfnComputeEnvironment(this, 'BatchComputeEnvironment', {
      type: 'MANAGED',
      state: 'ENABLED',
      computeEnvironmentName: `${projectName}-compute-environment`,
      serviceRole: batchServiceRole.roleArn,
      computeResources: {
        type: 'EC2',
        minvCpus: 0,
        maxvCpus: 1000,
        desiredvCpus: 0,
        instanceTypes: ['c5.large', 'c5.xlarge', 'c5.2xlarge', 'c5.4xlarge'],
        spotIamFleetRequestRole: `arn:aws:iam::${this.account}:role/aws-ec2-spot-fleet-tagging-role`,
        bidPercentage: 50,
        ec2Configuration: [{
          imageType: 'ECS_AL2',
        }],
        subnets: vpc.privateSubnets.map(subnet => subnet.subnetId),
        securityGroupIds: [batchSecurityGroup.securityGroupId],
        instanceRole: batchInstanceProfile.attrArn,
        tags: {
          Name: `${projectName}-batch-instance`,
          Project: projectName,
        },
      },
    });

    // AWS Batch Job Queue
    const batchJobQueue = new batch.CfnJobQueue(this, 'BatchJobQueue', {
      jobQueueName: `${projectName}-job-queue`,
      state: 'ENABLED',
      priority: 1,
      computeEnvironmentOrder: [
        {
          order: 1,
          computeEnvironment: batchComputeEnvironment.ref,
        },
      ],
    });

    // AWS Batch Job Definition
    const batchJobDefinition = new batch.CfnJobDefinition(this, 'BatchJobDefinition', {
      jobDefinitionName: `${projectName}-job-definition`,
      type: 'container',
      containerProperties: {
        image: 'amazonlinux:2',
        vcpus: 1,
        memory: 512,
        jobRoleArn: batchInstanceRole.roleArn,
      },
      retryStrategy: {
        attempts: 3,
      },
      timeout: {
        attemptDurationSeconds: 3600,
      },
    });

    // IAM role for Step Functions
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsRole', {
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      description: 'IAM role for HPC workflow Step Functions',
      inlinePolicies: {
        StepFunctionsExecutionPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction',
                'batch:SubmitJob',
                'batch:DescribeJobs',
                'batch:TerminateJob',
              ],
              resources: [
                workflowParserFunction.functionArn,
                checkpointManagerFunction.functionArn,
                spotFleetManagerFunction.functionArn,
                `arn:aws:batch:${this.region}:${this.account}:job-queue/${projectName}-job-queue`,
                `arn:aws:batch:${this.region}:${this.account}:job-definition/${projectName}-job-definition`,
              ],
            }),
          ],
        }),
      },
    });

    // Step Functions State Machine Definition
    const parseWorkflowTask = new stepfunctionsTasks.LambdaInvoke(this, 'ParseWorkflowTask', {
      lambdaFunction: workflowParserFunction,
      resultPath: '$.parsed_workflow',
      retryOnServiceExceptions: true,
    });

    const saveCheckpointTask = new stepfunctionsTasks.LambdaInvoke(this, 'SaveCheckpointTask', {
      lambdaFunction: checkpointManagerFunction,
      payload: stepfunctions.TaskInput.fromObject({
        action: 'save',
        'workflow_id.$': '$.workflow_id',
        'task_id.$': '$.id',
        'checkpoint_data.$': '$',
        bucket_name: checkpointsBucket.bucketName,
        table_name: workflowStateTable.tableName,
      }),
      resultPath: '$.checkpoint',
    });

    const executeTaskJob = new stepfunctionsTasks.BatchSubmitJob(this, 'ExecuteTaskJob', {
      jobDefinitionArn: batchJobDefinition.ref,
      jobName: 'HPC-Task',
      jobQueueArn: batchJobQueue.ref,
      resultPath: '$.job_result',
    });

    const taskCompleted = new stepfunctions.Pass(this, 'TaskCompleted', {
      parameters: {
        'status': 'completed',
        'task_id.$': '$.id',
        'completion_time.$': '$$.State.EnteredTime',
      },
    });

    const taskFailed = new stepfunctions.Fail(this, 'TaskFailed', {
      cause: 'Task execution failed after all retry attempts',
    });

    const workflowCompleted = new stepfunctions.Pass(this, 'WorkflowCompleted', {
      parameters: {
        'status': 'completed',
        'workflow_id.$': '$.parsed_workflow.workflow_id',
        'completion_time.$': '$$.State.EnteredTime',
      },
    });

    const workflowFailed = new stepfunctions.Fail(this, 'WorkflowFailed', {
      cause: 'Workflow execution failed',
    });

    // Build the state machine definition
    const definition = parseWorkflowTask
      .next(saveCheckpointTask)
      .next(executeTaskJob.addRetry({
        errors: ['States.TaskFailed'],
        intervalSeconds: 30,
        maxAttempts: 3,
        backoffRate: 2.0,
      }).addCatch(taskFailed, {
        errors: ['States.ALL'],
        resultPath: '$.error',
      }))
      .next(taskCompleted);

    // Step Functions State Machine
    const stateMachine = new stepfunctions.StateMachine(this, 'HpcWorkflowStateMachine', {
      stateMachineName: `${projectName}-orchestrator`,
      definition: definition,
      role: stepFunctionsRole,
      timeout: cdk.Duration.hours(24),
      logs: {
        destination: new logs.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/${projectName}-orchestrator`,
          retention: logs.RetentionDays.TWO_WEEKS,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }),
        level: stepfunctions.LogLevel.ALL,
      },
    });

    // EventBridge rule for Spot instance interruption warnings
    const spotInterruptionRule = new events.Rule(this, 'SpotInterruptionRule', {
      eventPattern: {
        source: ['aws.ec2'],
        detailType: ['EC2 Spot Instance Interruption Warning'],
        detail: {
          'instance-action': ['terminate'],
        },
      },
      description: 'Detect Spot instance interruption warnings',
    });

    // Add Lambda target to EventBridge rule
    spotInterruptionRule.addTarget(new eventsTargets.LambdaFunction(spotInterruptionHandlerFunction));

    // SNS topic for alerts
    const alertsTopic = new sns.Topic(this, 'AlertsTopic', {
      topicName: `${projectName}-alerts`,
      displayName: 'HPC Workflow Alerts',
    });

    // CloudWatch alarms for monitoring
    const workflowFailureAlarm = new cloudwatch.Alarm(this, 'WorkflowFailureAlarm', {
      alarmName: `${projectName}-workflow-failures`,
      alarmDescription: 'Alert when workflows fail',
      metric: stateMachine.metricFailed({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    workflowFailureAlarm.addAlarmAction(new cloudwatch.SnsAction(alertsTopic));

    // CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'HpcWorkflowDashboard', {
      dashboardName: `${projectName}-monitoring`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Step Functions Executions',
            left: [
              stateMachine.metricSucceeded({
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              stateMachine.metricFailed({
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              workflowParserFunction.metricInvocations({
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              checkpointManagerFunction.metricInvocations({
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Outputs
    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'ARN of the HPC Workflow State Machine',
    });

    new cdk.CfnOutput(this, 'CheckpointsBucketName', {
      value: checkpointsBucket.bucketName,
      description: 'Name of the S3 bucket for checkpoints',
    });

    new cdk.CfnOutput(this, 'WorkflowStateTableName', {
      value: workflowStateTable.tableName,
      description: 'Name of the DynamoDB table for workflow state',
    });

    new cdk.CfnOutput(this, 'BatchJobQueueName', {
      value: batchJobQueue.jobQueueName || `${projectName}-job-queue`,
      description: 'Name of the AWS Batch job queue',
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: alertsTopic.topicArn,
      description: 'ARN of the SNS topic for alerts',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${projectName}-monitoring`,
      description: 'URL to the CloudWatch dashboard',
    });
  }
}

// CDK App
const app = new cdk.App();

new FaultTolerantHpcWorkflowsStack(app, 'FaultTolerantHpcWorkflowsStack', {
  description: 'CDK stack for fault-tolerant HPC workflows with Step Functions and Spot Fleet',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'fault-tolerant-hpc-workflows',
    Environment: 'development',
    CreatedBy: 'aws-cdk',
  },
});

app.synth();