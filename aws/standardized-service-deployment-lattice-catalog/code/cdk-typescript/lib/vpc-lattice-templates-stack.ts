import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';

/**
 * Stack that creates and manages CloudFormation templates for VPC Lattice services
 * These templates are used by Service Catalog products for standardized deployments
 */
export class VpcLatticeTemplatesStack extends cdk.Stack {
  public readonly templatesBucket: s3.Bucket;
  public readonly serviceNetworkTemplateKey: string;
  public readonly latticeServiceTemplateKey: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Define template file names
    this.serviceNetworkTemplateKey = 'templates/service-network-template.yaml';
    this.latticeServiceTemplateKey = 'templates/lattice-service-template.yaml';

    // Create S3 bucket for storing CloudFormation templates
    this.templatesBucket = new s3.Bucket(this, 'TemplatesBucket', {
      bucketName: `vpc-lattice-templates-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'delete-old-versions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
          enabled: true,
        },
      ],
    });

    // Deploy CloudFormation templates to S3
    new s3deploy.BucketDeployment(this, 'DeployTemplates', {
      sources: [
        s3deploy.Source.data(
          this.serviceNetworkTemplateKey,
          this.getServiceNetworkTemplate()
        ),
        s3deploy.Source.data(
          this.latticeServiceTemplateKey,
          this.getLatticeServiceTemplate()
        ),
      ],
      destinationBucket: this.templatesBucket,
      retainOnDelete: false,
    });

    // Output bucket information
    new cdk.CfnOutput(this, 'TemplatesBucketName', {
      value: this.templatesBucket.bucketName,
      description: 'S3 bucket containing CloudFormation templates',
      exportName: `${this.stackName}-TemplatesBucketName`,
    });

    new cdk.CfnOutput(this, 'TemplatesBucketArn', {
      value: this.templatesBucket.bucketArn,
      description: 'ARN of the templates bucket',
      exportName: `${this.stackName}-TemplatesBucketArn`,
    });

    // CDK Nag suppressions
    NagSuppressions.addResourceSuppressions(
      this.templatesBucket,
      [
        {
          id: 'AwsSolutions-S1',
          reason: 'Access logging not required for template storage bucket',
        },
      ]
    );

    // Tag all resources
    cdk.Tags.of(this).add('Purpose', 'VPCLatticeTemplateStorage');
    cdk.Tags.of(this).add('Component', 'Templates');
  }

  /**
   * Generate the CloudFormation template for VPC Lattice Service Network
   */
  private getServiceNetworkTemplate(): string {
    return `AWSTemplateFormatVersion: '2010-09-09'
Description: 'Standardized VPC Lattice Service Network with security best practices'

Parameters:
  NetworkName:
    Type: String
    Default: 'standard-service-network'
    Description: 'Name for the VPC Lattice service network'
    MinLength: 1
    MaxLength: 63
    ConstraintDescription: 'Network name must be between 1 and 63 characters'
  
  AuthType:
    Type: String
    Default: 'AWS_IAM'
    AllowedValues: ['AWS_IAM', 'NONE']
    Description: 'Authentication type for the service network'
  
  EnableLogging:
    Type: String
    Default: 'true'
    AllowedValues: ['true', 'false']
    Description: 'Enable access logging for the service network'

Conditions:
  ShouldEnableLogging: !Equals [!Ref EnableLogging, 'true']

Resources:
  ServiceNetwork:
    Type: AWS::VpcLattice::ServiceNetwork
    Properties:
      Name: !Ref NetworkName
      AuthType: !Ref AuthType
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'
        - Key: 'Environment'
          Value: !Ref 'AWS::StackName'

  ServiceNetworkPolicy:
    Type: AWS::VpcLattice::AuthPolicy
    Properties:
      ResourceIdentifier: !Ref ServiceNetwork
      Policy:
        Version: '2012-10-17'
        Statement:
          - Sid: AllowSameAccountAccess
            Effect: Allow
            Principal: '*'
            Action: 'vpc-lattice-svcs:Invoke'
            Resource: '*'
            Condition:
              StringEquals:
                'aws:PrincipalAccount': !Ref 'AWS::AccountId'
          - Sid: DenyUnauthorizedAccess
            Effect: Deny
            Principal: '*'
            Action: 'vpc-lattice-svcs:Invoke'
            Resource: '*'
            Condition:
              StringNotEquals:
                'aws:PrincipalAccount': !Ref 'AWS::AccountId'

  AccessLogGroup:
    Type: AWS::Logs::LogGroup
    Condition: ShouldEnableLogging
    Properties:
      LogGroupName: !Sub '/aws/vpc-lattice/\${NetworkName}'
      RetentionInDays: 30
      KmsKeyId: !Ref LogGroupKey

  LogGroupKey:
    Type: AWS::KMS::Key
    Condition: ShouldEnableLogging
    Properties:
      Description: 'KMS key for VPC Lattice access logs encryption'
      KeyPolicy:
        Version: '2012-10-17'
        Statement:
          - Sid: Enable IAM User Permissions
            Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::\${AWS::AccountId}:root'
            Action: 'kms:*'
            Resource: '*'
          - Sid: Allow CloudWatch Logs
            Effect: Allow
            Principal:
              Service: !Sub 'logs.\${AWS::Region}.amazonaws.com'
            Action:
              - 'kms:Encrypt'
              - 'kms:Decrypt'
              - 'kms:ReEncrypt*'
              - 'kms:GenerateDataKey*'
              - 'kms:DescribeKey'
            Resource: '*'

  LogGroupKeyAlias:
    Type: AWS::KMS::Alias
    Condition: ShouldEnableLogging
    Properties:
      AliasName: !Sub 'alias/vpc-lattice-logs-\${AWS::StackName}'
      TargetKeyId: !Ref LogGroupKey

Outputs:
  ServiceNetworkId:
    Description: 'Service Network ID'
    Value: !Ref ServiceNetwork
    Export:
      Name: !Sub '\${AWS::StackName}-ServiceNetworkId'
  
  ServiceNetworkArn:
    Description: 'Service Network ARN'
    Value: !GetAtt ServiceNetwork.Arn
    Export:
      Name: !Sub '\${AWS::StackName}-ServiceNetworkArn'
  
  ServiceNetworkName:
    Description: 'Service Network Name'
    Value: !GetAtt ServiceNetwork.Name
    Export:
      Name: !Sub '\${AWS::StackName}-ServiceNetworkName'
  
  LogGroupArn:
    Condition: ShouldEnableLogging
    Description: 'CloudWatch Log Group ARN for access logs'
    Value: !GetAtt AccessLogGroup.Arn
    Export:
      Name: !Sub '\${AWS::StackName}-LogGroupArn'`;
  }

  /**
   * Generate the CloudFormation template for VPC Lattice Service
   */
  private getLatticeServiceTemplate(): string {
    return `AWSTemplateFormatVersion: '2010-09-09'
Description: 'Standardized VPC Lattice Service with Target Group and security best practices'

Parameters:
  ServiceName:
    Type: String
    Description: 'Name for the VPC Lattice service'
    MinLength: 1
    MaxLength: 63
    ConstraintDescription: 'Service name must be between 1 and 63 characters'
  
  ServiceNetworkId:
    Type: String
    Description: 'Service Network ID to associate with'
    MinLength: 1
  
  TargetType:
    Type: String
    Default: 'IP'
    AllowedValues: ['IP', 'LAMBDA', 'ALB']
    Description: 'Type of targets for the target group'
  
  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: 'VPC ID for the target group'
  
  Port:
    Type: Number
    Default: 80
    MinValue: 1
    MaxValue: 65535
    Description: 'Port for the service listener'
  
  Protocol:
    Type: String
    Default: 'HTTP'
    AllowedValues: ['HTTP', 'HTTPS']
    Description: 'Protocol for the service listener'
  
  HealthCheckPath:
    Type: String
    Default: '/health'
    Description: 'Health check path for the target group'
    MinLength: 1
  
  HealthCheckIntervalSeconds:
    Type: Number
    Default: 30
    MinValue: 5
    MaxValue: 300
    Description: 'Health check interval in seconds'
  
  HealthyThresholdCount:
    Type: Number
    Default: 2
    MinValue: 2
    MaxValue: 10
    Description: 'Number of consecutive successful health checks'
  
  UnhealthyThresholdCount:
    Type: Number
    Default: 3
    MinValue: 2
    MaxValue: 10
    Description: 'Number of consecutive failed health checks'

Resources:
  TargetGroup:
    Type: AWS::VpcLattice::TargetGroup
    Properties:
      Name: !Sub '\${ServiceName}-targets'
      Type: !Ref TargetType
      Port: !Ref Port
      Protocol: !Ref Protocol
      VpcIdentifier: !Ref VpcId
      HealthCheck:
        Enabled: true
        HealthCheckIntervalSeconds: !Ref HealthCheckIntervalSeconds
        HealthCheckTimeoutSeconds: 5
        HealthyThresholdCount: !Ref HealthyThresholdCount
        UnhealthyThresholdCount: !Ref UnhealthyThresholdCount
        Matcher:
          HttpCode: '200'
        Path: !Ref HealthCheckPath
        Port: !Ref Port
        Protocol: !Ref Protocol
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'
        - Key: 'ServiceName'
          Value: !Ref ServiceName

  Service:
    Type: AWS::VpcLattice::Service
    Properties:
      Name: !Ref ServiceName
      AuthType: 'AWS_IAM'
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'
        - Key: 'Environment'
          Value: !Ref 'AWS::StackName'

  Listener:
    Type: AWS::VpcLattice::Listener
    Properties:
      ServiceIdentifier: !Ref Service
      Name: 'default-listener'
      Port: !Ref Port
      Protocol: !Ref Protocol
      DefaultAction:
        Forward:
          TargetGroups:
            - TargetGroupIdentifier: !Ref TargetGroup
              Weight: 100
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'

  ServiceNetworkAssociation:
    Type: AWS::VpcLattice::ServiceNetworkServiceAssociation
    Properties:
      ServiceIdentifier: !Ref Service
      ServiceNetworkIdentifier: !Ref ServiceNetworkId
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'

  ServiceAuthPolicy:
    Type: AWS::VpcLattice::AuthPolicy
    Properties:
      ResourceIdentifier: !Ref Service
      Policy:
        Version: '2012-10-17'
        Statement:
          - Sid: AllowSameAccountAccess
            Effect: Allow
            Principal: '*'
            Action: 'vpc-lattice-svcs:Invoke'
            Resource: '*'
            Condition:
              StringEquals:
                'aws:PrincipalAccount': !Ref 'AWS::AccountId'

Outputs:
  ServiceId:
    Description: 'VPC Lattice Service ID'
    Value: !Ref Service
    Export:
      Name: !Sub '\${AWS::StackName}-ServiceId'
  
  ServiceArn:
    Description: 'VPC Lattice Service ARN'
    Value: !GetAtt Service.Arn
    Export:
      Name: !Sub '\${AWS::StackName}-ServiceArn'
  
  ServiceName:
    Description: 'VPC Lattice Service Name'
    Value: !GetAtt Service.Name
    Export:
      Name: !Sub '\${AWS::StackName}-ServiceName'
  
  TargetGroupId:
    Description: 'Target Group ID'
    Value: !Ref TargetGroup
    Export:
      Name: !Sub '\${AWS::StackName}-TargetGroupId'
  
  TargetGroupArn:
    Description: 'Target Group ARN'
    Value: !GetAtt TargetGroup.Arn
    Export:
      Name: !Sub '\${AWS::StackName}-TargetGroupArn'
  
  ListenerId:
    Description: 'Listener ID'
    Value: !Ref Listener
    Export:
      Name: !Sub '\${AWS::StackName}-ListenerId'
  
  ServiceNetworkAssociationId:
    Description: 'Service Network Association ID'
    Value: !Ref ServiceNetworkAssociation
    Export:
      Name: !Sub '\${AWS::StackName}-ServiceNetworkAssociationId'`;
  }
}