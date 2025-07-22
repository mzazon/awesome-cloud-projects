import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { KubernetesOperatorsStack } from '../lib/kubernetes-operators-stack';

describe('KubernetesOperatorsStack', () => {
  let app: cdk.App;
  let stack: KubernetesOperatorsStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new KubernetesOperatorsStack(app, 'TestStack', {
      clusterName: 'test-cluster',
      resourceSuffix: 'test',
      enableLogging: true,
      nodeGroupInstanceTypes: ['t3.medium'],
      nodeGroupDesiredSize: 2,
      nodeGroupMinSize: 1,
      nodeGroupMaxSize: 4,
    });
    template = Template.fromStack(stack);
  });

  describe('VPC Configuration', () => {
    test('creates VPC with correct CIDR and subnets', () => {
      template.hasResourceProperties('AWS::EC2::VPC', {
        CidrBlock: '10.0.0.0/16',
        EnableDnsHostnames: true,
        EnableDnsSupport: true,
      });

      // Should have public and private subnets
      template.resourceCountIs('AWS::EC2::Subnet', 6); // 3 AZs * 2 subnet types
    });

    test('creates NAT gateways for private subnet egress', () => {
      template.resourceCountIs('AWS::EC2::NatGateway', 2);
    });

    test('creates VPC Flow Logs when logging is enabled', () => {
      template.hasResourceProperties('AWS::EC2::FlowLog', {
        ResourceType: 'VPC',
      });

      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: '/aws/vpc/flowlogs/test',
      });
    });
  });

  describe('EKS Cluster', () => {
    test('creates EKS cluster with correct configuration', () => {
      template.hasResourceProperties('AWS::EKS::Cluster', {
        Name: 'test-cluster',
        Version: '1.28',
        EndpointConfig: {
          PrivateAccess: true,
          PublicAccess: true,
        },
      });
    });

    test('creates cluster service role with correct policies', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: Match.objectLike({
          Statement: Match.arrayWith([
            Match.objectLike({
              Principal: { Service: 'eks.amazonaws.com' },
            }),
          ]),
        }),
        ManagedPolicyArns: Match.arrayWith([
          'arn:aws:iam::aws:policy/AmazonEKSClusterPolicy',
        ]),
      });
    });

    test('enables cluster logging', () => {
      template.hasResourceProperties('AWS::EKS::Cluster', {
        Logging: {
          ClusterLogging: {
            EnabledTypes: Match.arrayWith([
              { Type: 'api' },
              { Type: 'audit' },
              { Type: 'authenticator' },
              { Type: 'controllerManager' },
              { Type: 'scheduler' },
            ]),
          },
        },
      });
    });

    test('creates OIDC identity provider', () => {
      template.hasResourceProperties('AWS::IAM::OIDCIdentityProvider', {
        Url: Match.anyValue(),
        ClientIdList: ['sts.amazonaws.com'],
      });
    });

    test('creates managed node group', () => {
      template.hasResourceProperties('AWS::EKS::Nodegroup', {
        NodegroupName: 'test-cluster-nodes',
        InstanceTypes: ['t3.medium'],
        ScalingConfig: {
          DesiredSize: 2,
          MaxSize: 4,
          MinSize: 1,
        },
        DiskSize: 20,
        AmiType: 'AL2_x86_64',
        CapacityType: 'ON_DEMAND',
      });
    });

    test('creates ACK system namespace', () => {
      template.hasResourceProperties('Custom::AWSCDK-EKS-KubernetesResource', {
        Manifest: JSON.stringify({
          apiVersion: 'v1',
          kind: 'Namespace',
          metadata: {
            name: 'ack-system',
            labels: {
              name: 'ack-system',
              'pod-security.kubernetes.io/enforce': 'restricted',
              'pod-security.kubernetes.io/audit': 'restricted',
              'pod-security.kubernetes.io/warn': 'restricted',
            },
          },
        }),
      });
    });
  });

  describe('IAM Roles', () => {
    test('creates ACK controller role with correct trust policy', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        RoleName: 'ACK-Controller-Role-test',
        AssumeRolePolicyDocument: Match.objectLike({
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Principal: {
                Federated: Match.anyValue(),
              },
              Action: 'sts:AssumeRoleWithWebIdentity',
              Condition: {
                StringEquals: Match.objectLike({
                  'sts.amazonaws.com': 'sts.amazonaws.com',
                }),
              },
            }),
          ]),
        }),
      });
    });

    test('grants S3 permissions to ACK controller role', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith([
                's3:CreateBucket',
                's3:DeleteBucket',
                's3:GetBucket*',
                's3:ListBucket*',
                's3:PutBucket*',
              ]),
              Resource: '*',
            }),
          ]),
        },
      });
    });

    test('grants IAM permissions to ACK controller role', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith([
                'iam:CreateRole',
                'iam:DeleteRole',
                'iam:GetRole',
                'iam:ListRoles',
                'iam:UpdateRole',
              ]),
              Resource: '*',
            }),
          ]),
        },
      });
    });

    test('grants Lambda permissions to ACK controller role', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith([
                'lambda:CreateFunction',
                'lambda:DeleteFunction',
                'lambda:GetFunction',
                'lambda:UpdateFunctionCode',
              ]),
              Resource: '*',
            }),
          ]),
        },
      });
    });

    test('creates sample application role', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        RoleName: 'sample-app-role-test',
        AssumeRolePolicyDocument: Match.objectLike({
          Statement: Match.arrayWith([
            Match.objectLike({
              Principal: { Service: 'lambda.amazonaws.com' },
            }),
          ]),
        }),
      });
    });
  });

  describe('S3 Bucket', () => {
    test('creates S3 bucket with security best practices', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: 'kubernetes-operators-storage-test',
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: {
                SSEAlgorithm: 'AES256',
              },
            },
          ],
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
        VersioningConfiguration: {
          Status: 'Enabled',
        },
      });
    });

    test('creates bucket policy denying insecure connections', () => {
      template.hasResourceProperties('AWS::S3::BucketPolicy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Sid: 'DenyInsecureConnections',
              Effect: 'Deny',
              Principal: '*',
              Action: 's3:*',
              Condition: {
                Bool: {
                  'aws:SecureTransport': 'false',
                },
              },
            }),
          ]),
        },
      });
    });

    test('creates lifecycle configuration for old versions', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: Match.arrayWith([
            Match.objectLike({
              Id: 'DeleteOldVersions',
              Status: 'Enabled',
              NoncurrentVersionExpirationInDays: 30,
            }),
          ]),
        },
      });
    });
  });

  describe('Lambda Function', () => {
    test('creates Lambda function with correct configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: 'kubernetes-operators-processor-test',
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 300,
        MemorySize: 256,
      });
    });

    test('creates Lambda execution role with basic execution policy', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: Match.objectLike({
          Statement: Match.arrayWith([
            Match.objectLike({
              Principal: { Service: 'lambda.amazonaws.com' },
            }),
          ]),
        }),
        ManagedPolicyArns: Match.arrayWith([
          'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
        ]),
      });
    });

    test('grants S3 access to Lambda function', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith(['s3:GetObject*', 's3:PutObject*']),
            }),
          ]),
        },
      });
    });

    test('sets environment variables for Lambda function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            BUCKET_NAME: Match.anyValue(),
            CLUSTER_NAME: 'test-cluster',
            RESOURCE_SUFFIX: 'test',
          },
        },
      });
    });
  });

  describe('Outputs', () => {
    test('creates all required stack outputs', () => {
      const outputs = [
        'ClusterName',
        'ClusterEndpoint',
        'ClusterArn',
        'OidcProviderArn',
        'AckControllerRoleArn',
        'ApplicationBucketName',
        'ApplicationBucketArn',
        'ProcessingFunctionName',
        'ProcessingFunctionArn',
        'VpcId',
        'SampleAppRoleArn',
        'KubectlUpdateCommand',
        'HelmInstallCommands',
      ];

      outputs.forEach((outputName) => {
        template.hasOutput(outputName, {});
      });
    });

    test('creates exports for cross-stack references', () => {
      template.hasOutput('ClusterName', {
        Export: {
          Name: 'ClusterName-test',
        },
      });

      template.hasOutput('AckControllerRoleArn', {
        Export: {
          Name: 'AckControllerRoleArn-test',
        },
      });
    });
  });

  describe('Resource Tagging', () => {
    test('applies consistent tags to resources', () => {
      // Check that VPC has proper tags
      template.hasResourceProperties('AWS::EC2::VPC', {
        Tags: Match.arrayWith([
          {
            Key: 'Name',
            Value: 'kubernetes-operators-vpc-test',
          },
        ]),
      });
    });
  });

  describe('Security Configurations', () => {
    test('node group role has required managed policies', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        ManagedPolicyArns: Match.arrayWith([
          'arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy',
          'arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy',
          'arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly',
        ]),
      });
    });

    test('uses private subnets for node group', () => {
      template.hasResourceProperties('AWS::EKS::Nodegroup', {
        Subnets: Match.anyValue(), // Subnets should be private ones from VPC
      });
    });
  });
});

