#!/usr/bin/env node
/**
 * AWS CDK TypeScript Application for Container Secrets Management
 * 
 * This application demonstrates secure container secrets management using AWS Secrets Manager
 * integrated with both ECS and EKS environments. It provides centralized secret storage,
 * automatic rotation, and fine-grained access control through IAM policies.
 * 
 * Features:
 * - AWS Secrets Manager for centralized secret storage
 * - KMS encryption for secrets at rest
 * - IAM roles for secure access (ECS task roles and EKS IRSA)
 * - Lambda function for automatic secret rotation
 * - CloudWatch monitoring and alerting
 * - ECS cluster with Fargate support
 * - EKS cluster with OIDC provider for IRSA
 * - Security best practices throughout
 */

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as path from 'path';

interface ContainerSecretsStackProps extends cdk.StackProps {
  /**
   * Environment name for resource naming
   */
  environment?: string;
  
  /**
   * Whether to create EKS cluster (can be disabled for cost savings)
   */
  createEksCluster?: boolean;
  
  /**
   * VPC to use for resources (optional - will create new VPC if not provided)
   */
  vpc?: ec2.IVpc;
  
  /**
   * Secret rotation schedule in days
   */
  rotationScheduleDays?: number;
  
  /**
   * CloudWatch log retention in days
   */
  logRetentionDays?: number;
}

