#$LocalCredentials  = Get-Credential -Message 'Provide a password used for the template' -UserName 'Administrator'
#$DomainCredentials = Get-Credential -Message 'Provide a password used for the domain' -UserName 'joko\Administrator'
#$Credentials = Get-Credential -Message 'Provide a password used for the domain' -UserName 'Administrator'

configuration DomainController
{
        param(
            [PSCredential] $DomainCredentials,
            [ipaddress]$primarydcdns,
            $domainname = 'jokohome.local'
        )
        Import-DscResource –ModuleName @{ModuleName="xActiveDirectory";ModuleVersion="2.16.0.0"}
        Import-DscResource –ModuleName @{ModuleName="xComputerManagement";ModuleVersion="1.9.0.0"}
        Import-DscResource –ModuleName @{ModuleName="xSQLserver";ModuleVersion="7.0.0.0"}
        Import-DscResource -ModuleName @{ModuleName='xFailOverCluster';ModuleVersion='1.6.0.0'}
        Import-DscResource –ModuleName "PSDesiredStateConfiguration"
        
            #node ("Node1")
            node $AllNodes.Where{$_.Role -eq "DomainController1"}.NodeName
            {
                # Call Resource Provider
                # E.g: WindowsFeature, File
                WindowsFeature 'Domain Controller'
                {
                    Ensure = "Present"
                    Name   = "AD-Domain-Services"
                }

                xADDomain 'jokohome'
                {
                    DomainAdministratorCredential = $DomainCredentials
                    DomainName = 'jokohome.local'
                    SafemodeAdministratorPassword = $DomainCredentials
                    DatabasePath = 'c:\ntds'
                    LogPath = 'c:\ntds'
                    #PsDscRunAsCredential = Get-Credential
                    SysvolPath = 'c:\sys'
                }

                xADGroup 'Domain_MSSQL_Administrators'
                {
                    GroupName   = 'MSSQL_Administrators'
                    groupscope  = 'Global'
                    Category    = 'Security'
                    #Credential  = $DomainCredentials
                    Description = 'Sysadmin in MSSQL'
                    Ensure      = 'Present'
                }
            }
            
            node $AllNodes.Where{$_.Role -eq "DomainController2"}.NodeName
            {
                # Call Resource Provider
                # E.g: WindowsFeature, File
                WindowsFeature 'Domain Controller'
                {
                    Ensure = "Present"
                    Name   = "AD-Domain-Services"
                }

                xADDomain 'joko2'
                {
                    DomainAdministratorCredential = $DomainCredentials
                    DomainName = 'joko2.local'
                    SafemodeAdministratorPassword = $DomainCredentials
                    DatabasePath = 'c:\ntds'
                    LogPath = 'c:\ntds'
                    #PsDscRunAsCredential = Get-Credential
                    SysvolPath = 'c:\sys'
                }
            }
            node $AllNodes.Where{$_.Role -eq "DomainJoined"}.NodeName
            {
                WindowsFeature 'telnet-client'
                {
                    Ensure = "present"
                    Name   = "telnet-client"
                }

                if($NodeName.Length -gt '15')
                {
                    $NodeNaam = $NodeName.Substring(0,15)
                }
                else
                {
                    $nodenaam =  $NodeName
                }

                xComputer 'Join Domain'
                {
                    Name = $nodenaam
                    

                    Credential = $DomainCredentials
                    DomainName = $domainname

                }
            }

            node $AllNodes.Where{$_.Role -eq "SQL"}.NodeName
            {
                WindowsFeature 'FailoverClustering'
                {
                    Ensure = "Present"
                    Name   = "Failover-clustering"
                }
                WindowsFeature "RSAT-Clustering-PowerShell"
                {
                    Ensure = "Present"
                    Name   = "RSAT-Clustering-PowerShell"
                }
                WindowsFeature "RSAT-Clustering-CmdInterface"
                {
                    Ensure = "Present"
                    Name   = "RSAT-Clustering-CmdInterface"
                }
                WindowsFeature "NetFramework45"
                {
                    Ensure = "Present"
                    Name   = "NET-Framework-45-Core"
                }
                Group 'MSSQL_Administrators'
                {
                    GroupName   = 'MSSQL_Administrators'
                    Credential  = $DomainCredentials
                    Description = 'Sysadmin in MSSQL'
                    Ensure      = 'Present'
                    Members     = 'joko\mssql_administrators'
                }

                
            }

            node $AllNodes.Where{$_.Role -eq "Primary"}.NodeName
            {
                xCluster 'WINC0003'
                {
                    Name = 'WINC0003'
                    StaticIPAddress   = '10.128.2.251'
                    DomainAdministratorCredential = $DomainCredentials
                } 

                          
                xSQLserversetup 'SQL2016-Standard'
                {
                    InstanceName = 'INSTANCE1'
                    SetupCredential = $DomainCredentials
                    Action = 'Install'
                    #Action = 'InstallFailoverCluster'
                    AgtSvcAccount = $DomainCredentials
                    ###ASBackupDir = "D:\Microsoft SQL Server\OLAP\Backup"
                    #ASCollation = [string]]
                    ###ASConfigDir = "D:\Microsoft SQL Server\OLAP\Config"
                    ###ASDataDir = "D:\Microsoft SQL Server\OLAP\Data"
                    ###ASLogDir = "D:\Microsoft SQL Server\OLAP\Log"
                    #[ASSvcAccount = [PSCredential]]
                    #ASSysAdminAccounts = ".\MSSQL_Administrators"
                    ###ASTempDir = "D:\Microsoft SQL Server\OLAP\Temp"
                    BrowserSvcStartupType = 'Manual'
                    #[DependsOn = [string[]]]
                    #[ErrorReporting = [string]]
                    #FailoverClusterGroupName = 'WINC0003GN'
                    #FailoverClusterIPAddress = '192.168.0.171'
                    #FailoverClusterNetworkName = 'WINC0003NN'
                    Features = 'SQLENGINE'#'SQLENGINE'
                    ForceReboot = $true
                    #[FTSvcAccount = [PSCredential]]
                    InstallSharedDir = 'C:\Program Files\Microsoft SQL Server'
                    InstallSharedWOWDir = 'C:\Program Files (x86)\Microsoft SQL Server'
                    InstallSQLDataDir = "C:\Microsoft SQL Server"
                    InstanceDir = "C:\Microsoft SQL Server"
                    #[InstanceID = [string]]
                    #[ISSvcAccount = [PSCredential]]
                    #ProductKey = 'P7FRV-Y6X6Y-Y8C6Q-TB4QR-DMTTK' # 'Standard'  = 'P7FRV-Y6X6Y-Y8C6Q-TB4QR-DMTTK' #'Enterprise' = '27HMJ-GH7P9-X2TTB-WPHQC-RG79R'
                    PsDscRunAsCredential = $DomainCredentials
                    #[RSSvcAccount = [PSCredential]]
                    SAPwd = $DomainCredentials
                    SecurityMode = 'SQL'
                    #SecurityMode = 'Windows'
                    #SourceCredential = $DomainCredentialswap
                    SourcePath = 'd:\'
                    #[SQLBackupDir = [string]]
                    #[SQLCollation = [string]]
                    SQLSvcAccount = $DomainCredentials
                    #SQLSysAdminAccounts = 'MSSQL_Administrators','MSSQL_Administrators'
                    SQLTempDBDir = "c:\Microsoft SQL Server\Data"
                    SQLTempDBLogDir = "c:\Microsoft SQL Server\Data"
                    SQLUserDBDir = "c:\Microsoft SQL Server\Data"
                    SQLUserDBLogDir = "c:\Microsoft SQL Server\Data"
                    #[SQMReporting = [string]]
                    #[SuppressReboot = [bool]]
                    #[UpdateEnabled = [string]]
                    #[UpdateSource = [string]]
                }

                xSQLServerEndpoint 'endpoint'
                {
                    EndPointName = 'WINC0003-SQLE1'
                    SQLInstanceName = 'INSTANCE1'
                    SQLServer = 'w2k16-core-sql1'
                    Ensure = 'Present'
                    Port = 5022
                }
             
                #region enable hadr
                xSQLServerAlwaysOnService 'Enable Hadr'
                {
                    SQLInstanceName = 'INSTANCE1'
                    SQLServer = 'w2k16-core-sql1'
                    Ensure = 'Present'
                    PsDscRunAsCredential = $DomainCredentials
                    RestartTimeout = 10
                }
                #endregion

                #region create ha group
                xSQLServerAlwaysOnAvailabilityGroup 'ha group'
                {
                    Name = 'WINC0003-SQLG1'
                    SQLServer = 'w2k16-core-sql1'
                    SQLInstanceName = 'instance1'
                    Ensure = 'Present'
                    AutomatedBackupPreference  = 'Secondary'
                    AvailabilityMode = 'SynchronousCommit'
                    BackupPriority = 50
                }
                #endregion

                #region create ha listener
                xSQLServerAvailabilityGroupListener 'ha listener'
                {
                    AvailabilityGroup = 'WINC0003-SQLG1'
                    Name = 'WINC0003-SQLL1'
                    Nodename = 'w2k16-core-sql1' #primary node $PrimaryNode
                    InstanceName  = 'INSTANCE1'
                    ipaddress = @('10.128.2.247/255.255.255.0')#,'10.128.2.249/255.255.255.0')
                    port = 1433
                    Ensure = 'Present'
                }
                #endregion
            }
      
            node $AllNodes.Where{$_.Role -eq "Secondary"}.NodeName
            {
                xSQLserversetup 'SQL2016-Standard'
                {
                    Action = 'AddNode'
                    ForceReboot = $false
                    UpdateEnabled = 'False'
                    SourcePath = 'd:\'
                    SourceCredential = $DomainCredentials
                    SetupCredential = $DomainCredentials

                    InstanceName = 'INSTANCE1'
                    Features = 'SQLENGINE'

                    SQLSvcAccount = $DomainCredentials
                    AgtSvcAccount = $DomainCredentials
                    ASSvcAccount = $DomainCredentials

                    FailoverClusterNetworkName = 'WINC0003-SQLL1'
                }
            }

            node $AllNodes.Where{$_.Role -eq "SA"}.NodeName
            {
                xSQLserversetup 'SQL2016-Standard'
                {
                    InstanceName = 'MSSQLSERVER'
                    Features = 'SQLENGINE,AS'
                    SQLCollation = 'SQL_Latin1_General_CP1_CI_AS'
                    SQLSvcAccount = $DomainCredentials
                    AgtSvcAccount = $DomainCredentials
                    ASSvcAccount = $DomainCredentials
                    SQLSysAdminAccounts = $DomainCredentials.UserName
                    ASSysAdminAccounts = $DomainCredentials.UserName
                    SetupCredential = $SqlInstallCredential
                    InstallSharedDir = 'C:\Program Files\Microsoft SQL Server'
                    InstallSharedWOWDir = 'C:\Program Files (x86)\Microsoft SQL Server'
                    InstanceDir = 'C:\Program Files\Microsoft SQL Server'
                    InstallSQLDataDir = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
                    SQLUserDBDir = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
                    SQLUserDBLogDir = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
                    SQLTempDBDir = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
                    SQLTempDBLogDir = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'
                    SQLBackupDir = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Backup'
                    ASConfigDir = 'C:\MSOLAP\Config'
                    ASDataDir = 'C:\MSOLAP\Data'
                    ASLogDir = 'C:\MSOLAP\Log'
                    ASBackupDir = 'C:\MSOLAP\Backup'
                    ASTempDir = 'C:\MSOLAP\Temp'
                    SourcePath = 'd:\'
                    UpdateEnabled = 'False'
                    ForceReboot = $false
                }
            }

            node $AllNodes.Where{$_.Role -eq "Management"}.NodeName
            { 
                WindowsFeature 'AD management tools'
                {
                    Ensure = "Present"
                    Name   = "RSAT-ADDS"
                }
                
                WindowsFeature 'Cluster management tools'
                {
                    Ensure = "Present"
                    Name   = "RSAT-Clustering-Mgmt"
                }

                WindowsFeature 'DNS management tools'
                {
                    Ensure = "Present"
                    Name   = "RSAT-DNS-Server"
                }
            }
}

