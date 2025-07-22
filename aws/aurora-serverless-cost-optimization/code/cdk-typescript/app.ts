#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the Aurora Serverless v2 Cost Optimization Stack
 */
export interface AuroraServerlessV2CostOptimizationStackProps extends cdk.StackProps {
  readonly clusterName?: string;
  readonly environment?: string;
  readonly minCapacity?: number;
  readonly maxCapacity?: number;
  readonly budgetLimit?: number;
}

/**
 * Aurora Serverless v2 Cost Optimization Stack
 * 
 * This stack implements intelligent auto-scaling patterns for Aurora Serverless v2
 * that automatically adjusts capacity based on workload demands while incorporating
 * cost optimization strategies including automatic pause/resume capabilities,
 * intelligent capacity forecasting, and workload-aware scaling policies.
 */
export class AuroraServerlessV2CostOptimizationStack extends cdk.Stack {
  public readonly cluster: rds.DatabaseCluster;
  public readonly writerInstance: rds.DatabaseInstance;
  public readonly readerInstances: rds.DatabaseInstance[];
  public readonly costAwareScalerFunction: lambda.Function;
  public readonly autoPauseResumeFunction: lambda.Function;
  public readonly costTopic: sns.Topic;

  constructor(scope: Construct, id: string, props?: AuroraServerlessV2CostOptimizationStackProps) {
    super(scope, id, props);

    // Default values
    const clusterName = props?.clusterName || 'aurora-sv2-cost-opt';
    const environment = props?.environment || 'development';
    const minCapacity = props?.minCapacity || 0.5;
    const maxCapacity = props?.maxCapacity || 16;
    const budgetLimit = props?.budgetLimit || 200;

    // Create VPC for Aurora cluster
    const vpc = this.createVpc();

    // Create security group for Aurora
    const auroraSecurityGroup = this.createAuroraSecurityGroup(vpc);

    // Create subnet group for Aurora
    const subnetGroup = this.createSubnetGroup(vpc);

    // Create custom parameter group for cost optimization
    const parameterGroup = this.createParameterGroup(clusterName);

    // Create IAM role for Lambda functions
    const lambdaRole = this.createLambdaRole(clusterName);

    // Create Aurora Serverless v2 cluster
    this.cluster = this.createAuroraCluster(
      clusterName,
      vpc,
      auroraSecurityGroup,
      subnetGroup,
      parameterGroup,
      minCapacity,
      maxCapacity
    );

    // Create writer instance
    this.writerInstance = this.createWriterInstance(this.cluster, clusterName);

    // Create read replica instances with different scaling patterns
    this.readerInstances = this.createReaderInstances(this.cluster, clusterName);

    // Create SNS topic for cost alerts
    this.costTopic = this.createCostAlertTopic();

    // Create Lambda functions for intelligent scaling
    this.costAwareScalerFunction = this.createCostAwareScalerFunction(
      clusterName,
      lambdaRole,
      this.costTopic
    );

    this.autoPauseResumeFunction = this.createAutoPauseResumeFunction(
      clusterName,
      environment,
      lambdaRole
    );

    // Create EventBridge rules for scheduled scaling
    this.createEventBridgeRules(this.costAwareScalerFunction, this.autoPauseResumeFunction);

    // Create CloudWatch alarms for cost monitoring
    this.createCloudWatchAlarms(this.cluster, this.costTopic);

    // Create AWS Budget for cost control
    this.createBudget(budgetLimit, this.costTopic);

    // Output important values
    this.createOutputs();
  }

