#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as config from 'aws-cdk-lib/aws-config';
import * as guardduty from 'aws-cdk-lib/aws-guardduty';
import * as securityhub from 'aws-cdk-lib/aws-securityhub';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as inspector from 'aws-cdk-lib/aws-inspector';

/**
 * Zero Trust Security Architecture Stack
 * 
 * This stack implements a comprehensive zero trust security architecture using AWS services
 * including Security Hub, GuardDuty, Config, IAM Identity Center integration, and advanced
 * monitoring capabilities.
 */
export class ZeroTrustSecurityStack extends cdk.Stack {
  public readonly securityBucket: s3.Bucket;
  public readonly zeroTrustKmsKey: kms.Key;
  public readonly zeroTrustVpc: ec2.Vpc;
  public readonly guardDutyDetector: guardduty.CfnDetector;
  public readonly configRecorder: config.CfnConfigurationRecorder;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const resourcePrefix = `zero-trust-${randomSuffix}`;

    // Create KMS key for zero trust encryption with comprehensive policies
    this.zeroTrustKmsKey = new kms.Key(this, 'ZeroTrustKMSKey', {
      description: 'Zero Trust Security Architecture Master Key',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'EnableIAMUserPermissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowZeroTrustServices',
            effect: iam.Effect.ALLOW,
            principals: [
              new iam.ServicePrincipal('s3.amazonaws.com'),
              new iam.ServicePrincipal('secretsmanager.amazonaws.com'),
              new iam.ServicePrincipal('rds.amazonaws.com'),
              new iam.ServicePrincipal('logs.amazonaws.com'),
            ],
            actions: [
              'kms:Decrypt',
              'kms:Encrypt',
              'kms:GenerateDataKey',
              'kms:ReEncrypt*',
              'kms:CreateGrant',
              'kms:DescribeKey',
            ],
            resources: ['*'],
            conditions: {
              StringEquals: {
                'kms:ViaService': [
                  `s3.${this.region}.amazonaws.com`,
                  `secretsmanager.${this.region}.amazonaws.com`,
                  `rds.${this.region}.amazonaws.com`,
                  `logs.${this.region}.amazonaws.com`,
                ],
              },
            },
          }),
        ],
      }),
    });

    // Create KMS key alias for easier reference
    new kms.Alias(this, 'ZeroTrustKMSAlias', {
      aliasName: `alias/${resourcePrefix}-key`,
      targetKey: this.zeroTrustKmsKey,
    });

    // Create S3 bucket for security logs with comprehensive security controls
    this.securityBucket = new s3.Bucket(this, 'SecurityLogsBucket', {
      bucketName: `${resourcePrefix}-security-logs-${this.account}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.zeroTrustKmsKey,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'SecurityLogsLifecycle',
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
          expiration: cdk.Duration.days(2555), // 7 years retention
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create secure S3 bucket for sensitive data with zero trust controls
    const secureDataBucket = new s3.Bucket(this, 'SecureDataBucket', {
      bucketName: `${resourcePrefix}-secure-data-${this.account}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.zeroTrustKmsKey,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create zero trust VPC with private-only architecture
    this.zeroTrustVpc = new ec2.Vpc(this, 'ZeroTrustVPC', {
      vpcName: `${resourcePrefix}-vpc`,
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'ZeroTrustPrivate',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create VPC endpoints for AWS services (avoid internet gateway)
    const s3VpcEndpoint = this.zeroTrustVpc.addGatewayEndpoint('S3Endpoint', {
      service: ec2.GatewayVpcEndpointAwsService.S3,
      policyDocument: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
            actions: ['s3:GetObject', 's3:PutObject'],
            resources: [
              `${this.securityBucket.bucketArn}/*`,
              `${secureDataBucket.bucketArn}/*`,
            ],
            conditions: {
              StringEquals: {
                's3:x-amz-server-side-encryption': 'aws:kms',
              },
            },
          }),
        ],
      }),
    });

    // Create restrictive security group for zero trust access
    const zeroTrustSecurityGroup = new ec2.SecurityGroup(this, 'ZeroTrustSecurityGroup', {
      vpc: this.zeroTrustVpc,
      securityGroupName: `${resourcePrefix}-zero-trust-sg`,
      description: 'Zero Trust Security Group with minimal access',
      allowAllOutbound: false,
    });

    // Add only necessary outbound rules for HTTPS
    zeroTrustSecurityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS outbound for AWS API calls'
    );

    // Add self-referencing rule for internal communication
    zeroTrustSecurityGroup.addIngressRule(
      zeroTrustSecurityGroup,
      ec2.Port.tcp(443),
      'Allow HTTPS within security group'
    );

    // Enable AWS Security Hub with foundational standards
    const securityHub = new securityhub.CfnHub(this, 'SecurityHub', {
      tags: [
        {
          key: 'Purpose',
          value: 'ZeroTrustSecurity',
        },
      ],
    });

    // Enable foundational security standards
    new securityhub.CfnStandard(this, 'FoundationalStandard', {
      standardsArn: `arn:aws:securityhub:${this.region}::standard/aws-foundational-security/v/1.0.0`,
      disabledStandardsControls: [], // Enable all controls
    });

    // Enable CIS AWS Foundations Benchmark
    new securityhub.CfnStandard(this, 'CISStandard', {
      standardsArn: `arn:aws:securityhub:${this.region}::standard/cis-aws-foundations-benchmark/v/1.2.0`,
      disabledStandardsControls: [],
    });

    // Enable Amazon GuardDuty for intelligent threat detection
    this.guardDutyDetector = new guardduty.CfnDetector(this, 'GuardDutyDetector', {
      enable: true,
      findingPublishingFrequency: 'FIFTEEN_MINUTES',
      dataSources: {
        s3Logs: {
          enable: true,
        },
        kubernetesConfiguration: {
          auditLogs: {
            enable: true,
          },
        },
        malwareProtection: {
          scanEc2InstanceWithFindings: {
            ebsVolumes: true,
          },
        },
      },
      tags: [
        {
          key: 'Purpose',
          value: 'ZeroTrustThreatDetection',
        },
      ],
    });

    // Create IAM role for AWS Config
    const configRole = new iam.Role(this, 'ConfigServiceRole', {
      roleName: `${resourcePrefix}-config-role`,
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
    });

    // Create Config delivery channel
    const configDeliveryChannel = new config.CfnDeliveryChannel(this, 'ConfigDeliveryChannel', {
      name: 'zero-trust-config-channel',
      s3BucketName: this.securityBucket.bucketName,
      s3KeyPrefix: 'config/',
      configSnapshotDeliveryProperties: {
        deliveryFrequency: 'TwentyFour_Hours',
      },
    });

    // Create Config configuration recorder
    this.configRecorder = new config.CfnConfigurationRecorder(this, 'ConfigRecorder', {
      name: 'zero-trust-config-recorder',
      roleArn: configRole.roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
        recordingModeOverrides: [
          {
            resourceTypes: ['AWS::IAM::Role', 'AWS::IAM::Policy'],
            recordingMode: {
              recordingFrequency: 'CONTINUOUS',
            },
          },
        ],
      },
    });

    // Ensure delivery channel is created before recorder
    this.configRecorder.addDependency(configDeliveryChannel);

    // Create zero trust boundary policy with conditional access
    const zeroTrustBoundaryPolicy = new iam.ManagedPolicy(this, 'ZeroTrustBoundaryPolicy', {
      managedPolicyName: `${resourcePrefix}-boundary-policy`,
      description: 'Zero Trust Security Boundary Policy with conditional access',
      document: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'EnforceMFAForAllActions',
            effect: iam.Effect.DENY,
            actions: ['*'],
            resources: ['*'],
            conditions: {
              BoolIfExists: {
                'aws:MultiFactorAuthPresent': 'false',
              },
              NumericLessThan: {
                'aws:MultiFactorAuthAge': '3600',
              },
            },
          }),
          new iam.PolicyStatement({
            sid: 'EnforceSSLRequests',
            effect: iam.Effect.DENY,
            actions: ['s3:*'],
            resources: ['*'],
            conditions: {
              Bool: {
                'aws:SecureTransport': 'false',
              },
            },
          }),
          new iam.PolicyStatement({
            sid: 'RestrictHighRiskActions',
            effect: iam.Effect.DENY,
            actions: [
              'iam:CreateUser',
              'iam:DeleteUser',
              'iam:CreateRole',
              'iam:DeleteRole',
              'iam:AttachUserPolicy',
              'iam:DetachUserPolicy',
              'iam:AttachRolePolicy',
              'iam:DetachRolePolicy',
            ],
            resources: ['*'],
            conditions: {
              StringNotEquals: {
                'aws:RequestedRegion': ['us-east-1', 'us-west-2'],
              },
            },
          }),
        ],
      }),
    });

    // Create zero trust security roles with permissions boundaries
    const securityRole = new iam.Role(this, 'ZeroTrustSecurityRole', {
      roleName: `${resourcePrefix}-security-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      permissionsBoundary: zeroTrustBoundaryPolicy,
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('SecurityAudit'),
      ],
      inlinePolicies: {
        SessionManagement: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:TerminateSession',
                'ssm:DescribeSessions',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch log group for zero trust events
    const zeroTrustLogGroup = new logs.LogGroup(this, 'ZeroTrustLogGroup', {
      logGroupName: `/aws/zero-trust/${resourcePrefix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      encryptionKey: this.zeroTrustKmsKey,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create session verification Lambda function
    const sessionVerificationFunction = new lambda.Function(this, 'SessionVerificationFunction', {
      functionName: `${resourcePrefix}-session-verification`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: securityRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        LOG_GROUP_NAME: zeroTrustLogGroup.logGroupName,
        KMS_KEY_ID: this.zeroTrustKmsKey.keyId,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Continuous session verification for zero trust architecture
    """
    try:
        # Parse session details from event
        session_id = event.get('sessionId', '')
        user_id = event.get('userId', '')
        source_ip = event.get('sourceIp', '')
        
        logger.info(f"Verifying session {session_id} for user {user_id} from {source_ip}")
        
        # Verify session integrity
        if not verify_session_integrity(session_id, user_id, source_ip):
            terminate_session(session_id)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'action': 'terminated',
                    'reason': 'session_integrity_violation',
                    'sessionId': session_id
                })
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'action': 'verified',
                'sessionId': session_id,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Session verification failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def verify_session_integrity(session_id, user_id, source_ip):
    """
    Verify session integrity based on zero trust principles
    """
    # Check for suspicious patterns
    if not session_id or not user_id:
        return False
    
    # Verify IP address is not from suspicious ranges
    suspicious_ranges = ['0.0.0.0', '127.0.0.1']
    if source_ip in suspicious_ranges:
        return False
    
    # Additional verification logic would go here
    # - Check session duration
    # - Verify geolocation consistency
    # - Check for concurrent sessions
    # - Validate device fingerprint
    
    return True

def terminate_session(session_id):
    """
    Terminate session for security violation
    """
    try:
        ssm = boto3.client('ssm')
        ssm.terminate_session(SessionId=session_id)
        logger.info(f"Terminated session {session_id} for security violation")
    except Exception as e:
        logger.error(f"Failed to terminate session {session_id}: {str(e)}")
`),
    });

    // Create SNS topic for zero trust security alerts
    const alertTopic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `${resourcePrefix}-security-alerts`,
      displayName: 'Zero Trust Security Alerts',
      masterKey: this.zeroTrustKmsKey,
    });

    // Create CloudWatch alarms for zero trust violations
    const failedLoginsAlarm = new cloudwatch.Alarm(this, 'FailedLoginsAlarm', {
      alarmName: `${resourcePrefix}-failed-logins`,
      alarmDescription: 'Zero Trust: Multiple failed login attempts detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudTrail',
        metricName: 'ConsoleLogin',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
    });

    failedLoginsAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertTopic)
    );

    // Create Config rules for zero trust compliance
    new config.CfnConfigRule(this, 'MFAEnabledRule', {
      configRuleName: 'zero-trust-mfa-enabled',
      description: 'Checks if MFA is enabled for all IAM users',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS',
      },
      dependsOn: [this.configRecorder],
    });

    new config.CfnConfigRule(this, 'S3SSLRequestsOnlyRule', {
      configRuleName: 'zero-trust-s3-bucket-ssl-requests-only',
      description: 'Checks if S3 buckets have policies requiring SSL requests only',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'S3_BUCKET_SSL_REQUESTS_ONLY',
      },
      dependsOn: [this.configRecorder],
    });

    // Create SSM document for session preferences
    new ssm.CfnDocument(this, 'SessionPreferencesDocument', {
      name: `${resourcePrefix}-session-preferences`,
      documentType: 'Session',
      documentFormat: 'JSON',
      content: {
        schemaVersion: '1.0',
        description: 'Zero Trust Session Manager Preferences',
        sessionType: 'Standard_Stream',
        inputs: {
          s3BucketName: this.securityBucket.bucketName,
          s3KeyPrefix: 'session-logs/',
          s3EncryptionEnabled: true,
          cloudWatchLogGroupName: zeroTrustLogGroup.logGroupName,
          cloudWatchEncryptionEnabled: true,
          kmsKeyId: this.zeroTrustKmsKey.keyId,
          shellProfile: {
            linux: 'cd /tmp && echo "Zero Trust Session Started at $(date)" && export PS1="[ZT]\\u@\\h:\\w\\$ "',
            windows: 'cd C:\\temp && echo Zero Trust Session Started at %DATE% %TIME%',
          },
        },
      },
    });

    // Create CloudWatch dashboard for zero trust monitoring
    new cloudwatch.Dashboard(this, 'ZeroTrustDashboard', {
      dashboardName: `${resourcePrefix}-security-dashboard`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Security Hub Findings',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/SecurityHub',
                metricName: 'Findings',
                dimensionsMap: {
                  ComplianceType: 'FAILED',
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'GuardDuty Findings',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/GuardDuty',
                metricName: 'Findings',
                dimensionsMap: {
                  Severity: 'HIGH',
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Purpose', 'ZeroTrustSecurity');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('ResourcePrefix', resourcePrefix);
  }
}

/**
 * CDK App definition
 */
const app = new cdk.App();

new ZeroTrustSecurityStack(app, 'ZeroTrustSecurityStack', {
  description: 'Zero Trust Security Architecture implementation using AWS services',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ZeroTrustSecurity',
    Environment: 'Demo',
    ManagedBy: 'CDK',
  },
});

app.synth();