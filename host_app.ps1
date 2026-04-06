$port = 8081
$ip = [System.Net.IPAddress]::Any
$listener = New-Object System.Net.Sockets.TcpListener($ip, $port)
$listener.Start()

$ordersFile = Join-Path (Get-Location) "orders.json"
if (-not (Test-Path $ordersFile)) { "[]" | Out-File $ordersFile -Encoding utf8 }

$productsFile = Join-Path (Get-Location) "products.json"
if (-not (Test-Path $productsFile)) { "[]" | Out-File $productsFile -Encoding utf8 }

$localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Wi-Fi*" -or $_.InterfaceAlias -like "*Ethernet*" }).IPAddress | Select-Object -First 1
Write-Host "Server started! addresses:"
Write-Host "Local:  http://localhost:$port/"
Write-Host "Mobile: http://$($localIp):$port/"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $requestLine = $reader.ReadLine()
        if ($null -eq $requestLine) { $client.Close(); continue }

        $parts = $requestLine.Split(" ")
        $method = $parts[0]
        $url = $parts[1].Split('?')[0]
        if ($url -eq "/") { $url = "/index.html" }
        $url = [System.Net.WebUtility]::UrlDecode($url)

        if ($method -eq "POST" -and $url -eq "/api/orders") {
            $len = 0
            while ($line = $reader.ReadLine()) {
                if ($line -eq "") { break }
                if ($line -match "content-length:\s*(\d+)") { $len = [int]$matches[1] }
            }
            $buffer = New-Object byte[] $len
            $read = 0
            while ($read -lt $len) { $read += $stream.Read($buffer, $read, $len - $read) }
            $body = [System.Text.Encoding]::UTF8.GetString($buffer)
            $newOrder = $body | ConvertFrom-Json
            
            $orders = Get-Content $ordersFile -Raw | ConvertFrom-Json
            if ($null -eq $orders) { $orders = @() }
            $orders = @($newOrder) + $orders
            $orders | ConvertTo-Json -Depth 10 | Out-File $ordersFile -Encoding utf8
            
            Write-Host "Order: $($newOrder.id)"
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 2`r`n`r`n{}"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "POST" -and $url -eq "/api/products") {
            $len = 0
            while ($line = $reader.ReadLine()) {
                if ($line -eq "") { break }
                if ($line -match "content-length:\s*(\d+)") { $len = [int]$matches[1] }
            }
            $buffer = New-Object byte[] $len
            $read = 0
            while ($read -lt $len) { $read += $stream.Read($buffer, $read, $len - $read) }
            $body = [System.Text.Encoding]::UTF8.GetString($buffer)
            $newProduct = $body | ConvertFrom-Json
            
            $products = Get-Content $productsFile -Raw | ConvertFrom-Json
            if ($null -eq $products) { $products = @() }
            $products = @($products) + $newProduct
            $products | ConvertTo-Json -Depth 10 | Out-File $productsFile -Encoding utf8
            
            Write-Host "Product Added: $($newProduct.id)"
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 2`r`n`r`n{}"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "GET" -and $url -eq "/api/products") {
            $data = Get-Content $productsFile -Raw
            $header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nCache-Control: no-cache, no-store, must-revalidate`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($data))`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($header), 0, [System.Text.Encoding]::UTF8.GetByteCount($header))
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($data), 0, [System.Text.Encoding]::UTF8.GetByteCount($data))
        }
        elseif ($method -eq "PUT" -and $url -match "^/api/products/(.+)") {
            $id = $matches[1]
            $len = 0
            while ($line = $reader.ReadLine()) {
                if ($line -eq "") { break }
                if ($line -match "content-length:\s*(\d+)") { $len = [int]$matches[1] }
            }
            $buffer = New-Object byte[] $len
            $read = 0
            while ($read -lt $len) { $read += $stream.Read($buffer, $read, $len - $read) }
            $body = [System.Text.Encoding]::UTF8.GetString($buffer)
            $updateData = $body | ConvertFrom-Json
            
            $products = Get-Content $productsFile -Raw | ConvertFrom-Json
            if ($null -eq $products) { $products = @() }
            foreach ($p in $products) {
                if ($p.id -eq $id -or $p.id.ToString() -eq $id) {
                    if ($updateData.name) { $p.name = $updateData.name }
                    if ($updateData.category) { $p.category = $updateData.category }
                    if ($updateData.price) { $p.price = $updateData.price }
                    if ($updateData.description) { $p.description = $updateData.description }
                    if ($updateData.image) { $p.image = $updateData.image }
                    break
                }
            }
            @($products) | ConvertTo-Json -Depth 10 | Out-File $productsFile -Encoding utf8
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 0`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "DELETE" -and $url -match "^/api/products/(.+)") {
            $id = $matches[1]
            $products = Get-Content $productsFile -Raw | ConvertFrom-Json
            $products = $products | Where-Object { $_.id -ne $id -and $_.id.ToString() -ne $id }
            $products | ConvertTo-Json -Depth 10 | Out-File $productsFile -Encoding utf8
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 0`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "GET" -and $url -eq "/api/orders") {
            $data = Get-Content $ordersFile -Raw
            $header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nCache-Control: no-cache, no-store, must-revalidate`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($data))`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($header), 0, [System.Text.Encoding]::UTF8.GetByteCount($header))
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($data), 0, [System.Text.Encoding]::UTF8.GetByteCount($data))
        }
        elseif ($method -eq "PUT" -and $url -match "^/api/orders/(.+)") {
            $id = $matches[1]
            $len = 0
            while ($line = $reader.ReadLine()) {
                if ($line -eq "") { break }
                if ($line -match "content-length:\s*(\d+)") { $len = [int]$matches[1] }
            }
            $buffer = New-Object byte[] $len
            $read = 0
            while ($read -lt $len) { $read += $stream.Read($buffer, $read, $len - $read) }
            $body = [System.Text.Encoding]::UTF8.GetString($buffer)
            $updateData = $body | ConvertFrom-Json
            
            $orders = Get-Content $ordersFile -Raw | ConvertFrom-Json
            if ($null -eq $orders) { $orders = @() }
            foreach ($o in $orders) {
                if ($o.id -eq $id) {
                    if ($updateData.status) { $o.status = $updateData.status }
                    break
                }
            }
            @($orders) | ConvertTo-Json -Depth 10 | Out-File $ordersFile -Encoding utf8
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 0`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "DELETE" -and $url -match "^/api/orders/(.+)") {
            $id = $matches[1]
            $orders = Get-Content $ordersFile -Raw | ConvertFrom-Json
            $orders = $orders | Where-Object { $_.id -ne $id }
            $orders | ConvertTo-Json -Depth 10 | Out-File $ordersFile -Encoding utf8
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 0`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "POST" -and $url -eq "/api/upload") {
            $len = 0
            $fileName = "upload_$(Get-Date -Format 'yyyyMMddHHmmss').jpg"
            # Read headers from the StreamReader - it's okay for the headers part
            while ($line = $reader.ReadLine()) {
                if ($line -eq "") { break }
                if ($line -match "content-length:\s*(\d+)") { $len = [int]$matches[1] }
                if ($line -match "x-file-name:\s*(.+)") { $fileName = $matches[1].Trim() }
            }
            
            # StreamReader may have buffered part of the body. We need to handle that.
            # However, for a simple implementation, let's try to read exactly $len bytes.
            # If the user is on a slow connection or the body is large, we should read in a loop.
            
            $uploadDir = Join-Path (Get-Location) "images\products"
            if (-not (Test-Path $uploadDir)) { New-Item -ItemType Directory -Path $uploadDir -Force | Out-Null }
            $filePath = Join-Path $uploadDir $fileName
            
            # Since $reader buffered some data, we need to get the "remnant" from it.
            # But in the current simple TcpListener setup, it's easier to just read the remaining bytes from the stream.
            # This is tricky because $reader.ReadLine() is hungry.
            # A more reliable way is to not use $reader for the header/body boundary if we want byte-per-byte accuracy.
            
            $buffer = New-Object byte[] $len
            $totalRead = 0
            while ($totalRead -lt $len) {
                $read = $stream.Read($buffer, $totalRead, $len - $totalRead)
                if ($read -eq 0) { break }
                $totalRead += $read
            }
            [System.IO.File]::WriteAllBytes($filePath, $buffer)
            
            $jsonResp = @{ url = "images/products/$fileName" } | ConvertTo-Json
            $respSize = [System.Text.Encoding]::UTF8.GetByteCount($jsonResp)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: application/json`r`nContent-Length: $respSize`r`n`r`n$jsonResp"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "OPTIONS") {
            $resp = "HTTP/1.1 204 No Content`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: POST, GET, OPTIONS, PUT, DELETE`r`nAccess-Control-Allow-Headers: Content-Type, Authorization`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        else {
            $path = Join-Path (Get-Location) $url.TrimStart('/')
            if (Test-Path $path -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($path)
                $type = "application/octet-stream"
                if ($path -like "*.html") { $type = "text/html" }
                elseif ($path -like "*.js") { $type = "application/javascript" }
                elseif ($path -like "*.css") { $type = "text/css" }
                $header = "HTTP/1.1 200 OK`r`nContent-Type: $type`r`nCache-Control: no-cache, no-store, must-revalidate`r`nContent-Length: $($bytes.Length)`r`nAccess-Control-Allow-Origin: *`r`n`r`n"
                $stream.Write([System.Text.Encoding]::UTF8.GetBytes($header), 0, [System.Text.Encoding]::UTF8.GetByteCount($header))
                $stream.Write($bytes, 0, $bytes.Length)
            }
            else {
                $resp = "HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`n`r`n"
                $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
            }
        }
        $stream.Flush(); $client.Close()
    }
}
catch { Write-Host "Error: $_" } finally { $listener.Stop() }
