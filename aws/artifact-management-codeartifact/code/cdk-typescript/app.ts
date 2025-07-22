#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as codeartifact from 'aws-cdk-lib/aws-codeartifact';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';

/**
 * Interface for stack properties including optional configuration parameters
 */
export interface ArtifactManagementStackProps extends cdk.StackProps {
  /**
   * Name for the CodeArtifact domain (defaults to 'my-company-domain')
   */
  readonly domainName?: string;
  
  /**
   * Whether to enable KMS encryption for the domain (defaults to true)
   */
  readonly enableEncryption?: boolean;
  
  /**
   * Environment prefix for resource naming (defaults to 'dev')
   */
  readonly environmentPrefix?: string;
}

/**
 * CDK Stack for AWS CodeArtifact artifact management solution
 * 
 * This stack creates a complete CodeArtifact setup including:
 * - Domain with KMS encryption
 * - Repository hierarchy with upstream relationships
 * - External connections to public registries (npm, PyPI)
 * - IAM policies for development and production access
 * - Repository permissions for fine-grained access control
 */
export class ArtifactManagementStack extends cdk.Stack {
  /**
   * The CodeArtifact domain
   */
  public readonly domain: codeartifact.CfnDomain;
  
  /**
   * The npm store repository with external connection
   */
  public readonly npmStoreRepository: codeartifact.CfnRepository;
  
  /**
   * The PyPI store repository with external connection
   */
  public readonly pypiStoreRepository: codeartifact.CfnRepository;
  
  /**
   * The team development repository
   */
  public readonly teamRepository: codeartifact.CfnRepository;
  
  /**
   * The production repository
   */
  public readonly productionRepository: codeartifact.CfnRepository;
  
  /**
   * IAM policy for development team access
   */
  public readonly developerPolicy: iam.ManagedPolicy;
  
  /**
   * IAM policy for production read-only access
   */
  public readonly productionPolicy: iam.ManagedPolicy;
  
  /**
   * KMS key for domain encryption
   */
  public readonly encryptionKey: kms.Key;

  constructor(scope: Construct, id: string, props: ArtifactManagementStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const domainName = props.domainName || 'my-company-domain';
    const enableEncryption = props.enableEncryption ?? true;
    const envPrefix = props.environmentPrefix || 'dev';
    
    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);
    const uniqueDomainName = `${domainName}-${uniqueSuffix}`;

