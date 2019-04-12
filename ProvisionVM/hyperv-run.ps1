param (
    [CmdletBinding()]
    [String] $action,
    [String] $nvr,
    [Switch] $dual,
    [Switch] $gen2
)
$DebugPreference = "Continue"
Write-Debug "Get action = $action"
Write-Debug "Get nvr = $nvr"
Write-Debug "Get dual = $dual"
Write-Debug "Get gen2 = $gen2"

if (${env:IMAGE}) {
    $tmp = ${env:IMAGE}.replace(".vhdx","")
} else {
    Write-Host "Error: env:IMAGE is NULL"
    exit 100
}

New-Variable -Name vmArray -Value @()
if ($dual){
    Set-Variable -Name testType -Value "downstream" -Option constant -Scope Script
    ( Get-Variable -Name "vmArray" ).Value += "${tmp}-${nvr}-${testType}-A"
    ( Get-Variable -Name "vmArray" ).Value += "${tmp}-${nvr}-${testType}-B"
    Set-Variable -Name suite -Value "debug" -Option constant -Scope Script
} else {
    Set-Variable -Name testType -Value "gating" -Option constant -Scope Script
    ( Get-Variable -Name "vmArray" ).Value += "${tmp}-${nvr}-${testType}"
    Set-Variable -Name suite -Value "debug" -Option constant -Scope Script
}

Set-Variable -Name hostFolder -Value "C:\${nvr}-${testType}" -Option constant -Scope Script


$SecurePassword = $env:DOMAIN_PSW | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:DOMAIN_USR, $SecurePassword

