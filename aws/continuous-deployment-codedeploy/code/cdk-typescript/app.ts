#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as codedeploy from 'aws-cdk-lib/aws-codedeploy';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';

/**
 * Properties for the ContinuousDeploymentCodeDeployStack
 */
export interface ContinuousDeploymentCodeDeployStackProps extends cdk.StackProps {
  /**
   * The name of the application
   * @default 'webapp'
   */
  readonly appName?: string;

  /**
   * The name of the CodeCommit repository
   * @default 'webapp-repo'
   */
  readonly repositoryName?: string;

  /**
   * The name of the CodeBuild project
   * @default 'webapp-build'
   */
  readonly buildProjectName?: string;

  /**
   * The name of the deployment group
   * @default 'webapp-depgroup'
   */
  readonly deploymentGroupName?: string;

  /**
   * The EC2 key pair name for instances
   * @default 'webapp-keypair'
   */
  readonly keyPairName?: string;

  /**
   * The EC2 instance type for the Auto Scaling Group
   * @default 't3.micro'
   */
  readonly instanceType?: string;

  /**
   * The minimum number of instances in the Auto Scaling Group
   * @default 2
   */
  readonly minCapacity?: number;

  /**
   * The maximum number of instances in the Auto Scaling Group
   * @default 4
   */
  readonly maxCapacity?: number;

  /**
   * The desired number of instances in the Auto Scaling Group
   * @default 2
   */
  readonly desiredCapacity?: number;
}

/**
 * CDK Stack for Continuous Deployment with CodeDeploy
 * 
 * This stack creates a complete CI/CD pipeline for blue-green deployments using:
 * - CodeCommit for source control
 * - CodeBuild for build automation
 * - CodeDeploy for application deployment
 * - Application Load Balancer for traffic routing
 * - Auto Scaling Group for compute resources
 * - CloudWatch for monitoring and alarms
 */
export class ContinuousDeploymentCodeDeployStack extends cdk.Stack {
  /**
   * The VPC where resources will be created
   */
  public readonly vpc: ec2.IVpc;

  /**
   * The Application Load Balancer
   */
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;

  /**
   * The CodeCommit repository
   */
  public readonly repository: codecommit.Repository;

  /**
   * The CodeBuild project
   */
  public readonly buildProject: codebuild.Project;

  /**
   * The CodeDeploy application
   */
  public readonly codeDeployApplication: codedeploy.ServerApplication;

  /**
   * The Auto Scaling Group
   */
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;

  constructor(scope: Construct, id: string, props: ContinuousDeploymentCodeDeployStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const appName = props.appName ?? 'webapp';
    const repositoryName = props.repositoryName ?? 'webapp-repo';
    const buildProjectName = props.buildProjectName ?? 'webapp-build';
    const deploymentGroupName = props.deploymentGroupName ?? 'webapp-depgroup';
    const keyPairName = props.keyPairName ?? 'webapp-keypair';
    const instanceType = props.instanceType ?? 't3.micro';
    const minCapacity = props.minCapacity ?? 2;
    const maxCapacity = props.maxCapacity ?? 4;
    const desiredCapacity = props.desiredCapacity ?? 2;

    // Use default VPC or create a new one
    this.vpc = ec2.Vpc.fromLookup(this, 'VPC', {
      isDefault: true,
    });

    // Create IAM roles
    const codeDeployServiceRole = this.createCodeDeployServiceRole();
    const ec2InstanceRole = this.createEC2InstanceRole();
    const codeBuildServiceRole = this.createCodeBuildServiceRole();

    // Create S3 bucket for artifacts
    const artifactsBucket = new s3.Bucket(this, 'ArtifactsBucket', {
      bucketName: `codedeploy-artifacts-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    // Create security groups
    const albSecurityGroup = this.createALBSecurityGroup();
    const ec2SecurityGroup = this.createEC2SecurityGroup(albSecurityGroup);

    // Create Application Load Balancer and target groups
    const { loadBalancer, blueTargetGroup, greenTargetGroup } = this.createLoadBalancer(
      albSecurityGroup
    );
    this.loadBalancer = loadBalancer;

    // Create Auto Scaling Group with launch template
    this.autoScalingGroup = this.createAutoScalingGroup(
      keyPairName,
      instanceType,
      minCapacity,
      maxCapacity,
      desiredCapacity,
      ec2SecurityGroup,
      ec2InstanceRole,
      blueTargetGroup
    );

    // Create CodeCommit repository
    this.repository = this.createCodeCommitRepository(repositoryName);

    // Create CodeBuild project
    this.buildProject = this.createCodeBuildProject(
      buildProjectName,
      this.repository,
      artifactsBucket,
      codeBuildServiceRole
    );

    // Create CodeDeploy application and deployment group
    this.codeDeployApplication = this.createCodeDeployApplication(appName);
    const deploymentGroup = this.createDeploymentGroup(
      deploymentGroupName,
      this.codeDeployApplication,
      codeDeployServiceRole,
      this.autoScalingGroup,
      blueTargetGroup
    );

    // Create CloudWatch alarms
    this.createCloudWatchAlarms(appName, this.codeDeployApplication, deploymentGroup, blueTargetGroup);

    // Create SNS topic for notifications
    const notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${appName}-notifications`,
      displayName: 'CodeDeploy Deployment Notifications',
    });

    // Output important information
    this.createOutputs(appName, repositoryName, buildProjectName, loadBalancer, notificationTopic);
  }

