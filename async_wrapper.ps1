function Async_Job_Creation {
    <# Begin asynchronous background jobs on each remote host #>

    foreach ($endpoint in $live_hosts[0]) {
        Start-Job -Name "$($endpoint)-async" -ScriptBlock {
            Invoke-Command -ComputerName $args[0] -FilePath $args[1]
        } -ArgumentList $endpoint, $script_location
    }
    $global:jobs = $live_hosts[0]
    $global:jobs = [System.Collections.ArrayList]$jobs

}

function Async_Job_Removal {
    <# Remove job after its output is received #>

    Remove-Job -Name "$($job)-async"

}

function Async_Job_Lifecycle {
    <# Loops all jobs until all jobs removed. Takes the output
    of the job and sends it to Log_Output for logging. #>

    $completed_jobs = @()
    while (Get-Job | Where-Object {$_.Name -like "*async*"}) {
        if ($completed_jobs) {
            foreach ($job_done in $completed_jobs) {
                if ($jobs -contains $job_done) {
                    $global:jobs.Remove($job_done)
                }
            }
        }
        foreach ($job in $jobs) {
            if (Get-Job "$($job)-async" | Where-Object {$_.State -eq "Completed"} ) {
                $job_results = Receive-Job "$($job)-async"
                Async_Job_Removal $job
                $completed_jobs += $job
                Log_Output
            }
        }
    }

}

function Run_Locally {
    <# Used if you run your script against the local machine only #>

    $job_results = & $script_location
    $job = $env:computername
    Log_Output

}

function Log_Output {
    <# How to the script formats and outputs its data #>

    if ($log_options[1] -eq "0") {
        Write-Output "[!] ### Start Results for $job ###[!] " | Out-File $log_options[0] -Append
        $job_results | Out-File $log_options[0] -Append
        Write-Output "[!] ### End Results for $job ### [!]" | Out-File $log_options[0] -Append
    } elseif ($log_options[1] -eq "1") {
        Write-Output "[!] ### Start Results for $job ### [!]" | Out-File "$($job)$($log_options[0])" -Append
        $job_results | Out-File "$($job)$($log_options[0])" -Append
        Write-Output "[!] ### End Results for $job ### [!]" | Out-File "$($job)$($log_options[0])" -Append
    } elseif ($log_options[1] -ge "2") {
        Write-Output "[!] ### Start Results for $job ### [!]"
        Start-Sleep -s 1
        Write-Output $job_results
        Write-Output "[!] ### End Results for $job ### [!]"
        Start-Sleep -s 1
    }
}

function Automatic_Host_Discovery {

    $domain = "dsinet.deltaware.com"
    $win10ou = "OU=Windows 10,OU=DSI Workstations,DC=dsinet,DC=deltaware,DC=com"
    $win7ou = "OU=Windows 7,OU=DSI Workstations,DC=dsinet,DC=deltaware,DC=com"

    $dc = Get-ADDomainController -Discover -Domain $domain | Select-Object -ExpandProperty Name
    $ADComputers += Get-ADComputer -Filter * -SearchBase $win10ou -Server $dc | Select -ExpandProperty Name
    $ADComputers += Get-ADComputer -Filter * -SearchBase $win7ou -Server $dc | Select -ExpandProperty Name

    $live_hosts = @()
    Write-Output "[!] This may take 5-10 minutes to complete"
    foreach ($workstation in $ADComputers) {
        if (Test-Connection $workstation -Count 1 -ErrorAction Ignore) {
                $live_hosts += $workstation
        }
    }
    Write-Output "[!] AD host discovery complete"
    return $live_hosts

}