export class ContainerSecretsStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly encryptionKey: kms.IKey;
  public readonly databaseSecret: secretsmanager.ISecret;
  public readonly apiSecret: secretsmanager.ISecret;
  public readonly ecsCluster: ecs.ICluster;
  public readonly eksCluster?: eks.ICluster;
  public readonly rotationFunction: lambda.IFunction;
  public readonly alertTopic: sns.ITopic;

  constructor(scope: Construct, id: string, props: ContainerSecretsStackProps = {}) {
    super(scope, id, props);

    // Extract configuration from props
    const environment = props.environment || 'demo';
    const createEksCluster = props.createEksCluster ?? true;
    const rotationScheduleDays = props.rotationScheduleDays || 30;
    const logRetentionDays = props.logRetentionDays || 30;

    // Create VPC or use existing one
    this.vpc = props.vpc || new ec2.Vpc(this, 'Vpc', {
      maxAzs: 3,
      natGateways: 1,
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
      ],
    });

    // Create KMS key for encryption
    this.encryptionKey = new kms.Key(this, 'SecretsEncryptionKey', {
      description: 'KMS key for encrypting secrets in Secrets Manager',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create KMS key alias for easier reference
    new kms.Alias(this, 'SecretsEncryptionKeyAlias', {
      aliasName: `alias/secrets-manager-${environment}`,
      targetKey: this.encryptionKey,
    });

    // Create database credentials secret
    this.databaseSecret = new secretsmanager.Secret(this, 'DatabaseSecret', {
      description: 'Database credentials for demo application',
      encryptionKey: this.encryptionKey,
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          username: 'appuser',
          host: 'demo-db.cluster-xyz.us-west-2.rds.amazonaws.com',
          port: '5432',
          database: 'appdb',
        }),
        generateStringKey: 'password',
        excludeCharacters: ' "\'@/\\',
        passwordLength: 32,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create API keys secret
    this.apiSecret = new secretsmanager.Secret(this, 'ApiSecret', {
      description: 'API keys for external services',
      encryptionKey: this.encryptionKey,
      secretObjectValue: {
        github_token: cdk.SecretValue.unsafePlainText('ghp_example_token'),
        stripe_key: cdk.SecretValue.unsafePlainText('sk_test_example_key'),
        twilio_sid: cdk.SecretValue.unsafePlainText('AC_example_sid'),
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for alerts
    this.alertTopic = new sns.Topic(this, 'AlertTopic', {
      displayName: 'Container Secrets Alerts',
      topicName: `container-secrets-alerts-${environment}`,
    });

    // Create ECS infrastructure
    this.createEcsInfrastructure(environment, logRetentionDays);

    // Create EKS infrastructure (optional)
    if (createEksCluster) {
      this.eksCluster = this.createEksInfrastructure(environment);
    }

    // Create Lambda function for secret rotation
    this.rotationFunction = this.createRotationFunction(environment, logRetentionDays);

    // Configure automatic secret rotation
    this.configureSecretRotation(rotationScheduleDays);

    // Create monitoring and alerting
    this.createMonitoringAndAlerting(environment);

    // Output important values
    this.createOutputs(environment);
  }

  /**
   * Creates ECS infrastructure including cluster, task definition, and IAM roles
   */
  private createEcsInfrastructure(environment: string, logRetentionDays: number): void {
    // Create ECS cluster
    this.ecsCluster = new ecs.Cluster(this, 'EcsCluster', {
      vpc: this.vpc,
      clusterName: `secrets-${environment}-cluster`,
      containerInsights: true,
    });

    // Create CloudWatch log group for ECS
    const ecsLogGroup = new logs.LogGroup(this, 'EcsLogGroup', {
      logGroupName: `/ecs/secrets-${environment}`,
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for ECS task execution
    const ecsTaskExecutionRole = new iam.Role(this, 'EcsTaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Create IAM role for ECS task
    const ecsTaskRole = new iam.Role(this, 'EcsTaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      roleName: `secrets-${environment}-ecs-task-role`,
    });

    // Grant ECS task role access to secrets
    this.databaseSecret.grantRead(ecsTaskRole);
    this.apiSecret.grantRead(ecsTaskRole);
    this.encryptionKey.grantDecrypt(ecsTaskRole);

    // Create ECS task definition
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'EcsTaskDefinition', {
      family: `secrets-${environment}-task`,
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole: ecsTaskExecutionRole,
      taskRole: ecsTaskRole,
    });

    // Add container to task definition with secrets
    const container = taskDefinition.addContainer('DemoApp', {
      image: ecs.ContainerImage.fromRegistry('nginx:latest'),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup: ecsLogGroup,
      }),
      secrets: {
        DB_USERNAME: ecs.Secret.fromSecretsManager(this.databaseSecret, 'username'),
        DB_PASSWORD: ecs.Secret.fromSecretsManager(this.databaseSecret, 'password'),
        DB_HOST: ecs.Secret.fromSecretsManager(this.databaseSecret, 'host'),
        DB_PORT: ecs.Secret.fromSecretsManager(this.databaseSecret, 'port'),
        DB_DATABASE: ecs.Secret.fromSecretsManager(this.databaseSecret, 'database'),
        GITHUB_TOKEN: ecs.Secret.fromSecretsManager(this.apiSecret, 'github_token'),
        STRIPE_KEY: ecs.Secret.fromSecretsManager(this.apiSecret, 'stripe_key'),
        TWILIO_SID: ecs.Secret.fromSecretsManager(this.apiSecret, 'twilio_sid'),
      },
    });

    // Add port mapping
    container.addPortMappings({
      containerPort: 80,
      protocol: ecs.Protocol.TCP,
    });

    // Create ECS service
    new ecs.FargateService(this, 'EcsService', {
      cluster: this.ecsCluster,
      taskDefinition,
      serviceName: `secrets-${environment}-service`,
      desiredCount: 1,
      assignPublicIp: false,
    });
  }

  /**
   * Creates EKS infrastructure including cluster and OIDC provider
   */
  private createEksInfrastructure(environment: string): eks.ICluster {
    // Create EKS cluster
    const eksCluster = new eks.Cluster(this, 'EksCluster', {
      vpc: this.vpc,
      clusterName: `secrets-${environment}-eks`,
      version: eks.KubernetesVersion.V1_28,
      defaultCapacity: 2,
      defaultCapacityInstance: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
    });

    // Create namespace for demo application
    eksCluster.addManifest('DemoNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'demo-app',
        labels: {
          name: 'demo-app',
        },
      },
    });

    // Create service account for pods with IRSA
    const serviceAccount = eksCluster.addServiceAccount('SecretsServiceAccount', {
      name: 'secrets-demo-sa',
      namespace: 'demo-app',
    });

    // Grant service account access to secrets
    this.databaseSecret.grantRead(serviceAccount);
    this.apiSecret.grantRead(serviceAccount);
    this.encryptionKey.grantDecrypt(serviceAccount);

    // Install Secrets Store CSI Driver
    eksCluster.addHelmChart('SecretsStoreCsiDriver', {
      chart: 'secrets-store-csi-driver',
      repository: 'https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts',
      namespace: 'kube-system',
      values: {
        syncSecret: {
          enabled: true,
        },
        enableSecretRotation: true,
      },
    });

    // Install AWS Secrets Manager provider
    eksCluster.addHelmChart('AwsSecretsProvider', {
      chart: 'secrets-store-csi-driver-provider-aws',
      repository: 'https://aws.github.io/secrets-store-csi-driver-provider-aws',
      namespace: 'kube-system',
    });

    // Create SecretProviderClass
    eksCluster.addManifest('SecretProviderClass', {
      apiVersion: 'secrets-store.csi.x-k8s.io/v1',
      kind: 'SecretProviderClass',
      metadata: {
        name: 'demo-secrets-provider',
        namespace: 'demo-app',
      },
      spec: {
        provider: 'aws',
        parameters: {
          objects: `
            - objectName: "${this.databaseSecret.secretName}"
              objectType: "secretsmanager"
              jmesPath:
                - path: "username"
                  objectAlias: "db_username"
                - path: "password"
                  objectAlias: "db_password"
                - path: "host"
                  objectAlias: "db_host"
                - path: "port"
                  objectAlias: "db_port"
                - path: "database"
                  objectAlias: "db_database"
            - objectName: "${this.apiSecret.secretName}"
              objectType: "secretsmanager"
              jmesPath:
                - path: "github_token"
                  objectAlias: "github_token"
                - path: "stripe_key"
                  objectAlias: "stripe_key"
                - path: "twilio_sid"
                  objectAlias: "twilio_sid"
          `,
        },
      },
    });

    // Create demo application deployment
    eksCluster.addManifest('DemoAppDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'demo-app',
        namespace: 'demo-app',
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'demo-app',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'demo-app',
            },
          },
          spec: {
            serviceAccountName: 'secrets-demo-sa',
            containers: [{
              name: 'demo-app',
              image: 'nginx:latest',
              ports: [{
                containerPort: 80,
              }],
              volumeMounts: [{
                name: 'secrets-store',
                mountPath: '/mnt/secrets',
                readOnly: true,
              }],
              env: [
                {
                  name: 'DB_USERNAME',
                  valueFrom: {
                    secretKeyRef: {
                      name: 'demo-secrets',
                      key: 'db_username',
                    },
                  },
                },
                {
                  name: 'DB_PASSWORD',
                  valueFrom: {
                    secretKeyRef: {
                      name: 'demo-secrets',
                      key: 'db_password',
                    },
                  },
                },
                {
                  name: 'DB_HOST',
                  valueFrom: {
                    secretKeyRef: {
                      name: 'demo-secrets',
                      key: 'db_host',
                    },
                  },
                },
              ],
            }],
            volumes: [{
              name: 'secrets-store',
              csi: {
                driver: 'secrets-store.csi.k8s.io',
                readOnly: true,
                volumeAttributes: {
                  secretProviderClass: 'demo-secrets-provider',
                },
              },
            }],
          },
        },
      },
    });

    return eksCluster;
  }

  /**
   * Creates Lambda function for automatic secret rotation
   */
  private createRotationFunction(environment: string, logRetentionDays: number): lambda.IFunction {
    // Create IAM role for Lambda
    const lambdaRole = new iam.Role(this, 'LambdaRotationRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      roleName: `secrets-${environment}-rotation-role`,
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Grant Lambda access to secrets and KMS
    this.databaseSecret.grantRead(lambdaRole);
    this.databaseSecret.grantWrite(lambdaRole);
    this.apiSecret.grantRead(lambdaRole);
    this.apiSecret.grantWrite(lambdaRole);
    this.encryptionKey.grantDecrypt(lambdaRole);
    this.encryptionKey.grantEncrypt(lambdaRole);

    // Grant Lambda permission to generate random passwords
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['secretsmanager:GetRandomPassword'],
      resources: ['*'],
    }));

    // Create Lambda function
    const rotationFunction = new lambda.Function(this, 'RotationFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import boto3
import json
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to rotate secrets in AWS Secrets Manager
    """
    client = boto3.client('secretsmanager')
    
    # Get the secret ARN from the event
    secret_arn = event.get('Step', '')
    
    if not secret_arn:
        logger.error("Secret ARN not found in event")
        raise ValueError("Secret ARN not found in event")
    
    try:
        # Generate new random password
        new_password = client.get_random_password(
            PasswordLength=32,
            ExcludeCharacters='"@/\\\\'
        )['RandomPassword']
        
        # Get current secret
        current_secret = client.get_secret_value(SecretId=secret_arn)
        secret_dict = json.loads(current_secret['SecretString'])
        
        # Update password
        secret_dict['password'] = new_password
        
        # Update secret
        client.update_secret(
            SecretId=secret_arn,
            SecretString=json.dumps(secret_dict)
        )
        
        logger.info(f"Successfully rotated secret: {secret_arn}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Secret rotated successfully',
                'secretArn': secret_arn,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error rotating secret: {str(e)}")
        raise e
`),
      functionName: `secrets-${environment}-rotation`,
      timeout: cdk.Duration.minutes(5),
      role: lambdaRole,
      logRetention: logRetentionDays,
      environment: {
        ENVIRONMENT: environment,
      },
    });

    return rotationFunction;
  }

  /**
   * Configures automatic secret rotation
   */
  private configureSecretRotation(rotationScheduleDays: number): void {
    // Configure rotation for database secret
    this.databaseSecret.addRotationSchedule('DatabaseSecretRotation', {
      rotationLambda: this.rotationFunction,
      automaticallyAfter: cdk.Duration.days(rotationScheduleDays),
    });

    // Create EventBridge rule for rotation monitoring
    const rotationRule = new events.Rule(this, 'RotationEventRule', {
      eventPattern: {
        source: ['aws.secretsmanager'],
        detailType: ['AWS API Call via CloudTrail'],
        detail: {
          eventSource: ['secretsmanager.amazonaws.com'],
          eventName: ['RotateSecret'],
        },
      },
    });

    // Send rotation events to SNS
    rotationRule.addTarget(new targets.SnsTopic(this.alertTopic));
  }

  /**
   * Creates monitoring and alerting infrastructure
   */
  private createMonitoringAndAlerting(environment: string): void {
    // Create CloudWatch log group for secret access audit
    const auditLogGroup = new logs.LogGroup(this, 'SecretsAuditLogGroup', {
      logGroupName: `/aws/secretsmanager/${environment}`,
      retention: logs.RetentionDays.THREE_MONTHS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create metric filter for unauthorized access attempts
    const unauthorizedAccessMetric = new logs.MetricFilter(this, 'UnauthorizedAccessMetric', {
      logGroup: auditLogGroup,
      metricNamespace: 'ContainerSecrets',
      metricName: 'UnauthorizedAccess',
      filterPattern: logs.FilterPattern.literal('[timestamp, requestId, eventName="GetSecretValue", errorCode="AccessDenied"]'),
      metricValue: '1',
    });

    // Create CloudWatch alarm for unauthorized access
    const unauthorizedAccessAlarm = new cloudwatch.Alarm(this, 'UnauthorizedAccessAlarm', {
      metric: unauthorizedAccessMetric.metric(),
      threshold: 1,
      evaluationPeriods: 1,
      alarmName: `secrets-${environment}-unauthorized-access`,
      alarmDescription: 'Alert on unauthorized secret access attempts',
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to alarm
    unauthorizedAccessAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));

    // Create metric for secret rotation failures
    const rotationFailureMetric = new logs.MetricFilter(this, 'RotationFailureMetric', {
      logGroup: this.rotationFunction.logGroup,
      metricNamespace: 'ContainerSecrets',
      metricName: 'RotationFailures',
      filterPattern: logs.FilterPattern.literal('[timestamp, requestId, level="ERROR", message="Error rotating secret*"]'),
      metricValue: '1',
    });

    // Create CloudWatch alarm for rotation failures
    const rotationFailureAlarm = new cloudwatch.Alarm(this, 'RotationFailureAlarm', {
      metric: rotationFailureMetric.metric(),
      threshold: 1,
      evaluationPeriods: 1,
      alarmName: `secrets-${environment}-rotation-failure`,
      alarmDescription: 'Alert on secret rotation failures',
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to rotation failure alarm
    rotationFailureAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));

    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'SecretsDashboard', {
      dashboardName: `container-secrets-${environment}`,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Secret Access Patterns',
        left: [unauthorizedAccessMetric.metric()],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Rotation Status',
        left: [rotationFailureMetric.metric()],
        width: 12,
        height: 6,
      })
    );
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(environment: string): void {
    // VPC outputs
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID',
      exportName: `${this.stackName}-VpcId`,
    });

    // KMS key outputs
    new cdk.CfnOutput(this, 'EncryptionKeyId', {
      value: this.encryptionKey.keyId,
      description: 'KMS key ID for secrets encryption',
      exportName: `${this.stackName}-EncryptionKeyId`,
    });

    // Secrets outputs
    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: this.databaseSecret.secretArn,
      description: 'Database secret ARN',
      exportName: `${this.stackName}-DatabaseSecretArn`,
    });

    new cdk.CfnOutput(this, 'ApiSecretArn', {
      value: this.apiSecret.secretArn,
      description: 'API secret ARN',
      exportName: `${this.stackName}-ApiSecretArn`,
    });

    // ECS outputs
    new cdk.CfnOutput(this, 'EcsClusterName', {
      value: this.ecsCluster.clusterName,
      description: 'ECS cluster name',
      exportName: `${this.stackName}-EcsClusterName`,
    });

    new cdk.CfnOutput(this, 'EcsClusterArn', {
      value: this.ecsCluster.clusterArn,
      description: 'ECS cluster ARN',
      exportName: `${this.stackName}-EcsClusterArn`,
    });

    // EKS outputs (if created)
    if (this.eksCluster) {
      new cdk.CfnOutput(this, 'EksClusterName', {
        value: this.eksCluster.clusterName,
        description: 'EKS cluster name',
        exportName: `${this.stackName}-EksClusterName`,
      });

      new cdk.CfnOutput(this, 'EksClusterArn', {
        value: this.eksCluster.clusterArn,
        description: 'EKS cluster ARN',
        exportName: `${this.stackName}-EksClusterArn`,
      });

      new cdk.CfnOutput(this, 'EksClusterEndpoint', {
        value: this.eksCluster.clusterEndpoint,
        description: 'EKS cluster endpoint',
        exportName: `${this.stackName}-EksClusterEndpoint`,
      });
    }

    // Lambda outputs
    new cdk.CfnOutput(this, 'RotationFunctionArn', {
      value: this.rotationFunction.functionArn,
      description: 'Rotation Lambda function ARN',
      exportName: `${this.stackName}-RotationFunctionArn`,
    });

    // SNS outputs
    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS topic ARN for alerts',
      exportName: `${this.stackName}-AlertTopicArn`,
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Get configuration from context or environment
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'demo';
const createEksCluster = app.node.tryGetContext('createEksCluster') ?? true;
const rotationScheduleDays = app.node.tryGetContext('rotationScheduleDays') || 30;

// Create the stack
new ContainerSecretsStack(app, 'ContainerSecretsStack', {
  environment,
  createEksCluster,
  rotationScheduleDays,
  logRetentionDays: 30,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Container Secrets Management with AWS Secrets Manager - CDK TypeScript Implementation',
  tags: {
    Project: 'container-secrets-management',
    Environment: environment,
    ManagedBy: 'CDK',
  },
});