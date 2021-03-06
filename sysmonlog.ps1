# 2016.01.11 0xH@jic
# Sysmon Powershell

Write-Host "End to [Ctrl + C]"
Add-Type -Assembly System.Windows.Forms

####### Parameters ##########
$Counter = 0
$EventLog = "SysmonLog2"
$HostName = $Env:COMPUTERNAME
$f = "Z:\sysmon1.csv" #Change to your CSV file
$SyslogServer="10.211.55.27" #Change to your Syslog Server IP
$Port = 514 #UDP port #Change to your Syslog Server Port

$Popup = $FALSE #For Desktop Message
$LocalCSV = $TRUE #For Save Sysmon As CSV
$Email = $FALSE #For Sending Email
$Syslog = $FALSE #For Sending Syslog
#############################

#Check Sysmon CSV File Exists OR Not. If Not, then Prepare New One with Header.
if($LocalCSV){
    if (Test-Path $f) {
            Write-Host $f is found!
        } else {
            Write-Host $f is not found!
            $head = "Host" + "," + "Date" + "," + "EventName" + "," + #Host Date EventName
	              "ProcessID" + "," + "CmdLine" + "," + "ParentPID" + "," + #ProcessId CmdLine ParentPID
	               "ParentCmd" + "," + "User" + "," + "Hash" + "," + #ParentCmd User Hash
	               "SourceIP" + "," + "SourcePort" + "," + "DestIP" + "," + #SourceIP SourcePort DestIP
	               "DestPort" + ","  #DestPort
            $head | Out-File $f -Encoding UTF8
        }
}
    
function AlertMail($content, $title){
    $EmailFrom = “xxxxx@gmail.com” 
    $EmailTo =”xxxxx@gmail.com” 
    $SMTPServer = "smtp.gmail.com" 
    $SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, 587) 
    $SMTPClient.EnableSsl = $true 
    $SMTPClient.Credentials = New-Object System.Net.NetworkCredential(“xxxxx@gmail.com”, "YourPswd”);
    $SMTPClient.Send($EmailFrom, $EmailTo, $title, $content)
}

function ShowMsg($title, $msg){
    [System.Windows.Forms.MessageBox]::Show(
    $title + 
    $msg +  "`n" + 
    "Check Symon Log in Detai OR Contact Admin","Possible APT","OK","Warning","button1")    
}

function SendSyslog([System.String]$SyslogMessage){

    Write-Host $SyslogServer
    Write-Host $SyslogMessage #Debug
        
    $Lib = "System.Net"
    $AssembliesName = [Appdomain]::CurrentDomain.GetAssemblies() | % {$_.GetName().Name}
    if( -not ($AssembliesName -contains $Lib)){
        [void][System.Reflection.Assembly]::LoadWithPartialName($Lib)
    }
    
    $ByteData = [System.Text.Encoding]::UTF8.GetBytes($SyslogMessage)
    #$ByteDate = [System.Text.Encoding]::Unicode.GetBytes($SyslogMessage)

    $UDPSocket = $null
    $UDPSocket = New-Object System.Net.Sockets.UdpClient($SyslogServer, $Port)

    if( $UDPSocket -ne $null ){
        [void]$UDPSocket.Send($ByteData, $ByteData.Length)

        $UDPSocket.Close()
    }
    
}

Register-WmiEvent -Query "SELECT * FROM __InstanceCreationEvent WHERE TargetInstance ISA 'Win32_NTLogEvent' AND TargetInstance.LogFile = 'Microsoft-Windows-Sysmon/Operational'" -SourceIdentifier $EventLog

