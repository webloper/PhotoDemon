Attribute VB_Name = "Filters_Miscellaneous"
'***************************************************************************
'Filter Module
'Copyright 2000-2017 by Tanner Helland
'Created: 13/October/00
'Last updated: 07/September/15
'Last update: continued work on moving crap out of this module
'
'The general image filter module; contains unorganized routines at present.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Render an image using faux thermography; basically, map luminance values as if they were heat, and use a modified hue spectrum for representation.
' (I have manually tweaked the values at certain ranges to better approximate actual thermography.)
Public Sub MenuHeatMap()

    Message "Performing thermographic analysis..."
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    PrepImageData tmpSA
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickVal As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    Dim grayVal As Long
    Dim hVal As Double, sVal As Double, lVal As Double
    Dim h As Double, s As Double, l As Double
    
    'Because gray values are constant, we can use a look-up table to calculate them
    Dim gLookup(0 To 765) As Byte
    For x = 0 To 765
        gLookup(x) = CByte(x \ 3)
    Next x
        
    'Apply the filter
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
        
        r = imageData(quickVal + 2, y)
        g = imageData(quickVal + 1, y)
        b = imageData(quickVal, y)
        
        grayVal = gLookup(r + g + b)
        
        'Based on the luminance of this pixel, apply a predetermined hue gradient (stretching between -1 and 5)
        hVal = (CSng(grayVal) / 255) * 360
        
        'If the hue is "below" blue, gradually darken the corresponding luminance value
        If hVal < 120 Then
            lVal = (0.35 * (hVal / 120)) + 0.15
        Else
            lVal = 0.5
        End If
        
        'Invert the hue
        hVal = 360 - hVal
                
        'Place hue in the range of -1 to 5, per the requirements of our HSL conversion algorithm
        hVal = (hVal - 60) / 60
        
        'Use nearly full saturation (for dramatic effect)
        sVal = 0.8
        
        'Use RGB to calculate hue, saturation, and luminance
        Colors.ImpreciseRGBtoHSL r, g, b, h, s, l
        
        'Now convert those HSL values back to RGB, but substitute in our artificial hue value (calculated above)
        Colors.ImpreciseHSLtoRGB hVal, sVal, lVal, r, g, b
        
        imageData(quickVal + 2, y) = r
        imageData(quickVal + 1, y) = g
        imageData(quickVal, y) = b
        
    Next y
        If (x And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal x
        End If
    Next x
        
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData
    
End Sub

'A very neat comic-book filter that actually blends together a number of other filters into one!
Public Sub MenuComicBook()
    
    Dim gRadius As Long
    gRadius = 20
    
    Dim gThreshold As Long
    gThreshold = 8
    
    Message "Animating image (stage %1 of %2)...", 1, 3
                
    'More color variables - in this case, sums for each color component
    Dim r As Long, g As Long, b As Long
    Dim r2 As Long, g2 As Long, b2 As Long
    Dim tDelta As Long
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstSA As SAFEARRAY2D
    PrepImageData dstSA
    
    'Create a second local array.  This will contain the a copy of the current image, and we will use it as our source reference
    ' (This is necessary to prevent blurred pixel values from spreading across the image as we go.)
    Dim srcDIB As pdDIB
    Set srcDIB = New pdDIB
    srcDIB.CreateFromExistingDIB workingDIB
    
    Dim gaussDIB As pdDIB
    Set gaussDIB = New pdDIB
    gaussDIB.CreateFromExistingDIB workingDIB
    
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
    
    CreateGaussianBlurDIB gRadius, srcDIB, gaussDIB, False, finalY + finalY + finalX + finalX
    
    If g_cancelCurrentAction Then
        srcDIB.EraseDIB
        gaussDIB.EraseDIB
        FinalizeImageData
        Exit Sub
    End If
        
    'Now that we have a gaussian DIB created in gaussDIB, we can point arrays toward it and the source DIB
    Dim dstImageData() As Byte
    PrepImageData dstSA
    CopyMemory ByVal VarPtrArray(dstImageData()), VarPtr(dstSA), 4
    
    Dim srcImageData() As Byte
    Dim srcSA As SAFEARRAY2D
    PrepSafeArray srcSA, srcDIB
    CopyMemory ByVal VarPtrArray(srcImageData()), VarPtr(srcSA), 4
        
    Dim GaussImageData() As Byte
    Dim gaussSA As SAFEARRAY2D
    PrepSafeArray gaussSA, gaussDIB
    CopyMemory ByVal VarPtrArray(GaussImageData()), VarPtr(gaussSA), 4
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickVal As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
        
    Message "Animating image (stage %1 of %2)...", 2, 3
        
    Dim blendVal As Double
    
    'The final step of the smart blur function is to find edges, and replace them with the blurred data as necessary
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
        
        'Retrieve the original image's pixels
        r = srcImageData(quickVal + 2, y)
        g = srcImageData(quickVal + 1, y)
        b = srcImageData(quickVal, y)
        
        tDelta = (213 * r + 715 * g + 72 * b) \ 1000
        
        'Now, retrieve the gaussian pixels
        r2 = GaussImageData(quickVal + 2, y)
        g2 = GaussImageData(quickVal + 1, y)
        b2 = GaussImageData(quickVal, y)
        
        'Calculate a delta between the two
        tDelta = tDelta - ((213 * r2 + 715 * g2 + 72 * b2) \ 1000)
        If tDelta < 0 Then tDelta = -tDelta
                
        'If the delta is below the specified threshold, replace it with the blurred data.
        If tDelta > gThreshold Then
            If tDelta <> 0 Then blendVal = 1 - (gThreshold / tDelta) Else blendVal = 0
            dstImageData(quickVal + 2, y) = BlendColors(srcImageData(quickVal + 2, y), GaussImageData(quickVal + 2, y), blendVal)
            dstImageData(quickVal + 1, y) = BlendColors(srcImageData(quickVal + 1, y), GaussImageData(quickVal + 1, y), blendVal)
            dstImageData(quickVal, y) = BlendColors(srcImageData(quickVal, y), GaussImageData(quickVal, y), blendVal)
            If qvDepth = 4 Then dstImageData(quickVal + 3, y) = BlendColors(srcImageData(quickVal + 3, y), GaussImageData(quickVal + 3, y), blendVal)
        End If
        
    Next y
        If (x And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal x + (finalY * 2)
        End If
    Next x
        
    'With our work complete, release all arrays
    CopyMemory ByVal VarPtrArray(GaussImageData), 0&, 4
    Erase GaussImageData
    
    gaussDIB.EraseDIB
    Set gaussDIB = Nothing
    
    'Because this function occurs in multiple passes, it requires specialized cancel behavior.  All array references must be dropped
    ' or the program will experience a hard-freeze.
    If g_cancelCurrentAction Then
        CopyMemory ByVal VarPtrArray(dstImageData()), 0&, 4
        CopyMemory ByVal VarPtrArray(srcImageData()), 0&, 4
        FinalizeImageData
        Exit Sub
    End If
    
    'The last thing we need to do is sketch in the edges of the image.
    
    Message "Animating image (stage %1 of %2)...", 3, 3
    
    'We can't do this at the borders of the image, so shrink the functional area by one in each dimension.
    initX = initX + 1
    initY = initY + 1
    finalX = finalX - 1
    finalY = finalY - 1
    
    Dim QuickValRight As Long, QuickValLeft As Long, tmpColor As Long, tMin As Long
    Dim z As Long
        
    'Loop through each pixel in the image, converting values as we go
    For x = initX To finalX
        quickVal = x * qvDepth
        QuickValRight = (x + 1) * qvDepth
        QuickValLeft = (x - 1) * qvDepth
    For y = initY To finalY
        For z = 0 To 2
    
            tMin = 255
            tmpColor = srcImageData(QuickValRight + z, y)
            If tmpColor < tMin Then tMin = tmpColor
            tmpColor = srcImageData(QuickValRight + z, y - 1)
            If tmpColor < tMin Then tMin = tmpColor
            tmpColor = srcImageData(QuickValRight + z, y + 1)
            If tmpColor < tMin Then tMin = tmpColor
            tmpColor = srcImageData(QuickValLeft + z, y)
            If tmpColor < tMin Then tMin = tmpColor
            tmpColor = srcImageData(QuickValLeft + z, y - 1)
            If tmpColor < tMin Then tMin = tmpColor
            tmpColor = srcImageData(QuickValLeft + z, y + 1)
            If tmpColor < tMin Then tMin = tmpColor
            tmpColor = srcImageData(quickVal + z, y)
            If tmpColor < tMin Then tMin = tmpColor
            tmpColor = srcImageData(quickVal + z, y - 1)
            If tmpColor < tMin Then tMin = tmpColor
            tmpColor = srcImageData(quickVal + z, y + 1)
            If tmpColor < tMin Then tMin = tmpColor
            
            If tMin > 255 Then tMin = 255
            If tMin < 0 Then tMin = 0
            
            Select Case z
            
                Case 0
                    b = 255 - (srcImageData(quickVal, y) - tMin)
            
                Case 1
                    g = 255 - (srcImageData(quickVal + 1, y) - tMin)
                    
                Case 2
                    r = 255 - (srcImageData(quickVal + 2, y) - tMin)
            
            End Select
                    
        Next z
        
        r2 = dstImageData(quickVal + 2, y)
        g2 = dstImageData(quickVal + 1, y)
        b2 = dstImageData(quickVal, y)
        
        r = ((CSng(r) / 255) * (CSng(r2) / 255)) * 255
        g = ((CSng(g) / 255) * (CSng(g2) / 255)) * 255
        b = ((CSng(b) / 255) * (CSng(b2) / 255)) * 255
        
        dstImageData(quickVal + 2, y) = r
        dstImageData(quickVal + 1, y) = g
        dstImageData(quickVal, y) = b
        
    Next y
        If (x And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal x + finalX + (finalY * 2)
        End If
    Next x
    
    CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
    Erase srcImageData
    
    CopyMemory ByVal VarPtrArray(dstImageData), 0&, 4
    Erase dstImageData
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData

End Sub

'Wacky filter discovered by trial-and-error.  I named it "synthesize".
Public Sub MenuSynthesize()

    Message "Synthesizing new image..."
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    PrepImageData tmpSA
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickVal As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    Dim grayVal As Long
    
    'Because gray values are constant, we can use a look-up table to calculate them
    Dim gLookup(0 To 765) As Byte
    For x = 0 To 765
        gLookup(x) = CByte(x \ 3)
    Next x
        
    'Apply the filter
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
        
        r = imageData(quickVal + 2, y)
        g = imageData(quickVal + 1, y)
        b = imageData(quickVal, y)
        
        grayVal = gLookup(r + g + b)
        
        r = g + b - grayVal
        g = r + b - grayVal
        b = r + g - grayVal
        
        If r > 255 Then r = 255
        If r < 0 Then r = 0
        If g > 255 Then g = 255
        If g < 0 Then g = 0
        If b > 255 Then b = 255
        If b < 0 Then b = 0
        
        imageData(quickVal + 2, y) = r
        imageData(quickVal + 1, y) = g
        imageData(quickVal, y) = b
        
    Next y
        If (x And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal x
        End If
    Next x
        
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData

End Sub

'Very improved version of "sepia".  This is more involved than a typical "change to brown" effect - the white balance and
' shading is also adjusted to give the image a more "antique" look.
Public Sub MenuAntique()
    
    Message "Accelerating to 88mph in order to antique-ify this image..."
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    PrepImageData tmpSA
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickVal As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    'We're going to need grayscale values as part of the effect; grayscale is easily optimized via a look-up table
    Dim gLookup(0 To 765) As Byte
    For x = 0 To 765
        gLookup(x) = CByte(x \ 3)
    Next x
    
    'We're going to use gamma conversion as part of the effect; gamma is easily optimized via a look-up table
    Dim gammaLookup(0 To 255) As Byte
    Dim tmpVal As Double
    For x = 0 To 255
        tmpVal = x / 255
        tmpVal = tmpVal ^ (1# / 1.6)
        tmpVal = tmpVal * 255
        If tmpVal > 255 Then tmpVal = 255
        If tmpVal < 0 Then tmpVal = 0
        gammaLookup(x) = CByte(tmpVal)
    Next x
    
    'Finally, we also need to adjust brightness.  A look-up table is once again invaluable
    Dim bLookup(0 To 255) As Byte
    For x = 0 To 255
        tmpVal = x * 1.75
        If tmpVal > 255 Then tmpVal = 255
        bLookup(x) = CByte(tmpVal)
    Next x
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    Dim newR As Long, newG As Long, newB As Long
    Dim gray As Long
        
    'Apply the filter
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
    
        r = imageData(quickVal + 2, y)
        g = imageData(quickVal + 1, y)
        b = imageData(quickVal, y)
        
        gray = gLookup(r + g + b)
        
        r = (r + gray) \ 2
        g = (g + gray) \ 2
        b = (b + gray) \ 2
        
        r = (g * b) \ 256
        g = (b * r) \ 256
        b = (r * g) \ 256
        
        newR = bLookup(r)
        newG = bLookup(g)
        newB = bLookup(b)
        
        newR = gammaLookup(newR)
        newG = gammaLookup(newG)
        newB = gammaLookup(newB)
        
        imageData(quickVal + 2, y) = newR
        imageData(quickVal + 1, y) = newG
        imageData(quickVal, y) = newB
        
    Next y
        If (x And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal x
        End If
    Next x
        
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData
    
End Sub

'Dull but standard "sepia" transformation.  Values derived from the w3c standard at:
' https://dvcs.w3.org/hg/FXTF/raw-file/tip/filters/index.html#sepiaEquivalent
Public Sub MenuSepia()
    
    Message "Engaging hipsters to perform sepia conversion..."
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    PrepImageData tmpSA
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickVal As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    Dim newR As Double, newG As Double, newB As Double
        
    'Apply the filter
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
    
        r = imageData(quickVal + 2, y)
        g = imageData(quickVal + 1, y)
        b = imageData(quickVal, y)
                
        newR = CSng(r) * 0.393 + CSng(g) * 0.769 + CSng(b) * 0.189
        newG = CSng(r) * 0.349 + CSng(g) * 0.686 + CSng(b) * 0.168
        newB = CSng(r) * 0.272 + CSng(g) * 0.534 + CSng(b) * 0.131
        
        r = newR
        g = newG
        b = newB
        
        If r > 255 Then r = 255
        If g > 255 Then g = 255
        If b > 255 Then b = 255
        
        imageData(quickVal + 2, y) = r
        imageData(quickVal + 1, y) = g
        imageData(quickVal, y) = b
        
    Next y
        If (x And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal x
        End If
    Next x
        
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData
    
End Sub

'Another filter found by trial-and-error.  "Dream" effect.
Public Sub MenuDream()

    Message "Putting image to sleep, then measuring its REM cycles..."
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    PrepImageData tmpSA
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickVal As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    Dim newR As Long, newG As Long, newB As Long
    Dim grayVal As Long
    
    'Because gray values are constant, we can use a look-up table to calculate them
    Dim gLookup(0 To 765) As Byte
    For x = 0 To 765
        gLookup(x) = CByte(x \ 3)
    Next x
        
    'Apply the filter
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
        
        newR = imageData(quickVal + 2, y)
        newG = imageData(quickVal + 1, y)
        newB = imageData(quickVal, y)
        
        grayVal = gLookup(newR + newG + newB)
        
        r = Abs(newR - grayVal) + Abs(newR - newG) + Abs(newR - newB) + (newR \ 2)
        g = Abs(newG - grayVal) + Abs(newG - newB) + Abs(newG - newR) + (newG \ 2)
        b = Abs(newB - grayVal) + Abs(newB - newR) + Abs(newB - newG) + (newB \ 2)
        
        If r > 255 Then r = 255
        If r < 0 Then r = 0
        If g > 255 Then g = 255
        If g < 0 Then g = 0
        If b > 255 Then b = 255
        If b < 0 Then b = 0
        
        imageData(quickVal + 2, y) = r
        imageData(quickVal + 1, y) = g
        imageData(quickVal, y) = b
        
    Next y
        If (x And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal x
        End If
    Next x
        
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData

End Sub

'Subroutine for counting the number of unique colors in an image
Public Sub MenuCountColors()
    
    Message "Counting the number of unique colors in this image..."
    
    'Grab a composited copy of the image
    Dim tmpImageComposite As pdDIB
    pdImages(g_CurrentImage).GetCompositedImage tmpImageComposite, True
    If (tmpImageComposite Is Nothing) Then Exit Sub
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    EffectPrep.PrepSafeArray tmpSA, tmpImageComposite
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(tmpSA), 4
    
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim qvDepth As Long
    qvDepth = tmpImageComposite.GetDIBColorDepth \ 8
    
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = 0
    initY = 0
    finalX = tmpImageComposite.GetDIBStride - 1
    finalY = tmpImageComposite.GetDIBHeight - 1
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    SetProgBarMax finalY
    progBarCheck = FindBestProgBarValue()
    
    'This array will track whether or not a given color has been detected in the image
    Dim uniqueColors() As Byte
    ReDim uniqueColors(0 To 16777216) As Byte
    
    'Total number of unique colors counted so far
    Dim totalCount As Long
    totalCount = 0
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    Dim chkValue As Long
        
    'Apply the filter
    For y = initY To finalY
    For x = initX To finalX Step qvDepth
        b = imageData(x, y)
        g = imageData(x + 1, y)
        r = imageData(x + 2, y)
        
        chkValue = RGB(r, g, b)
        If uniqueColors(chkValue) = 0 Then
            totalCount = totalCount + 1
            uniqueColors(chkValue) = 1
        End If
    Next x
        If (y And progBarCheck) = 0 Then SetProgBarVal y
    Next y
    
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    Erase uniqueColors
    Set tmpImageComposite = Nothing
    
    'Reset the progress bar
    SetProgBarVal 0
    ReleaseProgressBar
    
    'Show the user our final tally
    Message "Total unique colors: %1", totalCount
    PDMsgBox "This image contains %1 unique colors.", vbOKOnly + vbApplicationModal + vbInformation, "Count image colors", totalCount
    
End Sub

'You can use this section of code to test out your own filters.  I've left some sample code below.
Public Sub MenuTest()
    
    PDMsgBox "This menu item only appears in the Visual Basic IDE." & vbCrLf & vbCrLf & "You can use the MenuTest() sub in the Filters_Miscellaneous module to test your own filters.  I typically do this first, then once the filter is working properly, I give it a subroutine of its own.", vbInformation + vbOKOnly + vbApplicationModal, " PhotoDemon Pro Tip"
    
    'Apply fake color correction, as a test
    'ColorManagement.convertRGBUsingCustomEndpoints pdImages(g_CurrentImage).getActiveDIB, 0.15, 0.06, 0.3, 0.6, 0.64, 0.33, 0.3127, 0.329
    
    'Create a LUT class for testing
    Dim cLut As pdFilterLUT
    Set cLut = New pdFilterLUT
    
    Dim rLUT() As Byte, gLUT() As Byte, bLUT() As Byte
    Dim rLUT2() As Byte, gLUT2() As Byte, bLUT2() As Byte
    Dim rLUT3() As Byte, gLUT3() As Byte, bLUT3() As Byte
    Dim curvePoints() As POINTFLOAT
    
    '*******************************
    'Brightness/contrast test (use Merge to combine the two results)
    'cLUT.fillLUT_Brightness rLUT2, -20
    'cLUT.fillLUT_Brightness gLUT2, -20
    'cLUT.fillLUT_Brightness bLUT2, -20
    '
    'cLUT.fillLUT_Contrast rLUT3, -50
    'cLUT.fillLUT_Contrast gLUT3, -50
    'cLUT.fillLUT_Contrast bLUT3, -50
    '*******************************
    
    '*******************************
    'Gamma test
    cLut.FillLUT_Gamma rLUT, 2.2
    cLut.FillLUT_Gamma gLUT, 2.2
    cLut.FillLUT_Gamma bLUT, 2.2
    '*******************************
    
    '*******************************
    'Merge test
    ' 3 after 2...
    'cLUT.MergeLUTs rLUT2, rLUT3, rLUT
    'cLUT.MergeLUTs gLUT2, gLUT3, gLUT
    'cLUT.MergeLUTs bLUT2, bLUT3, bLUT
    
    ' ...or 2 after 3...
    'cLUT.MergeLUTs rLUT3, rLUT2, rLUT
    'cLUT.MergeLUTs gLUT3, gLUT2, gLUT
    'cLUT.MergeLUTs bLUT3, bLUT2, bLUT
    '*******************************
    
    '*******************************
    'Curve test
    'cLUT.helper_QuickCreateCurveArray curvePoints, 0, 255, 255, 0
    'cLUT.fillLUT_Curve rLUT, curvePoints
    'cLUT.fillLUT_Curve gLUT, curvePoints
    'cLUT.fillLUT_Curve bLUT, curvePoints
    '*******************************
    
    'Apply the test LUTs to the image
    cLut.ApplyLUTsToDIB_Color pdImages(g_CurrentImage).GetActiveDIB, rLUT, gLUT, bLUT
        
    'Reflect any image changes on the screen.
    ReleaseProgressBar
    ViewportEngine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    Exit Sub
        
End Sub

'Placeholder function I'm using to remind myself how to best use the new palette generator functions.
Public Sub MenuApplyTestPalette()

    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    PrepImageData tmpSA
    
    Dim startTime As Currency
    VBHacks.GetHighResTime startTime
    
    'Make a smaller, localized copy of the DIB.  (50k pixels is more than enough for accurate
    ' palette generation, and using a fixed size guarantees roughly O(1) time for palette generation.)
    Dim megapixelSize As Long
    megapixelSize = 50000
    Dim smallDIB As pdDIB
    If DIBs.ResizeDIBByPixelCount(workingDIB, smallDIB, megapixelSize) Then
        
        'Construct an optimized palette based on the small image
        Dim srcPalette() As RGBQUAD
        If Palettes.GetOptimizedPalette(smallDIB, srcPalette, 256) Then
        
            'Apply the optimized palette to the full-sized DIB.
            'Palettes.ApplyPaletteToImage workingDIB, srcPalette
            'Palettes.ApplyPaletteToImage_SysAPI workingDIB, srcPalette
            'Palettes.ApplyPaletteToImage_LossyHashTable workingDIB, srcPalette
            Palettes.ApplyPaletteToImage_Octree workingDIB, srcPalette
            
        End If
        
    End If
    
    'Debug.Print "Finished: " & VBHacks.GetTimerDifferenceNow(startTime) * 1000
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData
    
    ViewportEngine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
End Sub
