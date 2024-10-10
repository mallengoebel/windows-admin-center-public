# author Kendall Conner 12:27 PM 10/17/2018
# maintianer Matt Allen-Goebel

# Set Logging Path
$logDirectory = "C:\path\to\Logs\delegation\"
$logFileName = "wac-delegation_{0}.log" -f (Get-Date -Format "yyyyMMddhhmmss")
# Create the log directory if it doesn't exist
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory
}
# Define the full path to the log file
$logFilePath = Join-Path -Path $logDirectory -ChildPath $logFileName

#Open Logs
start-transcript -path $logFilePath -IncludeInvocationHeader

# Self Discover the gateway and its AD object
$gateway = $env:COMPUTERNAME
$gatewayObject = Get-ADComputer -Identity $gateway
$DomainName = (Get-WmiObject Win32_ComputerSystem).Domain
$property = Get-ADComputer -Identity $gateway -Server $DomainName | Select-Object -ExpandProperty DistinguishedName

# Note which domain is being operated against
Write-Output "Working on $DomainName Hosts"

# Define the group objects to work on
$Computer = (Get-ADComputer -Server $DomainName -Filter 'OperatingSystem -NotLike "*Server 2008*"' | Sort-Object Name).Name | Select-String -Pattern "your|variables"
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
$vmhosts = (Get-SCVMHost -VMMServer "yourscvmmconsole.$DomainName" | Sort-Object ComputerName).ComputerName
Write-Output "vmhosts in $DomainName = "($vmhosts).Count

# Set the Static Domain
$domain = "yourDomain" # (required if running a multi-domain environment and vmhosts/clusters are in one domain and their guests are in another)

# Loop through each Host Server
foreach ( $item in $vmhosts ) {

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
$vmhostcluster = (Get-SCVMHostCluster -VMMServer "yourscvmmconsole.$DomainName" | Sort-Object Name).ClusterName
Write-Output "vmhostclusters in $DomainName = "($vmhostcluster).Count

# Loop through each Cluster Server
foreach ( $item in $vmhostcluster ) {

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
