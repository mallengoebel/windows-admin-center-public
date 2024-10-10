# this script is to collect, from AD and VMM, the Windows Servers list and clusters list
# the lists can be imported into Windows Admin Center, under 'shared' connections
# created 2/23/2021 by Kendall Conner
# maintainer - Matt Allen-Goebel 
# forked and renamed													09/20/2024	malgoebel	v.1.1
# added 2k22Servers vars												09/20/2024	malgoebel	v.1.11
# added under construction section										09/20/2024	malgoebel	v.1.12
# adding logging and content variables/path validation and creation		09/26/2024	malgoebel	v.1.2
# refactor to append to one uber content file 							09/26/2024	malgoebel	v.2.0
# update to CSV file format and headings structure						09/26/2024	malgoebel	v.2.01
# breaking out logging path to separate from delagation task logs		10/01/2024	malgoebel	v.2.11
# adding clusters and vmhosts sections									10/01/2024	malgoebel	v.2.51
# adding opening content csv file with headers							10/01/2024	malgoebel	v.2.61
# log file garbage collection sections									10/01/2024	malgoebel	v.2.71
# Removed under construction sections									10/01/2024	malgoebel	v.2.75
# Added try/catch block to retry content additions/avoid stream error	10/02/2024	malgoebel	v.2.81
# removed redundant variables 											10/02/2024	malgoebel	v.2.85
# adding import task section with new logging (renewed vars)			10/02/2024	malgoebel	v.2.95
# Forking and creating domain specific instance							10/03/2024	malgoebel	v.3.0
# adding VM Host discovery and tagging									10/04/2024	malgoebel	v.3.11
# common Error Handling for tagging										10/08/2024	malgoebel	v.3.51



# Global Vars
$DomainName = (Get-WmiObject Win32_ComputerSystem).Domain
$WacUrl = "https://wac.$DomainName"

# Content Vars
$contentDirectory = "C:\nt\code\Content\"
$contentFileName = "wac-HostsList.csv"

# Logging Vars
$logDirectory = "C:\nt\code\Logs\build\"
$logFileName = "wac-build-csv_{0}.log" -f (Get-Date -Format "yyyyMMddhhmmss")

# Create the log directory if it doesn't exist
Write-Output "Creating Log Path if non-existant"
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory
}

#Create the content directory if it doesn't exist
Write-Output "Creating Content Path if non-existent"
if (-not (Test-Path -Path $contentDirectory)) {
    New-Item -ItemType Directory -Path $contentDirectory
}

# Define the full path to the log and log files
$logFilePath = Join-Path -Path $logDirectory -ChildPath $logFileName
$contentFilePath = Join-Path -Path $contentDirectory -ChildPath $contentFileName

# Write a log entry
$logEntry = "{0} - Opening the log. This log is for tracking failures to connect. " -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Add-Content -Path $logFilePath -Value $logEntry


# Garbage Collection 
Write-Output "Garbage Collection from $contentDirectory"
Remove-Item -path $contentDirectory\*.*

# Open New Content file
$contentEntry = '"name","type","tags","groupId"'
Add-Content -Path $contentFilePath -Value $contentEntry

# Note which domain is being operated against
$logEntry = "{0} - Working on $DomainName Hosts" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Add-Content -Path $logFilePath -Value $logEntry
Write-Host "Working on $DomainName Hosts"
	
# Define the group objects to work on
$Computer = (Get-ADComputer -Server $DomainName -Filter 'OperatingSystem -NotLike "*Server 2008*"' | Sort-Object Name).Name | findstr /i "jbv jvl jvd jvt jvp"
    
# Note which Group and domain
$Count = ($Computer).Count
$logEntry = "{0} - Total Computers on $DomainName : $Count" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Add-Content -Path $logFilePath -Value $logEntry

