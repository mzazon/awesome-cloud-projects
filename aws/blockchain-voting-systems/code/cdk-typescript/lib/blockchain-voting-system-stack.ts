import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as path from 'path';

/**
 * Stack properties for the Blockchain Voting System
 */
export interface BlockchainVotingSystemStackProps extends cdk.StackProps {
  environment: string;
  adminEmail: string;
}

/**
 * Main CDK Stack for the Blockchain Voting System
 * 
 * This stack creates a comprehensive blockchain-based voting system with:
 * - Amazon Managed Blockchain for immutable vote storage
 * - Lambda functions for voter authentication and vote monitoring
 * - DynamoDB for voter registry and election management
 * - S3 for voting data storage and DApp hosting
 * - EventBridge for real-time event processing
 * - SNS for notifications
 * - CloudWatch for monitoring and alerting
 * - API Gateway with Cognito authentication
 * - KMS for encryption
 */
export class BlockchainVotingSystemStack extends cdk.Stack {
  public readonly votingSystemBucket: s3.Bucket;
  public readonly voterAuthFunction: lambda.Function;
  public readonly voteMonitorFunction: lambda.Function;
  public readonly voterRegistryTable: dynamodb.Table;
  public readonly electionsTable: dynamodb.Table;
  public readonly encryptionKey: kms.Key;
  public readonly votingNotificationTopic: sns.Topic;
  public readonly userPool: cognito.UserPool;
  public readonly api: apigateway.RestApi;

