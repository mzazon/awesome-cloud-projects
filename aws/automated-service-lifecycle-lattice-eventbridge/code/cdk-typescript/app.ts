#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Duration, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';

/**
 * CDK Stack for Automated Service Lifecycle Management with VPC Lattice and EventBridge
 * 
 * This stack implements an automated service lifecycle management system that:
 * - Creates a VPC Lattice service network for microservice communication
 * - Sets up EventBridge for event-driven automation
 * - Deploys Lambda functions for health monitoring and auto-scaling
 * - Configures CloudWatch for comprehensive monitoring and dashboards
 * - Implements scheduled health checks and event-driven responses
 */
export class AutomatedServiceLifecycleStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // CloudWatch Log Group for VPC Lattice access logs
    const latticeLogGroup = new logs.LogGroup(this, 'LatticeAccessLogGroup', {
      logGroupName: `/aws/vpclattice/service-lifecycle-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // VPC Lattice Service Network
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `microservices-network-${uniqueSuffix}`,
      authType: 'AWS_IAM',
    });

    // Enable access logging for the service network
    new vpclattice.CfnAccessLogSubscription(this, 'ServiceNetworkAccessLogs', {
      resourceIdentifier: serviceNetwork.attrId,
      destinationArn: latticeLogGroup.logGroupArn,
    });

    // Custom EventBridge Bus for service lifecycle events
    const customEventBus = new events.EventBus(this, 'ServiceLifecycleBus', {
      eventBusName: `service-lifecycle-bus-${uniqueSuffix}`,
    });

    // IAM Role for Lambda functions with comprehensive permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `service-lifecycle-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ServiceLifecyclePolicy: new iam.PolicyDocument({
          statements: [
            // VPC Lattice permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'vpc-lattice:*',
              ],
              resources: ['*'],
            }),
            // CloudWatch permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics',
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
            // EventBridge permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'events:PutEvents',
              ],
              resources: [customEventBus.eventBusArn],
            }),
            // ECS permissions for scaling operations
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecs:DescribeServices',
                'ecs:UpdateService',
                'ecs:ListTasks',
                'ecs:DescribeTasks',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Health Monitoring Lambda Function
    const healthMonitorFunction = new lambda.Function(this, 'HealthMonitorFunction', {
      functionName: `service-health-monitor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.minutes(1),
      memorySize: 256,
      environment: {
        SERVICE_NETWORK_ID: serviceNetwork.attrId,
        EVENT_BUS_NAME: customEventBus.eventBusName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Monitor VPC Lattice service health and publish lifecycle events.
    
    This function:
    1. Retrieves all services in the VPC Lattice service network
    2. Queries CloudWatch metrics for service health indicators
    3. Determines health status based on request patterns
    4. Publishes health events to EventBridge for automation
    """
    lattice = boto3.client('vpc-lattice')
    cloudwatch = boto3.client('cloudwatch')
    eventbridge = boto3.client('events')
    
    service_network_id = os.environ['SERVICE_NETWORK_ID']
    event_bus_name = os.environ['EVENT_BUS_NAME']
    
    try:
        logger.info(f"Starting health check for service network: {service_network_id}")
        
        # Get service network services
        try:
            services = lattice.list_services(
                serviceNetworkIdentifier=service_network_id
            )
        except Exception as e:
            logger.warning(f"No services found in network or network not ready: {e}")
            # Return success for empty network (not an error condition)
            return {'statusCode': 200, 'body': 'No services to monitor'}
        
        services_monitored = 0
        
        for service in services.get('items', []):
            service_id = service['id']
            service_name = service['name']
            
            logger.info(f"Monitoring service: {service_name} ({service_id})")
            
            # Get CloudWatch metrics for service health
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(minutes=5)
            
            try:
                # Query VPC Lattice metrics
                metrics = cloudwatch.get_metric_statistics(
                    Namespace='AWS/VpcLattice',
                    MetricName='RequestCount',
                    Dimensions=[
                        {'Name': 'ServiceId', 'Value': service_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Sum']
                )
                
                # Determine service health based on metrics
                request_count = sum([point['Sum'] for point in metrics['Datapoints']])
                
                # Simple health determination - in production, use more sophisticated logic
                health_status = 'healthy' if request_count >= 0 else 'unknown'
                
                # Get additional metrics for comprehensive monitoring
                try:
                    error_metrics = cloudwatch.get_metric_statistics(
                        Namespace='AWS/VpcLattice',
                        MetricName='HTTP_5XX_Count',
                        Dimensions=[
                            {'Name': 'ServiceId', 'Value': service_id}
                        ],
                        StartTime=start_time,
                        EndTime=end_time,
                        Period=300,
                        Statistics=['Sum']
                    )
                    error_count = sum([point['Sum'] for point in error_metrics['Datapoints']])
                    
                    # Adjust health status based on error rate
                    if error_count > 0 and request_count > 0:
                        error_rate = error_count / request_count
                        if error_rate > 0.05:  # 5% error threshold
                            health_status = 'unhealthy'
                except Exception as e:
                    logger.warning(f"Could not retrieve error metrics: {e}")
                    error_count = 0
                
            except Exception as e:
                logger.warning(f"Could not retrieve metrics for service {service_id}: {e}")
                request_count = 0
                error_count = 0
                health_status = 'unknown'
            
            # Publish service health event
            event_detail = {
                'serviceId': service_id,
                'serviceName': service_name,
                'healthStatus': health_status,
                'requestCount': int(request_count),
                'errorCount': int(error_count),
                'timestamp': datetime.utcnow().isoformat(),
                'serviceNetworkId': service_network_id
            }
            
            try:
                eventbridge.put_events(
                    Entries=[
                        {
                            'Source': 'vpc-lattice.health-monitor',
                            'DetailType': 'Service Health Check',
                            'Detail': json.dumps(event_detail),
                            'EventBusName': event_bus_name
                        }
                    ]
                )
                logger.info(f"Published health event for {service_name}: {health_status}")
                services_monitored += 1
                
            except Exception as e:
                logger.error(f"Failed to publish event for service {service_id}: {e}")
        
        logger.info(f"Health check completed. Monitored {services_monitored} services.")
        return {
            'statusCode': 200, 
            'body': f'Health check completed for {services_monitored} services'
        }
        
    except Exception as e:
        logger.error(f"Error in health monitoring: {str(e)}")
        return {'statusCode': 500, 'body': f"Error: {str(e)}"}
`),
    });

    // Auto-Scaling Lambda Function
    const autoScalerFunction = new lambda.Function(this, 'AutoScalerFunction', {
      functionName: `service-auto-scaler-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.minutes(1),
      memorySize: 256,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Respond to service health events and implement intelligent scaling decisions.
    
    This function:
    1. Processes EventBridge health events
    2. Evaluates scaling requirements based on health and metrics
    3. Implements scaling logic (demonstration mode)
    4. Logs scaling decisions for audit and monitoring
    """
    lattice = boto3.client('vpc-lattice')
    ecs = boto3.client('ecs')
    
    try:
        logger.info(f"Processing scaling event: {json.dumps(event, default=str)}")
        
        # Parse EventBridge event
        if 'detail' not in event:
            logger.warning("No detail found in event, skipping processing")
            return {'statusCode': 200, 'body': 'No detail to process'}
            
        detail = event['detail']
        if isinstance(detail, str):
            detail = json.loads(detail)
        
        service_id = detail.get('serviceId')
        service_name = detail.get('serviceName')
        health_status = detail.get('healthStatus')
        request_count = detail.get('requestCount', 0)
        error_count = detail.get('errorCount', 0)
        
        if not all([service_id, service_name, health_status]):
            logger.warning("Missing required fields in event detail")
            return {'statusCode': 400, 'body': 'Missing required event fields'}
        
        logger.info(f"Processing scaling for service: {service_name}")
        logger.info(f"Health: {health_status}, Requests: {request_count}, Errors: {error_count}")
        
        # Get target groups for the service
        try:
            target_groups = lattice.list_target_groups(
                serviceIdentifier=service_id
            )
            
            for tg in target_groups.get('items', []):
                tg_id = tg['id']
                tg_name = tg.get('name', 'unknown')
                
                logger.info(f"Evaluating target group: {tg_name} ({tg_id})")
                
                # Get current target count
                try:
                    targets = lattice.list_targets(
                        targetGroupIdentifier=tg_id
                    )
                    current_count = len(targets.get('items', []))
                    
                    logger.info(f"Current target count: {current_count}")
                    
                    # Scaling decision logic
                    scaling_action = determine_scaling_action(
                        health_status, request_count, error_count, current_count
                    )
                    
                    if scaling_action['action'] != 'none':
                        logger.info(f"Scaling decision: {scaling_action['action']} - {scaling_action['reason']}")
                        
                        # In a production environment, implement actual scaling here:
                        # - Update ECS service desired count
                        # - Trigger Auto Scaling Group scaling
                        # - Add/remove targets from target groups
                        
                        # For demonstration, log the scaling decision
                        log_scaling_decision(service_name, tg_name, scaling_action)
                    else:
                        logger.info("No scaling action required")
                        
                except Exception as e:
                    logger.error(f"Error processing target group {tg_id}: {e}")
                    
        except Exception as e:
            logger.warning(f"Could not retrieve target groups for service {service_id}: {e}")
        
        return {
            'statusCode': 200, 
            'body': f'Scaling evaluation completed for service {service_name}'
        }
        
    except Exception as e:
        logger.error(f"Error in auto-scaling: {str(e)}")
        return {'statusCode': 500, 'body': f"Error: {str(e)}"}

def determine_scaling_action(health_status: str, request_count: int, error_count: int, current_count: int) -> Dict[str, str]:
    """
    Determine appropriate scaling action based on service metrics.
    
    Args:
        health_status: Current health status of the service
        request_count: Number of requests in monitoring period
        error_count: Number of errors in monitoring period
        current_count: Current number of targets
    
    Returns:
        Dictionary with scaling action and reason
    """
    max_targets = 10
    min_targets = 1
    
    # Scale up conditions
    if health_status == 'unhealthy' and current_count < max_targets:
        return {
            'action': 'scale_up',
            'reason': f'Service unhealthy with {current_count} targets, scaling up for resilience'
        }
    
    if request_count > 100 and current_count < max_targets:
        return {
            'action': 'scale_up',
            'reason': f'High request volume ({request_count}) detected, scaling up'
        }
    
    if error_count > 0 and request_count > 0:
        error_rate = error_count / request_count
        if error_rate > 0.1 and current_count < max_targets:  # 10% error rate
            return {
                'action': 'scale_up',
                'reason': f'High error rate ({error_rate:.1%}) detected, scaling up'
            }
    
    # Scale down conditions
    if (health_status == 'healthy' and 
        request_count < 10 and 
        error_count == 0 and 
        current_count > min_targets):
        return {
            'action': 'scale_down',
            'reason': f'Low traffic ({request_count} requests) and healthy status, scaling down'
        }
    
    return {
        'action': 'none',
        'reason': 'Current scaling level is appropriate'
    }

def log_scaling_decision(service_name: str, target_group_name: str, scaling_action: Dict[str, str]) -> None:
    """Log scaling decisions for audit and monitoring."""
    logger.info(f"SCALING_DECISION: Service={service_name}, TargetGroup={target_group_name}, "
               f"Action={scaling_action['action']}, Reason={scaling_action['reason']}")
`),
    });

    // EventBridge Rule for Health Monitoring Events
    const healthMonitoringRule = new events.Rule(this, 'HealthMonitoringRule', {
      ruleName: `health-monitoring-rule-${uniqueSuffix}`,
      eventBus: customEventBus,
      eventPattern: {
        source: ['vpc-lattice.health-monitor'],
        detailType: ['Service Health Check'],
        detail: {
          healthStatus: ['unhealthy', 'healthy'],
        },
      },
      enabled: true,
    });

    // Add auto-scaler as target for health events
    healthMonitoringRule.addTarget(new targets.LambdaFunction(autoScalerFunction));

    // Scheduled Rule for Regular Health Checks
    const scheduledHealthCheck = new events.Rule(this, 'ScheduledHealthCheck', {
      ruleName: `scheduled-health-check-${uniqueSuffix}`,
      schedule: events.Schedule.rate(Duration.minutes(5)),
      enabled: true,
    });

    // Add health monitor as target for scheduled checks
    scheduledHealthCheck.addTarget(new targets.LambdaFunction(healthMonitorFunction));

    // CloudWatch Dashboard for Service Lifecycle Monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'ServiceLifecycleDashboard', {
      dashboardName: `ServiceLifecycle-${uniqueSuffix}`,
      widgets: [
        [
          // VPC Lattice metrics
          new cloudwatch.GraphWidget({
            title: 'VPC Lattice Service Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'RequestCount',
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'ResponseTime',
                statistic: 'Average',
              }),
            ],
            period: Duration.minutes(5),
            width: 12,
            height: 6,
          }),
        ],
        [
          // Lambda function metrics
          new cloudwatch.GraphWidget({
            title: 'Health Monitor Function Metrics',
            left: [
              healthMonitorFunction.metricInvocations(),
              healthMonitorFunction.metricErrors(),
            ],
            right: [healthMonitorFunction.metricDuration()],
            period: Duration.minutes(5),
            width: 6,
            height: 6,
          }),
          // Auto-scaler function metrics
          new cloudwatch.GraphWidget({
            title: 'Auto-Scaler Function Metrics',
            left: [
              autoScalerFunction.metricInvocations(),
              autoScalerFunction.metricErrors(),
            ],
            right: [autoScalerFunction.metricDuration()],
            period: Duration.minutes(5),
            width: 6,
            height: 6,
          }),
        ],
        [
          // EventBridge metrics
          new cloudwatch.GraphWidget({
            title: 'EventBridge Custom Bus Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'SuccessfulInvocations',
                dimensionsMap: {
                  EventBusName: customEventBus.eventBusName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'FailedInvocations',
                dimensionsMap: {
                  EventBusName: customEventBus.eventBusName,
                },
                statistic: 'Sum',
              }),
            ],
            period: Duration.minutes(5),
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // CloudWatch Alarms for Critical Events
    const healthMonitorErrorAlarm = new cloudwatch.Alarm(this, 'HealthMonitorErrorAlarm', {
      alarmName: `health-monitor-errors-${uniqueSuffix}`,
      alarmDescription: 'Health monitor function experiencing errors',
      metric: healthMonitorFunction.metricErrors({
        period: Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const autoScalerErrorAlarm = new cloudwatch.Alarm(this, 'AutoScalerErrorAlarm', {
      alarmName: `auto-scaler-errors-${uniqueSuffix}`,
      alarmDescription: 'Auto-scaler function experiencing errors',
      metric: autoScalerFunction.metricErrors({
        period: Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkArn', {
      value: serviceNetwork.attrArn,
      description: 'VPC Lattice Service Network ARN',
      exportName: `${this.stackName}-ServiceNetworkArn`,
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: customEventBus.eventBusName,
      description: 'Custom EventBridge Bus Name',
      exportName: `${this.stackName}-EventBusName`,
    });

    new cdk.CfnOutput(this, 'EventBusArn', {
      value: customEventBus.eventBusArn,
      description: 'Custom EventBridge Bus ARN',
      exportName: `${this.stackName}-EventBusArn`,
    });

    new cdk.CfnOutput(this, 'HealthMonitorFunctionArn', {
      value: healthMonitorFunction.functionArn,
      description: 'Health Monitor Lambda Function ARN',
      exportName: `${this.stackName}-HealthMonitorFunctionArn`,
    });

    new cdk.CfnOutput(this, 'AutoScalerFunctionArn', {
      value: autoScalerFunction.functionArn,
      description: 'Auto-Scaler Lambda Function ARN',
      exportName: `${this.stackName}-AutoScalerFunctionArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: latticeLogGroup.logGroupName,
      description: 'VPC Lattice Access Log Group Name',
      exportName: `${this.stackName}-LogGroupName`,
    });
  }
}

// CDK App instantiation
const app = new cdk.App();

// Get stack name from context or use default
const stackName = app.node.tryGetContext('stackName') || 'AutomatedServiceLifecycleStack';

// Create the stack
new AutomatedServiceLifecycleStack(app, stackName, {
  description: 'Automated Service Lifecycle Management with VPC Lattice and EventBridge (Recipe: a4b9c7e3)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'CloudRecipes',
    Recipe: 'automated-service-lifecycle-lattice-eventbridge',
    RecipeId: 'a4b9c7e3',
    Purpose: 'DemoAndTesting',
    Environment: 'Development',
    ManagedBy: 'CDK',
  },
});

// Synthesize the app
app.synth();