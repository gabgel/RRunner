Attribute VB_Name = "RRunner"
Option Explicit
' ###################################################################
' Configuration Parameters
' ###################################################################
' Path to the R Scripts and where the temporary files will be created
Private Const R_SCRIPTS_PATH = ".\r"
Private Const WORKING_PATH = ".\tmp"
' Time to wait for the R Script answer in milliseconds
Private Const TIMEOUT_MILLISECONDS = 10000
Private Const R_IN_FILE_NAME = "_RInput_"
Private Const R_OUT_FILE_NAME = "_ROutput_"
' ###################################################################

Private Declare Function GetWindowText Lib "User32" Alias "GetWindowTextA" (ByVal hwnd As Long, ByVal lpString As String, ByVal cch As Long) As Long
Private Declare Function GetWindowTextLength Lib "User32" Alias "GetWindowTextLengthA" (ByVal hwnd As Long) As Long
Private Declare Function GetWindow Lib "User32" (ByVal hwnd As Long, ByVal wCmd As Long) As Long

Private Declare Sub Sleep Lib "kernel32" (ByVal dwMilliseconds As Long) 'For 32 Bit Systems
Private Declare Function PostMessage Lib "user32.dll" Alias "PostMessageA" (ByVal hwnd As Long, ByVal wMsg As Long, ByVal wParam As Long, ByVal lParam As Long) As Long
Private Declare Function FindWindowEx Lib "user32.dll" Alias "FindWindowExA" (ByVal hWnd1 As Long, ByVal hWnd2 As Long, ByVal lpsz1 As String, ByVal lpsz2 As String) As Long
Private Declare Function GetTickCount Lib "kernel32" () As Long
Private Declare PtrSafe Function FindWindow Lib "User32" Alias "FindWindowA" ( _
    ByVal lpClassName As String, ByVal lpWindowName As String) As LongPtr
    
Private Const WM_CHAR As Long = &H102
Private Const GW_HWNDNEXT = 2
Private Const GW_CHILD = 5


Dim WorkingPath As String
Dim RScriptsPath As String


Private Sub SetStatus(s As String)
    Application.StatusBar = s
End Sub
' Get the window handle of a windows given a part of its caption
Private Function GetHandleFromPartialCaption(ByRef lWnd As Long, ByVal sCaption As String, Optional ChildCaption As String) As Boolean

    Dim lhWndP As Long, lhWndC As Long
    Dim sStr As String, found As Boolean, r As Long
    GetHandleFromPartialCaption = False
    lhWndP = FindWindow(vbNullString, vbNullString) 'PARENT WINDOW
    Do While lhWndP <> 0
        sStr = String(GetWindowTextLength(lhWndP) + 1, Chr$(0))
                      
        GetWindowText lhWndP, sStr, Len(sStr)
        sStr = Left$(sStr, Len(sStr) - 1)
        If InStr(1, sStr, sCaption) > 0 Then
            found = True
            lWnd = lhWndP
            Exit Do
        End If
        lhWndP = GetWindow(lhWndP, GW_HWNDNEXT)
    Loop
    If found And ChildCaption <> "" Then
        lhWndC = GetWindow(lhWndP, GW_CHILD)
        found = False
        Do Until lhWndC = 0
                sStr = Space$(255)
                r = GetWindowText(lhWndC, sStr, 255)
                sStr = Left$(sStr, r)
                If InStr(1, sStr, ChildCaption) <> 0 Then
                    lWnd = lhWndC
                    found = True
                    Exit Do
                End If
                lhWndC = GetWindow(lhWndC, GW_CHILD)
        Loop
    End If
    GetHandleFromPartialCaption = found
End Function



' Converts a relative path into an absolute path
Private Function AbsolutePath(path As String) As String
    If Left(path, 1) = "." Then
        AbsolutePath = ThisWorkbook.path & Right(path, Len(path) - 1)
    Else
        AbsolutePath = path
    End If
End Function

