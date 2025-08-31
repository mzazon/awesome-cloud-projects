import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * AWS CDK Stack for Simple Log Retention Management with CloudWatch and Lambda
 * 
 * This stack creates:
 * - Lambda function for automated log retention management
 * - IAM role with appropriate permissions
 * - EventBridge rule for weekly execution
 * - Test log groups with various naming patterns
 */
export class SimpleLogRetentionStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LogRetentionManagerRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for automated CloudWatch Logs retention management',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        LogRetentionPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:DescribeLogGroups',
                'logs:PutRetentionPolicy',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for log retention management
    const logRetentionFunction = new lambda.Function(this, 'LogRetentionManagerFunction', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from botocore.exceptions import ClientError

# Initialize CloudWatch Logs client
logs_client = boto3.client('logs')

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def apply_retention_policy(log_group_name, retention_days):
    """Apply retention policy to a specific log group"""
    try:
        logs_client.put_retention_policy(
            logGroupName=log_group_name,
            retentionInDays=retention_days
        )
        logger.info(f"Applied {retention_days} day retention to {log_group_name}")
        return True
    except ClientError as e:
        logger.error(f"Failed to set retention for {log_group_name}: {e}")
        return False

def get_retention_days(log_group_name):
    """Determine appropriate retention period based on log group name patterns"""
    # Define retention rules based on log group naming patterns
    retention_rules = {
        '/aws/lambda/': 30,       # Lambda logs: 30 days
        '/aws/apigateway/': 90,   # API Gateway logs: 90 days  
        '/aws/codebuild/': 14,    # CodeBuild logs: 14 days
        '/aws/ecs/': 60,          # ECS logs: 60 days
        '/aws/stepfunctions/': 90, # Step Functions: 90 days
        '/application/': 180,     # Application logs: 180 days
        '/system/': 365,          # System logs: 1 year
    }
    
    # Check log group name against patterns
    for pattern, days in retention_rules.items():
        if pattern in log_group_name:
            return days
    
    # Default retention for unmatched patterns
    return int(os.environ.get('DEFAULT_RETENTION_DAYS', '30'))

def lambda_handler(event, context):
    """Main Lambda handler for log retention management"""
    try:
        processed_groups = 0
        updated_groups = 0
        errors = []
        
        # Get all log groups (paginated)
        paginator = logs_client.get_paginator('describe_log_groups')
        
        for page in paginator.paginate():
            for log_group in page['logGroups']:
                log_group_name = log_group['logGroupName']
                current_retention = log_group.get('retentionInDays')
                
                # Determine appropriate retention period
                target_retention = get_retention_days(log_group_name)
                
                processed_groups += 1
                
                # Apply retention policy if needed
                if current_retention != target_retention:
                    if apply_retention_policy(log_group_name, target_retention):
                        updated_groups += 1
                    else:
                        errors.append(log_group_name)
                else:
                    logger.info(f"Log group {log_group_name} already has correct retention: {current_retention} days")
        
        # Return summary
        result = {
            'statusCode': 200,
            'message': f'Processed {processed_groups} log groups, updated {updated_groups} retention policies',
            'processedGroups': processed_groups,
            'updatedGroups': updated_groups,
            'errors': errors
        }
        
        logger.info(json.dumps(result))
        return result
        
    except Exception as e:
        logger.error(f"Error in log retention management: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
      `),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Automated CloudWatch Logs retention management function',
      environment: {
        DEFAULT_RETENTION_DAYS: '30',
      },
      // Configure log retention for the Lambda function itself
      logRetention: logs.RetentionDays.ONE_MONTH,
      logRemovalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create EventBridge rule for weekly execution
    const scheduleRule = new events.Rule(this, 'LogRetentionScheduleRule', {
      schedule: events.Schedule.rate(cdk.Duration.days(7)),
      description: 'Weekly log retention policy management schedule',
      enabled: true,
    });

    // Add Lambda function as target for the EventBridge rule
    scheduleRule.addTarget(new targets.LambdaFunction(logRetentionFunction));

    // Create test log groups with different naming patterns to demonstrate functionality
    const testLogGroups = [
      {
        name: '/aws/lambda/test-function',
        expectedRetention: 30,
        description: 'Lambda function logs (30 days retention)',
      },
      {
        name: '/aws/apigateway/test-api',
        expectedRetention: 90,
        description: 'API Gateway logs (90 days retention)',
      },
      {
        name: '/application/web-app',
        expectedRetention: 180,
        description: 'Application logs (180 days retention)',
      },
      {
        name: '/system/monitoring',
        expectedRetention: 365,
        description: 'System logs (365 days retention)',
      },
    ];

    // Create test log groups
    testLogGroups.forEach((logGroupConfig, index) => {
      new logs.LogGroup(this, `TestLogGroup${index + 1}`, {
        logGroupName: `${logGroupConfig.name}-${this.stackName.toLowerCase()}`,
        // Initially create without retention to demonstrate the Lambda function setting it
        retention: logs.RetentionDays.INFINITE,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cdk.aws_cloudwatch.Dashboard(this, 'LogRetentionDashboard', {
      dashboardName: `log-retention-management-${this.stackName.toLowerCase()}`,
      defaultInterval: cdk.Duration.hours(24),
    });

    // Add Lambda function metrics to dashboard
    dashboard.addWidgets(
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'Lambda Function Metrics',
        left: [
          logRetentionFunction.metricInvocations({
            label: 'Invocations',
            period: cdk.Duration.minutes(5),
          }),
          logRetentionFunction.metricErrors({
            label: 'Errors',
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          logRetentionFunction.metricDuration({
            label: 'Duration',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 24,
        height: 6,
      }),
    );

    // Output important information
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: logRetentionFunction.functionName,
      description: 'Name of the log retention management Lambda function',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: logRetentionFunction.functionArn,
      description: 'ARN of the log retention management Lambda function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'ScheduleRuleName', {
      value: scheduleRule.ruleName,
      description: 'Name of the EventBridge rule for weekly execution',
      exportName: `${this.stackName}-ScheduleRuleName`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for monitoring',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    // Add tags to all resources for cost tracking and management
    cdk.Tags.of(this).add('Project', 'SimpleLogRetention');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CostCenter', 'LogManagement');
  }
}

// CDK App
const app = new cdk.App();

new SimpleLogRetentionStack(app, 'SimpleLogRetentionStack', {
  description: 'Simple Log Retention Management with CloudWatch and Lambda - AWS CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();