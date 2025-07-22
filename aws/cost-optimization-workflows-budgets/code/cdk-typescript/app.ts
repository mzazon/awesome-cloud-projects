#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { 
  aws_budgets as budgets,
  aws_sns as sns,
  aws_sns_subscriptions as snsSubscriptions,
  aws_lambda as lambda,
  aws_iam as iam,
  aws_ce as ce,
  aws_logs as logs,
  Duration,
  Stack,
  StackProps,
  CfnOutput,
  RemovalPolicy
} from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as path from 'path';

/**
 * Properties for the AutomatedCostOptimizationStack
 */
export interface AutomatedCostOptimizationStackProps extends StackProps {
  /**
   * Monthly budget limit in USD
   * @default 1000
   */
  readonly monthlyBudgetLimit?: number;
  
  /**
   * EC2 usage budget limit in hours
   * @default 2000
   */
  readonly ec2UsageBudgetLimit?: number;
  
  /**
   * Reserved Instance utilization threshold percentage
   * @default 80
   */
  readonly riUtilizationThreshold?: number;
  
  /**
   * Email address for budget notifications
   */
  readonly notificationEmail: string;
  
  /**
   * Budget alert threshold percentage
   * @default 80
   */
  readonly budgetAlertThreshold?: number;
}

/**
 * Stack for automated cost optimization workflows using AWS Cost Optimization Hub and AWS Budgets
 */
export class AutomatedCostOptimizationStack extends Stack {
  public readonly snsTopicArn: string;
  public readonly lambdaFunctionArn: string;
  public readonly budgetNames: string[];

  constructor(scope: Construct, id: string, props: AutomatedCostOptimizationStackProps) {
    super(scope, id, props);

    // Extract props with defaults
    const monthlyBudgetLimit = props.monthlyBudgetLimit ?? 1000;
    const ec2UsageBudgetLimit = props.ec2UsageBudgetLimit ?? 2000;
    const riUtilizationThreshold = props.riUtilizationThreshold ?? 80;
    const budgetAlertThreshold = props.budgetAlertThreshold ?? 80;
    const notificationEmail = props.notificationEmail;

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6);

    // Create SNS Topic for cost optimization notifications
    const costOptimizationTopic = new sns.Topic(this, 'CostOptimizationTopic', {
      topicName: `cost-optimization-alerts-${uniqueSuffix}`,
      displayName: 'AWS Cost Optimization Alerts',
      description: 'Notifications for budget alerts and cost optimization recommendations'
    });

