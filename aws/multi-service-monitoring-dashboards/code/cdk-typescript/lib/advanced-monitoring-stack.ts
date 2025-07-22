import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

export interface AdvancedMonitoringStackProps extends cdk.StackProps {
  config: {
    stackName: string;
    environment: string;
    projectName: string;
    alertEmail: string;
    enableCostMonitoring: boolean;
    anomalyDetectionSensitivity: number;
  };
}

export class AdvancedMonitoringStack extends cdk.Stack {
  private readonly config: AdvancedMonitoringStackProps['config'];
  private readonly lambdaRole: iam.Role;
  private readonly alertTopics: {
    critical: sns.Topic;
    warning: sns.Topic;
    info: sns.Topic;
  };

  constructor(scope: Construct, id: string, props: AdvancedMonitoringStackProps) {
    super(scope, id, props);

    this.config = props.config;

    // Create IAM role for Lambda functions
    this.lambdaRole = this.createLambdaRole();

    // Create SNS topics for tiered alerting
    this.alertTopics = this.createAlertTopics();

    // Create Lambda functions for custom metrics
    const businessMetricsFunction = this.createBusinessMetricsFunction();
    const infrastructureHealthFunction = this.createInfrastructureHealthFunction();
    const costMonitoringFunction = this.createCostMonitoringFunction();

    // Create EventBridge rules for scheduled metric collection
    this.createScheduledRules([
      { function: businessMetricsFunction, schedule: 'rate(5 minutes)', name: 'business-metrics' },
      { function: infrastructureHealthFunction, schedule: 'rate(10 minutes)', name: 'infrastructure-health' },
      { function: costMonitoringFunction, schedule: 'rate(1 day)', name: 'cost-monitoring' },
    ]);

    // Create CloudWatch dashboards
    this.createInfrastructureDashboard();
    this.createBusinessDashboard();
    this.createExecutiveDashboard();
    this.createOperationsDashboard();

    // Create anomaly detectors
    this.createAnomalyDetectors();

    // Create intelligent alarms
    this.createIntelligentAlarms();

    // Output important information
    this.createOutputs();
  }

