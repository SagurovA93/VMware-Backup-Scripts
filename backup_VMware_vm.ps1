# Import VMware modules into powershell 
Get-Module -Name VMware* -ListAvailable | Import-Module 

$vm_list_txt = "$PSScriptRoot\vm-backup-list.txt"
$CONFIG = Import-Csv $vm_list_txt -Delimiter ';'
$HOSTNAME = (Get-ChildItem -Path env:computername).Value
$Today = Get-Date -Format d
$server = "server_ip"
$DATASTOR_NAME = 'nfs_iz2bstor_backup_vm'
$BACKUP_DIR = '\\backup_server\backup_folder'
$LOG_DIR = '\\backup_server\backup_folder\logs'
$global:VMachines = @()
$ScriptStartTime = Get-Date -Format dd.MM.yyyy_HH_mm_ss

New-Item "$LOG_DIR" -Name "$ScriptStartTime.txt" -ItemType file
$FileLog = "$LOG_DIR\$ScriptStartTime.txt"

Write-Output "Бэкап виртуальных машин VMWare" | Out-File $FileLog -Append -Encoding utf8
Write-Output "Время запуска $ScriptStartTime" | Out-File $FileLog -Append -Encoding utf8


$TODAY_DAY_OF_WEEK = switch ((Get-Date).DayOfWeek.value__) {
0 {"sun"}
1 {"mon"}
2 {"tue"}
3 {"wed"}
4 {"thu"}
5 {"fri"}
6 {"sat"}
}

function VM_from_config {
  foreach ($VMachine in $CONFIG) {

    if ( $VMachine.'VM name' -match '#') {
      continue
    }

    $MACHINE_ID = $VMachine.'VM id'
    $MACHINE_NAME = $VMachine.'VM name'
    $SCHEDUEL_MONTH = $VMachine.month
    $SCHEDUEL_DAYS = $VMachine.day -split(',',7) 
    $BACKUP_COPIES = $VMachine.'number of copies'
    $BACKUP_HOST= $VMachine.'backup host'

    #Write-Host "$MACHINE_ID;$MACHINE_NAME;$SCHEDUEL_MONTH;$SCHEDUEL_DAY;$BACKUP_COPIES"

    $BACKUP_MONTH = 'False'

    if ( $SCHEDUEL_MONTH -eq '*' ) {
      $BACKUP_MONTH = 'True'
    }
    elseif ( $SCHEDUEL_MONTH -eq (Get-Date).Month ) {
      $BACKUP_MONTH = 'True'
    }
    else {
      continue
    }

    $BACKUP_TODAY = 'False'

    foreach ( $DAY in $SCHEDUEL_DAYS ) {

        if ( $DAY -eq '*' ) { 
          $BACKUP_TODAY = 'True'
          break
        }
        elseif ( $DAY -eq $TODAY_DAY_OF_WEEK ) {
          $BACKUP_TODAY = 'True'
          break
        }
        else {
          continue
        }
    }

    if ( $BACKUP_TODAY -eq 'True') {
      $VM_TO_BACKUP = "$MACHINE_ID,$MACHINE_NAME,$BACKUP_COPIES"
      $global:VMachines += , $VM_TO_BACKUP
    }
    
  }
}

