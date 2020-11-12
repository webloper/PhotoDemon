Attribute VB_Name = "Animation"
'***************************************************************************
'Animation Functions
'Copyright 2019-2020 by Tanner Helland
'Created: 20/August/19
'Last updated: 30/August/20
'Last update: new function for (reliably?) replacing an existing layer-name-frame-time with a new value
'
'PhotoDemon was never meant to be an animation editor, but repeat user requests for animated GIF handling
' led to a rudimentary set of import/export/playback features.
'
'This module collects a few useful tools for dealing with animated images.
'
'Unless otherwise noted, all source code in this file is shared under a simplified BSD license.
' Full license details are available in the LICENSE.md file, or at https://photodemon.org/license/
'
'***************************************************************************

Option Explicit

'Many dialogs render animations in some fashion.  A standard struct is used for retrieving
' animation frames (typically from a pdSpriteSheet object), but there's no reason you can't
' use your own custom struct if this one doesn't meet your needs.  (This struct is not
' currently passed anywhere; it's only used for local caching of key animation data.)
Public Type PD_AnimationFrame
    
    'DIB parameters
    afThumbKey As Long
    afWidth As Long
    afHeight As Long
    
    'Metadata
    afFrameDelayMS As Long
    
    'For perf-sensitive rendering tasks, timestamps can be used to avoid unnecessary thumbnail updates
    afTimeStamp As Currency
    
End Type

'Used to temporarily cache the location of a temporary animation-related file.
Private m_TmpAnimationFile As String

Public Sub SetAnimationTmpFile(ByRef srcFile As String)
    m_TmpAnimationFile = srcFile
End Sub

Public Function GetFrameTimeFromLayerName(ByRef srcLayerName As String, Optional ByVal defaultTimeIfMissing As Long = 100) As Long
    
    'Default to the user's requested default value; if we find a valid value, it will replace this one
    GetFrameTimeFromLayerName = defaultTimeIfMissing
    
    'Look for a trailing parenthesis
    Dim strStart As Long, strEnd As Long
    strEnd = InStrRev(srcLayerName, ")", -1, vbBinaryCompare)
    If (strEnd > 0) Then
        
        'Find the nearest leading parenthesis
        strStart = InStrRev(srcLayerName, "(", strEnd, vbBinaryCompare)
        If (strStart > 0) And (strStart < strEnd - 1) Then
        
            'Retrieve the text between said parentheses
            Dim tmpString As String
            tmpString = Mid$(srcLayerName, strStart + 1, (strEnd - strStart) - 1)
            
            'Finally, strip any non-numeric characters from the text.  (Frame times are typically displayed
            ' as "100ms", and we don't want the "ms" bit.)
            Dim ascLow As Long, ascHigh As Long
            ascLow = AscW("0")
            ascHigh = AscW("9")
            
            Dim finalString As pdString
            Set finalString = New pdString
            
            Dim i As Long, singleChar As String
            For i = 1 To Len(tmpString)
                singleChar = Mid$(tmpString, i, 1)
                If (AscW(singleChar) >= ascLow) And (AscW(singleChar) <= ascHigh) Then finalString.Append singleChar
            Next i
            
            On Error GoTo BadNumber
            GetFrameTimeFromLayerName = CLng(finalString.ToString())
            
            'Enforce a minimum frametime of 0 ms, and leave it to decoders to deal with that case as necessary
            If (GetFrameTimeFromLayerName < 0) Then GetFrameTimeFromLayerName = 0
            
BadNumber:
        
        End If
        
    End If
    
End Function

'Create a new pdImage object from a screen recording.  Note that this is only meaningful if the user
' selected to load their recording directly into PD; otherwise, the passed filename will be null and
' we don't need to do anything.
Public Sub CreateNewPDImageFromAnimation()
    
    If (LenB(m_TmpAnimationFile) <> 0) Then
        
        'We can now use the standard image load routine to import the temporary file
        Dim sTitle As String
        sTitle = g_Language.TranslateMessage("[untitled image]")
        Loading.LoadFileAsNewImage m_TmpAnimationFile, sTitle, False
                        
        'Be polite and remove the temporary file, then release this dialog completely
        Files.FileDeleteIfExists m_TmpAnimationFile
        m_TmpAnimationFile = vbNullString
            
    End If
End Sub

Public Function UpdateFrameTimeInLayerName(ByRef srcLayerName As String, ByVal newFrameTime As Long) As String
    
    'Look for a trailing parenthesis
    Dim parenFound As Boolean
    parenFound = False
    
    Dim strStart As Long, strEnd As Long
    strEnd = InStrRev(srcLayerName, ")", -1, vbBinaryCompare)
    If (strEnd > 0) Then
        
        'Find the nearest leading parenthesis
        strStart = InStrRev(srcLayerName, "(", strEnd, vbBinaryCompare)
        If (strStart > 0) And (strStart < strEnd - 1) Then
            
            'Note that we found parentheses.  (We'll use this to determine where to stick frame time text.)
            parenFound = True
            
            Dim validNumberFound As Boolean
            validNumberFound = False
            
            'Retrieve the text between said parentheses
            Dim tmpString As String
            tmpString = Mid$(srcLayerName, strStart + 1, (strEnd - strStart) - 1)
            
            'Finally, strip any non-numeric characters from the text.  (Frame times are typically displayed
            ' as "100ms", and we don't want the "ms" bit.)
            Dim ascLow As Long, ascHigh As Long
            ascLow = AscW("0")
            ascHigh = AscW("9")
            
            Dim finalString As pdString
            Set finalString = New pdString
            
            Dim i As Long, singleChar As String
            For i = 1 To Len(tmpString)
                singleChar = Mid$(tmpString, i, 1)
                If (AscW(singleChar) >= ascLow) And (AscW(singleChar) <= ascHigh) Then finalString.Append singleChar
            Next i
            
            On Error GoTo BadNumber
            Dim curFrameTime As Long, curFrameTimeAsText As String
            curFrameTime = CLng(finalString.ToString())
            curFrameTimeAsText = Trim$(Str$(curFrameTime))
            
            'Replace the current frame time with the newly requested frame time
            Dim startPos As Long
            startPos = InStrRev(srcLayerName, curFrameTimeAsText)
            
            'I doubt it's physically possible to *not* find the string representation of the frame time inside the
            ' layer name, but hey - anything is possible.  If this happens, we'll just append our new frame time value
            ' at the end.
            If (startPos < 1) Then
                parenFound = False
            Else
            
                'Append everything to the left of the old frame time with the new frame time
                startPos = startPos - 1
                UpdateFrameTimeInLayerName = Left$(srcLayerName, startPos) & Trim$(Str$(newFrameTime))
                
                'If characters followed the old frame time, append that text too
                If ((startPos + Len(curFrameTimeAsText)) < Len(srcLayerName)) Then
                    UpdateFrameTimeInLayerName = UpdateFrameTimeInLayerName & Right$(srcLayerName, Len(srcLayerName) - (startPos + Len(curFrameTimeAsText)))
                End If
                
                'If we made it all the way here without errors, we found a valid frame time
                validNumberFound = True
                
            End If
            
BadNumber:
            'If we didn't find a valid number inside the parentheses, we'll just append frame time to the end
            ' of the existing layer name.
            If (Not validNumberFound) Then parenFound = False
            
        End If
        
    End If
    
    'If we didn't find parentheses in the layer name, just append the frame time to the end
    If (Not parenFound) Then
        UpdateFrameTimeInLayerName = srcLayerName & " (" & Trim$(Str$(newFrameTime)) & " ms)"
    End If
    
End Function
