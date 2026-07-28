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

项目根目录下提供了 `deploy_vue_doubao.ps1`，默认会部署到 `117.55.234.72:8765`。

```powershell
# 在项目根目录执行
.\deploy_vue_doubao.ps1
```

第一次使用请在脚本开头修改 `User` 和 `Key`（SSH 登录用户名与私钥路径），或在命令行传入：

```powershell
.\deploy_vue_doubao.ps1 -User "root" -Key "$env:USERPROFILE\.ssh\id_rsa"
```

脚本会完成：构建 -> 上传 dist 到服务器 -> 在服务器启动 `python3 -m http.server 8765`。
