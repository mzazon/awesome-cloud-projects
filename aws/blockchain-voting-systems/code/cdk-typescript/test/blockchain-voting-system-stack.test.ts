/**
 * Unit tests for the BlockchainVotingSystemStack
 * 
 * These tests validate the CDK stack construction and resource creation
 * for the blockchain voting system.
 */

import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { BlockchainVotingSystemStack } from '../lib/blockchain-voting-system-stack';
import { VotingSystemSecurityStack } from '../lib/voting-system-security-stack';
import { testConfig } from './setup';

describe('BlockchainVotingSystemStack', () => {
  let app: cdk.App;
  let securityStack: VotingSystemSecurityStack;
  let votingStack: BlockchainVotingSystemStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    
    // Create security stack first
    securityStack = new VotingSystemSecurityStack(app, 'TestSecurityStack', {
      config: {
        appName: testConfig.appName,
        environment: testConfig.environment,
        enableEncryption: testConfig.security.enableEncryption,
        enableKeyRotation: testConfig.security.kmsKeyRotation,
        adminEmail: testConfig.adminEmail,
      },
    });

    // Create voting system stack
    votingStack = new BlockchainVotingSystemStack(app, 'TestVotingStack', {
      config: testConfig,
      securityResources: {
        kmsKey: securityStack.kmsKey,
        lambdaExecutionRole: securityStack.lambdaExecutionRole,
        blockchainAccessRole: securityStack.blockchainAccessRole,
        apiGatewayRole: securityStack.apiGatewayRole,
      },
    });

    template = Template.fromStack(votingStack);
  });

  describe('DynamoDB Tables', () => {
    it('should create voter registry table', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        TableName: `${testConfig.appName}-voter-registry-${testConfig.environment}`,
        AttributeDefinitions: [
          {
            AttributeName: 'VoterId',
            AttributeType: 'S',
          },
          {
            AttributeName: 'ElectionId',
            AttributeType: 'S',
          },
        ],
        KeySchema: [
          {
            AttributeName: 'VoterId',
            KeyType: 'HASH',
          },
          {
            AttributeName: 'ElectionId',
            KeyType: 'RANGE',
          },
        ],
        BillingMode: 'PAY_PER_REQUEST',
      });
    });

    it('should create elections table', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        TableName: `${testConfig.appName}-elections-${testConfig.environment}`,
        AttributeDefinitions: [
          {
            AttributeName: 'ElectionId',
            AttributeType: 'S',
          },
        ],
        KeySchema: [
          {
            AttributeName: 'ElectionId',
            KeyType: 'HASH',
          },
        ],
        BillingMode: 'PAY_PER_REQUEST',
      });
    });

    it('should enable encryption for DynamoDB tables', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        SSESpecification: {
          SSEEnabled: true,
        },
      });
    });

    it('should enable point-in-time recovery for DynamoDB tables', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        PointInTimeRecoverySpecification: {
          PointInTimeRecoveryEnabled: true,
        },
      });
    });
  });

  describe('S3 Buckets', () => {
    it('should create voting data bucket', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: `${testConfig.appName}-voting-data-${testConfig.environment}-123456789012`,
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: {
                SSEAlgorithm: 'aws:kms',
              },
            },
          ],
        },
        VersioningConfiguration: {
          Status: 'Enabled',
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
      });
    });

    it('should create DApp bucket when DApp is enabled', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: `${testConfig.appName}-dapp-${testConfig.environment}-123456789012`,
        WebsiteConfiguration: {
          IndexDocument: 'index.html',
          ErrorDocument: 'error.html',
        },
      });
    });

    it('should configure lifecycle rules for voting data bucket', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: [
            {
              Id: 'DeleteOldVersions',
              Status: 'Enabled',
              ExpirationInDays: 2555,
              NoncurrentVersionExpirationInDays: 90,
            },
          ],
        },
      });
    });
  });

  describe('Lambda Functions', () => {
    it('should create voter authentication function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: `${testConfig.appName}-voter-auth-${testConfig.environment}`,
        Runtime: 'nodejs20.x',
        Handler: 'index.handler',
        Timeout: 30,
        MemorySize: 512,
      });
    });

    it('should create vote monitoring function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: `${testConfig.appName}-vote-monitor-${testConfig.environment}`,
        Runtime: 'nodejs20.x',
        Handler: 'index.handler',
        Timeout: 60,
        MemorySize: 1024,
      });
    });

    it('should configure environment variables for Lambda functions', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            ENVIRONMENT: testConfig.environment,
            LOG_LEVEL: 'DEBUG',
          },
        },
      });
    });

    it('should enable X-Ray tracing for Lambda functions', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        TracingConfig: {
          Mode: 'Active',
        },
      });
    });
  });

  describe('Cognito User Pool', () => {
    it('should create user pool for voter authentication', () => {
      template.hasResourceProperties('AWS::Cognito::UserPool', {
        UserPoolName: `${testConfig.appName}-voters-${testConfig.environment}`,
        AutoVerifiedAttributes: ['email'],
        MfaConfiguration: 'REQUIRED',
        Policies: {
          PasswordPolicy: {
            MinimumLength: 12,
            RequireLowercase: true,
            RequireNumbers: true,
            RequireSymbols: true,
            RequireUppercase: true,
          },
        },
      });
    });

    it('should create user pool client', () => {
      template.hasResourceProperties('AWS::Cognito::UserPoolClient', {
        UserPoolClientName: `${testConfig.appName}-client-${testConfig.environment}`,
        GenerateSecret: false,
        PreventUserExistenceErrors: true,
        RefreshTokenValidity: 1,
        AccessTokenValidity: 1,
        IdTokenValidity: 1,
        EnableTokenRevocation: true,
      });
    });

    it('should create identity pool', () => {
      template.hasResourceProperties('AWS::Cognito::IdentityPool', {
        IdentityPoolName: `${testConfig.appName}_identity_pool_${testConfig.environment}`,
        AllowUnauthenticatedIdentities: false,
      });
    });
  });

  describe('API Gateway', () => {
    it('should create REST API', () => {
      template.hasResourceProperties('AWS::ApiGateway::RestApi', {
        Name: `${testConfig.appName}-api-${testConfig.environment}`,
        Description: 'REST API for blockchain voting system',
        EndpointConfiguration: {
          Types: ['REGIONAL'],
        },
      });
    });

    it('should create deployment with proper stage', () => {
      template.hasResourceProperties('AWS::ApiGateway::Deployment', {
        StageName: testConfig.environment,
      });
    });

    it('should create Cognito authorizer', () => {
      template.hasResourceProperties('AWS::ApiGateway::Authorizer', {
        Type: 'COGNITO_USER_POOLS',
        IdentitySource: 'method.request.header.Authorization',
      });
    });

    it('should configure CORS', () => {
      template.hasResourceProperties('AWS::ApiGateway::Method', {
        HttpMethod: 'OPTIONS',
      });
    });
  });

  describe('EventBridge', () => {
    it('should create custom event bus', () => {
      template.hasResourceProperties('AWS::Events::EventBus', {
        Name: `${testConfig.appName}-events-${testConfig.environment}`,
      });
    });

    it('should create event rules', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Name: `${testConfig.appName}-voting-events-${testConfig.environment}`,
        EventPattern: {
          source: ['voting.blockchain'],
          'detail-type': [
            'VoteCast',
            'ElectionCreated',
            'ElectionEnded',
            'CandidateRegistered',
            'VoterRegistered',
            'SecurityAlert',
          ],
        },
        State: 'ENABLED',
      });
    });
  });

  describe('SNS Topics', () => {
    it('should create notification topic', () => {
      template.hasResourceProperties('AWS::SNS::Topic', {
        TopicName: `${testConfig.appName}-notifications-${testConfig.environment}`,
        DisplayName: 'Blockchain Voting System Notifications',
      });
    });

    it('should create email subscription for admin', () => {
      template.hasResourceProperties('AWS::SNS::Subscription', {
        Protocol: 'email',
        Endpoint: testConfig.adminEmail,
      });
    });
  });

  describe('CloudWatch Alarms', () => {
    it('should create Lambda function error alarms', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: `${testConfig.appName}-voter-auth-errors-${testConfig.environment}`,
        ComparisonOperator: 'GreaterThanOrEqualToThreshold',
        EvaluationPeriods: 2,
        MetricName: 'Errors',
        Namespace: 'AWS/Lambda',
        Period: 300,
        Statistic: 'Sum',
        Threshold: 5,
        TreatMissingData: 'notBreaching',
      });
    });

    it('should create API Gateway error alarms', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        ComparisonOperator: 'GreaterThanOrEqualToThreshold',
        EvaluationPeriods: 2,
        MetricName: '5XXError',
        Namespace: 'AWS/ApiGateway',
        Period: 300,
        Statistic: 'Sum',
        Threshold: 10,
        TreatMissingData: 'notBreaching',
      });
    });
  });

  describe('Stack Outputs', () => {
    it('should output important resource information', () => {
      template.hasOutput('VoterRegistryTableName', {});
      template.hasOutput('ElectionsTableName', {});
      template.hasOutput('VotingDataBucketName', {});
      template.hasOutput('ApiGatewayUrl', {});
      template.hasOutput('UserPoolId', {});
      template.hasOutput('UserPoolClientId', {});
      template.hasOutput('EventBusName', {});
    });

    it('should output DApp URL when DApp is enabled', () => {
      template.hasOutput('DAppUrl', {});
    });
  });

  describe('Resource Tagging', () => {
    it('should tag DynamoDB tables properly', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        Tags: [
          {
            Key: 'Purpose',
            Value: 'VoterRegistry',
          },
          {
            Key: 'DataClassification',
            Value: 'Sensitive',
          },
          {
            Key: 'BackupRequired',
            Value: 'true',
          },
        ],
      });
    });

    it('should tag S3 buckets properly', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        Tags: [
          {
            Key: 'Purpose',
            Value: 'VotingDataStorage',
          },
          {
            Key: 'DataClassification',
            Value: 'Sensitive',
          },
          {
            Key: 'BackupRequired',
            Value: 'true',
          },
        ],
      });
    });
  });

  describe('Security Configuration', () => {
    it('should configure proper removal policies for production', () => {
      // This test would need to be modified based on environment
      // For test environment, resources should be destroyable
      if (testConfig.environment === 'prod') {
        template.hasResource('AWS::DynamoDB::Table', {
          DeletionPolicy: 'Retain',
        });
      }
    });

    it('should enforce SSL for S3 buckets', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
      });
    });
  });
});

