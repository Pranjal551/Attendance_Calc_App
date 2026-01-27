Add-Type -AssemblyName System.Drawing
$width = 400
$height = 800
$steps = @("Step 1: Login to SAP", "Step 2: Go to Attendance Tab", "Step 3: Download PDF Report")

for ($i = 0; $i -lt 3; $i++) {
    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.Clear([System.Drawing.Color]::White)
    
    $font = New-Object System.Drawing.Font("Arial", 24, [System.Drawing.FontStyle]::Bold)
    $brush = [System.Drawing.Brushes]::Black
    $rect = New-Object System.Drawing.RectangleF(0, ($height / 2 - 50), $width, 100)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    
    $graphics.DrawString($steps[$i], $font, $brush, $rect, $format)
    $filename = "assets\guide\step" + ($i + 1) + ".png"
    $bmp.Save($filename, [System.Drawing.Imaging.ImageFormat]::Png)
    
    $graphics.Dispose()
    $bmp.Dispose()
}

Write-Host "Placeholder guide images created!" -ForegroundColor Green
Write-Host "Replace these files with actual screenshots:" -ForegroundColor Yellow
Write-Host "  - assets\guide\step1.png" -ForegroundColor Yellow
Write-Host "  - assets\guide\step2.png" -ForegroundColor Yellow
Write-Host "  - assets\guide\step3.png" -ForegroundColor Yellow
