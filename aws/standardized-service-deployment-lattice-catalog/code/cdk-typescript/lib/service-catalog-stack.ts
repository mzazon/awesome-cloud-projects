import * as cdk from 'aws-cdk-lib';
import * as servicecatalog from 'aws-cdk-lib/aws-servicecatalog';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';

export interface ServiceCatalogStackProps extends cdk.StackProps {
  templatesBucket: s3.Bucket;
  serviceNetworkTemplateKey: string;
  latticeServiceTemplateKey: string;
}

/**
 * Stack that creates Service Catalog portfolio, products, and governance controls
 * for standardized VPC Lattice service deployments
 */
export class ServiceCatalogStack extends cdk.Stack {
  public readonly portfolio: servicecatalog.Portfolio;
  public readonly networkProduct: servicecatalog.CloudFormationProduct;
  public readonly serviceProduct: servicecatalog.CloudFormationProduct;
  public readonly launchRole: iam.Role;

  constructor(scope: Construct, id: string, props: ServiceCatalogStackProps) {
    super(scope, id, props);

    // Create IAM role for Service Catalog launch constraint
    this.launchRole = this.createLaunchRole();

    // Create Service Catalog portfolio
    this.portfolio = this.createPortfolio();

    // Create Service Catalog products
    this.networkProduct = this.createServiceNetworkProduct(props);
    this.serviceProduct = this.createLatticeServiceProduct(props);

    // Associate products with portfolio
    this.portfolio.addProduct(this.networkProduct);
    this.portfolio.addProduct(this.serviceProduct);

    // Create launch constraints
    this.createLaunchConstraints();

    // Grant access to current account
    this.grantPortfolioAccess();

    // Create outputs
    this.createOutputs();

    // Apply CDK Nag suppressions
    this.applyCdkNagSuppressions();

    // Tag all resources
    cdk.Tags.of(this).add('Purpose', 'ServiceCatalogGovernance');
    cdk.Tags.of(this).add('Component', 'ServiceCatalog');
  }

