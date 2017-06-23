$LocalCredentials  = Get-Credential -Message 'provide password for blank vm to rename host' -UserName Administrator
$DomainCredentials = Get-Credential -Message 'Provide a password used for the domain' -UserName 'joko\Administrator'

#region deploy new vm
for ($i = 1; $i -lt 3; $i++)
{ 
    New-VirtualMachine -VMName w2k16-core$i -ImagesLocation C:\Images -VMsLocation C:\Hyper-V -VirtualSwitchName External -ProcessorCount 1 -Generation 2 -Memory 2048 -Verbose    
    Start-VM -VMName w2k16-core$i
}

for ($i = 1; $i -lt 3; $i++)
{ 
    New-VirtualMachine -VMName w2k16-sql$i -ImagesLocation F:\Images -VMsLocation J:\Hyper-V -VirtualSwitchName External -ProcessorCount 1 -Generation 2 -Memory 2048 -Verbose    
    #Start-VM -VMName w2k16-core-sql$i
}

New-VirtualMachine -VMName w2k16-dc1 -ImagesLocation F:\Images -VMsLocation J:\Hyper-V -VirtualSwitchName External -ProcessorCount 1 -Generation 2 -Memory 2048 -Verbose
New-VirtualMachine -VMName w2k16-core-dc2 -ImagesLocation C:\Images -VMsLocation C:\Hyper-V -VirtualSwitchName External -ProcessorCount 1 -Generation 2 -Memory 2048 -Verbose
New-VirtualMachine -VMName w2k16-template -ImagesLocation C:\Images -VMsLocation C:\Hyper-V -VirtualSwitchName External -ProcessorCount 1 -Generation 2 -Memory 2 -Verbose
New-VirtualMachine -VMName w2k16-test -ImagesLocation C:\Images -VMsLocation C:\Hyper-V -VirtualSwitchName External -ProcessorCount 1 -Generation 2 -Memory 2 -Verbose

New-VirtualMachine -VMName w2k16-core-sqlsa -ImagesLocation C:\Images -VMsLocation C:\Hyper-V -VirtualSwitchName External -ProcessorCount 1 -Generation 2 -Memory 2048 -Verbose    
#endregion 

#region set the bootorder
(Get-VM).foreach({
    
    $VMFirmware = Get-VMFirmware -VMName $_.name
    #Write-Verbose -Message ($VMFirmware|Out-String) -Verbose

    if(($VMFirmware.BootOrder.boottype | select -First 1) -ne 'Drive')
    {
        Set-VMFirmware -VMName $_.name -BootOrder ($VMFirmware.BootOrder | sort boottype) -Verbose
    }
    else
    {
        Write-Warning -Message "$_ settings were applied previously" -Verbose
    }
})
#endregion 

#set host passwords first cause of OOBE
#region set the computernames
#$LocalCredentials = Get-Credential -Message 'provide password for blank vm to rename host' -UserName Administrator
(Get-VM).foreach({
    if($_.state -eq 'Running')
    {
        Invoke-Command -VMName $_.name -ArgumentList $_ -Credential $LocalCredentials -ScriptBlock {
            param($_)

            try
            {
                Rename-Computer -ComputerName $env:COMPUTERNAME -NewName $_.name -Verbose
                if($? -eq $true)
                {
                    $null = ipconfig /registerdns | Out-Null
                    Restart-Computer -Confirm:$true -Force
                }
            }
            catch
            {
                Write-Warning -Message "Renaming $_ failed" -Verbose
            }
        }
    }
    else
    {
        Write-Warning -Message "$env:computername : Machine not running"
    }
})
#endregion

#region disable firewall for hosts
(Get-VM).foreach({
    if($_.state -eq 'Running')
    {
        Invoke-Command -VMName $_.name -Credential $LocalCredentials -ScriptBlock {
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -Verbose   
            Write-Verbose -Message "$env:computername : Firewall Set" -Verbose
        }

    if($error[0] -like '*credential is invalid*')
    {
        Invoke-Command -VMName $_.name -Credential $DomainCredentials -ScriptBlock {
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -Verbose
            Write-Verbose -Message "$env:computername : Firewall Set" -Verbose
        }
    }
    }
    else
    {
        Write-Warning -Message "$($_.name) VM isnt running" -Verbose
    }
})
#endregion

