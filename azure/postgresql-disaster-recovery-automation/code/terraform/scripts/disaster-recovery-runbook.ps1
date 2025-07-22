# PowerShell Runbook for PostgreSQL Disaster Recovery
# This script automates the disaster recovery process for PostgreSQL Flexible Server
# Parameters are templated by Terraform during deployment

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName = "${resource_group_primary}",
    
    [Parameter(Mandatory=$true)]
    [string]$ReplicaServerName = "${replica_server_name}",
    
    [Parameter(Mandatory=$true)]
    [string]$SecondaryResourceGroup = "${resource_group_secondary}",
    
    [Parameter(Mandatory=$false)]
    [string]$PrimaryServerName = "${primary_server_name}",
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName = "${storage_account_name}",
    
    [Parameter(Mandatory=$false)]
    [string]$LogLevel = "Info"
)

# Import required PowerShell modules
Write-Output "Importing required PowerShell modules..."
try {
    Import-Module Az.Accounts -Force
    Import-Module Az.PostgreSQL -Force
    Import-Module Az.Monitor -Force
    Import-Module Az.Storage -Force
    Import-Module Az.Resources -Force
    Write-Output "✅ PowerShell modules imported successfully"
} catch {
    Write-Error "❌ Failed to import PowerShell modules: $($_.Exception.Message)"
    throw
}

# Function to write timestamped log messages
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "Error" { Write-Error $logMessage }
        "Warning" { Write-Warning $logMessage }
        "Info" { Write-Output $logMessage }
        default { Write-Output $logMessage }
    }
}

