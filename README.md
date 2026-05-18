# Azure Claude Code VM

Azure上にClaude Codeを動かす開発VMを構築するためのBicepテンプレート集。  
開発VMの外向き通信はSquidプロキシVM経由に制限し、通信先をホワイトリストで管理する。

---

## アーキテクチャ

```
インターネット
    │
    │ SSH (NSGで接続元IP制限)
    ▼
┌─────────────────────────────────────────────────┐
│ VNet: 192.168.95.0/24                           │
│                                                 │
│  ┌─────────────────────┐  ┌─────────────────┐  │
│  │ 開発VMサブネット      │  │ ProxyVMサブネット │  │
│  │ 192.168.95.0/26     │  │ 192.168.95.64/26│  │
│  │                     │  │                 │  │
│  │  vm-{wl}-{env}-001  │──▶  vm-{wl}-{env}-002 │  │
│  │  Ubuntu 24.04       │  │  Ubuntu 24.04   │  │
│  │  Claude Code        │  │  Squid Proxy    │  │
│  │  Standard_B1s       │  │  Standard_B1s   │  │
│  └─────────────────────┘  └────────┬────────┘  │
│                                    │            │
└────────────────────────────────────┼────────────┘
                                     │ HTTP_PROXY経由
                                     ▼
                                 インターネット
                             (whitelist.txtで制限)
```

---

## ディレクトリ構造

```
.
├── README.md
├── bicep/
│   ├── main.bicep               # メインBicepテンプレート
│   ├── main.parameters.json     # パラメータファイル (要編集)
│   └── modules/
│       ├── network.bicep        # VNet / サブネット / NSG / パブリックIP
│       ├── dev-vm.bicep         # 開発VM
│       └── proxy-vm.bicep       # Proxy VM (Squid)
├── cloud-init/
│   ├── dev-vm.yaml              # 開発VM用cloud-init
│   └── proxy-vm.yaml            # Proxy VM用cloud-init
├── squid/
│   └── whitelist.txt            # Squid許可ドメインリスト
├── claude-code/
│   └── managed-settings.json   # Claude Code管理設定
└── scripts/
    └── prereq.sh                # 事前準備スクリプト
```

---

## 命名規約

`{type}-{workload}-{env}-{instance}` の形式に従う。