#region import the dsc resources
#$LocalCredentials  = Get-Credential -Message 'Provide a password used for the template' -UserName 'Administrator'
#$DomainCredentials = Get-Credential -Message 'Provide a password used for the domain' -UserName 'joko\Administrator'
(Get-VM).where({$_.state -eq 'running'}).foreach({
        Invoke-Command -ComputerName $PSItem.name  -ArgumentList $LocalCredentials -ScriptBlock {`
        param(
            $LocalCredentials
        )
        
        if((Get-DscResource -Module xActiveDirectory).where({$_.version -eq '2.16.0.0'}).count -eq 0)
        {
            Write-Verbose -Message "$env:computername : Module xactivedirectory will be installed" -Verbose
            Find-DscResource -Module xactivedirectory -MinimumVersion '2.16.0.0' -MaximumVersion '2.16.0.0' -Verbose | install-module -Confirm:$false -Verbose -Force
        }
        else
        {
            Write-Verbose -Message "$env:computername : Module xactivedirectory allready installed" -Verbose
        }

        if((Get-DscResource -Module xComputerManagement).where({$_.version -eq '1.9.0.0'}).count -eq 0)
        {
            Write-Verbose -Message "$env:computername : Module xComputerManagement will be installed" -Verbose
            Find-DscResource -Module xComputerManagement -MinimumVersion '1.9.0.0' -MaximumVersion '1.9.0.0' -Verbose | install-module -Confirm:$false -Verbose -Force
        }
        else
        {
            Write-Verbose -Message "$env:computername : Module xComputerManagement allready installed" -Verbose
        }
        if((Get-DscResource -Module xDnsServer).where({$_.version -eq '1.7.0.0'}).count -eq 0)
        {
            Write-Verbose -Message "$env:computername : Module xDnsServer will be installed" -Verbose
            Find-DscResource -Module xDnsServer -MinimumVersion '1.7.0.0' -MaximumVersion '1.7.0.0' -Verbose | install-module -Confirm:$false -Verbose -Force
        }
        else
        {
            Write-Verbose -Message "$env:computername : Module xDnsServer allready installed" -Verbose
        }

    } -Credential $LocalCredentials
    })
(Get-VM).where({$_.state -eq 'running'}).where({$_.name -like '*sql*'}).foreach({
        Invoke-Command -ComputerName $PSItem.name  -ArgumentList $LocalCredentials -ScriptBlock {`
        param(
            $LocalCredentials
        )
        
        if((Get-DscResource -Module xsqlserver).where({$_.version -eq "7.0.0.0"}).count -eq 0)
        {
            Write-Verbose -Message "$env:computername : Module xsqlserver will be installed" -Verbose
            Find-DscResource -Module xsqlserver -MinimumVersion "7.0.0.0" -MaximumVersion "7.0.0.0" -Verbose | install-module -Confirm:$false -Verbose -Force
        }
        else
        {
            Write-Verbose -Message "$env:computername : Module xsqlserver allready installed" -Verbose
        }

        if((Get-DscResource -Module xFailOverCluster).where({$_version -eq '1.6.0.0'}).count -eq 0)
        {
            Write-Verbose -Message "$env:computername : Module xFailOverCluster will be installed" -Verbose
            Find-DscResource -Module xFailOverCluster -MinimumVersion '1.6.0.0' -MaximumVersion '1.6.0.0' -Verbose | install-module -Confirm:$false -Verbose -Force
        }
        if((Get-DscResource -Module xDnsServer).where({$_.version -eq '1.7.0.0'}).count -eq 0)
        {
            Write-Verbose -Message "$env:computername : Module xDnsServer will be installed" -Verbose
            Find-DscResource -Module xDnsServer -MinimumVersion '1.7.0.0' -MaximumVersion '1.7.0.0' -Verbose | install-module -Confirm:$false -Verbose -Force
        }
        else
        {
            Write-Verbose -Message "$env:computername : Module xFailOverCluster allready installed" -Verbose
        }
    } -Credential $LocalCredentials
    })
#endregion

#region set the domaincontroller dns settings
#$LocalCredentials  = Get-Credential -Message 'Provide a password used for the template' -UserName 'Administrator'
#$DomainCredentials = Get-Credential -Message 'Provide a password used for the domain' -UserName 'joko\Administrator'
$DomainController = (Get-VM).where({$_.name -like '*dc1'})
$DomainControllerAddress = Test-Connection -ComputerName $DomainController.name -Count 1
#$DomainControllerAddressIPv6 = $DomainControllerAddress.IPV6Address.IPAddressToString
$DomainControllerAddressIPv4 = $DomainControllerAddress.IPV4Address.IPAddressToString
#$DomainControllerAddressIPv6  = $DomainControllerAddressIPv6 -replace '%\d+',''

