# RfaCwaDeploy
Tools for deploying CW Automate agent service

# How to Use this Module on a Windows Device
Open yourself an admin PowerShell and run this line after setting the location ID to a known value, or 1 for generic.
```
$LocationID = 1; Invoke-Expression (( new-object Net.WebClient ).DownloadString( 'https://github.com/RFAInc/RfaCwaDeploy/blob/master/RfaCwaDeploy.psm1' )); Install-RfaCwaAgent; 
```

# Roadmap
More to come...