    // Subscribe email to SNS topic
    costOptimizationTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(notificationEmail)
    );

    // Create IAM role for Lambda function
    const lambdaExecutionRole = new iam.Role(this, 'CostOptimizationLambdaRole', {
      roleName: `CostOptimizationLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for cost optimization Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CostOptimizationHubServiceRolePolicy')
      ],
      inlinePolicies: {
        CostOptimizationPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ce:GetCostAndUsage',
                'ce:GetDimensionValues',
                'ce:GetReservationCoverage',
                'ce:GetReservationPurchaseRecommendation',
                'ce:GetReservationUtilization',
                'ce:GetSavingsPlansUtilization',
                'ce:ListCostCategoryDefinitions',
                'cost-optimization-hub:GetPreferences',
                'cost-optimization-hub:ListRecommendations',
                'cost-optimization-hub:ListRecommendationSummaries',
                'cost-optimization-hub:GetRecommendation',
                'sns:Publish'
              ],
              resources: ['*']
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish'
              ],
              resources: [costOptimizationTopic.topicArn]
            })
          ]
        })
      }
    });

    // Create Lambda function for cost optimization automation
    const costOptimizationFunction = new lambda.Function(this, 'CostOptimizationFunction', {
      functionName: `cost-optimization-handler-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'cost_optimization_handler.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Cost Optimization Hub recommendations and budget alerts
    
    Args:
        event: Lambda event containing SNS messages or direct invocation
        context: Lambda context object
        
    Returns:
        Response dictionary with status and message
    """
    try:
        # Initialize AWS clients
        coh_client = boto3.client('cost-optimization-hub')
        ce_client = boto3.client('ce')
        sns_client = boto3.client('sns')
        
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Process SNS message from budget alerts
        if 'Records' in event:
            for record in event['Records']:
                if record.get('EventSource') == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    logger.info(f"Processing budget alert: {message}")
                    
                    # Process budget alert
                    await process_budget_alert(message, coh_client, sns_client)
        else:
            # Direct invocation - process cost optimization recommendations
            await process_cost_recommendations(coh_client, sns_client)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization processing completed successfully',
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing cost optimization: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Error processing cost optimization: {str(e)}',
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        }

async def process_budget_alert(message: Dict[str, Any], coh_client, sns_client) -> None:
    """Process budget alert and get relevant cost optimization recommendations"""
    try:
        budget_name = message.get('BudgetName', 'Unknown')
        alert_type = message.get('MessageType', 'Unknown')
        
        logger.info(f"Processing budget alert for {budget_name} - {alert_type}")
        
        # Get cost optimization recommendations
        recommendations = coh_client.list_recommendations(
            includeAllRecommendations=True,
            maxResults=10
        )
        
        # Create summary of top recommendations
        rec_summary = create_recommendation_summary(recommendations.get('items', []))
        
        # Send notification with recommendations
        notification_message = f"""
Budget Alert: {budget_name}
Alert Type: {alert_type}
Timestamp: {datetime.now(timezone.utc).isoformat()}

Top Cost Optimization Recommendations:
{rec_summary}

Please review these recommendations in the AWS Cost Optimization Hub console.
        """
        
        sns_client.publish(
            TopicArn='${costOptimizationTopic.topicArn}',
            Subject=f'Cost Optimization Recommendations - {budget_name}',
            Message=notification_message
        )
        
    except Exception as e:
        logger.error(f"Error processing budget alert: {str(e)}")

async def process_cost_recommendations(coh_client, sns_client) -> None:
    """Process cost optimization recommendations proactively"""
    try:
        # Get all available recommendations
        recommendations = coh_client.list_recommendations(
            includeAllRecommendations=True,
            maxResults=20
        )
        
        items = recommendations.get('items', [])
        if not items:
            logger.info("No cost optimization recommendations available")
            return
        
        # Group recommendations by type
        rec_by_type = {}
        total_savings = 0
        
        for rec in items:
            action_type = rec.get('actionType', 'Unknown')
            monthly_savings = float(rec.get('estimatedMonthlySavings', 0))
            total_savings += monthly_savings
            
            if action_type not in rec_by_type:
                rec_by_type[action_type] = []
            rec_by_type[action_type].append({
                'id': rec.get('recommendationId', 'Unknown'),
                'savings': monthly_savings,
                'resource': rec.get('resourceArn', 'N/A')
            })
        
        # Create detailed summary
        summary = create_detailed_summary(rec_by_type, total_savings)
        
        # Send proactive notification if significant savings available
        if total_savings > 50:  # Only notify if potential savings > $50/month
            notification_message = f"""
Proactive Cost Optimization Alert
Timestamp: {datetime.now(timezone.utc).isoformat()}

Total Potential Monthly Savings: ${total_savings:.2f}

{summary}

Review and implement these recommendations in the AWS Cost Optimization Hub console.
            """
            
            sns_client.publish(
                TopicArn='${costOptimizationTopic.topicArn}',
                Subject=f'Cost Optimization Opportunities - ${total_savings:.2f} Monthly Savings Available',
                Message=notification_message
            )
            
            logger.info(f"Sent proactive cost optimization notification - ${total_savings:.2f} potential savings")
        
    except Exception as e:
        logger.error(f"Error processing cost recommendations: {str(e)}")

def create_recommendation_summary(recommendations: List[Dict[str, Any]]) -> str:
    """Create a formatted summary of recommendations"""
    if not recommendations:
        return "No recommendations available at this time."
    
    summary_lines = []
    for i, rec in enumerate(recommendations[:5], 1):  # Top 5 recommendations
        action_type = rec.get('actionType', 'Unknown')
        savings = rec.get('estimatedMonthlySavings', 0)
        resource = rec.get('resourceArn', 'N/A')
        
        summary_lines.append(
            f"{i}. {action_type}: ${savings}/month potential savings"
        )
    
    return "\\n".join(summary_lines)

def create_detailed_summary(rec_by_type: Dict[str, List], total_savings: float) -> str:
    """Create detailed summary grouped by recommendation type"""
    summary_lines = []
    
    for action_type, recs in rec_by_type.items():
        type_savings = sum(r['savings'] for r in recs)
        summary_lines.append(f"\\n{action_type}: {len(recs)} recommendations, ${type_savings:.2f}/month")
        
        for rec in recs[:3]:  # Top 3 per type
            summary_lines.append(f"  - ${rec['savings']:.2f}/month potential savings")
    
    return "\\n".join(summary_lines)
      `),
      role: lambdaExecutionRole,
      timeout: Duration.minutes(5),
      memorySize: 256,
      description: 'Processes cost optimization recommendations and budget alerts',
      environment: {
        SNS_TOPIC_ARN: costOptimizationTopic.topicArn,
        LOG_LEVEL: 'INFO'
      }
    });

    // Create CloudWatch Log Group for Lambda function
    new logs.LogGroup(this, 'CostOptimizationLogGroup', {
      logGroupName: `/aws/lambda/${costOptimizationFunction.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Allow SNS to invoke Lambda function
    costOptimizationFunction.addPermission('AllowSNSInvoke', {
      principal: new iam.ServicePrincipal('sns.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: costOptimizationTopic.topicArn
    });

    // Create IAM role for Budget Actions
    const budgetActionsRole = new iam.Role(this, 'BudgetActionsRole', {
      roleName: `BudgetActionsRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('budgets.amazonaws.com'),
      description: 'IAM role for automated budget actions',
      inlinePolicies: {
        BudgetActionsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iam:AttachUserPolicy',
                'iam:DetachUserPolicy',
                'iam:AttachGroupPolicy',
                'iam:DetachGroupPolicy',
                'iam:AttachRolePolicy',
                'iam:DetachRolePolicy'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create restrictive policy for budget actions
    const budgetRestrictionPolicy = new iam.ManagedPolicy(this, 'BudgetRestrictionPolicy', {
      managedPolicyName: `BudgetRestrictionPolicy-${uniqueSuffix}`,
      description: 'Policy to restrict resource creation when budgets are exceeded',
      document: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.DENY,
            actions: [
              'ec2:RunInstances',
              'ec2:StartInstances',
              'rds:CreateDBInstance',
              'rds:CreateDBCluster',
              'elasticache:CreateCacheCluster',
              'elasticache:CreateReplicationGroup'
            ],
            resources: ['*']
          })
        ]
      })
    });

    // Create Monthly Cost Budget
    const monthlyCostBudget = new budgets.CfnBudget(this, 'MonthlyCostBudget', {
      budget: {
        budgetName: `monthly-cost-budget-${uniqueSuffix}`,
        budgetType: 'COST',
        timeUnit: 'MONTHLY',
        budgetLimit: {
          amount: monthlyBudgetLimit,
          unit: 'USD'
        },
        costFilters: {},
        timePeriod: {
          start: new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0],
          end: new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).toISOString().split('T')[0]
        }
      },
      notificationsWithSubscribers: [
        {
          notification: {
            notificationType: 'ACTUAL',
            comparisonOperator: 'GREATER_THAN',
            threshold: budgetAlertThreshold,
            thresholdType: 'PERCENTAGE'
          },
          subscribers: [
            {
              subscriptionType: 'SNS',
              address: costOptimizationTopic.topicArn
            }
          ]
        },
        {
          notification: {
            notificationType: 'FORECASTED',
            comparisonOperator: 'GREATER_THAN',
            threshold: 90,
            thresholdType: 'PERCENTAGE'
          },
          subscribers: [
            {
              subscriptionType: 'SNS',
              address: costOptimizationTopic.topicArn
            }
          ]
        }
      ]
    });

    // Create EC2 Usage Budget
    const ec2UsageBudget = new budgets.CfnBudget(this, 'EC2UsageBudget', {
      budget: {
        budgetName: `ec2-usage-budget-${uniqueSuffix}`,
        budgetType: 'USAGE',
        timeUnit: 'MONTHLY',
        budgetLimit: {
          amount: ec2UsageBudgetLimit,
          unit: 'HOURS'
        },
        costFilters: {
          Service: ['Amazon Elastic Compute Cloud - Compute']
        },
        timePeriod: {
          start: new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0],
          end: new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).toISOString().split('T')[0]
        }
      },
      notificationsWithSubscribers: [
        {
          notification: {
            notificationType: 'FORECASTED',
            comparisonOperator: 'GREATER_THAN',
            threshold: 90,
            thresholdType: 'PERCENTAGE'
          },
          subscribers: [
            {
              subscriptionType: 'SNS',
              address: costOptimizationTopic.topicArn
            }
          ]
        }
      ]
    });

    // Create Reserved Instance Utilization Budget
    const riUtilizationBudget = new budgets.CfnBudget(this, 'RIUtilizationBudget', {
      budget: {
        budgetName: `ri-utilization-budget-${uniqueSuffix}`,
        budgetType: 'RI_UTILIZATION',
        timeUnit: 'MONTHLY',
        budgetLimit: {
          amount: riUtilizationThreshold,
          unit: 'PERCENT'
        },
        costFilters: {
          Service: ['Amazon Elastic Compute Cloud - Compute']
        },
        timePeriod: {
          start: new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0],
          end: new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).toISOString().split('T')[0]
        }
      },
      notificationsWithSubscribers: [
        {
          notification: {
            notificationType: 'ACTUAL',
            comparisonOperator: 'LESS_THAN',
            threshold: riUtilizationThreshold,
            thresholdType: 'PERCENTAGE'
          },
          subscribers: [
            {
              subscriptionType: 'SNS',
              address: costOptimizationTopic.topicArn
            }
          ]
        }
      ]
    });

    // Create Cost Anomaly Detector
    const costAnomalyDetector = new ce.CfnAnomalyDetector(this, 'CostAnomalyDetector', {
      anomalyDetector: {
        detectorName: `cost-anomaly-detector-${uniqueSuffix}`,
        monitorType: 'DIMENSIONAL',
        dimensionKey: 'SERVICE',
        matchOptions: ['EQUALS'],
        monitorSpecification: JSON.stringify({
          DimensionKey: 'SERVICE',
          MatchOptions: ['EQUALS'],
          Values: ['EC2-Instance', 'RDS', 'S3', 'Lambda']
        })
      }
    });

    // Create Cost Anomaly Subscription
    const costAnomalySubscription = new ce.CfnAnomalySubscription(this, 'CostAnomalySubscription', {
      anomalySubscription: {
        subscriptionName: `cost-anomaly-subscription-${uniqueSuffix}`,
        frequency: 'DAILY',
        monitorArnList: [costAnomalyDetector.attrAnomalyDetectorArn],
        subscribers: [
          {
            type: 'SNS',
            address: costOptimizationTopic.topicArn
          }
        ],
        threshold: 100
      }
    });

    // Store values for outputs
    this.snsTopicArn = costOptimizationTopic.topicArn;
    this.lambdaFunctionArn = costOptimizationFunction.functionArn;
    this.budgetNames = [
      monthlyCostBudget.ref,
      ec2UsageBudget.ref,
      riUtilizationBudget.ref
    ];

    // Create CloudFormation Outputs
    new CfnOutput(this, 'SNSTopicArn', {
      value: costOptimizationTopic.topicArn,
      description: 'ARN of the SNS topic for cost optimization notifications',
      exportName: `${this.stackName}-SNSTopicArn`
    });

    new CfnOutput(this, 'LambdaFunctionArn', {
      value: costOptimizationFunction.functionArn,
      description: 'ARN of the Lambda function for cost optimization processing',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    new CfnOutput(this, 'CostAnomalyDetectorArn', {
      value: costAnomalyDetector.attrAnomalyDetectorArn,
      description: 'ARN of the Cost Anomaly Detector',
      exportName: `${this.stackName}-CostAnomalyDetectorArn`
    });

    new CfnOutput(this, 'BudgetNames', {
      value: this.budgetNames.join(', '),
      description: 'Names of the created budgets',
      exportName: `${this.stackName}-BudgetNames`
    });

    new CfnOutput(this, 'BudgetActionsRoleArn', {
      value: budgetActionsRole.roleArn,
      description: 'ARN of the IAM role for budget actions',
      exportName: `${this.stackName}-BudgetActionsRoleArn`
    });

    new CfnOutput(this, 'BudgetRestrictionPolicyArn', {
      value: budgetRestrictionPolicy.managedPolicyArn,
      description: 'ARN of the policy used for budget restriction actions',
      exportName: `${this.stackName}-BudgetRestrictionPolicyArn`
    });
  }
}

/**
 * CDK App for Automated Cost Optimization Workflows
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || 
                         process.env.NOTIFICATION_EMAIL || 
                         'your-email@example.com';

const monthlyBudgetLimit = app.node.tryGetContext('monthlyBudgetLimit') || 
                          process.env.MONTHLY_BUDGET_LIMIT || 
                          1000;

const ec2UsageBudgetLimit = app.node.tryGetContext('ec2UsageBudgetLimit') || 
                           process.env.EC2_USAGE_BUDGET_LIMIT || 
                           2000;

const riUtilizationThreshold = app.node.tryGetContext('riUtilizationThreshold') || 
                              process.env.RI_UTILIZATION_THRESHOLD || 
                              80;

const budgetAlertThreshold = app.node.tryGetContext('budgetAlertThreshold') || 
                            process.env.BUDGET_ALERT_THRESHOLD || 
                            80;

// Create the stack
new AutomatedCostOptimizationStack(app, 'AutomatedCostOptimizationStack', {
  notificationEmail: notificationEmail,
  monthlyBudgetLimit: Number(monthlyBudgetLimit),
  ec2UsageBudgetLimit: Number(ec2UsageBudgetLimit),
  riUtilizationThreshold: Number(riUtilizationThreshold),
  budgetAlertThreshold: Number(budgetAlertThreshold),
  
  // Stack configuration
  description: 'Automated Cost Optimization Workflows using AWS Cost Optimization Hub and AWS Budgets',
  tags: {
    Project: 'AutomatedCostOptimization',
    Environment: 'Production',
    ManagedBy: 'CDK'
  },
  
  // Enable termination protection for production use
  terminationProtection: false,
  
  // Stack naming
  stackName: 'automated-cost-optimization-workflows'
});

app.synth();