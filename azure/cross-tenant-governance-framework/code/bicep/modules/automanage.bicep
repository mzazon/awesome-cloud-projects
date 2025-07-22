// ==============================================================================
// Automanage Module
// ==============================================================================
// This module creates Azure Automanage configuration profiles for automated
// virtual machine management across customer tenants.
// ==============================================================================

@description('Location for Automanage resources')
param location string

@description('Name of the Automanage configuration profile')
param automanageProfileName string

@description('Resource ID of the Log Analytics workspace')
param logAnalyticsWorkspaceId string

@description('Tags to apply to Automanage resources')
param tags object = {}

@description('Enable antimalware protection')
param enableAntimalware bool = true

@description('Enable Azure Security Center integration')
param enableSecurityCenter bool = true

@description('Enable backup services')
param enableBackup bool = true

@description('Enable boot diagnostics')
param enableBootDiagnostics bool = true

@description('Enable change tracking and inventory')
param enableChangeTracking bool = true

@description('Enable guest configuration')
param enableGuestConfiguration bool = true

@description('Enable update management')
param enableUpdateManagement bool = true

@description('Enable VM insights')
param enableVMInsights bool = true

// ==============================================================================
// Automanage Configuration Profile
// ==============================================================================

resource automanageProfile 'Microsoft.Automanage/configurationProfiles@2022-05-04' = {
  name: automanageProfileName
  location: location
  tags: tags
  properties: {
    configuration: {
      'Antimalware/Enable': string(enableAntimalware)
      'Antimalware/EnableRealTimeProtection': string(enableAntimalware)
      'Antimalware/RunScheduledScan': string(enableAntimalware)
      'Antimalware/ScanType': 'Quick'
      'Antimalware/ScanDay': '7'
      'Antimalware/ScanTime': '120'
      'AzureSecurityCenter/Enable': string(enableSecurityCenter)
      'Backup/Enable': string(enableBackup)
      'Backup/PolicyName': 'DefaultPolicy'
      'Backup/TimeZone': 'UTC'
      'Backup/InstantRpRetentionRangeInDays': '2'
      'Backup/SchedulePolicy': 'Daily'
      'Backup/ScheduleRunTime': '02:00'
      'Backup/RetentionPolicy': 'LongTermRetentionPolicy'
      'Backup/WeeklySchedule': 'Sunday'
      'Backup/MonthlySchedule': 'First'
      'Backup/YearlySchedule': 'January'
      'BootDiagnostics/Enable': string(enableBootDiagnostics)
      'ChangeTrackingAndInventory/Enable': string(enableChangeTracking)
      'GuestConfiguration/Enable': string(enableGuestConfiguration)
      'LogAnalytics/Enable': 'true'
      'LogAnalytics/WorkspaceId': logAnalyticsWorkspaceId
      'UpdateManagement/Enable': string(enableUpdateManagement)
      'UpdateManagement/ExcludeKbsRequiringReboot': 'false'
      'UpdateManagement/IncludeKbsRequiringReboot': 'true'
      'UpdateManagement/RebootSetting': 'IfRequired'
      'UpdateManagement/Categories': 'Critical,Security'
      'UpdateManagement/MaintenanceWindowDuration': '3'
      'UpdateManagement/MaintenanceWindowStartTime': '03:00'
      'UpdateManagement/MaintenanceWindowRecurrence': 'Weekly'
      'UpdateManagement/MaintenanceWindowInterval': '1'
      'UpdateManagement/MaintenanceWindowDayOfWeek': 'Sunday'
      'VMInsights/Enable': string(enableVMInsights)
    }
  }
}

// ==============================================================================
// Automanage Best Practices Profile (Production)
// ==============================================================================

resource automanageBestPracticesProfile 'Microsoft.Automanage/configurationProfiles@2022-05-04' = {
  name: '${automanageProfileName}-best-practices'
  location: location
  tags: union(tags, { profile: 'best-practices' })
  properties: {
    configuration: {
      'Antimalware/Enable': 'true'
      'Antimalware/EnableRealTimeProtection': 'true'
      'Antimalware/RunScheduledScan': 'true'
      'Antimalware/ScanType': 'Full'
      'Antimalware/ScanDay': '0'
      'Antimalware/ScanTime': '120'
      'AzureSecurityCenter/Enable': 'true'
      'Backup/Enable': 'true'
      'Backup/PolicyName': 'EnhancedPolicy'
      'Backup/TimeZone': 'UTC'
      'Backup/InstantRpRetentionRangeInDays': '5'
      'Backup/SchedulePolicy': 'Daily'
      'Backup/ScheduleRunTime': '01:00'
      'Backup/RetentionPolicy': 'LongTermRetentionPolicy'
      'Backup/WeeklySchedule': 'Sunday'
      'Backup/MonthlySchedule': 'First'
      'Backup/YearlySchedule': 'January'
      'BootDiagnostics/Enable': 'true'
      'ChangeTrackingAndInventory/Enable': 'true'
      'GuestConfiguration/Enable': 'true'
      'LogAnalytics/Enable': 'true'
      'LogAnalytics/WorkspaceId': logAnalyticsWorkspaceId
      'UpdateManagement/Enable': 'true'
      'UpdateManagement/ExcludeKbsRequiringReboot': 'false'
      'UpdateManagement/IncludeKbsRequiringReboot': 'true'
      'UpdateManagement/RebootSetting': 'IfRequired'
      'UpdateManagement/Categories': 'Critical,Security,Updates'
      'UpdateManagement/MaintenanceWindowDuration': '4'
      'UpdateManagement/MaintenanceWindowStartTime': '02:00'
      'UpdateManagement/MaintenanceWindowRecurrence': 'Weekly'
      'UpdateManagement/MaintenanceWindowInterval': '1'
      'UpdateManagement/MaintenanceWindowDayOfWeek': 'Sunday'
      'VMInsights/Enable': 'true'
    }
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('The resource ID of the Automanage configuration profile')
output automanageProfileId string = automanageProfile.id

@description('The resource ID of the Automanage best practices profile')
output automanageBestPracticesProfileId string = automanageBestPracticesProfile.id

@description('The Automanage profile name')
output automanageProfileName string = automanageProfile.name

@description('The Automanage best practices profile name')
output automanageBestPracticesProfileName string = automanageBestPracticesProfile.name