switch ($action)
{
    "add"
    {
        Write-Host "Info: Starting to remove $hostFolder"
        Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock {(Test-Path $args[0]) -and (Remove-Item $args[0] -Confirm:$false -recurse -Force)} -ArgumentList $hostFolder

        Write-Host "Info: Starting to copy windows folder from JSlave to $hostFolder on $env:HOST_ID"
        $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
        Copy-Item ".\windows" -Destination $hostFolder -ToSession $Session -Recurse
        Remove-PSSession -Session $Session

        Write-Host "Info: Running HYPERV-Manager on $env:HOST_ID"
        $ret = Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock `
        { `
            Set-Location $args[0]; `
            .\HYPERV-Test $args[1] -image $args[2] -gen2 $args[3] -omni_ip $args[4] -omni_port $args[5] -vmArray $args[6];`
            return $LastExitCode
        } `
        -ArgumentList @($hostFolder, $action, $env:IMAGE, $gen2, ${env:OMNI_IP}, ${env:API_PORT}, $vmArray)
        if ( $ret[-1] -ne 0 ) { 
            write-host "Error: Add vm failed, get return value - $ret"
            exit 100
        } else { write-host "Debug: Get return value - $ret"; exit 0}
    }
    "run"
    {
        
        Set-Variable -Name lisa_home -Value ".\lis\WS2012R2\lisa" -Option constant -Scope Script
        #Set-Variable -Name vmNameB -Value "$env:name-$env:version-$env:release-$env:BUILD_ID-B" -Option constant -Scope Script
        Copy-Item ".\windows\ssh\3rd_id_rsa.ppk" -Destination "${lisa_home}\ssh\"
        Copy-Item ".\windows\bin\*" -Destination "${lisa_home}\bin\"
        Copy-Item ".\windows\cases.xml" -Destination "${lisa_home}\xml\"

        Write-Host "Info: Starting to copy LISA from JSlave to $hostFolder on $env:HOST_ID"
        $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
        Copy-Item $lisa_home -Destination $hostFolder -ToSession $Session -Recurse
        Remove-PSSession -Session $Session

        Write-Host "Info: Running $suite test cases on $env:HOST_ID"
        Invoke-command -computername $env:HOST_ID -Credential $cred -scriptblock `
        { `
            Set-Location $args[0]; `
            .\lisa run .\xml\cases.xml -vmName $args[1] -hvServer $args[2] -sshKey 3rd_id_rsa.ppk -suite $args[3] -os Linux -dbgLevel 10 -testParams "VM2NAME=${args[4]};SSH_PRIVATE_KEY=id_rsa_private" `
        } `
        -ArgumentList "${hostFolder}\lisa", $vmArray[0], $env:HOST_ID, $suite, $vmArray[1]

        Write-Host "Info: Copying result back to JSlave"
        $resultDir = "${hostFolder}\lisa\TestResults"
        $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
        Copy-Item $resultDir -Destination ".\" -FromSession $Session -Recurse -Confirm:$false
        Remove-PSSession -Session $Session
    
    }
    "del"
    {
        Write-Host "Info: Removing VM(s) on $env:HOST_ID"
        Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock `
        { `
            Set-Location $args[0]; `
            .\HYPERV-Test $args[1] -image $args[2] -gen2 $args[3] -omni_ip $args[4] -omni_port $args[5] -vmArray $args[6] `
        } `
        -ArgumentList $hostFolder, $action, $env:IMAGE, $gen2, ${env:OMNI_IP}， ${env:API_PORT}, $vmArray

        Write-Host "Info: Removing $hostFolder on $env:HOST_ID"
        Invoke-Command -ComputerName $env:HOST_ID -Credential $cred -ScriptBlock `
        { `
            Remove-Item $args[0] -Force -Confirm:$false -Recurse `
        } `
        -ArgumentList $hostFolder
    }
    "put"
    {
        Write-Host "Info: Uploading Report.xml to $env:OMNI_IP"
        Copy-Item ".\TestResults\*\Report*.xml" -Destination ".\report-${env:HOST_ID}${smoke}-${env:owner}-${env:id}.xml"
        Write-Output y | windows\bin\pscp -P $env:API_PORT -l $env:OMNI_USER -i windows\ssh\3rd_id_rsa.ppk ".\report-${env:HOST_ID}${smoke}-${env:owner}-${env:id}.xml" ${env:OMNI_IP}:
        Write-Host "Info: Action PUT exit code: $global:LastExitCode"
    }
    "start"
    {
        if ($esxi)
        {
            Set-Location ".\windows"
            .\ESX-Manager $action -dual $dual -name $env:name -version $env:version -release $env:release -image $env:IMAGE -buildID $env:BUILD_ID -gen2 $gen2 -omni_ip $env:OMNI_IP -omni_port $env:API_PORT -omni_user $env:OMNI_USER -hostID $env:HOST_ID -vsphereServer $env:ENVVISIPADDR -vsphereProtocol $env:ENVVISPROTOCOL -credential $cred
            Write-Host "Info: Action ADD exit code: $global:LastExitCode"
        }
        else
        {
            Write-Host "Info: Starting to remove $hostFolder"
            Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock {(Test-Path $args[0]) -and (Remove-Item $args[0] -Confirm:$false -recurse -Force)} -ArgumentList $hostFolder

            Write-Host "Info: Starting to copy windows folder from JSlave to $hostFolder on $env:HOST_ID"
            $Session = New-PSSession -ComputerName $env:HOST_ID -Credential $cred
            Copy-Item ".\windows" -Destination $hostFolder -ToSession $Session -Recurse
            Remove-PSSession -Session $Session

            Write-Host "Info: Running HYPERV-Manager on $env:HOST_ID"
            Invoke-Command -computername $env:HOST_ID -Credential $cred -scriptblock `
            { `
                Set-Location $args[0]; `
                .\HYPERV-Manager $args[1] -dual $args[2] -name $args[3] -version $args[4] -release $args[5] -image $args[6] -buildID $args[7] -gen2 $args[8] -omni_ip $args[9] -omni_port $args[10] -omni_user $args[11] -compose_ver $args[12]`
            } `
            -ArgumentList $hostFolder, $action, 0, "", "", "", $env:IMAGE, "", $gen2, $env:OMNI_IP, $env:API_PORT, $env:OMNI_USER, $env:ComposeVer
        }
    }
}