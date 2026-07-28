# vue_doubao

豆包信源面板的纯静态版本。所有数据已经硬编码在 `src/snapshot.json` 中，不依赖后端 API，部署后直接用任意静态服务器托管即可。

## 仓库

<https://github.com/about-felicity/vue_doubao>

## 本地预览

```powershell
cd vue_doubao
npm install
npm run build
npx vite preview
```

或直接用 Python 起静态服务：

```powershell
cd vue_doubao\dist
python -m http.server 8766
```

## 修改数据

如果想更新页面上的数据，把新的 `/api/stats` 响应替换掉 `src/snapshot.json`，然后重新构建即可。

## 一键部署到公网

项目根目录下提供了两个部署脚本，默认都会部署到 `117.55.234.72:8765`：

- Windows：[`deploy_vue_doubao.ps1`](./deploy_vue_doubao.ps1)
- Linux / macOS：[`deploy_vue_doubao.sh`](./deploy_vue_doubao.sh)

Linux/macOS 下：

```bash
chmod +x deploy_vue_doubao.sh
./deploy_vue_doubao.sh
```

Windows PowerShell 下：

```powershell
.\deploy_vue_doubao.ps1
```

第一次使用请在脚本开头修改登录信息（用户名、SSH 私钥路径），或设置环境变量：

```bash
export DEPLOY_USER="root"
export DEPLOY_KEY="$HOME/.ssh/id_rsa"
./deploy_vue_doubao.sh
```

脚本会完成：构建 -> 上传 dist 到服务器 -> 在服务器启动 `python3 -m http.server 8765`。

如果你**已经在服务器上**（比如 `/home/doubao/vue_doubao`），不需要 SSH，直接构建并启动服务即可：

```bash
npm run build
nohup python3 -m http.server 8765 --directory dist > /tmp/vue_doubao.log 2>&1 &
```
