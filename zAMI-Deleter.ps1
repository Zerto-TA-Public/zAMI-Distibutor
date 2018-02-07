########################################################################################
# zAMI-Deleter.ps1
#
# Written by Justin Paul, Zerto Tech Alliances Architect, jp@zerto.com
#
# Verion: 1.0 (2018-02-05)
#
# Overview:
# This script reads a list of AMI IDs from a CSV file and unregisters the AMIs from
# the proper region.
#
# Assumptions:
# you must have a csv input file in the proper format 
#
# Usage:
# .\zAMI-Deleter.ps1 InputFile.csv
#
# Output:
# Console output showing which AMIs were deleted will be displayed
#
########################################################################################

# Startup Variables
$awsAccessKey = ""
$awsSecretKey = ""



############################## Start of Script ##########################################
# make sure the user entered a csv arguement
$path = $args[0]

if (!$path){
    Write-Host "Command Arguement required!"
    Write-Host ".\zAMI-Deleter.ps1 InputFile.csv"
    exit
}


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

Set-AWSCredential -AccessKey $awsAccessKey -SecretKey $awsSecretKey -StoreAs zAMIDeleter

# Set the given credentials as the in-use profile and set default region to source region
Set-AWSCredential -profileName zAMIDeleter


#Import records to array
$InputAMIs = import-csv $path


# Delete all AMIs that were in the input file
foreach ($record in $InputAMIs)
{
    $tempRegion = $record.Region
    $tempAMI = $record.Result
    write-host "Unregistering: $tempRegion = $tempAMI"
    Unregister-EC2Image -ImageId $tempAMI -Region $tempRegion -Force
}


Remove-AWSCredentialProfile -ProfileName zAMIDeleter