function Set_Hosts {
    <# Select how the script finds hosts to connect to#>

    $selection = Read-Host -Prompt "Select how to find hosts >"

    if ($selection -eq "0" -or "") {
        Automatic_Host_Discovery
        return $live_hosts
    } elseif ($selection -eq "1") {
        $live_hosts = @()
        $hosts_file = Read-Host -Prompt "Absolute path >"
        if (Test-Path $hosts_file -PathType Leaf) {
            $possible_hosts = Get-Content $hosts_file
            $possible_hosts = $possible_hosts -Split ", "
            $possible_hosts = $possible_hosts -Split ","
            $possible_hosts = $possible_hosts -Split " "
            foreach ($endpoint in $possible_hosts) {
                if (Test-Connection $endpoint -Count 1 -ErrorAction Ignore) {
                    $live_hosts += $endpoint
                } else {
                    Write-Output "$($endpoint) not responding. Dropping $($endpoint)"
                }
            }
            return $live_hosts, "1"
        } else {
            return $live_hosts = "[!] File not found, please try again`r`n", "0"
        }
    } elseif ($selection -eq "2") {
        $live_hosts = @()
        $user_input = Read-Host -Prompt "Hostnames >"
        if ($user_input) {
            $possible_hosts = $user_input -Split ", "
            $possible_hosts = $possible_hosts -Split ","
            $possible_hosts = $possible_hosts -Split " "
            foreach ($endpoint in $possible_hosts) {
                if (Test-Connection $endpoint -Count 1 -ErrorAction Ignore) {
                    $live_hosts += $endpoint
                } else {
                    Write-Output "$($endpoint) not responding. Dropping $($endpoint)"
                }
            }
            return $live_hosts, "1"
        } else {
            return $live_hosts = "[!] No hostnames entered, please try again`r`n", "0"
        }
    } else {
        return $live_hosts = "", "2"
    }

}

function Set_Logging {
    <# Choose your logging option. Either: log output to single 
    file with custom name, log to separate files of type
    <hostname>-custom_suffix.txt, or log all output to console #>

    $selection = Read-Host -Prompt ">"

    if ($selection -eq "0") {
        $log_name = Read-Host -Prompt "Filename >"
        if ($log_name -eq "") {
            $log_name = "results.txt"
        }
        return $log_name, "0"
    } elseif ($selection -eq "1") {
        $log_name = Read-Host -Prompt "File suffix >"
        if ($log_name -eq "") {
            $log_name = "-result.txt"
        }
        return $log_name, "1"
    } else {
        return $log_name = "`r`n[+] Output will be written to the console...`r`n", "2"
    }

}

function Script_Location {
    <# Takes user input to determine script location on local
    file system. Checks if it's really there, then returns. #>

    $script_location = ""
    while ($script_location -eq "") {
        $script_location = Read-Host -Prompt "Path to script >"
        if (Test-Path $script_location -PathType Leaf) {
            if ([System.IO.Path]::GetExtension($script_location) -eq ".ps1") {
                return [string]$script_location
            } else {
                return $script_location = "[!] Not a PowerShell script", "0"
            }
        } else {
            return $script_location = "[!] Could not find script", "0"
        }
    }

}

function main {
    <# Entry point function for tool #>

    Write-Output "`r`nWelcome to the Asynchronous Remote Wrapper for PowerShell"
    Write-Output "Use this tool to execute your PowerShell scripts across remote systems"
    Write-Output "Now optimized for speed!`r`n"
    Start-Sleep -s 1
    Write-Output "`r`nPlease choose how you would like to discover remote hosts:"
    Write-Output "[0] Automatic remote host discovery via AD"
    Write-Output "[1] Text file containing list of remote hosts"
    Write-Output "[2] Command prompt with comma-separated entries"
    Write-Output "[3] Perform against this local system (default)`r`n"

    $live_hosts = Set_Hosts
    while ($live_hosts[1] -eq "0") {
        Write-Output $live_hosts[0]
        $live_hosts = Set_Hosts
    }

    Write-Output "`r`nProvide the path to your PowerShell script`r`n"

    $script_location = Script_Location
    while ($script_location[1] -eq "0") {
        Write-Output $script_location[0]
        $script_location = Script_Location
    }

    Write-Output "`r`nPlease choose how you would like to log your results:"
    Write-Output "[0] Log to single file"
    if ($live_hosts) {
        Write-Output "[1] Log to separate files per remote host (will append suffix to hostnames)"
        Write-Output "[2] Write to console`r`n"
    } else {
        Write-Output "[1] Write to console`r`n"
    }

    $log_options = Set_Logging
    if ($log_options[1] -eq "2") {
        Write-output $log_options[0]
    }

    if ($live_hosts) {
        Async_Job_Creation
        Async_Job_Lifecycle        
    } else {
        Run_Locally
    }

}

<# Start here 
Options near bottom of script
Remote logic near top #>

main
