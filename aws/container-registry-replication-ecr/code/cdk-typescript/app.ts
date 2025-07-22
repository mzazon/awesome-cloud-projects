#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cw_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Duration } from 'aws-cdk-lib';

/**
 * Configuration interface for ECR replication setup
 */
interface ECRReplicationConfig {
  readonly sourceRegion: string;
  readonly destinationRegions: string[];
  readonly repositoryPrefix: string;
  readonly enableVulnerabilityScanning: boolean;
  readonly enableLifecyclePolicies: boolean;
  readonly enableMonitoring: boolean;
}

/**
 * Stack for ECR container registry replication strategies
 * 
 * This stack implements:
 * - Multi-region ECR repositories with replication
 * - Lifecycle policies for cost optimization
 * - Repository access policies for security
 * - CloudWatch monitoring and alerting
 * - Automated cleanup Lambda function
 */
class ECRReplicationStack extends cdk.Stack {
  public readonly productionRepository: ecr.Repository;
  public readonly testingRepository: ecr.Repository;
  public readonly monitoringTopic: sns.Topic;
  public readonly cleanupFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: cdk.StackProps & { config: ECRReplicationConfig }) {
    super(scope, id, props);

    const config = props.config;

    // Create SNS topic for notifications
    this.monitoringTopic = new sns.Topic(this, 'ECRReplicationAlerts', {
      topicName: 'ECR-Replication-Alerts',
      displayName: 'ECR Replication Monitoring Alerts',
      description: 'Notifications for ECR replication events and alerts',
    });

    // Create production repository
    this.productionRepository = this.createRepository(
      'ProductionRepository',
      `${config.repositoryPrefix}/production`,
      {
        imageScanningConfiguration: {
          scanOnPush: config.enableVulnerabilityScanning,
        },
        imageTagMutability: ecr.TagMutability.IMMUTABLE,
        lifecycleRules: config.enableLifecyclePolicies ? this.getProductionLifecycleRules() : undefined,
        repositoryPolicyStatements: this.getProductionRepositoryPolicyStatements(),
      }
    );

    // Create testing repository
    this.testingRepository = this.createRepository(
      'TestingRepository',
      `${config.repositoryPrefix}/testing`,
      {
        imageScanningConfiguration: {
          scanOnPush: config.enableVulnerabilityScanning,
        },
        imageTagMutability: ecr.TagMutability.MUTABLE,
        lifecycleRules: config.enableLifecyclePolicies ? this.getTestingLifecycleRules() : undefined,
        repositoryPolicyStatements: this.getTestingRepositoryPolicyStatements(),
      }
    );

    // Create replication configuration
    this.createReplicationConfiguration(config);

    // Create IAM roles for ECR access
    this.createECRAccessRoles();

    // Create Lambda function for automated cleanup
    this.cleanupFunction = this.createCleanupFunction(config);

    // Create CloudWatch monitoring if enabled
    if (config.enableMonitoring) {
      this.createCloudWatchMonitoring();
    }

    // Create outputs
    this.createOutputs(config);
  }

  /**
   * Create ECR repository with common configuration
   */
  private createRepository(
    id: string,
    repositoryName: string,
    options: {
      imageScanningConfiguration?: ecr.ImageScanningConfiguration;
      imageTagMutability?: ecr.TagMutability;
      lifecycleRules?: ecr.LifecycleRule[];
      repositoryPolicyStatements?: iam.PolicyStatement[];
    }
  ): ecr.Repository {
    const repository = new ecr.Repository(this, id, {
      repositoryName,
      imageScanningConfiguration: options.imageScanningConfiguration,
      imageTagMutability: options.imageTagMutability,
      lifecycleRules: options.lifecycleRules,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
    });

    // Add repository policy statements if provided
    if (options.repositoryPolicyStatements) {
      options.repositoryPolicyStatements.forEach(statement => {
        repository.addToResourcePolicy(statement);
      });
    }

    // Add tags
    cdk.Tags.of(repository).add('Project', 'ECR-Replication-Strategy');
    cdk.Tags.of(repository).add('Environment', 'Demo');

    return repository;
  }

  /**
   * Get lifecycle rules for production repository
   */
  private getProductionLifecycleRules(): ecr.LifecycleRule[] {
    return [
      {
        description: 'Keep last 10 production images',
        rulePriority: 1,
        selection: {
          tagStatus: ecr.TagStatus.TAGGED,
          tagPrefixList: ['prod', 'release'],
          countType: ecr.CountType.IMAGE_COUNT_MORE_THAN,
          countNumber: 10,
        },
      },
      {
        description: 'Delete untagged images older than 1 day',
        rulePriority: 2,
        selection: {
          tagStatus: ecr.TagStatus.UNTAGGED,
          countType: ecr.CountType.SINCE_IMAGE_PUSHED,
          countNumber: 1,
          countUnit: ecr.CountUnit.DAYS,
        },
      },
    ];
  }

  /**
   * Get lifecycle rules for testing repository
   */
  private getTestingLifecycleRules(): ecr.LifecycleRule[] {
    return [
      {
        description: 'Keep last 5 testing images',
        rulePriority: 1,
        selection: {
          tagStatus: ecr.TagStatus.TAGGED,
          tagPrefixList: ['test', 'dev', 'staging'],
          countType: ecr.CountType.IMAGE_COUNT_MORE_THAN,
          countNumber: 5,
        },
      },
      {
        description: 'Delete images older than 7 days',
        rulePriority: 2,
        selection: {
          tagStatus: ecr.TagStatus.ANY,
          countType: ecr.CountType.SINCE_IMAGE_PUSHED,
          countNumber: 7,
          countUnit: ecr.CountUnit.DAYS,
        },
      },
    ];
  }

  /**
   * Get repository policy statements for production repository
   */
  private getProductionRepositoryPolicyStatements(): iam.PolicyStatement[] {
    return [
      new iam.PolicyStatement({
        sid: 'ProdReadOnlyAccess',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ArnPrincipal(`arn:aws:iam::${this.account}:role/ECRProductionRole`)],
        actions: [
          'ecr:GetDownloadUrlForLayer',
          'ecr:BatchGetImage',
          'ecr:BatchCheckLayerAvailability',
        ],
      }),
      new iam.PolicyStatement({
        sid: 'ProdPushAccess',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ArnPrincipal(`arn:aws:iam::${this.account}:role/ECRCIPipelineRole`)],
        actions: [
          'ecr:PutImage',
          'ecr:InitiateLayerUpload',
          'ecr:UploadLayerPart',
          'ecr:CompleteLayerUpload',
        ],
      }),
    ];
  }

  /**
   * Get repository policy statements for testing repository
   */
  private getTestingRepositoryPolicyStatements(): iam.PolicyStatement[] {
    return [
      new iam.PolicyStatement({
        sid: 'TestingFullAccess',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ArnPrincipal(`arn:aws:iam::${this.account}:role/ECRTestingRole`)],
        actions: [
          'ecr:GetDownloadUrlForLayer',
          'ecr:BatchGetImage',
          'ecr:BatchCheckLayerAvailability',
          'ecr:PutImage',
          'ecr:InitiateLayerUpload',
          'ecr:UploadLayerPart',
          'ecr:CompleteLayerUpload',
        ],
      }),
    ];
  }

  /**
   * Create replication configuration
   */
  private createReplicationConfiguration(config: ECRReplicationConfig): void {
    // Create replication destinations
    const destinations = config.destinationRegions.map(region => ({
      region,
      registryId: this.account,
    }));

    // Create replication configuration
    new ecr.CfnReplicationConfiguration(this, 'ReplicationConfiguration', {
      replicationConfiguration: {
        rules: [
          {
            destinations,
            repositoryFilters: [
              {
                filter: config.repositoryPrefix,
                filterType: 'PREFIX_MATCH',
              },
            ],
          },
        ],
      },
    });
  }

  /**
   * Create IAM roles for ECR access
   */
  private createECRAccessRoles(): void {
    // Production role for read-only access
    const productionRole = new iam.Role(this, 'ECRProductionRole', {
      roleName: 'ECRProductionRole',
      description: 'Role for production ECR access',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
      ],
    });

    // CI/CD pipeline role for push access
    const ciPipelineRole = new iam.Role(this, 'ECRCIPipelineRole', {
      roleName: 'ECRCIPipelineRole',
      description: 'Role for CI/CD pipeline ECR access',
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryPowerUser'),
      ],
    });

    // Testing role for full access
    const testingRole = new iam.Role(this, 'ECRTestingRole', {
      roleName: 'ECRTestingRole',
      description: 'Role for testing ECR access',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryPowerUser'),
      ],
    });

    // Add tags
    cdk.Tags.of(productionRole).add('Purpose', 'ECR-Production-Access');
    cdk.Tags.of(ciPipelineRole).add('Purpose', 'ECR-CI-Pipeline');
    cdk.Tags.of(testingRole).add('Purpose', 'ECR-Testing-Access');
  }

  /**
   * Create Lambda function for automated cleanup
   */
  private createCleanupFunction(config: ECRReplicationConfig): lambda.Function {
    const cleanupFunction = new lambda.Function(this, 'CleanupFunction', {
      functionName: 'ECR-Automated-Cleanup',
      description: 'Automated cleanup function for ECR repositories',
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      timeout: Duration.minutes(15),
      memorySize: 256,
      environment: {
        REPOSITORY_PREFIX: config.repositoryPrefix,
        SNS_TOPIC_ARN: this.monitoringTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import boto3
import json
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ecr_client = boto3.client('ecr')
    sns_client = boto3.client('sns')
    
    repository_prefix = os.environ['REPOSITORY_PREFIX']
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Get all repositories with specific prefix
        response = ecr_client.describe_repositories()
        repositories = [
            repo for repo in response['repositories']
            if repo['repositoryName'].startswith(repository_prefix)
        ]
        
        cleanup_summary = []
        
        for repo in repositories:
            repo_name = repo['repositoryName']
            
            # Get untagged images older than 30 days
            images_response = ecr_client.describe_images(
                repositoryName=repo_name,
                filter={'tagStatus': 'UNTAGGED'}
            )
            
            old_images = []
            cutoff_date = datetime.now(images_response['imageDetails'][0]['imagePushedAt'].tzinfo) - timedelta(days=30)
            
            for image in images_response['imageDetails']:
                if image['imagePushedAt'] < cutoff_date:
                    old_images.append({'imageDigest': image['imageDigest']})
            
            # Delete old images
            if old_images:
                ecr_client.batch_delete_image(
                    repositoryName=repo_name,
                    imageIds=old_images
                )
                cleanup_summary.append(f"Deleted {len(old_images)} old images from {repo_name}")
        
        # Send notification
        if cleanup_summary:
            message = "ECR Cleanup Summary:\\n" + "\\n".join(cleanup_summary)
            sns_client.publish(
                TopicArn=topic_arn,
                Subject="ECR Automated Cleanup Completed",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cleanup completed successfully',
                'summary': cleanup_summary
            })
        }
        
    except Exception as e:
        error_message = f"ECR cleanup failed: {str(e)}"
        sns_client.publish(
            TopicArn=topic_arn,
            Subject="ECR Cleanup Failed",
            Message=error_message
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message
            })
        }
      `),
    });

    // Grant ECR permissions to Lambda
    cleanupFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'ecr:DescribeRepositories',
          'ecr:DescribeImages',
          'ecr:BatchDeleteImage',
        ],
        resources: ['*'],
      })
    );

    // Grant SNS permissions to Lambda
    this.monitoringTopic.grantPublish(cleanupFunction);

    // Schedule the cleanup function to run weekly
    const cleanupSchedule = new events.Rule(this, 'CleanupSchedule', {
      description: 'Schedule for ECR automated cleanup',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '2',
        weekDay: 'SUN',
      }),
    });

    cleanupSchedule.addTarget(new targets.LambdaFunction(cleanupFunction));

    return cleanupFunction;
  }

  /**
   * Create CloudWatch monitoring and alerting
   */
  private createCloudWatchMonitoring(): void {
    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'ECRReplicationDashboard', {
      dashboardName: 'ECR-Replication-Monitoring',
      defaultInterval: Duration.hours(1),
    });

    // Add repository activity widgets
    const repositoryPullMetric = new cloudwatch.Metric({
      namespace: 'AWS/ECR',
      metricName: 'RepositoryPullCount',
      dimensionsMap: {
        RepositoryName: this.productionRepository.repositoryName,
      },
      statistic: 'Sum',
      period: Duration.minutes(5),
    });

    const repositoryPushMetric = new cloudwatch.Metric({
      namespace: 'AWS/ECR',
      metricName: 'RepositoryPushCount',
      dimensionsMap: {
        RepositoryName: this.productionRepository.repositoryName,
      },
      statistic: 'Sum',
      period: Duration.minutes(5),
    });

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'ECR Repository Activity',
        left: [repositoryPullMetric, repositoryPushMetric],
        width: 12,
        height: 6,
      })
    );

    // Create replication failure alarm
    const replicationFailureAlarm = new cloudwatch.Alarm(this, 'ReplicationFailureAlarm', {
      alarmName: 'ECR-Replication-Failure-Rate',
      alarmDescription: 'Monitor ECR replication failure rate',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ECR',
        metricName: 'ReplicationFailureRate',
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 0.1,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to alarm
    replicationFailureAlarm.addAlarmAction(
      new cw_actions.SnsAction(this.monitoringTopic)
    );

    // Create custom metric for cleanup function
    const cleanupMetric = new cloudwatch.Metric({
      namespace: 'AWS/Lambda',
      metricName: 'Duration',
      dimensionsMap: {
        FunctionName: this.cleanupFunction.functionName,
      },
      statistic: 'Average',
      period: Duration.minutes(5),
    });

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Cleanup Function Performance',
        left: [cleanupMetric],
        width: 12,
        height: 6,
      })
    );
  }

  /**
   * Create stack outputs
   */
  private createOutputs(config: ECRReplicationConfig): void {
    // Repository URIs
    new cdk.CfnOutput(this, 'ProductionRepositoryUri', {
      description: 'URI of the production ECR repository',
      value: this.productionRepository.repositoryUri,
      exportName: 'ECR-Production-Repository-Uri',
    });

    new cdk.CfnOutput(this, 'TestingRepositoryUri', {
      description: 'URI of the testing ECR repository',
      value: this.testingRepository.repositoryUri,
      exportName: 'ECR-Testing-Repository-Uri',
    });

    // Repository names
    new cdk.CfnOutput(this, 'ProductionRepositoryName', {
      description: 'Name of the production ECR repository',
      value: this.productionRepository.repositoryName,
      exportName: 'ECR-Production-Repository-Name',
    });

    new cdk.CfnOutput(this, 'TestingRepositoryName', {
      description: 'Name of the testing ECR repository',
      value: this.testingRepository.repositoryName,
      exportName: 'ECR-Testing-Repository-Name',
    });

    // Replication configuration
    new cdk.CfnOutput(this, 'ReplicationDestinations', {
      description: 'ECR replication destination regions',
      value: config.destinationRegions.join(', '),
      exportName: 'ECR-Replication-Destinations',
    });

    // Monitoring topic
    new cdk.CfnOutput(this, 'MonitoringTopicArn', {
      description: 'ARN of the SNS topic for monitoring alerts',
      value: this.monitoringTopic.topicArn,
      exportName: 'ECR-Monitoring-Topic-Arn',
    });

    // Cleanup function
    new cdk.CfnOutput(this, 'CleanupFunctionArn', {
      description: 'ARN of the automated cleanup Lambda function',
      value: this.cleanupFunction.functionArn,
      exportName: 'ECR-Cleanup-Function-Arn',
    });

    // Login commands
    new cdk.CfnOutput(this, 'DockerLoginCommand', {
      description: 'Docker login command for the ECR repositories',
      value: `aws ecr get-login-password --region ${config.sourceRegion} | docker login --username AWS --password-stdin ${this.account}.dkr.ecr.${config.sourceRegion}.amazonaws.com`,
      exportName: 'ECR-Docker-Login-Command',
    });
  }
}

/**
 * CDK App for ECR Replication Strategies
 */
const app = new cdk.App();

// Configuration
const config: ECRReplicationConfig = {
  sourceRegion: 'us-east-1',
  destinationRegions: ['us-west-2', 'eu-west-1'],
  repositoryPrefix: 'enterprise-apps',
  enableVulnerabilityScanning: true,
  enableLifecyclePolicies: true,
  enableMonitoring: true,
};

// Deploy the stack
new ECRReplicationStack(app, 'ECRReplicationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: config.sourceRegion,
  },
  config,
  description: 'ECR container registry replication strategies with multi-region support, lifecycle policies, and monitoring',
});

// Add tags to all resources
cdk.Tags.of(app).add('Project', 'ECR-Replication-Strategy');
cdk.Tags.of(app).add('Environment', 'Demo');
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Recipe', 'container-registry-replication-strategies-ecr');