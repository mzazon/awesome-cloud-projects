import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as resourcegroups from 'aws-cdk-lib/aws-resourcegroups';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import * as path from 'path';

export class ResourceTaggingAutomationStack extends cdk.Stack {
  public readonly lambdaFunction: lambda.Function;
  public readonly eventBridgeRule: events.Rule;
  public readonly resourceGroup: resourcegroups.CfnGroup;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Standard tags to be applied by the Lambda function
    const standardTags = {
      AutoTagged: 'true',
      Environment: 'production',
      CostCenter: 'engineering',
      ManagedBy: 'automation',
    };

    // Create IAM role for Lambda function with least privilege permissions
    const lambdaRole = new iam.Role(this, 'AutoTaggerRole', {
      roleName: `AutoTaggerRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for automated resource tagging Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        AutoTaggingPolicy: new iam.PolicyDocument({
          statements: [
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
            }),
            // Resource tagging permissions for supported services
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:CreateTags',
                'ec2:DescribeInstances',
                'ec2:DescribeImages',
                'ec2:DescribeVolumes',
                's3:PutBucketTagging',
                's3:GetBucketTagging',
                'rds:AddTagsToResource',
                'rds:ListTagsForResource',
                'lambda:TagResource',
                'lambda:ListTags',
              ],
              resources: ['*'],
            }),
            // Resource Groups and tagging API permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'resource-groups:Tag',
                'resource-groups:GetTags',
                'tag:GetResources',
                'tag:TagResources',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Group for Lambda function with retention policy
    const logGroup = new logs.LogGroup(this, 'AutoTaggerLogGroup', {
      logGroupName: `/aws/lambda/auto-tagger-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for automated resource tagging
    this.lambdaFunction = new lambda.Function(this, 'AutoTaggerFunction', {
      functionName: `auto-tagger-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process CloudTrail events and apply tags to newly created resources
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', '')
        source_ip_address = detail.get('sourceIPAddress', 'unknown')
        user_identity = detail.get('userIdentity', {})
        user_name = user_identity.get('userName', user_identity.get('type', 'unknown'))
        
        logger.info(f"Processing event: {event_name} by user: {user_name}")
        
        # Define standard tags to apply
        standard_tags = {
            'AutoTagged': 'true',
            'Environment': 'production',
            'CostCenter': 'engineering',
            'CreatedBy': user_name,
            'CreatedDate': datetime.now().strftime('%Y-%m-%d'),
            'ManagedBy': 'automation'
        }
        
        # Process different resource types
        resources_tagged = 0
        
        if event_name == 'RunInstances':
            resources_tagged += tag_ec2_instances(detail, standard_tags)
        elif event_name == 'CreateBucket':
            resources_tagged += tag_s3_bucket(detail, standard_tags)
        elif event_name == 'CreateDBInstance':
            resources_tagged += tag_rds_instance(detail, standard_tags)
        elif event_name == 'CreateFunction20150331':
            resources_tagged += tag_lambda_function(detail, standard_tags)
        
        logger.info(f"Successfully tagged {resources_tagged} resources")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Tagged {resources_tagged} resources',
                'event': event_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def tag_ec2_instances(detail, tags):
    """Tag EC2 instances"""
    ec2 = boto3.client('ec2')
    instance_ids = []
    
    # Extract instance IDs from response elements
    response_elements = detail.get('responseElements', {})
    instances = response_elements.get('instancesSet', {}).get('items', [])
    
    for instance in instances:
        instance_ids.append(instance.get('instanceId'))
    
    if instance_ids:
        tag_list = [{'Key': k, 'Value': v} for k, v in tags.items()]
        ec2.create_tags(Resources=instance_ids, Tags=tag_list)
        logger.info(f"Tagged EC2 instances: {instance_ids}")
        return len(instance_ids)
    
    return 0

def tag_s3_bucket(detail, tags):
    """Tag S3 bucket"""
    s3 = boto3.client('s3')
    
    # Extract bucket name
    request_params = detail.get('requestParameters', {})
    bucket_name = request_params.get('bucketName')
    
    if bucket_name:
        tag_set = [{'Key': k, 'Value': v} for k, v in tags.items()]
        s3.put_bucket_tagging(
            Bucket=bucket_name,
            Tagging={'TagSet': tag_set}
        )
        logger.info(f"Tagged S3 bucket: {bucket_name}")
        return 1
    
    return 0

def tag_rds_instance(detail, tags):
    """Tag RDS instance"""
    rds = boto3.client('rds')
    
    # Extract DB instance identifier
    response_elements = detail.get('responseElements', {})
    db_instance = response_elements.get('dBInstance', {})
    db_instance_arn = db_instance.get('dBInstanceArn')
    
    if db_instance_arn:
        tag_list = [{'Key': k, 'Value': v} for k, v in tags.items()]
        rds.add_tags_to_resource(
            ResourceName=db_instance_arn,
            Tags=tag_list
        )
        logger.info(f"Tagged RDS instance: {db_instance_arn}")
        return 1
    
    return 0

def tag_lambda_function(detail, tags):
    """Tag Lambda function"""
    lambda_client = boto3.client('lambda')
    
    # Extract function name
    response_elements = detail.get('responseElements', {})
    function_arn = response_elements.get('functionArn')
    
    if function_arn:
        lambda_client.tag_resource(
            Resource=function_arn,
            Tags=tags
        )
        logger.info(f"Tagged Lambda function: {function_arn}")
        return 1
    
    return 0
      `),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Automated resource tagging function triggered by EventBridge',
      logGroup: logGroup,
      environment: {
        LOG_LEVEL: 'INFO',
        STANDARD_TAGS: JSON.stringify(standardTags),
      },
    });

    // Create EventBridge rule to capture resource creation events
    this.eventBridgeRule = new events.Rule(this, 'ResourceCreationRule', {
      ruleName: `resource-creation-rule-${uniqueSuffix}`,
      description: 'Trigger tagging for new AWS resources',
      enabled: true,
      eventPattern: {
        source: ['aws.ec2', 'aws.s3', 'aws.rds', 'aws.lambda'],
        detailType: ['AWS API Call via CloudTrail'],
        detail: {
          eventName: [
            'RunInstances',
            'CreateBucket',
            'CreateDBInstance',
            'CreateFunction20150331',
          ],
          eventSource: [
            'ec2.amazonaws.com',
            's3.amazonaws.com',
            'rds.amazonaws.com',
            'lambda.amazonaws.com',
          ],
        },
      },
      targets: [new targets.LambdaFunction(this.lambdaFunction)],
    });

    // Create Resource Group for auto-tagged resources
    this.resourceGroup = new resourcegroups.CfnGroup(this, 'AutoTaggedResourceGroup', {
      name: `auto-tagged-resources-${uniqueSuffix}`,
      description: 'Resources automatically tagged by Lambda function',
      resourceQuery: {
        type: 'TAG_FILTERS_1_0',
        query: {
          resourceTypeFilters: ['AWS::AllSupported'],
          tagFilters: [
            {
              key: 'AutoTagged',
              values: ['true'],
            },
          ],
        },
      },
      tags: [
        {
          key: 'Environment',
          value: 'production',
        },
        {
          key: 'Purpose',
          value: 'automation',
        },
      ],
    });

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Name of the auto-tagging Lambda function',
      exportName: `${this.stackName}-lambda-function-name`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'ARN of the auto-tagging Lambda function',
      exportName: `${this.stackName}-lambda-function-arn`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: this.eventBridgeRule.ruleName,
      description: 'Name of the EventBridge rule for resource creation events',
      exportName: `${this.stackName}-eventbridge-rule-name`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleArn', {
      value: this.eventBridgeRule.ruleArn,
      description: 'ARN of the EventBridge rule for resource creation events',
      exportName: `${this.stackName}-eventbridge-rule-arn`,
    });

    new cdk.CfnOutput(this, 'ResourceGroupName', {
      value: this.resourceGroup.name!,
      description: 'Name of the Resource Group for auto-tagged resources',
      exportName: `${this.stackName}-resource-group-name`,
    });

    new cdk.CfnOutput(this, 'IAMRoleName', {
      value: lambdaRole.roleName,
      description: 'Name of the IAM role used by the Lambda function',
      exportName: `${this.stackName}-iam-role-name`,
    });

    new cdk.CfnOutput(this, 'IAMRoleArn', {
      value: lambdaRole.roleArn,
      description: 'ARN of the IAM role used by the Lambda function',
      exportName: `${this.stackName}-iam-role-arn`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'Name of the CloudWatch Log Group for the Lambda function',
      exportName: `${this.stackName}-log-group-name`,
    });
  }
}