$PublicDNSIP = '8.8.8.8'

(Get-VM).where({$_.name -notlike '*dc1'}).foreach({
    if($_.state -eq 'Running')
    {
        #Invoke-Command -VMName $_.name -Credential $LocalCredentials -ArgumentList $DomainControllerAddressIPv4,$DomainControllerAddressIPv6,$PublicDNSIP  -ScriptBlock {
        Write-Verbose -Message "$env:computername : attempting : $LocalCredentials" -Verbose
        Invoke-Command -VMName $_.name -Credential $LocalCredentials -ArgumentList $DomainControllerAddressIPv4,$PublicDNSIP  -ScriptBlock {
    param(
        #$DomainControllerAddressIPv6,
        $DomainControllerAddressIPv4,
        $PublicDNSIP 
    )
    
    $DNSServers = Get-DnsClientServerAddress #| Set-DnsClientServerAddress -ServerAddresses $DomainControllerAddress.IPV4Address.IPAddressToString,192.168.1.1
    #if($DNSServers -notcontains $DomainControllerAddress)
    #{
        #Write-Verbose -Message "$env:computername : $($DomainControllerAddressIPv4,$DomainControllerAddressIPv6,$PublicDNSIP | Out-String)" -Verbose
        Write-Verbose -Message "$env:computername : $($DomainControllerAddressIPv4,$PublicDNSIP | Out-String)" -Verbose
        #Set-DnsClientServerAddress -ServerAddresses $DomainControllerAddressIPv6,$DomainControllerAddressIPv4,$PublicDNSIP  -InterfaceIndex $DNSServers.where({$psitem.interfacealias -like '*Ethernet*'}).InterfaceIndex[0]
        Set-DnsClientServerAddress -ServerAddresses $DomainControllerAddressIPv4,$PublicDNSIP  -InterfaceIndex $DNSServers.where({$psitem.interfacealias -like '*Ethernet*'}).InterfaceIndex[0]
        #Set-DnsClientServerAddress -ServerAddresses 192.168.1.1 -InterfaceIndex $DNSServers.where({$psitem.interfacealias -like '*Ethernet*'}).InterfaceIndex[0]
    #}
}
        if($error[0] -like '*credential is invalid*')
        {
            #Invoke-Command -VMName $_.name -Credential $DomainCredentials -ArgumentList $DomainControllerAddressIPv4,$DomainControllerAddressIPv6,$PublicDNSIP  -ScriptBlock {
            Write-Verbose -Message "$env:computername : attempting : $DomainCredentials" -Verbose
            Invoke-Command -VMName $_.name -Credential $DomainCredentials -ArgumentList $DomainControllerAddressIPv4,$PublicDNSIP  -ScriptBlock {
    param(
        #$DomainControllerAddressIPv6,
        $DomainControllerAddressIPv4,
        $PublicDNSIP 
    )
    
    $DNSServers = Get-DnsClientServerAddress #| Set-DnsClientServerAddress -ServerAddresses $DomainControllerAddress.IPV4Address.IPAddressToString,192.168.1.1
    #if($DNSServers -notcontains $DomainControllerAddress)
    #{
        #Write-Verbose -Message "$env:computername : $($DomainControllerAddressIPv4,$DomainControllerAddressIPv6,$PublicDNSIP | Out-String)" -Verbose
        Write-Verbose -Message "$env:computername : $($DomainControllerAddressIPv4,$PublicDNSIP | Out-String)" -Verbose
        #Set-DnsClientServerAddress -ServerAddresses $DomainControllerAddressIPv6,$DomainControllerAddressIPv4,$PublicDNSIP  -InterfaceIndex $DNSServers.where({$psitem.interfacealias -like '*Ethernet*'}).InterfaceIndex[0]
        Set-DnsClientServerAddress -ServerAddresses $DomainControllerAddressIPv4,$PublicDNSIP  -InterfaceIndex $DNSServers.where({$psitem.interfacealias -like '*Ethernet*'}).InterfaceIndex[0]
        #Set-DnsClientServerAddress -ServerAddresses 192.168.1.1 -InterfaceIndex $DNSServers.where({$psitem.interfacealias -like '*Ethernet*'}).InterfaceIndex[0]
    #}
}
        }
    }
    else
    {
        Write-Warning -Message "$($_.name) VM isnt running" -Verbose
    }
})
#endregion