  /**
   * Creates the CodeDeploy service role with necessary permissions
   */
  private createCodeDeployServiceRole(): iam.Role {
    const role = new iam.Role(this, 'CodeDeployServiceRole', {
      roleName: 'CodeDeployServiceRole',
      assumedBy: new iam.ServicePrincipal('codedeploy.amazonaws.com'),
      description: 'Service role for CodeDeploy to perform deployments',
    });

    // Attach AWS managed policy for CodeDeploy
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSCodeDeployRole')
    );

    return role;
  }

  /**
   * Creates the EC2 instance role with necessary permissions for CodeDeploy agent
   */
  private createEC2InstanceRole(): iam.Role {
    const role = new iam.Role(this, 'CodeDeployEC2Role', {
      roleName: 'CodeDeployEC2Role',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'Role for EC2 instances to interact with CodeDeploy',
    });

    // Attach AWS managed policies
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2RoleforAWSCodeDeploy')
    );
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy')
    );

    return role;
  }

  /**
   * Creates the CodeBuild service role with necessary permissions
   */
  private createCodeBuildServiceRole(): iam.Role {
    const role = new iam.Role(this, 'CodeBuildServiceRole', {
      roleName: 'CodeBuildServiceRole',
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      description: 'Service role for CodeBuild to build projects',
    });

    // Add inline policy for CodeBuild permissions
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'codecommit:GitPull',
          's3:GetObject',
          's3:PutObject',
          's3:GetBucketLocation',
          's3:ListBucket',
        ],
        resources: ['*'],
      })
    );

    return role;
  }

  /**
   * Creates security group for the Application Load Balancer
   */
  private createALBSecurityGroup(): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from anywhere
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from anywhere'
    );

    // Allow HTTPS traffic from anywhere
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from anywhere'
    );

    return securityGroup;
  }

  /**
   * Creates security group for EC2 instances
   */
  private createEC2SecurityGroup(albSecurityGroup: ec2.SecurityGroup): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'EC2SecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for EC2 instances',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from ALB
    securityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(80),
      'Allow HTTP traffic from ALB'
    );

    // Allow SSH access (for debugging)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access'
    );

    return securityGroup;
  }

  /**
   * Creates Application Load Balancer with blue and green target groups
   */
  private createLoadBalancer(albSecurityGroup: ec2.SecurityGroup): {
    loadBalancer: elbv2.ApplicationLoadBalancer;
    blueTargetGroup: elbv2.ApplicationTargetGroup;
    greenTargetGroup: elbv2.ApplicationTargetGroup;
  } {
    const loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'ApplicationLoadBalancer', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
      loadBalancerName: 'webapp-alb',
    });

    // Create blue target group
    const blueTargetGroup = new elbv2.ApplicationTargetGroup(this, 'BlueTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetGroupName: 'webapp-tg-blue',
      healthCheck: {
        path: '/',
        intervalSeconds: 30,
        timeoutSeconds: 5,
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // Create green target group
    const greenTargetGroup = new elbv2.ApplicationTargetGroup(this, 'GreenTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetGroupName: 'webapp-tg-green',
      healthCheck: {
        path: '/',
        intervalSeconds: 30,
        timeoutSeconds: 5,
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // Create listener that initially routes to blue target group
    const listener = loadBalancer.addListener('Listener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [blueTargetGroup],
    });

    return { loadBalancer, blueTargetGroup, greenTargetGroup };
  }

  /**
   * Creates Auto Scaling Group with launch template
   */
  private createAutoScalingGroup(
    keyPairName: string,
    instanceType: string,
    minCapacity: number,
    maxCapacity: number,
    desiredCapacity: number,
    securityGroup: ec2.SecurityGroup,
    instanceRole: iam.Role,
    targetGroup: elbv2.ApplicationTargetGroup
  ): autoscaling.AutoScalingGroup {
    // Get Amazon Linux 2 AMI
    const amznLinux = ec2.MachineImage.latestAmazonLinux({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
    });

    // Create user data script to install CodeDeploy agent and setup web server
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      'yum update -y',
      'yum install -y ruby wget httpd',
      'systemctl start httpd',
      'systemctl enable httpd',
      'echo "<h1>Blue Environment - Version 1.0</h1>" > /var/www/html/index.html',
      'cd /home/ec2-user',
      'wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install',
      'chmod +x ./install',
      './install auto',
      'systemctl start codedeploy-agent',
      'systemctl enable codedeploy-agent'
    );

    // Create Auto Scaling Group
    const asg = new autoscaling.AutoScalingGroup(this, 'AutoScalingGroup', {
      vpc: this.vpc,
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: amznLinux,
      userData: userData,
      minCapacity: minCapacity,
      maxCapacity: maxCapacity,
      desiredCapacity: desiredCapacity,
      keyName: keyPairName,
      securityGroup: securityGroup,
      role: instanceRole,
      autoScalingGroupName: 'webapp-asg',
      healthCheck: autoscaling.HealthCheck.elb({
        grace: cdk.Duration.seconds(300),
      }),
    });

    // Attach to target group
    asg.attachToApplicationTargetGroup(targetGroup);

    // Add tags
    cdk.Tags.of(asg).add('Name', 'webapp-instance');
    cdk.Tags.of(asg).add('Environment', 'blue');

    return asg;
  }

  /**
   * Creates CodeCommit repository
   */
  private createCodeCommitRepository(repositoryName: string): codecommit.Repository {
    const repository = new codecommit.Repository(this, 'Repository', {
      repositoryName: repositoryName,
      description: 'Repository for webapp deployment',
    });

    return repository;
  }

  /**
   * Creates CodeBuild project
   */
  private createCodeBuildProject(
    buildProjectName: string,
    repository: codecommit.Repository,
    artifactsBucket: s3.Bucket,
    serviceRole: iam.Role
  ): codebuild.Project {
    const project = new codebuild.Project(this, 'BuildProject', {
      projectName: buildProjectName,
      source: codebuild.Source.codeCommit({
        repository: repository,
        branchOrRef: 'main',
      }),
      artifacts: codebuild.Artifacts.s3({
        bucket: artifactsBucket,
        name: 'artifacts',
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_3,
        computeType: codebuild.ComputeType.SMALL,
      },
      role: serviceRole,
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          install: {
            'runtime-versions': {
              nodejs: '14',
            },
          },
          pre_build: {
            commands: [
              'echo Logging in to Amazon ECR...',
              'echo Build started on `date`',
            ],
          },
          build: {
            commands: [
              'echo Build completed on `date`',
            ],
          },
        },
        artifacts: {
          files: ['**/*'],
        },
      }),
    });

    return project;
  }

  /**
   * Creates CodeDeploy application
   */
  private createCodeDeployApplication(appName: string): codedeploy.ServerApplication {
    const application = new codedeploy.ServerApplication(this, 'CodeDeployApplication', {
      applicationName: appName,
    });

    return application;
  }

  /**
   * Creates CodeDeploy deployment group
   */
  private createDeploymentGroup(
    deploymentGroupName: string,
    application: codedeploy.ServerApplication,
    serviceRole: iam.Role,
    autoScalingGroup: autoscaling.AutoScalingGroup,
    targetGroup: elbv2.ApplicationTargetGroup
  ): codedeploy.ServerDeploymentGroup {
    const deploymentGroup = new codedeploy.ServerDeploymentGroup(this, 'DeploymentGroup', {
      application: application,
      deploymentGroupName: deploymentGroupName,
      role: serviceRole,
      deploymentConfig: codedeploy.ServerDeploymentConfig.ALL_AT_ONCE_BLUE_GREEN,
      autoScalingGroups: [autoScalingGroup],
      loadBalancer: codedeploy.LoadBalancer.application(targetGroup),
      blueGreenDeploymentConfig: {
        terminateBlueInstancesOnDeploymentSuccess: {
          action: codedeploy.TerminationAction.TERMINATE,
          terminationWaitTime: cdk.Duration.minutes(5),
        },
        deploymentReadyOption: {
          actionOnTimeout: codedeploy.ActionOnTimeout.CONTINUE_DEPLOYMENT,
        },
        greenFleetProvisioningOption: {
          action: codedeploy.GreenFleetProvisioningAction.COPY_AUTO_SCALING_GROUP,
        },
      },
      autoRollback: {
        failedDeployment: true,
        stoppedDeployment: true,
        deploymentInAlarm: true,
      },
    });

    return deploymentGroup;
  }

  /**
   * Creates CloudWatch alarms for monitoring
   */
  private createCloudWatchAlarms(
    appName: string,
    application: codedeploy.ServerApplication,
    deploymentGroup: codedeploy.ServerDeploymentGroup,
    targetGroup: elbv2.ApplicationTargetGroup
  ): void {
    // Create alarm for deployment failures
    const deploymentFailureAlarm = new cloudwatch.Alarm(this, 'DeploymentFailureAlarm', {
      alarmName: `${appName}-deployment-failure`,
      alarmDescription: 'Alarm for CodeDeploy deployment failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CodeDeploy',
        metricName: 'FailedDeployments',
        dimensionsMap: {
          ApplicationName: application.applicationName,
          DeploymentGroupName: deploymentGroup.deploymentGroupName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
    });

    // Create alarm for target group health
    const targetHealthAlarm = new cloudwatch.Alarm(this, 'TargetHealthAlarm', {
      alarmName: `${appName}-target-health`,
      alarmDescription: 'Alarm for target group health',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: 'HealthyHostCount',
        dimensionsMap: {
          TargetGroup: targetGroup.targetGroupFullName,
          LoadBalancer: this.loadBalancer.loadBalancerFullName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Add alarms to deployment group
    deploymentGroup.addAlarm(deploymentFailureAlarm);
    deploymentGroup.addAlarm(targetHealthAlarm);
  }

  /**
   * Creates stack outputs
   */
  private createOutputs(
    appName: string,
    repositoryName: string,
    buildProjectName: string,
    loadBalancer: elbv2.ApplicationLoadBalancer,
    notificationTopic: sns.Topic
  ): void {
    new cdk.CfnOutput(this, 'ApplicationName', {
      value: appName,
      description: 'Name of the CodeDeploy application',
    });

    new cdk.CfnOutput(this, 'RepositoryName', {
      value: repositoryName,
      description: 'Name of the CodeCommit repository',
    });

    new cdk.CfnOutput(this, 'BuildProjectName', {
      value: buildProjectName,
      description: 'Name of the CodeBuild project',
    });

    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: loadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
    });

    new cdk.CfnOutput(this, 'ApplicationURL', {
      value: `http://${loadBalancer.loadBalancerDnsName}`,
      description: 'URL of the deployed application',
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'ARN of the SNS topic for notifications',
    });

    new cdk.CfnOutput(this, 'RepositoryCloneUrlHttp', {
      value: this.repository.repositoryCloneUrlHttp,
      description: 'HTTP clone URL for the CodeCommit repository',
    });

    new cdk.CfnOutput(this, 'RepositoryCloneUrlSsh', {
      value: this.repository.repositoryCloneUrlSsh,
      description: 'SSH clone URL for the CodeCommit repository',
    });
  }
}

/**
 * Main CDK App
 */
const app = new cdk.App();

// Create the main stack
new ContinuousDeploymentCodeDeployStack(app, 'ContinuousDeploymentCodeDeployStack', {
  description: 'Continuous Deployment with CodeDeploy - Blue-Green Deployment Pipeline',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ContinuousDeploymentCodeDeploy',
    Environment: 'Development',
    Owner: 'DevOps Team',
  },
});

app.synth();