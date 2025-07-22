import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as codedeploy from 'aws-cdk-lib/aws-codedeploy';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as path from 'path';
import { Construct } from 'constructs';

export interface AdvancedBlueGreenDeploymentStackProps extends cdk.StackProps {
  projectName: string;
  environment: string;
}

export class AdvancedBlueGreenDeploymentStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: AdvancedBlueGreenDeploymentStackProps) {
    super(scope, id, props);

    const { projectName, environment } = props;
    
    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);
    
    // VPC - Use default VPC or create new one
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true,
    });

    // ECR Repository for container images
    const ecrRepository = new ecr.Repository(this, 'WebAppRepository', {
      repositoryName: `web-app-${uniqueSuffix}`,
      imageScanOnPush: true,
      lifecycleRules: [
        {
          tagStatus: ecr.TagStatus.UNTAGGED,
          maxImageAge: cdk.Duration.days(7),
        },
        {
          tagStatus: ecr.TagStatus.ANY,
          maxImageCount: 10,
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // CloudWatch Log Group for ECS
    const logGroup = new logs.LogGroup(this, 'ECSLogGroup', {
      logGroupName: `/ecs/${projectName}-service-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM Roles
    
    // ECS Task Execution Role
    const ecsExecutionRole = new iam.Role(this, 'ECSExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // ECS Task Role
    const ecsTaskRole = new iam.Role(this, 'ECSTaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      inlinePolicies: {
        ECSTaskPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // CodeDeploy Service Role
    const codeDeployRole = new iam.Role(this, 'CodeDeployRole', {
      assumedBy: new iam.ServicePrincipal('codedeploy.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodeDeployRoleForECS'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSCodeDeployRoleForLambda'),
      ],
    });

    // Lambda Execution Role
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CloudWatchMetrics: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Application Load Balancer Security Group
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

    // ECS Security Group
    const ecsSecurityGroup = new ec2.SecurityGroup(this, 'ECSSecurityGroup', {
      vpc,
      description: 'Security group for ECS tasks',
      allowAllOutbound: true,
    });

    ecsSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(8080),
      'Allow traffic from ALB'
    );

    // Application Load Balancer
    const alb = new elbv2.ApplicationLoadBalancer(this, 'ApplicationLoadBalancer', {
      vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
      loadBalancerName: `${projectName}-alb-${uniqueSuffix}`,
    });

    // Target Groups for Blue-Green Deployment
    const blueTargetGroup = new elbv2.ApplicationTargetGroup(this, 'BlueTargetGroup', {
      vpc,
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      targetGroupName: `${projectName}-blue-${uniqueSuffix}`,
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    const greenTargetGroup = new elbv2.ApplicationTargetGroup(this, 'GreenTargetGroup', {
      vpc,
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      targetGroupName: `${projectName}-green-${uniqueSuffix}`,
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // ALB Listener
    const listener = alb.addListener('HTTPListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [blueTargetGroup],
    });

    // ECS Cluster
    const cluster = new ecs.Cluster(this, 'ECSCluster', {
      vpc,
      clusterName: `${projectName}-cluster-${uniqueSuffix}`,
      capacityProviders: ['FARGATE'],
      enableFargateCapacityProviders: true,
    });

    // ECS Task Definition
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'TaskDefinition', {
      family: `${projectName}-service-${uniqueSuffix}`,
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole: ecsExecutionRole,
      taskRole: ecsTaskRole,
    });

    // Container Definition
    const container = taskDefinition.addContainer('WebAppContainer', {
      containerName: 'web-app',
      image: ecs.ContainerImage.fromEcrRepository(ecrRepository, '1.0.0'),
      portMappings: [
        {
          containerPort: 8080,
          protocol: ecs.Protocol.TCP,
        },
      ],
      environment: {
        APP_VERSION: '1.0.0',
        ENVIRONMENT: 'blue',
        PORT: '8080',
      },
      logging: ecs.LogDrivers.awsLogs({
        logGroup,
        streamPrefix: 'ecs',
      }),
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:8080/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
      essential: true,
    });

    // ECS Service
    const ecsService = new ecs.FargateService(this, 'ECSService', {
      cluster,
      taskDefinition,
      serviceName: `${projectName}-service-${uniqueSuffix}`,
      desiredCount: 2,
      assignPublicIp: true,
      securityGroups: [ecsSecurityGroup],
      enableExecuteCommand: true,
      deploymentConfiguration: {
        maximumPercent: 200,
        minimumHealthyPercent: 50,
      },
    });

    // Associate ECS service with blue target group
    ecsService.attachToApplicationTargetGroup(blueTargetGroup);

    // Lambda Function for API Backend
    const apiFunction = new lambda.Function(this, 'APIFunction', {
      functionName: `api-function-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../lambda')),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        VERSION: '1.0.0',
        ENVIRONMENT: 'blue',
      },
      description: 'Lambda function for blue-green deployment demo',
    });

    // Lambda Alias for production traffic
    const lambdaAlias = new lambda.Alias(this, 'LambdaProductionAlias', {
      aliasName: 'PROD',
      version: apiFunction.currentVersion,
      description: 'Production alias for blue-green deployments',
    });

    // SNS Topic for notifications
    const notificationTopic = new sns.Topic(this, 'DeploymentNotifications', {
      topicName: `deployment-notifications-${uniqueSuffix}`,
      displayName: 'Deployment Notifications',
    });

    // CloudWatch Alarms for ECS Service
    const ecsHighErrorRateAlarm = new cloudwatch.Alarm(this, 'ECSHighErrorRateAlarm', {
      alarmName: `${projectName}-ecs-high-error-rate-${uniqueSuffix}`,
      alarmDescription: 'High error rate in ECS service',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: 'HTTPCode_Target_5XX_Count',
        dimensionsMap: {
          LoadBalancer: alb.loadBalancerFullName,
          TargetGroup: greenTargetGroup.targetGroupFullName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 10,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 3,
    });

    ecsHighErrorRateAlarm.addAlarmAction(new cloudwatch.SnsAction(notificationTopic));

    const ecsHighResponseTimeAlarm = new cloudwatch.Alarm(this, 'ECSHighResponseTimeAlarm', {
      alarmName: `${projectName}-ecs-high-response-time-${uniqueSuffix}`,
      alarmDescription: 'High response time in ECS service',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: 'TargetResponseTime',
        dimensionsMap: {
          LoadBalancer: alb.loadBalancerFullName,
          TargetGroup: greenTargetGroup.targetGroupFullName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 2.0,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 5,
    });

    ecsHighResponseTimeAlarm.addAlarmAction(new cloudwatch.SnsAction(notificationTopic));

    // CloudWatch Alarms for Lambda Function
    const lambdaHighErrorRateAlarm = new cloudwatch.Alarm(this, 'LambdaHighErrorRateAlarm', {
      alarmName: `${projectName}-lambda-high-error-rate-${uniqueSuffix}`,
      alarmDescription: 'High error rate in Lambda function',
      metric: apiFunction.metricErrors({
        period: cdk.Duration.minutes(1),
        statistic: 'Sum',
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 3,
    });

    lambdaHighErrorRateAlarm.addAlarmAction(new cloudwatch.SnsAction(notificationTopic));

    const lambdaHighDurationAlarm = new cloudwatch.Alarm(this, 'LambdaHighDurationAlarm', {
      alarmName: `${projectName}-lambda-high-duration-${uniqueSuffix}`,
      alarmDescription: 'High duration in Lambda function',
      metric: apiFunction.metricDuration({
        period: cdk.Duration.minutes(1),
        statistic: 'Average',
      }),
      threshold: 5000,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 5,
    });

    lambdaHighDurationAlarm.addAlarmAction(new cloudwatch.SnsAction(notificationTopic));

    // Deployment Hook Lambda Functions
    const deploymentHookRole = new iam.Role(this, 'DeploymentHookRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DeploymentHookPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codedeploy:PutLifecycleEventHookExecutionStatus',
                'ecs:DescribeServices',
                'ecs:DescribeTasks',
                'lambda:InvokeFunction',
                'cloudwatch:PutMetricData',
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

    const preDeploymentHook = new lambda.Function(this, 'PreDeploymentHook', {
      functionName: `${projectName}-pre-deployment-hook-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'pre_deployment_hook.lambda_handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../hooks')),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: deploymentHookRole,
      description: 'Pre-deployment validation hook',
    });

    const postDeploymentHook = new lambda.Function(this, 'PostDeploymentHook', {
      functionName: `${projectName}-post-deployment-hook-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'post_deployment_hook.lambda_handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../hooks')),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: deploymentHookRole,
      environment: {
        ALB_DNS: alb.loadBalancerDnsName,
        LAMBDA_FUNCTION_NAME: apiFunction.functionName,
      },
      description: 'Post-deployment validation hook',
    });

    // CodeDeploy Applications
    const ecsApplication = new codedeploy.EcsApplication(this, 'ECSApplication', {
      applicationName: `ecs-deployment-${uniqueSuffix}`,
    });

    const lambdaApplication = new codedeploy.LambdaApplication(this, 'LambdaApplication', {
      applicationName: `lambda-deployment-${uniqueSuffix}`,
    });

    // CodeDeploy Deployment Groups
    const ecsDeploymentGroup = new codedeploy.EcsDeploymentGroup(this, 'ECSDeploymentGroup', {
      application: ecsApplication,
      deploymentGroupName: `${projectName}-ecs-deployment-group-${uniqueSuffix}`,
      service: ecsService,
      blueGreenDeploymentConfig: {
        blueTargetGroup,
        greenTargetGroup,
        listener,
        deploymentApprovalWaitTime: cdk.Duration.minutes(0),
        terminationWaitTime: cdk.Duration.minutes(5),
      },
      role: codeDeployRole,
      autoRollback: {
        failedDeployment: true,
        stoppedDeployment: true,
        deploymentInAlarm: true,
      },
      alarms: [
        ecsHighErrorRateAlarm,
        ecsHighResponseTimeAlarm,
      ],
    });

    const lambdaDeploymentGroup = new codedeploy.LambdaDeploymentGroup(this, 'LambdaDeploymentGroup', {
      application: lambdaApplication,
      deploymentGroupName: `${projectName}-lambda-deployment-group-${uniqueSuffix}`,
      alias: lambdaAlias,
      deploymentConfig: codedeploy.LambdaDeploymentConfig.LINEAR_10PERCENT_EVERY_1MINUTE,
      role: codeDeployRole,
      autoRollback: {
        failedDeployment: true,
        stoppedDeployment: true,
        deploymentInAlarm: true,
      },
      alarms: [
        lambdaHighErrorRateAlarm,
        lambdaHighDurationAlarm,
      ],
      preHook: preDeploymentHook,
      postHook: postDeploymentHook,
    });

    // CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'DeploymentDashboard', {
      dashboardName: `Blue-Green-Deployments-${projectName}-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'ALB Performance Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ApplicationELB',
                metricName: 'TargetResponseTime',
                dimensionsMap: {
                  LoadBalancer: alb.loadBalancerFullName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/ApplicationELB',
                metricName: 'HTTPCode_Target_2XX_Count',
                dimensionsMap: {
                  LoadBalancer: alb.loadBalancerFullName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/ApplicationELB',
                metricName: 'HTTPCode_Target_5XX_Count',
                dimensionsMap: {
                  LoadBalancer: alb.loadBalancerFullName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'ECS Service Metrics',
            left: [
              ecsService.metricCpuUtilization({
                period: cdk.Duration.minutes(5),
              }),
              ecsService.metricMemoryUtilization({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 8,
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              apiFunction.metricDuration({
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              apiFunction.metricInvocations({
                period: cdk.Duration.minutes(5),
              }),
              apiFunction.metricErrors({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 8,
          }),
        ],
      ],
    });

    // Outputs
    new cdk.CfnOutput(this, 'ECRRepositoryURI', {
      value: ecrRepository.repositoryUri,
      description: 'ECR Repository URI for container images',
      exportName: `${this.stackName}-ECRRepositoryURI`,
    });

    new cdk.CfnOutput(this, 'ALBDNSName', {
      value: alb.loadBalancerDnsName,
      description: 'Application Load Balancer DNS name',
      exportName: `${this.stackName}-ALBDNSName`,
    });

    new cdk.CfnOutput(this, 'ECSClusterName', {
      value: cluster.clusterName,
      description: 'ECS Cluster name',
      exportName: `${this.stackName}-ECSClusterName`,
    });

    new cdk.CfnOutput(this, 'ECSServiceName', {
      value: ecsService.serviceName,
      description: 'ECS Service name',
      exportName: `${this.stackName}-ECSServiceName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: apiFunction.functionName,
      description: 'Lambda function name',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionARN', {
      value: apiFunction.functionArn,
      description: 'Lambda function ARN',
      exportName: `${this.stackName}-LambdaFunctionARN`,
    });

    new cdk.CfnOutput(this, 'ECSCodeDeployApplication', {
      value: ecsApplication.applicationName,
      description: 'CodeDeploy application for ECS',
      exportName: `${this.stackName}-ECSCodeDeployApplication`,
    });

    new cdk.CfnOutput(this, 'LambdaCodeDeployApplication', {
      value: lambdaApplication.applicationName,
      description: 'CodeDeploy application for Lambda',
      exportName: `${this.stackName}-LambdaCodeDeployApplication`,
    });

    new cdk.CfnOutput(this, 'BlueTargetGroupARN', {
      value: blueTargetGroup.targetGroupArn,
      description: 'Blue target group ARN',
      exportName: `${this.stackName}-BlueTargetGroupARN`,
    });

    new cdk.CfnOutput(this, 'GreenTargetGroupARN', {
      value: greenTargetGroup.targetGroupArn,
      description: 'Green target group ARN',
      exportName: `${this.stackName}-GreenTargetGroupARN`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
      exportName: `${this.stackName}-DashboardURL`,
    });
  }
}