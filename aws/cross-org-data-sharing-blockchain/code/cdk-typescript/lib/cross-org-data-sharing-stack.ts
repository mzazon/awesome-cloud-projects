import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as managedblockchain from 'aws-cdk-lib/aws-managedblockchain';
import { Construct } from 'constructs';

/**
 * Configuration interface for the cross-organization data sharing solution
 */
export interface CrossOrgConfig {
  networkName: string;
  orgAName: string;
  orgBName: string;
  environment: string;
  uniqueSuffix: string;
  enableMonitoring: boolean;
  retentionDays: number;
  networkId?: string;
  orgAMemberId?: string;
  orgBMemberId?: string;
  auditTable?: dynamodb.Table;
  dataBucket?: s3.Bucket;
  lambdaFunction?: lambda.Function;
  eventBridgeRule?: events.Rule;
  notificationTopic?: sns.Topic;
}

/**
 * Stack properties for cross-organization data sharing stacks
 */
export interface CrossOrgStackProps extends cdk.StackProps {
  config: CrossOrgConfig;
}

/**
 * Amazon Managed Blockchain Network Stack
 * 
 * Creates the foundational blockchain network with Hyperledger Fabric,
 * including the initial organization and peer nodes required for
 * cross-organization data sharing operations.
 */
export class BlockchainNetworkStack extends cdk.Stack {
  public readonly networkId: string;
  public readonly orgAMemberId: string;
  public readonly orgBMemberId: string;
  public readonly network: managedblockchain.CfnNetwork;

  constructor(scope: Construct, id: string, props: CrossOrgStackProps) {
    super(scope, id, props);

    const { config } = props;

    // Create the Managed Blockchain network with Hyperledger Fabric
    this.network = new managedblockchain.CfnNetwork(this, 'CrossOrgNetwork', {
      name: `${config.networkName}-${config.uniqueSuffix}`,
      description: 'Cross-Organization Data Sharing Network with Hyperledger Fabric',
      framework: 'HYPERLEDGER_FABRIC',
      frameworkVersion: '2.2',
      frameworkConfiguration: {
        networkFabricConfiguration: {
          edition: 'STANDARD',
        },
      },
      votingPolicy: {
        approvalThresholdPolicy: {
          thresholdPercentage: 66,
          proposalDurationInHours: 24,
          thresholdComparator: 'GREATER_THAN',
        },
      },
      memberConfiguration: {
        name: `${config.orgAName}-${config.uniqueSuffix}`,
        description: 'Financial Institution Member Organization',
        memberFabricConfiguration: {
          adminUsername: 'admin',
          adminPassword: 'TempPassword123!', // In production, use AWS Secrets Manager
        },
      },
    });

    // Create peer node for Organization A
    const orgAPeerNode = new managedblockchain.CfnNode(this, 'OrgAPeerNode', {
      networkId: this.network.attrNetworkId,
      memberId: this.network.attrMemberIds,
      nodeConfiguration: {
        instanceType: 'bc.t3.medium',
        availabilityZone: `${this.region}a`,
      },
    });

    // Store the network and member IDs for other stacks
    this.networkId = this.network.attrNetworkId;
    this.orgAMemberId = this.network.attrMemberIds;

    // Note: Organization B will be added through the invitation process
    // This is simulated here for completeness, but in a real deployment
    // Organization B would be in a separate account
    this.orgBMemberId = 'placeholder-for-org-b';

    // Output key network information
    new cdk.CfnOutput(this, 'NetworkId', {
      value: this.networkId,
      description: 'Amazon Managed Blockchain Network ID',
      exportName: `${this.stackName}-NetworkId`,
    });

    new cdk.CfnOutput(this, 'OrgAMemberId', {
      value: this.orgAMemberId,
      description: 'Organization A Member ID',
      exportName: `${this.stackName}-OrgAMemberId`,
    });

    new cdk.CfnOutput(this, 'NetworkEndpoint', {
      value: this.network.attrVpcEndpointServiceName || 'N/A',
      description: 'VPC Endpoint Service Name for the blockchain network',
    });

    // Add tags to the network
    cdk.Tags.of(this.network).add('Component', 'BlockchainNetwork');
    cdk.Tags.of(this.network).add('Purpose', 'CrossOrgDataSharing');
  }
}

