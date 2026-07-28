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

## 每日更新数据（从本地动态面板生成静态页面）

你的本地抓取和动态面板不受影响。服务器上的这个页面只是一个快照，想更新时按下面流程来：

1. 确保本地动态面板在跑（`python doubao_dashboard_server.py`，默认 `http://127.0.0.1:8765`）。
2. 等抓取/分析完成后，执行：

```powershell
cd vue_doubao
python update_snapshots.py
```

这个脚本会：
- 抓取“全部问题” + 每个具体问题的 `/api/stats` 数据
- 写入 `src/snapshots.json`
- 自动执行 `npm run build`

3. 推送到 GitHub：

```bash
git add .
git commit -m "Update daily snapshot"
git push origin main
```

4. 在服务器上拉取最新代码：

```bash
cd /home/doubao/vue_doubao
git pull origin main
```

然后刷新网页即可看到新数据。

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
