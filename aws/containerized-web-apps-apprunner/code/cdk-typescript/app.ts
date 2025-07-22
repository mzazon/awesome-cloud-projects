#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as apprunner from 'aws-cdk-lib/aws-apprunner';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { AwsSolutionsChecks } from 'cdk-nag';
import { NagSuppressions } from 'cdk-nag';

/**
 * CDK Stack for containerized web applications using AWS App Runner and RDS
 * 
 * This stack creates:
 * - VPC with private subnets for RDS
 * - RDS PostgreSQL database instance
 * - Secrets Manager for database credentials
 * - ECR repository for container images
 * - App Runner service with proper IAM roles
 * - CloudWatch monitoring and alarms
 */
export class ContainerizedWebAppStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create VPC for RDS with private subnets only (App Runner doesn't require VPC)
    const vpc = new ec2.Vpc(this, 'WebAppVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      subnetConfiguration: [
        {
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          cidrMask: 24,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Security group for RDS database
    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for RDS PostgreSQL database',
      allowAllOutbound: false,
    });

    // Allow inbound connections on PostgreSQL port from App Runner
    dbSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(5432),
      'Allow PostgreSQL connections from VPC'
    );

    // Create database credentials secret
    const dbSecret = new secretsmanager.Secret(this, 'DatabaseSecret', {
      secretName: `webapp-db-credentials-${uniqueSuffix}`,
      description: 'Database credentials for web application',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          username: 'postgres',
          dbname: 'postgres',
        }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\',
        passwordLength: 20,
        requireEachIncludedType: true,
      },
    });

    // Create RDS subnet group
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      description: 'Subnet group for web application database',
    });

    // Create RDS PostgreSQL instance
    const database = new rds.DatabaseInstance(this, 'Database', {
      instanceIdentifier: `webapp-db-${uniqueSuffix}`,
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_14_9,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO),
      credentials: rds.Credentials.fromSecret(dbSecret),
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [dbSecurityGroup],
      subnetGroup: dbSubnetGroup,
      allocatedStorage: 20,
      storageType: rds.StorageType.GP2,
      storageEncrypted: true,
      backupRetention: cdk.Duration.days(7),
      deletionProtection: false,
      multiAz: false,
      allowMajorVersionUpgrade: false,
      autoMinorVersionUpgrade: true,
      deleteAutomatedBackups: true,
    });

    // Update secret with database endpoint after RDS creation
    new secretsmanager.SecretTargetAttachment(this, 'SecretTargetAttachment', {
      secret: dbSecret,
      target: database,
      targetType: secretsmanager.AttachmentTargetType.RDS_DB_INSTANCE,
    });

    // Create ECR repository for container images
    const ecrRepository = new ecr.Repository(this, 'ContainerRepository', {
      repositoryName: `webapp-${uniqueSuffix}`,
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      lifecycleRules: [
        {
          description: 'Keep only the latest 10 images',
          maxImageCount: 10,
          rulePriority: 1,
        }
      ],
    });

    // Create IAM role for App Runner service access to ECR
    const appRunnerAccessRole = new iam.Role(this, 'AppRunnerAccessRole', {
      assumedBy: new iam.ServicePrincipal('build.apprunner.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSAppRunnerServicePolicyForECRAccess')
      ],
      description: 'IAM role for App Runner to access ECR repository',
    });

    // Create IAM role for App Runner task execution (runtime permissions)
    const appRunnerInstanceRole = new iam.Role(this, 'AppRunnerInstanceRole', {
      assumedBy: new iam.ServicePrincipal('tasks.apprunner.amazonaws.com'),
      description: 'IAM role for App Runner task execution',
    });

    // Grant read access to the database secret
    dbSecret.grantRead(appRunnerInstanceRole);

    // Create App Runner service
    const appRunnerService = new apprunner.Service(this, 'WebAppService', {
      serviceName: `webapp-${uniqueSuffix}`,
      source: apprunner.Source.fromEcr({
        imageConfiguration: {
          port: 8080,
          environmentVariables: {
            NODE_ENV: 'production',
            AWS_REGION: this.region,
            DB_SECRET_NAME: dbSecret.secretName,
          },
        },
        repository: ecrRepository,
        tagOrDigest: 'latest',
      }),
      instanceConfiguration: {
        instanceRole: appRunnerInstanceRole,
        cpu: apprunner.Cpu.ONE_VCPU,
        memory: apprunner.Memory.TWO_GB,
      },
      healthCheckConfiguration: {
        protocol: apprunner.HealthCheckProtocol.HTTP,
        path: '/health',
        interval: cdk.Duration.seconds(10),
        timeout: cdk.Duration.seconds(5),
        healthyThreshold: 1,
        unhealthyThreshold: 5,
      },
      autoScalingConfiguration: {
        minSize: 1,
        maxSize: 10,
        maxConcurrency: 100,
      },
      accessRole: appRunnerAccessRole,
    });

    // Create CloudWatch Log Group for App Runner
    const logGroup = new logs.LogGroup(this, 'AppRunnerLogGroup', {
      logGroupName: `/aws/apprunner/${appRunnerService.serviceName}/application`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch Alarms for monitoring
    const highCpuAlarm = new cloudwatch.Alarm(this, 'HighCpuAlarm', {
      alarmName: `${appRunnerService.serviceName}-high-cpu`,
      alarmDescription: 'Alert when CPU exceeds 80%',
      metric: appRunnerService.metricCpuUtilization({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    const highMemoryAlarm = new cloudwatch.Alarm(this, 'HighMemoryAlarm', {
      alarmName: `${appRunnerService.serviceName}-high-memory`,
      alarmDescription: 'Alert when memory exceeds 80%',
      metric: appRunnerService.metricMemoryUtilization({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    const highLatencyAlarm = new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      alarmName: `${appRunnerService.serviceName}-high-latency`,
      alarmDescription: 'Alert when response time exceeds 2 seconds',
      metric: appRunnerService.metricRequestLatency({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 2000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    // CloudFormation outputs
    new cdk.CfnOutput(this, 'AppRunnerServiceUrl', {
      value: `https://${appRunnerService.serviceUrl}`,
      description: 'URL of the App Runner service',
    });

    new cdk.CfnOutput(this, 'ECRRepositoryUri', {
      value: ecrRepository.repositoryUri,
      description: 'URI of the ECR repository',
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: database.instanceEndpoint.hostname,
      description: 'RDS database endpoint',
    });

    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: dbSecret.secretArn,
      description: 'ARN of the database credentials secret',
    });

    // CDK Nag suppressions for specific resources
    NagSuppressions.addResourceSuppressions(
      database,
      [
        {
          id: 'AwsSolutions-RDS2',
          reason: 'Storage encryption is enabled with default KMS key',
        },
        {
          id: 'AwsSolutions-RDS3',
          reason: 'Multi-AZ is disabled to reduce costs for development/demo purposes',
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      dbSecurityGroup,
      [
        {
          id: 'AwsSolutions-EC23',
          reason: 'Security group allows inbound traffic on PostgreSQL port 5432 from VPC CIDR, which is appropriate for database access',
        }
      ]
    );

    NagSuppressions.addResourceSuppressions(
      appRunnerInstanceRole,
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'App Runner service requires AWS managed policies for ECR access',
        }
      ]
    );

    NagSuppressions.addResourceSuppressions(
      appRunnerAccessRole,
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'App Runner access role uses AWS managed policy for ECR access as per AWS best practices',
        }
      ]
    );
  }
}

// Create CDK app and stack
const app = new cdk.App();

// Apply CDK Nag to ensure security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

new ContainerizedWebAppStack(app, 'ContainerizedWebAppStack', {
  description: 'Stack for containerized web applications using AWS App Runner and RDS',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ContainerizedWebApp',
    Environment: 'Development',
    Owner: 'CDK',
  },
});

app.synth();