import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as ce from 'aws-cdk-lib/aws-ce';
import * as cur from 'aws-cdk-lib/aws-cur';
import { Construct } from 'constructs';

/**
 * Cost Allocation and Chargeback Stack
 * 
 * This stack creates a comprehensive cost allocation and chargeback system
 * that enables organizations to track, allocate, and manage cloud costs
 * across departments and business units.
 */
export class CostAllocationChargebackStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create unique suffix for resource naming
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // ========== S3 Bucket for Cost Reports ==========
    const costReportsBucket = new s3.Bucket(this, 'CostReportsBucket', {
      bucketName: `cost-allocation-reports-${uniqueSuffix}`,
      versioned: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [{
        id: 'CostReportsLifecycle',
        enabled: true,
        transitions: [{
          storageClass: s3.StorageClass.INTELLIGENT_TIERING,
          transitionAfter: cdk.Duration.days(30)
        }, {
          storageClass: s3.StorageClass.GLACIER,
          transitionAfter: cdk.Duration.days(90)
        }],
        expiration: cdk.Duration.days(2555) // 7 years for compliance
      }]
    });

    // Add bucket policy for Cost and Usage Reports service
    costReportsBucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AllowCURServiceAccess',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('billingreports.amazonaws.com')],
      actions: [
        's3:GetBucketAcl',
        's3:GetBucketPolicy',
        's3:PutObject'
      ],
      resources: [
        costReportsBucket.bucketArn,
        `${costReportsBucket.bucketArn}/*`
      ]
    }));

    // ========== Cost and Usage Report ==========
    const costUsageReport = new cur.CfnReportDefinition(this, 'CostUsageReport', {
      reportName: 'cost-allocation-report',
      timeUnit: 'DAILY',
      format: 'textORcsv',
      compression: 'GZIP',
      additionalSchemaElements: ['RESOURCES'],
      s3Bucket: costReportsBucket.bucketName,
      s3Prefix: 'cost-reports/',
      s3Region: this.region,
      additionalArtifacts: ['REDSHIFT', 'ATHENA'],
      refreshClosedReports: true,
      reportVersioning: 'OVERWRITE_REPORT'
    });

    // ========== SNS Topic for Cost Alerts ==========
    const costAlertsTopic = new sns.Topic(this, 'CostAlertsTopic', {
      topicName: `cost-allocation-alerts-${uniqueSuffix}`,
      displayName: 'Cost Allocation Alerts',
      fifo: false
    });

    // Add topic policy to allow AWS Budgets to publish
    costAlertsTopic.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AllowBudgetsToPublish',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('budgets.amazonaws.com')],
      actions: ['sns:Publish'],
      resources: [costAlertsTopic.topicArn]
    }));

    // ========== Lambda Function for Cost Processing ==========
    const costProcessorFunction = new lambda.Function(this, 'CostProcessorFunction', {
      functionName: `cost-allocation-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'cost_processor.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        COST_BUCKET_NAME: costReportsBucket.bucketName,
        SNS_TOPIC_ARN: costAlertsTopic.topicArn,
        AWS_REGION: this.region
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import csv
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Process cost allocation data and generate chargeback reports
    """
    ce_client = boto3.client('ce')
    sns_client = boto3.client('sns')
    
    # Get cost data for the last 30 days
    end_date = datetime.now().strftime('%Y-%m-%d')
    start_date = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
    
    try:
        # Query costs by department
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'TAG',
                    'Key': 'Department'
                }
            ]
        )
        
        # Process cost data
        department_costs = {}
        for result in response['ResultsByTime']:
            for group in result['Groups']:
                dept = group['Keys'][0] if group['Keys'][0] != 'No Department' else 'Untagged'
                cost = float(group['Metrics']['BlendedCost']['Amount'])
                department_costs[dept] = department_costs.get(dept, 0) + cost
        
        # Create chargeback report
        report = {
            'report_date': end_date,
            'period': f"{start_date} to {end_date}",
            'department_costs': department_costs,
            'total_cost': sum(department_costs.values())
        }
        
        # Send notification with summary
        message = f"""
Cost Allocation Report - {end_date}

Department Breakdown:
"""
        for dept, cost in department_costs.items():
            message += f"• {dept}: ${cost:.2f}\\n"
        
        message += f"\\nTotal Cost: ${report['total_cost']:.2f}"
        
        sns_client.publish(
            TopicArn=context.invoked_function_arn.replace(':function:', ':sns:').replace(context.function_name, '${costAlertsTopic.topicName}'),
            Subject='Monthly Cost Allocation Report',
            Message=message
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(report, default=str)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error processing costs: {str(e)}")
        }
`)
    });

    // Grant Lambda permissions for Cost Explorer, S3, and SNS
    costProcessorFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ce:GetCostAndUsage',
        'ce:GetUsageReport',
        'ce:ListCostCategoryDefinitions',
        'ce:GetCostCategories'
      ],
      resources: ['*']
    }));

    costReportsBucket.grantReadWrite(costProcessorFunction);
    costAlertsTopic.grantPublish(costProcessorFunction);

    // ========== EventBridge Schedule for Monthly Processing ==========
    const monthlyScheduleRule = new events.Rule(this, 'MonthlyScheduleRule', {
      ruleName: `cost-allocation-schedule-${uniqueSuffix}`,
      description: 'Monthly cost allocation processing',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '9',
        day: '1',
        month: '*',
        year: '*'
      })
    });

    monthlyScheduleRule.addTarget(new targets.LambdaFunction(costProcessorFunction));

    // ========== Cost Categories for Department Grouping ==========
    const costCategoryDefinition = new ce.CfnCostCategory(this, 'DepartmentCostCategory', {
      name: 'CostCenter',
      ruleVersion: 'CostCategoryExpression.v1',
      rules: JSON.stringify([
        {
          Value: 'Engineering',
          Rule: {
            Tags: {
              Key: 'Department',
              Values: ['Engineering', 'Development', 'DevOps']
            }
          }
        },
        {
          Value: 'Marketing',
          Rule: {
            Tags: {
              Key: 'Department',
              Values: ['Marketing', 'Sales', 'Customer Success']
            }
          }
        },
        {
          Value: 'Operations',
          Rule: {
            Tags: {
              Key: 'Department',
              Values: ['Operations', 'Finance', 'HR']
            }
          }
        }
      ])
    });

    // ========== AWS Budgets for Department Cost Control ==========
    
    // Engineering Department Budget
    const engineeringBudget = new budgets.CfnBudget(this, 'EngineeringBudget', {
      budget: {
        budgetName: 'Engineering-Monthly-Budget',
        budgetLimit: {
          amount: 1000,
          unit: 'USD'
        },
        timeUnit: 'MONTHLY',
        budgetType: 'COST',
        costFilters: {
          TagKey: ['Department'],
          TagValue: ['Engineering']
        }
      },
      notificationsWithSubscribers: [{
        notification: {
          notificationType: 'ACTUAL',
          comparisonOperator: 'GREATER_THAN',
          threshold: 80,
          thresholdType: 'PERCENTAGE'
        },
        subscribers: [{
          subscriptionType: 'SNS',
          address: costAlertsTopic.topicArn
        }]
      }, {
        notification: {
          notificationType: 'FORECASTED',
          comparisonOperator: 'GREATER_THAN',
          threshold: 100,
          thresholdType: 'PERCENTAGE'
        },
        subscribers: [{
          subscriptionType: 'SNS',
          address: costAlertsTopic.topicArn
        }]
      }]
    });

    // Marketing Department Budget
    const marketingBudget = new budgets.CfnBudget(this, 'MarketingBudget', {
      budget: {
        budgetName: 'Marketing-Monthly-Budget',
        budgetLimit: {
          amount: 500,
          unit: 'USD'
        },
        timeUnit: 'MONTHLY',
        budgetType: 'COST',
        costFilters: {
          TagKey: ['Department'],
          TagValue: ['Marketing']
        }
      },
      notificationsWithSubscribers: [{
        notification: {
          notificationType: 'ACTUAL',
          comparisonOperator: 'GREATER_THAN',
          threshold: 75,
          thresholdType: 'PERCENTAGE'
        },
        subscribers: [{
          subscriptionType: 'SNS',
          address: costAlertsTopic.topicArn
        }]
      }]
    });

    // Operations Department Budget
    const operationsBudget = new budgets.CfnBudget(this, 'OperationsBudget', {
      budget: {
        budgetName: 'Operations-Monthly-Budget',
        budgetLimit: {
          amount: 750,
          unit: 'USD'
        },
        timeUnit: 'MONTHLY',
        budgetType: 'COST',
        costFilters: {
          TagKey: ['Department'],
          TagValue: ['Operations']
        }
      },
      notificationsWithSubscribers: [{
        notification: {
          notificationType: 'ACTUAL',
          comparisonOperator: 'GREATER_THAN',
          threshold: 85,
          thresholdType: 'PERCENTAGE'
        },
        subscribers: [{
          subscriptionType: 'SNS',
          address: costAlertsTopic.topicArn
        }]
      }]
    });

    // ========== Cost Anomaly Detection ==========
    const anomalyDetector = new ce.CfnAnomalyDetector(this, 'DepartmentAnomalyDetector', {
      anomalyDetector: {
        detectorName: 'DepartmentCostAnomalyDetector',
        monitorType: 'DIMENSIONAL',
        dimensionKey: 'TAG',
        matchOptions: ['EQUALS'],
        monitorSpecification: 'Department'
      }
    });

    const anomalySubscription = new ce.CfnAnomalySubscription(this, 'CostAnomalySubscription', {
      anomalySubscription: {
        subscriptionName: 'CostAnomalyAlerts',
        monitorArnList: [anomalyDetector.attrDetectorArn],
        subscribers: [{
          address: costAlertsTopic.topicArn,
          type: 'SNS'
        }],
        threshold: 100,
        frequency: 'DAILY'
      }
    });

    // ========== Stack Outputs ==========
    new cdk.CfnOutput(this, 'CostReportsBucketName', {
      value: costReportsBucket.bucketName,
      description: 'S3 bucket name for cost reports storage',
      exportName: `${this.stackName}-CostReportsBucket`
    });

    new cdk.CfnOutput(this, 'CostAlertsTopicArn', {
      value: costAlertsTopic.topicArn,
      description: 'SNS topic ARN for cost alerts and notifications',
      exportName: `${this.stackName}-CostAlertsTopic`
    });

    new cdk.CfnOutput(this, 'CostProcessorFunctionName', {
      value: costProcessorFunction.functionName,
      description: 'Lambda function name for cost processing',
      exportName: `${this.stackName}-CostProcessorFunction`
    });

    new cdk.CfnOutput(this, 'CostCategoryArn', {
      value: costCategoryDefinition.attrArn,
      description: 'Cost category ARN for department grouping',
      exportName: `${this.stackName}-CostCategory`
    });

    new cdk.CfnOutput(this, 'AnomalyDetectorArn', {
      value: anomalyDetector.attrDetectorArn,
      description: 'Cost anomaly detector ARN',
      exportName: `${this.stackName}-AnomalyDetector`
    });

    // Tag all resources for cost allocation
    cdk.Tags.of(this).add('Project', 'CostAllocationChargeback');
    cdk.Tags.of(this).add('Department', 'Finance');
    cdk.Tags.of(this).add('CostCenter', 'FinanceOperations');
    cdk.Tags.of(this).add('Environment', 'Production');
  }
}