' Function that accepts multiple outputs and multiple inputs as dictionaries
Public Function RunRScript(RangesToExport As Dictionary, RangesToImport As Dictionary, PicturesToImport As Dictionary, script As String) As Boolean
    Dim h As Long, x As String, i As Long, KeyVal As String, WindowFound As Boolean
    Dim rng As Range, Key As Variant, OutputKey As String, doneFile As String
        
    Application.ScreenUpdating = False
    WorkingPath = AbsolutePath(WORKING_PATH)
    If Not FolderExists(WorkingPath) Then
        MkDir WorkingPath
    End If
    
    RScriptsPath = AbsolutePath(R_SCRIPTS_PATH)
    doneFile = WorkingPath + "\done"
    ' Remove output file before running the script
    If FileExists(doneFile) Then
        Kill doneFile
    End If
    
    ' Generate input files for the R script
    If Not ExportFiles(RangesToExport) Then
        Exit Function
    End If
    
    script = "source('" + Replace(RScriptsPath, "\", "/") + "/" + script + "')" + vbNewLine
    
    ' Find MDI Child first
    WindowFound = GetHandleFromPartialCaption(h, "RGui", "R Console")
    
    ' If not found, look for the console in SDI mode
    If Not WindowFound Then
        WindowFound = GetHandleFromPartialCaption(h, "R Console")
    End If
    
    If WindowFound Then
        For i = 1 To Len(script)
            PostMessage h, WM_CHAR, Asc(Mid(script, i)), 0
        Next i
        If WaitForFile(doneFile) Then
            For Each Key In RangesToImport.Keys
                OutputKey = Key
                LoadOutput OutputKey, RangesToImport(OutputKey)
            Next Key
            If Not PicturesToImport Is Nothing Then
                For Each Key In PicturesToImport.Keys
                    OutputKey = Key
                    LoadOutputPicture OutputKey, PicturesToImport(OutputKey)
                Next Key
            End If
            RunRScript = True
        Else
            RunRScript = False
        End If
    Else
        RunRScript = False
        MsgBox "R Console not found. Please start the R Console first."
    End If
    Application.ScreenUpdating = True
End Function

' Check every 100 milliseconds if the expected file is available
Private Function WaitForFile(fileName As String) As Boolean
    Dim StartTickCount As Long
    Dim TickCountNow As Long
    Dim EndTickCount As Long, done As Boolean

    SetStatus "Waiting for R Script to finish..."
    StartTickCount = GetTickCount()
    EndTickCount = StartTickCount + TIMEOUT_MILLISECONDS
    done = False
    Do While Not done
        DoEvents
        Sleep (100)
        If FileExists(fileName) Then
            done = True
            WaitForFile = True
        End If
        If GetTickCount() > EndTickCount Then
            done = True
            WaitForFile = False
        End If
    Loop
    SetStatus ""
End Function

' Helper function to check if a file exists
Private Function FileExists(fileName As String) As Boolean
    If Dir(fileName) <> "" Then
        FileExists = True
    Else
        FileExists = False
    End If

End Function


' Helper function to check if a folder exists
Private Function FolderExists(folderName As String) As Boolean
    If Dir(folderName, vbDirectory) <> "" Then
        FolderExists = True
    Else
        FolderExists = False
    End If

End Function


' Load a xlsx file into a range
Private Sub LoadOutput(TableName As String, rng As Range)
    Dim wb As Workbook, tblArr As Variant, destRng As Variant
    Dim rows As Long, cols As Long
    
    SetStatus "Retrieving output..."
    Set wb = Application.Workbooks.Open(WorkingPath + "\" & R_OUT_FILE_NAME & ".xlsx")
    tblArr = wb.Worksheets(TableName).UsedRange.Value
    wb.Close
    rows = UBound(tblArr, 1)
    cols = UBound(tblArr, 2)
    Set destRng = rng.Resize(rows, cols)
    destRng.Value = tblArr
    SetStatus ""
End Sub



' Simplified call to run a script with a single outRange called Resultado
Public Function RunR2Range(script As String, RangeToImport As Range, ParamArray RangesToExport() As Variant) As Boolean
    Dim i As Integer
    Dim inp As New Dictionary, out As New Dictionary, outP As Dictionary
    
    For i = LBound(RangesToExport) To UBound(RangesToExport) Step 2
        Set inp(RangesToExport(i)) = RangesToExport(i + 1)
    Next i
    
    Set out("result") = RangeToImport
    RunR2Range = RunRScript(inp, out, outP, script)
End Function

' Simplified call to run a script with a single outRange called Resultado
Public Function RunR2Plot(script As String, RangeToExport As Range, ChartToLoad As ChartObject, PlotName As String) As Boolean
    Dim i As Integer
    Dim inp As New Dictionary, out As New Dictionary, outP As New Dictionary
    
    Set inp(PlotName) = RangeToExport
    
    
    Set outP(PlotName) = ChartToLoad
    RunR2Plot = RunRScript(inp, out, outP, script)
End Function



'Export a range into a sheet of a given workbook
Private Function ExportTable(TableName As String, rng As Range, tempWB As Workbook) As Boolean

    Dim tblArr As Variant
    Dim cols As Long, lrow As Long
    Dim sht As Worksheet, destRng As Range
    
    ExportTable = True
    ' Find the last not empty row. This allows to send a range as columns
    ' https://www.excelcampus.com/vba/find-last-row-column-cell/
    If rng.rows.Count > 2 Then
        On Error GoTo empty_range:
        lrow = rng.Find(What:="*", _
                        After:=rng(1, 1), _
                        lookAt:=xlPart, _
                        LookIn:=xlFormulas, _
                        SearchOrder:=xlByRows, _
                        SearchDirection:=xlPrevious, _
                        MatchCase:=False).Row
        On Error GoTo 0
        tblArr = rng.Resize(lrow).Value
    Else
        lrow = rng.rows.Count
    End If
    cols = UBound(tblArr, 2)
    SetStatus "Exporting table " + TableName + "..."
    Set sht = tempWB.Worksheets.Add
    sht.Name = TableName
    Set destRng = sht.Range(sht.Cells(1, 1), sht.Cells(lrow, cols))
    destRng.Value = tblArr
    Exit Function
empty_range:
    On Error GoTo 0
    MsgBox ("Empty Range selected to export.")
    ExportTable = False
End Function

'Export a dictionary of ranges to the interface workbook
Private Function ExportFiles(InputRange As Dictionary) As Boolean
    Dim Key As Variant, KeyVal As String
    Dim tempWB As Workbook, filePath As String
    
    ExportFiles = True
    filePath = WorkingPath + "\" + R_IN_FILE_NAME + ".xlsx"
    SetStatus "Exporting ranges to R..."
    Set tempWB = Application.Workbooks.Add()
    For Each Key In InputRange.Keys
        KeyVal = Key
        If Not ExportTable(KeyVal, InputRange(Key), tempWB) Then
            ExportFiles = False
            tempWB.Close False
            Exit Function
        End If
    Next Key
    Application.DisplayAlerts = False
    tempWB.SaveAs filePath, FileFormat:=xlOpenXMLWorkbook, CreateBackup:=False
    tempWB.Close False
    Application.DisplayAlerts = True
    SetStatus ""
End Function

'Insert a file picture inside a given ChartObject
Private Sub LoadOutputPicture(PictureName As String, ChartArea As ChartObject)
    Dim filePath As String, sh As Shape, pic As Shape, meas As Variant, wia As Object
    Dim orWidth As Long, orHeight As Long
    filePath = WorkingPath + "\" + PictureName + ".png"
    For Each sh In ChartArea.Chart.Shapes
        sh.Delete
    Next sh

    On Error Resume Next
    Set pic = ChartArea.Chart.Shapes.AddPicture(filePath, msoFalse, msoCTrue, 0, 0, -1, -1)
    If Err.Number <> 0 Then
        MsgBox Err.Description & ": " & filePath
        Exit Sub
    End If
    On Error GoTo 0
    Set wia = CreateObject("WIA.ImageFile")
    'Load the ImageFile object with the specified File.
    wia.LoadFile filePath
    'Get the necessary properties.
    orWidth = wia.Width
    orHeight = wia.Height
    'Release the ImageFile object.
    Set wia = Nothing
    With pic
        .LockAspectRatio = msoFalse
        .Placement = xlFreeFloating
        If orWidth / orHeight < ChartArea.Width / ChartArea.Height Then
            .Height = ChartArea.Height
            .Width = .Height * orWidth / orHeight
        Else
            .Width = ChartArea.Width
            .Height = .Width * orHeight / orWidth
        End If
        .LockAspectRatio = msoTrue
    End With

End Sub
    