/**
 * Main Cross-Organization Data Sharing Stack
 * 
 * Deploys the core infrastructure including S3 storage for shared data,
 * DynamoDB for audit trails, and IAM roles for cross-organization access.
 */
export class CrossOrgDataSharingStack extends cdk.Stack {
  public readonly auditTable: dynamodb.Table;
  public readonly dataBucket: s3.Bucket;
  public readonly crossOrgAccessRole: iam.Role;

  constructor(scope: Construct, id: string, props: CrossOrgStackProps) {
    super(scope, id, props);

    const { config } = props;

    // Create S3 bucket for shared data and chaincode storage
    this.dataBucket = new s3.Bucket(this, 'CrossOrgDataBucket', {
      bucketName: `cross-org-data-${config.uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldData',
          enabled: true,
          expiration: cdk.Duration.days(config.retentionDays),
          noncurrentVersionExpiration: cdk.Duration.days(7),
        },
      ],
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // Create DynamoDB table for comprehensive audit trail
    this.auditTable = new dynamodb.Table(this, 'CrossOrgAuditTrail', {
      tableName: `CrossOrgAuditTrail-${config.uniqueSuffix}`,
      partitionKey: {
        name: 'TransactionId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER,
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Add GSI for querying by organization
    this.auditTable.addGlobalSecondaryIndex({
      indexName: 'OrganizationIndex',
      partitionKey: {
        name: 'OrganizationId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER,
      },
      readCapacity: 5,
      writeCapacity: 5,
    });

    // Add GSI for querying by event type
    this.auditTable.addGlobalSecondaryIndex({
      indexName: 'EventTypeIndex',
      partitionKey: {
        name: 'EventType',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER,
      },
      readCapacity: 5,
      writeCapacity: 5,
    });

    // Create IAM role for cross-organization access control
    this.crossOrgAccessRole = new iam.Role(this, 'CrossOrgAccessRole', {
      roleName: `CrossOrgDataSharingRole-${config.uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for cross-organization data sharing operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add custom policy for blockchain and data access
    this.crossOrgAccessRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'managedblockchain:GetNetwork',
          'managedblockchain:GetMember',
          'managedblockchain:GetNode',
          'managedblockchain:ListMembers',
          'managedblockchain:ListNodes',
        ],
        resources: ['*'],
        conditions: {
          StringEquals: {
            'managedblockchain:NetworkId': config.networkId || '*',
          },
        },
      })
    );

    this.crossOrgAccessRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:DeleteObject',
          's3:ListBucket',
        ],
        resources: [
          this.dataBucket.bucketArn,
          `${this.dataBucket.bucketArn}/*`,
        ],
      })
    );

    this.crossOrgAccessRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'dynamodb:PutItem',
          'dynamodb:GetItem',
          'dynamodb:Query',
          'dynamodb:UpdateItem',
          'dynamodb:DeleteItem',
        ],
        resources: [
          this.auditTable.tableArn,
          `${this.auditTable.tableArn}/index/*`,
        ],
      })
    );

    // Output resource information
    new cdk.CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'S3 bucket for cross-organization data sharing',
      exportName: `${this.stackName}-DataBucketName`,
    });

    new cdk.CfnOutput(this, 'AuditTableName', {
      value: this.auditTable.tableName,
      description: 'DynamoDB table for audit trail',
      exportName: `${this.stackName}-AuditTableName`,
    });

    new cdk.CfnOutput(this, 'CrossOrgAccessRoleArn', {
      value: this.crossOrgAccessRole.roleArn,
      description: 'IAM role for cross-organization access',
      exportName: `${this.stackName}-CrossOrgAccessRoleArn`,
    });

    // Add tags
    cdk.Tags.of(this.dataBucket).add('Component', 'DataStorage');
    cdk.Tags.of(this.auditTable).add('Component', 'AuditTrail');
    cdk.Tags.of(this.crossOrgAccessRole).add('Component', 'AccessControl');
  }
}

/**
 * Event Processing Stack
 * 
 * Deploys Lambda functions for data validation and event processing,
 * EventBridge rules for cross-organization notifications, and SNS topics
 * for real-time notifications to stakeholders.
 */
