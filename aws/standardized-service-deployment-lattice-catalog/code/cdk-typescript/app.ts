#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { StandardizedServiceDeploymentStack } from './lib/standardized-service-deployment-stack';
import { ServiceCatalogStack } from './lib/service-catalog-stack';
import { VpcLatticeTemplatesStack } from './lib/vpc-lattice-templates-stack';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';

const app = new cdk.App();

// Get context variables with defaults
const environment = app.node.tryGetContext('environment') || 'dev';
const projectName = app.node.tryGetContext('projectName') || 'standardized-lattice';

// Define stack configuration
const stackProps: cdk.StackProps = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: `Standardized Service Deployment with VPC Lattice and Service Catalog - ${environment}`,
  tags: {
    Project: projectName,
    Environment: environment,
    Purpose: 'VPCLatticeStandardization',
    ManagedBy: 'CDK',
  },
};

// Stack 1: VPC Lattice CloudFormation Templates Storage
const templatesStack = new VpcLatticeTemplatesStack(app, 'VpcLatticeTemplates', {
  ...stackProps,
  stackName: `${projectName}-templates-${environment}`,
});

// Stack 2: Service Catalog Portfolio and Products
const serviceCatalogStack = new ServiceCatalogStack(app, 'ServiceCatalog', {
  ...stackProps,
  stackName: `${projectName}-catalog-${environment}`,
  templatesBucket: templatesStack.templatesBucket,
  serviceNetworkTemplateKey: templatesStack.serviceNetworkTemplateKey,
  latticeServiceTemplateKey: templatesStack.latticeServiceTemplateKey,
});

// Stack 3: Main infrastructure and example deployment
const mainStack = new StandardizedServiceDeploymentStack(app, 'StandardizedServiceDeployment', {
  ...stackProps,
  stackName: `${projectName}-main-${environment}`,
  serviceCatalogPortfolio: serviceCatalogStack.portfolio,
  networkProduct: serviceCatalogStack.networkProduct,
  serviceProduct: serviceCatalogStack.serviceProduct,
});

// Add stack dependencies
serviceCatalogStack.addDependency(templatesStack);
mainStack.addDependency(serviceCatalogStack);

// Apply CDK Nag security checks in non-development environments
if (environment !== 'dev') {
  AwsSolutionsChecks.check(app);
}

// Global suppressions for known acceptable patterns
NagSuppressions.addStackSuppressions(templatesStack, [
  {
    id: 'AwsSolutions-S1',
    reason: 'S3 bucket is used for CloudFormation template storage and does not require access logging',
  },
]);

NagSuppressions.addStackSuppressions(serviceCatalogStack, [
  {
    id: 'AwsSolutions-IAM5',
    reason: 'Service Catalog launch role requires broad permissions to manage VPC Lattice resources',
  },
]);

app.synth();