# Cleanup in case we're running a second time
Remove-Variable * -ErrorAction SilentlyContinue

# Check for AzureADPreview module
try
{
    if ((Get-Module -Name AzureADPreview -ListAvailable).Version -lt [System.Version]"2.0.2.77") { Throw "Bad AzureAD Module version." }
}
catch
{
    #Attempt to install proper Azure AD Module
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
    Install-Module AzureADPreview -Scope CurrentUser -Force -AllowClobber -MinimumVersion 2.0.2.77
}

Import-Module AzureADPreview -Force

$secretLife = 20 #Years

# Mapping Policy
$policytemplate = @"
{
  "ClaimsMappingPolicy": {
    "Version": 1,
    "IncludeBasicClaimSet": true,
    "ClaimsSchema": [
      {
        "Source": "user",
        "ID": "onpremisessamaccountname",
        "JwtClaimType": "sAMAccountName"
      }
    ]
  }
}
"@

try {
    # Connect to Azure AD
    Connect-AzureAD -ErrorAction Stop | Out-Null

    # Present a list of service principals for the user to choose
    Write-Host "Obtaining list of Azure AD Service Principals..." -ForegroundColor Cyan -NoNewline
    $spnobj = Get-AzureADServicePrincipal -all $true | Sort-Object DisplayName | Out-GridView -PassThru -Title "Select your ClinicianNexus app registration"
    Write-Host "Application Chosen: $($spnobj.AppDisplayName)" -ForegroundColor Green

    # Create new Azure AD Claims Policy (https://learn.microsoft.com/en-us/azure/active-directory/develop/reference-claims-mapping-policy-type)
    Write-Host "Creating claims mapping policy..." -ForegroundColor Cyan -NoNewline
    $pol = New-AzureADPolicy -Definition $policytemplate -DisplayName "ClinicianNexus_Mapping_Policy_$(Get-Date (Get-Date).ToUniversalTime() -Format "MM-dd-yyyy-HH:mm")" -Type "ClaimsMappingPolicy" -IsOrganizationDefault $false
    Write-Host "Created policy ID: $($pol.Id)" -ForegroundColor Green

    # Check for and remove existing policy
    Write-Host "Checking for an existing mapping policy attached to Service Principal ($($spnobj.ObjectId))..." -ForegroundColor Cyan -NoNewline
    $oldpol = Get-AzureADServicePrincipalPolicy -Id $spnobj.ObjectId
    if ($oldpol -ne $null)
    {
        Write-Host "Found an existing policy." -ForegroundColor Yellow
        Write-Host "Detaching policy with Id: $($oldpol.Id) and Name: $($oldpol.DisplayName)..." -ForegroundColor Cyan -NoNewline
        Remove-AzureADServicePrincipalPolicy -Id $spnobj.ObjectId -PolicyId $oldpol.Id
        Write-Host "Done." -ForegroundColor Green
    } else { Write-Host "Not found." -ForegroundColor Green }

    # Assign the new mapping policy to the selected application
    Write-Host "Assigning policy ($($pol.Id)) to registered app ($($spnobj.ObjectId))..." -ForegroundColor Cyan -NoNewline
    Add-AzureADServicePrincipalPolicy -Id $spnobj.ObjectId -RefObjectId $pol.Id
    Write-Host "Done." -ForegroundColor Green

    # Configure long lived secret
    Write-Host "Creating secret with $($secretLife) year validity..." -ForegroundColor Cyan -NoNewline
    $startDate = Get-Date
    $endDate = $startDate.AddYears($secretLife) 
    $aadAppSecret = New-AzureADApplicationPasswordCredential -ObjectId (Get-AzureADApplication -Filter "AppId eq '$($spnobj.AppId)'").ObjectId -CustomKeyIdentifier "ClinicianNexus_$(Get-Date (Get-Date).ToUniversalTime() -Format "MM-dd-yyyy-HH:mm")" -StartDate $startDate -EndDate $endDate
    Write-Host "Done." -ForegroundColor Green

    # Output secret value and disconnect AzureAD
    write-host "Record this application secret: " -NoNewLine -ForegroundColor Cyan 
    write-host "$($aadAppSecret.Value)" -ForegroundColor Yellow
    Disconnect-AzureAD -ErrorAction SilentlyContinue
}
catch
{
    Write-Host "Failed." -ForegroundColor Red
    Write-Host "Cleaning Up..." -ForegroundColor Cyan
    # Remove new mapping policy
    if ($pol -ne $null) { 
        Write-Host "Removing mapping policy ($($pol.Id))..." -ForegroundColor Cyan -NoNewline
        Remove-AzureADPolicy -Id $pol.Id
        Write-Host "Done." -ForegroundColor Green
    }

    # Reattach original mapping policy
    if (($oldpol -ne $null) -and ($spnobj -ne $null)) {
        Write-Host "Reattaching original mapping policy ($($oldpol.Id))..." -ForegroundColor Cyan -NoNewLine
        Add-AzureADServicePrincipalPolicy -Id $spnobj.ObjectId -RefObjectId $oldpol.Id
        Write-Host "Done." -ForegroundColor Green
    }

    # Disconnect AzureAD and report error
    Disconnect-AzureAD -ErrorAction SilentlyContinue
    Write-Host "----------------[Unexpected Error]------------------" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
}