#endregion

$cd = @{
    AllNodes = @(    
        @{  
            NodeName = '*'
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }

        $Nodes = (get-vm).where({$_.name}).name
        foreach($Node in $Nodes)
        {
            if($Node -like '*sql1')
            {
                @{
                    NodeName = $Node
                    Role = "DomainJoined","SQL","Primary"
                 }
            }
            elseif($Node -like '*sql2')
            {
                @{
                    NodeName = $Node
                    Role = "DomainJoined","SQL","Secondary"
                 }
            }
            elseif($Node -like '*SQLSA')
            {
                @{
                    NodeName = $Node
                    Role = "DomainJoined","SQL","SA"
                 }
            }
            elseif($Node -like '*dc1*')
            {
                @{
                    NodeName = $Node
                    Role = "DomainController1"
                }
            }
            elseif($Node -like '*dc2*')
            {
                @{
                    NodeName = $Node
                    Role = "DomainController2"
                }
            }
            elseif($Node -like '*gui*')
            {
                @{
                    NodeName = $Node
                    Role = "DomainJoined","Management"
                 }
            }
            else
            {
                @{
                    NodeName = $Node
                    Role = "DomainJoined"
                 }
            }

        }
   ) 
}

#mkdir C:\DSC\Hyper-V\Archive\
#move C:\DSC\Hyper-V\* C:\DSC\Hyper-V\Archive\
DomainController -OutputPath C:\DSC\Hyper-V -ConfigurationData $cd -DomainCredentials $DomainCredentials