export class EventProcessingStack extends cdk.Stack {
  public readonly dataValidationFunction: lambda.Function;
  public readonly eventRule: events.Rule;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: CrossOrgStackProps) {
    super(scope, id, props);

    const { config } = props;

    // Create SNS topic for cross-organization notifications
    this.notificationTopic = new sns.Topic(this, 'CrossOrgNotifications', {
      topicName: `cross-org-notifications-${config.uniqueSuffix}`,
      displayName: 'Cross-Organization Data Sharing Notifications',
      fifo: false,
    });

    // Create Lambda function for data validation and event processing
    this.dataValidationFunction = new lambda.Function(this, 'DataValidationFunction', {
      functionName: `CrossOrgDataValidator-${config.uniqueSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(1),
      memorySize: 512,
      environment: {
        AUDIT_TABLE_NAME: config.auditTable?.tableName || '',
        DATA_BUCKET_NAME: config.dataBucket?.bucketName || '',
        NOTIFICATION_TOPIC_ARN: this.notificationTopic.topicArn,
        ENVIRONMENT: config.environment,
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      role: config.auditTable ? undefined : new iam.Role(this, 'LambdaExecutionRole', {
        assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        ],
      }),
      code: lambda.Code.fromInline(`
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const eventbridge = new AWS.EventBridge();
const s3 = new AWS.S3();
const sns = new AWS.SNS();

exports.handler = async (event) => {
    try {
        console.log('Processing blockchain event:', JSON.stringify(event, null, 2));
        
        // Extract blockchain event data
        const blockchainEvent = {
            eventType: event.eventType || 'UNKNOWN',
            agreementId: event.agreementId,
            organizationId: event.organizationId,
            dataId: event.dataId,
            timestamp: event.timestamp || Date.now(),
            metadata: event.metadata || {}
        };
        
        // Validate event data
        if (!blockchainEvent.agreementId) {
            throw new Error('Agreement ID is required');
        }
        
        // Store audit trail in DynamoDB
        const auditRecord = {
            TransactionId: \`\${blockchainEvent.agreementId}-\${blockchainEvent.timestamp}\`,
            Timestamp: blockchainEvent.timestamp,
            EventType: blockchainEvent.eventType,
            AgreementId: blockchainEvent.agreementId,
            OrganizationId: blockchainEvent.organizationId,
            DataId: blockchainEvent.dataId,
            Metadata: blockchainEvent.metadata
        };
        
        await dynamodb.put({
            TableName: process.env.AUDIT_TABLE_NAME,
            Item: auditRecord
        }).promise();
        
        // Process different event types
        switch (blockchainEvent.eventType) {
            case 'DataSharingAgreementCreated':
                await processAgreementCreated(blockchainEvent);
                break;
            case 'OrganizationJoinedAgreement':
                await processOrganizationJoined(blockchainEvent);
                break;
            case 'DataShared':
                await processDataShared(blockchainEvent);
                break;
            case 'DataAccessed':
                await processDataAccessed(blockchainEvent);
                break;
            default:
                console.log(\`Unknown event type: \${blockchainEvent.eventType}\`);
        }
        
        // Send notification via SNS
        await sns.publish({
            TopicArn: process.env.NOTIFICATION_TOPIC_ARN,
            Subject: \`Cross-Org Blockchain Event: \${blockchainEvent.eventType}\`,
            Message: JSON.stringify(blockchainEvent, null, 2)
        }).promise();
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Blockchain event processed successfully',
                eventType: blockchainEvent.eventType,
                agreementId: blockchainEvent.agreementId
            })
        };
        
    } catch (error) {
        console.error('Error processing blockchain event:', error);
        throw error;
    }
};

async function processAgreementCreated(event) {
    console.log(\`Processing agreement creation: \${event.agreementId}\`);
    
    // Create metadata record in S3
    const metadata = {
        agreementId: event.agreementId,
        creator: event.organizationId,
        createdAt: new Date(event.timestamp).toISOString(),
        status: 'ACTIVE',
        participants: [event.organizationId]
    };
    
    await s3.putObject({
        Bucket: process.env.DATA_BUCKET_NAME,
        Key: \`agreements/\${event.agreementId}/metadata.json\`,
        Body: JSON.stringify(metadata, null, 2),
        ContentType: 'application/json'
    }).promise();
}

async function processOrganizationJoined(event) {
    console.log(\`Processing organization join: \${event.organizationId} to \${event.agreementId}\`);
    // Update participant notification logic would go here
}

async function processDataShared(event) {
    console.log(\`Processing data sharing: \${event.dataId} in \${event.agreementId}\`);
    // Data validation and compliance checks would go here
}

async function processDataAccessed(event) {
    console.log(\`Processing data access: \${event.dataId} by \${event.organizationId}\`);
    // Access logging and compliance monitoring would go here
}
      `),
    });

    // Grant permissions to Lambda function
    if (config.auditTable) {
      config.auditTable.grantReadWriteData(this.dataValidationFunction);
    }
    if (config.dataBucket) {
      config.dataBucket.grantReadWrite(this.dataValidationFunction);
    }
    this.notificationTopic.grantPublish(this.dataValidationFunction);

    // Grant EventBridge permissions
    this.dataValidationFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['events:PutEvents'],
        resources: ['*'],
      })
    );

    // Create EventBridge rule for cross-organization data sharing events
    this.eventRule = new events.Rule(this, 'CrossOrgDataSharingRule', {
      ruleName: `CrossOrgDataSharingRule-${config.uniqueSuffix}`,
      description: 'Rule for cross-organization data sharing events',
      eventPattern: {
        source: ['cross-org.blockchain'],
        detailType: [
          'DataSharingAgreementCreated',
          'OrganizationJoinedAgreement',
          'DataShared',
          'DataAccessed',
        ],
      },
      enabled: true,
    });

    // Add Lambda as target for EventBridge rule
    this.eventRule.addTarget(new targets.LambdaFunction(this.dataValidationFunction));

    // Add SNS as target for notifications
    this.eventRule.addTarget(new targets.SnsTopic(this.notificationTopic));

    // Output event processing information
    new cdk.CfnOutput(this, 'DataValidationFunctionName', {
      value: this.dataValidationFunction.functionName,
      description: 'Lambda function for data validation and event processing',
      exportName: `${this.stackName}-DataValidationFunctionName`,
    });

    new cdk.CfnOutput(this, 'EventRuleName', {
      value: this.eventRule.ruleName,
      description: 'EventBridge rule for cross-organization events',
      exportName: `${this.stackName}-EventRuleName`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS topic for cross-organization notifications',
      exportName: `${this.stackName}-NotificationTopicArn`,
    });

    // Add tags
    cdk.Tags.of(this.dataValidationFunction).add('Component', 'EventProcessing');
    cdk.Tags.of(this.eventRule).add('Component', 'EventRouting');
    cdk.Tags.of(this.notificationTopic).add('Component', 'Notifications');
  }
}