# Loop on the items in Computers
foreach ($item in $Computer) {
    if (Test-Connection -ComputerName $item -Count 1 -Quiet) {
        if (Test-NetConnection -ComputerName $item -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue) {
            $logEntry = "{0} - ${item} has passed an SSH open port check. This is likely a Linux Server. Skipping." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Add-Content -Path $logFilePath -Value $logEntry
        } else {
            $vmhostname = $null
            try {
                if (Invoke-Command -ComputerName $item { Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters" }) {
                    $vmhostname = Invoke-Command -ComputerName $item {
                        Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters" | Select-Object -ExpandProperty PhysicalHostName
                    }
                } else {
                    # Non-fatal error: Continue processing as if successful
                    $vmhostname = "Google"
                }
            } catch {
                # Fatal error: Log and skip to the next item
                $logEntry = "{0} - ${item} encountered a fatal error: $_.Exception.Message. Skipping to next item." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                Add-Content -Path $logFilePath -Value $logEntry
                continue
            }

            Write-Host "VM Host Name: $vmhostname"
            Write-Host $item
            $contentEntry = '"{0}","msft.sme.connection-type.server","{1}","global"' -f $item, $vmhostname
            Add-Content -Path $contentFilePath -Value $contentEntry -ErrorAction Stop
        }
    } else {
        $logEntry = "{0} - $item failed to connect." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $logFilePath -Value $logEntry
    }
}

# Get the Cluster Server Names
$jbhvmhostcluster = (Get-SCVMHostCluster -VMMServer "scvmmconsole.$DomainName" | Sort-Object Name).ClusterName
Write-Output "Clusters in ${DomainName}: $($jbhvmhostcluster.Count)"

# Set the Static Domain
$domain = "JBH01"

# Function to test connection and log results
function Test-ConnectionAndLog {
    param (
        [string]$computerName,
        [string]$connectionType
    )

    if (Test-Connection -ComputerName $computerName -Count 1 -Quiet) {
        $contentEntry = '"{0}","msft.sme.connection-type.{1}",,"global"' -f $computerName, $connectionType
        Add-Content -Path $contentFilePath -Value $contentEntry
    } else {
        $logEntry = "{0} - $computerName Failed to connect in $domain. Skipping . . . " -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $logFilePath -Value $logEntry
    }
}

# Loop through each Cluster Server
foreach ($item in $jbhvmhostcluster) {
    Test-ConnectionAndLog -computerName $item -connectionType "cluster"
}

# Get the Host Server Names
$jbhvmhosts = (Get-SCVMHost -VMMServer "scvmmconsole.$DomainName" | Sort-Object ComputerName).ComputerName
Write-Output "VM Hosts in ${DomainName}: $($jbhvmhosts.Count)"

# Loop through each Host Server
foreach ($item in $jbhvmhosts) {
    Test-ConnectionAndLog -computerName $item -connectionType "server"
}

# Log file Garbage Collection
# Rotate logs: Keep only the last 7 log files
$files = Get-ChildItem -Path $logDirectory -Filter "wac-build-csv_*.log" | Sort-Object LastWriteTime -Descending
$filesToKeep = $files | Select-Object -First 7
$filesToDelete = $files | Where-Object { $_ -notin $filesToKeep }
foreach ($file in $filesToDelete) {
    Remove-Item -Path $file.FullName -Force
}

# Import task section

# Renewing Logging Vars
$logDirectory = "C:\nt\code\Logs\Import\"
$logFileName = "wac-import_{0}.log" -f (Get-Date -Format "yyyyMMddhhmmss")

# Create the log directory if it doesn't exist
Write-Output "Creating Log Path if non-existant"
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory
}
# Define the full path to the log and log files
$logFilePath = Join-Path -Path $logDirectory -ChildPath $logFileName

#Open the log
start-transcript -path $logFilePath -IncludeInvocationHeader

#Check variables
Write-Output "Domain Name of Host:" $DomainName
Write-Output "Target URL of import task:" $WacUrl

# Import powershell module for commands
Write-Output "Importing PowerShell ConnectionTools Module"
Import-Module "$env:ProgramFiles\windows admin center\PowerShell\Modules\ConnectionTools"

# Do the import task.
# Import connections (including tags) from a .csv file
Write-Output "Importing" $contentFilePath 
Import-Connection -GatewayEndpoint $WacUrl -FileName $contentFilePath -Prune

Write-Output "Task Completed"

stop-transcript

# Rotate logs: Keep only the last 7 log files
$files = Get-ChildItem -Path $logDirectory -Filter "wac-import_*.log" | Sort-Object LastWriteTime -Descending
$filesToKeep = $files | Select-Object -First 7
$filesToDelete = $files | Where-Object { $_ -notin $filesToKeep }
foreach ($file in $filesToDelete) {
    Remove-Item -Path $file.FullName -Force
}
#end