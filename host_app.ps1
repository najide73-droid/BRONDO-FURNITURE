$port = 8081
$ip = [System.Net.IPAddress]::Any
$listener = New-Object System.Net.Sockets.TcpListener($ip, $port)
$listener.Start()

$ordersFile = Join-Path (Get-Location) "orders.json"
if (-not (Test-Path $ordersFile)) { "[]" | Out-File $ordersFile -Encoding utf8 }

$productsFile = Join-Path (Get-Location) "products.json"
if (-not (Test-Path $productsFile)) { "[]" | Out-File $productsFile -Encoding utf8 }

$categoriesFile = Join-Path (Get-Location) "categories.json"
if (-not (Test-Path $categoriesFile)) {
    '[{"name":"Wall Decors","image":""},{"name":"Frames","image":""},{"name":"Statues","image":""},{"name":"Clocks","image":""}]' | Out-File $categoriesFile -Encoding utf8
}

$historyFile = Join-Path (Get-Location) "order_history.json"
if (-not (Test-Path $historyFile)) { "[]" | Out-File $historyFile -Encoding utf8 }

$localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Wi-Fi*" -or $_.InterfaceAlias -like "*Ethernet*" }).IPAddress | Select-Object -First 1
Write-Host "Server started! addresses:"
Write-Host "Local:  http://localhost:$port/"
Write-Host "Mobile: http://$($localIp):$port/"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000
        
        $buffer = New-Object byte[] 8192
        try {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -eq 0) { $client.Close(); continue }
            $headerText = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        } catch {
            $client.Close(); continue
        }

        $lines = $headerText.Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($lines.Count -eq 0) { $client.Close(); continue }
        
        $requestLine = $lines[0]
        $parts = $requestLine.Split(" ")
        if ($parts.Count -lt 2) { $client.Close(); continue }
        
        $method = $parts[0]
        $url = $parts[1].Split('?')[0]
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - $method $url"
        if ($url -eq "/") { $url = "/index.html" }
        $url = [System.Net.WebUtility]::UrlDecode($url)
        
        $contentLength = 0
        $fileName = "upload_$(Get-Date -Format 'yyyyMMddHHmmss').jpg"
        foreach ($line in $lines) {
            if ($line -match "content-length:\s*(\d+)") { $contentLength = [int]$matches[1] }
            if ($line -match "x-file-name:\s*(.+)") { $fileName = $matches[1].Trim() }
        }

        # Handle body if it wasn't fully read in the first chunk
        $bodyBytes = @()
        if ($method -eq "POST" -or $method -eq "PUT") {
            $headerEndIndex = $headerText.IndexOf("`r`n`r`n")
            if ($headerEndIndex -ge 0) {
                # Some body might be in the first chunk
                $headerSize = [System.Text.Encoding]::UTF8.GetByteCount($headerText.Substring(0, $headerEndIndex + 4))
                $initialBodySize = $read - $headerSize
                if ($initialBodySize -gt 0) {
                    $bodyBytes = $buffer[$headerSize..($read-1)]
                }
            }
            # Read remaining body
            while ($bodyBytes.Count -lt $contentLength) {
                $remBuffer = New-Object byte[] 8192
                $remRead = $stream.Read($remBuffer, 0, $remBuffer.Length)
                if ($remRead -eq 0) { break }
                $bodyBytes += $remBuffer[0..($remRead-1)]
            }
        }

        if ($method -eq "POST" -and $url -eq "/api/orders") {
            $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
            $newOrder = $body | ConvertFrom-Json
            $orders = Get-Content $ordersFile -Raw | ConvertFrom-Json
            if ($null -eq $orders) { $orders = @() }
            $orders = @($newOrder) + $orders
            $json = $orders | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($ordersFile, $json)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 2`r`n`r`n{}"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "GET" -and $url -eq "/api/orders") {
            $data = Get-Content $ordersFile -Raw
            if ($null -eq $data -or $data.Trim() -eq "") { $data = "[]" }
            $header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($data))`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($header), 0, [System.Text.Encoding]::UTF8.GetByteCount($header))
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($data), 0, [System.Text.Encoding]::UTF8.GetByteCount($data))
        }
        elseif ($method -eq "GET" -and $url -eq "/api/order-history") {
            $data = Get-Content $historyFile -Raw
            if ($null -eq $data -or $data.Trim() -eq "") { $data = "[]" }
            $header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($data))`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($header), 0, [System.Text.Encoding]::UTF8.GetByteCount($header))
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($data), 0, [System.Text.Encoding]::UTF8.GetByteCount($data))
        }
        elseif ($method -eq "PUT" -and $url -match "^/api/orders/(.+)") {
            $orderId = [System.Net.WebUtility]::UrlDecode($matches[1])
            $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
            $update = $body | ConvertFrom-Json
            $orders = Get-Content $ordersFile -Raw | ConvertFrom-Json
            if ($null -eq $orders) { $orders = @() }
            $orders = @($orders) | ForEach-Object {
                if ($_.id -eq $orderId) { $_.status = $update.status }
                $_
            }
            $json = $orders | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($ordersFile, $json)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 2`r`n`r`n{}"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "POST" -and $url -eq "/api/products") {
            $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
            $newProduct = $body | ConvertFrom-Json
            $products = Get-Content $productsFile -Raw | ConvertFrom-Json
            if ($null -eq $products) { $products = @() }
            $products = @($products) | Where-Object { $_.id.ToString() -ne $newProduct.id.ToString() }
            $products = @($products) + $newProduct
            $json = $products | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($productsFile, $json)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 2`r`n`r`n{}"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "GET" -and $url -eq "/api/products") {
            $data = Get-Content $productsFile -Raw
            if ($null -eq $data -or $data.Trim() -eq "") { $data = "[]" }
            $header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($data))`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($header), 0, [System.Text.Encoding]::UTF8.GetByteCount($header))
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($data), 0, [System.Text.Encoding]::UTF8.GetByteCount($data))
        }
        elseif ($method -eq "PUT" -and $url -match "^/api/products/(.+)") {
            $productId = [System.Net.WebUtility]::UrlDecode($matches[1])
            $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
            $update = $body | ConvertFrom-Json
            $products = Get-Content $productsFile -Raw | ConvertFrom-Json
            if ($null -eq $products) { $products = @() }
            $products = @($products) | ForEach-Object {
                if ($_.id -eq $productId) { 
                    $_.image = $update.image 
                }
                $_
            }
            $json = $products | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($productsFile, $json)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 2`r`n`r`n{}"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "GET" -and $url -eq "/api/categories") {
            $data = Get-Content $categoriesFile -Raw
            if ($null -eq $data -or $data.Trim() -eq "") { $data = "[]" }
            $header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($data))`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($header), 0, [System.Text.Encoding]::UTF8.GetByteCount($header))
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($data), 0, [System.Text.Encoding]::UTF8.GetByteCount($data))
        }
        elseif ($method -eq "POST" -and $url -eq "/api/categories") {
            $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
            $newCat = $body | ConvertFrom-Json
            $categories = Get-Content $categoriesFile -Raw | ConvertFrom-Json
            if ($null -eq $categories) { $categories = @() }
            $categories = @($categories) | Where-Object { $_.name -ne $newCat.name }
            $categories = @($categories) + $newCat
            $json = $categories | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($categoriesFile, $json)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 2`r`n`r`n{}"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "DELETE" -and $url -match "^/api/categories/(.+)") {
            $name = [System.Net.WebUtility]::UrlDecode($matches[1])
            $categories = Get-Content $categoriesFile -Raw | ConvertFrom-Json
            if ($null -eq $categories) { $categories = @() }
            $categories = @($categories) | Where-Object { $_.name -ne $name }
            $json = $categories | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($categoriesFile, $json)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 0`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "DELETE" -and $url -match "^/api/orders/(.+)") {
            $orderId = [System.Net.WebUtility]::UrlDecode($matches[1])
            Write-Host "Attempting to delete order: $orderId"
            $orders = Get-Content $ordersFile -Raw | ConvertFrom-Json
            if ($null -eq $orders) { $orders = @() }
            
            # Archive to history
            $toArchive = @($orders) | Where-Object { $_.id.ToString().Trim() -eq $orderId.Trim() }
            if ($null -ne $toArchive) {
                $history = Get-Content $historyFile -Raw | ConvertFrom-Json
                if ($null -eq $history) { $history = @() }
                $history = @($toArchive) + $history
                $historyJson = $history | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($historyFile, $historyJson)
            }

            $orders = @($orders) | Where-Object { $_.id.ToString().Trim() -ne $orderId.Trim() }
            $json = $orders | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($ordersFile, $json)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 0`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "DELETE" -and $url -eq "/api/order-history") {
            Write-Host "Clearing all order history"
            "[]" | Out-File $historyFile -Encoding utf8
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 0`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "DELETE" -and $url -match "^/api/products/(.+)") {
            $productId = [System.Net.WebUtility]::UrlDecode($matches[1])
            $products = Get-Content $productsFile -Raw | ConvertFrom-Json
            if ($null -eq $products) { $products = @() }
            $products = @($products) | Where-Object { $_.id.ToString() -ne $productId }
            $json = $products | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($productsFile, $json)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: 0`r`n`r`n"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "POST" -and $url -eq "/api/upload") {
            $uploadDir = Join-Path (Get-Location) "images\products"
            if (-not (Test-Path $uploadDir)) { New-Item -ItemType Directory -Path $uploadDir -Force | Out-Null }
            $filePath = Join-Path $uploadDir $fileName
            [System.IO.File]::WriteAllBytes($filePath, $bodyBytes)
            $jsonResp = @{ url = "images/products/$fileName" } | ConvertTo-Json
            $respSize = [System.Text.Encoding]::UTF8.GetByteCount($jsonResp)
            $resp = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: application/json`r`nContent-Length: $respSize`r`n`r`n$jsonResp"
            $stream.Write([System.Text.Encoding]::UTF8.GetBytes($resp), 0, [System.Text.Encoding]::UTF8.GetByteCount($resp))
        }
        elseif ($method -eq "OPTIONS") {
            $resp = "HTTP/1.1 204 No Content`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: POST, GET, OPTIONS, PUT, DELETE`r`nAccess-Control-Allow-Headers: Content-Type, Authorization, X-File-Name`r`n`r`n"
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
                $header = "HTTP/1.1 200 OK`r`nContent-Type: $type`r`nAccess-Control-Allow-Origin: *`r`nContent-Length: $($bytes.Length)`r`n`r`n"
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
