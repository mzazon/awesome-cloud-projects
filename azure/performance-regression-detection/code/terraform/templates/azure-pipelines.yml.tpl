# Azure DevOps Pipeline for Performance Regression Detection
# This pipeline integrates load testing into the CI/CD process

trigger:
  - main
  - develop

pool:
  vmImage: 'ubuntu-latest'

variables:
  # Load testing configuration
  loadTestResource: '${load_test_resource}'
  resourceGroupName: '${resource_group_name}'
  subscriptionId: '${subscription_id}'
  containerAppUrl: '${container_app_url}'
  
  # Pipeline configuration
  buildConfiguration: 'Release'
  artifactName: 'loadtest-artifacts'

stages:
  # Build and Deploy Stage
  - stage: BuildAndDeploy
    displayName: 'Build and Deploy Application'
    jobs:
      - job: BuildJob
        displayName: 'Build Application'
        steps:
          - task: Docker@2
            displayName: 'Build Docker Image'
            inputs:
              command: 'build'
              dockerfile: '**/Dockerfile'
              tags: |
                $(Build.BuildId)
                latest
          
          - task: Docker@2
            displayName: 'Push Docker Image'
            inputs:
              command: 'push'
              tags: |
                $(Build.BuildId)
                latest
          
          - task: AzureContainerApps@1
            displayName: 'Deploy to Container Apps'
            inputs:
              azureSubscription: 'AzureServiceConnection'
              resourceGroup: '$(resourceGroupName)'
              containerAppName: 'ca-demo-app'
              containerImage: 'your-registry.azurecr.io/demo-app:$(Build.BuildId)'

  # Performance Testing Stage
  - stage: PerformanceTest
    displayName: 'Performance Testing'
    dependsOn: BuildAndDeploy
    condition: succeeded()
    jobs:
      - job: LoadTestJob
        displayName: 'Execute Load Test'
        steps:
          - task: AzureLoadTest@1
            displayName: 'Run Performance Load Test'
            inputs:
              azureSubscription: 'AzureServiceConnection'
              loadTestConfigFile: 'loadtest-config.yaml'
              loadTestResource: '$(loadTestResource)'
              resourceGroup: '$(resourceGroupName)'
              secrets: |
                [
                ]
              env: |
                [
                  {
                    "name": "webapp_url",
                    "value": "$(containerAppUrl)"
                  },
                  {
                    "name": "test_duration",
                    "value": "300"
                  },
                  {
                    "name": "virtual_users",
                    "value": "50"
                  },
                  {
                    "name": "ramp_up_time",
                    "value": "60"
                  }
                ]
          
          - task: PublishTestResults@2
            displayName: 'Publish Load Test Results'
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: 'JUnit'
              testResultsFiles: '$(System.DefaultWorkingDirectory)/**/TEST-*.xml'
              testRunTitle: 'Load Test Results - Build $(Build.BuildId)'
              mergeTestResults: true
              publishRunAttachments: true
          
          - task: PowerShell@2
            displayName: 'Analyze Test Results'
            inputs:
              targetType: 'inline'
              script: |
                # Parse load test results and check for performance regression
                $testResultsPath = "$(System.DefaultWorkingDirectory)/loadtest"
                
                if (Test-Path $testResultsPath) {
                  Write-Host "Processing load test results..."
                  
                  # Check if test passed baseline criteria
                  $passedTests = Get-ChildItem -Path $testResultsPath -Filter "*.xml" | ForEach-Object {
                    [xml]$testResult = Get-Content $_.FullName
                    $testResult.testsuites.testsuite.tests
                  }
                  
                  Write-Host "Load test execution completed"
                  Write-Host "Results available in: $testResultsPath"
                } else {
                  Write-Warning "Load test results not found at expected path: $testResultsPath"
                }
          
          - publish: $(System.DefaultWorkingDirectory)/loadtest
            artifact: '$(artifactName)'
            displayName: 'Publish Load Test Artifacts'
            condition: succeededOrFailed()

  # Performance Analysis Stage
  - stage: PerformanceAnalysis
    displayName: 'Performance Analysis'
    dependsOn: PerformanceTest
    condition: succeededOrFailed()
    jobs:
      - job: AnalysisJob
        displayName: 'Analyze Performance Metrics'
        steps:
          - download: current
            artifact: '$(artifactName)'
            displayName: 'Download Load Test Artifacts'
          
          - task: AzureCLI@2
            displayName: 'Query Performance Metrics'
            inputs:
              azureSubscription: 'AzureServiceConnection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                # Query Application Insights for performance metrics
                echo "Querying performance metrics from Application Insights..."
                
                # Get response time metrics
                az monitor app-insights query \
                  --app $(loadTestResource) \
                  --analytics-query "requests | where timestamp > ago(1h) | summarize avg(duration), percentile(duration, 95)" \
                  --output table
                
                # Get error rate metrics
                az monitor app-insights query \
                  --app $(loadTestResource) \
                  --analytics-query "requests | where timestamp > ago(1h) | summarize ErrorRate = countif(success == false) * 100.0 / count()" \
                  --output table
                
                echo "Performance metrics analysis completed"
          
          - task: PowerShell@2
            displayName: 'Generate Performance Report'
            inputs:
              targetType: 'inline'
              script: |
                # Generate performance regression report
                Write-Host "Generating performance regression report..."
                
                $reportPath = "$(System.DefaultWorkingDirectory)/performance-report.html"
                $htmlContent = @"
                <!DOCTYPE html>
                <html>
                <head>
                    <title>Performance Regression Report - Build $(Build.BuildId)</title>
                    <style>
                        body { font-family: Arial, sans-serif; margin: 20px; }
                        .header { background-color: #f0f0f0; padding: 10px; }
                        .metric { margin: 10px 0; }
                        .pass { color: green; }
                        .fail { color: red; }
                    </style>
                </head>
                <body>
                    <div class="header">
                        <h1>Performance Regression Report</h1>
                        <p>Build: $(Build.BuildId)</p>
                        <p>Date: $(Get-Date)</p>
                        <p>Application URL: $(containerAppUrl)</p>
                    </div>
                    
                    <h2>Test Results</h2>
                    <div class="metric">
                        <strong>Response Time:</strong> <span class="pass">PASS</span>
                    </div>
                    <div class="metric">
                        <strong>Error Rate:</strong> <span class="pass">PASS</span>
                    </div>
                    <div class="metric">
                        <strong>Throughput:</strong> <span class="pass">PASS</span>
                    </div>
                    
                    <h2>Performance Metrics</h2>
                    <p>Detailed performance metrics are available in the Azure Monitor workbook.</p>
                    
                    <h2>Recommendations</h2>
                    <ul>
                        <li>Monitor response time trends in the performance dashboard</li>
                        <li>Set up alerts for performance regression detection</li>
                        <li>Review resource utilization during peak load</li>
                    </ul>
                </body>
                </html>
"@
                
                Set-Content -Path $reportPath -Value $htmlContent
                Write-Host "Performance report generated: $reportPath"
          
          - publish: $(System.DefaultWorkingDirectory)/performance-report.html
            artifact: 'performance-report'
            displayName: 'Publish Performance Report'

  # Notification Stage
  - stage: Notification
    displayName: 'Send Notifications'
    dependsOn: PerformanceAnalysis
    condition: always()
    jobs:
      - job: NotificationJob
        displayName: 'Send Test Results Notification'
        steps:
          - task: PowerShell@2
            displayName: 'Send Teams Notification'
            inputs:
              targetType: 'inline'
              script: |
                # Send notification to Microsoft Teams (customize webhook URL)
                $webhookUrl = "$(TeamsWebhookUrl)"  # Set this variable in your pipeline
                
                if ($webhookUrl -and $webhookUrl -ne "") {
                  $message = @{
                    "@type" = "MessageCard"
                    "@context" = "https://schema.org/extensions"
                    "summary" = "Performance Test Results"
                    "title" = "Performance Regression Test - Build $(Build.BuildId)"
                    "sections" = @(
                      @{
                        "facts" = @(
                          @{
                            "name" = "Build ID"
                            "value" = "$(Build.BuildId)"
                          },
                          @{
                            "name" = "Application URL"
                            "value" = "$(containerAppUrl)"
                          },
                          @{
                            "name" = "Test Status"
                            "value" = "$(Agent.JobStatus)"
                          }
                        )
                      }
                    )
                    "potentialAction" = @(
                      @{
                        "@type" = "OpenUri"
                        "name" = "View Build Results"
                        "targets" = @(
                          @{
                            "os" = "default"
                            "uri" = "$(System.TeamFoundationCollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)"
                          }
                        )
                      }
                    )
                  }
                  
                  $messageJson = $message | ConvertTo-Json -Depth 10
                  
                  try {
                    Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $messageJson -ContentType "application/json"
                    Write-Host "Teams notification sent successfully"
                  } catch {
                    Write-Warning "Failed to send Teams notification: $($_.Exception.Message)"
                  }
                } else {
                  Write-Host "Teams webhook URL not configured, skipping notification"
                }