function Start-GSDriveFileUpload {
    [cmdletbinding()]
    Param
    (
        [parameter(Mandatory = $true,Position = 0,ValueFromPipeline = $true,ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [ValidateScript({Test-Path $_})]
        [String[]]
        $Path,
        [parameter(Mandatory = $false)]
        [String]
        $Name,
        [parameter(Mandatory = $false)]
        [String]
        $Description,
        [parameter(Mandatory = $false)]
        [String[]]
        $Parents,
        [parameter(Mandatory = $false)]
        [Switch]
        $Recurse,
        [parameter(Mandatory = $false)]
        [Switch]
        $Wait,
        [parameter(Mandatory = $false)]
        [Int]
        $RetryCount = 10,
        [parameter(Mandatory = $false)]
        [ValidateRange(1,200)]
        [Int]
        $ThrottleLimit = 20,
        [parameter(Mandatory = $false,ValueFromPipelineByPropertyName = $true)]
        [Alias('Owner','PrimaryEmail','UserKey','Mail')]
        [string]
        $User = $Script:PSGSuite.AdminEmail
    )
    Begin {
        if ($User -ceq 'me') {
            $User = $Script:PSGSuite.AdminEmail
        }
        elseif ($User -notlike "*@*.*") {
            $User = "$($User)@$($Script:PSGSuite.Domain)"
        }
        $serviceParams = @{
            Scope       = 'https://www.googleapis.com/auth/drive'
            ServiceType = 'Google.Apis.Drive.v3.DriveService'
            User        = $User
        }
        $service = New-GoogleService @serviceParams
        $taskList = [System.Collections.ArrayList]@()
        $fullTaskList = [System.Collections.ArrayList]@()
        $start = Get-Date
        $folIdHash = @{}
        $throttleCount = 0
        $totalThrottleCount = 0
    }
    Process {
        try {
            foreach ($file in $Path) {
                $details = Get-Item $file
                if ($details.PSIsContainer) {
                    $newFolPerms = @{
                        Name = $details.Name
                        Type = 'DriveFolder'
                        Verbose = $false
                    }
                    if ($PSBoundParameters.Keys -contains 'Parents') {
                        $newFolPerms['Parents'] = $PSBoundParameters['Parents']
                    }
                    Write-Verbose "Creating new Drive folder '$($details.Name)'"
                    $id = New-GSDriveFile @newFolPerms | Select-Object -ExpandProperty Id
                    $folIdHash[$details.FullName] = $id
                    if ($Recurse) {
                        $recurseList = Get-ChildItem $details.FullName -Recurse
                        $recDirs = $recurseList | Where-Object {$_.PSIsContainer} | Sort-Object FullName
                        if ($recDirs) {
                            Write-Verbose "Creating recursive folder structure under '$($details.Name)'"
                            $recDirs | ForEach-Object {
                                $parPath = "$(Split-Path $_.FullName -Parent)"
                                $newFolPerms = @{
                                    Name = $_.Name
                                    Type = 'DriveFolder'
                                    Parents = [String[]]$folIdHash[$parPath]
                                    Verbose = $false
                                }
                                $id = New-GSDriveFile @newFolPerms | Select-Object -ExpandProperty Id
                                $folIdHash[$_.FullName] = $id
                            }
                        }
                        $details = $recurseList | Where-Object {!$_.PSIsContainer} | Sort-Object FullName
                        $checkFolIdHash = $true
                        $totalFiles = $details.Count
                    }
                }
                else {
                    $checkFolIdHash = $false
                }
                foreach ($detPart in $details) {
                    $throttleCount++
                    $contentType = Get-MimeType $detPart
                    $body = New-Object 'Google.Apis.Drive.v3.Data.File' -Property @{
                        Name = [String]$detPart.Name
                    }
                    if (!$checkFolIdHash -and ($PSBoundParameters.Keys -contains 'Parents')) {
                        if ($Parents) {
                            $body.Parents = [String[]]$Parents
                        }
                    }
                    elseif ($checkFolIdHash) {
                        $parPath = "$(Split-Path $detPart.FullName -Parent)"
                        $body.Parents = [String[]]$folIdHash[$parPath]
                    }
                    if ($Description) {
                        $body.Description = $Description
                    }
                    $stream = New-Object 'System.IO.FileStream' $detPart.FullName,'Open','Read'
                    $request = $service.Files.Create($body,$stream,$contentType)
                    $request.QuotaUser = $User
                    $request.SupportsTeamDrives = $true
                    $request.ChunkSize = 512KB
                    $upload = $request.UploadAsync()
                    $task = $upload.ContinueWith([System.Action[System.Threading.Tasks.Task]]{$stream.Dispose()})
                    Write-Verbose "[$($detPart.Name)] Upload Id $($upload.Id) has started"
                    if (!$Script:DriveUploadTasks) {
                        $Script:DriveUploadTasks = [System.Collections.ArrayList]@()
                    }
                    $script:DriveUploadTasks += [PSCustomObject]@{
                        Id = $upload.Id
                        File = $detPart
                        Length = $detPart.Length
                        SizeInMB = [Math]::Round(($detPart.Length/1MB),2,[MidPointRounding]::AwayFromZero)
                        StartTime = $(Get-Date)
                        Parents = $body.Parents
                        User = $User
                        Upload = $upload
                        Request = $request
                    }
                    $taskList += [PSCustomObject]@{
                        Id = $upload.Id
                        File = $detPart
                        SizeInMB = [Math]::Round(($detPart.Length/1MB),2,[MidPointRounding]::AwayFromZero)
                        User = $User
                    }
                    $fullTaskList += [PSCustomObject]@{
                        Id = $upload.Id
                        File = $detPart
                        SizeInMB = [Math]::Round(($detPart.Length/1MB),2,[MidPointRounding]::AwayFromZero)
                        User = $User
                    }
                    if ($throttleCount -ge $ThrottleLimit) {
                        $totalThrottleCount += $throttleCount
                        if ($Wait) {
                            do {
                                $i = 1
                                $statusList = Get-GSDriveFileUploadStatus -Id $taskList.Id
                                $totalPercent = 0
                                $totalSecondsRemaining = 0
                                $count = 0
                                $statusList | ForEach-Object {
                                    $count++
                                    $totalPercent += $_.PercentComplete
                                    $totalSecondsRemaining += $_.Remaining.TotalSeconds
                                }
                                $totalPercent = $totalPercent / $count
                                $totalSecondsRemaining = $totalSecondsRemaining / $count
                                $parentParams = @{
                                    Activity = "[$([Math]::Round($totalPercent,4))%] Uploading [$totalThrottleCount / $totalFiles] files to Google Drive"
                                    SecondsRemaining = $($statusList.Remaining.TotalSeconds | Sort-Object | Select-Object -Last 1)
                                }
                                if (!($statusList | Where-Object {$_.Status -ne "Completed"})) {
                                    $parentParams['Completed'] = $true
                                }
                                else {
                                    $parentParams['PercentComplete'] = [Math]::Round($totalPercent,4)
                                }
                                if ($psEditor -or $IsMacOS -or $IsLinux) {
                                    Write-InlineProgress @parentParams
                                }
                                else {
                                    $parentParams['Id'] = 1
                                    Write-Progress @parentParams
                                }
                                if (!$psEditor -and !$IsMacOS -and !$IsLinux -and ($statusList.Count -le 10)) {
                                    foreach ($status in $statusList) {
                                        $i++
                                        $statusFmt = if ($status.Status -eq "Completed") {
                                            "Completed uploading"
                                        }
                                        else {
                                            $status.Status
                                        }
                                        $progParams = @{
                                            Activity = "[$($status.PercentComplete)%] [ID: $($status.Id)] $($statusFmt) file '$($status.File.FullName)' to Google Drive$(if($Parents){" (Parents: '$($Parents -join "', '")')"})"
                                            SecondsRemaining = $status.Remaining.TotalSeconds
                                            Id = $i
                                            ParentId = 1
                                        }
                                        if ($_.Status -eq "Completed") {
                                            $progParams['Completed'] = $true
                                        }
                                        else {
                                            $progParams['PercentComplete'] = [Math]::Round($status.PercentComplete,4)
                                        }
                                        Write-Progress @progParams
                                    }
                                }
                            }
                            until (!($statusList | Where-Object {$_.Status -notin @("Failed","Completed")}))
                            $throttleCount = 0
                            $taskList = [System.Collections.ArrayList]@()
                        }
                    }
                }
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
    End {
        if (!$Wait) {
            $fullTaskList
        }
        else {
            do {
                $i = 1
                $statusList = Get-GSDriveFileUploadStatus -Id $fullTaskList.Id
                $totalPercent = 0
                $totalSecondsRemaining = 0
                $count = 0
                $statusList | ForEach-Object {
                    $count++
                    $totalPercent += $_.PercentComplete
                    $totalSecondsRemaining += $_.Remaining.TotalSeconds
                }
                $totalPercent = $totalPercent / $count
                $totalSecondsRemaining = $totalSecondsRemaining / $count
                $parentParams = @{
                    Activity = "[$([Math]::Round($totalPercent,4))%] Uploading [$count / $count] files to Google Drive"
                    SecondsRemaining = $($statusList.Remaining.TotalSeconds | Sort-Object | Select-Object -Last 1)
                }
                if (!($statusList | Where-Object {$_.Status -ne "Completed"})) {
                    $parentParams['Completed'] = $true
                }
                else {
                    $parentParams['PercentComplete'] = [Math]::Round($totalPercent,4)
                }
                if ($psEditor -or $IsMacOS -or $IsLinux) {
                    Write-InlineProgress @parentParams
                }
                else {
                    $parentParams['Id'] = 1
                    Write-Progress @parentParams
                }
                if (!$psEditor -and !$IsMacOS -and !$IsLinux -and ($statusList.Count -le 10)) {
                    foreach ($status in $statusList) {
                        $i++
                        $statusFmt = if ($status.Status -eq "Completed") {
                            "Completed uploading"
                        }
                        else {
                            $status.Status
                        }
                        $progParams = @{
                            Activity = "[$($status.PercentComplete)%] [ID: $($status.Id)] $($statusFmt) file '$($status.File.FullName)' to Google Drive$(if($Parents){" (Parents: '$($Parents -join "', '")')"})"
                            SecondsRemaining = $status.Remaining.TotalSeconds
                            Id = $i
                            ParentId = 1
                        }
                        if ($_.Status -eq "Completed") {
                            $progParams['Completed'] = $true
                        }
                        else {
                            $progParams['PercentComplete'] = [Math]::Round($status.PercentComplete,4)
                        }
                        Write-Progress @progParams
                    }
                }
            }
            until (!($statusList | Where-Object {$_.Status -notin @("Failed","Completed")}))
            $fullStatusList = Get-GSDriveFileUploadStatus -Id $fullTaskList.Id
            $failedFiles = $fullStatusList | Where-Object {$_.Status -eq "Failed"}
            if (!$failedFiles) {
                Write-Verbose "All files uploaded to Google Drive successfully! Total time: $("{0:c}" -f ((Get-Date) - $start) -replace "\..*")"
            }
            elseif ($RetryCount) {
                $totalRetries = 0
                do {
                    $throttleCount = 0
                    $totalThrottleCount = 0
                    $taskList = [System.Collections.ArrayList]@()
                    $fullTaskList = [System.Collections.ArrayList]@()
                    $details = Get-Item $failedFiles.File
                    $totalFiles = $details.Count
                    $totalRetries++
                    Write-Verbose "~ ~ ~ RETRYING [$totalFiles] FAILED FILES [Retry # $totalRetries / $RetryCount] ~ ~ ~"
                    $details = Get-Item $failedFiles.File
                    foreach ($detPart in $details) {
                        $throttleCount++
                        $contentType = Get-MimeType $detPart
                        $body = New-Object 'Google.Apis.Drive.v3.Data.File' -Property @{
                            Name = [String]$detPart.Name
                        }
                        $parPath = "$(Split-Path $detPart.FullName -Parent)"
                        $body.Parents = [String[]]$folIdHash[$parPath]
                        if ($Description) {
                            $body.Description = $Description
                        }
                        $stream = New-Object 'System.IO.FileStream' $detPart.FullName,'Open','Read'
                        $request = $service.Files.Create($body,$stream,$contentType)
                        $request.QuotaUser = $User
                        $request.SupportsTeamDrives = $true
                        $request.ChunkSize = 512KB
                        $upload = $request.UploadAsync()
                        $task = $upload.ContinueWith([System.Action[System.Threading.Tasks.Task]]{$stream.Dispose()})
                        Write-Verbose "[$($detPart.Name)] Upload Id $($upload.Id) has started"
                        if (!$Script:DriveUploadTasks) {
                            $Script:DriveUploadTasks = [System.Collections.ArrayList]@()
                        }
                        $script:DriveUploadTasks += [PSCustomObject]@{
                            Id = $upload.Id
                            File = $detPart
                            Length = $detPart.Length
                            SizeInMB = [Math]::Round(($detPart.Length/1MB),2,[MidPointRounding]::AwayFromZero)
                            StartTime = $(Get-Date)
                            Parents = $body.Parents
                            User = $User
                            Upload = $upload
                            Request = $request
                        }
                        $taskList += [PSCustomObject]@{
                            Id = $upload.Id
                            File = $detPart
                            SizeInMB = [Math]::Round(($detPart.Length/1MB),2,[MidPointRounding]::AwayFromZero)
                            User = $User
                        }
                        $fullTaskList += [PSCustomObject]@{
                            Id = $upload.Id
                            File = $detPart
                            SizeInMB = [Math]::Round(($detPart.Length/1MB),2,[MidPointRounding]::AwayFromZero)
                            User = $User
                        }
                        if ($throttleCount -ge $ThrottleLimit) {
                            $totalThrottleCount += $throttleCount
                            if ($Wait) {
                                do {
                                    $i = 1
                                    $statusList = Get-GSDriveFileUploadStatus -Id $taskList.Id
                                    $totalPercent = 0
                                    $totalSecondsRemaining = 0
                                    $count = 0
                                    $statusList | ForEach-Object {
                                        $count++
                                        $totalPercent += $_.PercentComplete
                                        $totalSecondsRemaining += $_.Remaining.TotalSeconds
                                    }
                                    $totalPercent = $totalPercent / $count
                                    $totalSecondsRemaining = $totalSecondsRemaining / $count
                                    $parentParams = @{
                                        Activity = "[$([Math]::Round($totalPercent,4))%] Retrying upload of [$totalThrottleCount / $totalFiles] files to Google Drive"
                                        SecondsRemaining = $($statusList.Remaining.TotalSeconds | Sort-Object | Select-Object -Last 1)
                                    }
                                    if (!($statusList | Where-Object {$_.Status -ne "Completed"})) {
                                        $parentParams['Completed'] = $true
                                    }
                                    else {
                                        $parentParams['PercentComplete'] = [Math]::Round($totalPercent,4)
                                    }
                                    if ($psEditor -or $IsMacOS -or $IsLinux) {
                                        Write-InlineProgress @parentParams
                                    }
                                    else {
                                        $parentParams['Id'] = 1
                                        Write-Progress @parentParams
                                    }
                                    if (!$psEditor -and !$IsMacOS -and !$IsLinux -and ($statusList.Count -le 10)) {
                                        foreach ($status in $statusList) {
                                            $i++
                                            $statusFmt = if ($status.Status -eq "Completed") {
                                                "Completed uploading"
                                            }
                                            else {
                                                $status.Status
                                            }
                                            $progParams = @{
                                                Activity = "[$($status.PercentComplete)%] [ID: $($status.Id)] $($statusFmt) file '$($status.File.FullName)' to Google Drive$(if($Parents){" (Parents: '$($Parents -join "', '")')"})"
                                                SecondsRemaining = $status.Remaining.TotalSeconds
                                                Id = $i
                                                ParentId = 1
                                            }
                                            if ($_.Status -eq "Completed") {
                                                $progParams['Completed'] = $true
                                            }
                                            else {
                                                $progParams['PercentComplete'] = [Math]::Round($status.PercentComplete,4)
                                            }
                                            Write-Progress @progParams
                                        }
                                    }
                                }
                                until (!($statusList | Where-Object {$_.Status -notin @("Failed","Completed")}))
                                $throttleCount = 0
                                $taskList = [System.Collections.ArrayList]@()
                            }
                        }
                    }
                    do {
                        $i = 1
                        $statusList = Get-GSDriveFileUploadStatus -Id $fullTaskList.Id
                        $totalPercent = 0
                        $totalSecondsRemaining = 0
                        $count = 0
                        $statusList | ForEach-Object {
                            $count++
                            $totalPercent += $_.PercentComplete
                            $totalSecondsRemaining += $_.Remaining.TotalSeconds
                        }
                        $totalPercent = $totalPercent / $count
                        $totalSecondsRemaining = $totalSecondsRemaining / $count
                        $parentParams = @{
                            Activity = "[$([Math]::Round($totalPercent,4))%] Retrying upload of [$count / $count] files to Google Drive"
                            SecondsRemaining = $($statusList.Remaining.TotalSeconds | Sort-Object | Select-Object -Last 1)
                        }
                        if (!($statusList | Where-Object {$_.Status -ne "Completed"})) {
                            $parentParams['Completed'] = $true
                        }
                        else {
                            $parentParams['PercentComplete'] = [Math]::Round($totalPercent,4)
                        }
                        if ($psEditor -or $IsMacOS -or $IsLinux) {
                            Write-InlineProgress @parentParams
                        }
                        else {
                            $parentParams['Id'] = 1
                            Write-Progress @parentParams
                        }
                        if (!$psEditor -and !$IsMacOS -and !$IsLinux -and ($statusList.Count -le 10)) {
                            foreach ($status in $statusList) {
                                $i++
                                $statusFmt = if ($status.Status -eq "Completed") {
                                    "Completed uploading"
                                }
                                else {
                                    $status.Status
                                }
                                $progParams = @{
                                    Activity = "[$($status.PercentComplete)%] [ID: $($status.Id)] $($statusFmt) file '$($status.File.FullName)' to Google Drive$(if($Parents){" (Parents: '$($Parents -join "', '")')"})"
                                    SecondsRemaining = $status.Remaining.TotalSeconds
                                    Id = $i
                                    ParentId = 1
                                }
                                if ($_.Status -eq "Completed") {
                                    $progParams['Completed'] = $true
                                }
                                else {
                                    $progParams['PercentComplete'] = [Math]::Round($status.PercentComplete,4)
                                }
                                Write-Progress @progParams
                            }
                        }
                    }
                    until (!($statusList | Where-Object {$_.Status -notin @("Failed","Completed")}))
                    $fullStatusList = Get-GSDriveFileUploadStatus -Id $fullTaskList.Id
                    $failedFiles = $fullStatusList | Where-Object {$_.Status -eq "Failed"}
                }
                until (!$failedFiles -or ($totalRetries -ge $RetryCount))
                if ($failedFiles) {
                    Write-Warning "The following files failed to upload:`n`n$($failedFiles | Select-Object Id,Status,Exception,File | Format-List | Out-String)"
                }
                elseif (!$failedFiles) {
                    Write-Verbose "All files uploaded to Google Drive successfully! Total time: $("{0:c}" -f ((Get-Date) - $start) -replace "\..*")"
                }
            }
            [Console]::CursorVisible = $true
        }
    }
}