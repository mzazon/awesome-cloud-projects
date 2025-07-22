#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as backup from 'aws-cdk-lib/aws-backup';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cwalarms from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

/**
 * Configuration interface for the Database Backup Stack
 */
interface DatabaseBackupStackProps extends cdk.StackProps {
  readonly dbInstanceClass?: ec2.InstanceType;
  readonly dbEngine?: rds.IEngine;
  readonly allocatedStorage?: number;
  readonly backupRetentionPeriod?: number;
  readonly backupWindow?: string;
  readonly maintenanceWindow?: string;
  readonly disasterRecoveryRegion?: string;
  readonly enableCrossRegionBackup?: boolean;
  readonly enableMonitoring?: boolean;
}

/**
 * CDK Stack for implementing comprehensive database backup and point-in-time recovery strategies
 * with Amazon RDS, AWS Backup, and cross-region disaster recovery capabilities.
 */
class DatabaseBackupStack extends cdk.Stack {
  public readonly dbInstance: rds.DatabaseInstance;
  public readonly backupVault: backup.BackupVault;
  public readonly backupPlan: backup.BackupPlan;
  public readonly kmsKey: kms.Key;
  public readonly drRegionKmsKey: kms.Key;
  public readonly backupRole: iam.Role;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: DatabaseBackupStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const config = {
      dbInstanceClass: props.dbInstanceClass || ec2.InstanceType.of(ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO),
      dbEngine: props.dbEngine || rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0_35
      }),
      allocatedStorage: props.allocatedStorage || 20,
      backupRetentionPeriod: props.backupRetentionPeriod || 7,
      backupWindow: props.backupWindow || '03:00-04:00',
      maintenanceWindow: props.maintenanceWindow || 'sun:04:00-sun:05:00',
      disasterRecoveryRegion: props.disasterRecoveryRegion || 'us-west-2',
      enableCrossRegionBackup: props.enableCrossRegionBackup ?? true,
      enableMonitoring: props.enableMonitoring ?? true
    };

    // Create KMS key for backup encryption
    this.kmsKey = this.createKmsKey();

    // Create KMS key for DR region if cross-region backup is enabled
    if (config.enableCrossRegionBackup) {
      this.drRegionKmsKey = this.createDrRegionKmsKey(config.disasterRecoveryRegion);
    }

    // Create VPC for RDS instance
    const vpc = this.createVpc();

    // Create database credentials secret
    const dbCredentials = this.createDatabaseCredentials();

    // Create RDS instance with backup configuration
    this.dbInstance = this.createRdsInstance(vpc, config, dbCredentials);

    // Create IAM role for AWS Backup
    this.backupRole = this.createBackupRole();

    // Create backup vault with encryption
    this.backupVault = this.createBackupVault();

    // Create backup plan with automated schedules
    this.backupPlan = this.createBackupPlan(config);

    // Create backup selection to assign RDS to backup plan
    this.createBackupSelection();

    // Create cross-region backup vault if enabled
    if (config.enableCrossRegionBackup) {
      this.createCrossRegionBackupVault(config.disasterRecoveryRegion);
    }

    // Create monitoring and alerting if enabled
    if (config.enableMonitoring) {
      this.notificationTopic = this.createMonitoringAndAlerting();
    }

    // Create backup vault access policy for cross-account access
    this.createBackupVaultAccessPolicy();

    // Add tags to all resources
    this.addResourceTags();

    // Create outputs
    this.createOutputs();
  }

  /**
   * Creates a KMS key for backup encryption in the primary region
   */
  private createKmsKey(): kms.Key {
    return new kms.Key(this, 'BackupKmsKey', {
      description: 'KMS key for RDS backup encryption',
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      enableKeyRotation: true,
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*']
          }),
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('backup.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:CreateGrant'
            ],
            resources: ['*']
          })
        ]
      })
    });
  }

  /**
   * Creates a KMS key for backup encryption in the DR region
   */
  private createDrRegionKmsKey(drRegion: string): kms.Key {
    return new kms.Key(this, 'DrRegionBackupKmsKey', {
      description: 'KMS key for RDS backup encryption in DR region',
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      enableKeyRotation: true,
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*']
          }),
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('backup.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:CreateGrant'
            ],
            resources: ['*']
          })
        ]
      })
    });
  }

  /**
   * Creates a VPC for the RDS instance with proper subnet configuration
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'DatabaseVpc', {
      maxAzs: 2,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true
    });
  }

  /**
   * Creates database credentials stored in AWS Secrets Manager
   */
  private createDatabaseCredentials(): secretsmanager.Secret {
    return new secretsmanager.Secret(this, 'DatabaseCredentials', {
      description: 'Database credentials for RDS instance',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'admin' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\'
      }
    });
  }

  /**
   * Creates RDS instance with comprehensive backup configuration
   */
  private createRdsInstance(
    vpc: ec2.Vpc,
    config: any,
    credentials: secretsmanager.Secret
  ): rds.DatabaseInstance {
    // Create subnet group for RDS
    const subnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      description: 'Subnet group for RDS database instance',
      vpc,
      subnetGroupName: 'database-subnet-group',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED
      }
    });

    // Create security group for RDS
    const securityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for RDS database instance',
      allowAllOutbound: false
    });

    // Allow inbound MySQL/Aurora connections from VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL connections from VPC'
    );

    return new rds.DatabaseInstance(this, 'DatabaseInstance', {
      engine: config.dbEngine,
      instanceType: config.dbInstanceClass,
      vpc,
      subnetGroup,
      securityGroups: [securityGroup],
      credentials: rds.Credentials.fromSecret(credentials),
      allocatedStorage: config.allocatedStorage,
      storageType: rds.StorageType.GP2,
      storageEncrypted: true,
      storageEncryptionKey: this.kmsKey,
      backupRetention: cdk.Duration.days(config.backupRetentionPeriod),
      preferredBackupWindow: config.backupWindow,
      preferredMaintenanceWindow: config.maintenanceWindow,
      copyTagsToSnapshot: true,
      deleteAutomatedBackups: true,
      deletionProtection: true,
      enablePerformanceInsights: true,
      performanceInsightEncryptionKey: this.kmsKey,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      monitoringInterval: cdk.Duration.seconds(60),
      cloudwatchLogsExports: ['error', 'general', 'slow-query'],
      autoMinorVersionUpgrade: true,
      allowMajorVersionUpgrade: false
    });
  }

  /**
   * Creates IAM role for AWS Backup service operations
   */
  private createBackupRole(): iam.Role {
    const role = new iam.Role(this, 'BackupRole', {
      assumedBy: new iam.ServicePrincipal('backup.amazonaws.com'),
      description: 'IAM role for AWS Backup service operations'
    });

    // Attach AWS managed policies for backup operations
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForBackup')
    );
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForRestores')
    );

    // Add additional permissions for cross-region operations
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'rds:DescribeDBInstances',
        'rds:DescribeDBSnapshots',
        'rds:DescribeDBClusters',
        'rds:DescribeDBClusterSnapshots',
        'rds:CopyDBSnapshot',
        'rds:CopyDBClusterSnapshot',
        'kms:Decrypt',
        'kms:GenerateDataKey'
      ],
      resources: ['*']
    }));

    return role;
  }

  /**
   * Creates backup vault with encryption and access controls
   */
  private createBackupVault(): backup.BackupVault {
    return new backup.BackupVault(this, 'BackupVault', {
      backupVaultName: 'rds-backup-vault',
      encryptionKey: this.kmsKey,
      accessPolicy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['backup:*'],
            resources: ['*']
          })
        ]
      })
    });
  }

  /**
   * Creates comprehensive backup plan with multiple retention policies
   */
  private createBackupPlan(config: any): backup.BackupPlan {
    const plan = new backup.BackupPlan(this, 'BackupPlan', {
      backupPlanName: 'rds-backup-plan'
    });

    // Daily backup rule
    plan.addRule(new backup.BackupPlanRule({
      ruleName: 'DailyBackups',
      backupVault: this.backupVault,
      scheduleExpression: cdk.aws_events.Schedule.cron({
        minute: '0',
        hour: '5',
        day: '*',
        month: '*',
        year: '*'
      }),
      startWindow: cdk.Duration.minutes(60),
      completionWindow: cdk.Duration.minutes(120),
      deleteAfter: cdk.Duration.days(30),
      moveToColdStorageAfter: cdk.Duration.days(7),
      recoveryPointTags: {
        Environment: 'Production',
        BackupType: 'Daily'
      },
      copyActions: config.enableCrossRegionBackup ? [{
        destinationBackupVault: backup.BackupVault.fromBackupVaultArn(
          this,
          'DrRegionBackupVault',
          `arn:aws:backup:${config.disasterRecoveryRegion}:${this.account}:backup-vault:rds-backup-vault-dr`
        ),
        deleteAfter: cdk.Duration.days(30)
      }] : undefined
    }));

    // Weekly backup rule
    plan.addRule(new backup.BackupPlanRule({
      ruleName: 'WeeklyBackups',
      backupVault: this.backupVault,
      scheduleExpression: cdk.aws_events.Schedule.cron({
        minute: '0',
        hour: '3',
        day: '*',
        month: '*',
        year: '*',
        weekDay: 'SUN'
      }),
      startWindow: cdk.Duration.minutes(60),
      completionWindow: cdk.Duration.minutes(180),
      deleteAfter: cdk.Duration.days(90),
      moveToColdStorageAfter: cdk.Duration.days(14),
      recoveryPointTags: {
        Environment: 'Production',
        BackupType: 'Weekly'
      }
    }));

    return plan;
  }

  /**
   * Creates backup selection to assign RDS instance to backup plan
   */
  private createBackupSelection(): backup.BackupSelection {
    return new backup.BackupSelection(this, 'BackupSelection', {
      backupPlan: this.backupPlan,
      resources: [
        backup.BackupResource.fromRdsDatabaseInstance(this.dbInstance)
      ],
      role: this.backupRole,
      backupSelectionName: 'rds-backup-selection',
      conditions: {
        stringEquals: {
          'aws:ResourceTag/Environment': 'Production'
        }
      }
    });
  }

  /**
   * Creates cross-region backup vault for disaster recovery
   */
  private createCrossRegionBackupVault(drRegion: string): void {
    // Note: This creates a reference to the DR region vault
    // The actual vault would need to be created in the DR region stack
    new backup.BackupVault(this, 'DrRegionBackupVaultRef', {
      backupVaultName: 'rds-backup-vault-dr',
      encryptionKey: this.drRegionKmsKey
    });
  }

  /**
   * Creates monitoring and alerting for backup operations
   */
  private createMonitoringAndAlerting(): sns.Topic {
    // Create SNS topic for backup notifications
    const topic = new sns.Topic(this, 'BackupNotificationTopic', {
      topicName: 'rds-backup-notifications',
      displayName: 'RDS Backup Notifications'
    });

    // Create CloudWatch alarm for backup failures
    const backupFailureAlarm = new cloudwatch.Alarm(this, 'BackupFailureAlarm', {
      alarmName: 'RDS-Backup-Failures',
      alarmDescription: 'Alert on RDS backup failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Backup',
        metricName: 'NumberOfBackupJobsFailed',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to the alarm
    backupFailureAlarm.addAlarmAction(new cwalarms.SnsAction(topic));

    // Create CloudWatch alarm for backup job completion
    const backupSuccessAlarm = new cloudwatch.Alarm(this, 'BackupSuccessAlarm', {
      alarmName: 'RDS-Backup-Success',
      alarmDescription: 'Monitor successful RDS backup completions',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Backup',
        metricName: 'NumberOfBackupJobsCompleted',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING
    });

    return topic;
  }

  /**
   * Creates backup vault access policy for cross-account access
   */
  private createBackupVaultAccessPolicy(): void {
    const accessPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          sid: 'AllowCrossAccountAccess',
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: [
            'backup:DescribeBackupVault',
            'backup:DescribeRecoveryPoint',
            'backup:ListRecoveryPointsByBackupVault'
          ],
          resources: ['*']
        })
      ]
    });

    // Apply access policy to backup vault
    this.backupVault.addToAccessPolicy(accessPolicy.statements[0]);
  }

  /**
   * Adds comprehensive tags to all resources
   */
  private addResourceTags(): void {
    const tags = {
      Environment: 'Production',
      Project: 'DatabaseBackupRecovery',
      Owner: 'DatabaseTeam',
      CostCenter: 'Infrastructure',
      BackupEnabled: 'true'
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // Add specific tags to RDS instance
    cdk.Tags.of(this.dbInstance).add('Environment', 'Production');
    cdk.Tags.of(this.dbInstance).add('BackupRequired', 'true');
  }

  /**
   * Creates stack outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'DatabaseInstanceId', {
      value: this.dbInstance.instanceIdentifier,
      description: 'RDS Database Instance Identifier'
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: this.dbInstance.instanceEndpoint.hostname,
      description: 'RDS Database Endpoint'
    });

    new cdk.CfnOutput(this, 'BackupVaultName', {
      value: this.backupVault.backupVaultName,
      description: 'AWS Backup Vault Name'
    });

    new cdk.CfnOutput(this, 'BackupPlanId', {
      value: this.backupPlan.backupPlanId,
      description: 'AWS Backup Plan ID'
    });

    new cdk.CfnOutput(this, 'KmsKeyId', {
      value: this.kmsKey.keyId,
      description: 'KMS Key ID for backup encryption'
    });

    new cdk.CfnOutput(this, 'BackupRoleArn', {
      value: this.backupRole.roleArn,
      description: 'IAM Role ARN for backup operations'
    });

    if (this.notificationTopic) {
      new cdk.CfnOutput(this, 'NotificationTopicArn', {
        value: this.notificationTopic.topicArn,
        description: 'SNS Topic ARN for backup notifications'
      });
    }
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Deploy the main stack
new DatabaseBackupStack(app, 'DatabaseBackupStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  description: 'Comprehensive database backup and point-in-time recovery solution with RDS and AWS Backup',
  
  // Stack configuration
  dbInstanceClass: ec2.InstanceType.of(ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO),
  allocatedStorage: 20,
  backupRetentionPeriod: 7,
  backupWindow: '03:00-04:00',
  maintenanceWindow: 'sun:04:00-sun:05:00',
  disasterRecoveryRegion: 'us-west-2',
  enableCrossRegionBackup: true,
  enableMonitoring: true
});

// Add global tags to the app
cdk.Tags.of(app).add('Application', 'DatabaseBackupRecovery');
cdk.Tags.of(app).add('ManagedBy', 'CDK');

app.synth();