    // Create KMS key for domain encryption
    this.encryptionKey = new kms.Key(this, 'CodeArtifactEncryptionKey', {
      description: 'KMS key for CodeArtifact domain encryption',
      enableKeyRotation: true,
      alias: `codeartifact-${envPrefix}-${uniqueSuffix}`,
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'Enable IAM User Permissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'Allow CodeArtifact Service',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('codeartifact.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:DescribeKey',
              'kms:Encrypt',
              'kms:GenerateDataKey*',
              'kms:ReEncrypt*',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create CodeArtifact domain
    this.domain = new codeartifact.CfnDomain(this, 'ArtifactDomain', {
      domainName: uniqueDomainName,
      encryptionKey: enableEncryption ? this.encryptionKey.keyArn : undefined,
      tags: [
        {
          key: 'Purpose',
          value: 'Artifact Management',
        },
        {
          key: 'Environment',
          value: envPrefix,
        },
        {
          key: 'CreatedBy',
          value: 'CDK',
        },
      ],
    });

    // Create npm store repository with external connection to npmjs
    this.npmStoreRepository = new codeartifact.CfnRepository(this, 'NpmStoreRepository', {
      repositoryName: 'npm-store',
      domainName: this.domain.domainName,
      description: 'npm packages from public registry with caching',
      externalConnections: ['public:npmjs'],
      tags: [
        {
          key: 'PackageType',
          value: 'npm',
        },
        {
          key: 'Purpose',
          value: 'External Package Cache',
        },
      ],
    });

    // Ensure repository depends on domain
    this.npmStoreRepository.addDependency(this.domain);

    // Create PyPI store repository with external connection to PyPI
    this.pypiStoreRepository = new codeartifact.CfnRepository(this, 'PypiStoreRepository', {
      repositoryName: 'pypi-store',
      domainName: this.domain.domainName,
      description: 'Python packages from PyPI with caching',
      externalConnections: ['public:pypi'],
      tags: [
        {
          key: 'PackageType',
          value: 'pypi',
        },
        {
          key: 'Purpose',
          value: 'External Package Cache',
        },
      ],
    });

    // Ensure repository depends on domain
    this.pypiStoreRepository.addDependency(this.domain);

    // Create team development repository with upstream connections
    this.teamRepository = new codeartifact.CfnRepository(this, 'TeamRepository', {
      repositoryName: 'team-dev',
      domainName: this.domain.domainName,
      description: 'Team development artifacts with access to public packages',
      upstreams: [
        this.npmStoreRepository.repositoryName,
        this.pypiStoreRepository.repositoryName,
      ],
      tags: [
        {
          key: 'Environment',
          value: 'Development',
        },
        {
          key: 'Access',
          value: 'Team',
        },
      ],
    });

    // Ensure repository depends on upstream repositories
    this.teamRepository.addDependency(this.npmStoreRepository);
    this.teamRepository.addDependency(this.pypiStoreRepository);

    // Create production repository with upstream to team repository
    this.productionRepository = new codeartifact.CfnRepository(this, 'ProductionRepository', {
      repositoryName: 'production',
      domainName: this.domain.domainName,
      description: 'Production-ready artifacts for deployment',
      upstreams: [this.teamRepository.repositoryName],
      tags: [
        {
          key: 'Environment',
          value: 'Production',
        },
        {
          key: 'Access',
          value: 'Restricted',
        },
      ],
    });

    // Ensure repository depends on team repository
    this.productionRepository.addDependency(this.teamRepository);

    // Create IAM policy for development team access
    this.developerPolicy = new iam.ManagedPolicy(this, 'DeveloperPolicy', {
      managedPolicyName: `CodeArtifact-Developer-${envPrefix}-${uniqueSuffix}`,
      description: 'Policy for development team access to CodeArtifact repositories',
      statements: [
        new iam.PolicyStatement({
          sid: 'CodeArtifactDomainAccess',
          effect: iam.Effect.ALLOW,
          actions: [
            'codeartifact:GetAuthorizationToken',
            'codeartifact:GetRepositoryEndpoint',
            'codeartifact:ReadFromRepository',
            'codeartifact:PublishPackageVersion',
            'codeartifact:PutPackageMetadata',
            'codeartifact:DeletePackageVersion',
          ],
          resources: [
            this.domain.attrArn,
            cdk.Fn.sub('arn:aws:codeartifact:${AWS::Region}:${AWS::AccountId}:repository/${DomainName}/${TeamRepo}', {
              DomainName: this.domain.domainName,
              TeamRepo: this.teamRepository.repositoryName,
            }),
            cdk.Fn.sub('arn:aws:codeartifact:${AWS::Region}:${AWS::AccountId}:repository/${DomainName}/${NpmStore}', {
              DomainName: this.domain.domainName,
              NpmStore: this.npmStoreRepository.repositoryName,
            }),
            cdk.Fn.sub('arn:aws:codeartifact:${AWS::Region}:${AWS::AccountId}:repository/${DomainName}/${PypiStore}', {
              DomainName: this.domain.domainName,
              PypiStore: this.pypiStoreRepository.repositoryName,
            }),
            cdk.Fn.sub('arn:aws:codeartifact:${AWS::Region}:${AWS::AccountId}:package/${DomainName}/${TeamRepo}/*', {
              DomainName: this.domain.domainName,
              TeamRepo: this.teamRepository.repositoryName,
            }),
          ],
        }),
        new iam.PolicyStatement({
          sid: 'STSTokenAccess',
          effect: iam.Effect.ALLOW,
          actions: ['sts:GetServiceBearerToken'],
          resources: ['*'],
          conditions: {
            StringEquals: {
              'sts:AWSServiceName': 'codeartifact.amazonaws.com',
            },
          },
        }),
      ],
    });

    // Create IAM policy for production read-only access
    this.productionPolicy = new iam.ManagedPolicy(this, 'ProductionPolicy', {
      managedPolicyName: `CodeArtifact-Production-${envPrefix}-${uniqueSuffix}`,
      description: 'Policy for production read-only access to CodeArtifact repositories',
      statements: [
        new iam.PolicyStatement({
          sid: 'CodeArtifactProductionReadAccess',
          effect: iam.Effect.ALLOW,
          actions: [
            'codeartifact:GetAuthorizationToken',
            'codeartifact:GetRepositoryEndpoint',
            'codeartifact:ReadFromRepository',
          ],
          resources: [
            this.domain.attrArn,
            cdk.Fn.sub('arn:aws:codeartifact:${AWS::Region}:${AWS::AccountId}:repository/${DomainName}/${ProdRepo}', {
              DomainName: this.domain.domainName,
              ProdRepo: this.productionRepository.repositoryName,
            }),
            cdk.Fn.sub('arn:aws:codeartifact:${AWS::Region}:${AWS::AccountId}:package/${DomainName}/${ProdRepo}/*', {
              DomainName: this.domain.domainName,
              ProdRepo: this.productionRepository.repositoryName,
            }),
          ],
        }),
        new iam.PolicyStatement({
          sid: 'STSTokenAccess',
          effect: iam.Effect.ALLOW,
          actions: ['sts:GetServiceBearerToken'],
          resources: ['*'],
          conditions: {
            StringEquals: {
              'sts:AWSServiceName': 'codeartifact.amazonaws.com',
            },
          },
        }),
      ],
    });

    // Add outputs for important values
    new cdk.CfnOutput(this, 'DomainName', {
      value: this.domain.domainName,
      description: 'CodeArtifact domain name',
      exportName: `${envPrefix}-codeartifact-domain-name`,
    });

    new cdk.CfnOutput(this, 'DomainArn', {
      value: this.domain.attrArn,
      description: 'CodeArtifact domain ARN',
      exportName: `${envPrefix}-codeartifact-domain-arn`,
    });

    new cdk.CfnOutput(this, 'TeamRepositoryName', {
      value: this.teamRepository.repositoryName,
      description: 'Team development repository name',
      exportName: `${envPrefix}-codeartifact-team-repo`,
    });

    new cdk.CfnOutput(this, 'ProductionRepositoryName', {
      value: this.productionRepository.repositoryName,
      description: 'Production repository name',
      exportName: `${envPrefix}-codeartifact-prod-repo`,
    });

    new cdk.CfnOutput(this, 'DeveloperPolicyArn', {
      value: this.developerPolicy.managedPolicyArn,
      description: 'IAM policy ARN for developer access',
      exportName: `${envPrefix}-codeartifact-dev-policy-arn`,
    });

    new cdk.CfnOutput(this, 'ProductionPolicyArn', {
      value: this.productionPolicy.managedPolicyArn,
      description: 'IAM policy ARN for production access',
      exportName: `${envPrefix}-codeartifact-prod-policy-arn`,
    });

    new cdk.CfnOutput(this, 'KmsKeyArn', {
      value: this.encryptionKey.keyArn,
      description: 'KMS key ARN for domain encryption',
      exportName: `${envPrefix}-codeartifact-kms-key-arn`,
    });

    // CLI commands for authentication (as outputs for reference)
    new cdk.CfnOutput(this, 'NpmLoginCommand', {
      value: cdk.Fn.sub(
        'aws codeartifact login --tool npm --domain ${DomainName} --repository ${TeamRepo}',
        {
          DomainName: this.domain.domainName,
          TeamRepo: this.teamRepository.repositoryName,
        }
      ),
      description: 'CLI command to configure npm authentication',
    });

    new cdk.CfnOutput(this, 'PipLoginCommand', {
      value: cdk.Fn.sub(
        'aws codeartifact login --tool pip --domain ${DomainName} --repository ${TeamRepo}',
        {
          DomainName: this.domain.domainName,
          TeamRepo: this.teamRepository.repositoryName,
        }
      ),
      description: 'CLI command to configure pip authentication',
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const domainName = app.node.tryGetContext('domainName') || process.env.DOMAIN_NAME;
const enableEncryption = app.node.tryGetContext('enableEncryption') ?? 
                         (process.env.ENABLE_ENCRYPTION === 'true');
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || 
                         process.env.ENVIRONMENT_PREFIX || 'dev';

// Create the stack
new ArtifactManagementStack(app, 'ArtifactManagementStack', {
  domainName,
  enableEncryption,
  environmentPrefix,
  description: 'AWS CodeArtifact artifact management solution with repository hierarchy and IAM policies',
  
  // Use environment variables or default AWS account and region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Add stack-level tags
  tags: {
    Project: 'ArtifactManagement',
    ManagedBy: 'CDK',
    Environment: environmentPrefix,
  },
});

// Synthesize the app
app.synth();