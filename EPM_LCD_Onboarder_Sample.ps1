<#
PURPOSE
Demonstrates the query of a datasource (SQL database in this case) for the local administrator
accounts on a particular host.  Then checks to see if they are already present in a CyberArk
CorePAS vault.  The script onboards any new accounts, skips any existing accounts.


NOTES
This script utilizes the psPAS and CredentialRetriever Powershell modules from
psPete - please download and import those from https://github.com/pspete

This is a sample script for demonstrating a proof-of-concept, it is not intended for direct
use in a production scenario.

(c) 2019 Adam Markert, CyberArk Software
#>



#PVWA and Safe Info
$PVWAURL = "https://pvwa.company.com" #The PVWA Host that will be used for API commands
$onBoardingSafe = "Windows Local Admin" #CyberArk Safe to onboard new accounts to
$onBoardingPlatform = "WinLooselyDevice" #CyberArk Platform to onboard the accounts with

#Get API and DB Creds via CCP, substitute relevant values for your DB/Address/Username
$dbPass = (Get-CCPCredential -URL $PVWAURL -AppID EPMOnboarder -Safe MSSQL -UserName sa -Address epmsvr.cyberarkdemo.com).Content #The database password for the account used to query the configuration database
$APICreds = (Get-CCPCredential -URL $PVWAURL -AppID EPMOnboarder -Safe EPMOnboarder -UserName svc_epm_onboarding -Address cyberarkdemo.com).ToCredential() #The LDAP credential used to authenticate against the PVWA API

#Database Connection Details - Replace Server/DB/Query details with the relevant values for your environment
$ServerName = "db.company.com"
$DatabaseName = "db name"
$Query = "SELECT * FROM ...."
$QueryTimeout = 120
$ConnectionTimeout = 30

#Connect to database and run query, store resuts in dataset
write-host -ForegroundColor Green "Connecting to DB $DatabaseName on $ServerName"
$conn=New-Object System.Data.SqlClient.SQLConnection
$ConnectionString = "Server={0};Database={1};Integrated Security=False;user=sa;password=$dbPass;Connect Timeout={2}" -f $ServerName,$DatabaseName,$ConnectionTimeout
$conn.ConnectionString=$ConnectionString
$conn.Open()
Write-Host -ForegroundColor Green "Executing Query: $Query"
$cmd=New-Object system.Data.SqlClient.SqlCommand($Query,$conn)
$cmd.CommandTimeout=$QueryTimeout
$ds=New-Object system.Data.DataSet
$da=New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
[void]$da.fill($ds)
$conn.Close()

#Authenticate to PVWA Rest API
write-host -Foreground Green "Connecting to PVWA Rest API..."
New-PASSession -Credential $APICreds -type LDAP -BaseURI $PVWAURL -Verbose



foreach($record in $ds.Tables[0]){
    $currentAccount = $record.Name #Replace Name with the user account name column from your dataset
    $currentAddress = $record.Domain #Replace Domain with the hostname column from the dataset
    
    write-host -ForegroundColor Green "Checking for existing account $currentAddress\$currentAccount in $onBoardingSafe..."
    $account = Get-PASAccount -Keywords "client $currentAccount" -Safe $onBoardingSafe -Verbose

    #Check if name already exists, add account if it does not exist
    if($account -eq $null){
    write-host -Foreground Green  "Account does not exist. Onboarding $currentAddress\$currentAccount to $onBoardingSafe..."
    Add-PASAccount -username $currentAccount -address $currentAddress -platformID $onBoardingPlatform -SafeName $onBoardingSafe -Verbose | Invoke-PASCPMOperation -ChangeTask -Verbose
    }else{
    Write-Host -Foreground Magenta "Account $currentAccount already exists, skipping..."
    }

 
}

#Flag credentials for DB and API for change, terminate API connection
write-host -Foreground Green "Batch Complete.  Invoking change of DB and API Credentials"
Get-PASAccount -safe EPMOnboarder -Keywords "cyberarkdemo.com svc_epm_onboarding" -Verbose | Invoke-PASCPMOperation -ChangeTask -Verbose
Get-PASAccount -safe MSSQL -Keywords "sa epmsvr.cyberarkdemo.com" -Verbose | Invoke-PASCPMOperation -ChangeTask -Verbose
write-host -Foreground Green "Closing PVWA Rest API session"
Close-PASSession -Verbose