# vue_doubao

营养健康客户的豆包信源面板纯静态版本。数据来自独立的 `customer_a`
范围，只包含“维生素B族哪个牌子好”和“辅酶Q10哪个牌子好”。
所有数据已写入 `src/snapshots.json`，公网页面不依赖本地 API。

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

1. 确保 `customer_a` 动态面板正在 `http://127.0.0.1:8766` 运行。
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

## 部署到 1any.top/custombjp

服务器克隆或更新仓库后执行：

```bash
cd /home/vue_doubao
git pull origin main
sudo bash deploy_custombjp.sh
```

脚本会自动拉取 GitHub 最新 `main`、建立带版本号的静态发布目录、把
路径安全地写入现有 `1any.top:443` Nginx 站点、校验配置并执行 HTTPS
健康检查。最终地址：

```text
https://1any.top/custombjp/
```

重复执行同一条命令即可更新快照，不会覆盖现有 `/customXL/` 路径。

## 旧版独立端口部署

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
