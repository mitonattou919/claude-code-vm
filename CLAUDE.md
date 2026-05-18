# CLAUDE.md

## 目的

Azure上にClaude Code用の開発VMとSquidプロキシVMをBicepで構築・管理するリポジトリ。
外向き通信はSquidプロキシ経由に限定し、`squid/whitelist.txt` でドメインをホワイトリスト管理する。

@README.md

## ファイル構成

| ファイル | 役割 |
|---------|------|
| `bicep/main.bicep` | メインテンプレート（network / dev-vm / proxy-vm モジュールを呼び出す） |
| `bicep/main.parameters.json` | パラメータ（workload・environment・allowedSshSourceIp・keyVaultName・adminUsername を要編集） |
| `bicep/modules/network.bicep` | VNet / サブネット / NSG / パブリックIP |
| `bicep/modules/dev-vm.bicep` | 開発VM（Claude Code）|
| `bicep/modules/proxy-vm.bicep` | Proxy VM（Squid）|
| `cloud-init/dev-vm.yaml` | 開発VM の cloud-init |
| `cloud-init/proxy-vm.yaml` | Proxy VM の cloud-init |
| `squid/whitelist.txt` | Squid 許可ドメインリスト |
| `scripts/prereq.sh` | 事前準備スクリプト |