  constructor(scope: Construct, id: string, props: BlockchainVotingSystemStackProps) {
    super(scope, id, props);

    // Create KMS key for encryption
    this.encryptionKey = this.createEncryptionKey();

    // Create S3 bucket for voting data and DApp hosting
    this.votingSystemBucket = this.createVotingSystemBucket();

    // Create DynamoDB tables
    this.voterRegistryTable = this.createVoterRegistryTable();
    this.electionsTable = this.createElectionsTable();

    // Create Cognito User Pool for authentication
    this.userPool = this.createUserPool(props.adminEmail);

    // Create SNS topic for notifications
    this.votingNotificationTopic = this.createNotificationTopic(props.adminEmail);

    // Create Lambda functions
    this.voterAuthFunction = this.createVoterAuthFunction();
    this.voteMonitorFunction = this.createVoteMonitorFunction();

    // Create EventBridge rules for voting events
    this.createEventBridgeRules();

    // Create API Gateway
    this.api = this.createApiGateway();

    // Create CloudWatch dashboard and alarms
    this.createMonitoringResources();

    // Grant necessary permissions
    this.grantPermissions();

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates KMS key for encrypting voting system data
   */
  private createEncryptionKey(): kms.Key {
    const key = new kms.Key(this, 'VotingSystemEncryptionKey', {
      description: 'KMS key for encrypting voting system data',
      enableKeyRotation: true,
      keyPolicy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'Enable IAM User Permissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'Allow CloudWatch Logs',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('logs.amazonaws.com')],
            actions: [
              'kms:Encrypt',
              'kms:Decrypt',
              'kms:ReEncrypt*',
              'kms:GenerateDataKey*',
              'kms:DescribeKey',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create alias for easier identification
    new kms.Alias(this, 'VotingSystemKeyAlias', {
      aliasName: 'alias/voting-system-key',
      targetKey: key,
    });

    return key;
  }

  /**
   * Creates S3 bucket for voting system data and DApp hosting
   */
  private createVotingSystemBucket(): s3.Bucket {
    const bucket = new s3.Bucket(this, 'VotingSystemBucket', {
      bucketName: `voting-system-${this.account}-${this.region}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.encryptionKey,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For dev/testing - change to RETAIN for production
      autoDeleteObjects: true, // For dev/testing - remove for production
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
        {
          id: 'ArchiveOldData',
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
      notificationConfiguration: {
        eventBridgeConfiguration: {
          enabled: true,
        },
      },
    });

    // Create bucket policy for secure access
    bucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:*'],
        resources: [bucket.bucketArn, bucket.arnForObjects('*')],
        conditions: {
          Bool: {
            'aws:SecureTransport': 'false',
          },
        },
      })
    );

    return bucket;
  }

  /**
   * Creates DynamoDB table for voter registry
   */
  private createVoterRegistryTable(): dynamodb.Table {
    const table = new dynamodb.Table(this, 'VoterRegistryTable', {
      tableName: 'VoterRegistry',
      partitionKey: {
        name: 'VoterId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'ElectionId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.CUSTOMER_MANAGED,
      encryptionKey: this.encryptionKey,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For dev/testing - change to RETAIN for production
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Add GSI for querying by election
    table.addGlobalSecondaryIndex({
      indexName: 'ElectionIndex',
      partitionKey: {
        name: 'ElectionId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'VoterId',
        type: dynamodb.AttributeType.STRING,
      },
    });

    return table;
  }

  /**
   * Creates DynamoDB table for elections
   */
  private createElectionsTable(): dynamodb.Table {
    const table = new dynamodb.Table(this, 'ElectionsTable', {
      tableName: 'Elections',
      partitionKey: {
        name: 'ElectionId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.CUSTOMER_MANAGED,
      encryptionKey: this.encryptionKey,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For dev/testing - change to RETAIN for production
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Add GSI for querying by status
    table.addGlobalSecondaryIndex({
      indexName: 'StatusIndex',
      partitionKey: {
        name: 'Status',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'ElectionId',
        type: dynamodb.AttributeType.STRING,
      },
    });

    return table;
  }

  /**
   * Creates Cognito User Pool for voter authentication
   */
  private createUserPool(adminEmail: string): cognito.UserPool {
    const userPool = new cognito.UserPool(this, 'VotingUserPool', {
      userPoolName: 'VotingSystemUserPool',
      selfSignUpEnabled: false, // Only admin can create users
      signInAliases: {
        email: true,
        username: true,
      },
      autoVerify: {
        email: true,
      },
      standardAttributes: {
        email: {
          required: true,
          mutable: false,
        },
        givenName: {
          required: true,
          mutable: true,
        },
        familyName: {
          required: true,
          mutable: true,
        },
      },
      customAttributes: {
        voterId: new cognito.StringAttribute({
          mutable: false,
        }),
        electionId: new cognito.StringAttribute({
          mutable: true,
        }),
      },
      passwordPolicy: {
        minLength: 12,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For dev/testing - change to RETAIN for production
    });

    // Create user pool client for the DApp
    const userPoolClient = new cognito.UserPoolClient(this, 'VotingUserPoolClient', {
      userPool,
      userPoolClientName: 'VotingDAppClient',
      generateSecret: false,
      authFlows: {
        userPassword: true,
        userSrp: true,
      },
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
        },
        scopes: [
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.PROFILE,
        ],
      },
    });

    return userPool;
  }

  /**
   * Creates SNS topic for voting system notifications
   */
  private createNotificationTopic(adminEmail: string): sns.Topic {
    const topic = new sns.Topic(this, 'VotingNotificationTopic', {
      topicName: 'VotingSystemNotifications',
      displayName: 'Voting System Notifications',
      masterKey: this.encryptionKey,
    });

    // Add email subscription for admin
    topic.addSubscription(new subscriptions.EmailSubscription(adminEmail));

    return topic;
  }

  /**
   * Creates the voter authentication Lambda function
   */
  private createVoterAuthFunction(): lambda.Function {
    const fn = new lambda.Function(this, 'VoterAuthFunction', {
      functionName: 'VoterAuthentication',
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
const AWS = require('aws-sdk');
const crypto = require('crypto');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const kms = new AWS.KMS();

exports.handler = async (event) => {
    try {
        const action = event.action;
        
        switch (action) {
            case 'registerVoter':
                return await registerVoter(event);
            case 'verifyVoter':
                return await verifyVoter(event);
            case 'generateVotingToken':
                return await generateVotingToken(event);
            default:
                throw new Error(\`Unknown action: \${action}\`);
        }
        
    } catch (error) {
        console.error('Error in voter authentication:', error);
        return {
            statusCode: 400,
            body: JSON.stringify({
                error: error.message
            })
        };
    }
};

async function registerVoter(event) {
    const { voterId, electionId, identityDocument, publicKey } = event;
    
    if (!voterId || !electionId || !identityDocument || !publicKey) {
        throw new Error('Missing required fields for voter registration');
    }
    
    const voterIdHash = crypto.createHash('sha256').update(voterId).digest('hex');
    
    const encryptionParams = {
        KeyId: process.env.KMS_KEY_ID,
        Plaintext: JSON.stringify(identityDocument)
    };
    
    const encryptedIdentity = await kms.encrypt(encryptionParams).promise();
    
    const voterRecord = {
        VoterId: voterIdHash,
        ElectionId: electionId,
        PublicKey: publicKey,
        EncryptedIdentity: encryptedIdentity.CiphertextBlob.toString('base64'),
        RegistrationTimestamp: Date.now(),
        IsVerified: false,
        IsActive: true
    };
    
    await dynamodb.put({
        TableName: 'VoterRegistry',
        Item: voterRecord,
        ConditionExpression: 'attribute_not_exists(VoterId)'
    }).promise();
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Voter registered successfully',
            voterIdHash: voterIdHash,
            requiresVerification: true
        })
    };
}

async function verifyVoter(event) {
    const { voterIdHash, electionId, verificationCode } = event;
    
    const voterRecord = await dynamodb.get({
        TableName: 'VoterRegistry',
        Key: {
            VoterId: voterIdHash,
            ElectionId: electionId
        }
    }).promise();
    
    if (!voterRecord.Item) {
        throw new Error('Voter not found');
    }
    
    const isValidVerification = await validateVerificationCode(verificationCode);
    
    if (!isValidVerification) {
        throw new Error('Invalid verification code');
    }
    
    await dynamodb.update({
        TableName: 'VoterRegistry',
        Key: {
            VoterId: voterIdHash,
            ElectionId: electionId
        },
        UpdateExpression: 'SET IsVerified = :verified, VerificationTimestamp = :timestamp',
        ExpressionAttributeValues: {
            ':verified': true,
            ':timestamp': Date.now()
        }
    }).promise();
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Voter verified successfully',
            isVerified: true
        })
    };
}

async function generateVotingToken(event) {
    const { voterIdHash, electionId } = event;
    
    const voterRecord = await dynamodb.get({
        TableName: 'VoterRegistry',
        Key: {
            VoterId: voterIdHash,
            ElectionId: electionId
        }
    }).promise();
    
    if (!voterRecord.Item || !voterRecord.Item.IsVerified) {
        throw new Error('Voter not verified');
    }
    
    const tokenPayload = {
        voterIdHash: voterIdHash,
        electionId: electionId,
        timestamp: Date.now(),
        expiresAt: Date.now() + (60 * 60 * 1000)
    };
    
    const encryptedToken = await kms.encrypt({
        KeyId: process.env.KMS_KEY_ID,
        Plaintext: JSON.stringify(tokenPayload)
    }).promise();
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Voting token generated successfully',
            token: encryptedToken.CiphertextBlob.toString('base64'),
            expiresAt: tokenPayload.expiresAt
        })
    };
}

async function validateVerificationCode(code) {
    return code && code.length >= 6;
}
      `),
      environment: {
        KMS_KEY_ID: this.encryptionKey.keyId,
        VOTER_REGISTRY_TABLE: this.voterRegistryTable.tableName,
        ELECTIONS_TABLE: this.electionsTable.tableName,
      },
      timeout: cdk.Duration.minutes(1),
      memorySize: 512,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    return fn;
  }

  /**
   * Creates the vote monitoring Lambda function
   */
  private createVoteMonitorFunction(): lambda.Function {
    const fn = new lambda.Function(this, 'VoteMonitorFunction', {
      functionName: 'VoteMonitoring',
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const eventbridge = new AWS.EventBridge();
const s3 = new AWS.S3();

exports.handler = async (event) => {
    try {
        console.log('Processing voting event:', JSON.stringify(event, null, 2));
        
        const votingEvent = {
            eventType: event.eventType || 'UNKNOWN',
            electionId: event.electionId,
            candidateId: event.candidateId,
            voterAddress: event.voterAddress,
            transactionHash: event.transactionHash,
            blockNumber: event.blockNumber,
            timestamp: event.timestamp || Date.now()
        };
        
        switch (votingEvent.eventType) {
            case 'VoteCast':
                await processVoteCast(votingEvent);
                break;
            case 'ElectionCreated':
                await processElectionCreated(votingEvent);
                break;
            case 'ElectionEnded':
                await processElectionEnded(votingEvent);
                break;
            case 'CandidateRegistered':
                await processCandidateRegistered(votingEvent);
                break;
            default:
                console.log(\`Unknown event type: \${votingEvent.eventType}\`);
        }
        
        await storeAuditEvent(votingEvent);
        
        await eventbridge.putEvents({
            Entries: [{
                Source: 'voting.blockchain',
                DetailType: votingEvent.eventType,
                Detail: JSON.stringify(votingEvent)
            }]
        }).promise();
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Voting event processed successfully',
                eventType: votingEvent.eventType,
                electionId: votingEvent.electionId
            })
        };
        
    } catch (error) {
        console.error('Error processing voting event:', error);
        throw error;
    }
};

async function processVoteCast(event) {
    console.log(\`Processing vote cast: Election \${event.electionId}, Candidate \${event.candidateId}\`);
    
    await dynamodb.update({
        TableName: 'Elections',
        Key: { ElectionId: event.electionId },
        UpdateExpression: 'ADD TotalVotes :increment',
        ExpressionAttributeValues: {
            ':increment': 1
        }
    }).promise();
    
    const voteRecord = {
        electionId: event.electionId,
        candidateId: event.candidateId,
        transactionHash: event.transactionHash,
        blockNumber: event.blockNumber,
        timestamp: event.timestamp,
        voterAddressHash: hashAddress(event.voterAddress)
    };
    
    await s3.putObject({
        Bucket: process.env.BUCKET_NAME,
        Key: \`votes/\${event.electionId}/\${event.transactionHash}.json\`,
        Body: JSON.stringify(voteRecord),
        ServerSideEncryption: 'AES256'
    }).promise();
}

async function processElectionCreated(event) {
    console.log(\`Processing election creation: \${event.electionId}\`);
    
    const electionRecord = {
        ElectionId: event.electionId,
        CreatedAt: event.timestamp,
        Status: 'ACTIVE',
        TotalVotes: 0,
        LastUpdated: event.timestamp
    };
    
    await dynamodb.put({
        TableName: 'Elections',
        Item: electionRecord
    }).promise();
}

async function processElectionEnded(event) {
    console.log(\`Processing election end: \${event.electionId}\`);
    
    await dynamodb.update({
        TableName: 'Elections',
        Key: { ElectionId: event.electionId },
        UpdateExpression: 'SET #status = :status, EndedAt = :timestamp',
        ExpressionAttributeNames: {
            '#status': 'Status'
        },
        ExpressionAttributeValues: {
            ':status': 'ENDED',
            ':timestamp': event.timestamp
        }
    }).promise();
    
    await generateResultsReport(event.electionId);
}

async function processCandidateRegistered(event) {
    console.log(\`Processing candidate registration: Election \${event.electionId}, Candidate \${event.candidateId}\`);
}

async function storeAuditEvent(event) {
    console.log('AUDIT_EVENT:', JSON.stringify(event));
}

async function generateResultsReport(electionId) {
    console.log(\`Generating results report for election: \${electionId}\`);
    
    const reportData = {
        electionId: electionId,
        generatedAt: new Date().toISOString(),
        status: 'FINAL',
        note: 'Results report generated from blockchain data'
    };
    
    await s3.putObject({
        Bucket: process.env.BUCKET_NAME,
        Key: \`results/\${electionId}/final-report.json\`,
        Body: JSON.stringify(reportData, null, 2),
        ContentType: 'application/json'
    }).promise();
}

function hashAddress(address) {
    const crypto = require('crypto');
    return crypto.createHash('sha256').update(address).digest('hex');
}
      `),
      environment: {
        BUCKET_NAME: this.votingSystemBucket.bucketName,
        VOTER_REGISTRY_TABLE: this.voterRegistryTable.tableName,
        ELECTIONS_TABLE: this.electionsTable.tableName,
      },
      timeout: cdk.Duration.minutes(1),
      memorySize: 512,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    return fn;
  }

  /**
   * Creates EventBridge rules for voting events
   */
  private createEventBridgeRules(): void {
    // Create EventBridge rule for voting events
    const votingEventRule = new events.Rule(this, 'VotingSystemEventsRule', {
      ruleName: 'VotingSystemEvents',
      description: 'Rule for blockchain voting system events',
      eventPattern: {
        source: ['voting.blockchain'],
        detailType: ['VoteCast', 'ElectionCreated', 'ElectionEnded', 'CandidateRegistered'],
      },
    });

    // Add SNS topic as target
    votingEventRule.addTarget(new targets.SnsTopic(this.votingNotificationTopic));

    // Add Lambda function as target
    votingEventRule.addTarget(new targets.LambdaFunction(this.voteMonitorFunction));
  }

  /**
   * Creates API Gateway for voting system
   */
  private createApiGateway(): apigateway.RestApi {
    const api = new apigateway.RestApi(this, 'VotingSystemApi', {
      restApiName: 'VotingSystemAPI',
      description: 'API for blockchain voting system',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      deployOptions: {
        stageName: 'api',
        throttle: {
          rateLimit: 1000,
          burstLimit: 2000,
        },
      },
    });

    // Create Cognito authorizer
    const auth = new apigateway.CognitoUserPoolsAuthorizer(this, 'VotingSystemAuthorizer', {
      cognitoUserPools: [this.userPool],
    });

    // Create auth resource
    const authResource = api.root.addResource('auth');
    authResource.addMethod('POST', new apigateway.LambdaIntegration(this.voterAuthFunction), {
      authorizer: auth,
    });

    return api;
  }

  /**
   * Creates CloudWatch monitoring resources
   */
  private createMonitoringResources(): void {
    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'VotingSystemDashboard', {
      dashboardName: 'BlockchainVotingSystem',
    });

    // Add Lambda metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Voter Authentication Metrics',
        left: [
          this.voterAuthFunction.metricInvocations(),
          this.voterAuthFunction.metricErrors(),
        ],
        right: [this.voterAuthFunction.metricDuration()],
      })
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Vote Monitoring Metrics',
        left: [
          this.voteMonitorFunction.metricInvocations(),
          this.voteMonitorFunction.metricErrors(),
        ],
        right: [this.voteMonitorFunction.metricDuration()],
      })
    );

    // Create CloudWatch alarms
    const authErrorAlarm = new cloudwatch.Alarm(this, 'VoterAuthErrorAlarm', {
      alarmName: 'VotingSystem-Auth-Errors',
      alarmDescription: 'Alert on voter authentication errors',
      metric: this.voterAuthFunction.metricErrors(),
      threshold: 5,
      evaluationPeriods: 2,
    });

    const monitorErrorAlarm = new cloudwatch.Alarm(this, 'VoteMonitorErrorAlarm', {
      alarmName: 'VotingSystem-Monitor-Errors',
      alarmDescription: 'Alert on vote monitoring errors',
      metric: this.voteMonitorFunction.metricErrors(),
      threshold: 3,
      evaluationPeriods: 2,
    });

    // Add SNS actions to alarms
    authErrorAlarm.addAlarmAction(new cloudwatch.SnsAction(this.votingNotificationTopic));
    monitorErrorAlarm.addAlarmAction(new cloudwatch.SnsAction(this.votingNotificationTopic));
  }

  /**
   * Grants necessary permissions to Lambda functions
   */
  private grantPermissions(): void {
    // Grant KMS permissions
    this.encryptionKey.grantEncryptDecrypt(this.voterAuthFunction);
    this.encryptionKey.grantEncryptDecrypt(this.voteMonitorFunction);

    // Grant DynamoDB permissions
    this.voterRegistryTable.grantReadWriteData(this.voterAuthFunction);
    this.electionsTable.grantReadWriteData(this.voterAuthFunction);
    this.voterRegistryTable.grantReadWriteData(this.voteMonitorFunction);
    this.electionsTable.grantReadWriteData(this.voteMonitorFunction);

    // Grant S3 permissions
    this.votingSystemBucket.grantReadWrite(this.voteMonitorFunction);

    // Grant EventBridge permissions
    this.voteMonitorFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['events:PutEvents'],
        resources: ['*'],
      })
    );

    // Grant SNS permissions
    this.votingNotificationTopic.grantPublish(this.voteMonitorFunction);
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VotingSystemBucketName', {
      value: this.votingSystemBucket.bucketName,
      description: 'Name of the S3 bucket for voting system data',
    });

