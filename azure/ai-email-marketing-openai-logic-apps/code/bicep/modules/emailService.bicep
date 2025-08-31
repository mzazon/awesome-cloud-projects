@description('Email Communication Services module for AI-powered email marketing')

// Parameters
@description('Email Communication Services resource name')
param emailServicesName string

@description('Communication Services resource name for linking')
param communicationServicesName string

@description('Location for email services (must be global for Communication Services)')
param location string = 'global'

@description('Email domain type')
@allowed(['AzureManaged', 'CustomDomain'])
param emailDomainType string = 'AzureManaged'

@description('Custom email domain name (if using CustomDomain)')
param customEmailDomain string = ''

@description('Tags to apply to resources')
param tags object = {}

// Variables
var azureManagedDomainName = 'AzureManagedDomain'

// Email Communication Services
resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: emailServicesName
  location: location
  tags: tags
  properties: {
    dataLocation: 'United States'
  }
}

// Azure Managed Domain (default option)
resource azureManagedDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = if (emailDomainType == 'AzureManaged') {
  parent: emailService
  name: azureManagedDomainName
  location: location
  tags: tags
  properties: {
    domainManagement: 'AzureManaged'
  }
}

// Custom Domain (requires DNS verification)
resource customDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = if (emailDomainType == 'CustomDomain' && !empty(customEmailDomain)) {
  parent: emailService
  name: customEmailDomain
  location: location
  tags: tags
  properties: {
    domainManagement: 'CustomerManaged'
    userEngagementTracking: 'Enabled'
  }
}

// Link Email Service to Communication Services
resource emailServiceConnection 'Microsoft.Communication/communicationServices@2023-04-01' existing = {
  name: communicationServicesName
}

// Connect the email domain to the communication service
resource domainConnection 'Microsoft.Communication/emailServices/domains/senderUsernames@2023-04-01' = if (emailDomainType == 'AzureManaged') {
  parent: azureManagedDomain
  name: 'DoNotReply'
  properties: {
    username: 'DoNotReply'
    displayName: 'AI Email Marketing System'
  }
}

// Custom domain sender username (if using custom domain)
resource customDomainConnection 'Microsoft.Communication/emailServices/domains/senderUsernames@2023-04-01' = if (emailDomainType == 'CustomDomain' && !empty(customEmailDomain)) {
  parent: customDomain
  name: 'DoNotReply'
  properties: {
    username: 'DoNotReply'
    displayName: 'AI Email Marketing System'
  }
}

// Outputs
@description('Email Services resource name')
output emailServicesName string = emailService.name

@description('Email Services resource ID')
output emailServicesId string = emailService.id

@description('Azure Managed Domain name (if using Azure Managed Domain)')
output azureManagedDomain string = emailDomainType == 'AzureManaged' ? azureManagedDomain.properties.mailFromSenderDomain : ''

@description('Custom domain name (if using custom domain)')
output customDomainName string = emailDomainType == 'CustomDomain' ? customEmailDomain : ''

@description('Email domain verification status')
output domainVerificationStatus string = emailDomainType == 'AzureManaged' ? 'Verified' : (emailDomainType == 'CustomDomain' ? customDomain.properties.verificationStates.Domain.status : 'Not Configured')

@description('Domain management type')
output domainManagement string = emailDomainType

@description('DNS verification records (for custom domains)')
output dnsVerificationRecords object = emailDomainType == 'CustomDomain' && !empty(customEmailDomain) ? {
  domain: {
    type: customDomain.properties.domainVerificationRecords.Domain.type
    name: customDomain.properties.domainVerificationRecords.Domain.name
    value: customDomain.properties.domainVerificationRecords.Domain.value
    ttl: customDomain.properties.domainVerificationRecords.Domain.ttl
  }
  spf: {
    type: customDomain.properties.domainVerificationRecords.SPF.type
    name: customDomain.properties.domainVerificationRecords.SPF.name
    value: customDomain.properties.domainVerificationRecords.SPF.value
    ttl: customDomain.properties.domainVerificationRecords.SPF.ttl
  }
  dkim: {
    type: customDomain.properties.domainVerificationRecords.DKIM.type
    name: customDomain.properties.domainVerificationRecords.DKIM.name
    value: customDomain.properties.domainVerificationRecords.DKIM.value
    ttl: customDomain.properties.domainVerificationRecords.DKIM.ttl
  }
  dkim2: {
    type: customDomain.properties.domainVerificationRecords.DKIM2.type
    name: customDomain.properties.domainVerificationRecords.DKIM2.name
    value: customDomain.properties.domainVerificationRecords.DKIM2.value
    ttl: customDomain.properties.domainVerificationRecords.DKIM2.ttl
  }
  dmarc: {
    type: customDomain.properties.domainVerificationRecords.DMARC.type
    name: customDomain.properties.domainVerificationRecords.DMARC.name
    value: customDomain.properties.domainVerificationRecords.DMARC.value
    ttl: customDomain.properties.domainVerificationRecords.DMARC.ttl
  }
} : {}

@description('Configuration instructions')
output configurationInstructions object = {
  azureManaged: emailDomainType == 'AzureManaged' ? 'Azure Managed Domain is automatically configured and verified' : ''
  customDomain: emailDomainType == 'CustomDomain' ? 'Add the DNS verification records to your domain DNS configuration' : ''
  senderAddress: emailDomainType == 'AzureManaged' ? 'DoNotReply@${azureManagedDomain.properties.mailFromSenderDomain}' : (emailDomainType == 'CustomDomain' ? 'DoNotReply@${customEmailDomain}' : '')
}