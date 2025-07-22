// ==============================================================================
// Azure Lighthouse Module
// ==============================================================================
// This module creates Azure Lighthouse delegation resources for cross-tenant
// resource management.
// ==============================================================================

@description('The tenant ID of the MSP (Managed Service Provider)')
param mspTenantId string

@description('The name of the MSP offer for Lighthouse delegation')
param mspOfferName string

@description('Description of the MSP offer')
param mspOfferDescription string

@description('Array of authorization objects for Lighthouse delegation')
param authorizations array

@description('Tags to apply to Lighthouse resources')
param tags object = {}

// ==============================================================================
// Variables
// ==============================================================================

var mspRegistrationName = guid(mspOfferName)
var mspAssignmentName = guid('${mspOfferName}-assignment')

// ==============================================================================
// Lighthouse Registration Definition
// ==============================================================================

resource lighthouseRegistrationDefinition 'Microsoft.ManagedServices/registrationDefinitions@2022-10-01' = {
  name: mspRegistrationName
  properties: {
    registrationDefinitionName: mspOfferName
    description: mspOfferDescription
    managedByTenantId: mspTenantId
    authorizations: authorizations
    eligibleAuthorizations: []
  }
}

// ==============================================================================
// Lighthouse Registration Assignment
// ==============================================================================

resource lighthouseRegistrationAssignment 'Microsoft.ManagedServices/registrationAssignments@2022-10-01' = {
  name: mspAssignmentName
  properties: {
    registrationDefinitionId: lighthouseRegistrationDefinition.id
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('The resource ID of the Lighthouse registration definition')
output registrationDefinitionId string = lighthouseRegistrationDefinition.id

@description('The resource ID of the Lighthouse registration assignment')
output registrationAssignmentId string = lighthouseRegistrationAssignment.id

@description('The MSP registration name for reference')
output mspRegistrationName string = mspRegistrationName

@description('The MSP assignment name for reference')
output mspAssignmentName string = mspAssignmentName

@description('The registration definition name')
output registrationDefinitionName string = lighthouseRegistrationDefinition.properties.registrationDefinitionName