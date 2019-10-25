##############################################################################################################################
#### Script:      Update-MachineCatalog.ps1                                      
#### Author:      Callan Halls-Palmer                                            
#### Version:     1.2                                                            
#### Description: This script will allow an admin to quickly update a Machine Catalog using a selection of prompts.
####
#### Changes:     v1.2 - 16-10-2019 - CHP: Added functionality to query available Master VM's instead of asking admin to type.
####              v1.3 - 21-10-2019 - CHP: Added logic to intelligently snapshot a Master VM in VMware if the user hasn't 
####                                       performed a manual snapshot.
####              v1.4 - 22-10-2019 - CHP: Added functionality to automatically detect region instead of prompting the admin.                              
##############################################################################################################################
# Create Base Variables Section #
$Regions = "UK","AME","EMEA","APAC"
$Date = Get-Date -Format dd-MM-yyyy
$Log = ('C:\Masters\Scripts\Update-MachineCatalog\Logs\MCS-Update-Log-'+$Date+'.txt')
# Configure Logging #
# Create Timestamp Function for logging #
Function Get-Timestamp{
    Return "[{0:dd-MM-yyyy} {0:HH:mm:ss}]" -f (Get-Date)
}
# Write Basic info to Log #
Write-Output "$(Get-Timestamp)   -   The script has been initiated on: $env:COMPUTERNAME" >> $Log
Write-Output "$(Get-Timestamp)   -   The script is running in the context of: $env:USERNAME" >> $Log
Write-Output "$(Get-Timestamp)   -   Base Variable Decleration:" >> $Log
Write-Output ((Get-Timestamp)+'   -                              $Regions = '+$Regions) >> $Log
Write-Output ((Get-Timestamp)+'   -                              $Date = '+$Date) >> $Log
Write-Output ((Get-Timestamp)+'   -                              $Log = '+$Log) >> $Log
Write-Output "$(Get-Timestamp)   -   The actions completed by this script will be captured below." >> $Log
# Set Base Variables per region Function #
############################### Create Functions for use with whole Script ###############################
# Create Set-BaseVariables Function #
Function Check-VMware{
    $1stAnswer = Read-Host "
Have you carried out a Snapshot of your Master VM via the vSphere Web Console? (y/n)"
    If($1stAnswer -eq "n"){
        $2ndAnswer = Read-Host "
Will you Snapshot the Master VM now? (y/n)"
        If($2ndAnswer -eq "y"){
            $Global:Username = Read-Host "
Please enter your Username to access VMware vCenter"
            $Global:Password = Read-Host "
Please enter your Password to access VMware vCenter" -AsSecureString
            $Global:Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Username,$Password
            Connect-vCenter
            Check-VMSnapshot
        }
        Else{
            Write-Host -ForegroundColor Cyan -Verbose "
$(Get-Date -Format hh:mm:ss)   -   $env:USERNAME has chosen not to snapshot the Master VM via the script. Either choose an existing Snapshot in the upcoming steps or Snapshot the Master VM via vSphere Web Console now."
        }
    }
    Elseif($1stAnswer -eq "y"){
    Write-Host -ForegroundColor Cyan -Verbose "$(Get-Date -Format hh:mm:ss)   -   $env:USERNAME has carried out a snaphot of the Master VM manually via vSphere web console";Write-Output "$(get-Timestamp)   -   $env:USERNAME has carried out a snaphot of the Master VM manually via vSphere web console" >> $Log
    }
}
# Function to execute script #
Function Execute-MachineCatalogUpdate{
    $DCQuery = Get-ADDomainController -Discover | Select HostName
    If($DCQuery.HostName -like "*LON*" -or $DCQuery.HostName -like "*GB*"){
        Write-Host -ForegroundColor Green -Verbose "
$(Get-Date -Format hh:mm:ss)   -   The script has detected that it is running in the United Kingdom";Write-Output "$(Get-Timestamp)   -   The script has detected that it is running in the United Kingdom" >> $Log
        Write-Output "$(Get-Timestamp)   -   Region is set to UK" >> $Log;
        Process-UKRegion
    }
    If($DCQuery.HostName -like "*ESC*" -or $DCQuery.HostName -like "*DE*"){
        Write-Host -ForegroundColor Green "
$(Get-Date -Format hh:mm:ss)   -   The script has detected that it is running in Continental Europe";Write-Output "$(Get-Timestamp)   -   The script has detected that it is running in Continental Europe" >> $Log
        Write-Output "$(Get-Timestamp)   -   Region is set to EMEA" >> $Log;
        Process-EMEARegion
    }
    If($DCQuery.HostName -like "*HK*" -or $DCQuery.HostName -like "*HKG*"){
        Write-Host -ForegroundColor Green "
$(Get-Date -Format hh:mm:ss)   -   The script has detected that it is running in Asia";Write-Output "$(Get-Timestamp)   -   The script has detected that it is running in Asia" >> $Log
        Write-Output "$(Get-Timestamp)   -   Region is set to APAC" >> $Log;
        Process-APACRegion
    }
    If($DCQuery.HostName -like "*US*" -or $DCQuery.HostName -like "*NYC*"){
        Write-Host -ForegroundColor Green "
$(Get-Date -Format hh:mm:ss)   -   The script has detected that it is running in the Americas";Write-Output "$(Get-Timestamp)   -   The script has detected that it is running in the Americas" >> $Log
        Write-Output "$(Get-Timestamp)   -   Region is set to AME" >> $Log;
        Process-AMERegion
    }
}
# Create Set-DDC Function #
Function Set-DDC{
    $Global:ProgressPreference = 'SilentlyContinue'
    $ConnectionTest1 = Test-NetConnection -ComputerName $DDCs[0] -Port 443 | Select ComputerName,TcpTestSucceeded
    $ConnectionTest2 = Test-NetConnection -ComputerName $DDCs[1] -Port 443 | Select ComputerName,TcpTestSucceeded
    If($ConnectionTest1.TcpTestSucceeded -eq $true){
        $Global:AdminAddress = $DDCs[0];Write-Output ((Get-Timestamp)+'   -   The connection to '+$DDCs[0]+' was successful. $AdminAddress = '+$AdminAddress) >> $Log
        $Global:ProgressPreference = 'Continue'
    }
    Elseif($ConnectionTest2.TcpTestSucceeded -eq $true){
        $Global:AdminAddress = $DDCs[1];Write-Output ((Get-Timestamp)+'   -   The connection to '+$DDCs[1]+' was successful, $AdminAddress = '+$AdminAddress) >> $Log
        $Global:ProgressPreference = 'Continue'
    }
    If($AdminAddress -eq $null){
        Write-Host (Get-Date -Format hh:mm:ss)"  -   Could not connect to any of the Delivery Controllers for $SelectedRegion, the script will now Exit!" -ForegroundColor Red -Verbose;;Write-Output "$(Get-Timestamp)   -   Could not connect to any of the Delivery Controllers for $SelectedRegion, the script will now Exit!" >> $Log
        $Global:ProgressPreference = 'Continue'
        Pause
        Exit
    }
}
# Create Check-VMSnapshot Function #
Function Check-VMSnapshot{
    Write-Host -ForegroundColor White -Verbose "
### VMware Section ###"
    Write-Output "$(Get-Timestamp)   -   $env:USERNAME chose to snapshot the Master VM via the script" >> $Log
    $VMs = Get-VM | Where-Object {$_.Name -like "*000" -or $_.Name -like "*XXX*"} | Select Name
    Write-Host -ForegroundColor White -Verbose "
Please choose a Master VM:
"
    For ($i=0; $i -lt $VMs.Count; $i++){
    Write-Host "$($i+1): $($VMs.Name[$i])" -ForegroundColor Yellow -Verbose
    }
    [int]$number = Read-Host "
Press the number to select a VM"
    $Global:MasterVM = $($VMs[$number-1]);Write-Output ((Get-Timestamp)+'   -   '+$env:USERNAME+' selected the following Master VM: '+$MasterVM.Name) >> $Log
    Write-Host -ForegroundColor Cyan -Verbose "
Gathering VM and Snapshot information from vCenter"
    $LatestSnapshot = Get-Snapshot -VM $MasterVM.Name | Select Name,Description | Sort-Object Name -Descending | Select-Object -First 1
    $PriorSnapshot = ($LatestSnapshot.Name).Substring(0,4)
    $MajorVersion = ($LatestSnapshot.Name).Substring(1,1)
    $MinorVersion = ($LatestSnapshot.Name).Substring(3,1)
    If($MinorVersion -eq "9"){
        $MinorVersion = "0"
        $LatestVersion = New-Object -TypeName PSObject
        $Properties = [ordered]@{FullVersion=$PriorSnapshot;MajorVersion=$MajorVersion;MinorVersion=$MinorVersion}
        $LatestVersion | Add-Member -NotePropertyMembers $Properties -TypeName Version
        $versionString = ($LatestVersion.MajorVersion+'.'+$LatestVersion.MinorVersion)
        $Version = [Version]$versionString
        $NewVersion = "{0}.{1}" -f ($Version.Major + 1), $Version.Minor
    }
    Else{
        $LatestVersion = New-Object -TypeName PSObject
        $Properties = [ordered]@{FullVersion=$PriorSnapshot;MajorVersion=$MajorVersion;MinorVersion=$MinorVersion}
        $LatestVersion | Add-Member -NotePropertyMembers $Properties -TypeName Version
        $versionString = ($LatestVersion.MajorVersion+'.'+$LatestVersion.MinorVersion)
        $Version = [Version]$versionString
        $NewVersion = "{0}.{1}" -f $Version.Major, ($Version.Minor + "1")
    }
    $LatestSnapshotString = $LatestSnapshot.Name | Out-String
    $MainString = $LatestSnapshotString.Split(" ",2).Split("-")[1]
    $Answer3 = Read-Host ('
Do you want to enter a name for this Snapshot? The previous Snapshot is: '+$LatestSnapshot.Name+' (y/n)')
    If($Answer3 -eq "y"){
        $NewSnapshotName = Read-Host "Enter a name for the Snapshot"
    }
    Else{
        $NewSnapshotName = ('v'+$NewVersion+' '+$MainString+'- '+$Date)
    }
    $Answer4 = Read-Host "
Do you want to enter a description for this Snapshot? (y/n)"
    If($Answer4 -eq "y"){
        $NewSnapshotDescription = Read-Host ('Enter a description for Snapshot '+$LatestSnapshot.FullVersion)
    }
    Else{
        $NewSnapshotDescription = "Automated Snapshot completed by Update-MachineCatalog script. Initiated by: $env:USERNAME"
    }
    # New VM Snapshot #
    New-Snapshot -VM $MasterVM.Name -Name $NewSnapshotName -Description $NewSnapshotDescription -RunAsync -Confirm:$false | Out-Null
    Write-Host -ForegroundColor Green -Verbose "
$(Get-Date -Format hh:mm:ss)   -   New VM Snapshot created: $NewSnapshotName";Write-Output "$(Get-Timestamp)   -   New Snapshot created: $NewSnapshotName" >> $Log
}
# Create Connect-vCenter Function #
Function Connect-vCenter{
    If($SelectedRegion -eq "UK"){Connect-VIServer "UK vcenter FQDN" -Credential $Credentials;Write-Output "$(Get-Timestamp)   -   $env:USERNAME has succesfully connected to UK vCenter" >> $Log}
    If($SelectedRegion -eq "AME"){Connect-VIServer "AME vcenter FQDN" -Credential $Credentials;Write-Output "$(Get-Timestamp)   -   $env:USERNAME has succesfully connected to AME vCenter" >> $Log}
    If($SelectedRegion -eq "EMEA"){Connect-VIServer "EMEA vcenter FQDN" -Credential $Credentials;Write-Output "$(Get-Timestamp)   -   $env:USERNAME has succesfully connected to EMEA vCenter" >> $Log}
    If($SelectedRegion -eq "APAC"){Connect-VIServer "APAC vcenter FQDN" -Credential $Credentials;Write-Output "$(Get-Timestamp)   -   $env:USERNAME has succesfully connected to APAC vCenter" >> $Log}
}
# Create UK Function #
Function Process-UKRegion{
    $Global:SelectedRegion = "UK"
    Check-VMware
    Write-Host -ForegroundColor Green -Verbose "$(Get-Date -Format hh:mm:ss)   -   Selected Region is: United Kingdom" ;Write-Output "$(Get-Timestamp)   -   Selected Region is: United Kindgom" >> $Log
    $DDCs = "ddc1","ddc2";Write-Output ((Get-Timestamp)+'   -   Specified Delivery Controllers for '+$SelectedRegion+' are: '+$DDCs[0]+' and '+$DDCs[1]) >> $Log
    Set-DDC
    Update-MachineCatalog # Runs the Update-MachineCatalog function #
}
# Create AME Function #
Function Process-AMERegion{
    $Global:SelectedRegion = "AME"
    Check-VMware
    Write-Host -ForegroundColor Green -Verbose "$(Get-Date -Format hh:mm:ss)   -   Selected Region is: Americas" ;Write-Output "$(Get-Timestamp)   -   Selected Region is: Americas" >> $Log
    $DDCs = "ddc1","ddc2";Write-Output ((Get-Timestamp)+'   -   Specified Delivery Controllers for '+$SelectedRegion+' are: '+$DDCs[0]+' and '+$DDCs[1]) >> $Log
    Set-DDC
    Update-MachineCatalog # Runs the Update-MachineCatalog function #
}
# Create EMEA Function #
Function Process-EMEARegion{
    $Global:SelectedRegion = "EMEA"
    Check-VMware
    Write-Host -ForegroundColor Green -Verbose "$(Get-Date -Format hh:mm:ss)   -   Selected Region is: Continental Europe" ;Write-Output "$(Get-Timestamp)   -   Selected Region is: Continental Europe" >> $Log
    $DDCs = "ddc1","ddc2";Write-Output ((Get-Timestamp)+'   -   Specified Delivery Controllers for '+$SelectedRegion+' are: '+$DDCs[0]+' and '+$DDCs[1]) >> $Log
    Set-DDC
    Update-MachineCatalog # Runs the Update-MachineCatalog function #
}
# Create APAC FUnction #
Function Process-APACRegion{
    $Global:SelectedRegion = "APAC"
    Check-VMware
    Write-Host -ForegroundColor Green -Verbose "$(Get-Date -Format hh:mm:ss)   -   Selected Region is: Asia" ;Write-Output "$(Get-Timestamp)   -   Selected Region is: Asia" >> $Log
    $DDCs = "ddc1","ddc2";Write-Output ((Get-Timestamp)+'   -   Specified Delivery Controllers for '+$SelectedRegion+' are: '+$DDCs[0]+' and '+$DDCs[1]) >> $Log
    Set-DDC
    Update-MachineCatalog # Runs the Update-MachineCatalog function #
}
# Create Update Machine Catalog Function #
Function Update-MachineCatalog{
    # Load the Citrix PowerShell modules #
    Write-Host -ForegroundColor White "
### Connection Section ###"
    Write-Host -ForegroundColor Cyan -Verbose "$(Get-Date -Format hh:mm:ss)   -   Loading Citrix PowerShell Modules..." ;Write-Output "$(Get-Timestamp)   -   Loading Citrix PowerShell Modules..." >> $Log
    Add-PSSnapin Citrix*;Write-Output "$(Get-Timestamp)   -   Citrix Snapins have been successfully added" >> $Log
    Write-Host (Get-Date -Format hh:mm:ss)"  -   Creating a PSSession on $AdminAddress" -ForegroundColor Cyan -Verbose;Write-Output "$(Get-Timestamp)   -   Creating a PSSession on $AdminAddress" >> $Log
    $Session = New-PSSession -ComputerName $AdminAddress
    Invoke-Command -Session $Session -ArgumentList $SelectedRegion,$MasterVM -ScriptBlock {asnp Citrix*;$SelectedRegion = $($args[0]);$MasterVM = $($args[1])}
    Write-Host (Get-Date -Format hh:mm:ss)"  -   PSSession has been created successfully on $AdminAddress" -ForegroundColor Green -Verbose;Write-Output "$(Get-Timestamp)   -   PSSession has been created successfully on $AdminAddress" >> $Log
    ############################### Create Functions for use within the Function ###############################
    # Create Select-MasterVM Function #
    Function Select-MasterVM{
        $VMs = Invoke-Command -Session $Session -ScriptBlock {Get-ChildItem ('XDHyp:\HostingUnits\'+$TargetStorageResource.PSChildName) | Where-Object {$_.ObjectType -eq "VM" -and $_.PSChildName -like "*000*" -or $_.PSChildName -like "*XXX*"}};Write-Output ((Get-Timestamp)+'   -   Pulled all Master VM candidates into $VMs variable') >> $Log
        Write-Host -ForegroundColor White -Verbose "
Please choose a Master VM:
        " 
        For ($i=0; $i -lt $VMs.Count; $i++){
            Write-Host "$($i+1): $($VMs.Name[$i])" -ForegroundColor Yellow -Verbose
        }
        [int]$number = Read-Host "
Press the number to select a VM"
        $Global:MasterVM = $($VMs[$number-1])
        Write-Host -ForegroundColor White "
### VM and Snapshot Section ###"
        Write-Host ("$(Get-Date -Format hh:mm:ss)"+'   -   Master VM set to '+$MasterVM.Name) -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   '+$env:USERNAME+' selected '+$MasterVM.Name+' as the Master VM') >> $Log
        Invoke-Command -Session $Session -ArgumentList $MasterVM -ScriptBlock {$MasterVM = $($args[0])};Write-Output ((Get-Timestamp)+'   -   Setting $MasterVM to: '+$MasterVM.Name+' inside PSSession on '+$AdminAddress) >> $Log
        Write-Host ((Get-Date -Format hh:mm:ss)+'   -   MasterVM variable written to '+$AdminAddress+' via PSSession') -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   Variable successfully set to '+$MasterVM.Name+' on $AdminAddress') >> $Log
    }
    # Select Machine Catalog Function #
    Function Select-MachineCatalog{
        $MachineCatalogs = (Get-BrokerCatalog -AdminAddress $AdminAddress).Name;Write-Output ((Get-Timestamp)+'   -   Pulled all Machine Catalogs into $MachineCatalogs variable') >> $Log
        Write-Host -ForegroundColor White -Verbose "
Please choose a Machine Catalog:
        " 
        For ($i=0; $i -lt $MachineCatalogs.Count; $i++){
            Write-Host "$($i+1): $($MachineCatalogs[$i])" -ForegroundColor Yellow -Verbose
        }
        [int]$number = Read-Host "
Press the number to select a Machine Catalog"
        $Global:MachineCatalog = $($MachineCatalogs[$number-1])
        Write-Host -ForegroundColor White "
### Machine Catalog Section ###"
        Write-Host ("$(Get-Date -Format hh:mm:ss)"+'   -   Machine Catalog set to '+$MachineCatalog) -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   '+$env:USERNAME+' selected '+$MachineCatalog+' as the target Machine Catalog') >> $Log
    }
    # Select Storage Resource Function #
    Function Select-StorageResource{
        $StorageResources = Invoke-Command -Session $Session -ScriptBlock{Get-ChildItem "XDHyp:\HostingUnits" | Where-Object {$_.PSChildName -like "*DS"} | Select-Object PSChildName,PSPath};Write-Output ((Get-Timestamp)+'   -   Pulled all Storage Resources into $TargetStorageResources variable') >> $Log
        Write-Host -ForegroundColor White -Verbose "
Please choose a Storage Resource:
        " 
        For ($i=0; $i -lt $StorageResources.Count; $i++){
            Write-Host "$($i+1): $($StorageResources.PSChildName[$i])" -ForegroundColor Yellow -Verbose
        }
        [int]$number = Read-Host "
Press the number to select a Storage Resource"
        $Global:TargetStorageResource = $($StorageResources[$number-1])
        Write-Host -ForegroundColor White "
### Storage Resource Section ###"
        Write-Host ((Get-Date -Format hh:mm:ss)+'   -   TargetStorageResource set to '+$TargetStorageResource.PSChildName) -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   '+$env:USERNAME+' selected '+$TargetStorageResource.PSChildName+' as the Storage Resource') >> $Log
        Invoke-Command -Session $Session -ArgumentList $TargetStorageResource -ScriptBlock {$TargetStorageResource = $($args[0])};Write-Output ((Get-Timestamp)+'   -   Setting $StorageResource to: '+$TargetStorageResource.PSChildName+' inside PSSession on '+$AdminAddress) >> $Log
        Write-Host ((Get-Date -Format hh:mm:ss)+'   -   TargetStorageResource variable written to '+$AdminAddress+' via PSSession') -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   Variable successfully set to '+$TargetStorageResource.PSChildName+' on $AdminAddress') >> $Log
    }
    # Select VM Snapshot #
    Function Select-VMSnapshot{
        $VMSnapshots = Invoke-Command -Session $Session -ScriptBlock {Get-ChildItem $VM.FullPath -Recurse -Include *.snapshot | Select Name,FullName,FullPath};Write-Output ((Get-Timestamp)+'   -   Pulled all VM Snapshots into $VMSnapshots variable') >> $Log
        Write-Host -ForegroundColor White -Verbose "
Please choose a VM Snapshot:
        " 
        For ($i=0; $i -lt $VMSnapshots.Count; $i++){
            Write-Host "$($i+1): $($VMSnapshots.Name[$i])" -ForegroundColor Yellow -Verbose
        }
        [int]$number = Read-Host "
Press the number to select a Snapshot"
        $Global:VMSnapshot = $($VMSnapshots[$number-1])
        Write-Host ("
$(Get-Date -Format hh:mm:ss)"+'   -   VMSnapshot set to '+$VMSnapshot.Name) -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   '+$env:USERNAME+' selected '+$VMSnapshot.Name+' as the VM Snapshot') >> $Log
    }
    # Select Hosting Resource Function #
    Function Select-HostingResource{
        $HostingResources = Invoke-Command -Session $Session -ScriptBlock {Get-ChildItem "XDHyp:\Connections" | Where-Object {$_.HypervisorConnectionName -like "*$SelectedRegion*"} | Select-Object HypervisorConnectionName,HypervisorConnectionUid};Write-Output ((Get-Timestamp)+'   -   Pulled all Hosting Resources into $TargetHostingResources variable') >> $Log
        If($HostingResources.Count -gt "1"){
            Write-Host -ForegroundColor White -Verbose "
Please choose a Hosting Resource:
            " 
            For ($i=0; $i -lt $HostingResources.Count; $i++){
                Write-Host "$($i+1): $($HostingResources.HypervisorConnectionName[$i])" -ForegroundColor Yellow -Verbose
            }
            [int]$number = Read-Host "
Press the number to select a Hosting Resource"
            $Global:TargetHostingResource = $($HostingResources[$number-1])
            Write-Host -ForegroundColor White "
### Hosting Resource Section ###"
            Write-Host ((Get-Date -Format hh:mm:ss)+'   -   TargetHostingResource set to '+$TargetHostingResource.HypervisorConnectionName) -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   '+$env:USERNAME+' selected '+$TargetHostingResource.HypervisorConnectionName+' as the Hosting Resource') >> $Log
            Invoke-Command -Session $Session -ArgumentList $TargetHostingResource -ScriptBlock {$TargetHostingResource = $($args[0])};Write-Output ((Get-Timestamp)+'   -   Setting $HostingResource to: '+$TargetHostingResource.HypervisorConnectionName+' inside PSSession on '+$AdminAddress) >> $Log
            Write-Host ((Get-Date -Format hh:mm:ss)+'   -   TargetHostingResource variable written to '+$AdminAddress+' via PSSession') -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   Variable successfully set to '+$TargetHostingResource.HypervisorConnectionName+' on '+$AdminAddress) >> $Log
        }
        Else{
            $Global:TargetHostingResource = $HostingResources[0]
            Write-Host ((Get-Date -Format hh:mm:ss)+'   -   TargetHostingResource set to '+$TargetHostingResource.HypervisorConnectionName+' automatically as it was the only option') -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   $HostingResource automatically set to '+$TargetHostingResource.HypervisorConnectionName+' as it was the only option') >> $Log
            Invoke-Command -Session $Session -ArgumentList $TargetHostingResource -ScriptBlock {$TargetHostingResource = $($args[0])};Write-Output ((Get-Timestamp)+'   -   Setting $HostingResource to: '+$TargetHostingResource.HypervisorConnectionName+' inside PSSession on '+$AdminAddress) >> $Log
            Write-Host ((Get-Date -Format hh:mm:ss)+'   -   TargetHostingResource variable written to '+$AdminAddress+' via PSSession') -ForegroundColor Green -Verbose;Write-Output ((Get-Timestamp)+'   -   Variable successfully set to '+$TargetHostingResource.HypervisorConnectionName+' on '+$AdminAddress) >> $Log
        }
    }
    ############################### Resource Assignment ###############################
    # Target infrastructure #
    Write-Output "$(Get-Timestamp)   -   The selected AdminAddress is: $AdminAddress, this will be used when executing commands against Citrix infrastructure" >> $Log # The XD Controller we're going to execute against #
    # Master image properties #
    Select-MachineCatalog # Retrieve Machine Catalog #
    # Hypervisor and storage resources #
    Select-HostingResource; # Retrieve hosting resource #
    Select-StorageResource; # Retrieve Storage resource #
    # Get information from the hosting environment via the XD Controller #
    # Get the storage resource #
    Write-Host -ForegroundColor White "
### Infrastructure Section ###"
    Write-Host -ForegroundColor Cyan -Verbose "$(Get-Date -Format hh:mm:ss)   -   Gathering storage and hypervisor connections from the Virtual Apps and Desktops infrastructure" ;Write-Output "$(Get-Timestamp)   -   Gathering storage and hypervisor connections from the Virtual Apps and Desktops infrastructure" >> $Log
    $HostingUnit = $TargetStorageResource;Write-Output ((Get-Timestamp)+'   -   Set $HostingUnit variable using information from $StorageResource') >> $Log
    # Get the hypervisor management resources #
    $HostConnection = $TargetHostingResource;Write-Output ((Get-Timestamp)+'   -   Set $HostingConnection variable using information from $HostingResource. The script only needs $HostConnection.HypervisorConnectionUid which is: '+$TargetHostingResource.HypervisorConnectionUid) >> $Log
    # Get the broker connection to the hypervisor management #
    $BrokerHypConnection = Get-BrokerHypervisorConnection -AdminAddress $AdminAddress -HypHypervisorConnectionUid $HostConnection.HypervisorConnectionUid;Write-Output "$(Get-Timestamp)   -   Connecting to Hypervisor Management via Broker Connection" >> $Log
    # Set a provisioning scheme for the update process #
    $ProvScheme = Set-ProvSchemeMetadata -AdminAddress $AdminAddress -Name 'ImageManagementPrep_DoImagePreparation' -ProvisioningSchemeName $MachineCatalog -Value 'True';Write-Output "$(Get-Timestamp)   -   Setting Provisioning Scheme for Machine Catalog update" >> $Log
    # Get the master VM image from the same storage resource we're going to deploy to. Could pull this from another storage resource available to the host #
    #Select-MasterVM
    If($MasterVM -eq $null){
        Select-MasterVM
        $VM = Invoke-Command -Session $Session -ScriptBlock {Get-ChildItem ('XDHyp:\HostingUnits\'+$TargetStorageResource.PSChildName) | Where-Object {$_.ObjectType -eq "VM" -and $_.PSChildName -eq $MasterVM}};Write-Output ((Get-Timestamp)+'   -   Pulled all Master VM candidates into $VMs variable') >> $Log
    }
    Else{
        $VM = Invoke-Command -Session $Session -ScriptBlock {Get-ChildItem ('XDHyp:\HostingUnits\'+$TargetStorageResource.PSChildName) | Where-Object {$_.ObjectType -eq "VM" -and $_.PSChildName -eq ($MasterVM.Name+'.vm')}};Write-Output ((Get-Timestamp)+'   -   Pulled all Master VM candidates into $VMs variable') >> $Log
    }
    Write-Host -ForegroundColor Cyan -Verbose ("$(Get-Date -Format hh:mm:ss)"+'   -   Getting Snapshot Details for '+$MasterVM.Name);Write-Output ((Get-Timestamp)+'   -   Getting Snapshot Details for '+$MasterVM.Name) >> $Log
    Invoke-Command -Session $Session -ArgumentList $VM -ScriptBlock {$VM = $($args[0])};Write-Output ((Get-Timestamp)+'   -   $VM set to: '+$VM.Name+' on '+$AdminAddress) >> $Log
    # Get the snapshot details. This code will grab the newest entry in the list #
    Select-VMSnapshot
    # Publish the image update to the machine catalog #
    $Answer = Read-Host "
Are you sure you want to continue? Continuing will update your Machine Catalog: $MachineCatalog (y/n)"
    If($Answer -eq "y"){
        $PubTask = Publish-ProvMasterVmImage -AdminAddress $adminAddress -MasterImageVM $VMSnapshot.FullPath -ProvisioningSchemeName $MachineCatalog -RunAsynchronously;Write-Output ((Get-Timestamp)+'   -   Start processing the Provisioning Scheme to update Machine Catalog: '+$MachineCatalog+' to Snapshot: '+$VMSnapshot.Name) >> $Log
        $provTask = Get-ProvTask -AdminAddress $adminAddress -TaskId $PubTask
        # Track progress of the image update #
        Write-Host -ForegroundColor Cyan -Verbose "
$(Get-Date -Format hh:mm:ss)   -   Tracking progress of the machine creation task" ;Write-Output "$(Get-Timestamp)   -   Tracking progress of update task" >> $Log
        $totalPercent = 0
        While ($provTask.Active -eq $True){
            Try
            { 
                $totalPercent = If($provTask.TaskProgress)
                {
                    $provTask.TaskProgress
                } 
                Else
                {
                    0
                } 
            }
            Catch
                {
                }
            Write-Progress -Activity "Provisioning image update" -Status "$totalPercent% Complete:" -percentcomplete $totalPercent;Write-Output "$(Get-Timestamp)   -   Provisioning image update is $totalpercent% Complete" >> $Log
            Sleep 15
            $provTask = Get-ProvTask -AdminAddress $adminAddress -TaskId $PubTask
        }
        Write-Host "
$(Get-Date -Format hh:mm:ss)  -   Machine Catalog update task completed for $MachineCatalog" -ForegroundColor Green -Verbose;Write-Output "$(Get-Timestamp)   -   Machine Catalog update task 100% complete for $MachineCatalog" >> $Log
    }
    Elseif($Answer -eq "n"){
        Write-Host -ForegroundColor Red "$env:USERNAME typed no, script is exiting";Write-Output "$(Get-Timestamp)   -   $env:USERNAME typed no, script is existing" >> $Log
        Exit
    }
}   
# Create Build-Email Function # 
Function Build-Email{
    # Build Email #
    Write-Output "$(Get-Timestamp)   -   Setting Variables for Email:" >> $Log
    $NoVMs = Get-BrokerCatalog $MachineCatalog | Select-Object AvailableCount;Write-Output ((Get-Timestamp)+'   -                                $NoVMs = '+$NoVMs.AvailableCount) >> $Log
    $Global:Recipient = "Recipient Email Address";Write-Output ((Get-Timestamp)+'   -                                $Recipient = '+$Recipient) >> $Log
    $Global:Sender = ('VAD_'+$SelectedRegion+'@cliffordchance.com');Write-Output ((Get-Timestamp)+'   -                                $Sender = '+$Sender) >> $Log
    $Global:SMTP = "0.0.0.0";Write-Output ((Get-Timestamp)+'   -                                $SMTP = '+$SMTP) >> $Log
    $Global:Attachment = $Log
    $Global:Subject = ('The following Machine Catalog has been updated: '+$MachineCatalog+' on '+$Date)
    $Global:Body = 
        (
'To Administrator,

The automated Machine Catalog update is complete. Please see the details below:

Administrator: '+$env:USERNAME+'
Date: '+$Date+'
Machine Catalog: '+$MachineCatalog+'
Snapshot: '+$VMSnapshot.Name+'
No of VMs pending reboot: '+$NoVMs.AvailableCount+'

All VMs in the Machine Catalog need to be rebooted for this update to take effect, please carry this out manually or ensure the machines are party to a Delivery Group with a nightly reboot schedule.

Attached, please find the log file from this process.

PLEASE DO NOT REPLY TO THIS EMAIL.

Regards,
EUC Engineering')
}
# Execute Script Processes #
Execute-MachineCatalogUpdate
# Send Email to Administrators #
Build-Email
Write-Output ((Get-Timestamp)+'   -   Script Complete, sending Email to '+$Recipient) >> $Log
Send-MailMessage -To $Recipient -From $Sender -Subject $Subject -Body $Body -Attachments $Attachment -SmtpServer $SMTP
Exit   
# End #