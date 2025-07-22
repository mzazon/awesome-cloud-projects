#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the AutomatedPatchingStack
 */
export interface AutomatedPatchingStackProps extends cdk.StackProps {
  /**
   * Email address to receive patch notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Patch group name for organizing instances
   * @default 'Production'
   */
  readonly patchGroupName?: string;
  
  /**
   * Schedule for maintenance window (cron expression)
   * @default 'cron(0 2 ? * SUN *)' - 2 AM UTC every Sunday
   */
  readonly maintenanceSchedule?: string;
  
  /**
   * Schedule for patch scanning (cron expression)
   * @default 'cron(0 1 * * ? *)' - 1 AM UTC daily
   */
  readonly scanSchedule?: string;
  
  /**
   * Maximum percentage of instances to patch concurrently
   * @default '50%'
   */
  readonly maxConcurrency?: string;
  
  /**
   * Maximum percentage of failed patches allowed
   * @default '10%'
   */
  readonly maxErrors?: string;
  
  /**
   * Number of days to wait before auto-approving patches
   * @default 7
   */
  readonly patchApprovalDelay?: number;
  
  /**
   * Maintenance window duration in hours
   * @default 4
   */
  readonly maintenanceWindowDuration?: number;
  
  /**
   * Maintenance window cutoff time in hours
   * @default 1
   */
  readonly maintenanceWindowCutoff?: number;
}

/**
 * AWS CDK Stack for Automated Patching and Maintenance Windows with Systems Manager
 * 
 * This stack creates:
 * - Custom patch baseline with security and critical patches
 * - Maintenance windows for patching and scanning
 * - IAM roles with least privilege permissions
 * - S3 bucket for patch logs and reports
 * - SNS topic for notifications
 * - CloudWatch alarms for monitoring patch compliance
 * - Automated patch group associations
 */
export class AutomatedPatchingStack extends cdk.Stack {
  public readonly patchBaseline: ssm.CfnPatchBaseline;
  public readonly maintenanceWindow: ssm.CfnMaintenanceWindow;
  public readonly scanWindow: ssm.CfnMaintenanceWindow;
  public readonly patchReportsBucket: s3.Bucket;
  public readonly notificationTopic: sns.Topic;
  public readonly maintenanceWindowRole: iam.Role;