function ExportVm {
    #Trust certificate
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
    
    Connect-VIServer $server
    
    Write-Output "$(Get-Date -Format dd.MM.yyyy-HH:mm:ss) Подключаюсь к vCenter" | Out-File $FileLog -Append -Encoding utf8

    $VMachines = $global:VMachines

    foreach ($vm in $VMachines){
        # select VM using vm-id
        $vm_id = ($vm -split(','))[0]
        $vm = Get-VM -Id $vm_id
        # take view
        $VM_VIEW = Get-View $vm
	# find path to a VM file
        $VM_FILE_PATH = $VM_VIEW.Config.Files.VmPathName
	#Take date + time for clone vm
        $CLONE_DATA = Get-Date -Format dd.MM.yyyy_HH_mm_ss
	# making vm snapshot 
        $CLONE_SNAP = $vm | New-Snapshot -Name "$CLONE_DATA"
	# select snapshot folder
        $CLONE_FOLDER = $VM_VIEW.parent  #Get-Item ds:\123 
	# take view with currently created snapshot
        $VM_VIEW = Get-View $vm
	# Create object spec for cloning VM
        $CLONE_SPEC = new-object Vmware.Vim.VirtualMachineCloneSpec
	# determine snapshot for clone
        $CLONE_SPEC.Snapshot = $vmView.Snapshot.CurrentSnapshot
    
	# where to locate clone: $DATASTOR_NAME
        $CLONE_SPEC.Location = new-object Vmware.Vim.VirtualMachineRelocateSpec
        $CLONE_SPEC.Location.Datastore = ((Get-Datastore -Name $DATASTOR_NAME)[0] | Get-View).MoRef
        $CLONE_SPEC.Location.Transform = [Vmware.Vim.VirtualMachineRelocateTransformation]::sparse

        $CLONE_NAME = "$vm-$vm_id-$CLONE_DATA"

        $TimeStart = Get-Date
        Write-Output "$(Get-Date -Format dd.MM.yyyy-HH:mm:ss) Начинаю бэкап $vm с id: $vm_id" | Out-File $FileLog -Append -Encoding utf8
        
        # Create clone
        $VM_VIEW.CloneVM($CLONE_FOLDER, $CLONE_NAME, $CLONE_SPEC)
        
        #"$BACKUP_DIR\$CLONE_NAME"
        
        New-Item "$BACKUP_DIR\$CLONE_NAME" -Name README_$vm_id.txt -ItemType file
        $readme = "$BACKUP_DIR\$CLONE_NAME\README_$vm_id.txt"

        $TimeEnd = Get-Date
        $TotalTime = $($TimeEnd - $TimeStart).TotalMinutes

        Write-Output "Время создания бэкапа: $CLONE_DATA" | Out-File $readme -Append -Encoding utf8
        Write-Output "Время создания бэкапа: $TotalTime минут" | Out-File $readme -Append -Encoding utf8


        # Write newly created VM to stdout as confirmation
        Get-VM $CLONE_NAME
    
        $CLONE_VIEW = Get-VM $CLONE_NAME | Get-View
        $CLONE_VIEW.Config.files

        # Remove Snapshot created for clone
        Get-Snapshot -VM (Get-VM -Name $vm.Name) -Name $CLONE_SNAP | Remove-Snapshot -confirm:$False

        Write-Output "Удален снапшот $CLONE_SNAP" | Out-File $readme -Append -Encoding utf8

	# Remove clone from inventory, if -DeletePermanently is defined vm copy will be deletedd from disk
        Get-VM $CLONE_NAME | Remove-VM -Verbose -Confirm:$false

        Write-Output "Удален клон из инвентори $CLONE_NAME" | Out-File $readme -Append -Encoding utf8
        
        Write-Output "$(Get-Date -Format dd.MM.yyyy-HH:mm:ss) Бэкап $vm успешно завершён" | Out-File $FileLog -Append -Encoding utf8
    }

    #Disconnect from vCentre
    Disconnect-VIServer * -Confirm:$false
}

function Retention_backup {
  $VMachines = $global:VMachines

  Write-Output "$(Get-Date -Format dd.MM.yyyy-HH:mm:ss) Проверка количества экзамеплячров бэкапов" | Out-File $FileLog -Append -Encoding utf8

  foreach ($vm in $VMachines) {
    $COPY_AMOUNT = ($vm -split(','))[2]
    $VM_NAME = ($vm -split(','))[1]
    $VM_ID = ($vm -split(','))[0]

    $VM_BACKUPS =  Get-ChildItem $BACKUP_DIR | where {$_.Name -match $VM_ID}

    if ( $COPY_AMOUNT -lt $VM_BACKUPS.Count ) {
      
      Write-Output "$(Get-Date -Format dd.MM.yyyy-HH:mm:ss) $VM_NAME - Количество резервных копий превышает лимит $COPY_AMOUNT" | Out-File $FileLog -Append -Encoding utf8

      $RM_BACKUP = $VM_BACKUPS | Sort CreationTime | Select -First $($VM_BACKUPS.Count - $COPY_AMOUNT)

      # Remove old backups
      foreach ( $backup in $RM_BACKUP) {
        
        $backup
        
        Write-Output "$(Get-Date -Format dd.MM.yyyy-HH:mm:ss) Удаляется $BACKUP_DIR\$backup" | Out-File $FileLog -Append -Encoding utf8
        
        Remove-Item $BACKUP_DIR\$backup -Recurse

      }
    }
    
    else {
      Write-Output "$(Get-Date -Format dd.MM.yyyy-HH:mm:ss) $VM_NAME - Количество резервных копий НЕ превышает лимит" | Out-File $FileLog -Append -Encoding utf8
    }
    
  }
 
}

VM_from_config
ExportVm
Retention_backup
