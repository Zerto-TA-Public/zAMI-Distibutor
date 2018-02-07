########################################################################################
# zAMI-Deployer.ps1
#
# Written by Justin Paul, Zerto Tech Alliances Architect, jp@zerto.com
#
# Verion: 1.0 (2018-02-05)
#
# Overview:
# This script takes a given AMI image and distributes it to all AWS regions so that
# 3rd Party AWS accounts and deploy it just like a normal marketplace offering.
#
# Assumptions:
# It is assumed that the source AMI will be located in the Northern Virgina AWS Region
# us-east-1. 
#
# Usage:
# .\zAMI-Deployer.ps1
#
# Output:
# A CSV file containing a list of all of the AMIs created during this process will be
# saved to the directory where the script is ran from.
#
########################################################################################

# Startup Variables
$sourceRegion = "us-east-1"
$awsAccessKey = ""
$awsSecretKey = ""
$SourceAMIName = ""


############################## Start of Script ##########################################

# Stop script if error
$ErrorActionPreference = "Stop" # "Continue" switching to continue is handy for debug purposes.

# Load the AWS Powershell Module
Import-Module AWSPowerShell
Write-Host "AWS Powershell cmdlets Imported"

#if user has not specified their key already ask for it
if (!$awsAccessKey -and !$awsSecretKey)
{ 
    # Get AWS Access key information and set it as a profile
    $awsAccessKey = Read-Host 'Paste your AWS Access Key'
    $awsSecretKey = Read-Host 'Paste your AWS Secret Key'
}

Set-AWSCredential -AccessKey $awsAccessKey -SecretKey $awsSecretKey -StoreAs zAMIDeployer

# Set the given credentials as the in-use profile and set default region to source region
Set-AWSCredential -profileName zAMIDeployer
Set-DefaultAWSRegion -Region $sourceRegion

# Test Credentials If credentials are invalid this wil fail and stop script
Get-EC2Image -owner self | Out-Null


#if user has not specified their key already ask for it
if (!$SourceAMIName)
{ 
    # Get AWS source AMI name from user 
    $temp = Read-Host 'Paste the source AMI name, it should look like "ami-xxxxxxxx"'
    $sourceAMI = New-Object -TypeName PSObject
    $sourceAMI | Add-Member -MemberType NoteProperty -Name Name -Value $temp
} else {
    #if AMI name was specified in variables use that instead
    $sourceAMI = New-Object -TypeName PSObject
    $sourceAMI | Add-Member -MemberType NoteProperty -Name Name -Value $SourceAMIName
}

Write-Host "Looking for $sourceAMI"

# Check to see if that AMI exists in region
$found = 0
$temp = $sourceAMI.Name
$MyAMIs = Get-EC2Image -owner self
foreach ( $ami in $MyAMIs ) 
{ 
    if ($ami.ImageId -eq $temp)
    {
        $found = 1
        $sourceAMI | Add-Member -MemberType NoteProperty -Name FullName -Value $ami.Name -Force
        $sourceAMI | Add-Member -MemberType NoteProperty -Name Description -Value $ami.Description -Force
    }
}
if ($found -ne "1")
{
    Write-Host "That AMI was not found in this region"
    #exit
}

# Make Sure Source is ready
$newStatus = (Get-Ec2Image -ImageId $sourceAMI.Name -Region $sourceRegion).State
if ($newStatus -ne "available")
{
    Write-Host "The Source AMI is not in the "available" state. Re-run the script once it is."
    exit
}


Write-Host "Found your AMI, starting clone process to other regions"
Write-Host "Details of Image"
Write-Host $sourceAMI.FullName
Write-Host $sourceAMI.Description

# find all current AWS Regions
$regions = Get-AWSRegion
$AWSRegions = New-Object System.Collections.ArrayList
foreach($rg in $regions)
{
    if ($rg.region -ne $sourceRegion)
    {
        $AWSRegions.Add($rg.region) > null
    }
}
Write-Host "Clone AMIs will be created in the following regions"
Write-Host $AWSRegions

#Copy Source AMI to all other regions and save their AMI numbers
$cloneAMIs = @()

foreach ($region in $AWSRegions) 
{
    $newAMI = Copy-EC2Image -SourceImage $sourceAMI.Name -SourceRegion $sourceRegion -Description $sourceAMI.Description -Region $region
    Write-Host "Created $newAMI in $region"
    $cloneAMIs += New-Object psobject -Property @{
        Region = $region
        Result = $newAMI
        Public = $False
        Available = $False
    }  
}

# Check to make sure all AMIs are "Available" before proceeding
$AMIsNotReady = $True
While ($AMIsNotReady)
{
    foreach ($record in $cloneAMIs)
    {
        $tempRegion = $record.Region
        $tempAMI = $record.Result
        $tempPublic = $record.Public
        $tempStatus = $record.Available
        $newStatus = (Get-Ec2Image -ImageId $tempAMI -Region $tempRegion).State
        if ($newStatus -eq "available")
        {
            $record.Available = $True
        }
        write-host "Region: $tempRegion = $tempAMI Is public? $tempPublic Is Available? $tempStatus"
    }
    # If all regions = available proceed
    if (($CloneAMIs.Available) -contains $false){
        $AMIsNotReady = $True
        Write-Host "All AMIs were not ready, Waiting for 1 minute, then rechecking..."
        sleep 60
    } else {
        Write-Host "All AMIs are ready to make public!"
        $AMIsNotReady = $False
    }
}


#Check if Source AMI is public, make it public if it is not
$temp = Get-EC2ImageAttribute -ImageId $sourceAMI.Name -attribute launchPermission
$temp = $temp.LaunchPermissions
$temp = $temp.Group
if ($temp -ne "all")
{
    Write-Host "Making Source AMI Public"
    
    # Set Source Image Public
    Edit-EC2ImageAttribute -ImageId $sourceAMI.Name -Attribute launchPermission -OperationType add -UserGroup all
} Else {
    Write-Host "Source AMI was already Public"
}

# Make all new AMIs Public
foreach ($region in $cloneAMIs)
{
    $tempRegion = $region.Region
    $tempAMI = $region.Result
    $temp = Get-EC2ImageAttribute -ImageId $tempAMI -attribute launchPermission -region $tempRegion
    $temp = $temp.LaunchPermissions
    $temp = $temp.Group
    if ($temp -ne "all")
    {
        Write-Host "Making $tempAMI Public in $tempRegion"
        # Set Source Image Public
        Edit-EC2ImageAttribute -region $tempRegion -ImageId $tempAMI -Attribute launchPermission -OperationType add -UserGroup all
        $region.Public = $True
    } Else {
        Write-Host "Source AMI was already Public"
    }
}

#Add Source Region AMI to full list
$obj = New-Object -TypeName PSObject
$obj | Add-Member -MemberType NoteProperty -Name Region -Value $sourceRegion
$obj | Add-Member -MemberType NoteProperty -Name Result -Value $sourceAMI.Name
$obj | Add-Member -MemberType NoteProperty -Name Public -value $True
$obj | Add-Member -MemberType NoteProperty -Name Available -value $True
			
$CloneAMIs += $obj

Write-Host "Final List of ZCA AMI Images"
$CloneAMIs

#Create AMI Log File with all Regions with Corrisponding AMI ID so it can be used for delete script later
Write-Host "Saving List to CSV"
$CloneAMIs | Export-Csv 'zAMIs.csv'





Remove-AWSCredentialProfile -ProfileName zAMIDeployer