  constructor(scope: Construct, id: string, props: AutomatedPatchingStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const patchGroupName = props.patchGroupName || 'Production';
    const maintenanceSchedule = props.maintenanceSchedule || 'cron(0 2 ? * SUN *)';
    const scanSchedule = props.scanSchedule || 'cron(0 1 * * ? *)';
    const maxConcurrency = props.maxConcurrency || '50%';
    const maxErrors = props.maxErrors || '10%';
    const patchApprovalDelay = props.patchApprovalDelay || 7;
    const maintenanceWindowDuration = props.maintenanceWindowDuration || 4;
    const maintenanceWindowCutoff = props.maintenanceWindowCutoff || 1;

    // Create S3 bucket for patch reports and logs
    this.patchReportsBucket = new s3.Bucket(this, 'PatchReportsBucket', {
      bucketName: `patch-reports-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: cdk.Duration.days(90),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    // Create SNS topic for patch notifications
    this.notificationTopic = new sns.Topic(this, 'PatchNotificationTopic', {
      topicName: `patch-notifications-${cdk.Aws.REGION}`,
      displayName: 'Patch Management Notifications',
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create CloudWatch log group for patch operations
    const patchLogGroup = new logs.LogGroup(this, 'PatchLogGroup', {
      logGroupName: '/aws/systems-manager/patch-operations',
      retention: logs.RetentionDays.THREE_MONTHS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create custom patch baseline for Amazon Linux 2
    this.patchBaseline = new ssm.CfnPatchBaseline(this, 'CustomPatchBaseline', {
      name: `custom-patch-baseline-${cdk.Aws.REGION}`,
      description: 'Custom patch baseline for production instances with security and critical patches',
      operatingSystem: 'AMAZON_LINUX_2',
      
      // Define approval rules for automatic patch approval
      approvalRules: {
        patchRules: [
          {
            patchFilterGroup: {
              patchFilters: [
                {
                  key: 'CLASSIFICATION',
                  values: ['Security', 'Bugfix', 'Critical'],
                },
              ],
            },
            approveAfterDays: patchApprovalDelay,
            complianceLevel: 'CRITICAL',
            enableNonSecurity: false,
          },
        ],
      },
      
      // Set compliance level for approved patches
      approvedPatchesComplianceLevel: 'CRITICAL',
      
      // Global filters to include only specific patch types
      globalFilters: {
        patchFilters: [
          {
            key: 'PRODUCT',
            values: ['AmazonLinux2'],
          },
        ],
      },
      
      // Patches to explicitly reject (example: kernel patches that require reboot)
      rejectedPatchesAction: 'BLOCK',
      
      // Add tags for resource management
      tags: [
        {
          key: 'Environment',
          value: patchGroupName,
        },
        {
          key: 'Purpose',
          value: 'AutomatedPatching',
        },
      ],
    });

    // Create IAM role for maintenance window operations
    this.maintenanceWindowRole = new iam.Role(this, 'MaintenanceWindowRole', {
      roleName: `MaintenanceWindowRole-${cdk.Aws.REGION}`,
      assumedBy: new iam.ServicePrincipal('ssm.amazonaws.com'),
      description: 'IAM role for Systems Manager maintenance window operations',
      
      // Attach AWS managed policy for maintenance window operations
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonSSMMaintenanceWindowRole'),
      ],
      
      // Add inline policy for additional permissions
      inlinePolicies: {
        MaintenanceWindowPolicy: new iam.PolicyDocument({
          statements: [
            // Allow writing to S3 bucket for logs
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:DeleteObject',
              ],
              resources: [
                this.patchReportsBucket.bucketArn,
                `${this.patchReportsBucket.bucketArn}/*`,
              ],
            }),
            
            // Allow CloudWatch Logs operations
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogStreams',
              ],
              resources: [
                patchLogGroup.logGroupArn,
                `${patchLogGroup.logGroupArn}:*`,
              ],
            }),
            
            // Allow SNS notifications
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
              ],
              resources: [
                this.notificationTopic.topicArn,
              ],
            }),
          ],
        }),
      },
    });

    // Create maintenance window for weekly patching
    this.maintenanceWindow = new ssm.CfnMaintenanceWindow(this, 'PatchMaintenanceWindow', {
      name: `patch-maintenance-window-${cdk.Aws.REGION}`,
      description: 'Weekly maintenance window for automated patching',
      schedule: maintenanceSchedule,
      scheduleTimezone: 'UTC',
      duration: maintenanceWindowDuration,
      cutoff: maintenanceWindowCutoff,
      allowUnassociatedTargets: true,
      
      // Add tags
      tags: [
        {
          key: 'Purpose',
          value: 'AutomatedPatching',
        },
        {
          key: 'Schedule',
          value: 'Weekly',
        },
      ],
    });

    // Create maintenance window for daily patch scanning
    this.scanWindow = new ssm.CfnMaintenanceWindow(this, 'ScanMaintenanceWindow', {
      name: `scan-maintenance-window-${cdk.Aws.REGION}`,
      description: 'Daily maintenance window for patch scanning',
      schedule: scanSchedule,
      scheduleTimezone: 'UTC',
      duration: 2,
      cutoff: 1,
      allowUnassociatedTargets: true,
      
      // Add tags
      tags: [
        {
          key: 'Purpose',
          value: 'PatchScanning',
        },
        {
          key: 'Schedule',
          value: 'Daily',
        },
      ],
    });

    // Register targets for patch maintenance window (Production instances)
    const patchTargets = new ssm.CfnMaintenanceWindowTarget(this, 'PatchMaintenanceWindowTargets', {
      windowId: this.maintenanceWindow.ref,
      resourceType: 'INSTANCE',
      name: 'ProductionInstances',
      description: 'Production instances tagged for patching',
      
      // Target instances with Environment=Production tag
      targets: [
        {
          key: 'tag:Environment',
          values: [patchGroupName],
        },
      ],
    });

    // Register targets for scan maintenance window
    const scanTargets = new ssm.CfnMaintenanceWindowTarget(this, 'ScanMaintenanceWindowTargets', {
      windowId: this.scanWindow.ref,
      resourceType: 'INSTANCE',
      name: 'ScanTargets',
      description: 'Instances for patch scanning',
      
      // Target instances with Environment=Production tag
      targets: [
        {
          key: 'tag:Environment',
          values: [patchGroupName],
        },
      ],
    });

    // Register patching task with maintenance window
    const patchTask = new ssm.CfnMaintenanceWindowTask(this, 'PatchingTask', {
      windowId: this.maintenanceWindow.ref,
      taskType: 'RUN_COMMAND',
      taskArn: 'AWS-RunPatchBaseline',
      serviceRoleArn: this.maintenanceWindowRole.roleArn,
      name: 'PatchingTask',
      description: 'Install patches using custom baseline',
      maxConcurrency: maxConcurrency,
      maxErrors: maxErrors,
      priority: 1,
      
      // Target the registered instances
      targets: [
        {
          key: 'WindowTargetIds',
          values: [patchTargets.ref],
        },
      ],
      
      // Task parameters for patch installation
      taskParameters: {
        BaselineOverride: [this.patchBaseline.ref],
        Operation: ['Install'],
        RebootOption: ['RebootIfNeeded'],
      },
      
      // Configure logging to S3
      loggingInfo: {
        s3Bucket: this.patchReportsBucket.bucketName,
        s3KeyPrefix: 'patch-logs',
        s3Region: cdk.Aws.REGION,
      },
    });

    // Register scanning task with scan maintenance window
    const scanTask = new ssm.CfnMaintenanceWindowTask(this, 'ScanningTask', {
      windowId: this.scanWindow.ref,
      taskType: 'RUN_COMMAND',
      taskArn: 'AWS-RunPatchBaseline',
      serviceRoleArn: this.maintenanceWindowRole.roleArn,
      name: 'ScanningTask',
      description: 'Scan for missing patches',
      maxConcurrency: '100%',
      maxErrors: '5%',
      priority: 1,
      
      // Target the registered instances
      targets: [
        {
          key: 'WindowTargetIds',
          values: [scanTargets.ref],
        },
      ],
      
      // Task parameters for patch scanning
      taskParameters: {
        BaselineOverride: [this.patchBaseline.ref],
        Operation: ['Scan'],
      },
      
      // Configure logging to S3
      loggingInfo: {
        s3Bucket: this.patchReportsBucket.bucketName,
        s3KeyPrefix: 'scan-logs',
        s3Region: cdk.Aws.REGION,
      },
    });

    // Register patch baseline with patch group
    const patchGroupAssociation = new ssm.CfnPatchBaselineAssociation(this, 'PatchGroupAssociation', {
      baselineId: this.patchBaseline.ref,
      patchGroup: patchGroupName,
    });

    // Create CloudWatch alarm for patch compliance monitoring
    const patchComplianceAlarm = new cloudwatch.Alarm(this, 'PatchComplianceAlarm', {
      alarmName: `PatchComplianceAlarm-${cdk.Aws.REGION}`,
      alarmDescription: 'Monitor patch compliance status across instances',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SSM-PatchCompliance',
        metricName: 'ComplianceByPatchGroup',
        dimensionsMap: {
          PatchGroup: patchGroupName,
        },
        statistic: 'Maximum',
        period: cdk.Duration.hours(1),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    // Add SNS action to the alarm
    patchComplianceAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.notificationTopic)
    );

    // Create additional CloudWatch alarm for maintenance window execution failures
    const maintenanceWindowAlarm = new cloudwatch.Alarm(this, 'MaintenanceWindowFailureAlarm', {
      alarmName: `MaintenanceWindowFailures-${cdk.Aws.REGION}`,
      alarmDescription: 'Monitor maintenance window execution failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SSM',
        metricName: 'MaintenanceWindowExecutionFailures',
        dimensionsMap: {
          MaintenanceWindowId: this.maintenanceWindow.ref,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to the maintenance window alarm
    maintenanceWindowAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.notificationTopic)
    );

    // Add dependencies to ensure resources are created in correct order
    patchTask.addDependency(patchTargets);
    scanTask.addDependency(scanTargets);
    patchGroupAssociation.addDependency(this.patchBaseline);

    // Output important resource information
    new cdk.CfnOutput(this, 'PatchBaselineId', {
      value: this.patchBaseline.ref,
      description: 'ID of the custom patch baseline',
      exportName: `${this.stackName}-PatchBaselineId`,
    });

    new cdk.CfnOutput(this, 'MaintenanceWindowId', {
      value: this.maintenanceWindow.ref,
      description: 'ID of the patch maintenance window',
      exportName: `${this.stackName}-MaintenanceWindowId`,
    });

    new cdk.CfnOutput(this, 'ScanWindowId', {
      value: this.scanWindow.ref,
      description: 'ID of the scan maintenance window',
      exportName: `${this.stackName}-ScanWindowId`,
    });

    new cdk.CfnOutput(this, 'PatchReportsBucketName', {
      value: this.patchReportsBucket.bucketName,
      description: 'S3 bucket name for patch reports and logs',
      exportName: `${this.stackName}-PatchReportsBucket`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS topic ARN for patch notifications',
      exportName: `${this.stackName}-NotificationTopicArn`,
    });

    new cdk.CfnOutput(this, 'MaintenanceWindowRoleArn', {
      value: this.maintenanceWindowRole.roleArn,
      description: 'IAM role ARN for maintenance window operations',
      exportName: `${this.stackName}-MaintenanceWindowRoleArn`,
    });

    new cdk.CfnOutput(this, 'PatchGroupName', {
      value: patchGroupName,
      description: 'Name of the patch group for instance organization',
      exportName: `${this.stackName}-PatchGroupName`,
    });

    new cdk.CfnOutput(this, 'MaintenanceSchedule', {
      value: maintenanceSchedule,
      description: 'Cron expression for maintenance window schedule',
      exportName: `${this.stackName}-MaintenanceSchedule`,
    });
  }
}

// Create the CDK app and instantiate the stack
const app = new cdk.App();

// Get context values or use defaults
const notificationEmail = app.node.tryGetContext('notificationEmail');
const patchGroupName = app.node.tryGetContext('patchGroupName') || 'Production';
const maintenanceSchedule = app.node.tryGetContext('maintenanceSchedule') || 'cron(0 2 ? * SUN *)';

// Create the stack with configuration
new AutomatedPatchingStack(app, 'AutomatedPatchingStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Automated patching and maintenance windows with AWS Systems Manager',
  notificationEmail,
  patchGroupName,
  maintenanceSchedule,
  
  // Add stack tags
  tags: {
    Project: 'AutomatedPatching',
    Environment: patchGroupName,
    ManagedBy: 'CDK',
  },
});

app.synth();