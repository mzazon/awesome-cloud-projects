#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for demonstrating ECS Task Definitions with comprehensive environment variable management
 * including Systems Manager Parameter Store, S3 environment files, and direct environment variables
 */
export class EcsTaskDefinitionsEnvironmentVariableManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // ========================================
    // VPC and Networking Infrastructure
    // ========================================
    
    // Create VPC for ECS cluster - using default configuration for simplicity
    // In production, consider custom VPC with private subnets and NAT gateways
    const vpc = new ec2.Vpc(this, 'EcsEnvVarVpc', {
      maxAzs: 2, // Use 2 availability zones for high availability
      natGateways: 1, // Reduce costs with single NAT gateway for demo
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

    // ========================================
    // Systems Manager Parameter Store Setup
    // ========================================
    
    // Create hierarchical parameters for configuration management
    // This demonstrates environment-specific parameter organization
    const databaseHostParam = new ssm.StringParameter(this, 'DatabaseHostParam', {
      parameterName: '/myapp/dev/database/host',
      stringValue: 'dev-database.internal.com',
      description: 'Development database host',
      tier: ssm.ParameterTier.STANDARD,
    });

    const databasePortParam = new ssm.StringParameter(this, 'DatabasePortParam', {
      parameterName: '/myapp/dev/database/port',
      stringValue: '5432',
      description: 'Development database port',
      tier: ssm.ParameterTier.STANDARD,
    });

    const apiDebugParam = new ssm.StringParameter(this, 'ApiDebugParam', {
      parameterName: '/myapp/dev/api/debug',
      stringValue: 'true',
      description: 'Development API debug mode',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Create secure parameters for sensitive data using SecureString
    const databasePasswordParam = new ssm.StringParameter(this, 'DatabasePasswordParam', {
      parameterName: '/myapp/dev/database/password',
      stringValue: 'dev-secure-password-123',
      description: 'Development database password',
      type: ssm.ParameterType.SECURE_STRING,
      tier: ssm.ParameterTier.STANDARD,
    });

    const apiSecretKeyParam = new ssm.StringParameter(this, 'ApiSecretKeyParam', {
      parameterName: '/myapp/dev/api/secret-key',
      stringValue: 'dev-api-secret-key-456',
      description: 'Development API secret key',
      type: ssm.ParameterType.SECURE_STRING,
      tier: ssm.ParameterTier.STANDARD,
    });

    // Create shared parameters for cross-environment settings
    const sharedRegionParam = new ssm.StringParameter(this, 'SharedRegionParam', {
      parameterName: '/myapp/shared/region',
      stringValue: this.region,
      description: 'Shared region parameter',
      tier: ssm.ParameterTier.STANDARD,
    });

    const sharedAccountIdParam = new ssm.StringParameter(this, 'SharedAccountIdParam', {
      parameterName: '/myapp/shared/account-id',
      stringValue: this.account,
      description: 'Shared account ID parameter',
      tier: ssm.ParameterTier.STANDARD,
    });

    // ========================================
    // S3 Bucket for Environment Files
    // ========================================
    
    // Create S3 bucket for storing environment configuration files
    const configBucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `ecs-envvar-configs-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - handle carefully in production
      versioned: true, // Enable versioning for configuration file tracking
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
    });

    // Deploy environment configuration files to S3
    // In production, these would typically be managed through CI/CD pipelines
    new s3.deployment.BucketDeployment(this, 'ConfigDeployment', {
      sources: [
        s3.deployment.Source.data('configs/app-config.env', 
          'LOG_LEVEL=info\n' +
          'MAX_CONNECTIONS=100\n' +
          'TIMEOUT_SECONDS=30\n' +
          'FEATURE_FLAGS=auth,logging,metrics\n' +
          'APP_VERSION=1.2.3\n'
        ),
        s3.deployment.Source.data('configs/prod-config.env',
          'LOG_LEVEL=warn\n' +
          'MAX_CONNECTIONS=500\n' +
          'TIMEOUT_SECONDS=60\n' +
          'FEATURE_FLAGS=auth,logging,metrics,cache\n' +
          'APP_VERSION=1.2.3\n' +
          'MONITORING_ENABLED=true\n'
        ),
      ],
      destinationBucket: configBucket,
    });

    // ========================================
    // IAM Roles for ECS Tasks
    // ========================================
    
    // Create ECS task execution role with comprehensive permissions
    // This role is used by ECS to start and manage tasks
    const taskExecutionRole = new iam.Role(this, 'TaskExecutionRole', {
      roleName: `ecsTaskExecutionRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      description: 'ECS task execution role with Parameter Store and S3 access',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Add custom policy for Systems Manager Parameter Store access
    // This enables secure retrieval of configuration parameters
    taskExecutionRole.addToPolicy(new iam.PolicyStatement({
      sid: 'ParameterStoreAccess',
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:GetParameters',
        'ssm:GetParameter',
        'ssm:GetParametersByPath',
      ],
      resources: [
        `arn:aws:ssm:${this.region}:${this.account}:parameter/myapp/*`,
      ],
    }));

    // Add S3 permissions for environment file access
    taskExecutionRole.addToPolicy(new iam.PolicyStatement({
      sid: 'S3EnvironmentFileAccess',
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
      ],
      resources: [
        `${configBucket.bucketArn}/configs/*`,
      ],
    }));

    // Create ECS task role for runtime container permissions
    // This role is used by the application running inside the container
    const taskRole = new iam.Role(this, 'TaskRole', {
      roleName: `ecsTaskRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      description: 'ECS task role for application runtime permissions',
    });

    // Add runtime parameter access if needed by the application
    taskRole.addToPolicy(new iam.PolicyStatement({
      sid: 'RuntimeParameterAccess',
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:GetParameter',
        'ssm:GetParameters',
      ],
      resources: [
        `arn:aws:ssm:${this.region}:${this.account}:parameter/myapp/shared/*`,
      ],
    }));

    // ========================================
    // ECS Cluster and Log Groups
    // ========================================
    
    // Create ECS cluster with container insights enabled
    const cluster = new ecs.Cluster(this, 'EcsCluster', {
      clusterName: `ecs-envvar-cluster-${uniqueSuffix}`,
      vpc: vpc,
      containerInsights: true, // Enable CloudWatch Container Insights for monitoring
    });

    // Create CloudWatch log groups for task definitions
    const appLogGroup = new logs.LogGroup(this, 'AppLogGroup', {
      logGroupName: `/ecs/envvar-demo-task`,
      retention: logs.RetentionDays.ONE_WEEK, // Adjust retention for production use
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    const envFilesLogGroup = new logs.LogGroup(this, 'EnvFilesLogGroup', {
      logGroupName: `/ecs/envvar-demo-task-envfiles`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ========================================
    // ECS Task Definitions
    // ========================================
    
    // Create comprehensive task definition demonstrating multiple environment variable sources
    const appTaskDefinition = new ecs.FargateTaskDefinition(this, 'AppTaskDefinition', {
      family: 'envvar-demo-task',
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
    });

    // Add container with comprehensive environment variable configuration
    const appContainer = appTaskDefinition.addContainer('AppContainer', {
      image: ecs.ContainerImage.fromRegistry('nginx:latest'),
      essential: true,
      logging: ecs.LogDrivers.awsLogs({
        logGroup: appLogGroup,
        streamPrefix: 'ecs',
      }),
      // Direct environment variables - highest precedence
      environment: {
        'NODE_ENV': 'development',
        'SERVICE_NAME': 'envvar-demo-service',
        'CLUSTER_NAME': cluster.clusterName,
        'DEPLOYMENT_TYPE': 'comprehensive',
      },
      // Systems Manager Parameter Store secrets - secure parameter injection
      secrets: {
        'DATABASE_HOST': ecs.Secret.fromSsmParameter(databaseHostParam),
        'DATABASE_PORT': ecs.Secret.fromSsmParameter(databasePortParam),
        'DATABASE_PASSWORD': ecs.Secret.fromSsmParameter(databasePasswordParam),
        'API_SECRET_KEY': ecs.Secret.fromSsmParameter(apiSecretKeyParam),
        'API_DEBUG': ecs.Secret.fromSsmParameter(apiDebugParam),
      },
      // Environment files from S3 - batch configuration loading
      environmentFiles: [
        ecs.EnvironmentFile.fromS3Bucket(configBucket, 'configs/app-config.env'),
      ],
    });

    // Add port mapping for the nginx container
    appContainer.addPortMappings({
      containerPort: 80,
      protocol: ecs.Protocol.TCP,
    });

    // Create alternative task definition focused on environment files
    const envFilesTaskDefinition = new ecs.FargateTaskDefinition(this, 'EnvFilesTaskDefinition', {
      family: 'envvar-demo-task-envfiles',
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
    });

    // Add container focused on environment file-based configuration
    const envFilesContainer = envFilesTaskDefinition.addContainer('EnvFilesContainer', {
      image: ecs.ContainerImage.fromRegistry('nginx:latest'),
      essential: true,
      logging: ecs.LogDrivers.awsLogs({
        logGroup: envFilesLogGroup,
        streamPrefix: 'ecs',
      }),
      environment: {
        'DEPLOYMENT_TYPE': 'environment-files',
      },
      // Multiple environment files for layered configuration
      environmentFiles: [
        ecs.EnvironmentFile.fromS3Bucket(configBucket, 'configs/app-config.env'),
        ecs.EnvironmentFile.fromS3Bucket(configBucket, 'configs/prod-config.env'),
      ],
    });

    envFilesContainer.addPortMappings({
      containerPort: 80,
      protocol: ecs.Protocol.TCP,
    });

    // ========================================
    // ECS Services
    // ========================================
    
    // Create ECS service for the comprehensive environment variable demo
    const appService = new ecs.FargateService(this, 'AppService', {
      cluster: cluster,
      taskDefinition: appTaskDefinition,
      serviceName: 'envvar-demo-service',
      desiredCount: 1,
      assignPublicIp: true, // For demo purposes - use private subnets with ALB in production
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC, // Use public for demo - consider private with ALB
      },
      enableLogging: true,
      enableExecuteCommand: true, // Enable ECS Exec for debugging
    });

    // Create service for environment files demonstration
    const envFilesService = new ecs.FargateService(this, 'EnvFilesService', {
      cluster: cluster,
      taskDefinition: envFilesTaskDefinition,
      serviceName: 'envvar-demo-envfiles-service',
      desiredCount: 1,
      assignPublicIp: true,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      enableLogging: true,
      enableExecuteCommand: true,
    });

    // ========================================
    // Outputs for Verification and Integration
    // ========================================
    
    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'ECS Cluster name for environment variable management demo',
      exportName: `${this.stackName}-ClusterName`,
    });

    new cdk.CfnOutput(this, 'ConfigBucketName', {
      value: configBucket.bucketName,
      description: 'S3 bucket containing environment configuration files',
      exportName: `${this.stackName}-ConfigBucketName`,
    });

    new cdk.CfnOutput(this, 'AppServiceName', {
      value: appService.serviceName,
      description: 'ECS service demonstrating comprehensive environment variable management',
      exportName: `${this.stackName}-AppServiceName`,
    });

    new cdk.CfnOutput(this, 'EnvFilesServiceName', {
      value: envFilesService.serviceName,
      description: 'ECS service demonstrating environment file-based configuration',
      exportName: `${this.stackName}-EnvFilesServiceName`,
    });

    new cdk.CfnOutput(this, 'TaskExecutionRoleArn', {
      value: taskExecutionRole.roleArn,
      description: 'ECS task execution role with Parameter Store and S3 permissions',
      exportName: `${this.stackName}-TaskExecutionRoleArn`,
    });

    new cdk.CfnOutput(this, 'ParameterStoreHierarchy', {
      value: '/myapp/*',
      description: 'Systems Manager Parameter Store hierarchy for application configuration',
      exportName: `${this.stackName}-ParameterStoreHierarchy`,
    });

    // Output parameter ARNs for reference
    new cdk.CfnOutput(this, 'DatabaseHostParameterArn', {
      value: databaseHostParam.parameterArn,
      description: 'Database host parameter ARN',
    });

    new cdk.CfnOutput(this, 'DatabasePasswordParameterArn', {
      value: databasePasswordParam.parameterArn,
      description: 'Database password secure parameter ARN',
    });

    // Add tags to all resources for better organization and cost tracking
    cdk.Tags.of(this).add('Project', 'ECS-Environment-Variable-Management');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'DevOps-Team');
    cdk.Tags.of(this).add('CostCenter', 'Infrastructure');
  }
}

// ========================================
// CDK Application Entry Point
// ========================================

const app = new cdk.App();

// Deploy the stack with appropriate environment configuration
new EcsTaskDefinitionsEnvironmentVariableManagementStack(app, 'EcsTaskDefinitionsEnvironmentVariableManagementStack', {
  description: 'CDK Stack demonstrating comprehensive ECS Task Definition environment variable management with Parameter Store, S3 environment files, and direct environment variables',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Add stack-level tags
  tags: {
    'Recipe': 'ecs-task-definitions-environment-variable-management',
    'Framework': 'CDK-TypeScript',
    'Version': '1.0',
  },
});

// Synthesize the CDK application
app.synth();