Try{
	While ($True) {
		$NewEvent = Wait-Event -SourceIdentifier $EventLog
		$Log = $NewEvent.SourceEventArgs.NewEvent.TargetInstance
		$LogName  = $Log.LogFile
		$SourceName   = $Log.SourceName
        $Category = $Log.CategoryString
		$EventCode  = $Log.EventCode
		$TimeGenerated = $Log.TimeGenerated
		$Year =  $TimeGenerated.SubString(0, 4)
		$Month = $TimeGenerated.SubString(4, 2)
		$Day =  $TimeGenerated.SubString(6, 2)
		$Hour = $TimeGenerated.SubString(8, 2)
		$Minutes =  $TimeGenerated.SubString(10, 2)    
		$Date = $Year + "/" + $Month + "/" + $Day + " " + $Hour + ":" + $Minutes
		$Date = (([DateTime]$Date)).AddHours(9).ToString("yyyy/MM/dd HH:mm:ss")
		$Message = $Log.Message

		$Body = `
@"
$SourceName
$EventCode
$Date
$Message	
-----------------------------------------------	
"@
           
        $Category
        $EventCode #Process Create(1) Network Connect(3) Process Terminate(5)
        #Write-Host "----------------------" #Debug
        #$HostName
        #$Message
        #Write-Host "----------------------" #Debug

        #Detection Conditions By Process Create Event
		if($EventCode -eq 1)
        {
            #Debug $Message 
            
            $a = $Message -split "`r`n"
            #$a.Length
            #foreach($i in $a){Write-Host $i}
            #$a[3].SubString(11) #ProcessId
            #$a[4] #Image
            #$a[5] #CommandLine
            
            if($a[5].ToLower().Contains("quser")) #quser
            {
                Write-Host "####### APT APT quser executed!"
                $a[0]="APT (quser)"
                
                if($Popup){
                    $message = "`n" + $a[3] + "`n" + $a[4] + "`n" + $a[5] + "`n" 
                    ShowMsg("Following APT Command was Executed !`n", $message)
                }
                
                if($Email){
                     $Subject = $Env:COMPUTERNAME + " Sysmon Alert - APT Command Quser"
                     AlertMail($Body, $Subject)
                }
                
             }elseif($a[4].ToLower().Contains("powershell") -and $a[5].ToLower().Contains("hidden") -and 
                    $a[5].ToLower().Contains("-enc")){ #Encoded PowerShell
                    
                Write-Host "####### APT Encrypted Powershell Executed"
                $a[0]="APT (Encode PowerShell)"
                
                if($Popup){
                    $message = "`n" + $a[3] + "`n" + $a[4] + "`n" + $a[5] + "`n" 
                    ShowMsg("Possible APT PowerShell was Executed !`n", $message)
                }
                
                if($Email){
                     $Subject = $Env:COMPUTERNAME + " Sysmon Alert - APT PowerShell"
                     AlertMail($Body, $Subject)
                }
                
             }elseif($a[5].ToLower().Contains("netstat") -or $a[5].ToLower().Contains("whoami") -or 
                    $a[5].ToLower().Contains("net ") -or $a[5].ToLower().Contains("ipconfig")  -or 
                    $a[5].ToLower().Contains("systeminfo")) #Recon Commands
            {
                Write-Host "####### APT Recon Command Counter ++ !"
                $Counter++
                #Write-Host "Counter: " $Counter
                if($Counter -gt 3)
                {
                    #TODO If Parent Image is IIS, Show other message
                    Write-Host "####### APT Possible Recon Command Executed!" #Debug
                    $a[0]="APT (Multiple Recon)"
                    
                    $Counter--
                    
                    if($Popup){
                        $message = "`n" + $a[3] + "`n" + $a[4] + "`n" + $a[5] + "`n" 
                        ShowMsg("APT Command was Executed Multiple Times !`n", $message)
                    }
                
                    if($Email){
                         $Subject = $Env:COMPUTERNAME + " Sysmon Alert - APT Recon"
                        AlertMail($Body, $Subject)
                    }                
                    
                }
                
            }elseif($a[4].ToLower().Contains("reg.exe") -and $a[5].ToLower().Contains("save") -and 
                    ( $a[5].ToLower().Contains("hklm\sam") -or 
                    $a[5].ToLower().Contains("hklm\system"))){ #Credential Dump
                    
                Write-Host "####### APT SAM HIVE was dumped!"
                $a[0]="APT (Credential Access)"
                
                if($Popup){
                    $message = "`n" + $a[3] + "`n" + $a[4] + "`n" + $a[5] + "`n" 
                    ShowMsg("Possible APT SAM Access !`n", $message)
                }
                
                if($Email){
                         $Subject = $Env:COMPUTERNAME + " Sysmon Alert - APT SAM Access"
                        AlertMail($Body, $Subject)
                } 
                         
            }elseif($a[5].ToLower().Contains(" a ") -and $a[5].ToLower().Contains(" -hp")){ #RAR
            
                $a[0]="APT (Data Stolen)"
                
                if($Popup){
                    $message = "`n" + $a[3] + "`n" + $a[4] + "`n" + $a[5] + "`n" 
                    ShowMsg("Possible APT Data Theft  !`n", $message)
                }

                if($Email){
                        $Subject = $Env:COMPUTERNAME + " Sysmon Alert - APT Data Theft"
                        AlertMail($Body, $Subject)
                } 
                     
            }elseif($a[5].ToLower().Contains("ntds.dit")) { #Server Compromise
                
                $a[0]="APT (DC Compromise)"
                
                if($Popup){
                    $message = "`n" + $a[3] + "`n" + $a[4] + "`n" + $a[5] + "`n" 
                    ShowMsg("Possible APT DC Compromise  !`n", $message)
                }
                
                if($Email){
                         $Subject = $Env:COMPUTERNAME + " Sysmon Alert - DC Comromise"
                        AlertMail($Body, $Subject)
                }
                     
            }elseif($a[5].ToLower().Contains("sekurlsa")) { #Mimikatz
                $a[0]="APT (Mimikatz)"

                if($Popup){
                    $message = "`n" + $a[3] + "`n" + $a[4] + "`n" + $a[5] + "`n" 
                    ShowMsg("Possible APT Mimikatz  !`n", $message)
                }
                                
                if($Email){
                        $Subject = $Env:COMPUTERNAME + " Sysmon Alert - APT Mimikatz"
                        AlertMail($Body, $Subject)
                }    
            }
            else {
            
            
            }

            $log = $HostName + "," + $a[1].SubString(9) + "," + $a[0].Replace(":","") + "," + #Host Date EventName
	               $a[3].SubString(11) + "," + $a[5].SubString(13).Replace(",","<R?>") + "," + $a[14].SubString(17) + "," + #ProcessId CmdLine ParentPID
	               $a[16].SubString(19).Replace(",","<R?>") + "," + $a[7].SubString(6) + "," + $a[12].SubString(15) + "," + #ParentCmd User Hash
	               "" + "," + "" + "," + "" + "," + #SourceID SourcePort DestIP
	               "" + ","  #DestPort
                       
             if($LocalCSV){          
                $log | Out-File $f -Encoding UTF8 -Append
             }
             
             if($Syslog){
                
                #Write-Host "TEST`n" $log
                SendSyslog([System.String]$log)
                # SendSyslog("10.211.55.27", "AAAAAAAAAA")
                #OK AT Here $ByteDate = [System.Text.Encoding]::Unicode.GetBytes($log) 
                
             }
        }
        
        #Network Connect Event
		if($EventCode -eq 3)
        {
            $a = $Message -split "`r`n"
            
            $log = $HostName + "," + $a[1].SubString(9) + "," + $a[0].Replace(":","") + "," + #Host Date EventName
	               $a[3].SubString(11) + "," + $a[4].SubString(7).Replace(",","<R?>") + "," + "" + "," + #ProcessId CmdLine ParentPID
	               "" + "," + $a[5].SubString(6) + "," + "" + "," + #ParentCmd User Hash
	               $a[9].SubString(10) + "," + $a[11].SubString(12) + "," + $a[14].SubString(15) + "," + #SourceIP SourcePort DestIP
	               $a[16].SubString(17) + ","  #DestPort

            if($LocalCSV){
                $log | Out-File $f -Encoding UTF8 -Append
            }
            
            if($Syslog){
                SendSyslog([System.String]$log)
            }
        }
        
        Remove-Event $EventLog

	}    
}Catch{
	Write-Warning "Error"
    $Error[0]
}Finally{
    Get-Event | Remove-Event 
    Get-EventSubscriber | Unregister-Event
}