#region set dns suffix
#Changes the setting to Append these DNS Suffixes and adds suffixes
$suffixes = 'jokohome.local'
(Get-VM).foreach({
    if($_.state -eq 'Running')
    {
        Invoke-Command -VMName $_.name -Credential $LocalCredentials -ArgumentList $suffixes -ScriptBlock {
            $class = [wmiclass]'Win32_NetworkAdapterConfiguration'
            $class.SetDNSSuffixSearchOrder($suffixes)
            Write-Verbose -Message "$env:computername : Suffix Set" -Verbose
        }

    if($error[0] -like '*credential is invalid*')
    {
        Invoke-Command -VMName $_.name -Credential $DomainCredentials -ArgumentList $suffixes -ScriptBlock {
            $class = [wmiclass]'Win32_NetworkAdapterConfiguration'
            $class.SetDNSSuffixSearchOrder($suffixes)
            Write-Verbose -Message "$env:computername : Suffix Set" -Verbose
        }
    }
    }
    else
    {
        Write-Warning -Message "$($_.name) VM isnt running" -Verbose
    }
})
#Changes setting back to Append primary and connection specific DNS suffixes
#$class = [wmiclass]'Win32_NetworkAdapterConfiguration'
#$class.SetDNSSuffixSearchOrder($null)

#endregion

#region set netadapter binding 
#Changes the setting to Append these DNS Suffixes and adds suffixes Disable-NetAdapterBinding -Name "Ethernet 2" -ComponentID ms_tcpip6
(Get-VM).foreach({
    if($_.state -eq 'Running')
    {
        Invoke-Command -VMName $_.name -Credential $LocalCredentials -ArgumentList $suffixes -ScriptBlock {
            $class = [wmiclass]'Win32_NetworkAdapterConfiguration'
            $class.SetDNSSuffixSearchOrder($suffixes)
            Write-Verbose -Message "$env:computername : Suffix Set" -Verbose
        }

    if($error[0] -like '*credential is invalid*')
    {
        Invoke-Command -VMName $_.name -Credential $DomainCredentials -ArgumentList $suffixes -ScriptBlock {
            $class = [wmiclass]'Win32_NetworkAdapterConfiguration'
            $class.SetDNSSuffixSearchOrder($suffixes)
            Write-Verbose -Message "$env:computername : Suffix Set" -Verbose
        }
    }
    }
    else
    {
        Write-Warning -Message "$($_.name) VM isnt running" -Verbose
    }
})
#Changes setting back to Append primary and connection specific DNS suffixes
#$class = [wmiclass]'Win32_NetworkAdapterConfiguration'
#$class.SetDNSSuffixSearchOrder($null)

#endregion

Disable-NetAdapterBinding -Name "Ethernet 2" -ComponentID ms_tcpip6
#endregion

New-NetIPAddress -InterfaceAlias

New-NetIPAddress –InterfaceAlias "Ethernet 2" –IPAddress "192.168.0.1" –PrefixLength 24
New-NetIPAddress –InterfaceAlias "Ethernet"   –IPAddress "192.168.0.2" –PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.0.1
New-NetIPAddress –InterfaceAlias "Ethernet" –IPAddress "192.168.0.3" –PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.0.1
New-NetIPAddress –InterfaceAlias "Ethernet" –IPAddress "192.168.0.4" –PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.0.1



<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this workflow
.EXAMPLE
   Another example of how to use this workflow
.INPUTS
   Inputs to this workflow (if any)
.OUTPUTS
   Output from this workflow (if any)
.NOTES
   General notes
.FUNCTIONALITY
   The functionality that best describes this workflow
#>
workflow Verb-Noun 
{
    Param
    (
        # Param1 help description
        [string]
        $Param1,

        # Param2 help description
        [int]
        $Param2,

        $RunningVms
    )

    foreach -parallel ($vm in $RunningVms)
    {
        Write-Output $vm
        Write-Verbose -Message "$env:computername : $vm" -Verbose
    }

}

Verb-Noun -RunningVms $RunningVms

(get-vm).where({$_.state -eq 'Running'}) | Restart-VM