  private createLambdaRole(): iam.Role {
    const role = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for monitoring Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonRDSReadOnlyAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonElastiCacheReadOnlyAccess'),
      ],
    });

    // Add Cost Explorer permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ce:GetCostAndUsage',
        'ce:GetUsageReport',
        'ce:GetCostCategories',
        'ce:GetDimensionValues',
        'ce:GetReservationCoverage',
        'ce:GetReservationPurchaseRecommendation',
        'ce:GetReservationUtilization',
        'ce:GetUsageReport',
        'ce:ListCostCategoryDefinitions',
        'ce:GetRightsizingRecommendation',
      ],
      resources: ['*'],
    }));

    return role;
  }

  private createAlertTopics(): { critical: sns.Topic; warning: sns.Topic; info: sns.Topic } {
    const critical = new sns.Topic(this, 'CriticalAlerts', {
      topicName: `${this.config.projectName}-critical-alerts`,
      displayName: 'Critical Alerts',
      description: 'Critical alerts requiring immediate attention',
    });

    const warning = new sns.Topic(this, 'WarningAlerts', {
      topicName: `${this.config.projectName}-warning-alerts`,
      displayName: 'Warning Alerts',
      description: 'Warning alerts for operations team',
    });

    const info = new sns.Topic(this, 'InfoAlerts', {
      topicName: `${this.config.projectName}-info-alerts`,
      displayName: 'Info Alerts',
      description: 'Informational alerts and notifications',
    });

    // Subscribe email to critical alerts
    critical.addSubscription(new subscriptions.EmailSubscription(this.config.alertEmail));

    return { critical, warning, info };
  }

  private createBusinessMetricsFunction(): lambda.Function {
    const func = new lambda.Function(this, 'BusinessMetricsFunction', {
      functionName: `${this.config.projectName}-business-metrics`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import random
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Simulate business metrics (replace with real business logic)
        
        # Revenue metrics
        hourly_revenue = random.uniform(10000, 50000)
        transaction_count = random.randint(100, 1000)
        average_order_value = hourly_revenue / transaction_count
        
        # User engagement metrics
        active_users = random.randint(500, 5000)
        page_views = random.randint(10000, 50000)
        bounce_rate = random.uniform(0.2, 0.8)
        
        # Performance metrics
        api_response_time = random.uniform(100, 2000)
        error_rate = random.uniform(0.001, 0.05)
        throughput = random.randint(100, 1000)
        
        # Customer satisfaction
        nps_score = random.uniform(6.0, 9.5)
        support_ticket_volume = random.randint(5, 50)
        
        # Send custom metrics to CloudWatch
        metrics = [
            {
                'MetricName': 'HourlyRevenue',
                'Value': hourly_revenue,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${this.config.environment}'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'TransactionCount',
                'Value': transaction_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${this.config.environment}'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'AverageOrderValue',
                'Value': average_order_value,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${this.config.environment}'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'ActiveUsers',
                'Value': active_users,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${this.config.environment}'}
                ]
            },
            {
                'MetricName': 'APIResponseTime',
                'Value': api_response_time,
                'Unit': 'Milliseconds',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${this.config.environment}'},
                    {'Name': 'Service', 'Value': 'api-gateway'}
                ]
            },
            {
                'MetricName': 'ErrorRate',
                'Value': error_rate,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${this.config.environment}'},
                    {'Name': 'Service', 'Value': 'api-gateway'}
                ]
            },
            {
                'MetricName': 'NPSScore',
                'Value': nps_score,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${this.config.environment}'}
                ]
            },
            {
                'MetricName': 'SupportTicketVolume',
                'Value': support_ticket_volume,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': '${this.config.environment}'}
                ]
            }
        ]
        
        # Submit metrics in batches
        for i in range(0, len(metrics), 20):
            batch = metrics[i:i+20]
            cloudwatch.put_metric_data(
                Namespace='Business/Metrics',
                MetricData=batch
            )
        
        # Calculate and submit composite health score
        health_score = calculate_health_score(
            api_response_time, error_rate, nps_score, 
            support_ticket_volume, active_users
        )
        
        cloudwatch.put_metric_data(
            Namespace='Business/Health',
            MetricData=[
                {
                    'MetricName': 'CompositeHealthScore',
                    'Value': health_score,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': '${this.config.environment}'}
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Business metrics published successfully',
                'health_score': health_score,
                'metrics_count': len(metrics)
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def calculate_health_score(response_time, error_rate, nps, tickets, users):
    # Normalize metrics to 0-100 scale and weight them
    response_score = max(0, 100 - (response_time / 20))  # Lower is better
    error_score = max(0, 100 - (error_rate * 2000))      # Lower is better
    nps_score = (nps / 10) * 100                         # Higher is better
    ticket_score = max(0, 100 - (tickets * 2))          # Lower is better
    user_score = min(100, (users / 50))                 # Higher is better
    
    # Weighted average
    weights = [0.25, 0.30, 0.20, 0.15, 0.10]
    scores = [response_score, error_score, nps_score, ticket_score, user_score]
    
    return sum(w * s for w, s in zip(weights, scores))
      `),
      role: this.lambdaRole,
      timeout: cdk.Duration.seconds(60),
      description: 'Collects and publishes business metrics to CloudWatch',
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    return func;
  }

  private createInfrastructureHealthFunction(): lambda.Function {
    const func = new lambda.Function(this, 'InfrastructureHealthFunction', {
      functionName: `${this.config.projectName}-infrastructure-health`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
rds = boto3.client('rds')
elasticache = boto3.client('elasticache')
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    try:
        health_scores = {}
        
        # Check RDS health
        rds_health = check_rds_health()
        health_scores['RDS'] = rds_health
        
        # Check ElastiCache health
        cache_health = check_elasticache_health()
        health_scores['ElastiCache'] = cache_health
        
        # Check EC2/ECS health
        compute_health = check_compute_health()
        health_scores['Compute'] = compute_health
        
        # Calculate overall infrastructure health
        overall_health = sum(health_scores.values()) / len(health_scores)
        
        # Publish infrastructure health metrics
        metrics = []
        for service, score in health_scores.items():
            metrics.append({
                'MetricName': f'{service}HealthScore',
                'Value': score,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Service', 'Value': service},
                    {'Name': 'Environment', 'Value': '${this.config.environment}'}
                ]
            })
        
        # Add overall health score
        metrics.append({
            'MetricName': 'OverallInfrastructureHealth',
            'Value': overall_health,
            'Unit': 'Percent',
            'Dimensions': [
                {'Name': 'Environment', 'Value': '${this.config.environment}'}
            ]
        })
        
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Health',
            MetricData=metrics
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'health_scores': health_scores,
                'overall_health': overall_health
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_rds_health():
    try:
        instances = rds.describe_db_instances()
        if not instances['DBInstances']:
            return 100  # No instances to monitor
        
        healthy_count = 0
        total_count = len(instances['DBInstances'])
        
        for instance in instances['DBInstances']:
            if instance['DBInstanceStatus'] == 'available':
                healthy_count += 1
        
        return (healthy_count / total_count) * 100
    except:
        return 50  # Assume degraded if can't check

def check_elasticache_health():
    try:
        clusters = elasticache.describe_cache_clusters()
        if not clusters['CacheClusters']:
            return 100  # No clusters to monitor
        
        healthy_count = 0
        total_count = len(clusters['CacheClusters'])
        
        for cluster in clusters['CacheClusters']:
            if cluster['CacheClusterStatus'] == 'available':
                healthy_count += 1
        
        return (healthy_count / total_count) * 100
    except:
        return 50  # Assume degraded if can't check

def check_compute_health():
    try:
        # Simplified compute health check
        # In reality, you'd check ECS services, task health, etc.
        instances = ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        total_instances = 0
        for reservation in instances['Reservations']:
            total_instances += len(reservation['Instances'])
        
        # Simple health heuristic based on running instances
        if total_instances == 0:
            return 100  # No instances to monitor
        elif total_instances >= 3:
            return 95   # Good redundancy
        elif total_instances >= 2:
            return 80   # Acceptable redundancy
        else:
            return 60   # Limited redundancy
            
    except:
        return 50  # Assume degraded if can't check
      `),
      role: this.lambdaRole,
      timeout: cdk.Duration.seconds(120),
      description: 'Monitors infrastructure health across AWS services',
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    return func;
  }

  private createCostMonitoringFunction(): lambda.Function {
    const func = new lambda.Function(this, 'CostMonitoringFunction', {
      functionName: `${this.config.projectName}-cost-monitoring`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
ce = boto3.client('ce')

def lambda_handler(event, context):
    try:
        # Get cost data for the last 7 days
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=7)
        
        response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        # Calculate daily cost trend
        daily_costs = []
        for result in response['ResultsByTime']:
            daily_cost = float(result['Total']['BlendedCost']['Amount'])
            daily_costs.append(daily_cost)
        
        # Calculate cost metrics
        if daily_costs:
            avg_daily_cost = sum(daily_costs) / len(daily_costs)
            latest_cost = daily_costs[-1]
            cost_trend = ((latest_cost - avg_daily_cost) / avg_daily_cost) * 100 if avg_daily_cost > 0 else 0
        else:
            avg_daily_cost = 0
            latest_cost = 0
            cost_trend = 0
        
        # Publish cost metrics
        cloudwatch.put_metric_data(
            Namespace='Cost/Management',
            MetricData=[
                {
                    'MetricName': 'DailyCost',
                    'Value': latest_cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': '${this.config.environment}'}
                    ]
                },
                {
                    'MetricName': 'CostTrend',
                    'Value': cost_trend,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': '${this.config.environment}'}
                    ]
                },
                {
                    'MetricName': 'WeeklyAverageCost',
                    'Value': avg_daily_cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': '${this.config.environment}'}
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'daily_cost': latest_cost,
                'cost_trend': cost_trend,
                'weekly_average': avg_daily_cost
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      role: this.lambdaRole,
      timeout: cdk.Duration.seconds(120),
      description: 'Monitors AWS costs and publishes cost metrics',
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    return func;
  }

  private createScheduledRules(functions: Array<{ function: lambda.Function; schedule: string; name: string }>): void {
    functions.forEach(({ function: func, schedule, name }) => {
      const rule = new events.Rule(this, `${name}Rule`, {
        ruleName: `${this.config.projectName}-${name}`,
        schedule: events.Schedule.expression(schedule),
        description: `Scheduled execution for ${name} function`,
      });

      rule.addTarget(new targets.LambdaFunction(func));
    });
  }

  private createInfrastructureDashboard(): void {
    const dashboard = new cloudwatch.Dashboard(this, 'InfrastructureDashboard', {
      dashboardName: `${this.config.projectName}-Infrastructure`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // Overall System Health widget
    const systemHealthWidget = new cloudwatch.GraphWidget({
      title: 'Overall System Health',
      width: 8,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'Infrastructure/Health',
          metricName: 'OverallInfrastructureHealth',
          dimensionsMap: { Environment: this.config.environment },
        }),
        new cloudwatch.Metric({
          namespace: 'Business/Health',
          metricName: 'CompositeHealthScore',
          dimensionsMap: { Environment: this.config.environment },
        }),
      ],
      leftYAxis: { min: 0, max: 100 },
    });

    // Service Health Scores widget
    const serviceHealthWidget = new cloudwatch.GraphWidget({
      title: 'Service Health Scores',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'Infrastructure/Health',
          metricName: 'RDSHealthScore',
          dimensionsMap: { Service: 'RDS', Environment: this.config.environment },
        }),
        new cloudwatch.Metric({
          namespace: 'Infrastructure/Health',
          metricName: 'ElastiCacheHealthScore',
          dimensionsMap: { Service: 'ElastiCache', Environment: this.config.environment },
        }),
        new cloudwatch.Metric({
          namespace: 'Infrastructure/Health',
          metricName: 'ComputeHealthScore',
          dimensionsMap: { Service: 'Compute', Environment: this.config.environment },
        }),
      ],
      leftYAxis: { min: 0, max: 100 },
    });

    dashboard.addWidgets(systemHealthWidget, serviceHealthWidget);
  }

  private createBusinessDashboard(): void {
    const dashboard = new cloudwatch.Dashboard(this, 'BusinessDashboard', {
      dashboardName: `${this.config.projectName}-Business`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // Revenue widget
    const revenueWidget = new cloudwatch.GraphWidget({
      title: 'Hourly Revenue',
      width: 8,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'Business/Metrics',
          metricName: 'HourlyRevenue',
          dimensionsMap: { Environment: this.config.environment, BusinessUnit: 'ecommerce' },
        }),
      ],
    });

    // Transaction Volume widget
    const transactionWidget = new cloudwatch.GraphWidget({
      title: 'Transaction Volume & Active Users',
      width: 8,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'Business/Metrics',
          metricName: 'TransactionCount',
          dimensionsMap: { Environment: this.config.environment, BusinessUnit: 'ecommerce' },
          statistic: 'Sum',
        }),
        new cloudwatch.Metric({
          namespace: 'Business/Metrics',
          metricName: 'ActiveUsers',
          dimensionsMap: { Environment: this.config.environment },
          statistic: 'Sum',
        }),
      ],
    });

    // API Performance widget
    const apiPerformanceWidget = new cloudwatch.GraphWidget({
      title: 'API Performance Metrics',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'Business/Metrics',
          metricName: 'APIResponseTime',
          dimensionsMap: { Environment: this.config.environment, Service: 'api-gateway' },
        }),
        new cloudwatch.Metric({
          namespace: 'Business/Metrics',
          metricName: 'ErrorRate',
          dimensionsMap: { Environment: this.config.environment, Service: 'api-gateway' },
        }),
      ],
    });

    dashboard.addWidgets(revenueWidget, transactionWidget, apiPerformanceWidget);
  }

  private createExecutiveDashboard(): void {
    const dashboard = new cloudwatch.Dashboard(this, 'ExecutiveDashboard', {
      dashboardName: `${this.config.projectName}-Executive`,
      defaultInterval: cdk.Duration.hours(24),
    });

    // System Health Overview widget
    const healthOverviewWidget = new cloudwatch.GraphWidget({
      title: 'System Health Overview (Last 24 Hours)',
      width: 24,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'Business/Health',
          metricName: 'CompositeHealthScore',
          dimensionsMap: { Environment: this.config.environment },
        }),
        new cloudwatch.Metric({
          namespace: 'Infrastructure/Health',
          metricName: 'OverallInfrastructureHealth',
          dimensionsMap: { Environment: this.config.environment },
        }),
      ],
      leftYAxis: { min: 0, max: 100 },
    });

    // Revenue trend widget
    const revenueTrendWidget = new cloudwatch.SingleValueWidget({
      title: 'Revenue Trend (24H)',
      width: 8,
      height: 6,
      metrics: [
        new cloudwatch.Metric({
          namespace: 'Business/Metrics',
          metricName: 'HourlyRevenue',
          dimensionsMap: { Environment: this.config.environment, BusinessUnit: 'ecommerce' },
          statistic: 'Sum',
        }),
      ],
      setPeriodToTimeRange: true,
    });

    // Customer satisfaction widget
    const customerSatWidget = new cloudwatch.SingleValueWidget({
      title: 'Customer Satisfaction (NPS)',
      width: 8,
      height: 6,
      metrics: [
        new cloudwatch.Metric({
          namespace: 'Business/Metrics',
          metricName: 'NPSScore',
          dimensionsMap: { Environment: this.config.environment },
        }),
      ],
      setPeriodToTimeRange: true,
    });

    dashboard.addWidgets(healthOverviewWidget, revenueTrendWidget, customerSatWidget);
  }

  private createOperationsDashboard(): void {
    const dashboard = new cloudwatch.Dashboard(this, 'OperationsDashboard', {
      dashboardName: `${this.config.projectName}-Operations`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // Cost monitoring widget
    const costWidget = new cloudwatch.GraphWidget({
      title: 'Cost Monitoring',
      width: 8,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'Cost/Management',
          metricName: 'DailyCost',
          dimensionsMap: { Environment: this.config.environment },
        }),
        new cloudwatch.Metric({
          namespace: 'Cost/Management',
          metricName: 'CostTrend',
          dimensionsMap: { Environment: this.config.environment },
        }),
      ],
    });

    dashboard.addWidgets(costWidget);
  }

  private createAnomalyDetectors(): void {
    // Revenue anomaly detector
    new cloudwatch.CfnAnomalyDetector(this, 'RevenueAnomalyDetector', {
      namespace: 'Business/Metrics',
      metricName: 'HourlyRevenue',
      dimensions: [
        { name: 'Environment', value: this.config.environment },
        { name: 'BusinessUnit', value: 'ecommerce' },
      ],
      stat: 'Average',
    });

    // Response time anomaly detector
    new cloudwatch.CfnAnomalyDetector(this, 'ResponseTimeAnomalyDetector', {
      namespace: 'Business/Metrics',
      metricName: 'APIResponseTime',
      dimensions: [
        { name: 'Environment', value: this.config.environment },
        { name: 'Service', value: 'api-gateway' },
      ],
      stat: 'Average',
    });

    // Error rate anomaly detector
    new cloudwatch.CfnAnomalyDetector(this, 'ErrorRateAnomalyDetector', {
      namespace: 'Business/Metrics',
      metricName: 'ErrorRate',
      dimensions: [
        { name: 'Environment', value: this.config.environment },
        { name: 'Service', value: 'api-gateway' },
      ],
      stat: 'Average',
    });

    // Infrastructure health anomaly detector
    new cloudwatch.CfnAnomalyDetector(this, 'InfraHealthAnomalyDetector', {
      namespace: 'Infrastructure/Health',
      metricName: 'OverallInfrastructureHealth',
      dimensions: [
        { name: 'Environment', value: this.config.environment },
      ],
      stat: 'Average',
    });
  }

  private createIntelligentAlarms(): void {
    // Revenue anomaly alarm
    new cloudwatch.Alarm(this, 'RevenueAnomalyAlarm', {
      alarmName: `${this.config.projectName}-revenue-anomaly`,
      alarmDescription: 'Revenue anomaly detected',
      metric: new cloudwatch.MathExpression({
        expression: `ANOMALY_DETECTION_BAND(m1, ${this.config.anomalyDetectionSensitivity})`,
        usingMetrics: {
          m1: new cloudwatch.Metric({
            namespace: 'Business/Metrics',
            metricName: 'HourlyRevenue',
            dimensionsMap: { Environment: this.config.environment, BusinessUnit: 'ecommerce' },
          }),
        },
      }),
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_LOWER_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Infrastructure health threshold alarm
    const infraHealthAlarm = new cloudwatch.Alarm(this, 'InfraHealthAlarm', {
      alarmName: `${this.config.projectName}-infrastructure-health-low`,
      alarmDescription: 'Infrastructure health score below threshold',
      metric: new cloudwatch.Metric({
        namespace: 'Infrastructure/Health',
        metricName: 'OverallInfrastructureHealth',
        dimensionsMap: { Environment: this.config.environment },
      }),
      threshold: 80,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Add alarm actions
    infraHealthAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopics.critical));
  }

  private createOutputs(): void {
    new cdk.CfnOutput(this, 'InfrastructureDashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.config.projectName}-Infrastructure`,
      description: 'URL for Infrastructure Dashboard',
    });

    new cdk.CfnOutput(this, 'BusinessDashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.config.projectName}-Business`,
      description: 'URL for Business Dashboard',
    });

    new cdk.CfnOutput(this, 'ExecutiveDashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.config.projectName}-Executive`,
      description: 'URL for Executive Dashboard',
    });

    new cdk.CfnOutput(this, 'OperationsDashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.config.projectName}-Operations`,
      description: 'URL for Operations Dashboard',
    });

    new cdk.CfnOutput(this, 'CriticalAlertsTopicArn', {
      value: this.alertTopics.critical.topicArn,
      description: 'ARN of the Critical Alerts SNS Topic',
    });
  }
}