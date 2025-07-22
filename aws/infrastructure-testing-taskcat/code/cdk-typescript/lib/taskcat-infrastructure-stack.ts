import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import { Construct } from 'constructs';

export interface TaskCatInfrastructureStackProps extends cdk.StackProps {
  /**
   * The VPC CIDR block for test infrastructure
   * @default '10.0.0.0/16'
   */
  readonly vpcCidr?: string;

  /**
   * Environment name for resource tagging
   * @default 'TaskCatDemo'
   */
  readonly environmentName?: string;

  /**
   * Whether to create NAT Gateway for private subnets
   * @default true
   */
  readonly createNatGateway?: boolean;

  /**
   * Enable automated TaskCat testing on code changes
   * @default false
   */
  readonly enableAutomatedTesting?: boolean;
}

export class TaskCatInfrastructureStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly taskCatBucket: s3.Bucket;
  public readonly testingRole: iam.Role;
  public readonly codeRepository: codecommit.Repository;
  public readonly buildProject: codebuild.Project;

  constructor(scope: Construct, id: string, props: TaskCatInfrastructureStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const vpcCidr = props.vpcCidr ?? '10.0.0.0/16';
    const environmentName = props.environmentName ?? 'TaskCatDemo';
    const createNatGateway = props.createNatGateway ?? true;
    const enableAutomatedTesting = props.enableAutomatedTesting ?? false;

    // Generate unique suffix for resources
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);

    // Create VPC for testing infrastructure
    this.vpc = new ec2.Vpc(this, 'TaskCatVPC', {
      ipAddresses: ec2.IpAddresses.cidr(vpcCidr),
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        ...(createNatGateway ? [{
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        }] : []),
      ],
      natGateways: createNatGateway ? 1 : 0,
    });

    cdk.Tags.of(this.vpc).add('Name', `${environmentName}-VPC`);
    cdk.Tags.of(this.vpc).add('Environment', environmentName);

    // Create S3 bucket for TaskCat artifacts
    this.taskCatBucket = new s3.Bucket(this, 'TaskCatArtifactsBucket', {
      bucketName: `taskcat-artifacts-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
        {
          id: 'AbortIncompleteMultipartUploads',
          enabled: true,
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
        },
      ],
    });

    cdk.Tags.of(this.taskCatBucket).add('Name', `${environmentName}-TaskCat-Bucket`);
    cdk.Tags.of(this.taskCatBucket).add('Environment', environmentName);

    // Create IAM role for TaskCat testing
    this.testingRole = new iam.Role(this, 'TaskCatTestingRole', {
      roleName: `TaskCat-Testing-Role-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('codebuild.amazonaws.com'),
        new iam.ServicePrincipal('cloudformation.amazonaws.com'),
        new iam.AccountRootPrincipal(),
      ),
      description: 'Role for TaskCat to test CloudFormation templates',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('PowerUserAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('IAMFullAccess'),
      ],
      inlinePolicies: {
        TaskCatSpecificPermissions: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudformation:*',
                's3:*',
                'ec2:*',
                'iam:*',
                'logs:*',
                'events:*',
                'lambda:*',
                'codecommit:*',
                'codebuild:*',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sts:AssumeRole',
                'sts:GetCallerIdentity',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    cdk.Tags.of(this.testingRole).add('Name', `${environmentName}-TaskCat-Role`);
    cdk.Tags.of(this.testingRole).add('Environment', environmentName);

    // Create CodeCommit repository for CloudFormation templates
    this.codeRepository = new codecommit.Repository(this, 'CloudFormationRepository', {
      repositoryName: `cloudformation-templates-${uniqueSuffix}`,
      description: 'Repository for CloudFormation templates tested with TaskCat',
      code: codecommit.Code.fromDirectory('./templates', 'main'),
    });

    cdk.Tags.of(this.codeRepository).add('Name', `${environmentName}-CFN-Repository`);
    cdk.Tags.of(this.codeRepository).add('Environment', environmentName);

    // Grant TaskCat role access to S3 bucket
    this.taskCatBucket.grantReadWrite(this.testingRole);

    // Create security group for TaskCat testing
    const taskCatSecurityGroup = new ec2.SecurityGroup(this, 'TaskCatSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for TaskCat testing resources',
      allowAllOutbound: true,
    });

    taskCatSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpcCidr),
      ec2.Port.tcp(80),
      'Allow HTTP traffic within VPC'
    );

    taskCatSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpcCidr),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic within VPC'
    );

    cdk.Tags.of(taskCatSecurityGroup).add('Name', `${environmentName}-TaskCat-SG`);
    cdk.Tags.of(taskCatSecurityGroup).add('Environment', environmentName);

    // Create CodeBuild project for automated TaskCat testing
    this.buildProject = new codebuild.Project(this, 'TaskCatBuildProject', {
      projectName: `taskcat-testing-${uniqueSuffix}`,
      description: 'Automated TaskCat testing for CloudFormation templates',
      source: codebuild.Source.codeCommit({
        repository: this.codeRepository,
        branchOrRef: 'main',
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
        computeType: codebuild.ComputeType.SMALL,
        privileged: false,
        environmentVariables: {
          TASKCAT_BUCKET: {
            value: this.taskCatBucket.bucketName,
          },
          AWS_DEFAULT_REGION: {
            value: this.region,
          },
          ENVIRONMENT_NAME: {
            value: environmentName,
          },
        },
      },
      role: this.testingRole,
      vpc: this.vpc,
      subnetSelection: {
        subnetType: createNatGateway ? ec2.SubnetType.PRIVATE_WITH_EGRESS : ec2.SubnetType.PUBLIC,
      },
      securityGroups: [taskCatSecurityGroup],
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          install: {
            'runtime-versions': {
              python: '3.11',
            },
            commands: [
              'echo "Installing TaskCat and dependencies"',
              'pip install --upgrade pip',
              'pip install taskcat',
              'pip install taskcat[console]',
              'taskcat --version',
            ],
          },
          pre_build: {
            commands: [
              'echo "Setting up TaskCat environment"',
              'aws sts get-caller-identity',
              'ls -la',
              'if [ -f ".taskcat.yml" ]; then echo "TaskCat configuration found"; else echo "No TaskCat configuration found"; fi',
            ],
          },
          build: {
            commands: [
              'echo "Running TaskCat lint"',
              'taskcat lint || echo "Lint completed with warnings"',
              'echo "Uploading templates to S3"',
              'taskcat upload --project-root .',
              'echo "Running TaskCat tests"',
              'taskcat test run --output-directory ./taskcat_outputs',
              'echo "Generating test reports"',
              'ls -la ./taskcat_outputs/ || echo "No outputs directory found"',
            ],
          },
          post_build: {
            commands: [
              'echo "TaskCat testing completed"',
              'echo "Cleaning up test resources"',
              'taskcat test clean --project-root . || echo "Cleanup completed"',
              'echo "Build completed at $(date)"',
            ],
          },
        },
        artifacts: {
          files: [
            'taskcat_outputs/**/*',
            '**/*.html',
            '**/*.json',
          ],
          'base-directory': '.',
        },
        reports: {
          'taskcat-reports': {
            files: [
              '**/*.html',
              '**/*.json',
            ],
            'base-directory': 'taskcat_outputs',
          },
        },
      }),
      timeout: cdk.Duration.minutes(60),
      queuedTimeout: cdk.Duration.minutes(30),
    });

    cdk.Tags.of(this.buildProject).add('Name', `${environmentName}-TaskCat-Build`);
    cdk.Tags.of(this.buildProject).add('Environment', environmentName);

    // Create EventBridge rule for automated testing if enabled
    if (enableAutomatedTesting) {
      const commitRule = new events.Rule(this, 'CodeCommitRule', {
        description: 'Trigger TaskCat testing on CodeCommit push',
        eventPattern: {
          source: ['aws.codecommit'],
          detailType: ['CodeCommit Repository State Change'],
          detail: {
            repositoryName: [this.codeRepository.repositoryName],
            referenceType: ['branch'],
            referenceName: ['main'],
          },
        },
      });

      commitRule.addTarget(new targets.CodeBuildProject(this.buildProject));

      cdk.Tags.of(commitRule).add('Name', `${environmentName}-TaskCat-Trigger`);
      cdk.Tags.of(commitRule).add('Environment', environmentName);
    }

    // Stack Outputs
    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for TaskCat testing infrastructure',
      exportName: `${environmentName}-VPC-ID`,
    });

    new cdk.CfnOutput(this, 'PublicSubnetIds', {
      value: this.vpc.publicSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Public subnet IDs',
      exportName: `${environmentName}-Public-Subnets`,
    });

    if (createNatGateway && this.vpc.privateSubnets.length > 0) {
      new cdk.CfnOutput(this, 'PrivateSubnetIds', {
        value: this.vpc.privateSubnets.map(subnet => subnet.subnetId).join(','),
        description: 'Private subnet IDs',
        exportName: `${environmentName}-Private-Subnets`,
      });
    }

    new cdk.CfnOutput(this, 'TaskCatBucketName', {
      value: this.taskCatBucket.bucketName,
      description: 'S3 bucket for TaskCat artifacts',
      exportName: `${environmentName}-TaskCat-Bucket`,
    });

    new cdk.CfnOutput(this, 'TaskCatRoleArn', {
      value: this.testingRole.roleArn,
      description: 'IAM role ARN for TaskCat testing',
      exportName: `${environmentName}-TaskCat-Role-ARN`,
    });

    new cdk.CfnOutput(this, 'CodeRepositoryCloneUrl', {
      value: this.codeRepository.repositoryCloneUrlHttps,
      description: 'HTTPS clone URL for the CloudFormation repository',
      exportName: `${environmentName}-Repository-URL`,
    });

    new cdk.CfnOutput(this, 'BuildProjectName', {
      value: this.buildProject.projectName,
      description: 'CodeBuild project name for TaskCat testing',
      exportName: `${environmentName}-Build-Project`,
    });
  }
}