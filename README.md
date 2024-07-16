
## Installation Script for Debian/Ubuntu

### Step 1: Install Task Package
To install the required task package, execute the following command:
```
    $ sudo apt-get install task
```

### Step 2: Install Neoon Application in Minikube from Scratch (All-in-One)
Ensure to set the environment variables with your pull credentials for the north.io NEXUS registry, and then run the task:
```
    $ NEXUS_USERNAME=<name> NEXUS_PASSWORD='<password>' Version="0.3.2" task neoon:mini:from-scratch
```

This will install all necessary packages and services in Minikube, along with the Neoon application.

#### Default Variables:
- `Domain=<URL>`: Custom URL to run, defaults to `https://neoon.local`
- `EnvID=<EnvID>`: Environment ID, default is 'local'
- `Tenant=<Tenant>`: Tenant, default is 'local'
- `Version=<Version>`: Version of the product to run, default is '0.3.2'

**Note:** The application will be accessible at `https://<Domain>/<EnvID>`. For default values, use `https://neoon.local/local`.

A rootCA for the domain will be generated and stored in the directory `~/.local/share/mkcert/`. To connect to the VM from a PC or Laptop, add the following entry to your `/etc/hosts` file:

```
    <IP-VM> neoon.local
```

### Step 3: Change Domain or Version
To change the Domain, Version, or EnvID, set them as environment variables before running the task:

```
    Version="0.3.3" task neoon:mini:run
```

### Step 4: Step-by-Step Application Installation
The installation process can be executed step-by-step:

```
    - task requried-packages:install 
    - task minikube:start
    - task infra:mini:install -- --username <username-NEXUS> --password <password-NEXUS>
    - task neoon:mini:run
```
To install a specific version:
```
    Version="0.2.2" task neoon:mini:run
```

### Step 5: Upgrade Neoon Version
To upgrade the Neoon application to a new version:
 
    Version="0.3.2" task neoon:mini:upgrade

### Step 6: Recreate Neoon Application
To delete the current application and install a new one:
```
    Version="0.3.2" task neoon:mini:recreate
```

### Adding rootCA to Laptop
To configure the laptop to trust the `rootCA.pem` certificate, follow these guides:
- **MacOS**: [Guide to install the Securly SSL certificate on Mac OS X](https://support.securly.com/hc/en-us/articles/206058318-How-to-install-the-Securly-SSL-certificate-on-Mac-OSX-)
- **Windows**: [Guide to import intermediate and root certificates via MMC](https://www.ssls.com/knowledgebase/how-to-import-intermediate-and-root-certificates-via-mmc/)

### Default Admin User
If users are not explicitly provided via CLI to the `task` utility, the default users are taken [from values-file](https://github.com/north-io/minikube-launcher/blob/95aefe9b9fbf7f525692a1c395570314737a36de/scripts/values/minikube-values.yaml#L125-L132).