###########
###########
###########
###########
######################
######################
#################################
#################################
.\Blergh

#get-vm
$creds = Get-Credential
#start-vm w2k16-core_dc1

#create a domain controller
$Computername = Invoke-Command -VMName w2k16-core-dc1 -ScriptBlock {$env:COMPUTERNAME} -Credential $creds
ping -4 $Computername -n 2
ping -6 $Computername -n 2 

Invoke-Command -ComputerName $Computername  -ArgumentList $creds -ScriptBlock {`
        param(
            $creds
        )
        
        if((Get-DscResource -Module xactivedirectory -Name xADDomainController) -eq $null)
        {
            Write-Verbose -Message 'Module will be installed' -Verbose
            Find-DscResource -Module xactivedirectory -Verbose | install-module -Confirm:$false -Verbose
        }
        else
        {
            Write-Verbose -Message 'Module allready installed' -Verbose
        }

        #Write-Verbose -Message (Get-DscResource -Module xactivedirectory -Name xADDomainController).Version -Verbose

        #Get-DscConfigurationStatus

        #Invoke-DscResource -Name windowsfeature  -Method set -Property @{
        #    Ensure = "Present"
        #    Name = "AD-Domain-Services"
        #} -Verbose -ModuleName PSDesiredStateConfiguration

        #Invoke-DscResource -Name xADDomain  -Method set -Property @{
        #    DomainAdministratorCredential = Get-Credential
        #    DomainName = 'joko.local'
        #    SafemodeAdministratorPassword = Get-Credential
        #    DatabasePath = 'c:\ntds'
        #    LogPath = 'c:\ntds'
        #    #PsDscRunAsCredential = Get-Credential
        #    SysvolPath = 'c:\sys'
        #} -Verbose -ModuleName xactivedirectory

    } -Credential $creds

#join member server to domain
Invoke-Command -VMName w2k16-core1 -ArgumentList $creds -ScriptBlock {`
        param(
            $creds
        )
        
        if((Get-DscResource -Module xactivedirectory -Name xADDomainController) -eq $null)
        {
            Write-Verbose -Message 'Module will be installed' -Verbose
            Find-DscResource -Module xactivedirectory | install-module -Confirm:$false
        }

        Write-Verbose -Message (Get-DscResource -Module xactivedirectory -Name xADDomainController).Version -Verbose

        Invoke-DscResource -Name xADDomainController -Method set -Property @{
            DomainAdministratorCredential = Get-Credential
            DomainName = 'joko.local'
            SafemodeAdministratorPassword =  Get-Credential
            DatabasePath = 'c:\ntds'
            LogPath = 'c:\ntds'
            PsDscRunAsCredential = Get-Credential
            SysvolPath = 'c:\ntds'
        } -Verbose -ModuleName xactivedirectory

    } -Credential $creds
Invoke-Command -VMName w2k16-core1 -ArgumentList $creds -ScriptBlock {$env:COMPUTERNAME} -Credential $creds

Get-DnsClientServerAddress

Invoke-DscResource -Name xPackage -Method set -Property @{
    Name = '7-Zip 16.04 (x64 edition)'
    Path = 'C:\Users\Jeroen\Downloads\7z1604-x64.msi'
    ProductId = '23170F69-40C1-2702-1604-000001000000'
    Ensure = 'present'
} -Verbose -ModuleName xPSDesiredStateConfiguration

Set-DnsClientServerAddress -ServerAddresses 192.168.1.136 -InterfaceIndex 2
Invoke-DscResource -Name xComputer -Method set -Property @{
    Name = $env:computername
    DomainName = 'joko.local'
    Credential = $creds
} -Verbose -ModuleName xComputerManagement



             xComputer 'Join Domain'
                {
                    Name = $env:COMPUTERNAME
                    Credential = $Credentials
                                        #PsDscRunAsCredential = $DomainCredentials
#                    [DependsOn = [string[]]]
                    DomainName = $domainname

                }
                } -Verbose -ModuleName xPSDesiredStateConfiguration



###############SYNTAX
xComputer [String] #ResourceName
{
    Name = [string]
    [Credential = [PSCredential]]
    [DependsOn = [string[]]]
    [DomainName = [string]]
    [PsDscRunAsCredential = [PSCredential]]
    [UnjoinCredential = [PSCredential]]
    [WorkGroupName = [string]]
}