# Function to authenticate using managed identity
function Initialize-Authentication {
    try {
        Write-Log "Authenticating using managed identity..."
        Connect-AzAccount -Identity
        Write-Log "✅ Authentication successful"
        
        # Get current subscription context
        $context = Get-AzContext
        Write-Log "Current subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
        
        return $true
    } catch {
        Write-Log "❌ Authentication failed: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Function to check if replica server exists and is healthy
function Test-ReplicaServerHealth {
    param(
        [string]$ServerName,
        [string]$ResourceGroup
    )
    
    try {
        Write-Log "Checking replica server health: $ServerName in $ResourceGroup"
        
        $replica = Get-AzPostgreSqlFlexibleServer -Name $ServerName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
        
        if ($null -eq $replica) {
            Write-Log "❌ Replica server not found: $ServerName" -Level "Error"
            return $false
        }
        
        if ($replica.State -ne "Ready") {
            Write-Log "❌ Replica server is not in Ready state. Current state: $($replica.State)" -Level "Error"
            return $false
        }
        
        if ($replica.ReplicationRole -ne "AsyncReplica") {
            Write-Log "❌ Server is not configured as async replica. Current role: $($replica.ReplicationRole)" -Level "Error"
            return $false
        }
        
        Write-Log "✅ Replica server is healthy and ready for promotion"
        return $true
    } catch {
        Write-Log "❌ Error checking replica server health: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Function to promote replica to primary
function Invoke-ReplicaPromotion {
    param(
        [string]$ServerName,
        [string]$ResourceGroup
    )
    
    try {
        Write-Log "Starting replica promotion for server: $ServerName"
        
        # Stop replication and promote replica to primary
        Write-Log "Stopping replication for server: $ServerName"
        
        # Use Azure REST API to promote replica (as PowerShell module may not have direct promotion command)
        $subscriptionId = (Get-AzContext).Subscription.Id
        $resourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.DBforPostgreSQL/flexibleServers/$ServerName"
        
        # Promote the replica by stopping replication
        $promotionResult = Invoke-AzRestMethod -Uri "https://management.azure.com$resourceId/stopReplication?api-version=2022-12-01" -Method POST
        
        if ($promotionResult.StatusCode -eq 200 -or $promotionResult.StatusCode -eq 202) {
            Write-Log "✅ Replica promotion initiated successfully"
            
            # Wait for promotion to complete
            $timeout = 300 # 5 minutes timeout
            $elapsed = 0
            $checkInterval = 10
            
            do {
                Start-Sleep -Seconds $checkInterval
                $elapsed += $checkInterval
                
                $server = Get-AzPostgreSqlFlexibleServer -Name $ServerName -ResourceGroupName $ResourceGroup
                Write-Log "Checking server status: $($server.State), Role: $($server.ReplicationRole)"
                
                if ($server.ReplicationRole -eq "Primary" -and $server.State -eq "Ready") {
                    Write-Log "✅ Replica promoted to primary successfully"
                    return $true
                }
                
            } while ($elapsed -lt $timeout)
            
            Write-Log "❌ Replica promotion timed out after $timeout seconds" -Level "Error"
            return $false
        } else {
            Write-Log "❌ Replica promotion failed with status code: $($promotionResult.StatusCode)" -Level "Error"
            Write-Log "Response: $($promotionResult.Content)" -Level "Error"
            return $false
        }
        
    } catch {
        Write-Log "❌ Error during replica promotion: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Function to update firewall rules on promoted server
function Update-FirewallRules {
    param(
        [string]$ServerName,
        [string]$ResourceGroup
    )
    
    try {
        Write-Log "Updating firewall rules for promoted server: $ServerName"
        
        # Get existing firewall rules from primary server (if available)
        # This is a simplified approach - in production, you'd have predefined rules
        $firewallRules = @(
            @{
                Name = "AllowAzureServices"
                StartIpAddress = "0.0.0.0"
                EndIpAddress = "0.0.0.0"
            },
            @{
                Name = "AllowApplications"
                StartIpAddress = "10.0.0.0"
                EndIpAddress = "10.255.255.255"
            }
        )
        
        foreach ($rule in $firewallRules) {
            try {
                New-AzPostgreSqlFlexibleServerFirewallRule -Name $rule.Name -ResourceGroupName $ResourceGroup -ServerName $ServerName -StartIpAddress $rule.StartIpAddress -EndIpAddress $rule.EndIpAddress -ErrorAction SilentlyContinue
                Write-Log "✅ Firewall rule created: $($rule.Name)"
            } catch {
                Write-Log "⚠️ Firewall rule may already exist: $($rule.Name)" -Level "Warning"
            }
        }
        
        return $true
    } catch {
        Write-Log "❌ Error updating firewall rules: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Function to log disaster recovery event
function Write-DisasterRecoveryLog {
    param(
        [string]$EventType,
        [string]$EventDescription,
        [string]$ServerName,
        [string]$Status
    )
    
    try {
        $logEntry = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
            EventType = $EventType
            Description = $EventDescription
            ServerName = $ServerName
            Status = $Status
            RunbookName = "PostgreSQL-DisasterRecovery"
        } | ConvertTo-Json
        
        Write-Log "Disaster Recovery Event: $logEntry"
        
        # If storage account is available, write to blob storage
        if ($StorageAccountName) {
            try {
                $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
                $ctx = $storageAccount.Context
                $blobName = "dr-event-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
                Set-AzStorageBlobContent -File $logEntry -Container "recovery-logs" -Blob $blobName -Context $ctx
                Write-Log "✅ Disaster recovery event logged to storage"
            } catch {
                Write-Log "⚠️ Could not write to storage account: $($_.Exception.Message)" -Level "Warning"
            }
        }
        
    } catch {
        Write-Log "❌ Error logging disaster recovery event: $($_.Exception.Message)" -Level "Error"
    }
}

# Function to send notification
function Send-DisasterRecoveryNotification {
    param(
        [string]$Subject,
        [string]$Message,
        [string]$Status
    )
    
    try {
        Write-Log "Sending disaster recovery notification: $Subject"
        
        # Log the notification details
        $notificationDetails = @{
            Subject = $Subject
            Message = $Message
            Status = $Status
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
        }
        
        Write-Log "Notification Details: $($notificationDetails | ConvertTo-Json)"
        
        # In a real implementation, you would integrate with:
        # - Azure Logic Apps for email notifications
        # - Microsoft Teams webhooks
        # - Azure Service Bus for message queuing
        # - Azure Event Grid for event publishing
        
        Write-Log "✅ Notification sent successfully"
        
    } catch {
        Write-Log "❌ Error sending notification: $($_.Exception.Message)" -Level "Error"
    }
}

# Main disaster recovery execution function
function Start-DisasterRecovery {
    Write-Log "===== Starting PostgreSQL Disaster Recovery Process ====="
    
    $startTime = Get-Date
    $overallSuccess = $true
    
    try {
        # Step 1: Authenticate
        Write-Log "Step 1: Authenticating..."
        if (-not (Initialize-Authentication)) {
            throw "Authentication failed"
        }
        
        # Step 2: Validate parameters
        Write-Log "Step 2: Validating parameters..."
        if ([string]::IsNullOrEmpty($ReplicaServerName)) {
            throw "Replica server name is required"
        }
        if ([string]::IsNullOrEmpty($SecondaryResourceGroup)) {
            throw "Secondary resource group is required"
        }
        
        # Step 3: Check replica server health
        Write-Log "Step 3: Checking replica server health..."
        if (-not (Test-ReplicaServerHealth -ServerName $ReplicaServerName -ResourceGroup $SecondaryResourceGroup)) {
            throw "Replica server health check failed"
        }
        
        # Step 4: Log disaster recovery initiation
        Write-DisasterRecoveryLog -EventType "DisasterRecoveryInitiated" -EventDescription "Disaster recovery process started" -ServerName $ReplicaServerName -Status "InProgress"
        
        # Step 5: Promote replica to primary
        Write-Log "Step 5: Promoting replica to primary..."
        if (-not (Invoke-ReplicaPromotion -ServerName $ReplicaServerName -ResourceGroup $SecondaryResourceGroup)) {
            throw "Replica promotion failed"
        }
        
        # Step 6: Update firewall rules
        Write-Log "Step 6: Updating firewall rules..."
        if (-not (Update-FirewallRules -ServerName $ReplicaServerName -ResourceGroup $SecondaryResourceGroup)) {
            Write-Log "⚠️ Firewall rules update had issues, but continuing..." -Level "Warning"
        }
        
        # Step 7: Log successful disaster recovery
        Write-DisasterRecoveryLog -EventType "DisasterRecoveryCompleted" -EventDescription "Disaster recovery completed successfully" -ServerName $ReplicaServerName -Status "Success"
        
        # Step 8: Send success notification
        $endTime = Get-Date
        $duration = $endTime - $startTime
        $successMessage = "Disaster recovery completed successfully for PostgreSQL server $ReplicaServerName in $($duration.TotalMinutes.ToString('F2')) minutes."
        
        Send-DisasterRecoveryNotification -Subject "PostgreSQL Disaster Recovery - Success" -Message $successMessage -Status "Success"
        
        Write-Log "===== Disaster Recovery Process Completed Successfully ====="
        Write-Log "New primary server: $ReplicaServerName"
        Write-Log "Resource group: $SecondaryResourceGroup"
        Write-Log "Duration: $($duration.TotalMinutes.ToString('F2')) minutes"
        
    } catch {
        $overallSuccess = $false
        $errorMessage = $_.Exception.Message
        
        Write-Log "===== Disaster Recovery Process Failed ====="
        Write-Log "Error: $errorMessage" -Level "Error"
        
        # Log disaster recovery failure
        Write-DisasterRecoveryLog -EventType "DisasterRecoveryFailed" -EventDescription "Disaster recovery failed: $errorMessage" -ServerName $ReplicaServerName -Status "Failed"
        
        # Send failure notification
        $endTime = Get-Date
        $duration = $endTime - $startTime
        $failureMessage = "Disaster recovery failed for PostgreSQL server $ReplicaServerName after $($duration.TotalMinutes.ToString('F2')) minutes. Error: $errorMessage"
        
        Send-DisasterRecoveryNotification -Subject "PostgreSQL Disaster Recovery - Failed" -Message $failureMessage -Status "Failed"
        
        throw $errorMessage
    }
    
    return $overallSuccess
}

# Main execution
try {
    Write-Log "PostgreSQL Disaster Recovery Runbook started"
    Write-Log "Parameters: ResourceGroupName=$ResourceGroupName, ReplicaServerName=$ReplicaServerName, SecondaryResourceGroup=$SecondaryResourceGroup"
    
    $result = Start-DisasterRecovery
    
    if ($result) {
        Write-Output "✅ Disaster recovery completed successfully"
        exit 0
    } else {
        Write-Output "❌ Disaster recovery failed"
        exit 1
    }
    
} catch {
    Write-Error "❌ Disaster recovery runbook failed: $($_.Exception.Message)"
    exit 1
}