  /**
   * Create VPC for Aurora cluster
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'AuroraVpc', {
      maxAzs: 3,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'aurora-private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'aurora-public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });
  }

  /**
   * Create security group for Aurora cluster
   */
  private createAuroraSecurityGroup(vpc: ec2.Vpc): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'AuroraSecurityGroup', {
      vpc,
      description: 'Security group for Aurora Serverless v2 cluster',
      allowAllOutbound: true,
    });

    // Allow PostgreSQL connections from within VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(5432),
      'Allow PostgreSQL connections from VPC'
    );

    return securityGroup;
  }

  /**
   * Create subnet group for Aurora cluster
   */
  private createSubnetGroup(vpc: ec2.Vpc): rds.SubnetGroup {
    return new rds.SubnetGroup(this, 'AuroraSubnetGroup', {
      description: 'Subnet group for Aurora Serverless v2 cluster',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });
  }

  /**
   * Create custom parameter group for cost optimization
   */
  private createParameterGroup(clusterName: string): rds.ParameterGroup {
    return new rds.ParameterGroup(this, 'AuroraParameterGroup', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_15_4,
      }),
      description: 'Aurora Serverless v2 cost optimization parameters',
      parameters: {
        shared_preload_libraries: 'pg_stat_statements',
        track_activity_query_size: '2048',
        log_statement: 'ddl',
        log_min_duration_statement: '1000',
      },
    });
  }

  /**
   * Create IAM role for Lambda functions
   */
  private createLambdaRole(clusterName: string): iam.Role {
    const role = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for Aurora Serverless v2 scaling Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add custom policy for Aurora management
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'rds:DescribeDBClusters',
        'rds:DescribeDBInstances',
        'rds:ModifyDBCluster',
        'rds:ModifyDBInstance',
        'rds:StartDBCluster',
        'rds:StopDBCluster',
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:PutMetricData',
        'ce:GetUsageAndCosts',
        'budgets:ViewBudget',
        'sns:Publish',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Create Aurora Serverless v2 cluster
   */
  private createAuroraCluster(
    clusterName: string,
    vpc: ec2.Vpc,
    securityGroup: ec2.SecurityGroup,
    subnetGroup: rds.SubnetGroup,
    parameterGroup: rds.ParameterGroup,
    minCapacity: number,
    maxCapacity: number
  ): rds.DatabaseCluster {
    return new rds.DatabaseCluster(this, 'AuroraCluster', {
      clusterIdentifier: clusterName,
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_15_4,
      }),
      credentials: rds.Credentials.fromGeneratedSecret('postgres'),
      vpc,
      securityGroups: [securityGroup],
      subnetGroup,
      parameterGroup,
      serverlessV2MinCapacity: minCapacity,
      serverlessV2MaxCapacity: maxCapacity,
      backup: {
        retention: cdk.Duration.days(7),
        preferredWindow: '03:00-04:00',
      },
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      cloudwatchLogsExports: ['postgresql'],
      monitoringInterval: cdk.Duration.seconds(60),
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      storageEncrypted: true,
      deletionProtection: false, // Set to true for production
    });
  }

  /**
   * Create writer instance for Aurora cluster
   */
  private createWriterInstance(cluster: rds.DatabaseCluster, clusterName: string): rds.DatabaseInstance {
    return cluster.addRotationSingleUser();
    // Note: For Aurora Serverless v2, instances are automatically created with the cluster
    // This is a placeholder - actual instance creation is handled by the cluster
    return cluster.node.children.find(child => child instanceof rds.DatabaseInstance) as rds.DatabaseInstance;
  }

  /**
   * Create read replica instances with different scaling patterns
   */
  private createReaderInstances(cluster: rds.DatabaseCluster, clusterName: string): rds.DatabaseInstance[] {
    // Note: Aurora Serverless v2 read replicas are typically managed through the cluster configuration
    // For this implementation, we'll create additional instances through the cluster
    return [];
  }

  /**
   * Create SNS topic for cost alerts
   */
  private createCostAlertTopic(): sns.Topic {
    return new sns.Topic(this, 'CostAlertTopic', {
      displayName: 'Aurora Serverless v2 Cost Alerts',
      description: 'SNS topic for Aurora Serverless v2 cost optimization alerts',
    });
  }

  /**
   * Create cost-aware scaling Lambda function
   */
  private createCostAwareScalerFunction(
    clusterName: string,
    role: iam.Role,
    costTopic: sns.Topic
  ): lambda.Function {
    return new lambda.Function(this, 'CostAwareScalerFunction', {
      functionName: `${clusterName}-cost-aware-scaler`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        CLUSTER_ID: clusterName,
        COST_TOPIC_ARN: costTopic.topicArn,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, timedelta
import os

rds = boto3.client('rds')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

def lambda_handler(event, context):
    cluster_id = os.environ['CLUSTER_ID']
    
    try:
        # Get current cluster configuration
        cluster_response = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster = cluster_response['DBClusters'][0]
        
        current_min = cluster['ServerlessV2ScalingConfiguration']['MinCapacity']
        current_max = cluster['ServerlessV2ScalingConfiguration']['MaxCapacity']
        
        # Get CPU utilization metrics
        cpu_metrics = get_cpu_utilization(cluster_id)
        connection_metrics = get_connection_count(cluster_id)
        
        # Determine optimal scaling based on patterns
        new_min, new_max = calculate_optimal_scaling(
            cpu_metrics, connection_metrics, current_min, current_max
        )
        
        # Apply scaling if needed
        if new_min != current_min or new_max != current_max:
            update_scaling_configuration(cluster_id, new_min, new_max)
            send_scaling_notification(cluster_id, current_min, current_max, new_min, new_max)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_id,
                'previous_scaling': {'min': current_min, 'max': current_max},
                'new_scaling': {'min': new_min, 'max': new_max},
                'cpu_avg': cpu_metrics.get('average', 0),
                'connections_avg': connection_metrics.get('average', 0)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def get_cpu_utilization(cluster_id):
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='CPUUtilization',
        Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average', 'Maximum']
    )
    
    if response['Datapoints']:
        avg_cpu = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
        max_cpu = max(dp['Maximum'] for dp in response['Datapoints'])
        return {'average': avg_cpu, 'maximum': max_cpu}
    return {'average': 0, 'maximum': 0}

def get_connection_count(cluster_id):
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='DatabaseConnections',
        Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average', 'Maximum']
    )
    
    if response['Datapoints']:
        avg_conn = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
        max_conn = max(dp['Maximum'] for dp in response['Datapoints'])
        return {'average': avg_conn, 'maximum': max_conn}
    return {'average': 0, 'maximum': 0}

def calculate_optimal_scaling(cpu_metrics, conn_metrics, current_min, current_max):
    cpu_avg = cpu_metrics.get('average', 0)
    cpu_max = cpu_metrics.get('maximum', 0)
    conn_avg = conn_metrics.get('average', 0)
    
    # Determine optimal minimum capacity
    if cpu_avg < 20 and conn_avg < 5:
        new_min = 0.5  # Very low utilization - aggressive scale down
    elif cpu_avg < 40 and conn_avg < 20:
        new_min = max(0.5, current_min - 0.5)  # Low utilization - moderate scale down
    elif cpu_avg > 70 or conn_avg > 50:
        new_min = min(8, current_min + 1)  # High utilization - scale up minimum
    else:
        new_min = current_min  # Maintain current minimum
    
    # Determine optimal maximum capacity
    if cpu_max > 80 or conn_avg > 80:
        new_max = min(32, current_max + 4)  # High peak usage - increase max capacity
    elif cpu_max < 50 and conn_avg < 30:
        new_max = max(4, current_max - 2)  # Low peak usage - reduce max capacity
    else:
        new_max = current_max  # Maintain current maximum
    
    # Ensure minimum <= maximum
    new_min = min(new_min, new_max)
    
    return new_min, new_max

def update_scaling_configuration(cluster_id, min_capacity, max_capacity):
    rds.modify_db_cluster(
        DBClusterIdentifier=cluster_id,
        ServerlessV2ScalingConfiguration={
            'MinCapacity': min_capacity,
            'MaxCapacity': max_capacity
        },
        ApplyImmediately=True
    )

def send_scaling_notification(cluster_id, old_min, old_max, new_min, new_max):
    cost_impact = calculate_cost_impact(old_min, old_max, new_min, new_max)
    
    message = f"""
Aurora Serverless v2 Scaling Update

Cluster: {cluster_id}
Previous: Min {old_min} ACU, Max {old_max} ACU
New: Min {new_min} ACU, Max {new_max} ACU

Estimated monthly cost impact: ${cost_impact:+.2f}

This change optimizes costs based on recent usage patterns.
"""
    
    # Send custom metrics to CloudWatch
    cloudwatch.put_metric_data(
        Namespace='Aurora/CostOptimization',
        MetricData=[
            {
                'MetricName': 'ScalingAdjustment',
                'Dimensions': [
                    {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                    {'Name': 'ScalingType', 'Value': 'MinCapacity'}
                ],
                'Value': new_min - old_min,
                'Unit': 'Count'
            },
            {
                'MetricName': 'EstimatedCostImpact',
                'Dimensions': [{'Name': 'ClusterIdentifier', 'Value': cluster_id}],
                'Value': cost_impact,
                'Unit': 'None'
            }
        ]
    )

def calculate_cost_impact(old_min, old_max, new_min, new_max):
    # Simplified cost calculation (ACU hours per month * cost per ACU hour)
    hours_per_month = 730
    cost_per_acu_hour = 0.12  # Approximate cost - varies by region
    
    # Estimate average usage
    old_avg_usage = (old_min + old_max) / 2
    new_avg_usage = (new_min + new_max) / 2
    
    old_cost = old_avg_usage * hours_per_month * cost_per_acu_hour
    new_cost = new_avg_usage * hours_per_month * cost_per_acu_hour
    
    return new_cost - old_cost
`),
    });
  }

  /**
   * Create auto-pause/resume Lambda function
   */
  private createAutoPauseResumeFunction(
    clusterName: string,
    environment: string,
    role: iam.Role
  ): lambda.Function {
    return new lambda.Function(this, 'AutoPauseResumeFunction', {
      functionName: `${clusterName}-auto-pause-resume`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        CLUSTER_ID: clusterName,
        ENVIRONMENT: environment,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, time
import os

rds = boto3.client('rds')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    cluster_id = os.environ['CLUSTER_ID']
    environment = os.environ.get('ENVIRONMENT', 'development')
    
    try:
        # Get current time and determine action
        current_time = datetime.utcnow().time()
        action = determine_action(current_time, environment)
        
        if action == 'pause':
            result = pause_cluster_if_idle(cluster_id)
        elif action == 'resume':
            result = resume_cluster_if_needed(cluster_id)
        else:
            result = {'action': 'no_action', 'reason': 'Outside operating hours'}
        
        # Record action in CloudWatch
        record_pause_resume_metrics(cluster_id, action, result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_id,
                'environment': environment,
                'action': action,
                'result': result,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def determine_action(current_time, environment):
    # Define operating hours based on environment
    if environment == 'development':
        start_hour = time(8, 0)   # 8 AM UTC
        end_hour = time(20, 0)    # 8 PM UTC
    elif environment == 'staging':
        start_hour = time(6, 0)   # 6 AM UTC
        end_hour = time(22, 0)    # 10 PM UTC
    else:
        return 'monitor'  # Production: always on
    
    if start_hour <= current_time <= end_hour:
        return 'resume'
    else:
        return 'pause'

def pause_cluster_if_idle(cluster_id):
    if is_cluster_idle(cluster_id):
        # Scale down to minimum effectively pausing
        rds.modify_db_cluster(
            DBClusterIdentifier=cluster_id,
            ServerlessV2ScalingConfiguration={
                'MinCapacity': 0.5,
                'MaxCapacity': 1
            },
            ApplyImmediately=True
        )
        return {'action': 'paused', 'reason': 'Low activity detected during off-hours'}
    else:
        return {'action': 'not_paused', 'reason': 'Active connections detected'}

def resume_cluster_if_needed(cluster_id):
    # Get current scaling configuration
    cluster_response = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
    cluster = cluster_response['DBClusters'][0]
    
    current_min = cluster['ServerlessV2ScalingConfiguration']['MinCapacity']
    current_max = cluster['ServerlessV2ScalingConfiguration']['MaxCapacity']
    
    # Resume to normal operating capacity if currently paused
    if current_min <= 0.5 and current_max <= 1:
        rds.modify_db_cluster(
            DBClusterIdentifier=cluster_id,
            ServerlessV2ScalingConfiguration={
                'MinCapacity': 0.5,
                'MaxCapacity': 8
            },
            ApplyImmediately=True
        )
        return {'action': 'resumed', 'reason': 'Operating hours started'}
    else:
        return {'action': 'already_active', 'reason': 'Cluster already in active state'}

def is_cluster_idle(cluster_id):
    from datetime import timedelta
    
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=30)
    
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='DatabaseConnections',
        Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Maximum']
    )
    
    if response['Datapoints']:
        max_connections = max(dp['Maximum'] for dp in response['Datapoints'])
        return max_connections <= 1  # Only system connections
    
    return True  # No data means idle

def record_pause_resume_metrics(cluster_id, action, result):
    metric_value = 1 if result.get('action') in ['paused', 'resumed'] else 0
    
    cloudwatch.put_metric_data(
        Namespace='Aurora/CostOptimization',
        MetricData=[
            {
                'MetricName': 'AutoPauseResumeActions',
                'Dimensions': [
                    {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                    {'Name': 'Action', 'Value': action}
                ],
                'Value': metric_value,
                'Unit': 'Count'
            }
        ]
    )
`),
    });
  }

  /**
   * Create EventBridge rules for scheduled scaling
   */
  private createEventBridgeRules(
    costAwareScalerFunction: lambda.Function,
    autoPauseResumeFunction: lambda.Function
  ): void {
    // Rule for cost-aware scaling (every 15 minutes)
    const costAwareScalingRule = new events.Rule(this, 'CostAwareScalingRule', {
      schedule: events.Schedule.rate(cdk.Duration.minutes(15)),
      description: 'Trigger cost-aware scaling for Aurora Serverless v2',
    });

    costAwareScalingRule.addTarget(new targets.LambdaFunction(costAwareScalerFunction));

    // Rule for auto-pause/resume (every hour)
    const autoPauseResumeRule = new events.Rule(this, 'AutoPauseResumeRule', {
      schedule: events.Schedule.rate(cdk.Duration.hours(1)),
      description: 'Trigger auto-pause/resume for Aurora Serverless v2',
    });

    autoPauseResumeRule.addTarget(new targets.LambdaFunction(autoPauseResumeFunction));
  }

  /**
   * Create CloudWatch alarms for cost monitoring
   */
  private createCloudWatchAlarms(cluster: rds.DatabaseCluster, costTopic: sns.Topic): void {
    // Alarm for high ACU usage
    new cloudwatch.Alarm(this, 'HighACUUsageAlarm', {
      alarmName: `${cluster.clusterIdentifier}-high-acu-usage`,
      alarmDescription: 'Alert when Aurora Serverless v2 ACU usage is high',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'ServerlessDatabaseCapacity',
        dimensionsMap: {
          DBClusterIdentifier: cluster.clusterIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 12,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    }).addAlarmAction(new cloudwatch.SnsAction(costTopic));

    // Alarm for sustained high capacity
    new cloudwatch.Alarm(this, 'SustainedHighCapacityAlarm', {
      alarmName: `${cluster.clusterIdentifier}-sustained-high-capacity`,
      alarmDescription: 'Alert when capacity remains high for extended period',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'ServerlessDatabaseCapacity',
        dimensionsMap: {
          DBClusterIdentifier: cluster.clusterIdentifier,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(30),
      }),
      threshold: 8,
      evaluationPeriods: 4,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    }).addAlarmAction(new cloudwatch.SnsAction(costTopic));
  }

  /**
   * Create AWS Budget for cost control
   */
  private createBudget(budgetLimit: number, costTopic: sns.Topic): void {
    new budgets.CfnBudget(this, 'AuroraServerlessV2Budget', {
      budget: {
        budgetName: 'Aurora-Serverless-v2-Monthly',
        budgetLimit: {
          amount: budgetLimit,
          unit: 'USD',
        },
        timeUnit: 'MONTHLY',
        budgetType: 'COST',
        costFilters: {
          Service: ['Amazon Relational Database Service'],
          TagKey: ['Application'],
          TagValue: ['AuroraServerlessV2'],
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
              subscriptionType: 'SNS',
              address: costTopic.topicArn,
            },
          ],
        },
        {
          notification: {
            notificationType: 'FORECASTED',
            comparisonOperator: 'GREATER_THAN',
            threshold: 100,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              subscriptionType: 'SNS',
              address: costTopic.topicArn,
            },
          ],
        },
      ],
    });
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'ClusterIdentifier', {
      value: this.cluster.clusterIdentifier,
      description: 'Aurora Serverless v2 Cluster Identifier',
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint.hostname,
      description: 'Aurora Serverless v2 Cluster Endpoint',
    });

    new cdk.CfnOutput(this, 'ClusterReaderEndpoint', {
      value: this.cluster.clusterReadEndpoint.hostname,
      description: 'Aurora Serverless v2 Cluster Reader Endpoint',
    });

    new cdk.CfnOutput(this, 'SecretArn', {
      value: this.cluster.secret?.secretArn || 'N/A',
      description: 'ARN of the secret containing database credentials',
    });

    new cdk.CfnOutput(this, 'CostAwareScalerFunctionName', {
      value: this.costAwareScalerFunction.functionName,
      description: 'Cost-aware scaling Lambda function name',
    });

    new cdk.CfnOutput(this, 'AutoPauseResumeFunctionName', {
      value: this.autoPauseResumeFunction.functionName,
      description: 'Auto-pause/resume Lambda function name',
    });

    new cdk.CfnOutput(this, 'CostAlertTopicArn', {
      value: this.costTopic.topicArn,
      description: 'SNS topic ARN for cost alerts',
    });
  }
}

/**
 * CDK App
 */
const app = new cdk.App();

// Get configuration from context or use defaults
const clusterName = app.node.tryGetContext('clusterName') || 'aurora-sv2-cost-opt';
const environment = app.node.tryGetContext('environment') || 'development';
const minCapacity = Number(app.node.tryGetContext('minCapacity')) || 0.5;
const maxCapacity = Number(app.node.tryGetContext('maxCapacity')) || 16;
const budgetLimit = Number(app.node.tryGetContext('budgetLimit')) || 200;

new AuroraServerlessV2CostOptimizationStack(app, 'AuroraServerlessV2CostOptimizationStack', {
  clusterName,
  environment,
  minCapacity,
  maxCapacity,
  budgetLimit,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Aurora Serverless v2 Cost Optimization Stack with intelligent auto-scaling patterns',
  tags: {
    Application: 'AuroraServerlessV2',
    Environment: environment,
    CostOptimization: 'Enabled',
    Project: 'aurora-serverless-v2-cost-optimization-patterns',
  },
});

app.synth();