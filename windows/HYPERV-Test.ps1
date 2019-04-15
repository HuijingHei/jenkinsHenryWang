param (
    [CmdletBinding()]
    [String] $action,
    [String] $image,
    [Bool] $gen2,
    [String] $omni_ip,
    [String] $omni_port,
    [string[]]$vmArray,
    [Int64] $cpuCount = 2,
    [Int64] $memorySize = 2
)

Set-Variable -Name switchName -Value "External" -Option constant -Scope Script
Set-Variable -Name arch -Value "x86_64" -Option constant -Scope Script
Set-Variable -Name snapshotName -Value "ICABase" -Option constant -Scope Script
Set-Variable -Name vmPath -Value "C:\downstream-vm\" -Option constant -Scope Script
Set-Variable -Name imageURL -Value "http://${omni_ip}:${omni_port}" -Option constant -Scope Script

Get-ChildItem .\Libraries -Recurse | Where-Object { $_.FullName.EndsWith(".psm1") } | ForEach-Object { Import-Module $_.FullName -Force}

function GetImage([String]$vmPath, [String]$vmName, [String]$image, [String]$imageURL)
{
    Write-Host "Info: Downloading from ${imageURL}/${image} to $vmPath${vmName}.vhdx"
    if (-not (Test-Path $vmPath))
    {
        New-Item -ItemType directory -Path $vmPath | Out-Null
        Write-Host "Info: Create new vhdx directory $vmPath"
    }
    $start_time = Get-Date
    (New-Object System.Net.WebClient).DownloadFile("$imageURL/${image}", "${vmPath}${vmName}.vhdx")
    if ( -not $? ) {
        write-host "Error: failed to download from ${imageURL}/${image} to $vmPath${vmName}.vhdx"
        return $false
    }
    write-host "Debug: Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s) for downloading"
    if (Test-Path "${vmPath}${vmName}.vhdx") {
        return $true
    } 
    return $false
}

function NewVMFromVHDX([String]$vmPath, [Switch]$gen2, [String]$switchName, [String]$vmName, [Int64]$cpuCount, [Int64]$mem)
{
    Write-Host "Info: Creating $vmName with $cpuCount CPU and ${mem}G memory."
    # Convert GB to bytes because parameter -MemoryStartupByptes requires bytes
    [Int64]$memory = 1GB * $mem

    if ($gen2)
    {
        New-VM -Name "$vmName" -Generation 2 -BootDevice "VHD" -MemoryStartupBytes $memory -VHDPath $vmPath -SwitchName $switchName | Out-Null
    }
    else
    {
        New-VM -Name "$vmName" -BootDevice "IDE" -MemoryStartupBytes $memory -VHDPath $vmPath -SwitchName $switchName | Out-Null
    }

    if (-not $?)
    {
        Write-Host "New-VM $vmName failed"
        # rm new created disk
        If (Test-Path $vmPath){
            Remove-Item $vmPath
        }
        return $false
    }
    Write-Host "Info: New-VM $vmName successfully"

    # If gen 2 vm, set vmfirmware secure boot disabled
    if ($gen2)
    {
        # disable secure boot
        Set-VMFirmware $vmName -EnableSecureBoot Off

        if (-not $?)
        {
            Write-Host "Info: Set-VMFirmware $vmName secureboot failed"
            return $false
        }

        Write-Host "Info: Set-VMFirmware $vmName secureboot successfully"
    }

    # set processor to 2, default is 1
    Set-VMProcessor -vmName $vmName -Count $cpuCount

    if (! $?)
    {
        Write-Host "Error: Set-VMProcessor $vmName  to $cpuCount failed"
        return $false
    }

    if ((Get-VMProcessor -vmName $vmName).Count -eq $cpuCount)
    {
        Write-Host "Info: Set-VMProcessor $vmName to $cpuCount"
    }
    return $true
}

