param workload string
param environment string
param location string
param allowedSshSourceIp string
param tags object

var vnetName = 'vnet-${workload}-${environment}-001'
var devSubnetName = 'snet-${workload}-${environment}-dev-001'
var proxySubnetName = 'snet-${workload}-${environment}-prx-001'
var devNsgName = 'nsg-${workload}-${environment}-dev-001'
var proxyNsgName = 'nsg-${workload}-${environment}-prx-001'
var devPipName = 'pip-${workload}-${environment}-dev-001'
var proxyPipName = 'pip-${workload}-${environment}-prx-001'

var devSubnetPrefix = '192.168.95.0/26'
var proxySubnetPrefix = '192.168.95.64/26'

resource devNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: devNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-Inbound'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSshSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'SSH接続を許可（接続元はパラメータで制御）'
        }
      }
    ]
  }
}

resource proxyNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: proxyNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Squid-From-DevSubnet'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: devSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3128'
          description: '開発VMサブネットからSquidプロキシへのアクセスを許可'
        }
      }
      {
        name: 'Allow-SSH-From-DevSubnet'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: devSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: '開発VMサブネットからSSH管理アクセスを許可'
        }
      }
      {
        name: 'Deny-SSH-Internet'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'インターネットからのSSHを拒否'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['192.168.95.0/24']
    }
  }
}

resource devSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: devSubnetName
  properties: {
    addressPrefix: devSubnetPrefix
    networkSecurityGroup: {
      id: devNsg.id
    }
  }
}

resource proxySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: proxySubnetName
  properties: {
    addressPrefix: proxySubnetPrefix
    networkSecurityGroup: {
      id: proxyNsg.id
    }
  }
  dependsOn: [devSubnet]
}

resource devPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: devPipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource proxyPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: proxyPipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

output vnetId string = vnet.id
output devSubnetId string = devSubnet.id
output proxySubnetId string = proxySubnet.id
output devPipId string = devPip.id
output devPipName string = devPipName
output proxyPipId string = proxyPip.id
output proxyPipName string = proxyPipName
