param workload string
param environment string
param location string
param adminUsername string
param keyVaultName string
param subnetId string
param publicIpId string
param proxyPrivateIp string
param tags object

@secure()
param sshPublicKey string

var vmName = 'vm-${workload}-${environment}-001'
var nicName = 'nic-${workload}-${environment}-dev-001'

var cloudInitRaw = loadTextContent('../../cloud-init/dev-vm.yaml')
var statuslineSh = base64(loadTextContent('../../claude-code/statusline.sh'))
var managedSettings = base64(loadTextContent('../../claude-code/managed-settings.json'))
var cloudInit = replace(replace(replace(cloudInitRaw, '__PROXY_IP__', proxyPrivateIp), '__STATUSLINE_SH__', statuslineSh), '__MANAGED_SETTINGS__', managedSettings)
var cloudInitBase64 = base64(cloudInit)

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIpId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: 30
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: cloudInitBase64
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource aadSshExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'AADSSHLoginForLinux'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADSSHLoginForLinux'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  }
}

output vmId string = vm.id
output vmName string = vm.name
