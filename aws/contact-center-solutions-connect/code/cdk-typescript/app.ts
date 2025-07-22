#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as connect from 'aws-cdk-lib/aws-connect';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cr from 'aws-cdk-lib/custom-resources';

/**
 * Amazon Connect Contact Center Stack
 * 
 * This stack creates a complete Amazon Connect contact center solution with:
 * - Connect instance with managed identity
 * - S3 storage for call recordings and chat transcripts
 * - Admin and agent users with appropriate security profiles
 * - Customer service queue with routing configuration
 * - Contact flows for call handling and recording
 * - CloudWatch monitoring and analytics
 */
export class AmazonConnectContactCenterStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const instanceAlias = `contact-center-${uniqueSuffix}`;

    // S3 Bucket for call recordings and chat transcripts
    const recordingsBucket = new s3.Bucket(this, 'ConnectRecordingsBucket', {
      bucketName: `connect-recordings-${this.account}-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'ArchiveOldRecordings',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // IAM role for Amazon Connect to access S3
    const connectServiceRole = new iam.Role(this, 'ConnectServiceRole', {
      assumedBy: new iam.ServicePrincipal('connect.amazonaws.com'),
      description: 'Service role for Amazon Connect to access S3 bucket',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonConnect_FullAccess'),
      ],
    });

    // Grant Connect permissions to the S3 bucket
    recordingsBucket.grantReadWrite(connectServiceRole);

    // Amazon Connect Instance
    const connectInstance = new connect.CfnInstance(this, 'ConnectInstance', {
      identityManagementType: 'CONNECT_MANAGED',
      instanceAlias: instanceAlias,
      attributes: {
        inboundCalls: true,
        outboundCalls: true,
        contactflowLogs: true,
        contactLens: true,
      },
    });

    // Storage configuration for call recordings
    const callRecordingStorageConfig = new connect.CfnInstanceStorageConfig(this, 'CallRecordingStorage', {
      instanceArn: connectInstance.attrArn,
      resourceType: 'CALL_RECORDINGS',
      storageConfig: {
        s3Config: {
          bucketName: recordingsBucket.bucketName,
          bucketPrefix: 'call-recordings/',
          encryptionConfig: {
            encryptionType: 'KMS',
            keyId: 'alias/aws/s3',
          },
        },
        storageType: 'S3',
      },
    });

    // Storage configuration for chat transcripts
    const chatTranscriptStorageConfig = new connect.CfnInstanceStorageConfig(this, 'ChatTranscriptStorage', {
      instanceArn: connectInstance.attrArn,
      resourceType: 'CHAT_TRANSCRIPTS',
      storageConfig: {
        s3Config: {
          bucketName: recordingsBucket.bucketName,
          bucketPrefix: 'chat-transcripts/',
          encryptionConfig: {
            encryptionType: 'KMS',
            keyId: 'alias/aws/s3',
          },
        },
        storageType: 'S3',
      },
    });

    // Hours of Operation (24/7 for this example)
    const hoursOfOperation = new connect.CfnHoursOfOperation(this, 'HoursOfOperation', {
      instanceArn: connectInstance.attrArn,
      name: 'CustomerService24x7',
      description: '24/7 customer service hours',
      timeZone: 'UTC',
      config: [
        {
          day: 'SUNDAY',
          startTime: { hours: 0, minutes: 0 },
          endTime: { hours: 23, minutes: 59 },
        },
        {
          day: 'MONDAY',
          startTime: { hours: 0, minutes: 0 },
          endTime: { hours: 23, minutes: 59 },
        },
        {
          day: 'TUESDAY',
          startTime: { hours: 0, minutes: 0 },
          endTime: { hours: 23, minutes: 59 },
        },
        {
          day: 'WEDNESDAY',
          startTime: { hours: 0, minutes: 0 },
          endTime: { hours: 23, minutes: 59 },
        },
        {
          day: 'THURSDAY',
          startTime: { hours: 0, minutes: 0 },
          endTime: { hours: 23, minutes: 59 },
        },
        {
          day: 'FRIDAY',
          startTime: { hours: 0, minutes: 0 },
          endTime: { hours: 23, minutes: 59 },
        },
        {
          day: 'SATURDAY',
          startTime: { hours: 0, minutes: 0 },
          endTime: { hours: 23, minutes: 59 },
        },
      ],
    });

    // Customer Service Queue
    const customerServiceQueue = new connect.CfnQueue(this, 'CustomerServiceQueue', {
      instanceArn: connectInstance.attrArn,
      name: 'CustomerService',
      description: 'Main customer service queue for general inquiries',
      hoursOfOperationArn: hoursOfOperation.attrHoursOfOperationArn,
      maxContacts: 50,
      status: 'ENABLED',
      tags: [
        { key: 'Purpose', value: 'CustomerService' },
        { key: 'Environment', value: 'Production' },
      ],
    });

    // Routing Profile for Customer Service Agents
    const agentRoutingProfile = new connect.CfnRoutingProfile(this, 'AgentRoutingProfile', {
      instanceArn: connectInstance.attrArn,
      name: 'CustomerServiceAgents',
      description: 'Routing profile for customer service representatives',
      defaultOutboundQueueArn: customerServiceQueue.attrQueueArn,
      mediaConcurrencies: [
        {
          channel: 'VOICE',
          concurrency: 1,
        },
        {
          channel: 'CHAT',
          concurrency: 3,
        },
      ],
      queueConfigs: [
        {
          delay: 0,
          priority: 1,
          queueReference: {
            channel: 'VOICE',
            queueArn: customerServiceQueue.attrQueueArn,
          },
        },
      ],
    });

    // Contact Flow JSON configuration
    const contactFlowContent = {
      Version: '2019-10-30',
      StartAction: '12345678-1234-1234-1234-123456789012',
      Metadata: {
        entryPointPosition: { x: 20, y: 20 },
        snapToGrid: false,
        ActionMetadata: {
          '12345678-1234-1234-1234-123456789012': {
            position: { x: 178, y: 52 },
          },
          '87654321-4321-4321-4321-210987654321': {
            position: { x: 392, y: 154 },
          },
          '11111111-2222-3333-4444-555555555555': {
            position: { x: 626, y: 154 },
          },
        },
      },
      Actions: [
        {
          Identifier: '12345678-1234-1234-1234-123456789012',
          Type: 'MessageParticipant',
          Parameters: {
            Text: 'Thank you for calling our customer service. Please wait while we connect you to an available agent.',
          },
          Transitions: {
            NextAction: '87654321-4321-4321-4321-210987654321',
          },
        },
        {
          Identifier: '87654321-4321-4321-4321-210987654321',
          Type: 'SetRecordingBehavior',
          Parameters: {
            RecordingBehaviorOption: 'Enable',
            RecordingParticipantOption: 'Both',
          },
          Transitions: {
            NextAction: '11111111-2222-3333-4444-555555555555',
          },
        },
        {
          Identifier: '11111111-2222-3333-4444-555555555555',
          Type: 'TransferToQueue',
          Parameters: {
            QueueId: customerServiceQueue.attrQueueArn,
          },
          Transitions: {},
        },
      ],
    };

    // Contact Flow
    const customerServiceFlow = new connect.CfnContactFlow(this, 'CustomerServiceFlow', {
      instanceArn: connectInstance.attrArn,
      name: 'CustomerServiceFlow',
      description: 'Main customer service contact flow with recording',
      type: 'CONTACT_FLOW',
      content: JSON.stringify(contactFlowContent),
      state: 'ACTIVE',
    });

    // Security Profile for Agents
    const agentSecurityProfile = new connect.CfnSecurityProfile(this, 'AgentSecurityProfile', {
      instanceArn: connectInstance.attrArn,
      securityProfileName: 'CustomerServiceAgent',
      description: 'Security profile for customer service agents',
      permissions: [
        'BasicAgentAccess',
        'OutboundCallAccess',
        'AccessMetrics',
      ],
    });

    // Admin User
    const adminUser = new connect.CfnUser(this, 'AdminUser', {
      instanceArn: connectInstance.attrArn,
      username: 'connect-admin',
      password: 'TempPass123!',
      identityInfo: {
        firstName: 'Connect',
        lastName: 'Administrator',
        email: 'admin@example.com',
      },
      phoneConfig: {
        phoneType: 'SOFT_PHONE',
        autoAccept: false,
        afterContactWorkTimeLimit: 120,
      },
      routingProfileArn: agentRoutingProfile.attrRoutingProfileArn,
      securityProfileArns: [agentSecurityProfile.attrSecurityProfileArn],
    });

    // Agent User
    const agentUser = new connect.CfnUser(this, 'AgentUser', {
      instanceArn: connectInstance.attrArn,
      username: 'service-agent-01',
      password: 'AgentPass123!',
      identityInfo: {
        firstName: 'Service',
        lastName: 'Agent',
        email: 'agent@example.com',
      },
      phoneConfig: {
        phoneType: 'SOFT_PHONE',
        autoAccept: true,
        afterContactWorkTimeLimit: 180,
      },
      routingProfileArn: agentRoutingProfile.attrRoutingProfileArn,
      securityProfileArns: [agentSecurityProfile.attrSecurityProfileArn],
    });

    // CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'ConnectDashboard', {
      dashboardName: `ConnectContactCenter-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Contact Center Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Connect',
                metricName: 'ContactsReceived',
                dimensionsMap: {
                  InstanceId: connectInstance.ref,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Connect',
                metricName: 'ContactsHandled',
                dimensionsMap: {
                  InstanceId: connectInstance.ref,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Connect',
                metricName: 'ContactsAbandoned',
                dimensionsMap: {
                  InstanceId: connectInstance.ref,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 24,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Queue Performance',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Connect',
                metricName: 'QueueSize',
                dimensionsMap: {
                  InstanceId: connectInstance.ref,
                  QueueName: 'CustomerService',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'Agent Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Connect',
                metricName: 'AgentsOnline',
                dimensionsMap: {
                  InstanceId: connectInstance.ref,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Connect',
                metricName: 'AgentsAvailable',
                dimensionsMap: {
                  InstanceId: connectInstance.ref,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Outputs
    new cdk.CfnOutput(this, 'ConnectInstanceId', {
      value: connectInstance.ref,
      description: 'Amazon Connect Instance ID',
    });

    new cdk.CfnOutput(this, 'ConnectInstanceArn', {
      value: connectInstance.attrArn,
      description: 'Amazon Connect Instance ARN',
    });

    new cdk.CfnOutput(this, 'ConnectConsoleUrl', {
      value: `https://${instanceAlias}.my.connect.aws/`,
      description: 'Amazon Connect Admin Console URL',
    });

    new cdk.CfnOutput(this, 'RecordingsBucketName', {
      value: recordingsBucket.bucketName,
      description: 'S3 Bucket for call recordings and chat transcripts',
    });

    new cdk.CfnOutput(this, 'CustomerServiceQueueArn', {
      value: customerServiceQueue.attrQueueArn,
      description: 'Customer Service Queue ARN',
    });

    new cdk.CfnOutput(this, 'ContactFlowArn', {
      value: customerServiceFlow.attrContactFlowArn,
      description: 'Customer Service Contact Flow ARN',
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for monitoring',
    });

    new cdk.CfnOutput(this, 'AdminUsername', {
      value: 'connect-admin',
      description: 'Admin user username (Password: TempPass123!)',
    });

    new cdk.CfnOutput(this, 'AgentUsername', {
      value: 'service-agent-01',
      description: 'Agent user username (Password: AgentPass123!)',
    });

    // Add dependencies to ensure proper resource creation order
    callRecordingStorageConfig.addDependency(connectInstance);
    chatTranscriptStorageConfig.addDependency(connectInstance);
    hoursOfOperation.addDependency(connectInstance);
    customerServiceQueue.addDependency(hoursOfOperation);
    agentRoutingProfile.addDependency(customerServiceQueue);
    customerServiceFlow.addDependency(customerServiceQueue);
    agentSecurityProfile.addDependency(connectInstance);
    adminUser.addDependency(agentRoutingProfile);
    adminUser.addDependency(agentSecurityProfile);
    agentUser.addDependency(agentRoutingProfile);
    agentUser.addDependency(agentSecurityProfile);
  }
}

// CDK App
const app = new cdk.App();

new AmazonConnectContactCenterStack(app, 'AmazonConnectContactCenterStack', {
  description: 'Amazon Connect Contact Center Solution - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'AmazonConnectContactCenter',
    Environment: 'Development',
    Owner: 'CDK',
    CostCenter: 'Engineering',
  },
});