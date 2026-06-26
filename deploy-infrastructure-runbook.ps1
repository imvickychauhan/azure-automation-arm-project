param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$StorageResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$TemplateName,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "demo",
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountType = "Standard_LRS"
)

# Ensure no context inheritance
Disable-AzContextAutosave -Scope Process

try {
    # Connect using managed identity
    Write-Output "Connecting to Azure using managed identity..."
    $AzureContext = (Connect-AzAccount -Identity).context
    
    # Download ARM template from storage
    Write-Output "Downloading ARM template from storage..."
    $StorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroup -Name $StorageAccountName
    $StorageKey = (Get-AzStorageAccountKey -ResourceGroupName $StorageResourceGroup -Name $StorageAccountName)[0].Value
    $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageKey
    
    # Create temp directory for template
    $TempPath = "C:\Temp"
    if (!(Test-Path $TempPath)) {
        New-Item -ItemType Directory -Path $TempPath
    }
    
    # Download template file
    Get-AzStorageFileContent -ShareName "arm-templates" -Path $TemplateName -Destination $TempPath -Context $StorageContext
    $TemplateFile = Join-Path $TempPath $TemplateName
    
    # Set deployment parameters
    $DeploymentParams = @{
        storageAccountType = $StorageAccountType
        environment = $Environment
    }
    
    # Generate unique deployment name
    $DeploymentName = "deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-Output "Starting deployment: $DeploymentName"
    
    # Deploy ARM template
    $Deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFile -TemplateParameterObject $DeploymentParams -Verbose
    
    if ($Deployment.ProvisioningState -eq "Succeeded") {
        Write-Output "✅ Deployment completed successfully"
        Write-Output "Deployment Name: $DeploymentName"
        Write-Output "Provisioning State: $($Deployment.ProvisioningState)"
        
        # Log deployment outputs
        if ($Deployment.Outputs) {
            Write-Output "Deployment Outputs:"
            $Deployment.Outputs.Keys | ForEach-Object {
                Write-Output "  $($_): $($Deployment.Outputs[$_].Value)"
            }
        }
    } else {
        Write-Error "Deployment failed with state: $($Deployment.ProvisioningState)"
        throw "Deployment failed"
    }
    
} catch {
    Write-Error "Error during deployment: $($_.Exception.Message)"
    
    # Attempt rollback if deployment exists
    try {
        Write-Output "Attempting rollback to previous successful deployment..."
        $PreviousDeployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName | Where-Object { $_.ProvisioningState -eq "Succeeded" } | Sort-Object Timestamp -Descending | Select-Object -First 1
        
        if ($PreviousDeployment) {
            Write-Output "Rolling back to deployment: $($PreviousDeployment.DeploymentName)"
            # Rollback implementation would go here
        }
    } catch {
        Write-Error "Rollback failed: $($_.Exception.Message)"
    }
    
    throw $_.Exception
}