$DC1VM   = (get-vm).where({$_.name -like '*dc1*' }).name
$DC2VM   = (get-vm).where({$_.name -like '*dc2*' }).name
$GUIVM  = (get-vm).where({$_.name -like '*gui*'}).name
$SQLVM  = (get-vm).where({$_.name -like '*sql*'  -and $_.name -notlike '*SQL2*' -and $_.name -notlike '*SQLT*'-and $_.name -notlike '*SQLsa*'}).name
$RestVM = (get-vm).where({$_.name -notlike '*dc*' -and $_.name -notlike '*gui*' -and $_.name -notlike '*sql*' }).name

Start-DscConfiguration -ComputerName $DC1VM                  -Credential $DomainCredentials -Wait -Verbose -Path C:\DSC\Hyper-V -force
Start-DscConfiguration -ComputerName $DC2VM                  -Credential $DomainCredentials -Wait -Verbose -Path C:\DSC\Hyper-V -force
Start-DscConfiguration -ComputerName $GUIVM.substring(0,15) -Credential $DomainCredentials -Wait -Verbose -Path C:\DSC\Hyper-V -Force
Start-DscConfiguration -ComputerName $SQLVM                 -Credential $DomainCredentials -Wait -Verbose -Path C:\DSC\Hyper-V -Force
Start-DscConfiguration -ComputerName $RestVM                -Credential $DomainCredentials -Wait -Verbose -Path C:\DSC\Hyper-V -Force
Start-DscConfiguration -

$GUIVM = 
$GUIVM -replace ".{15}",""

ping $SQLVM[0]
ping $SQLVM[1]
