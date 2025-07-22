#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

/**
 * Stack for Proactive Application Resilience Monitoring with AWS Resilience Hub and EventBridge
 * 
 * This stack creates:
 * - Sample application infrastructure (EC2, RDS)
 * - EventBridge rules for Resilience Hub events
 * - Lambda function for event processing
 * - CloudWatch dashboard and alarms
 * - SNS topic for notifications
 */
export class ProactiveResilienceMonitoringStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly demoInstance: ec2.Instance;
  public readonly demoDatabase: rds.DatabaseInstance;
  public readonly eventProcessorFunction: lambda.Function;
  public readonly resilienceEventRule: events.Rule;
  public readonly alertTopic: sns.Topic;
  public readonly resilienceDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();
    
    // Create VPC with public and private subnets across multiple AZs
    this.vpc = new ec2.Vpc(this, 'ResilienceDemoVpc', {
      cidr: '10.0.0.0/16',
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create security group for application resources
    const appSecurityGroup = new ec2.SecurityGroup(this, 'AppSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for resilience demo application',
      allowAllOutbound: true,
    });

    // Allow MySQL/Aurora access within security group
    appSecurityGroup.addIngressRule(
      appSecurityGroup,
      ec2.Port.tcp(3306),
      'MySQL/Aurora access within application'
    );

    // Create IAM role for automation tasks
    const automationRole = new iam.Role(this, 'ResilienceAutomationRole', {
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('ssm.amazonaws.com'),
        new iam.ServicePrincipal('lambda.amazonaws.com')
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMAutomationRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
      inlinePolicies: {
        ResilienceMonitoringPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'sns:Publish',
                'ssm:StartAutomationExecution',
                'resiliencehub:*',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create demo EC2 instance with Systems Manager agent
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      'yum update -y',
      'yum install -y amazon-cloudwatch-agent',
      'systemctl enable amazon-ssm-agent',
      'systemctl start amazon-ssm-agent'
    );

    this.demoInstance = new ec2.Instance(this, 'ResilienceDemoInstance', {
      vpc: this.vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.latestAmazonLinux(),
      securityGroup: appSecurityGroup,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      userData,
      role: new iam.Role(this, 'InstanceRole', {
        assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
          iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        ],
      }),
    });

    // Tag the instance for resilience monitoring
    cdk.Tags.of(this.demoInstance).add('Environment', 'demo');
    cdk.Tags.of(this.demoInstance).add('Purpose', 'resilience-testing');

    // Create RDS subnet group
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc: this.vpc,
      description: 'Subnet group for resilience demo database',
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
    });

    // Create RDS instance with Multi-AZ deployment
    this.demoDatabase = new rds.DatabaseInstance(this, 'ResilienceDemoDatabase', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      credentials: rds.Credentials.fromGeneratedSecret('admin', {
        secretName: `resilience-demo-db-secret-${uniqueSuffix}`,
      }),
      vpc: this.vpc,
      subnetGroup: dbSubnetGroup,
      securityGroups: [appSecurityGroup],
      allocatedStorage: 20,
      storageEncrypted: true,
      multiAz: true, // Enable Multi-AZ for high availability
      autoMinorVersionUpgrade: true,
      backupRetention: cdk.Duration.days(7),
      deletionProtection: false, // Allow deletion for demo purposes
      databaseName: 'resiliencedb',
      deleteAutomatedBackups: true,
    });

    // Tag the database for resilience monitoring
    cdk.Tags.of(this.demoDatabase).add('Environment', 'demo');
    cdk.Tags.of(this.demoDatabase).add('Purpose', 'resilience-testing');

    // Create SNS topic for resilience alerts
    this.alertTopic = new sns.Topic(this, 'ResilienceAlerts', {
      displayName: 'Resilience Monitoring Alerts',
      topicName: `resilience-alerts-${uniqueSuffix}`,
    });

    // Create Lambda function for processing resilience events
    this.eventProcessorFunction = new lambda.Function(this, 'ResilienceEventProcessor', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      role: automationRole,
      environment: {
        LOG_LEVEL: 'INFO',
        SNS_TOPIC_ARN: this.alertTopic.topicArn,
        REGION: this.region,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Process EventBridge events from AWS Resilience Hub
    """
    logger.info(f"Received resilience event: {json.dumps(event)}")
    
    ssm = boto3.client('ssm')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Parse EventBridge event
        event_detail = event.get('detail', {})
        app_name = event_detail.get('applicationName', 'unknown')
        assessment_status = event_detail.get('assessmentStatus', 'UNKNOWN')
        resilience_score = event_detail.get('resilienceScore', 0)
        
        # Log resilience metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='ResilienceHub/Monitoring',
            MetricData=[
                {
                    'MetricName': 'ResilienceScore',
                    'Dimensions': [
                        {
                            'Name': 'ApplicationName',
                            'Value': app_name
                        }
                    ],
                    'Value': resilience_score,
                    'Unit': 'Percent',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'AssessmentEvents',
                    'Dimensions': [
                        {
                            'Name': 'ApplicationName',
                            'Value': app_name
                        },
                        {
                            'Name': 'Status',
                            'Value': assessment_status
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        # Trigger remediation if score below threshold
        if resilience_score < 80:
            logger.info(f"Resilience score {resilience_score}% below threshold, triggering remediation")
            
            # Create detailed alert message
            message = {
                'application': app_name,
                'resilience_score': resilience_score,
                'status': assessment_status,
                'timestamp': datetime.utcnow().isoformat(),
                'action': 'remediation_required',
                'details': 'Automated resilience monitoring detected score below threshold'
            }
            
            # Send SNS notification
            sns.publish(
                TopicArn=os.getenv('SNS_TOPIC_ARN'),
                Subject=f'Resilience Alert: {app_name} Score Below Threshold',
                Message=json.dumps(message, indent=2)
            )
            
            logger.info("SNS notification sent for low resilience score")
        else:
            logger.info(f"Resilience score {resilience_score}% above threshold, no action required")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'application': app_name,
                'resilience_score': resilience_score,
                'assessment_status': assessment_status
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        
        # Log error metric
        cloudwatch.put_metric_data(
            Namespace='ResilienceHub/Monitoring',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        raise e
      `),
    });

    // Create CloudWatch Log Group for Lambda function
    new logs.LogGroup(this, 'EventProcessorLogs', {
      logGroupName: `/aws/lambda/${this.eventProcessorFunction.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create EventBridge rule for Resilience Hub events
    this.resilienceEventRule = new events.Rule(this, 'ResilienceHubEventRule', {
      ruleName: `ResilienceHubAssessmentRule-${uniqueSuffix}`,
      description: 'Comprehensive rule for Resilience Hub assessment events',
      enabled: true,
      eventPattern: {
        source: ['aws.resiliencehub'],
        detailType: [
          'Resilience Assessment State Change',
          'Application Assessment Completed',
          'Policy Compliance Change',
        ],
        detail: {
          state: [
            'ASSESSMENT_COMPLETED',
            'ASSESSMENT_FAILED',
            'ASSESSMENT_IN_PROGRESS',
          ],
        },
      },
    });

    // Add Lambda function as target with input transformation
    this.resilienceEventRule.addTarget(
      new targets.LambdaFunction(this.eventProcessorFunction, {
        event: events.RuleTargetInput.fromObject({
          applicationName: events.EventField.fromPath('$.detail.applicationName'),
          assessmentStatus: events.EventField.fromPath('$.detail.state'),
          resilienceScore: events.EventField.fromPath('$.detail.resilienceScore'),
          source: events.EventField.fromPath('$.source'),
          timestamp: events.EventField.fromPath('$.time'),
        }),
      })
    );

    // Create CloudWatch Dashboard for resilience monitoring
    this.resilienceDashboard = new cloudwatch.Dashboard(this, 'ResilienceDashboard', {
      dashboardName: `Application-Resilience-Monitoring-${uniqueSuffix}`,
      widgets: [
        [
          // Resilience Score Trend
          new cloudwatch.GraphWidget({
            title: 'Application Resilience Score Trend',
            left: [
              new cloudwatch.Metric({
                namespace: 'ResilienceHub/Monitoring',
                metricName: 'ResilienceScore',
                dimensionsMap: {
                  ApplicationName: `resilience-demo-app-${uniqueSuffix}`,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            leftYAxis: {
              min: 0,
              max: 100,
            },
            leftAnnotations: [
              {
                value: 80,
                label: 'Critical Threshold',
                color: cloudwatch.Color.RED,
              },
            ],
            width: 12,
            height: 6,
          }),

          // Assessment Events
          new cloudwatch.GraphWidget({
            title: 'Assessment Events and Processing Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'ResilienceHub/Monitoring',
                metricName: 'AssessmentEvents',
                dimensionsMap: {
                  ApplicationName: `resilience-demo-app-${uniqueSuffix}`,
                  Status: 'ASSESSMENT_COMPLETED',
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'ResilienceHub/Monitoring',
                metricName: 'AssessmentEvents',
                dimensionsMap: {
                  ApplicationName: `resilience-demo-app-${uniqueSuffix}`,
                  Status: 'ASSESSMENT_FAILED',
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'ResilienceHub/Monitoring',
                metricName: 'ProcessingErrors',
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          // Lambda Function Metrics
          new cloudwatch.GraphWidget({
            title: 'Event Processing Lambda Metrics',
            left: [
              this.eventProcessorFunction.metricInvocations({
                period: cdk.Duration.minutes(5),
              }),
              this.eventProcessorFunction.metricErrors({
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              this.eventProcessorFunction.metricDuration({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 24,
            height: 6,
          }),
        ],
      ],
    });

    // Create CloudWatch Alarms for proactive monitoring
    const criticalLowResilienceAlarm = new cloudwatch.Alarm(this, 'CriticalLowResilienceAlarm', {
      alarmName: `Critical-Low-Resilience-Score-${uniqueSuffix}`,
      alarmDescription: 'Critical alert when resilience score drops below 70%',
      metric: new cloudwatch.Metric({
        namespace: 'ResilienceHub/Monitoring',
        metricName: 'ResilienceScore',
        dimensionsMap: {
          ApplicationName: `resilience-demo-app-${uniqueSuffix}`,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 70,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 1,
      datapointsToAlarm: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const warningLowResilienceAlarm = new cloudwatch.Alarm(this, 'WarningLowResilienceAlarm', {
      alarmName: `Warning-Low-Resilience-Score-${uniqueSuffix}`,
      alarmDescription: 'Warning when resilience score drops below 80%',
      metric: new cloudwatch.Metric({
        namespace: 'ResilienceHub/Monitoring',
        metricName: 'ResilienceScore',
        dimensionsMap: {
          ApplicationName: `resilience-demo-app-${uniqueSuffix}`,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      datapointsToAlarm: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const assessmentFailureAlarm = new cloudwatch.Alarm(this, 'AssessmentFailureAlarm', {
      alarmName: `Resilience-Assessment-Failures-${uniqueSuffix}`,
      alarmDescription: 'Alert when resilience assessments fail repeatedly',
      metric: new cloudwatch.Metric({
        namespace: 'ResilienceHub/Monitoring',
        metricName: 'AssessmentEvents',
        dimensionsMap: {
          ApplicationName: `resilience-demo-app-${uniqueSuffix}`,
          Status: 'ASSESSMENT_FAILED',
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      datapointsToAlarm: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS topic as action for all alarms
    [criticalLowResilienceAlarm, warningLowResilienceAlarm, assessmentFailureAlarm].forEach(alarm => {
      alarm.addAlarmAction(new cloudwatch.SnsAction(this.alertTopic));
      alarm.addOkAction(new cloudwatch.SnsAction(this.alertTopic));
    });

    // Create SSM parameter for storing application configuration
    new ssm.StringParameter(this, 'AppConfigParameter', {
      parameterName: `/resilience-monitoring/${uniqueSuffix}/app-config`,
      stringValue: JSON.stringify({
        applicationName: `resilience-demo-app-${uniqueSuffix}`,
        instanceId: this.demoInstance.instanceId,
        databaseIdentifier: this.demoDatabase.instanceIdentifier,
        snsTopic: this.alertTopic.topicArn,
        lambdaFunction: this.eventProcessorFunction.functionName,
      }),
      description: 'Configuration parameters for resilience monitoring application',
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the resilience demo application',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'InstanceId', {
      value: this.demoInstance.instanceId,
      description: 'EC2 Instance ID for resilience monitoring',
      exportName: `${this.stackName}-InstanceId`,
    });

    new cdk.CfnOutput(this, 'DatabaseIdentifier', {
      value: this.demoDatabase.instanceIdentifier,
      description: 'RDS Database Identifier for resilience monitoring',
      exportName: `${this.stackName}-DatabaseId`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.eventProcessorFunction.functionName,
      description: 'Lambda function name for processing resilience events',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: this.resilienceEventRule.ruleName,
      description: 'EventBridge rule name for resilience monitoring',
      exportName: `${this.stackName}-EventRule`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS Topic ARN for resilience alerts',
      exportName: `${this.stackName}-SNSTopic`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.resilienceDashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for resilience monitoring',
    });

    new cdk.CfnOutput(this, 'ResilienceHubConsoleURL', {
      value: `https://${this.region}.console.aws.amazon.com/resiliencehub/home?region=${this.region}#/applications`,
      description: 'AWS Resilience Hub Console URL for application management',
    });

    new cdk.CfnOutput(this, 'ApplicationName', {
      value: `resilience-demo-app-${uniqueSuffix}`,
      description: 'Application name for use with Resilience Hub registration',
      exportName: `${this.stackName}-AppName`,
    });
  }
}

// CDK App
const app = new cdk.App();

// Create the stack with recommended configuration
new ProactiveResilienceMonitoringStack(app, 'ProactiveResilienceMonitoringStack', {
  description: 'Proactive Application Resilience Monitoring with AWS Resilience Hub and EventBridge',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ResilienceMonitoring',
    Environment: 'Demo',
    ManagedBy: 'CDK',
    Purpose: 'ProactiveResilienceMonitoring',
  },
});

app.synth();