# author Kendall Conner 12:27 PM 10/17/2018
# maintianer Matt Allen-Goebel
# Version history
# updated 2:11 PM 2/20/2021
# forked 															09/10/2024	malgoebel	v.1.1
# added 2k22 server variables										09/10/2024	malgoebel	v.1.11
# updated gateway object 											09/11/2024	malgoebel	v.1.12
# major refactor to simplify management of commands					09/12/2024	malgoebel	v.2.0
# added validation step												09/13/2024	malgoebel	v.2.1
# machine counts reworked											09/20/2024	malgoebel	v.2.11
# added Logs path to transcript										09/20/2024	malgoebel	v.2.12
# added log rotation && garbage collection							09/20/2024	malgoebel	v.2.2
# added design goals section										09/20/2024	malgoebel	v.2.21
# backed out log rotation											09/21/2024	malgoebel	v.2.211
# Log rotation added back in										09/23/2024	malgoebel	v.2.22
# Refactor - Nested Loops to handle multiple domains        	    09/25/2024	malgoebel	v.2.7
# Removing Computergroups and the for loops requiring them			09/30/2024	malgoebel	v.2.8
# Changing $gateway var to being discovered instead of Set			10/02/2024	malgoebel	v.2.85
# Full Self Discovery with variable placement instead of hardcode	10/02/2024	malgoebel	v.2.95

# Design Goals:
# This script should on a defined schedule go out and collect new vms/hosts/clusters and add delegate 
# access. Logging is available for tracking assets as they come online and are retired. A script to 
# compare log files for changes and email a report of those changes will need to be developed. A script
# is being utilized for the purpose of gathering new assets and adding them to the shared configuration
# on the front end for management. 

# Maybe Future Plans: 
# A major refactor process for this script to merge with the asset collection script since they utilized 
# many of the same variables. Various log files will need to be worked out, one for delegations success
# one for delegation failures, one uber file for assets being added to WAC console, one for the failures
# to add. 

# Additional Instructions:
# file should live in c:\nt\code\wac-delegation.ps1
# may need to start powershell as another user [start powershell -credential ""] then close parent powershell window

# Set Logging Path
$logDirectory = "C:\nt\code\Logs\delegation\"
$logFileName = "wac-delegation_{0}.log" -f (Get-Date -Format "yyyyMMddhhmmss")
# Create the log directory if it doesn't exist
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory
}
# Define the full path to the log file
$logFilePath = Join-Path -Path $logDirectory -ChildPath $logFileName

#Open Logs
start-transcript -path $logFilePath -IncludeInvocationHeader

# Example manual delegation
# $gateway = "jvtadm00101"
# $node = "vmhnp00101"
# $gatewayObject = Get-ADComputer -Identity $gateway
# $nodeObject = Get-ADComputer -Identity $node
# Set-ADComputer -Identity $nodeObject -PrincipalsAllowedToDelegateToAccount $gatewayObject

# Self Discover the gateway and its AD object
$gateway = $env:COMPUTERNAME
$gatewayObject = Get-ADComputer -Identity $gateway
$DomainName = (Get-WmiObject Win32_ComputerSystem).Domain
$property = Get-ADComputer -Identity $gateway -Server $DomainName | Select-Object -ExpandProperty DistinguishedName

# Note which domain is being operated against
Write-Output "Working on $DomainName Hosts"

# Define the group objects to work on
$Computer = (Get-ADComputer -Server $DomainName -Filter 'OperatingSystem -NotLike "*Server 2008*"' | Sort-Object Name).Name | Select-String -Pattern "jb|jv"
# Note which Group and domain
Write-Output "Computers in $DomainName = "($Computer).Count

# Loop on the items in Computers
foreach ( $item in $Computer ) {

    # Test connection 
    if ( Test-Connection -ComputerName $item -Count 1 -Quiet ) {
		Write-Output "Connected to $item in $DomainName"

		# Define  single item to work on
		$nodeObject = (Get-ADComputer -Identity "$item" -Server $DomainName) 

	    # Examine Object Value for exception
	    $value = (Get-ADComputer -Identity $nodeObject -Properties * | Select-Object -ExpandProperty PrincipalsAllowedToDelegateToAccount)

		    # If value is equal to gateway, drop item and move forward
   	    	if ($value -eq $property) {
                Write-Host "$nodeObject already set"

    		} else {
				# Else write delegation 
				Set-ADComputer -Identity $nodeObject -PrincipalsAllowedToDelegateToAccount $gatewayObject
		    }
	} else {
			
	    # No connection available - skip to next computer. 
        Write-Output "Failed to connect to $item in $DomainName. Skipping . . . "    
    }
}

#Get the Host Server Names
$jbhvmhosts = (Get-SCVMHost -VMMServer "scvmmconsole.$DomainName" | Sort-Object ComputerName).ComputerName
Write-Output "jbhvmhosts in $DomainName = "($jbhvmhosts).Count

# Set the Static Domain
$domain = "JBH01"

# Loop through each Host Server
foreach ( $item in $jbhvmhosts ) {

	# Test Connection
	if ( Test-Connection -ComputerName $item -Count 1 -Quiet ) {

		# Get Identity
		$nodeObject = (Get-ADComputer -Identity "$item" -Server $domain) 

        # Pull Value of Delegate
        $value = (Get-ADComputer -Identity $nodeObject -Properties * | Select-Object -ExpandProperty PrincipalsAllowedToDelegateToAccount)

			#Test Value
            if ($value -eq $property) {

                # Skip if already set
                Write-Host "$nodeObject already set"
            } else {

                # Set Value
                Set-ADComputer -Identity $nodeObject -PrincipalsAllowedToDelegateToAccount $gatewayObject
            }
	} else {
		# Skip if no Connection
		Write-Output "Failed to connect to $item in $domain. Skipping . . . "    
	}
}

#Get the Cluster Server Names
$jbhvmhostcluster = (Get-SCVMHostCluster -VMMServer "scvmmconsole.$DomainName" | Sort-Object Name).ClusterName
Write-Output "jbhvmhostclusters in $DomainName = "($jbhvmhostcluster).Count

# Loop through each Cluster Server
foreach ( $item in $jbhvmhostcluster ) {

    # Test Connection
    if ( Test-Connection -ComputerName $item -Count 1 -Quiet ) {

		# Get the Object Identity
		$nodeObject = (Get-ADComputer -Identity "$item" -Server $domain) 

        # Set the Delegation Value
        $value = (Get-ADComputer -Identity $nodeObject -Properties * | Select-Object -ExpandProperty PrincipalsAllowedToDelegateToAccount)

            # Test Delegation Value
            if ($value -eq $property) {

                # Skip if already set
                Write-Host "$nodeObject already set"
            } else {

                # Set the Delegate
                Set-ADComputer -Identity $nodeObject -PrincipalsAllowedToDelegateToAccount $gatewayObject
            }
	} else {

        # Skip if Connection Test Fails
        Write-Output "Failed to connect to $item in $domain. Skipping . . . "    
	}
}

stop-transcript

# Rotate logs: Keep only the last 7 log files
$files = Get-ChildItem -Path $logDirectory -Filter "wac-delegation_*.log" | Sort-Object LastWriteTime -Descending
$filesToKeep = $files | Select-Object -First 7
$filesToDelete = $files | Where-Object { $_ -notin $filesToKeep }
foreach ($file in $filesToDelete) {
    Remove-Item -Path $file.FullName -Force
}

# end