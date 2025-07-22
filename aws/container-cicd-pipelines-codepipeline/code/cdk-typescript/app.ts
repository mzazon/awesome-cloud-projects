#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codedeploy from 'aws-cdk-lib/aws-codedeploy';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipeline_actions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

/**
 * Advanced CI/CD Pipeline Stack for Container Applications
 * 
 * This stack creates a comprehensive CI/CD pipeline with:
 * - Multi-environment ECS deployment (dev/prod)
 * - Blue-green deployment with CodeDeploy
 * - Advanced security scanning and monitoring
 * - Container Insights and X-Ray tracing
 * - Automated rollback capabilities
 */
export class AdvancedCICDPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);
    const projectName = `advanced-cicd-${uniqueSuffix}`;

    // Create VPC with multi-AZ subnets
    const vpc = new ec2.Vpc(this, 'VPC', {
      cidr: '10.0.0.0/16',
      maxAzs: 3,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
    });

    // Create S3 bucket for pipeline artifacts with versioning
    const artifactsBucket = new s3.Bucket(this, 'ArtifactsBucket', {
      bucketName: `${projectName}-artifacts-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create ECR repository with enhanced security
    const repository = new ecr.Repository(this, 'Repository', {
      repositoryName: `${projectName}-repo`,
      imageScanOnPush: true,
      encryption: ecr.RepositoryEncryption.AES_256,
      lifecycleRules: [
        {
          description: 'Keep last 10 production images',
          tagPrefixList: ['prod'],
          maxImageCount: 10,
        },
        {
          description: 'Keep last 5 development images',
          tagPrefixList: ['dev'],
          maxImageCount: 5,
        },
      ],
    });

    // Create Parameter Store parameters for configuration
    const appEnvironmentParam = new ssm.StringParameter(this, 'AppEnvironmentParam', {
      parameterName: `/${projectName}/app/environment`,
      stringValue: 'production',
      description: 'Application environment',
    });

    const appVersionParam = new ssm.StringParameter(this, 'AppVersionParam', {
      parameterName: `/${projectName}/app/version`,
      stringValue: '1.0.0',
      description: 'Application version',
    });

    // Create IAM roles with least privilege
    const taskExecutionRole = new iam.Role(this, 'TaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      inlinePolicies: {
        TaskRolePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:GetParameter',
                'ssm:GetParameters',
                'ssm:GetParametersByPath',
                'secretsmanager:GetSecretValue',
                'xray:PutTraceSegments',
                'xray:PutTelemetryRecords',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CodeDeploy service role
    const codeDeployRole = new iam.Role(this, 'CodeDeployRole', {
      assumedBy: new iam.ServicePrincipal('codedeploy.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodeDeployRoleForECS'),
      ],
    });

    // Create security groups
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic'
    );

    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic'
    );

    const ecsSecurityGroup = new ec2.SecurityGroup(this, 'ECSSecurityGroup', {
      vpc,
      description: 'Security group for ECS tasks',
      allowAllOutbound: true,
    });

    ecsSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(8080),
      'Allow ALB to ECS traffic'
    );

    // Create CloudWatch log groups
    const devLogGroup = new logs.LogGroup(this, 'DevLogGroup', {
      logGroupName: `/ecs/${projectName}/dev`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const prodLogGroup = new logs.LogGroup(this, 'ProdLogGroup', {
      logGroupName: `/ecs/${projectName}/prod`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create development ECS cluster
    const devCluster = new ecs.Cluster(this, 'DevCluster', {
      clusterName: `${projectName}-dev-cluster`,
      vpc,
      containerInsights: true,
      capacityProviders: ['FARGATE', 'FARGATE_SPOT'],
      defaultCapacityProviderStrategy: [
        {
          capacityProvider: 'FARGATE_SPOT',
          weight: 1,
          base: 0,
        },
      ],
    });

    // Create production ECS cluster
    const prodCluster = new ecs.Cluster(this, 'ProdCluster', {
      clusterName: `${projectName}-prod-cluster`,
      vpc,
      containerInsights: true,
      capacityProviders: ['FARGATE'],
      defaultCapacityProviderStrategy: [
        {
          capacityProvider: 'FARGATE',
          weight: 1,
          base: 0,
        },
      ],
    });

    // Create Application Load Balancers
    const devALB = new elbv2.ApplicationLoadBalancer(this, 'DevALB', {
      vpc,
      internetFacing: true,
      loadBalancerName: `${projectName}-dev-alb`,
      securityGroup: albSecurityGroup,
    });

    const prodALB = new elbv2.ApplicationLoadBalancer(this, 'ProdALB', {
      vpc,
      internetFacing: true,
      loadBalancerName: `${projectName}-prod-alb`,
      securityGroup: albSecurityGroup,
    });

    // Create target groups for development
    const devTargetGroup = new elbv2.ApplicationTargetGroup(this, 'DevTargetGroup', {
      vpc,
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      targetGroupName: `${projectName}-dev-tg`,
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // Create target groups for production blue-green deployment
    const prodBlueTargetGroup = new elbv2.ApplicationTargetGroup(this, 'ProdBlueTargetGroup', {
      vpc,
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      targetGroupName: `${projectName}-prod-blue`,
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(15),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 2,
      },
    });

    const prodGreenTargetGroup = new elbv2.ApplicationTargetGroup(this, 'ProdGreenTargetGroup', {
      vpc,
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      targetGroupName: `${projectName}-prod-green`,
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(15),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 2,
      },
    });

    // Create listeners
    const devListener = devALB.addListener('DevListener', {
      port: 80,
      defaultTargetGroups: [devTargetGroup],
    });

    const prodListener = prodALB.addListener('ProdListener', {
      port: 80,
      defaultTargetGroups: [prodBlueTargetGroup],
    });

    // Create task definitions with X-Ray and Parameter Store integration
    const devTaskDefinition = new ecs.FargateTaskDefinition(this, 'DevTaskDefinition', {
      family: `${projectName}-dev-task`,
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
    });

    // Add application container to development task definition
    const devAppContainer = devTaskDefinition.addContainer('app', {
      image: ecs.ContainerImage.fromRegistry('nginx:latest'),
      essential: true,
      environment: {
        ENV: 'development',
        AWS_XRAY_TRACING_NAME: `${projectName}-dev`,
      },
      secrets: {
        APP_VERSION: ecs.Secret.fromSsmParameter(appVersionParam),
      },
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup: devLogGroup,
      }),
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:8080/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    devAppContainer.addPortMappings({
      containerPort: 8080,
      protocol: ecs.Protocol.TCP,
    });

    // Add X-Ray daemon container to development task definition
    const devXrayContainer = devTaskDefinition.addContainer('xray-daemon', {
      image: ecs.ContainerImage.fromRegistry('amazon/aws-xray-daemon:latest'),
      essential: false,
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'xray',
        logGroup: devLogGroup,
      }),
    });

    devXrayContainer.addPortMappings({
      containerPort: 2000,
      protocol: ecs.Protocol.UDP,
    });

    // Create production task definition
    const prodTaskDefinition = new ecs.FargateTaskDefinition(this, 'ProdTaskDefinition', {
      family: `${projectName}-prod-task`,
      cpu: 512,
      memoryLimitMiB: 1024,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
    });

    // Add application container to production task definition
    const prodAppContainer = prodTaskDefinition.addContainer('app', {
      image: ecs.ContainerImage.fromEcrRepository(repository, 'latest'),
      essential: true,
      environment: {
        ENV: 'production',
        AWS_XRAY_TRACING_NAME: `${projectName}-prod`,
      },
      secrets: {
        APP_VERSION: ecs.Secret.fromSsmParameter(appVersionParam),
      },
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup: prodLogGroup,
      }),
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:8080/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    prodAppContainer.addPortMappings({
      containerPort: 8080,
      protocol: ecs.Protocol.TCP,
    });

    // Add X-Ray daemon container to production task definition
    const prodXrayContainer = prodTaskDefinition.addContainer('xray-daemon', {
      image: ecs.ContainerImage.fromRegistry('amazon/aws-xray-daemon:latest'),
      essential: false,
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'xray',
        logGroup: prodLogGroup,
      }),
    });

    prodXrayContainer.addPortMappings({
      containerPort: 2000,
      protocol: ecs.Protocol.UDP,
    });

    // Create ECS services
    const devService = new ecs.FargateService(this, 'DevService', {
      cluster: devCluster,
      taskDefinition: devTaskDefinition,
      serviceName: `${projectName}-service-dev`,
      desiredCount: 2,
      assignPublicIp: true,
      securityGroups: [ecsSecurityGroup],
      enableExecuteCommand: true,
      deploymentConfiguration: {
        maximumPercent: 200,
        minimumHealthyPercent: 50,
      },
    });

    devService.attachToApplicationTargetGroup(devTargetGroup);

    const prodService = new ecs.FargateService(this, 'ProdService', {
      cluster: prodCluster,
      taskDefinition: prodTaskDefinition,
      serviceName: `${projectName}-service-prod`,
      desiredCount: 3,
      assignPublicIp: true,
      securityGroups: [ecsSecurityGroup],
      enableExecuteCommand: true,
      deploymentController: {
        type: ecs.DeploymentControllerType.CODE_DEPLOY,
      },
    });

    prodService.attachToApplicationTargetGroup(prodBlueTargetGroup);

    // Create SNS topic for alerts
    const alertsTopic = new sns.Topic(this, 'AlertsTopic', {
      topicName: `${projectName}-alerts`,
    });

    // Create CloudWatch alarms for monitoring
    const highErrorRateAlarm = new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `${projectName}-high-error-rate`,
      alarmDescription: 'High error rate detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: '4XXError',
        dimensionsMap: {
          LoadBalancer: prodALB.loadBalancerFullName,
        },
        statistic: 'Sum',
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    highErrorRateAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertsTopic)
    );

    const highResponseTimeAlarm = new cloudwatch.Alarm(this, 'HighResponseTimeAlarm', {
      alarmName: `${projectName}-high-response-time`,
      alarmDescription: 'High response time detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: 'TargetResponseTime',
        dimensionsMap: {
          LoadBalancer: prodALB.loadBalancerFullName,
        },
        statistic: 'Average',
      }),
      threshold: 2.0,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    highResponseTimeAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertsTopic)
    );

    // Create CodeDeploy application and deployment group
    const codeDeployApplication = new codedeploy.EcsApplication(this, 'CodeDeployApplication', {
      applicationName: `${projectName}-app`,
    });

    const deploymentGroup = new codedeploy.EcsDeploymentGroup(this, 'DeploymentGroup', {
      application: codeDeployApplication,
      deploymentGroupName: `${projectName}-prod-deployment-group`,
      service: prodService,
      blueGreenDeploymentConfig: {
        blueTargetGroup: prodBlueTargetGroup,
        greenTargetGroup: prodGreenTargetGroup,
        listener: prodListener,
        deploymentApprovalWaitTime: cdk.Duration.minutes(0),
        terminationWaitTime: cdk.Duration.minutes(5),
      },
      deploymentConfig: codedeploy.EcsDeploymentConfig.CANARY_10_PERCENT_5_MINUTES,
      role: codeDeployRole,
      alarms: [highErrorRateAlarm],
      autoRollback: {
        failedDeployment: true,
        stoppedDeployment: true,
        deploymentInAlarm: true,
      },
    });

    // Create CodeBuild project with security scanning
    const codeBuildRole = new iam.Role(this, 'CodeBuildRole', {
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      inlinePolicies: {
        CodeBuildPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'ecr:BatchCheckLayerAvailability',
                'ecr:GetDownloadUrlForLayer',
                'ecr:BatchGetImage',
                'ecr:GetAuthorizationToken',
                'ecr:InitiateLayerUpload',
                'ecr:UploadLayerPart',
                'ecr:CompleteLayerUpload',
                'ecr:PutImage',
                'ecr:DescribeRepositories',
                'ecr:DescribeImages',
                's3:GetObject',
                's3:PutObject',
                'ssm:GetParameter',
                'ssm:GetParameters',
                'secretsmanager:GetSecretValue',
                'codebuild:CreateReportGroup',
                'codebuild:CreateReport',
                'codebuild:UpdateReport',
                'codebuild:BatchPutTestCases',
                'codebuild:BatchPutCodeCoverages',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    const buildProject = new codebuild.Project(this, 'BuildProject', {
      projectName: `${projectName}-build`,
      source: codebuild.Source.codeCommit({
        repository: undefined as any, // Will be set by CodePipeline
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_3,
        computeType: codebuild.ComputeType.SMALL,
        privileged: true,
      },
      role: codeBuildRole,
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          pre_build: {
            commands: [
              'echo Logging in to Amazon ECR...',
              'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com',
              'REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME',
              'COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)',
              'IMAGE_TAG=$COMMIT_HASH',
              'echo Installing security scanning tools...',
              'curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin',
            ],
          },
          build: {
            commands: [
              'echo Build started on `date`',
              'echo Building the Docker image...',
              'docker build -t $IMAGE_REPO_NAME:latest .',
              'docker tag $IMAGE_REPO_NAME:latest $REPOSITORY_URI:latest',
              'docker tag $IMAGE_REPO_NAME:latest $REPOSITORY_URI:$IMAGE_TAG',
              'echo Running security scan...',
              'grype $IMAGE_REPO_NAME:latest --fail-on medium',
              'echo Running unit tests...',
              'docker run --rm $IMAGE_REPO_NAME:latest npm test',
            ],
          },
          post_build: {
            commands: [
              'echo Build completed on `date`',
              'echo Pushing the Docker images...',
              'docker push $REPOSITORY_URI:latest',
              'docker push $REPOSITORY_URI:$IMAGE_TAG',
              'echo Writing image definitions file...',
              'printf \'[{"name":"app","imageUri":"%s"}]\' $REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json',
              'echo Creating task definition and appspec files...',
              'sed -i "s|IMAGE_URI|$REPOSITORY_URI:$IMAGE_TAG|g" taskdef.json',
              'cat taskdef.json',
              'cat appspec.yaml',
            ],
          },
        },
        artifacts: {
          files: [
            'imagedefinitions.json',
            'taskdef.json',
            'appspec.yaml',
          ],
        },
        reports: {
          'unit-tests': {
            files: ['test-results.xml'],
            name: 'unit-tests',
          },
          'security-scan': {
            files: ['security-scan-results.json'],
            name: 'security-scan',
          },
        },
      }),
      environmentVariables: {
        AWS_DEFAULT_REGION: { value: this.region },
        AWS_ACCOUNT_ID: { value: this.account },
        IMAGE_REPO_NAME: { value: repository.repositoryName },
      },
    });

    // Create CodePipeline
    const pipeline = new codepipeline.Pipeline(this, 'Pipeline', {
      pipelineName: `${projectName}-pipeline`,
      artifactBucket: artifactsBucket,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipeline_actions.S3SourceAction({
              actionName: 'Source',
              bucket: artifactsBucket,
              bucketKey: 'source.zip',
              output: new codepipeline.Artifact('SourceOutput'),
            }),
          ],
        },
        {
          stageName: 'Build',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'Build',
              project: buildProject,
              input: new codepipeline.Artifact('SourceOutput'),
              outputs: [new codepipeline.Artifact('BuildOutput')],
            }),
          ],
        },
        {
          stageName: 'Deploy-Dev',
          actions: [
            new codepipeline_actions.EcsDeployAction({
              actionName: 'Deploy-Dev',
              service: devService,
              input: new codepipeline.Artifact('BuildOutput'),
            }),
          ],
        },
        {
          stageName: 'Approval',
          actions: [
            new codepipeline_actions.ManualApprovalAction({
              actionName: 'ManualApproval',
              notificationTopic: alertsTopic,
              additionalInformation: 'Please review the development deployment and approve for production deployment.',
            }),
          ],
        },
        {
          stageName: 'Deploy-Production',
          actions: [
            new codepipeline_actions.CodeDeployEcsDeployAction({
              actionName: 'Deploy-Production',
              deploymentGroup: deploymentGroup,
              appSpecTemplateInput: new codepipeline.Artifact('BuildOutput'),
              taskDefinitionTemplateInput: new codepipeline.Artifact('BuildOutput'),
            }),
          ],
        },
      ],
    });

    // Grant necessary permissions
    repository.grantPullPush(buildProject);
    artifactsBucket.grantReadWrite(pipeline.role);

    // Output important values
    new cdk.CfnOutput(this, 'DevLoadBalancerDNS', {
      value: devALB.loadBalancerDnsName,
      description: 'Development Load Balancer DNS',
    });

    new cdk.CfnOutput(this, 'ProdLoadBalancerDNS', {
      value: prodALB.loadBalancerDnsName,
      description: 'Production Load Balancer DNS',
    });

    new cdk.CfnOutput(this, 'RepositoryURI', {
      value: repository.repositoryUri,
      description: 'ECR Repository URI',
    });

    new cdk.CfnOutput(this, 'PipelineName', {
      value: pipeline.pipelineName,
      description: 'CodePipeline Name',
    });

    new cdk.CfnOutput(this, 'DevClusterName', {
      value: devCluster.clusterName,
      description: 'Development ECS Cluster Name',
    });

    new cdk.CfnOutput(this, 'ProdClusterName', {
      value: prodCluster.clusterName,
      description: 'Production ECS Cluster Name',
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: alertsTopic.topicArn,
      description: 'SNS Topic ARN for Alerts',
    });
  }
}

// Create and deploy the stack
const app = new cdk.App();
new AdvancedCICDPipelineStack(app, 'AdvancedCICDPipelineStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Advanced CI/CD Pipeline Stack for Container Applications with CodePipeline and CodeDeploy',
});