import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as memorydb from 'aws-cdk-lib/aws-memorydb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as fs from 'fs';
import * as path from 'path';

export interface CostAwareResourceLifecycleStackProps extends cdk.StackProps {
  readonly clusterName?: string;
  readonly costThreshold?: number;
}

/**
 * CDK Stack for Cost-Aware Resource Lifecycle Management with EventBridge Scheduler and MemoryDB
 * 
 * This stack creates:
 * - MemoryDB cluster for Redis workloads
 * - Lambda function for intelligent cost optimization
 * - EventBridge Scheduler rules for automated scaling
 * - CloudWatch dashboard and alarms for monitoring
 * - AWS Budgets for cost control
 */
export class CostAwareResourceLifecycleStack extends cdk.Stack {
  public readonly memoryDbCluster: memorydb.CfnCluster;
  public readonly costOptimizerFunction: lambda.Function;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: CostAwareResourceLifecycleStackProps = {}) {
    super(scope, id, props);

    const clusterName = props.clusterName || 'cost-aware-memorydb';
    const costThreshold = props.costThreshold || 100;

    // Create VPC and networking for MemoryDB
    const vpc = this.createVpcResources();
    
    // Create IAM roles and policies
    const { lambdaRole, schedulerRole } = this.createIamResources();
    
    // Create Lambda function for cost optimization
    this.costOptimizerFunction = this.createCostOptimizerLambda(lambdaRole);
    
    // Create MemoryDB cluster
    this.memoryDbCluster = this.createMemoryDbCluster(clusterName, vpc);
    
    // Create EventBridge Scheduler resources
    this.createSchedulerResources(schedulerRole, clusterName, costThreshold);
    
    // Create monitoring and cost management resources
    this.createMonitoringResources(clusterName, costThreshold);
    
    // Create CloudWatch dashboard
    this.dashboard = this.createDashboard(clusterName);

    // Output important resource information
    this.createOutputs(clusterName);
  }

  /**
   * Create VPC resources for MemoryDB cluster
   */
  private createVpcResources(): ec2.IVpc {
    // Use default VPC or create a minimal VPC for MemoryDB
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true,
    });

    return vpc;
  }

  /**
   * Create IAM roles and policies for Lambda and EventBridge Scheduler
   */
  private createIamResources(): { lambdaRole: iam.Role; schedulerRole: iam.Role } {
    // Lambda execution role with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'CostOptimizerLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for MemoryDB cost optimization Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CostOptimizationPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'memorydb:DescribeClusters',
                'memorydb:ModifyCluster',
                'memorydb:DescribeSubnetGroups',
                'memorydb:DescribeParameterGroups',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ce:GetCostAndUsage',
                'ce:GetUsageReport',
                'ce:GetDimensionValues',
                'budgets:ViewBudget',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'cloudwatch:GetMetricStatistics',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'scheduler:GetSchedule',
                'scheduler:UpdateSchedule',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // EventBridge Scheduler execution role
    const schedulerRole = new iam.Role(this, 'EventBridgeSchedulerRole', {
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      description: 'IAM role for EventBridge Scheduler to invoke Lambda',
      inlinePolicies: {
        LambdaInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    return { lambdaRole, schedulerRole };
  }

  /**
   * Create Lambda function for intelligent cost optimization
   */
  private createCostOptimizerLambda(role: iam.Role): lambda.Function {
    // Create Lambda function code
    const lambdaCode = this.generateLambdaCode();

    const costOptimizerFunction = new lambda.Function(this, 'CostOptimizerFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(lambdaCode),
      role,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Cost-aware MemoryDB cluster lifecycle management function',
      environment: {
        LOG_LEVEL: 'INFO',
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    return costOptimizerFunction;
  }

  /**
   * Generate Lambda function code for cost optimization
   */
  private generateLambdaCode(): string {
    return `
import json
import boto3
import datetime
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

memorydb = boto3.client('memorydb')
ce = boto3.client('ce')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Intelligent cost-aware MemoryDB cluster management.
    Analyzes cost patterns and adjusts cluster configuration based on thresholds.
    """
    
    cluster_name = event.get('cluster_name')
    action = event.get('action', 'analyze')
    cost_threshold = event.get('cost_threshold', 100.0)
    
    if not cluster_name:
        return {
            'statusCode': 400,
            'body': {'error': 'cluster_name is required'}
        }
    
    try:
        # Get current cluster status
        cluster_response = memorydb.describe_clusters(ClusterName=cluster_name)
        if not cluster_response['Clusters']:
            return {
                'statusCode': 404,
                'body': {'error': f'Cluster {cluster_name} not found'}
            }
            
        cluster = cluster_response['Clusters'][0]
        current_node_type = cluster['NodeType']
        current_shards = cluster['NumberOfShards']
        cluster_status = cluster['Status']
        
        # Only proceed if cluster is available
        if cluster_status != 'available':
            logger.warning(f"Cluster {cluster_name} is not available, status: {cluster_status}")
            return {
                'statusCode': 200,
                'body': {'message': f'Cluster not available for modification, status: {cluster_status}'}
            }
        
        # Analyze recent cost trends
        cost_data = get_cost_analysis()
        memorydb_cost = cost_data['total_cost']
        
        # Determine scaling action based on cost analysis
        scaling_recommendation = analyze_scaling_needs(
            memorydb_cost, cost_threshold, current_node_type, action
        )
        
        # Execute scaling if recommended and cluster is available
        if scaling_recommendation['action'] != 'none' and cluster_status == 'available':
            modify_result = modify_cluster(cluster_name, scaling_recommendation)
            scaling_recommendation['execution_result'] = modify_result
        
        # Send metrics to CloudWatch
        send_cloudwatch_metrics(cluster_name, memorydb_cost, scaling_recommendation)
        
        return {
            'statusCode': 200,
            'body': {
                'cluster_name': cluster_name,
                'current_cost': memorydb_cost,
                'current_node_type': current_node_type,
                'recommendation': scaling_recommendation,
                'timestamp': datetime.datetime.now().isoformat()
            }
        }
        
    except Exception as e:
        logger.error(f"Error in cost optimization: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': str(e)}
        }

def get_cost_analysis() -> Dict[str, float]:
    """Retrieve and analyze recent MemoryDB costs."""
    try:
        end_date = datetime.datetime.now()
        start_date = end_date - datetime.timedelta(days=7)
        
        cost_response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
            ]
        )
        
        # Calculate MemoryDB costs
        memorydb_cost = 0.0
        for result_by_time in cost_response['ResultsByTime']:
            for group in result_by_time['Groups']:
                if 'MemoryDB' in group['Keys'][0] or 'ElastiCache' in group['Keys'][0]:
                    memorydb_cost += float(group['Metrics']['BlendedCost']['Amount'])
        
        return {'total_cost': memorydb_cost}
        
    except Exception as e:
        logger.warning(f"Could not retrieve cost data: {str(e)}")
        return {'total_cost': 0.0}

def analyze_scaling_needs(cost: float, threshold: float, node_type: str, action: str) -> Dict[str, Any]:
    """Analyze cost patterns and recommend scaling actions."""
    
    if action == 'scale_down' and cost > threshold:
        # Business hours ended, scale down for cost savings
        if 'large' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('large', 'small'),
                'reason': 'Off-peak cost optimization',
                'estimated_savings': '30-40%'
            }
        elif 'medium' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('medium', 'small'),
                'reason': 'Off-peak cost optimization',
                'estimated_savings': '20-30%'
            }
    elif action == 'scale_up':
        # Business hours starting, scale up for performance
        if 'small' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('small', 'medium'),
                'reason': 'Business hours performance optimization',
                'estimated_impact': 'Improved performance for business workloads'
            }
    
    return {'action': 'none', 'reason': 'No scaling needed based on current conditions'}

def modify_cluster(cluster_name: str, recommendation: Dict[str, Any]) -> Dict[str, str]:
    """Execute cluster modifications based on recommendations."""
    
    try:
        if recommendation['action'] == 'modify_node_type':
            response = memorydb.modify_cluster(
                ClusterName=cluster_name,
                NodeType=recommendation['target_node_type']
            )
            
            logger.info(f"Initiated cluster modification: {cluster_name} -> {recommendation['target_node_type']}")
            return {
                'status': 'initiated',
                'message': f"Cluster modification started to {recommendation['target_node_type']}"
            }
            
    except Exception as e:
        logger.error(f"Failed to modify cluster {cluster_name}: {str(e)}")
        return {
            'status': 'failed',
            'message': f"Cluster modification failed: {str(e)}"
        }

def send_cloudwatch_metrics(cluster_name: str, cost: float, recommendation: Dict[str, Any]) -> None:
    """Send cost optimization metrics to CloudWatch."""
    
    try:
        cloudwatch.put_metric_data(
            Namespace='MemoryDB/CostOptimization',
            MetricData=[
                {
                    'MetricName': 'WeeklyCost',
                    'Value': cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'ClusterName', 'Value': cluster_name}
                    ]
                },
                {
                    'MetricName': 'OptimizationAction',
                    'Value': 1 if recommendation['action'] != 'none' else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'ClusterName', 'Value': cluster_name}
                    ]
                }
            ]
        )
    except Exception as e:
        logger.warning(f"Failed to send CloudWatch metrics: {str(e)}")
`;
  }

  /**
   * Create MemoryDB cluster with subnet group
   */
  private createMemoryDbCluster(clusterName: string, vpc: ec2.IVpc): memorydb.CfnCluster {
    // Create subnet group for MemoryDB
    const subnetGroup = new memorydb.CfnSubnetGroup(this, 'MemoryDbSubnetGroup', {
      subnetGroupName: `${clusterName}-subnet-group`,
      description: 'Subnet group for cost-aware MemoryDB cluster',
      subnetIds: vpc.privateSubnets.length > 0 
        ? vpc.privateSubnets.map(subnet => subnet.subnetId)
        : vpc.publicSubnets.slice(0, 2).map(subnet => subnet.subnetId),
    });

    // Create default security group for MemoryDB
    const securityGroup = new ec2.SecurityGroup(this, 'MemoryDbSecurityGroup', {
      vpc,
      description: 'Security group for MemoryDB cluster',
      allowAllOutbound: true,
    });

    // Allow Redis traffic from VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(6379),
      'Allow Redis traffic from VPC'
    );

    // Create MemoryDB cluster
    const cluster = new memorydb.CfnCluster(this, 'MemoryDbCluster', {
      clusterName,
      nodeType: 'db.t4g.small',
      numShards: 1,
      numReplicasPerShard: 0,
      subnetGroupName: subnetGroup.subnetGroupName,
      securityGroupIds: [securityGroup.securityGroupId],
      maintenanceWindow: 'sun:03:00-sun:04:00',
      description: 'Cost-aware MemoryDB cluster for Redis workloads',
      tags: [
        {
          key: 'CostOptimization',
          value: 'enabled',
        },
        {
          key: 'ManagedBy',
          value: 'CDK',
        },
      ],
    });

    cluster.addDependency(subnetGroup);

    return cluster;
  }

  /**
   * Create EventBridge Scheduler resources for automated cost optimization
   */
  private createSchedulerResources(schedulerRole: iam.Role, clusterName: string, costThreshold: number): void {
    // Create schedule group
    const scheduleGroup = new scheduler.CfnScheduleGroup(this, 'CostOptimizationScheduleGroup', {
      name: 'cost-optimization-schedules',
      description: 'Cost optimization schedules for MemoryDB lifecycle management',
    });

    // Business hours scale-up schedule (8 AM weekdays)
    new scheduler.CfnSchedule(this, 'BusinessHoursStartSchedule', {
      scheduleExpression: 'cron(0 8 ? * MON-FRI *)',
      target: {
        arn: this.costOptimizerFunction.functionArn,
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({
          cluster_name: clusterName,
          action: 'scale_up',
          cost_threshold: costThreshold,
        }),
      },
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      groupName: scheduleGroup.name,
      description: 'Scale up MemoryDB for business hours performance',
      state: 'ENABLED',
    });

    // Off-hours scale-down schedule (6 PM weekdays)
    new scheduler.CfnSchedule(this, 'BusinessHoursEndSchedule', {
      scheduleExpression: 'cron(0 18 ? * MON-FRI *)',
      target: {
        arn: this.costOptimizerFunction.functionArn,
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({
          cluster_name: clusterName,
          action: 'scale_down',
          cost_threshold: costThreshold / 2,
        }),
      },
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      groupName: scheduleGroup.name,
      description: 'Scale down MemoryDB for cost optimization during off-hours',
      state: 'ENABLED',
    });

    // Weekly cost analysis schedule (9 AM Mondays)
    new scheduler.CfnSchedule(this, 'WeeklyCostAnalysisSchedule', {
      scheduleExpression: 'cron(0 9 ? * MON *)',
      target: {
        arn: this.costOptimizerFunction.functionArn,
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({
          cluster_name: clusterName,
          action: 'analyze',
          cost_threshold: costThreshold * 1.5,
        }),
      },
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      groupName: scheduleGroup.name,
      description: 'Weekly MemoryDB cost analysis and optimization review',
      state: 'ENABLED',
    });

    // Grant Lambda invoke permission to EventBridge Scheduler
    this.costOptimizerFunction.addPermission('AllowEventBridgeSchedulerInvoke', {
      principal: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      action: 'lambda:InvokeFunction',
    });
  }

  /**
   * Create monitoring and cost management resources
   */
  private createMonitoringResources(clusterName: string, costThreshold: number): void {
    // Create budget for MemoryDB cost monitoring
    new budgets.CfnBudget(this, 'MemoryDbCostBudget', {
      budget: {
        budgetName: `MemoryDB-Cost-Budget-${clusterName}`,
        budgetLimit: {
          amount: (costThreshold * 2).toString(),
          unit: 'USD',
        },
        timeUnit: 'MONTHLY',
        budgetType: 'COST',
        costFilters: {
          Service: ['Amazon MemoryDB for Redis'],
        },
        timePeriod: {
          start: '2025-07-01',
          end: '2025-12-31',
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
              address: 'admin@example.com',
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
              address: 'admin@example.com',
            },
          ],
        },
      ],
    });

    // Create CloudWatch alarms for cost optimization monitoring
    new cloudwatch.Alarm(this, 'MemoryDbWeeklyCostHighAlarm', {
      alarmName: `MemoryDB-Weekly-Cost-High-${clusterName}`,
      alarmDescription: 'Alert when MemoryDB weekly costs exceed threshold',
      metric: new cloudwatch.Metric({
        namespace: 'MemoryDB/CostOptimization',
        metricName: 'WeeklyCost',
        dimensionsMap: {
          ClusterName: clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.days(7),
      }),
      threshold: costThreshold * 1.5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create Lambda error alarm for monitoring automation health
    new cloudwatch.Alarm(this, 'CostOptimizerLambdaErrorsAlarm', {
      alarmName: `MemoryDB-Optimizer-Lambda-Errors-${clusterName}`,
      alarmDescription: 'Alert when cost optimization Lambda function has errors',
      metric: this.costOptimizerFunction.metricErrors({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 2,
    });
  }

  /**
   * Create CloudWatch dashboard for comprehensive monitoring
   */
  private createDashboard(clusterName: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'CostOptimizationDashboard', {
      dashboardName: `MemoryDB-Cost-Optimization-${clusterName}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'MemoryDB Cost Optimization Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'MemoryDB/CostOptimization',
                metricName: 'WeeklyCost',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.days(1),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'MemoryDB/CostOptimization',
                metricName: 'OptimizationAction',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Sum',
                period: cdk.Duration.days(1),
              }),
            ],
            width: 12,
          }),
          new cloudwatch.GraphWidget({
            title: 'MemoryDB Performance Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/MemoryDB',
                metricName: 'CPUUtilization',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/MemoryDB',
                metricName: 'NetworkBytesIn',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/MemoryDB',
                metricName: 'NetworkBytesOut',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Cost Optimization Lambda Metrics',
            left: [
              this.costOptimizerFunction.metricDuration({
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              this.costOptimizerFunction.metricErrors({
                period: cdk.Duration.minutes(5),
              }),
              this.costOptimizerFunction.metricInvocations({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 24,
          }),
        ],
      ],
    });

    return dashboard;
  }

  /**
   * Create stack outputs for important resource information
   */
  private createOutputs(clusterName: string): void {
    new cdk.CfnOutput(this, 'MemoryDbClusterName', {
      value: this.memoryDbCluster.clusterName!,
      description: 'Name of the MemoryDB cluster',
      exportName: `${this.stackName}-MemoryDbClusterName`,
    });

    new cdk.CfnOutput(this, 'MemoryDbClusterEndpoint', {
      value: this.memoryDbCluster.attrClusterEndpointAddress,
      description: 'MemoryDB cluster endpoint address',
      exportName: `${this.stackName}-MemoryDbClusterEndpoint`,
    });

    new cdk.CfnOutput(this, 'CostOptimizerFunctionName', {
      value: this.costOptimizerFunction.functionName,
      description: 'Name of the cost optimizer Lambda function',
      exportName: `${this.stackName}-CostOptimizerFunctionName`,
    });

    new cdk.CfnOutput(this, 'CostOptimizerFunctionArn', {
      value: this.costOptimizerFunction.functionArn,
      description: 'ARN of the cost optimizer Lambda function',
      exportName: `${this.stackName}-CostOptimizerFunctionArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for cost optimization monitoring',
    });
  }
}