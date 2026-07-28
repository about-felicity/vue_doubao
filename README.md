# 豆包 Signal Desk

新版实时面板使用 Vue 3 + Vite 构建，生产文件由根目录的
`doubao_dashboard_server.py` 直接提供。

## 本地开发

```powershell
cd dashboard_v2
npm.cmd install
npm.cmd run dev
```

Vite 开发服务器需要把 `/api` 请求代理到 Python 服务时，可直接以生产构建
方式联调：

```powershell
npm.cmd run build
cd ..
python doubao_dashboard_server.py
```

打开 <http://127.0.0.1:8765/> 查看新版面板。旧版临时保留在
<http://127.0.0.1:8765/legacy>，便于核对数据口径。

## 目录

- `src/App.vue`：页面结构、状态与接口交互
- `src/styles.css`：完整视觉系统与响应式规则
- `dist/`：已编译的生产文件，Python 服务直接读取