/**
 * Monitoring and Compliance Stack
 * 
 * Deploys CloudWatch dashboards, alarms, and compliance monitoring
 * infrastructure to provide visibility and governance for cross-organization
 * data sharing operations.
 */
export class MonitoringAndComplianceStack extends cdk.Stack {
  public readonly dashboard: cloudwatch.Dashboard;
  public readonly errorAlarm: cloudwatch.Alarm;

  constructor(scope: Construct, id: string, props: CrossOrgStackProps) {
    super(scope, id, props);

    const { config } = props;

    // Create CloudWatch dashboard for cross-organization monitoring
    this.dashboard = new cloudwatch.Dashboard(this, 'CrossOrgDashboard', {
      dashboardName: `CrossOrgDataSharing-${config.uniqueSuffix}`,
    });

    // Add Lambda function metrics to dashboard
    if (config.lambdaFunction) {
      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'Cross-Organization Data Processing Metrics',
          width: 12,
          height: 6,
          left: [
            config.lambdaFunction.metricInvocations({
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
            }),
            config.lambdaFunction.metricErrors({
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
            }),
            config.lambdaFunction.metricDuration({
              statistic: 'Average',
              period: cdk.Duration.minutes(5),
            }),
          ],
        })
      );

      // Create alarm for Lambda function errors
      this.errorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
        alarmName: `CrossOrg-Lambda-Errors-${config.uniqueSuffix}`,
        alarmDescription: 'Alert on cross-organization Lambda function errors',
        metric: config.lambdaFunction.metricErrors({
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 1,
        evaluationPeriods: 1,
      });

      // Add SNS notification to alarm
      if (config.notificationTopic) {
        this.errorAlarm.addAlarmAction(
          new cloudwatch.SnsAction(config.notificationTopic)
        );
      }
    }

    // Add EventBridge metrics to dashboard
    if (config.eventBridgeRule) {
      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'Cross-Organization Event Processing',
          width: 12,
          height: 6,
          left: [
            new cloudwatch.Metric({
              namespace: 'AWS/Events',
              metricName: 'MatchedEvents',
              dimensionsMap: {
                RuleName: config.eventBridgeRule.ruleName,
              },
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
            }),
            new cloudwatch.Metric({
              namespace: 'AWS/Events',
              metricName: 'InvocationsCount',
              dimensionsMap: {
                RuleName: config.eventBridgeRule.ruleName,
              },
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
            }),
          ],
        })
      );
    }

    // Add DynamoDB metrics to dashboard
    if (config.auditTable) {
      this.dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'Audit Trail Storage Metrics',
          width: 12,
          height: 6,
          left: [
            config.auditTable.metricConsumedReadCapacityUnits({
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
            }),
            config.auditTable.metricConsumedWriteCapacityUnits({
              statistic: 'Sum',
              period: cdk.Duration.minutes(5),
            }),
          ],
        })
      );
    }

    // Create compliance monitoring Lambda function
    const complianceMonitorFunction = new lambda.Function(this, 'ComplianceMonitorFunction', {
      functionName: `CrossOrgComplianceMonitor-${config.uniqueSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        AUDIT_TABLE_NAME: config.auditTable?.tableName || '',
        ENVIRONMENT: config.environment,
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      code: lambda.Code.fromInline(`
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    try {
        console.log('Monitoring compliance for cross-organization data sharing');
        
        // Query recent audit trail entries
        const params = {
            TableName: process.env.AUDIT_TABLE_NAME,
            IndexName: 'EventTypeIndex',
            KeyConditionExpression: 'EventType = :eventType',
            FilterExpression: '#ts BETWEEN :start AND :end',
            ExpressionAttributeNames: {
                '#ts': 'Timestamp'
            },
            ExpressionAttributeValues: {
                ':eventType': 'DataAccessed',
                ':start': Date.now() - (24 * 60 * 60 * 1000), // Last 24 hours
                ':end': Date.now()
            }
        };
        
        const result = await dynamodb.query(params).promise();
        
        // Analyze access patterns for compliance
        const accessAnalysis = {
            totalAccesses: result.Items.length,
            uniqueOrganizations: [...new Set(result.Items.map(item => item.OrganizationId))].length,
            timestamp: new Date().toISOString()
        };
        
        console.log('Compliance analysis:', accessAnalysis);
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Compliance monitoring completed',
                analysis: accessAnalysis
            })
        };
        
    } catch (error) {
        console.error('Error in compliance monitoring:', error);
        throw error;
    }
};
      `),
    });

    // Grant permissions to compliance monitoring function
    if (config.auditTable) {
      config.auditTable.grantReadData(complianceMonitorFunction);
    }

    // Schedule compliance monitoring to run daily
    const complianceRule = new events.Rule(this, 'ComplianceMonitoringRule', {
      ruleName: `ComplianceMonitoring-${config.uniqueSuffix}`,
      description: 'Daily compliance monitoring for cross-organization data sharing',
      schedule: events.Schedule.rate(cdk.Duration.days(1)),
      enabled: config.enableMonitoring,
    });

    complianceRule.addTarget(new targets.LambdaFunction(complianceMonitorFunction));

    // Output monitoring information
    new cdk.CfnOutput(this, 'DashboardName', {
      value: this.dashboard.dashboardName,
      description: 'CloudWatch dashboard for cross-organization monitoring',
      exportName: `${this.stackName}-DashboardName`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
    });

    new cdk.CfnOutput(this, 'ComplianceMonitorFunctionName', {
      value: complianceMonitorFunction.functionName,
      description: 'Lambda function for compliance monitoring',
      exportName: `${this.stackName}-ComplianceMonitorFunctionName`,
    });

    // Add tags
    cdk.Tags.of(this.dashboard).add('Component', 'Monitoring');
    cdk.Tags.of(complianceMonitorFunction).add('Component', 'ComplianceMonitoring');
    if (this.errorAlarm) {
      cdk.Tags.of(this.errorAlarm).add('Component', 'Alerting');
    }
  }
}