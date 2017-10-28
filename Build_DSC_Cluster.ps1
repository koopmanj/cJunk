#$LocalCredentials  = Get-Credential -Message 'Provide a password used for the template' -UserName 'Administrator'
#$DomainCredentials = Get-Credential -Message 'Provide a password used for the domain' -UserName 'jokohome\Administrator'
#$Credentials = Get-Credential -Message 'Provide a password used for the domain' -UserName 'Administrator'

configuration ClusterServices
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
        Import-DscResource -ModuleName @{ModuleName='xDnsServer';ModuleVersion='1.7.0.0'}
        Import-DscResource –ModuleName "PSDesiredStateConfiguration"
        
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

                #Address Record for member computer (clusternode won't be created, ensure it's resolable from the sql nodes, otherwise installation w
                xDnsRecord 'ClusterAddress'
                {
                    Name = 'winc0010'
                    Target = '192.168.10.164'
                    Type = 'Arecord'
                    Zone = $domainname
                    Ensure = 'Present'
                    PsDscRunAsCredential = $DomainCredentials
                }
                }

          node $AllNodes.Where{$_.Role -eq "DomainJoined"}.NodeName
            {
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

        node $AllNodes.Where{$_.Role -eq "Cluster"}.NodeName
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
                }

        node $AllNodes.Where{$_.Role -eq "Primary"}.NodeName
        {

                xCluster 'winc0010'
                {
                    Name = 'winc0010'
                    StaticIPAddress   = '192.168.10.164/24'
                    DomainAdministratorCredential = $DomainCredentials
                    PsDscRunAsCredential =  $DomainCredentials
                } 
        }

        node $AllNodes.Where{$_.Role -eq "Secondary"}.NodeName
        {
                xWaitForCluster WaitForCluster
                {
                    Name             = 'winc0010'
                    RetryIntervalSec = 10
                    RetryCount       = 60
                }

                xCluster 'winc0010'
                {
                    Name = 'winc0010'
                    StaticIPAddress   = '192.168.10.164/24'
                    DomainAdministratorCredential = $DomainCredentials
                    PsDscRunAsCredential =  $DomainCredentials
                    DependsOn                     = '[xWaitForCluster]WaitForCluster'
                } 
        }

        node $AllNodes.Where{$_.Role -eq "MSMQ"}.NodeName
        {
                WindowsFeature "MSMQ"
                {
                    Ensure = "Present"
                    Name   = "MSMQ"
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
            if($Node -like '*cluster1*')
            {
                @{
                    NodeName = $Node
                    Role = "DomainJoined","Cluster","Primary","MSMQ"
                 }
            }
            elseif($Node -like '*Cluster2*')
            {
                @{
                    NodeName = $Node
                    Role = "DomainJoined","Cluster","Secondary","MSMQ"
                 }
            }
            elseif($Node -like '*gui*')
            {
                @{
                    NodeName = $Node
                    Role = "DomainJoined","Management"
                 }
            }
            elseif($Node -like '*dc1*')
            {
                @{
                    NodeName = $Node
                    Role = "DomainController1"
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
ClusterServices -OutputPath C:\DSC\Hyper-V -ConfigurationData $cd -DomainCredentials $DomainCredentials

$DCVM      = (get-vm).where({$_.name -like '*dc*'}).name
$GUIVM      = (get-vm).where({$_.name -like '*gui*'}).name
$ClusterVM  = (get-vm).where({$_.name -like '*cluster*'}).name

Start-DscConfiguration -ComputerName $DCVM     -Credential $DomainCredentials -Wait -Verbose -Path C:\DSC\Hyper-V -force
Start-DscConfiguration -ComputerName $GUIVM     -Credential $DomainCredentials -Wait -Verbose -Path C:\DSC\Hyper-V -force
Start-DscConfiguration -ComputerName $ClusterVM -Credential $DomainCredentials -Wait -Verbose -Path C:\DSC\Hyper-V -force

#Invoke-Command -ComputerName w2k16-dc1 -ScriptBlock {start-dscconfiguration -useexisting -wait -verbose -force} -Credential $DomainCredentials
#Invoke-Command -ComputerName w2k16-cluster1 -ScriptBlock {start-dscconfiguration -useexisting -wait -verbose -force} -Credential $DomainCredentials
#Invoke-Command -ComputerName w2k16-cluster2 -ScriptBlock {start-dscconfiguration -useexisting -wait -verbose -force} -Credential $DomainCredentials