targetScope = 'resourceGroup'

@description('ワークロード略称（3文字）')
param workload string

@description('環境（prd / stg / dev）')
@allowed(['prd', 'stg', 'dev'])
param environment string

@description('Azureリージョン')
param location string = 'japaneast'

@description('SSH接続を許可する接続元IPアドレス（CIDR形式）。* は全開放。本番では必ず絞ること')
param allowedSshSourceIp string

@description('事前作成済みのKey Vault名')
param keyVaultName string

@description('VM管理者ユーザー名')
param adminUsername string = 'azureuser'

@description('Ownerタグに設定するメールアドレスまたはチーム名')
param ownerTag string

@description('Proxy VMに割り当てるプライベートIPアドレス（Proxyサブネット内）')
param proxyPrivateIp string = '192.168.95.68'

var tags = {
  Environment: environment
  Owner: ownerTag
  Project: '${workload}: Claude Code VM'
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

module network './modules/network.bicep' = {
  name: 'network'
  params: {
    workload: workload
    environment: environment
    location: location
    allowedSshSourceIp: allowedSshSourceIp
    tags: tags
  }
}

module proxyVm './modules/proxy-vm.bicep' = {
  name: 'proxy-vm'
  params: {
    workload: workload
    environment: environment
    location: location
    adminUsername: adminUsername
    keyVaultName: keyVaultName
    sshPublicKey: keyVault.getSecret('ssh-public-key-prx')
    subnetId: network.outputs.proxySubnetId
    publicIpId: network.outputs.proxyPipId
    proxyPrivateIp: proxyPrivateIp
    tags: tags
  }
}

module devVm './modules/dev-vm.bicep' = {
  name: 'dev-vm'
  params: {
    workload: workload
    environment: environment
    location: location
    adminUsername: adminUsername
    keyVaultName: keyVaultName
    sshPublicKey: keyVault.getSecret('ssh-public-key-dev')
    subnetId: network.outputs.devSubnetId
    publicIpId: network.outputs.devPipId
    proxyPrivateIp: proxyPrivateIp
    tags: tags
  }
  dependsOn: [proxyVm]
}

resource rgLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'lock-${workload}-${environment}-001'
  scope: resourceGroup()
  properties: {
    level: 'CanNotDelete'
    notes: '誤削除防止ロック'
  }
}

output devVmPublicIpName string = network.outputs.devPipName
output proxyVmPublicIpName string = network.outputs.proxyPipName
output devVmName string = devVm.outputs.vmName
output proxyVmName string = proxyVm.outputs.vmName