function VMSetup([String]$vmPath, [String]$vmName, [String]$image, [String]$omni_ip, [String]$omni_port, [String]$omni_user, [Bool]$gen2, [String]$switchName, [Int64]$cpuCount, [Int64]$mem)
{
    GetImage -vmPath $vmPath -vmName $vmName -image $image -omni_ip $omni_ip -omni_port $omni_port -omni_user $omni_user
    # remove vm if already exists same name VM already exists
    VMRemove -vmName $vmName
    # Create vm based on new vhdx file
    if ($gen2)
    {
        NewVMFromVHDX -vmPath "${vmPath}${vmName}.vhdx" -gen2 -switchName $switchName -vmName $vmName -cpuCount $cpuCount -mem $mem
    }
    else
    {
        NewVMFromVHDX -vmPath "${vmPath}${vmName}.vhdx" -switchName $switchName -vmName $vmName -cpuCount $cpuCount -mem $mem
    }
    # Now Start the VM
    Write-Host "Info: Starting VM $vmName."
    $timeout = 300
    Start-VM -Name $vmName
    WaitForVMToStartKVP -vmName $vmName -timeout $timeout
    $vmIP = GetIPv4ViaKVP $vmName

    Write-Host "Info: Downloading $kernelName to VM $vmIP."
    # Download kernel rpm from omni server and install
    Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "exit 0"
    Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "scp -o StrictHostKeyChecking=no -P $omni_port -i /root/.ssh/id_rsa_private data@${omni_ip}:kernel* . && yum install -y ./kernel* && reboot"

    WaitForVMToStartKVP -vmName $vmName -timeout $timeout
    $vmIP = GetIPv4ViaKVP $vmName

    Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "exit 0"
    $kernel = Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "uname -r"
    Write-Host "Info: Get kernel version from VM ${vmName}: ${kernel}, expect ${kernelName} "
    if ("${kernelName}.x86_64" -Match $kernel)
    {
        Write-Host "Info: Kernel version matched"
        VMStop -vmName $vmName
        NewCheckpoint -vmName $vmName -snapshotName $snapshotName
    }
    else
    {
        Write-host "ERROR: Unable get correct kernel version" -ErrorAction SilentlyContinue
        VMStop -vmName $vmName
        VMRemove -vmName $vmName -vmPath $vmPath
    }
}

function VMStart([String]$vmPath, [String]$vmName, [String]$image, [Bool]$gen2, [String]$switchName, [Int64]$cpuCount, [Int64]$mem)
{
    # remove vm if already exists same name VM already exists
    VMRemove -vmName $vmName

    write-host "Info: vmName is $vmName"
    $status = GetImage -vmPath $vmPath -vmName $vmName -image $image -imageURL $imageURL
    if ($status -eq $false) {
        return $null
    }
    
    # Create vm based on new vhdx file
    if ($gen2)
    {
        NewVMFromVHDX -vmPath "${vmPath}${vmName}.vhdx" -gen2 -switchName $switchName -vmName $vmName -cpuCount $cpuCount -mem $mem
    }
    else
    {
        NewVMFromVHDX -vmPath "${vmPath}${vmName}.vhdx" -switchName $switchName -vmName $vmName -cpuCount $cpuCount -mem $mem
    }
    # Now Start the VM
    Write-Host "Info: Starting VM $vmName."
    $timeout = 300
    Start-VM -Name $vmName
    WaitForVMToStartKVP -vmName $vmName -timeout $timeout
    $vmIP = GetIPv4ViaKVP $vmName

    if ($vmIP)
    {
        #Write-Output y | plink -l root -i ssh\3rd_id_rsa.ppk $vmIP "exit 0"
        Write-Host "Info: Get $vmName IP = $vmIP"
        return $vmIP
    }
    else
    {
        Write-host "ERROR: Unable get correct kernel version" -ErrorAction SilentlyContinue
        VMStop -vmName $vmName
        VMRemove -vmName $vmName -vmPath $vmPath
    }
    return $null
}

switch ($action)
{
    "add"
    {
        $hosts = ".\hosts"
        if (Test-Path $hosts) {
            Remove-Item $hosts -Confirm:$false -Force
            New-Item -ItemType file -Path $hosts | Out-Null
        }
        foreach ($i in $vmArray) {
            write-host "DEBUG: vm is $i"
            $ip = VMStart -vmPath $vmPath -vmName $i -image $image -gen2 $gen2 -switchName $switchName -cpuCount $cpuCount -mem $memorySize
            write-host "DEBUG: Get return value from VMStart : $ip"
            if ( $ip[-1] ) {
                $ip[-1] | Out-File -FilePath $hosts -Append -Encoding ASCII
            } else { exit 100 }            
        }
        Write-Output y | pscp -q -l root -i ssh\3rd_id_rsa.ppk $hosts root@${omni_ip}:/root/
        exit 0          
    }
    "del"
    {
        foreach ($i in $vmArray)
        {
            VMRemove -vmName $i
        }
    }
    "start"
    {
        foreach ($i in $vmArray) {
            write-host "DEBUG: $i"
            exit 100
        }
        $ip1 = VMStart -vmPath $vmPath -vmName $vmName -image $image -gen2 $gen2 -switchName $switchName -cpuCount $cpuCount -mem $memorySize
        if ( $ip1[-1] ) {
            Write-output $ip1[-1] | Out-File -FilePath .\hosts -Encoding ASCII
            write-host "INFO: get-content hosts"
            get-content .\hosts
            write-host "-----------------"
            Write-Output y | pscp -l root -i ssh\3rd_id_rsa.ppk .\hosts root@${omni_ip}:/root/
        } else {
            return $false
        }
    }
}