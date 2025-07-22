#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as managedblockchain from 'aws-cdk-lib/aws-managedblockchain';

/**
 * Properties for the BlockchainSupplyChainStack
 */
export interface BlockchainSupplyChainStackProps extends cdk.StackProps {
  /** Network name for the blockchain network */
  readonly networkName?: string;
  /** Member name for the initial blockchain member */
  readonly memberName?: string;
  /** Admin username for the blockchain member */
  readonly adminUsername?: string;
  /** Admin password for the blockchain member */
  readonly adminPassword?: string;
  /** Environment prefix for resource naming */
  readonly environmentPrefix?: string;
}

/**
 * CDK Stack for Blockchain-Based Supply Chain Tracking Systems
 * 
 * This stack creates a comprehensive supply chain tracking solution using:
 * - Amazon Managed Blockchain with Hyperledger Fabric
 * - AWS IoT Core for sensor data collection
 * - AWS Lambda for data processing
 * - Amazon EventBridge for event orchestration
 * - DynamoDB for metadata storage
 * - S3 for chaincode and data storage
 * - CloudWatch for monitoring and alerting
 */
export class BlockchainSupplyChainStack extends cdk.Stack {
  public readonly blockchainNetwork: managedblockchain.CfnNetwork;
  public readonly blockchainMember: managedblockchain.CfnMember;
  public readonly peerNode: managedblockchain.CfnNode;
  public readonly dataProcessingFunction: lambda.Function;
  public readonly supplyChainBucket: s3.Bucket;
  public readonly metadataTable: dynamodb.Table;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: BlockchainSupplyChainStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const environmentPrefix = props.environmentPrefix || 'supply-chain';
    const networkName = props.networkName || `${environmentPrefix}-network`;
    const memberName = props.memberName || `${environmentPrefix}-manufacturer`;
    const adminUsername = props.adminUsername || 'admin';
    const adminPassword = props.adminPassword || 'TempPassword123!';