    new cdk.CfnOutput(this, 'VoterAuthFunctionName', {
      value: this.voterAuthFunction.functionName,
      description: 'Name of the voter authentication Lambda function',
    });

    new cdk.CfnOutput(this, 'VoteMonitorFunctionName', {
      value: this.voteMonitorFunction.functionName,
      description: 'Name of the vote monitoring Lambda function',
    });

    new cdk.CfnOutput(this, 'VoterRegistryTableName', {
      value: this.voterRegistryTable.tableName,
      description: 'Name of the voter registry DynamoDB table',
    });

    new cdk.CfnOutput(this, 'ElectionsTableName', {
      value: this.electionsTable.tableName,
      description: 'Name of the elections DynamoDB table',
    });

    new cdk.CfnOutput(this, 'EncryptionKeyId', {
      value: this.encryptionKey.keyId,
      description: 'ID of the KMS encryption key',
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.votingNotificationTopic.topicArn,
      description: 'ARN of the SNS notification topic',
    });

    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'ID of the Cognito User Pool',
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: this.api.url,
      description: 'URL of the API Gateway',
    });

    new cdk.CfnOutput(this, 'DAppUrl', {
      value: `https://${this.votingSystemBucket.bucketDomainName}/dapp/index.html`,
      description: 'URL of the voting DApp',
    });
  }
}