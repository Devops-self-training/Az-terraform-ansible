Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.ps1'))
hab license accept
hab pkg install core/windows-service
netsh advfirewall firewall add rule name="Habitat Butterfly API" dir=in action=allow protocol=TCP localport=9631
netsh advfirewall firewall add rule name="ICMP Allow incoming V4 echo request" protocol=icmpv4:8,any dir=in action=allow
Start-Service -Name Habitat