    // Generate random suffix for unique resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    /**
     * S3 Bucket for storing chaincode and supply chain data
     * Configured with versioning, encryption, and lifecycle policies
     */
    this.supplyChainBucket = new s3.Bucket(this, 'SupplyChainBucket', {
      bucketName: `${environmentPrefix}-data-${randomSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
    });

    /**
     * DynamoDB Table for supply chain metadata
     * Configured with on-demand billing and point-in-time recovery
     */
    this.metadataTable = new dynamodb.Table(this, 'SupplyChainMetadata', {
      tableName: 'SupplyChainMetadata',
      partitionKey: {
        name: 'ProductId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER,
      },
      billingMode: dynamodb.BillingMode.ON_DEMAND,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      // Global Secondary Index for querying by location
      globalSecondaryIndexes: [
        {
          indexName: 'LocationIndex',
          partitionKey: {
            name: 'Location',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'Timestamp',
            type: dynamodb.AttributeType.NUMBER,
          },
        },
      ],
    });

    /**
     * SNS Topic for supply chain notifications
     * Used for alerting stakeholders about supply chain events
     */
    this.notificationTopic = new sns.Topic(this, 'SupplyChainNotifications', {
      topicName: `${environmentPrefix}-notifications`,
      displayName: 'Supply Chain Tracking Notifications',
    });

    /**
     * IAM Role for Lambda function execution
     * Includes permissions for DynamoDB, EventBridge, S3, and CloudWatch
     */
    const lambdaExecutionRole = new iam.Role(this, 'SupplyChainLambdaRole', {
      roleName: `SupplyChainLambdaRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        SupplyChainAccess: new iam.PolicyDocument({
          statements: [
            // DynamoDB permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:UpdateItem',
              ],
              resources: [this.metadataTable.tableArn, `${this.metadataTable.tableArn}/index/*`],
            }),
            // EventBridge permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['events:PutEvents'],
              resources: [`arn:aws:events:${this.region}:${this.account}:event-bus/default`],
            }),
            // S3 permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:PutObject'],
              resources: [`${this.supplyChainBucket.bucketArn}/*`],
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
            }),
          ],
        }),
      },
    });

    /**
     * Lambda Function for processing IoT sensor data
     * Processes incoming sensor data and updates blockchain and storage systems
     */
    this.dataProcessingFunction = new lambda.Function(this, 'ProcessSupplyChainData', {
      functionName: 'ProcessSupplyChainData',
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        METADATA_TABLE_NAME: this.metadataTable.tableName,
        SUPPLY_CHAIN_BUCKET: this.supplyChainBucket.bucketName,
        NOTIFICATION_TOPIC_ARN: this.notificationTopic.topicArn,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const dynamodb = new AWS.DynamoDB.DocumentClient();
        const eventbridge = new AWS.EventBridge();

        exports.handler = async (event) => {
            console.log('Processing sensor data:', JSON.stringify(event, null, 2));
            
            try {
                // Extract sensor data from IoT event
                const sensorData = {
                    productId: event.productId,
                    location: event.location,
                    temperature: event.temperature,
                    humidity: event.humidity,
                    timestamp: event.timestamp || Date.now()
                };
                
                // Validate required fields
                if (!sensorData.productId || !sensorData.location) {
                    throw new Error('Missing required fields: productId and location');
                }
                
                // Store metadata in DynamoDB
                await dynamodb.put({
                    TableName: process.env.METADATA_TABLE_NAME,
                    Item: {
                        ProductId: sensorData.productId,
                        Timestamp: sensorData.timestamp,
                        Location: sensorData.location,
                        SensorData: {
                            temperature: sensorData.temperature || null,
                            humidity: sensorData.humidity || null
                        },
                        ProcessedAt: new Date().toISOString()
                    }
                }).promise();
                
                // Send event to EventBridge for downstream processing
                await eventbridge.putEvents({
                    Entries: [{
                        Source: 'supply-chain.sensor',
                        DetailType: 'Product Location Update',
                        Detail: JSON.stringify(sensorData),
                        Time: new Date()
                    }]
                }).promise();
                
                // Check for temperature alerts
                if (sensorData.temperature && (sensorData.temperature < 2 || sensorData.temperature > 8)) {
                    await eventbridge.putEvents({
                        Entries: [{
                            Source: 'supply-chain.alert',
                            DetailType: 'Temperature Alert',
                            Detail: JSON.stringify({
                                ...sensorData,
                                alertType: 'TEMPERATURE_EXCURSION',
                                severity: 'HIGH'
                            }),
                            Time: new Date()
                        }]
                    }).promise();
                }
                
                return {
                    statusCode: 200,
                    body: JSON.stringify({
                        message: 'Sensor data processed successfully',
                        productId: sensorData.productId,
                        timestamp: sensorData.timestamp
                    })
                };
                
            } catch (error) {
                console.error('Error processing sensor data:', error);
                
                // Send error event
                await eventbridge.putEvents({
                    Entries: [{
                        Source: 'supply-chain.error',
                        DetailType: 'Processing Error',
                        Detail: JSON.stringify({
                            error: error.message,
                            event: event
                        }),
                        Time: new Date()
                    }]
                }).promise();
                
                throw error;
            }
        };
      `),
    });

    /**
     * IoT Thing for supply chain tracking devices
     * Represents logical IoT devices that can authenticate and communicate
     */
    const iotThing = new iot.CfnThing(this, 'SupplyChainTracker', {
      thingName: `${environmentPrefix}-tracker-${randomSuffix}`,
      attributePayload: {
        attributes: {
          deviceType: 'supplyChainTracker',
          version: '1.0',
          environment: environmentPrefix,
        },
      },
    });

    /**
     * IoT Policy for supply chain devices
     * Defines permissions for IoT devices to connect and publish data
     */
    const iotPolicy = new iot.CfnPolicy(this, 'SupplyChainTrackerPolicy', {
      policyName: `SupplyChainTrackerPolicy-${randomSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              'iot:Publish',
              'iot:Subscribe',
              'iot:Connect',
              'iot:Receive',
            ],
            Resource: '*',
          },
        ],
      },
    });

    /**
     * IoT Topic Rule for processing sensor data
     * Routes IoT messages to Lambda function for processing
     */
    const iotRule = new iot.CfnTopicRule(this, 'SupplyChainSensorRule', {
      ruleName: `SupplyChainSensorRule${randomSuffix}`,
      topicRulePayload: {
        sql: "SELECT * FROM 'supply-chain/sensor-data'",
        description: 'Route supply chain sensor data to Lambda for processing',
        actions: [
          {
            lambda: {
              functionArn: this.dataProcessingFunction.functionArn,
            },
          },
        ],
        ruleDisabled: false,
      },
    });

    /**
     * Grant IoT permission to invoke Lambda function
     */
    this.dataProcessingFunction.addPermission('IoTInvoke', {
      principal: new iam.ServicePrincipal('iot.amazonaws.com'),
      sourceArn: iotRule.attrArn,
      action: 'lambda:InvokeFunction',
    });

    /**
     * EventBridge Rule for supply chain tracking events
     * Captures and routes supply chain events for notifications
     */
    const supplyChainRule = new events.Rule(this, 'SupplyChainTrackingRule', {
      ruleName: `SupplyChainTrackingRule-${randomSuffix}`,
      description: 'Rule for supply chain tracking events',
      eventPattern: {
        source: ['supply-chain.sensor', 'supply-chain.alert'],
        detailType: ['Product Location Update', 'Temperature Alert'],
      },
      enabled: true,
    });

    /**
     * Add SNS topic as target for EventBridge rule
     */
    supplyChainRule.addTarget(new targets.SnsTopic(this.notificationTopic));

    /**
     * Amazon Managed Blockchain Network
     * Creates a Hyperledger Fabric network for supply chain tracking
     */
    this.blockchainNetwork = new managedblockchain.CfnNetwork(this, 'SupplyChainNetwork', {
      name: networkName,
      description: 'Supply Chain Tracking Blockchain Network',
      framework: 'HYPERLEDGER_FABRIC',
      frameworkVersion: '2.2',
      frameworkConfiguration: {
        networkFabricConfiguration: {
          edition: 'STARTER', // Use STANDARD for production workloads
        },
      },
      votingPolicy: {
        approvalThresholdPolicy: {
          thresholdPercentage: 50,
          proposalDurationInHours: 24,
          thresholdComparator: 'GREATER_THAN',
        },
      },
      memberConfiguration: {
        name: memberName,
        description: 'Manufacturer member of the supply chain network',
        memberFabricConfiguration: {
          adminUsername: adminUsername,
          adminPassword: adminPassword,
        },
      },
    });

    /**
     * Blockchain Member
     * Represents the manufacturer organization in the blockchain network
     */
    this.blockchainMember = new managedblockchain.CfnMember(this, 'SupplyChainMember', {
      networkId: this.blockchainNetwork.attrNetworkId,
      memberConfiguration: {
        name: memberName,
        description: 'Manufacturer member of the supply chain network',
        memberFabricConfiguration: {
          adminUsername: adminUsername,
          adminPassword: adminPassword,
        },
      },
    });

    // Ensure member depends on network
    this.blockchainMember.addDependency(this.blockchainNetwork);

    /**
     * Blockchain Peer Node
     * Processes transactions and maintains the blockchain ledger
     */
    this.peerNode = new managedblockchain.CfnNode(this, 'SupplyChainPeerNode', {
      networkId: this.blockchainNetwork.attrNetworkId,
      memberId: this.blockchainMember.attrMemberId,
      nodeConfiguration: {
        instanceType: 'bc.t3.small', // Suitable for development/testing
        availabilityZone: `${this.region}a`,
      },
    });

    // Ensure peer node depends on member
    this.peerNode.addDependency(this.blockchainMember);

    /**
     * CloudWatch Dashboard for monitoring supply chain metrics
     */
    const dashboard = new cloudwatch.Dashboard(this, 'SupplyChainDashboard', {
      dashboardName: `SupplyChainTracking-${randomSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              this.dataProcessingFunction.metricInvocations(),
              this.dataProcessingFunction.metricErrors(),
            ],
            right: [this.dataProcessingFunction.metricDuration()],
            width: 12,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'DynamoDB Metrics',
            left: [
              this.metadataTable.metricConsumedReadCapacityUnits(),
              this.metadataTable.metricConsumedWriteCapacityUnits(),
            ],
            right: [this.metadataTable.metricThrottledRequests()],
            width: 12,
          }),
        ],
      ],
    });

    /**
     * CloudWatch Alarms for monitoring and alerting
     */
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `SupplyChain-Lambda-Errors-${randomSuffix}`,
      alarmDescription: 'Alert on Lambda function errors',
      metric: this.dataProcessingFunction.metricErrors(),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const dynamodbThrottleAlarm = new cloudwatch.Alarm(this, 'DynamoDBThrottleAlarm', {
      alarmName: `SupplyChain-DynamoDB-Throttles-${randomSuffix}`,
      alarmDescription: 'Alert on DynamoDB throttling',
      metric: this.metadataTable.metricThrottledRequests(),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS notification to alarms
    lambdaErrorAlarm.addAlarmAction(new cloudwatch.SnsAction(this.notificationTopic));
    dynamodbThrottleAlarm.addAlarmAction(new cloudwatch.SnsAction(this.notificationTopic));

    /**
     * Stack Outputs for reference and integration
     */
    new cdk.CfnOutput(this, 'BlockchainNetworkId', {
      value: this.blockchainNetwork.attrNetworkId,
      description: 'Blockchain Network ID',
      exportName: `${this.stackName}-NetworkId`,
    });

    new cdk.CfnOutput(this, 'BlockchainMemberId', {
      value: this.blockchainMember.attrMemberId,
      description: 'Blockchain Member ID',
      exportName: `${this.stackName}-MemberId`,
    });

    new cdk.CfnOutput(this, 'PeerNodeId', {
      value: this.peerNode.attrNodeId,
      description: 'Peer Node ID',
      exportName: `${this.stackName}-NodeId`,
    });

    new cdk.CfnOutput(this, 'SupplyChainBucketName', {
      value: this.supplyChainBucket.bucketName,
      description: 'S3 Bucket for supply chain data',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'MetadataTableName', {
      value: this.metadataTable.tableName,
      description: 'DynamoDB table for supply chain metadata',
      exportName: `${this.stackName}-TableName`,
    });

    new cdk.CfnOutput(this, 'DataProcessingFunctionName', {
      value: this.dataProcessingFunction.functionName,
      description: 'Lambda function for processing sensor data',
      exportName: `${this.stackName}-FunctionName`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS topic for supply chain notifications',
      exportName: `${this.stackName}-TopicArn`,
    });

    new cdk.CfnOutput(this, 'IoTThingName', {
      value: iotThing.thingName!,
      description: 'IoT Thing name for supply chain tracking',
      exportName: `${this.stackName}-IoTThingName`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
    });

    /**
     * Tags for all resources in the stack
     */
    cdk.Tags.of(this).add('Project', 'SupplyChainTracking');
    cdk.Tags.of(this).add('Environment', environmentPrefix);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'SupplyChain');
  }
}

/**
 * Main CDK Application
 * Creates and configures the supply chain tracking stack
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || process.env.ENVIRONMENT_PREFIX || 'supply-chain';
const networkName = app.node.tryGetContext('networkName') || process.env.NETWORK_NAME;
const memberName = app.node.tryGetContext('memberName') || process.env.MEMBER_NAME;
const adminUsername = app.node.tryGetContext('adminUsername') || process.env.ADMIN_USERNAME || 'admin';
const adminPassword = app.node.tryGetContext('adminPassword') || process.env.ADMIN_PASSWORD || 'TempPassword123!';

// Create the main stack
new BlockchainSupplyChainStack(app, 'BlockchainSupplyChainStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Blockchain-based supply chain tracking system using Amazon Managed Blockchain, IoT Core, and Lambda',
  environmentPrefix,
  networkName,
  memberName,
  adminUsername,
  adminPassword,
});

// Synthesize the app
app.synth();