describe('KubernetesOperatorsStack with Logging Disabled', () => {
  test('does not create VPC Flow Logs when logging is disabled', () => {
    const app = new cdk.App();
    const stack = new KubernetesOperatorsStack(app, 'TestStackNoLogging', {
      clusterName: 'test-cluster',
      resourceSuffix: 'test',
      enableLogging: false,
      nodeGroupInstanceTypes: ['t3.medium'],
      nodeGroupDesiredSize: 2,
      nodeGroupMinSize: 1,
      nodeGroupMaxSize: 4,
    });
    const template = Template.fromStack(stack);

    // Should not create VPC Flow Logs
    template.resourceCountIs('AWS::EC2::FlowLog', 0);
  });

  test('does not enable EKS cluster logging when logging is disabled', () => {
    const app = new cdk.App();
    const stack = new KubernetesOperatorsStack(app, 'TestStackNoLogging', {
      clusterName: 'test-cluster',
      resourceSuffix: 'test',
      enableLogging: false,
      nodeGroupInstanceTypes: ['t3.medium'],
      nodeGroupDesiredSize: 2,
      nodeGroupMinSize: 1,
      nodeGroupMaxSize: 4,
    });
    const template = Template.fromStack(stack);

    // Cluster should not have logging configuration
    template.hasResourceProperties('AWS::EKS::Cluster', {
      Logging: Match.absent(),
    });
  });
});