| 要素 | ルール | 例 |
|------|--------|-----|
| type | [CAFリソース略称](https://learn.microsoft.com/ja-jp/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) | `rg`, `vm`, `kv`, `vnet` |
| workload | 3文字固定の略称 | `ccv`（Claude Code VM の場合） |
| env | `prd` / `stg` / `dev` | `dev` |
| instance | ゼロパディング番号 | `001` |

**例：** `vm-ccv-dev-001`（開発VM）、`vm-ccv-dev-002`（Proxy VM）

### 必須タグ（全リソース）

| キー | 例 |
|------|----|
| `Environment` | `dev` |
| `Owner` | `your-email@example.com` |
| `Project` | `ccv: Claude Code VM` |

---

## 前提条件

- Azure CLI (`az`) がインストール・ログイン済みであること
- Bicep CLI がインストール済みであること (`az bicep install`)
- 対象サブスクリプションへの **Contributor** 以上の権限があること

> **Windows ユーザーへ:** WSL2 のセットアップが不要な [Azure Cloud Shell（SSH接続）](#azure-cloud-shell-ssh接続) の利用を推奨する。

---

## 事前準備

`scripts/prereq.sh` を使うと以下の手順（1〜3）を一括で実行できる。

```bash
bash scripts/prereq.sh {workload} {env}
```

手動で実施する場合は以下の手順に従うこと。

### 1. リソースグループの作成

```bash
az group create \
  --name rg-{workload}-{env}-001 \
  --location japaneast \
  --tags Environment={env} Owner={your-email} Project="{workload}: Claude Code VM"
```

### 2. Key Vaultの作成

```bash
az keyvault create \
  --name kv-{workload}-{env}-001 \
  --resource-group rg-{workload}-{env}-001 \
  --location japaneast \
  --enable-rbac-authorization true \
  --enabled-for-template-deployment true
```

Key VaultへのアクセスにはRBACロール `Key Vault Administrator` または `Key Vault Secrets Officer` が必要。

```bash
az role assignment create \
  --role "Key Vault Administrator" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope $(az keyvault show --name kv-{workload}-{env}-001 --resource-group rg-{workload}-{env}-001 --query id -o tsv)
```

### 3. SSHキーペアの生成とKey Vaultへの登録

開発VM（dev）とProxy VM（prx）でそれぞれ独立したキーペアを生成する。

```bash
for ROLE in dev prx; do
  # キーペア生成
  ssh-keygen -t ed25519 -f ~/.ssh/azure-{workload}-{env}-${ROLE} -C "azure-{workload}-{env}-${ROLE}" -N ""

  # 公開鍵をKey Vaultに登録
  az keyvault secret set \
    --vault-name kv-{workload}-{env}-001 \
    --name "ssh-public-key-${ROLE}" \
    --value "$(cat ~/.ssh/azure-{workload}-{env}-${ROLE}.pub)"

  # 秘密鍵をKey Vaultに登録
  az keyvault secret set \
    --vault-name kv-{workload}-{env}-001 \
    --name "ssh-private-key-${ROLE}" \
    --file ~/.ssh/azure-{workload}-{env}-${ROLE}

  # ローカルの秘密鍵を削除（Key Vaultから取得して使うため不要）
  rm ~/.ssh/azure-{workload}-{env}-${ROLE}
done
```

| シークレット名 | 用途 |
|--------------|------|
| `ssh-public-key-dev` | 開発VM公開鍵（Bicepデプロイ時に参照） |
| `ssh-private-key-dev` | 開発VM秘密鍵（SSH接続時に取得） |
| `ssh-public-key-prx` | Proxy VM公開鍵（Bicepデプロイ時に参照） |
| `ssh-private-key-prx` | Proxy VM秘密鍵（SSH接続時に取得） |

---

## デプロイ

### 1. パラメータファイルの編集

`bicep/main.parameters.sample.json` をコピーして編集する。

```bash
cp bicep/main.parameters.sample.json bicep/main.parameters.json
```  
特に以下は必ず変更すること：

| パラメータ | 説明 |
|-----------|------|
| `workload` | ワークロード略称（3文字、例: `ccv`） |
| `environment` | 環境（`prd` / `stg` / `dev`） |
| `allowedSshSourceIp` | SSH接続を許可する接続元IPアドレス（例: `203.0.113.1/32`）。`*` にすると全開放になるため **本番では必ず絞ること** |
| `keyVaultName` | 事前準備で作成したKey Vault名 |
| `adminUsername` | VMの管理者ユーザー名 |

### 2. Bicepのデプロイ

```bash
az deployment group create \
  --resource-group rg-{workload}-{env}-001 \
  --template-file bicep/main.bicep \
  --parameters bicep/main.parameters.json
```

---

## VMへの接続

### SSH接続（公開鍵認証）

```bash
# 秘密鍵をKey Vaultから取得（dev VM の場合）
az keyvault secret show \
  --vault-name kv-{workload}-{env}-001 \
  --name ssh-private-key-dev \
  --query value -o tsv > ~/.ssh/azure-{workload}-{env}-dev
chmod 600 ~/.ssh/azure-{workload}-{env}-dev

# 開発VMのパブリックIPを取得
PUBLIC_IP=$(az vm show \
  --resource-group rg-{workload}-{env}-001 \
  --name vm-{workload}-{env}-001 \
  --show-details \
  --query publicIps -o tsv)

# 接続
ssh -i ~/.ssh/azure-{workload}-{env}-dev {adminUsername}@$PUBLIC_IP
```

### Entra ID認証でのSSH接続

Entra ID認証でSSHするには、事前にRBACロールを割り当てる必要がある（→ [RBACロール割り当て](#rbacロール割り当てentra-id-ssh) 参照）。

```bash
# 開発VMへの接続
az ssh vm \
  --resource-group rg-{workload}-{env}-001 \
  --name vm-{workload}-{env}-001
```

### カスタムプロンプトの有効化

開発VMにはカスタムプロンプト（git branch表示つき）が `/etc/profile.d/prompt.sh` に用意されている。  
有効にするには以下を実行する。

```bash
echo 'source /etc/profile.d/prompt.sh' >> ~/.bashrc
source ~/.bashrc
```

### VS Code Remote SSH での接続

VS Code の [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) 拡張を使うと、ローカルの VS Code からそのまま開発VMに接続できる。

**1. SSH config を生成する**

```bash
az ssh config \
  --resource-group rg-{workload}-{env}-001 \
  --name vm-{workload}-{env}-001 \
  --file ~/.ssh/config
```

Entra ID 認証に必要な設定が `~/.ssh/config` に自動で追記される。

**2. VS Code から接続する**

1. VS Code に **Remote - SSH** 拡張をインストールする
2. コマンドパレット（`Ctrl+Shift+P` / `Cmd+Shift+P`）→ `Remote-SSH: Connect to Host...`
3. `vm-{workload}-{env}-001` を選択
4. 新しいウィンドウが開き、開発VM上の VS Code Server に接続される

> Entra ID SSH 接続には事前に RBACロールの割り当てが必要（→ [RBACロール割り当て](#rbacロール割り当てentra-id-ssh) 参照）。

### Proxy VMへのSSH接続

Proxy VMはインターネットからのSSHをNSGで拒否しているため、**開発VMをジャンプホストとして経由する**こと。

ジャンプホスト（開発VM）と接続先（Proxy VM）で鍵が異なるため、`ProxyCommand` で鍵を使い分けること。

```bash
ssh -i ~/.ssh/azure-{workload}-{env}-prx \
  -o "ProxyCommand ssh -i ~/.ssh/azure-{workload}-{env}-dev -W %h:%p {adminUsername}@<開発VMのパブリックIP>" \
  {adminUsername}@{proxyPrivateIp}
```

`~/.ssh/config` に設定しておくと `ssh ccv-prx` だけで接続できる。

```
Host {workload}-dev
  HostName <開発VMのパブリックIP>
  User {adminUsername}
  IdentityFile ~/.ssh/azure-{workload}-{env}-dev

Host {workload}-prx
  HostName {proxyPrivateIp}
  User {adminUsername}
  IdentityFile ~/.ssh/azure-{workload}-{env}-prx
  ProxyJump {workload}-dev
```

---

## RBACロール割り当て（Entra ID SSH）

Entra IDでSSH接続するには、対象ユーザーに以下のいずれかのロールをVM（またはリソースグループ）スコープで割り当てること。

| ロール | 用途 |
|--------|------|
| `Virtual Machine Administrator Login` | sudoあり（管理者権限） |
| `Virtual Machine User Login` | sudoなし（一般ユーザー） |

```bash
# 例: 管理者ロールを自分自身に割り当て
az role assignment create \
  --role "Virtual Machine Administrator Login" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope $(az vm show --resource-group rg-{workload}-{env}-001 --name vm-{workload}-{env}-001 --query id -o tsv)
```

> Entra ID SSH接続にはVMへの `AADSSHLoginForLinux` 拡張機能のインストールが必要。Bicepテンプレートに含まれている。

---

## Claude Codeの認証

### デフォルト: claude.ai認証

```bash
claude
# ブラウザ認証のURLが表示されるのでブラウザで開いて認証
```

### オプション: Anthropic API

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
claude
```

### オプション: Azure AI Foundry

```bash
export ANTHROPIC_API_KEY="..."
export ANTHROPIC_BASE_URL="https://{your-foundry-endpoint}.services.ai.azure.com/..."
claude
```

---

## Squid Proxyのドメイン管理

`squid/whitelist.txt` に許可ドメインを1行1エントリで記述する。  
変更後はProxy VMでSquidを再起動すること。

```bash
sudo systemctl restart squid
```

---

## オプション: 代替接続方式

パブリックIP＋NSGの構成をベースとしているが、以下の方式も採用可能。

### Azure Cloud Shell（SSH接続）

ブラウザ不要・WSL2 不要で、Windows ターミナルから直接 Cloud Shell の bash 環境に接続できる。  
`az`・`git`・`bash` が最初から揃っており、`prereq.sh` もそのまま実行可能。

```bash
ssh -t {azure-account}@shell.azure.com
```

接続後はリポジトリをクローンしてそのまま作業できる。

```bash
git clone https://github.com/{your-org}/claude-code-vm.git
cd claude-code-vm
bash scripts/prereq.sh {workload} {env}
```

> Cloud Shell には 5GB の永続ストレージ（Azure Files）が自動マウントされるため、セッションをまたいでファイルが保持される。

### Azure VPN Gateway
VPN経由でプライベートアクセス。パブリックIPを開放したくない場合に有効。  
コスト増（VPN Gateway SKUに依存）。

### Azure Bastion
Azureポータルからブラウザ経由でSSH。パブリックIPなしで接続可能。  
Standard SKUで月額約150USD程度のコストが発生。

### Tailscale / Headscale
VMにTailscaleエージェントを入れてメッシュVPN構成。  
Headscaleを使えばコントロールプレーンも自己ホスト可能。  
パブリックIPなしで低コストに実現できる。

---

## コスト目安（japaneast）

| リソース | SKU | 月額目安 |
|---------|-----|---------|
| 開発VM | Standard_B1s | 約900円 |
| Proxy VM | Standard_B1s | 約900円 |
| パブリックIP × 2 | Basic | 約300円 |
| OSディスク × 2 | StandardSSD 30GB | 約400円 |
| **合計** | | **約2,500円** |

> VMを停止（deallocate）すればコンピュート費用はかからない。  
> `az vm deallocate --resource-group ... --name ...`

---

## リソースグループの削除

デプロイ後はリソースグループに削除ロックが設定されるため、全削除時は先にロックを解除すること。

```bash
az lock delete --name lock-{workload}-{env}-001 --resource-group rg-{workload}-{env}-001
az group delete --name rg-{workload}-{env}-001 --yes
```

Key Vaultは論理削除（soft delete）で保持期間90日間残るため、同名で再作成する場合はパージが必要。

```bash
az keyvault purge --name kv-{workload}-{env}-001 --location japaneast
```
