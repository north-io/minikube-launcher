## Installation script works for Debian/Ubuntu
1. Install task package
```
    $ sudo apt-get install task
```

2.  Install Neoon app in minikube from scratch (all in one)
### Needs to set enviroment variables with pull credential to north.io NEXUS registry and run a task
```
    $ NEXUS_USERNAME=<name> NEXUS_PASSWORD='<password>' Version="0.3.2" task neoon:mini:from-scratch
```

All needed packages will be installed in Linux.
All needed services will be installed in minikube.
Neoon-app will be installed.

Default vars:
          Domain=<URL>         Custom URL to run, defaults to https://neoon.local/local
          EnvID=<EnvID>        Environment ID, default 'local'
          Tenant=<Tenant>      Tenant, default 'local'
          Version=<Version>    Version of the product to run, default '0.3.2'

rootCA for domain will be generated and stored in directory ~/.local/share/mkcert/
For connecting to VM from PC or Laptop - add host to /etc/hosts
<IP-VM> neoon.local


3. Change Domain or Version
    For changing a Domain, Version, EnvID - add them as ENV var before run a task

```
    Version="0.3.3" task neoon:mini:run
```  

4. Run an application by step
    It is possible to run installation step by step:
```
    - task requried-packages:install 
    - task minikube:start
    - task infra:mini:install -- --username <username-NEXUS> --password <password-NEXUS>
    - task neoon:mini:run
```
    (for install certain version)
    - Version="0.2.2" task neoon:mini:run

5. Upgrade Neoon Version 
    - Version="0.3.2" task neoon:mini:upgrade

6. Recreate Neoon-app  (Delete current app and install the new one instead)
    - Version="0.3.2" task neoon:mini:recreate


### Add rootCA to Laptop
Configure the laptop to trust `rootCA.pem` certificate
    - MacOS - [read this guide](https://support.securly.com/hc/en-us/articles/206058318-How-to-install-the-Securly-SSL-certificate-on-Mac-OSX-)
    - Windows - [read this guide](https://www.ssls.com/knowledgebase/how-to-import-intermediate-and-root-certificates-via-mmc/)



    
