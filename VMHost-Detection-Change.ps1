# Script with functions for detecting, setting, and reporting changes to VMHost values in Registry
# Author Matt Allen-Goebel (malgoebel)

# Self Discovery Variables
$guest = $env:COMPUTERNAME
$DomainName = (Get-WmiObject Win32_ComputerSystem).Domain
$WacUrl = "https://wac.$DomainName"

# Content Vars
$contentDirectory = "\\srvrcode\appcode\img\WindowsAdminCenter\Working Tree\"
$contentFileName = "$guest-connection.csv"

#Create the content directory if it doesn't exist
Write-Output "Creating Content Path if non-existent"
if (-not (Test-Path -Path $contentDirectory)) {
    New-Item -ItemType Directory -Path $contentDirectory
}

# Define the full path to the log and log files
$contentFilePath = Join-Path -Path $contentDirectory -ChildPath $contentFileName
# Garbage Collection
if (Test-Path $contentFilePath) {
		Remove-Item $contentFilePath
}

# Set Path for initial source of truth
$lastValueFile = "C:\nt\code\LastValue.txt"

# Function to attain the value of the registry key
function Get-RegistryValue {
     return (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters" | Select-Object -ExpandProperty PhysicalHostName)
	}

# Function to Set the source of truth and/or read from it.
function Read-LastValue {
	if (Test-Path $lastValueFile) {
		return Get-Content $lastValueFile
	} else {
		$initialValue = Get-RegistryValue
		Write-LastValue -value $initialValue
		# Open New Content file
		$contentEntry = '"name","type","tags","groupId"'
		Add-Content -Path $contentFilePath -Value $contentEntry
		$contentEntry = '"{0}","msft.sme.connection-type.server","{1}","global"' -f $guest, $initialValue
		Add-Content -Path $contentFilePath -Value $contentEntry
		return $initialValue
		}
	}

# Function to overwrite the source of truth with the current value
function Write-LastValue {
    param ($value)
    Set-Content -Path $lastValueFile -Value $value
	}

# Setting Variables 
$currentValue = Get-RegistryValue
$lastValue = Read-LastValue

# Do a check of the current source of truth file, compare it to what is actually true. Overwrite or else move on. 
if ($currentValue -ne $lastValue) {
	Write-Output "Registry value has changed from $lastValue to $currentValue"
	Write-LastValue -value $currentValue

	# Send a tag to the WAC Server of choice. 
	
	# Open New Content file
	$contentEntry = '"name","type","tags","groupId"'
	Add-Content -Path $contentFilePath -Value $contentEntry
	
	# Add Computer to Import File
	$contentEntry = '"{0}","msft.sme.connection-type.server","{1}","global"' -f $guest, $currentValue
    Add-Content -Path $contentFilePath -Value $contentEntry
	
} else {
	Write-Output "No change detected"
}