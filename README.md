# RfaCwaDeploy
Tools for deploying CW Automate agent service

# How to Use this Module on a Windows Device
Open yourself an admin PowerShell and run this line after setting the location ID to a known value, or 1 for generic.
```
$LocationID = 1; Invoke-Expression (( new-object Net.WebClient ).DownloadString( 'https://automate.rfa.com/hidden/RfaCwaDeploy.psm1.txt' )); Install-RfaCwaAgent; 
```

# Roadmap
More to come...
