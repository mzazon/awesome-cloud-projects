#!/usr/bin/env node

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';

/**
 * Properties for the ApplicationHealthMonitoringStack
 */
interface ApplicationHealthMonitoringStackProps extends cdk.StackProps {
  /**
   * The VPC ID to use for VPC Lattice resources
   * If not provided, the default VPC will be used
   */
  readonly vpcId?: string;
  
  /**
   * Email address to subscribe to SNS notifications
   * If not provided, no email subscription will be created
   */
  readonly notificationEmail?: string;
  
  /**
   * Environment name for resource tagging
   * @default 'demo'
   */
  readonly environmentName?: string;
  
  /**
   * Prefix for resource names to ensure uniqueness
   * @default 'health-monitor'
   */
  readonly resourcePrefix?: string;
}

/**
 * AWS CDK Stack for Application Health Monitoring with VPC Lattice and CloudWatch
 * 
 * This stack creates a comprehensive health monitoring system that includes:
 * - VPC Lattice Service Network and Service
 * - Target Group with health checks
 * - CloudWatch alarms for monitoring health metrics
 * - Lambda function for auto-remediation
 * - SNS topic for notifications
 * - CloudWatch dashboard for operational visibility
 */
export class ApplicationHealthMonitoringStack extends cdk.Stack {
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  public readonly service: vpclattice.CfnService;
  public readonly targetGroup: vpclattice.CfnTargetGroup;
  public readonly remediationFunction: lambda.Function;
  public readonly notificationTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: ApplicationHealthMonitoringStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const environmentName = props.environmentName ?? 'demo';
    const resourcePrefix = props.resourcePrefix ?? 'health-monitor';
    
    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Get VPC - use provided VPC ID or find default VPC
    const vpc = props.vpcId 
      ? ec2.Vpc.fromLookup(this, 'Vpc', { vpcId: props.vpcId })
      : ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });

    // Create VPC Lattice Service Network
    this.serviceNetwork = this.createServiceNetwork(resourcePrefix, uniqueSuffix, environmentName);

    // Associate VPC with Service Network
    this.createVpcAssociation(vpc);

    // Create Target Group with health checks
    this.targetGroup = this.createTargetGroup(vpc, resourcePrefix, uniqueSuffix, environmentName);

    // Create VPC Lattice Service
    this.service = this.createService(resourcePrefix, uniqueSuffix, environmentName);

    // Associate Service with Service Network
    this.createServiceNetworkAssociation();

    // Create Listener for the Service
    this.createServiceListener();

    // Create SNS Topic for notifications
    this.notificationTopic = this.createNotificationTopic(resourcePrefix, uniqueSuffix, props.notificationEmail);

    // Create Lambda function for auto-remediation
    this.remediationFunction = this.createRemediationFunction(resourcePrefix, uniqueSuffix, environmentName);

    // Create CloudWatch alarms
    this.createCloudWatchAlarms(resourcePrefix, uniqueSuffix);

    // Create CloudWatch dashboard
    this.dashboard = this.createCloudWatchDashboard(resourcePrefix, uniqueSuffix);

    // Add outputs
    this.addOutputs(uniqueSuffix);
  }

  /**
   * Creates a VPC Lattice Service Network with AWS IAM authentication
   */
  private createServiceNetwork(prefix: string, suffix: string, environment: string): vpclattice.CfnServiceNetwork {
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `${prefix}-network-${suffix}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Environment', value: environment },
        { key: 'Purpose', value: 'health-monitoring' },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });

    // Add metadata for better documentation
    serviceNetwork.addMetadata('Description', 'VPC Lattice Service Network for application health monitoring');

    return serviceNetwork;
  }

  /**
   * Creates VPC association with the Service Network
   */
  private createVpcAssociation(vpc: ec2.IVpc): void {
    new vpclattice.CfnServiceNetworkVpcAssociation(this, 'VpcAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      vpcIdentifier: vpc.vpcId,
      tags: [
        { key: 'Environment', value: 'demo' },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });
  }

  /**
   * Creates a Target Group with comprehensive health check configuration
   */
  private createTargetGroup(vpc: ec2.IVpc, prefix: string, suffix: string, environment: string): vpclattice.CfnTargetGroup {
    const targetGroup = new vpclattice.CfnTargetGroup(this, 'TargetGroup', {
      name: `${prefix}-targets-${suffix}`,
      type: 'INSTANCE',
      protocol: 'HTTP',
      port: 80,
      vpcIdentifier: vpc.vpcId,
      config: {
        healthCheck: {
          enabled: true,
          protocol: 'HTTP',
          port: 80,
          path: '/health',
          healthCheckIntervalSeconds: 30,
          healthCheckTimeoutSeconds: 5,
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 2
        }
      },
      tags: [
        { key: 'Environment', value: environment },
        { key: 'Purpose', value: 'health-monitoring' },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });

    targetGroup.addMetadata('Description', 'Target group with aggressive health checking for rapid issue detection');

    return targetGroup;
  }

  /**
   * Creates a VPC Lattice Service
   */
  private createService(prefix: string, suffix: string, environment: string): vpclattice.CfnService {
    const service = new vpclattice.CfnService(this, 'Service', {
      name: `${prefix}-service-${suffix}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Environment', value: environment },
        { key: 'Purpose', value: 'health-monitoring' },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });

    service.addMetadata('Description', 'VPC Lattice Service for health monitoring demo');

    return service;
  }

  /**
   * Creates Service Network Association for the Service
   */
  private createServiceNetworkAssociation(): void {
    new vpclattice.CfnServiceNetworkServiceAssociation(this, 'ServiceNetworkAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      serviceIdentifier: this.service.attrId
    });
  }

  /**
   * Creates HTTP Listener for the Service
   */
  private createServiceListener(): void {
    new vpclattice.CfnListener(this, 'HttpListener', {
      serviceIdentifier: this.service.attrId,
      name: 'http-listener',
      protocol: 'HTTP',
      port: 80,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: this.targetGroup.attrId,
              weight: 100
            }
          ]
        }
      }
    });
  }

  /**
   * Creates SNS Topic for health notifications
   */
  private createNotificationTopic(prefix: string, suffix: string, email?: string): sns.Topic {
    const topic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${prefix}-alerts-${suffix}`,
      displayName: 'Application Health Alerts',
      description: 'SNS topic for VPC Lattice health monitoring alerts and notifications'
    });

    // Add email subscription if provided
    if (email) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(email));
    }

    // Apply security best practices
    topic.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'DenyInsecureConnections',
      effect: iam.Effect.DENY,
      principals: [new iam.AnyPrincipal()],
      actions: ['sns:*'],
      resources: [topic.topicArn],
      conditions: {
        Bool: {
          'aws:SecureTransport': 'false'
        }
      }
    }));

    // Add tags
    cdk.Tags.of(topic).add('Environment', 'demo');
    cdk.Tags.of(topic).add('Purpose', 'health-monitoring');
    cdk.Tags.of(topic).add('ManagedBy', 'CDK');

    return topic;
  }

  /**
   * Creates Lambda function for auto-remediation with comprehensive IAM permissions
   */
  private createRemediationFunction(prefix: string, suffix: string, environment: string): lambda.Function {
    // Create IAM role for Lambda with least privilege principles
    const lambdaRole = new iam.Role(this, 'RemediationLambdaRole', {
      roleName: `${prefix}-remediation-role-${suffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for VPC Lattice health remediation Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Add custom permissions for VPC Lattice, CloudWatch, and EC2
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      sid: 'VpcLatticeAccess',
      effect: iam.Effect.ALLOW,
      actions: [
        'vpc-lattice:GetService',
        'vpc-lattice:GetTargetGroup',
        'vpc-lattice:ListTargets',
        'vpc-lattice:DeregisterTargets',
        'vpc-lattice:RegisterTargets'
      ],
      resources: ['*']
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      sid: 'CloudWatchAccess',
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:ListMetrics'
      ],
      resources: ['*']
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      sid: 'EC2Access',
      effect: iam.Effect.ALLOW,
      actions: [
        'ec2:DescribeInstances',
        'ec2:RebootInstances'
      ],
      resources: ['*']
    }));

    // Grant SNS publish permissions
    this.notificationTopic.grantPublish(lambdaRole);

    // Create Lambda function with Python 3.12 runtime
    const remediationFunction = new lambda.Function(this, 'RemediationFunction', {
      functionName: `${prefix}-remediation-${suffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Auto-remediation function for VPC Lattice health monitoring',
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        SERVICE_ID: this.service.attrId,
        TARGET_GROUP_ID: this.targetGroup.attrId
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Auto-remediation function for VPC Lattice health issues
    """
    try:
        # Parse CloudWatch alarm data
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        alarm_state = message['NewStateValue']
        
        logger.info(f"Processing alarm: {alarm_name}, State: {alarm_state}")
        
        if alarm_state == 'ALARM':
            # Determine remediation action based on alarm type
            if '5XX' in alarm_name:
                remediate_error_rate(message)
            elif 'Timeout' in alarm_name:
                remediate_timeouts(message)
            elif 'ResponseTime' in alarm_name:
                remediate_performance(message)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed alarm: {alarm_name}')
        }
        
    except Exception as e:
        logger.error(f"Error processing alarm: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def remediate_error_rate(alarm_data):
    """Handle high error rate alarms"""
    logger.info("Implementing error rate remediation")
    
    # In a production implementation, you would:
    # 1. Identify unhealthy targets using VPC Lattice APIs
    # 2. Remove them from the target group
    # 3. Trigger instance replacement via Auto Scaling
    # 4. Monitor recovery and restore traffic
    
    send_notification(
        "🚨 High Error Rate Detected",
        f"Alarm: {alarm_data['AlarmName']}\\n"
        f"Action: Investigating unhealthy targets\\n"
        f"Time: {alarm_data['StateChangeTime']}\\n"
        f"Region: {alarm_data['Region']}\\n"
        f"Service: {os.environ.get('SERVICE_ID', 'Unknown')}"
    )

def remediate_timeouts(alarm_data):
    """Handle timeout alarms"""
    logger.info("Implementing timeout remediation")
    
    # Production implementation would:
    # 1. Check target group capacity
    # 2. Scale out if needed
    # 3. Investigate target health
    # 4. Restart unhealthy instances
    
    send_notification(
        "⏰ Request Timeouts Detected", 
        f"Alarm: {alarm_data['AlarmName']}\\n"
        f"Action: Checking target capacity and health\\n"
        f"Time: {alarm_data['StateChangeTime']}\\n"
        f"Region: {alarm_data['Region']}\\n"
        f"Target Group: {os.environ.get('TARGET_GROUP_ID', 'Unknown')}"
    )

def remediate_performance(alarm_data):
    """Handle performance degradation"""
    logger.info("Implementing performance remediation")
    
    # Production implementation would:
    # 1. Analyze response time patterns
    # 2. Check resource utilization
    # 3. Scale resources if needed
    # 4. Optimize configurations
    
    send_notification(
        "📉 Performance Degradation Detected",
        f"Alarm: {alarm_data['AlarmName']}\\n"
        f"Action: Analyzing response times and resource usage\\n"
        f"Time: {alarm_data['StateChangeTime']}\\n"
        f"Region: {alarm_data['Region']}\\n"
        f"Service: {os.environ.get('SERVICE_ID', 'Unknown')}"
    )

def send_notification(subject, message):
    """Send SNS notification"""
    try:
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=subject,
            Message=message
        )
        logger.info("Notification sent successfully")
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")
      `)
    });

    // Subscribe Lambda function to SNS topic
    this.notificationTopic.addSubscription(new snsSubscriptions.LambdaSubscription(remediationFunction));

    // Add tags
    cdk.Tags.of(remediationFunction).add('Environment', environment);
    cdk.Tags.of(remediationFunction).add('Purpose', 'health-monitoring');
    cdk.Tags.of(remediationFunction).add('ManagedBy', 'CDK');

    return remediationFunction;
  }

  /**
   * Creates comprehensive CloudWatch alarms for health monitoring
   */
  private createCloudWatchAlarms(prefix: string, suffix: string): void {
    // High 5XX Error Rate Alarm
    const high5xxAlarm = new cloudwatch.Alarm(this, 'High5XXErrorAlarm', {
      alarmName: `VPCLattice-${prefix}-service-${suffix}-High5XXRate`,
      alarmDescription: 'High 5XX error rate detected in VPC Lattice service',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VpcLattice',
        metricName: 'HTTPCode_5XX_Count',
        dimensionsMap: {
          Service: this.service.attrId
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Request Timeout Alarm
    const timeoutAlarm = new cloudwatch.Alarm(this, 'RequestTimeoutAlarm', {
      alarmName: `VPCLattice-${prefix}-service-${suffix}-RequestTimeouts`,
      alarmDescription: 'High request timeout rate detected in VPC Lattice service',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VpcLattice',
        metricName: 'RequestTimeoutCount',
        dimensionsMap: {
          Service: this.service.attrId
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // High Response Time Alarm
    const responseTimeAlarm = new cloudwatch.Alarm(this, 'HighResponseTimeAlarm', {
      alarmName: `VPCLattice-${prefix}-service-${suffix}-HighResponseTime`,
      alarmDescription: 'High response time detected in VPC Lattice service',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VpcLattice',
        metricName: 'RequestTime',
        dimensionsMap: {
          Service: this.service.attrId
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 2000, // 2 seconds in milliseconds
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add alarm actions for SNS notifications
    const snsAction = new cloudwatchActions.SnsAction(this.notificationTopic);
    
    high5xxAlarm.addAlarmAction(snsAction);
    high5xxAlarm.addOkAction(snsAction);
    
    timeoutAlarm.addAlarmAction(snsAction);
    timeoutAlarm.addOkAction(snsAction);
    
    responseTimeAlarm.addAlarmAction(snsAction);

    // Add tags to alarms
    const alarms = [high5xxAlarm, timeoutAlarm, responseTimeAlarm];
    alarms.forEach(alarm => {
      cdk.Tags.of(alarm).add('Environment', 'demo');
      cdk.Tags.of(alarm).add('Purpose', 'health-monitoring');
      cdk.Tags.of(alarm).add('ManagedBy', 'CDK');
    });
  }

  /**
   * Creates a comprehensive CloudWatch dashboard for operational visibility
   */
  private createCloudWatchDashboard(prefix: string, suffix: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'HealthMonitoringDashboard', {
      dashboardName: `VPCLattice-Health-${suffix}`,
      defaultInterval: cdk.Duration.hours(1)
    });

    // HTTP Response Codes Widget
    const responseCodesWidget = new cloudwatch.GraphWidget({
      title: 'HTTP Response Codes',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'HTTPCode_2XX_Count',
          dimensionsMap: { Service: this.service.attrId },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          label: '2XX Success'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'HTTPCode_4XX_Count',
          dimensionsMap: { Service: this.service.attrId },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          label: '4XX Client Errors'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'HTTPCode_5XX_Count',
          dimensionsMap: { Service: this.service.attrId },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          label: '5XX Server Errors'
        })
      ]
    });

    // Request Response Time Widget
    const responseTimeWidget = new cloudwatch.GraphWidget({
      title: 'Request Response Time',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'RequestTime',
          dimensionsMap: { Service: this.service.attrId },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
          label: 'Average Response Time (ms)'
        })
      ],
      yAxis: {
        label: 'Response Time (ms)',
        showUnits: true
      }
    });

    // Request Volume and Timeouts Widget
    const volumeTimeoutsWidget = new cloudwatch.GraphWidget({
      title: 'Request Volume and Timeouts',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'TotalRequestCount',
          dimensionsMap: { Service: this.service.attrId },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          label: 'Total Requests'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'RequestTimeoutCount',
          dimensionsMap: { Service: this.service.attrId },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          label: 'Request Timeouts'
        })
      ]
    });

    // Target Health Widget
    const targetHealthWidget = new cloudwatch.GraphWidget({
      title: 'Target Health',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'HealthyTargetCount',
          dimensionsMap: { TargetGroup: this.targetGroup.attrId },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
          label: 'Healthy Targets'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'UnhealthyTargetCount',
          dimensionsMap: { TargetGroup: this.targetGroup.attrId },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
          label: 'Unhealthy Targets'
        })
      ]
    });

    // Add widgets to dashboard
    dashboard.addWidgets(responseCodesWidget, responseTimeWidget);
    dashboard.addWidgets(volumeTimeoutsWidget, targetHealthWidget);

    // Add tags
    cdk.Tags.of(dashboard).add('Environment', 'demo');
    cdk.Tags.of(dashboard).add('Purpose', 'health-monitoring');
    cdk.Tags.of(dashboard).add('ManagedBy', 'CDK');

    return dashboard;
  }

  /**
   * Add CloudFormation outputs for key resources
   */
  private addOutputs(suffix: string): void {
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `health-monitor-service-network-${suffix}`
    });

    new cdk.CfnOutput(this, 'ServiceId', {
      value: this.service.attrId,
      description: 'VPC Lattice Service ID',
      exportName: `health-monitor-service-${suffix}`
    });

    new cdk.CfnOutput(this, 'TargetGroupId', {
      value: this.targetGroup.attrId,
      description: 'VPC Lattice Target Group ID',
      exportName: `health-monitor-target-group-${suffix}`
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS Topic ARN for health notifications',
      exportName: `health-monitor-topic-arn-${suffix}`
    });

    new cdk.CfnOutput(this, 'RemediationFunctionName', {
      value: this.remediationFunction.functionName,
      description: 'Lambda function name for auto-remediation',
      exportName: `health-monitor-function-${suffix}`
    });

    new cdk.CfnOutput(this, 'DashboardName', {
      value: this.dashboard.dashboardName,
      description: 'CloudWatch Dashboard name for health monitoring',
      exportName: `health-monitor-dashboard-${suffix}`
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for health monitoring'
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const vpcId = app.node.tryGetContext('vpcId') || process.env.VPC_ID;
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const environmentName = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'demo';

// Create the stack
new ApplicationHealthMonitoringStack(app, 'ApplicationHealthMonitoringStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Application Health Monitoring with VPC Lattice and CloudWatch - CDK TypeScript Implementation',
  vpcId,
  notificationEmail,
  environmentName,
  tags: {
    Project: 'application-health-monitoring-lattice-cloudwatch',
    ManagedBy: 'CDK',
    Environment: environmentName
  }
});

app.synth();