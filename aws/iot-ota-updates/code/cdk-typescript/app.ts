#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

/**
 * Stack for IoT Fleet Management and Over-the-Air Updates
 * This stack creates the infrastructure needed for managing IoT device fleets
 * and deploying firmware updates using AWS IoT Device Management and IoT Jobs
 */
export class IoTFleetManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // S3 bucket for storing firmware updates
    const firmwareBucket = new s3.Bucket(this, 'FirmwareBucket', {
      bucketName: `iot-firmware-updates-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldFirmwareVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
          expiration: cdk.Duration.days(90),
        },
      ],
    });

    // IAM role for IoT devices to access S3 bucket and IoT Jobs
    const deviceRole = new iam.Role(this, 'IoTDeviceRole', {
      roleName: `IoTDeviceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      description: 'Role for IoT devices to access firmware updates and report job status',
    });

    // Policy for S3 access to download firmware
    const s3AccessPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:GetObjectVersion',
      ],
      resources: [
        firmwareBucket.bucketArn,
        `${firmwareBucket.bucketArn}/*`,
      ],
    });

    // Policy for IoT Jobs access
    const jobsAccessPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'iot:UpdateJobExecution',
        'iot:GetJobDocument',
        'iot:DescribeJobExecution',
      ],
      resources: [
        `arn:aws:iot:${this.region}:${this.account}:job/*`,
      ],
    });

    // Policy for CloudWatch Logs
    const logsPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: [
        `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/iot/*`,
      ],
    });

    deviceRole.addToPolicy(s3AccessPolicy);
    deviceRole.addToPolicy(jobsAccessPolicy);
    deviceRole.addToPolicy(logsPolicy);

    // IoT policy for device authentication and authorization
    const iotPolicy = new iot.CfnPolicy(this, 'IoTDevicePolicy', {
      policyName: `IoTDevicePolicy-${uniqueSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: ['iot:Connect'],
            Resource: `arn:aws:iot:${this.region}:${this.account}:client/\${iot:Connection.Thing.ThingName}`,
          },
          {
            Effect: 'Allow',
            Action: [
              'iot:Publish',
              'iot:Subscribe',
              'iot:Receive',
            ],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:topic/$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*`,
              `arn:aws:iot:${this.region}:${this.account}:topicfilter/$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*`,
            ],
          },
          {
            Effect: 'Allow',
            Action: [
              'iot:Publish',
            ],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:topic/fleet/telemetry/\${iot:Connection.Thing.ThingName}`,
              `arn:aws:iot:${this.region}:${this.account}:topic/fleet/status/\${iot:Connection.Thing.ThingName}`,
            ],
          },
        ],
      },
    });

    // Thing Group for fleet organization
    const thingGroup = new iot.CfnThingGroup(this, 'ProductionDevicesGroup', {
      thingGroupName: `ProductionDevices-${uniqueSuffix}`,
      thingGroupProperties: {
        thingGroupDescription: 'Production IoT devices for OTA updates',
        attributePayload: {
          attributes: {
            environment: 'production',
            updatePolicy: 'automatic',
            firmwareVersion: 'v2.0.0',
            deviceType: 'sensor',
          },
        },
      },
    });

    // Create sample IoT things (devices) for demonstration
    const deviceNames: string[] = [];
    for (let i = 1; i <= 3; i++) {
      const deviceName = `IoTDevice-${uniqueSuffix}-${i}`;
      deviceNames.push(deviceName);

      const thing = new iot.CfnThing(this, `IoTDevice${i}`, {
        thingName: deviceName,
        attributePayload: {
          attributes: {
            deviceType: 'sensor',
            firmwareVersion: 'v2.0.0',
            location: `factory-floor-${i}`,
            serialNumber: `SN-${uniqueSuffix}-${i}`,
          },
        },
      });

      // Add device to thing group
      new iot.CfnThingGroupInfo(this, `DeviceGroupInfo${i}`, {
        thingGroupName: thingGroup.thingGroupName!,
        thingName: thing.thingName!,
      });
    }

    // CloudWatch Log Group for IoT Jobs
    const jobsLogGroup = new logs.LogGroup(this, 'IoTJobsLogGroup', {
      logGroupName: `/aws/iot/jobs/${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // CloudWatch Log Group for device telemetry
    const telemetryLogGroup = new logs.LogGroup(this, 'IoTTelemetryLogGroup', {
      logGroupName: `/aws/iot/telemetry/${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IoT Rule for logging device telemetry
    const telemetryRule = new iot.CfnTopicRule(this, 'TelemetryRule', {
      ruleName: `TelemetryRule_${uniqueSuffix}`,
      topicRulePayload: {
        sql: `SELECT * FROM 'fleet/telemetry/+' WHERE timestamp > 0`,
        description: 'Log device telemetry to CloudWatch',
        actions: [
          {
            cloudwatchLogs: {
              logGroupName: telemetryLogGroup.logGroupName,
              roleArn: deviceRole.roleArn,
            },
          },
        ],
        ruleDisabled: false,
      },
    });

    // IoT Rule for logging job status updates
    const jobStatusRule = new iot.CfnTopicRule(this, 'JobStatusRule', {
      ruleName: `JobStatusRule_${uniqueSuffix}`,
      topicRulePayload: {
        sql: `SELECT * FROM '$aws/events/job/+/jobExecution/+' WHERE eventType = 'JOB_EXECUTION'`,
        description: 'Log job execution status to CloudWatch',
        actions: [
          {
            cloudwatchLogs: {
              logGroupName: jobsLogGroup.logGroupName,
              roleArn: deviceRole.roleArn,
            },
          },
        ],
        ruleDisabled: false,
      },
    });

    // CloudWatch Dashboard for monitoring fleet health
    const dashboard = new cloudwatch.Dashboard(this, 'IoTFleetDashboard', {
      dashboardName: `IoT-Fleet-Dashboard-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.TextWidget({
            markdown: '# IoT Fleet Management Dashboard\\n\\nMonitor your IoT device fleet health and firmware update progress.',
            width: 24,
            height: 2,
          }),
        ],
        [
          new cloudwatch.LogQueryWidget({
            title: 'Recent Job Executions',
            logGroups: [jobsLogGroup],
            query: `
              fields @timestamp, eventType, status, thingName
              | filter eventType = "JOB_EXECUTION"
              | sort @timestamp desc
              | limit 20
            `,
            width: 12,
            height: 6,
          }),
          new cloudwatch.LogQueryWidget({
            title: 'Device Telemetry',
            logGroups: [telemetryLogGroup],
            query: `
              fields @timestamp, deviceType, firmwareVersion, location
              | sort @timestamp desc
              | limit 20
            `,
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // CloudWatch Alarms for monitoring
    const jobFailureAlarm = new cloudwatch.Alarm(this, 'JobFailureAlarm', {
      alarmName: `IoT-Job-Failures-${uniqueSuffix}`,
      alarmDescription: 'Alert when IoT job failure rate exceeds threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/IoT',
        metricName: 'JobExecutionsFailed',
        dimensionsMap: {
          JobId: '*',
        },
        statistic: 'Sum',
      }),
      threshold: 3,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Outputs
    new cdk.CfnOutput(this, 'FirmwareBucketName', {
      value: firmwareBucket.bucketName,
      description: 'S3 bucket name for firmware storage',
      exportName: `FirmwareBucket-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'ThingGroupName', {
      value: thingGroup.thingGroupName!,
      description: 'IoT Thing Group name for device fleet',
      exportName: `ThingGroup-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'IoTPolicyName', {
      value: iotPolicy.policyName!,
      description: 'IoT Policy name for device authentication',
      exportName: `IoTPolicy-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DeviceRoleArn', {
      value: deviceRole.roleArn,
      description: 'IAM Role ARN for IoT devices',
      exportName: `DeviceRole-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DeviceNames', {
      value: deviceNames.join(', '),
      description: 'Created IoT device names',
      exportName: `DeviceNames-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for fleet monitoring',
    });

    new cdk.CfnOutput(this, 'JobsLogGroupName', {
      value: jobsLogGroup.logGroupName,
      description: 'CloudWatch Log Group for IoT Jobs',
      exportName: `JobsLogGroup-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'TelemetryLogGroupName', {
      value: telemetryLogGroup.logGroupName,
      description: 'CloudWatch Log Group for device telemetry',
      exportName: `TelemetryLogGroup-${uniqueSuffix}`,
    });

    // Tags for all resources
    cdk.Tags.of(this).add('Project', 'IoT Fleet Management');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Recipe', 'iot-fleet-management-ota-updates');
  }
}

// CDK App
const app = new cdk.App();

// Stack configuration
const stackProps: cdk.StackProps = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'IoT Fleet Management and Over-the-Air Updates infrastructure',
  tags: {
    Project: 'IoT Fleet Management',
    Environment: 'Production',
    ManagedBy: 'CDK',
  },
};

// Create stack
new IoTFleetManagementStack(app, 'IoTFleetManagementStack', stackProps);

// Enable termination protection in production
if (process.env.NODE_ENV === 'production') {
  app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);
}