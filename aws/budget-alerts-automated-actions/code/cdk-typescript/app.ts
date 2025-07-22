#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Properties for the BudgetAlertsStack
 */
interface BudgetAlertsStackProps extends cdk.StackProps {
  /**
   * Email address for budget notifications
   */
  readonly notificationEmail: string;
  
  /**
   * Monthly budget limit in USD
   * @default 100
   */
  readonly budgetLimitUsd?: number;
  
  /**
   * Environment prefix for resource naming
   * @default 'budget-alerts'
   */
  readonly environmentPrefix?: string;
}

/**
 * CDK Stack that implements AWS Budget Alerts and Automated Actions
 * 
 * This stack creates:
 * - AWS Budget with multiple alert thresholds
 * - SNS topic for notifications
 * - Lambda function for automated cost control actions
 * - IAM roles and policies for budget actions
 * - Email subscriptions for budget alerts
 */
export class BudgetAlertsStack extends cdk.Stack {
  
  public readonly snsTopic: sns.Topic;
  public readonly budgetActionFunction: lambda.Function;
  public readonly budget: budgets.CfnBudget;
  
  constructor(scope: Construct, id: string, props: BudgetAlertsStackProps) {
    super(scope, id, props);
    
    // Validate required properties
    if (!props.notificationEmail) {
      throw new Error('notificationEmail is required');
    }
    
    const budgetLimit = props.budgetLimitUsd || 100;
    const prefix = props.environmentPrefix || 'budget-alerts';
    
    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    
    // Create SNS Topic for Budget Notifications
    this.snsTopic = new sns.Topic(this, 'BudgetAlertsTopic', {
      topicName: `${prefix}-topic-${uniqueSuffix}`,
      displayName: 'AWS Budget Alerts and Notifications',
      description: 'SNS topic for AWS Budget alerts and automated actions',
    });
    
    // Add email subscription to SNS topic
    this.snsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(props.notificationEmail)
    );
    
    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'BudgetActionLogGroup', {
      logGroupName: `/aws/lambda/${prefix}-action-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    
    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'BudgetActionLambdaRole', {
      roleName: `${prefix}-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for budget action Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });
    
    // Add custom policy for Lambda function permissions
    const lambdaPolicy = new iam.Policy(this, 'BudgetActionLambdaPolicy', {
      policyName: `${prefix}-lambda-policy-${uniqueSuffix}`,
      statements: [
        // CloudWatch Logs permissions
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'logs:CreateLogGroup',
            'logs:CreateLogStream',
            'logs:PutLogEvents',
          ],
          resources: [logGroup.logGroupArn],
        }),
        // EC2 permissions for instance management
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:DescribeInstances',
            'ec2:StopInstances',
            'ec2:StartInstances',
            'ec2:DescribeInstanceStatus',
          ],
          resources: ['*'],
        }),
        // SNS permissions for notifications
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sns:Publish'],
          resources: [this.snsTopic.topicArn],
        }),
        // Budget permissions for monitoring
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'budgets:ViewBudget',
            'budgets:ModifyBudget',
          ],
          resources: ['*'],
        }),
      ],
    });
    
    lambdaRole.attachInlinePolicy(lambdaPolicy);
    
    // Create Lambda function for automated budget actions
    this.budgetActionFunction = new lambda.Function(this, 'BudgetActionFunction', {
      functionName: `${prefix}-action-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      description: 'Automated budget action function for cost control',
      environment: {
        SNS_TOPIC_ARN: this.snsTopic.topicArn,
        LOG_LEVEL: 'INFO',
      },
      logGroup: logGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Lambda function to handle budget alerts and execute automated actions.
    
    This function:
    1. Parses budget alert messages from SNS
    2. Identifies development instances to stop
    3. Executes cost control actions
    4. Sends notifications about actions taken
    """
    try:
        # Parse the budget alert event from SNS
        if 'Records' not in event or not event['Records']:
            logger.error("No SNS records found in event")
            return {'statusCode': 400, 'body': 'Invalid event format'}
        
        # Extract SNS message
        sns_message = event['Records'][0]['Sns']['Message']
        message = json.loads(sns_message) if isinstance(sns_message, str) else sns_message
        
        budget_name = message.get('BudgetName', 'Unknown')
        account_id = message.get('AccountId', context.invoked_function_arn.split(':')[4])
        alert_type = message.get('AlertType', 'ACTUAL')
        threshold = message.get('Threshold', 'Unknown')
        
        logger.info(f"Budget alert triggered: {budget_name} ({alert_type}) at {threshold}% threshold")
        
        # Initialize AWS clients
        ec2 = boto3.client('ec2')
        sns_client = boto3.client('sns')
        
        # Find development instances to stop
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Environment', 'Values': ['Development', 'Dev', 'development', 'dev']},
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        instances_to_stop = []
        instance_details = []
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_type = instance.get('InstanceType', 'unknown')
                instance_name = 'Unknown'
                
                # Get instance name from tags
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        instance_name = tag['Value']
                        break
                
                instances_to_stop.append(instance_id)
                instance_details.append({
                    'id': instance_id,
                    'name': instance_name,
                    'type': instance_type
                })
        
        # Execute budget actions
        actions_taken = []
        
        if instances_to_stop:
            # Stop development instances
            ec2.stop_instances(InstanceIds=instances_to_stop)
            action_message = f"Stopped {len(instances_to_stop)} development instances"
            actions_taken.append(action_message)
            logger.info(action_message)
            
            # Create detailed notification message
            instance_list = "\\n".join([
                f"  - {detail['name']} ({detail['id']}) - {detail['type']}"
                for detail in instance_details
            ])
            
            notification_message = f"""
Budget Alert Action Executed

Budget: {budget_name}
Account: {account_id}
Alert Type: {alert_type}
Threshold: {threshold}%

Automated Actions Taken:
- Stopped {len(instances_to_stop)} development instances

Affected Instances:
{instance_list}

This automated action was triggered to help control costs when budget thresholds are exceeded.
Production instances were not affected.

For questions about this action, review your budget configuration in the AWS Budgets console.
            """.strip()
            
            # Send notification via SNS
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'Budget Action Executed - {budget_name}',
                Message=notification_message
            )
            
        else:
            no_action_message = "No development instances found to stop"
            actions_taken.append(no_action_message)
            logger.info(no_action_message)
            
            # Send notification that no action was needed
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'Budget Alert Received - {budget_name}',
                Message=f"""
Budget Alert Received

Budget: {budget_name}
Account: {account_id}
Alert Type: {alert_type}
Threshold: {threshold}%

No automated actions were taken as no running development instances were found.
Please review your current AWS usage and consider manual cost optimization actions.
                """.strip()
            )
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Budget action completed for {budget_name}',
                'budget_name': budget_name,
                'alert_type': alert_type,
                'threshold': threshold,
                'instances_stopped': len(instances_to_stop),
                'actions_taken': actions_taken
            })
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse SNS message: {str(e)}")
        return {'statusCode': 400, 'body': f'JSON parsing error: {str(e)}'}
    except Exception as e:
        logger.error(f"Error executing budget action: {str(e)}")
        return {'statusCode': 500, 'body': f'Execution error: {str(e)}'}
`),
    });
    
    // Allow SNS to invoke the Lambda function
    this.budgetActionFunction.addPermission('AllowSNSInvoke', {
      principal: new iam.ServicePrincipal('sns.amazonaws.com'),
      sourceArn: this.snsTopic.topicArn,
    });
    
    // Subscribe Lambda function to SNS topic
    this.snsTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(this.budgetActionFunction)
    );
    
    // Create IAM policy for budget actions (cost control restrictions)
    const budgetRestrictionPolicy = new iam.ManagedPolicy(this, 'BudgetRestrictionPolicy', {
      managedPolicyName: `budget-restriction-policy-${uniqueSuffix}`,
      description: 'Policy to restrict expensive resources when budget thresholds are exceeded',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.DENY,
          actions: [
            'ec2:RunInstances',
            'ec2:StartInstances',
            'rds:CreateDBInstance',
            'rds:StartDBInstance',
          ],
          resources: ['*'],
          conditions: {
            StringNotEquals: {
              'ec2:InstanceType': [
                't3.nano',
                't3.micro',
                't3.small',
                't2.nano',
                't2.micro',
                't2.small',
              ],
            },
          },
        }),
      ],
    });
    
    // Create IAM role for AWS Budgets service to execute actions
    const budgetActionRole = new iam.Role(this, 'BudgetActionRole', {
      roleName: `budget-action-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('budgets.amazonaws.com'),
      description: 'IAM role for AWS Budgets to execute automated actions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/BudgetsActionsWithAWSResourceControlAccess'),
      ],
    });
    
    // Create the AWS Budget with multiple notification thresholds
    this.budget = new budgets.CfnBudget(this, 'CostControlBudget', {
      budget: {
        budgetName: `cost-control-budget-${uniqueSuffix}`,
        budgetType: 'COST',
        timeUnit: 'MONTHLY',
        budgetLimit: {
          amount: budgetLimit,
          unit: 'USD',
        },
        costTypes: {
          includeCredit: false,
          includeDiscount: true,
          includeOtherSubscription: true,
          includeRecurring: true,
          includeRefund: true,
          includeSubscription: true,
          includeSupport: true,
          includeTax: true,
          includeUpfront: true,
          useBlended: false,
          useAmortized: false,
        },
        timePeriod: {
          start: new Date().toISOString().split('T')[0],
          end: new Date(Date.now() + 2 * 365 * 24 * 60 * 60 * 1000).toISOString().split('T')[0], // 2 years from now
        },
      },
      notificationsWithSubscribers: [
        {
          notification: {
            notificationType: 'ACTUAL',
            comparisonOperator: 'GREATER_THAN',
            threshold: 80,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              subscriptionType: 'EMAIL',
              address: props.notificationEmail,
            },
            {
              subscriptionType: 'SNS',
              address: this.snsTopic.topicArn,
            },
          ],
        },
        {
          notification: {
            notificationType: 'FORECASTED',
            comparisonOperator: 'GREATER_THAN',
            threshold: 90,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              subscriptionType: 'EMAIL',
              address: props.notificationEmail,
            },
            {
              subscriptionType: 'SNS',
              address: this.snsTopic.topicArn,
            },
          ],
        },
        {
          notification: {
            notificationType: 'ACTUAL',
            comparisonOperator: 'GREATER_THAN',
            threshold: 100,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              subscriptionType: 'EMAIL',
              address: props.notificationEmail,
            },
            {
              subscriptionType: 'SNS',
              address: this.snsTopic.topicArn,
            },
          ],
        },
      ],
    });
    
    // Add tags to all resources for better organization
    const tags = {
      Application: 'BudgetAlerts',
      Purpose: 'CostControl',
      Environment: 'Production',
      ManagedBy: 'CDK',
    };
    
    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
    
    // Output important resource information
    new cdk.CfnOutput(this, 'BudgetName', {
      value: this.budget.budget.budgetName!,
      description: 'Name of the created AWS Budget',
    });
    
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'ARN of the SNS topic for budget alerts',
    });
    
    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.budgetActionFunction.functionArn,
      description: 'ARN of the Lambda function for budget actions',
    });
    
    new cdk.CfnOutput(this, 'BudgetLimit', {
      value: budgetLimit.toString(),
      description: 'Monthly budget limit in USD',
    });
    
    new cdk.CfnOutput(this, 'NotificationEmail', {
      value: props.notificationEmail,
      description: 'Email address for budget notifications',
    });
    
    new cdk.CfnOutput(this, 'BudgetRestrictionPolicyArn', {
      value: budgetRestrictionPolicy.managedPolicyArn,
      description: 'ARN of the IAM policy for budget-based restrictions',
    });
    
    new cdk.CfnOutput(this, 'BudgetActionRoleArn', {
      value: budgetActionRole.roleArn,
      description: 'ARN of the IAM role for AWS Budgets actions',
    });
  }
}

// Main CDK App
const app = new cdk.App();

// Get context values for configuration
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.BUDGET_EMAIL;
const budgetLimit = parseInt(app.node.tryGetContext('budgetLimit') || process.env.BUDGET_LIMIT || '100');
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || process.env.ENVIRONMENT_PREFIX || 'budget-alerts';

// Validate required parameters
if (!notificationEmail) {
  throw new Error(
    'notificationEmail is required. Set it via context (-c notificationEmail=your-email@example.com) or environment variable BUDGET_EMAIL'
  );
}

// Create the stack
new BudgetAlertsStack(app, 'BudgetAlertsStack', {
  notificationEmail,
  budgetLimitUsd: budgetLimit,
  environmentPrefix,
  
  // Stack properties
  description: 'AWS Budget Alerts and Automated Actions - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Enable termination protection for production
  terminationProtection: false, // Set to true for production deployments
  
  tags: {
    Project: 'AWS-Budget-Alerts',
    CreatedBy: 'CDK-TypeScript',
    Purpose: 'Cost-Management',
    Environment: 'Development', // Change to 'Production' for production deployments
  },
});

// Synthesize the app
app.synth();