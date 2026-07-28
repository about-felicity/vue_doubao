# 一键部署 vue_doubao 静态面板到公网 117.55.234.72:8765
# 运行前请把下面的变量改成你自己的服务器登录信息
param(
    [string]$HostIP = "117.55.234.72",
    [int]$Port = 8765,
    [string]$User = "root",
    [string]$Key = "$env:USERPROFILE\.ssh\id_rsa",
    [string]$RemotePath = "/opt/vue_doubao/dist"
)

$ProjectDir = $PSScriptRoot
$DistDir = "$ProjectDir\dist"

Write-Host "[1/4] 开始构建..." -ForegroundColor Cyan
Set-Location $ProjectDir
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "构建失败" -ForegroundColor Red
    exit 1
}

Write-Host "[2/4] 上传静态文件到服务器..." -ForegroundColor Cyan
$sshArgs = "-i `"$Key`" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# 创建远程目录
ssh $sshArgs "$User@$HostIP" "mkdir -p $RemotePath"
# 上传 dist 内容
scp $sshArgs -r "$DistDir\*" "$User@${HostIP}:$RemotePath/"
if ($LASTEXITCODE -ne 0) {
    Write-Host "上传失败，请检查服务器地址、用户名和 SSH 密钥" -ForegroundColor Red
    exit 1
}

Write-Host "[3/4] 在服务器上启动/重启静态服务..." -ForegroundColor Cyan
# 关闭旧的 8765 端口服务（兼容 Python http.server 和之前的 doubao_dashboard_server）
ssh $sshArgs "$User@$HostIP" "pkill -f 'http.server $Port' 2>/dev/null; pkill -f 'doubao_dashboard_server' 2>/dev/null; sleep 1"
# 后台启动静态服务
ssh $sshArgs "$User@$HostIP" "nohup python3 -m http.server $Port --directory $RemotePath > /tmp/vue_doubao.log 2>&1 &"

Write-Host "[4/4] 等待服务启动..." -ForegroundColor Cyan
Start-Sleep -Seconds 2
$response = Invoke-WebRequest -Uri "http://${HostIP}:${Port}/" -UseBasicParsing -TimeoutSec 10
if ($response.StatusCode -eq 200) {
    Write-Host "部署成功: http://${HostIP}:${Port}/" -ForegroundColor Green
} else {
    Write-Host "部署可能失败，HTTP 状态: $($response.StatusCode)" -ForegroundColor Yellow
}