  /**
   * Create IAM role for Service Catalog launch constraint
   */
  private createLaunchRole(): iam.Role {
    const role = new iam.Role(this, 'LaunchRole', {
      roleName: `ServiceCatalogVpcLatticeRole-${cdk.Aws.REGION}`,
      assumedBy: new iam.ServicePrincipal('servicecatalog.amazonaws.com'),
      description: 'IAM role for Service Catalog VPC Lattice product launches',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess'),
      ],
      inlinePolicies: {
        VpcLatticePermissions: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              sid: 'VpcLatticeManagement',
              effect: iam.Effect.ALLOW,
              actions: [
                'vpc-lattice:*',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              sid: 'EC2ReadAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:DescribeVpcs',
                'ec2:DescribeSubnets',
                'ec2:DescribeSecurityGroups',
                'ec2:DescribeNetworkInterfaces',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              sid: 'CloudFormationAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudformation:*',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              sid: 'IAMPassRole',
              effect: iam.Effect.ALLOW,
              actions: [
                'iam:PassRole',
              ],
              resources: [
                `arn:aws:iam::${cdk.Aws.ACCOUNT_ID}:role/*`,
              ],
              conditions: {
                StringEquals: {
                  'iam:PassedToService': [
                    'vpc-lattice.amazonaws.com',
                    'cloudformation.amazonaws.com',
                  ],
                },
              },
            }),
            new iam.PolicyStatement({
              sid: 'KMSAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:CreateKey',
                'kms:CreateAlias',
                'kms:DeleteAlias',
                'kms:Describe*',
                'kms:List*',
                'kms:Put*',
                'kms:Update*',
                'kms:Revoke*',
                'kms:Disable*',
                'kms:Get*',
                'kms:Delete*',
                'kms:ScheduleKeyDeletion',
                'kms:CancelKeyDeletion',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              sid: 'CloudWatchLogsAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DeleteLogGroup',
                'logs:DeleteLogStream',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    return role;
  }

  /**
   * Create Service Catalog portfolio
   */
  private createPortfolio(): servicecatalog.Portfolio {
    return new servicecatalog.Portfolio(this, 'VpcLatticePortfolio', {
      displayName: 'VPC Lattice Services',
      providerName: 'Platform Engineering Team',
      description: 'Standardized VPC Lattice service deployment templates with governance controls',
      messageLanguage: servicecatalog.MessageLanguage.EN,
    });
  }

  /**
   * Create Service Network CloudFormation product
   */
  private createServiceNetworkProduct(props: ServiceCatalogStackProps): servicecatalog.CloudFormationProduct {
    return new servicecatalog.CloudFormationProduct(this, 'ServiceNetworkProduct', {
      productName: 'Standardized VPC Lattice Service Network',
      owner: 'Platform Engineering Team',
      description: 'Deploy a standardized VPC Lattice service network with security best practices and monitoring',
      productVersions: [
        {
          productVersionName: 'v1.0',
          description: 'Initial version with IAM authentication and access logging support',
          cloudFormationTemplate: servicecatalog.CloudFormationTemplate.fromUrl(
            `https://s3.${cdk.Aws.REGION}.amazonaws.com/${props.templatesBucket.bucketName}/${props.serviceNetworkTemplateKey}`
          ),
        },
      ],
      support: {
        description: 'Contact Platform Engineering Team for support',
        email: 'platform-engineering@example.com',
        url: 'https://wiki.example.com/vpc-lattice-support',
      },
    });
  }

  /**
   * Create Lattice Service CloudFormation product
   */
  private createLatticeServiceProduct(props: ServiceCatalogStackProps): servicecatalog.CloudFormationProduct {
    return new servicecatalog.CloudFormationProduct(this, 'LatticeServiceProduct', {
      productName: 'Standardized VPC Lattice Service',
      owner: 'Platform Engineering Team',
      description: 'Deploy a standardized VPC Lattice service with target group, listener, and health checks',
      productVersions: [
        {
          productVersionName: 'v1.0',
          description: 'Initial version with configurable target types and health check parameters',
          cloudFormationTemplate: servicecatalog.CloudFormationTemplate.fromUrl(
            `https://s3.${cdk.Aws.REGION}.amazonaws.com/${props.templatesBucket.bucketName}/${props.latticeServiceTemplateKey}`
          ),
        },
      ],
      support: {
        description: 'Contact Platform Engineering Team for support',
        email: 'platform-engineering@example.com',
        url: 'https://wiki.example.com/vpc-lattice-support',
      },
    });
  }

  /**
   * Create launch constraints for products
   */
  private createLaunchConstraints(): void {
    // Launch constraint for service network product
    new servicecatalog.LaunchRoleConstraint(this, 'NetworkLaunchConstraint', {
      portfolio: this.portfolio,
      product: this.networkProduct,
      localLaunchRole: this.launchRole,
      description: 'IAM role for VPC Lattice service network deployment',
    });

    // Launch constraint for lattice service product
    new servicecatalog.LaunchRoleConstraint(this, 'ServiceLaunchConstraint', {
      portfolio: this.portfolio,
      product: this.serviceProduct,
      localLaunchRole: this.launchRole,
      description: 'IAM role for VPC Lattice service deployment',
    });

    // Template constraint to enforce naming conventions
    new servicecatalog.TemplateConstraint(this, 'NamingConstraint', {
      portfolio: this.portfolio,
      product: this.serviceProduct,
      rules: servicecatalog.TemplateConstraintRules.fromString(JSON.stringify({
        Rules: {
          ServiceNameRule: {
            Assertions: [
              {
                Assert: {
                  'Fn::Not': [
                    {
                      'Fn::Equals': [
                        {
                          Ref: 'ServiceName',
                        },
                        '',
                      ],
                    },
                  ],
                },
                AssertDescription: 'Service name must not be empty',
              },
            ],
          },
        },
      })),
      description: 'Enforce naming conventions for VPC Lattice services',
    });
  }

  /**
   * Grant access to the portfolio for the current account
   */
  private grantPortfolioAccess(): void {
    // Grant access to current AWS account root
    this.portfolio.giveAccessToRole(
      iam.Role.fromRoleArn(
        this,
        'AccountRoot',
        `arn:aws:iam::${cdk.Aws.ACCOUNT_ID}:root`
      )
    );

    // In a real scenario, you would grant access to specific IAM users/groups
    // Example: this.portfolio.giveAccessToGroup(developersGroup);
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'PortfolioId', {
      value: this.portfolio.portfolioId,
      description: 'Service Catalog Portfolio ID',
      exportName: `${this.stackName}-PortfolioId`,
    });

    new cdk.CfnOutput(this, 'NetworkProductId', {
      value: this.networkProduct.productId,
      description: 'Service Network Product ID',
      exportName: `${this.stackName}-NetworkProductId`,
    });

    new cdk.CfnOutput(this, 'ServiceProductId', {
      value: this.serviceProduct.productId,
      description: 'Lattice Service Product ID',
      exportName: `${this.stackName}-ServiceProductId`,
    });

    new cdk.CfnOutput(this, 'LaunchRoleArn', {
      value: this.launchRole.roleArn,
      description: 'Launch Role ARN for Service Catalog',
      exportName: `${this.stackName}-LaunchRoleArn`,
    });
  }

  /**
   * Apply CDK Nag suppressions for acceptable security patterns
   */
  private applyCdkNagSuppressions(): void {
    NagSuppressions.addResourceSuppressions(
      this.launchRole,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'Service Catalog launch role requires broad permissions to manage VPC Lattice resources across different services and accounts',
        },
        {
          id: 'AwsSolutions-IAM4',
          reason: 'CloudWatchLogsFullAccess managed policy is used for simplified log management permissions',
        },
      ]
    );
  }
}