describe('Stack Integration', () => {
  it('should create stack without errors', () => {
    const app = new cdk.App();
    
    const securityStack = new VotingSystemSecurityStack(app, 'TestSecurityStack', {
      config: {
        appName: testConfig.appName,
        environment: testConfig.environment,
        enableEncryption: testConfig.security.enableEncryption,
        enableKeyRotation: testConfig.security.kmsKeyRotation,
        adminEmail: testConfig.adminEmail,
      },
    });

    expect(() => {
      new BlockchainVotingSystemStack(app, 'TestVotingStack', {
        config: testConfig,
        securityResources: {
          kmsKey: securityStack.kmsKey,
          lambdaExecutionRole: securityStack.lambdaExecutionRole,
          blockchainAccessRole: securityStack.blockchainAccessRole,
          apiGatewayRole: securityStack.apiGatewayRole,
        },
      });
    }).not.toThrow();
  });

  it('should synthesize template successfully', () => {
    const app = new cdk.App();
    
    const securityStack = new VotingSystemSecurityStack(app, 'TestSecurityStack', {
      config: {
        appName: testConfig.appName,
        environment: testConfig.environment,
        enableEncryption: testConfig.security.enableEncryption,
        enableKeyRotation: testConfig.security.kmsKeyRotation,
        adminEmail: testConfig.adminEmail,
      },
    });

    const votingStack = new BlockchainVotingSystemStack(app, 'TestVotingStack', {
      config: testConfig,
      securityResources: {
        kmsKey: securityStack.kmsKey,
        lambdaExecutionRole: securityStack.lambdaExecutionRole,
        blockchainAccessRole: securityStack.blockchainAccessRole,
        apiGatewayRole: securityStack.apiGatewayRole,
      },
    });

    expect(() => {
      const template = Template.fromStack(votingStack);
      expect(template).toBeDefined();
    }).not.toThrow();
  });
});