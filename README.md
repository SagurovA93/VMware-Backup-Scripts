# VMware-Backup-Script
Powershell script for backup VMware Virtual Machines

### Depends on:
1. Vmware Power-CLI >= 6.5
```
https://my.vmware.com/web/vmware/details?productId=614&downloadGroup=PCLI650R1
```
### Описание
  - This script you may schedule in Windows scheduler
  - For conneting to vCenter using account which is run scipt from windows scheduler, be shure it's account has rights to clone VM
  - vm-backup-list - script scheduler for Virtual Machines
  - You may comment strings in vm-backup-list using '#'
  
## TODO:
  - macke script scheduler more similar to crone
