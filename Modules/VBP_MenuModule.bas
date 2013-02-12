Attribute VB_Name = "File_Menu"
'***************************************************************************
'File Menu Handler
'Copyright �2001-2013 by Tanner Helland
'Created: 15/Apr/01
'Last updated: 18/November/12
'Last update: common dialog file format string is now generated by the g_ImageFormats class (of type pdFormats)
'
'Functions for controlling standard file menu options.  Currently only handles "open image" and "save image".
'
'***************************************************************************

Option Explicit

'This subroutine loads an image - note that the interesting stuff actually happens in PhotoDemon_OpenImageDialog, below
Public Sub MenuOpen()
    
    'String returned from the common dialog wrapper
    Dim sFile() As String
    
    If PhotoDemon_OpenImageDialog(sFile, FormMain.hWnd) Then PreLoadImage sFile

    Erase sFile

End Sub

'Pass this function a string array, and it will fill it with a list of files selected by the user.
' The commondialog filters are automatically set according to image formats supported by the program.
Public Function PhotoDemon_OpenImageDialog(ByRef listOfFiles() As String, ByVal ownerhWnd As Long) As Boolean

    'Common dialog interface
    Dim CC As cCommonDialog
    
    'Get the last "open image" path from the INI file
    Dim tempPathString As String
    tempPathString = g_UserPreferences.GetPreference_String("Program Paths", "MainOpen", "")
    
    Set CC = New cCommonDialog
        
    Dim sFileList As String
    
    'Use Steve McMahon's excellent Common Dialog class to launch a dialog (this way, no OCX is required)
    If CC.VBGetOpenFileName(sFileList, , True, True, False, True, g_ImageFormats.getCommonDialogInputFormats, g_LastOpenFilter, tempPathString, g_Language.TranslateMessage("Open an image"), , ownerhWnd, 0) Then
        
        Message "Preparing to load image..."
        
        'Take the return string (a null-delimited list of filenames) and split it out into a string array
        listOfFiles = Split(sFileList, vbNullChar)
        
        Dim x As Long
        
        'Due to the buffering required by the API call, uBound(listOfFiles) should ALWAYS > 0 but
        ' let's check it anyway (just to be safe)
        If UBound(listOfFiles) > 0 Then
        
            'Remove all empty strings from the array (which are a byproduct of the aforementioned buffering)
            For x = UBound(listOfFiles) To 0 Step -1
                If listOfFiles(x) <> "" Then Exit For
            Next
            
            'With all the empty strings removed, all that's left is legitimate file paths
            ReDim Preserve listOfFiles(0 To x) As String
            
        End If
        
        'If multiple files were selected, we need to do some additional processing to the array
        If UBound(listOfFiles) > 0 Then
        
            'The common dialog function returns a unique array. Index (0) contains the folder path (without a
            ' trailing backslash), so first things first - add a trailing backslash
            Dim imagesPath As String
            imagesPath = FixPath(listOfFiles(0))
            
            'The remaining indices contain a filename within that folder.  To get the full filename, we must
            ' append the path from (0) to the start of each filename.  This will relieve the burden on
            ' whatever function called us - it can simply loop through the full paths, loading files as it goes
            For x = 1 To UBound(listOfFiles)
                listOfFiles(x - 1) = imagesPath & listOfFiles(x)
            Next x
            
            ReDim Preserve listOfFiles(0 To UBound(listOfFiles) - 1)
            
            'Save the new directory as the default path for future usage
            g_UserPreferences.SetPreference_String "Program Paths", "MainOpen", imagesPath
            
        'If there is only one file in the array (e.g. the user only opened one image), we don't need to do all
        ' that extra processing - just save the new directory to the INI file
        Else
        
            'Save the new directory as the default path for future usage
            tempPathString = listOfFiles(0)
            StripDirectory tempPathString
        
            g_UserPreferences.SetPreference_String "Program Paths", "MainOpen", tempPathString
            
        End If
        
        'Also, remember the file filter for future use (in case the user tends to use the same filter repeatedly)
        g_UserPreferences.SetPreference_Long "File Formats", "LastOpenFilter", g_LastOpenFilter
        
        'All done!
        PhotoDemon_OpenImageDialog = True
        
    'If the user cancels the commondialog box, simply exit out
    Else
        
        If CC.ExtendedError <> 0 Then pdMsgBox "An error occurred: %1", vbCritical + vbOKOnly + vbApplicationModal, "Common dialog error", CC.ExtendedError
    
        PhotoDemon_OpenImageDialog = False
    End If
    
    'Release the common dialog object
    Set CC = Nothing

End Function

'Subroutine for saving an image to file.  This function assumes the image already exists on disk and is simply
' being replaced; if the file does not exist on disk, this routine will automatically transfer control to Save As...
' The imageToSave is a reference to an ID in the pdImages() array.  It can be grabbed from the form.Tag value as well.
Public Function MenuSave(ByVal imageID As Long) As Boolean

    If pdImages(imageID).LocationOnDisk = "" Then
    
        'This image hasn't been saved before.  Launch the Save As... dialog
        MenuSave = MenuSaveAs(imageID)
        
    Else
    
        'This image has been saved before.
        
        Dim dstFilename As String
                
        'If the user has requested that we only save copies of current images, we need to come up with a new filename
        If g_UserPreferences.GetPreference_Long("General Preferences", "SaveBehavior", 0) = 0 Then
            dstFilename = pdImages(imageID).LocationOnDisk
        Else
        
            'Determine the destination directory
            Dim tempPathString As String
            tempPathString = pdImages(imageID).LocationOnDisk
            StripDirectory tempPathString
            
            'Next, determine the target filename
            Dim tempFilename As String
            tempFilename = pdImages(imageID).OriginalFileName
            
            'Finally, determine the target file extension
            Dim tempExtension As String
            tempExtension = GetExtension(pdImages(imageID).LocationOnDisk)
            
            'Now, call the incrementFilename function to find a unique filename of the "filename (n+1)" variety
            dstFilename = tempPathString & incrementFilename(tempPathString, tempFilename, tempExtension) & "." & tempExtension
        
        End If
        
        'Check to see if the image is in a format that potentially provides an "additional settings" prompt.
        ' If it is, the user needs to be prompted at least once for those settings.
        
        'JPEG
        If (pdImages(imageID).CurrentFileFormat = FIF_JPEG) And (pdImages(imageID).hasSeenJPEGPrompt = False) Then
            MenuSave = PhotoDemon_SaveImage(imageID, dstFilename, True)
        
        'JPEG-2000
        ElseIf (pdImages(imageID).CurrentFileFormat = FIF_JP2) And (pdImages(imageID).hasSeenJP2Prompt = False) Then
            MenuSave = PhotoDemon_SaveImage(imageID, dstFilename, True)
        
        'All other formats
        Else
            MenuSave = PhotoDemon_SaveImage(imageID, dstFilename, False, pdImages(imageID).getSaveFlag(0), pdImages(imageID).getSaveFlag(1), pdImages(imageID).getSaveFlag(2))
        End If
    End If

End Function

'Subroutine for displaying a commondialog save box, then saving an image to the specified file
Public Function MenuSaveAs(ByVal imageID As Long) As Boolean

    Dim CC As cCommonDialog
    Set CC = New cCommonDialog
    
    'Get the last "save image" path from the INI file
    Dim tempPathString As String
    tempPathString = g_UserPreferences.GetPreference_String("Program Paths", "MainSave", "")
        
    'g_LastSaveFilter will be set to "-1" if the user has never saved a file before.  If that happens, default to JPEG
    If g_LastSaveFilter = -1 Then
    
        g_LastSaveFilter = g_ImageFormats.getIndexOfOutputFIF(FIF_JPEG) + 1
    
    'Otherwise, set g_LastSaveFilter to this image's current file format, or optionally the last-used format
    Else
    
        'There is a user preference for defaulting to either:
        ' 1) The current image's format (standard behavior)
        ' 2) The last format the user specified in the Save As screen (my preferred behavior)
        ' Use that preference to determine which save filter we select.
        If g_UserPreferences.GetPreference_Long("General Preferences", "DefaultSaveFormat", 0) = 0 Then
        
            g_LastSaveFilter = g_ImageFormats.getIndexOfOutputFIF(pdImages(imageID).CurrentFileFormat) + 1
    
            'The user may have loaded a file format where INPUT is supported but OUTPUT is not.  If this happens,
            ' we need to suggest an alternative format.  Use the color-depth of the current image as our guide.
            If g_LastSaveFilter = -1 Then
            
                '24bpp layers default to JPEG
                If pdImages(imageID).mainLayer.getLayerColorDepth = 24 Then
                    g_LastSaveFilter = g_ImageFormats.getIndexOfOutputFIF(FIF_JPEG) + 1
                
                '32bpp layers default to PNG
                Else
                    g_LastSaveFilter = g_ImageFormats.getIndexOfOutputFIF(FIF_PNG) + 1
                End If
            
            End If
                    
        'Note that we don't need an "Else" here - the g_LastSaveFilter value will already be present
        End If
    
    End If
    
    'Check to see if an image with this filename appears in the save location. If it does, use the incrementFilename
    ' function to append ascending numbers (of the format "_(#)") to the filename until a unique filename is found.
    Dim sFile As String
    sFile = tempPathString & incrementFilename(tempPathString, pdImages(imageID).OriginalFileName, g_ImageFormats.getOutputFormatExtension(g_LastSaveFilter - 1))
        
    If CC.VBGetSaveFileName(sFile, , True, g_ImageFormats.getCommonDialogOutputFormats, g_LastSaveFilter, tempPathString, g_Language.TranslateMessage("Save an image"), g_ImageFormats.getCommonDialogDefaultExtensions, FormMain.hWnd, 0) Then
                
        'Store the selected file format to the image object
        pdImages(imageID).CurrentFileFormat = g_ImageFormats.getOutputFIF(g_LastSaveFilter - 1)
        
        'Save the new directory as the default path for future usage
        tempPathString = sFile
        StripDirectory tempPathString
        g_UserPreferences.SetPreference_String "Program Paths", "MainSave", tempPathString
        
        'Also, remember the file filter for future use (in case the user tends to use the same filter repeatedly)
        g_UserPreferences.SetPreference_Long "File Formats", "LastSaveFilter", g_LastSaveFilter
                        
        'Transfer control to the core SaveImage routine, which will handle color depth analysis and actual saving
        MenuSaveAs = PhotoDemon_SaveImage(imageID, sFile, True)
        
        'If the save was successful, update the associated window caption to reflect the new name and/or location
        If MenuSaveAs Then
            
            If g_UserPreferences.GetPreference_Long("General Preferences", "ImageCaptionSize", 0) Then
                pdImages(imageID).containingForm.Caption = getFilename(sFile)
            Else
                pdImages(imageID).containingForm.Caption = sFile
            End If
            
        End If
        
    Else
        MenuSaveAs = False
    End If
    
    'Release the common dialog object
    Set CC = Nothing
    
End Function

'This routine will blindly save the image from the form containing pdImages(imageID) to dstPath.  It is up to
' the calling routine to make sure this is what is wanted. (Note: this routine will erase any existing image
' at dstPath, so BE VERY CAREFUL with what you send here!)
Public Function PhotoDemon_SaveImage(ByVal imageID As Long, ByVal dstPath As String, Optional ByVal loadRelevantForm As Boolean = False, Optional ByVal optionalSaveParameter0 As Long = -1, Optional ByVal optionalSaveParameter1 As Long = 0, Optional ByVal optionalSaveParameter2 As Long = 0) As Boolean
    
    'Only update the MRU list if 1) no form is shown (because the user may cancel it), 2) a form was shown and the user
    ' successfully navigated it, and 3) no errors occured during the export process.  By default, this is set to "do not update."
    Dim updateMRU As Boolean
    updateMRU = False
    
    'Start by determining the output format for this image (which was set either by a "Save As" common dialog box,
    ' or by copying the image's original format).
    Dim saveFormat As Long
    saveFormat = pdImages(imageID).CurrentFileFormat

    '****************************************************************************************************
    ' Determine exported color depth
    '****************************************************************************************************

    'The user is allowed to set a persistent preference for output color depth.  This setting affects a "color depth"
    ' parameter that will be sent to the various format-specific save file routines.  The available preferences are:
    ' 0) Mimic the file's original color depth (if available; this may not always be possible, e.g. saving a 32bpp PNG as JPEG)
    ' 1) Count the number of colors used, and save the file based on that (again, if possible)
    ' 2) Prompt the user for their desired export color depth
    Dim outputColorDepth As Long
    
    'Note that JPEG exporting, on account of it being somewhat specialized, ignores this step completely.
    ' The JPEG routine will do its own scan for grayscale/color and save the file out accordingly.
    
    If saveFormat <> FIF_JPEG Then
    
        Select Case g_UserPreferences.GetPreference_Long("General Preferences", "OutgoingColorDepth", 1)
        
            'Maintain the file's original color depth (if possible)
            Case 0
                
                'Check to see if this format supports the image's original color depth
                If g_ImageFormats.isColorDepthSupported(saveFormat, pdImages(imageID).OriginalColorDepth) Then
                    
                    'If it IS supported, set the original color depth as the output color depth for this save
                    outputColorDepth = pdImages(imageID).OriginalColorDepth
                    Message "Original color depth of %1 bpp is supported by this format.  Proceeding with save...", outputColorDepth
                
                'If it IS NOT supported, we need to find the closest available color depth for this format.
                Else
                    outputColorDepth = g_ImageFormats.getClosestColorDepth(saveFormat, pdImages(imageID).OriginalColorDepth)
                    Message "Original color depth of %1 bpp is not supported by this format.  Proceeding to save as %2 bpp...", pdImages(imageID).OriginalColorDepth, outputColorDepth
                
                End If
            
            'Count colors used
            Case 1
            
                'Count the number of colors in the image.  (The function will automatically cease if it hits 257 colors,
                ' as anything above 256 colors is treated as 24bpp.)
                Dim colorCountCheck As Long
                Message "Counting image colors to determine optimal exported color depth..."
                colorCountCheck = getQuickColorCount(pdImages(imageID), imageID)
                
                'If 256 or less colors were found in the image, mark it as 8bpp.  Otherwise, mark it as 24 or 32bpp.
                outputColorDepth = getColorDepthFromColorCount(colorCountCheck, pdImages(imageID).mainLayer)
                
                'A special case arises when an image has <= 256 colors, but a non-binary alpha channel.  PNG allows for
                ' this, but other formats do not.  Because even the PNG transformation is not lossless, set these types of
                ' images to be exported as 32bpp.
                If (outputColorDepth <= 8) And (pdImages(imageID).mainLayer.getLayerColorDepth = 32) Then
                    If (Not pdImages(imageID).mainLayer.isAlphaBinary) Then outputColorDepth = 32
                End If
                
                Message "Color count successful (%1 bpp recommended)", outputColorDepth
                
                'As with case 0, we now need to see if this format supports the suggested color depth
                If g_ImageFormats.isColorDepthSupported(saveFormat, outputColorDepth) Then
                    
                    'If it IS supported, set the original color depth as the output color depth for this save
                    Message "Recommended color depth of %1 bpp is supported by this format.  Proceeding with save...", outputColorDepth
                
                'If it IS NOT supported, we need to find the closest available color depth for this format.
                Else
                    outputColorDepth = g_ImageFormats.getClosestColorDepth(saveFormat, outputColorDepth)
                    Message "Recommended color depth of %1 bpp is not supported by this format.  Proceeding to save as %2 bpp...", pdImages(imageID).OriginalColorDepth, outputColorDepth
                
                End If
            
            'Prompt the user (but only if necessary)
            Case 2
            
                'First, check to see if the save format in question supports multiple color depths
                If g_ImageFormats.doesFIFSupportMultipleColorDepths(saveFormat) Then
                    
                    'If it does, provide the user with a prompt to choose whatever color depth they'd like
                    Dim dCheck As VbMsgBoxResult
                    dCheck = promptColorDepth(saveFormat)
                    
                    If dCheck = vbOK Then
                        outputColorDepth = g_ColorDepth
                    Else
                        PhotoDemon_SaveImage = False
                        Message "Save canceled."
                        Exit Function
                    End If
                
                'If this format only supports a single output color depth, don't bother the user with a prompt
                Else
            
                    outputColorDepth = g_ImageFormats.getClosestColorDepth(saveFormat, pdImages(imageID).OriginalColorDepth)
            
                End If
            
        End Select
    
    End If
    
    '****************************************************************************************************
    ' Based on the requested file type and color depth, call the appropriate save function
    '****************************************************************************************************

    Select Case saveFormat
        
        'JPEG
        Case FIF_JPEG
        
            'JPEG files may need to display a dialog box so the user can set compression quality
            If loadRelevantForm = True Then
                
                Dim gotSettings As VbMsgBoxResult
                gotSettings = promptJPEGSettings
                
                'If the dialog was canceled, note it.  Otherwise, remember that the user has seen the JPEG save screen at least once.
                If gotSettings = vbOK Then
                    pdImages(imageID).hasSeenJPEGPrompt = True
                    PhotoDemon_SaveImage = True
                Else
                    PhotoDemon_SaveImage = False
                    Message "Save canceled."
                    Exit Function
                End If
                
                'If the user clicked OK, replace the functions save parameters with the ones set by the user
                optionalSaveParameter0 = g_JPEGQuality
                optionalSaveParameter1 = g_JPEGFlags
                optionalSaveParameter2 = g_JPEGThumbnail
                
            End If
                
            'Store these JPEG settings in the image object so we don't have to pester the user for it if they save again
            pdImages(imageID).setSaveFlag 0, optionalSaveParameter0
            pdImages(imageID).setSaveFlag 1, optionalSaveParameter1
            pdImages(imageID).setSaveFlag 2, optionalSaveParameter2
                            
            'I implement two separate save functions for JPEG images: FreeImage and GDI+.  The system we select is
            ' contingent on a variety of factors, most important of which is - are we in the midst of a batch conversion.
            ' If we are, use GDI+ as it does not need to make a copy of the image before saving it (which is much faster).
            If MacroStatus = MacroBATCH Then
                If g_ImageFormats.GDIPlusEnabled Then
                    updateMRU = GDIPlusSavePicture(imageID, dstPath, ImageJPEG, 24, optionalSaveParameter0)
                ElseIf g_ImageFormats.FreeImageEnabled Then
                    updateMRU = SaveJPEGImage(imageID, dstPath, optionalSaveParameter0, optionalSaveParameter1, optionalSaveParameter2)
                Else
                    Message "No %1 encoder found. Save aborted.", "JPEG"
                    PhotoDemon_SaveImage = False
                    Exit Function
                End If
            Else
                If g_ImageFormats.FreeImageEnabled Then
                    updateMRU = SaveJPEGImage(imageID, dstPath, optionalSaveParameter0, optionalSaveParameter1, optionalSaveParameter2)
                ElseIf g_ImageFormats.GDIPlusEnabled Then
                    updateMRU = GDIPlusSavePicture(imageID, dstPath, ImageJPEG, 24, optionalSaveParameter0)
                Else
                    Message "No %1 encoder found. Save aborted.", "JPEG"
                    PhotoDemon_SaveImage = False
                    Exit Function
                End If
            End If
            
        'PDI, PhotoDemon's internal format
        Case 100
            If g_ZLibEnabled Then
                updateMRU = SavePhotoDemonImage(imageID, dstPath)
            Else
            'If zLib doesn't exist...
                pdMsgBox "The zLib compression library (zlibwapi.dll) was marked as missing or disabled upon program initialization." & vbCrLf & vbCrLf & "To enable PDI saving, please allow %1 to download plugin updates by going to the Tools -> Options menu, and selecting the 'offer to download core plugins' check box.", vbExclamation + vbOKOnly + vbApplicationModal, " PDI Interface Error", PROGRAMNAME
                Message "No %1 encoder found. Save aborted.", "PDI"
            End If
        
        'GIF
        Case FIF_GIF
            'GIFs are preferentially exported by FreeImage, then GDI+ (if available)
            If g_ImageFormats.FreeImageEnabled Then
                updateMRU = SaveGIFImage(imageID, dstPath)
            ElseIf g_ImageFormats.GDIPlusEnabled Then
                updateMRU = GDIPlusSavePicture(imageID, dstPath, ImageGIF, 8)
            Else
                Message "No %1 encoder found. Save aborted.", "GIF"
                PhotoDemon_SaveImage = False
                Exit Function
            End If
            
        'PNG
        Case FIF_PNG
            'PNGs are preferentially exported by FreeImage, then GDI+ (if available)
            If g_ImageFormats.FreeImageEnabled Then
                updateMRU = SavePNGImage(imageID, dstPath, outputColorDepth)
            ElseIf g_ImageFormats.GDIPlusEnabled Then
                updateMRU = GDIPlusSavePicture(imageID, dstPath, ImagePNG, outputColorDepth)
            Else
                Message "No %1 encoder found. Save aborted.", "PNG"
                PhotoDemon_SaveImage = False
                Exit Function
            End If
            
        'PPM
        Case FIF_PPM
            updateMRU = SavePPMImage(imageID, dstPath)
                
        'TGA
        Case FIF_TARGA
            updateMRU = SaveTGAImage(imageID, dstPath, outputColorDepth)
            
        'JPEG-2000
        Case FIF_JP2
        
            If loadRelevantForm = True Then
                
                Dim gotJP2Settings As VbMsgBoxResult
                gotJP2Settings = promptJP2Settings()
                
                'If the dialog was canceled, note it.  Otherwise, remember that the user has seen the JPEG save screen at least once.
                If gotJP2Settings = vbOK Then
                    pdImages(imageID).hasSeenJP2Prompt = True
                    PhotoDemon_SaveImage = True
                Else
                    PhotoDemon_SaveImage = False
                    Message "Save canceled."
                    Exit Function
                End If
                
                'If the user clicked OK, replace the functions save parameters with the ones set by the user
                optionalSaveParameter0 = g_JP2Compression
                
            End If
        
            updateMRU = SaveJP2Image(imageID, dstPath, outputColorDepth, optionalSaveParameter0)
            
        'TIFF
        Case FIF_TIFF
            'TIFFs are preferentially exported by FreeImage, then GDI+ (if available)
            If g_ImageFormats.FreeImageEnabled Then
                updateMRU = SaveTIFImage(imageID, dstPath, outputColorDepth)
            ElseIf g_ImageFormats.GDIPlusEnabled Then
                updateMRU = GDIPlusSavePicture(imageID, dstPath, ImageTIFF, outputColorDepth)
            Else
                Message "No %1 encoder found. Save aborted.", "TIFF"
                PhotoDemon_SaveImage = False
                Exit Function
            End If
        
        'Anything else must be a bitmap
        Case FIF_BMP
            updateMRU = SaveBMP(imageID, dstPath, outputColorDepth)
            
        Case Else
            Message "Output format not recognized.  Save aborted.  Please use the Help -> Submit Bug Report menu item to report this incident."
            PhotoDemon_SaveImage = False
            Exit Function
        
    End Select
    
    'UpdateMRU should only be true if the save was successful
    If updateMRU Then
    
        'Additionally, only add this MRU to the list (and generate an accompanying icon) if we are not in the midst
        ' of a batch conversion.
        If MacroStatus <> MacroBATCH Then
        
            'Add this file to the MRU list
            MRU_AddNewFile dstPath, pdImages(imageID)
        
            'Remember the file's location for future saves
            pdImages(imageID).LocationOnDisk = dstPath
            
            'Remember the file's filename
            Dim tmpFilename As String
            tmpFilename = dstPath
            StripFilename tmpFilename
            pdImages(imageID).OriginalFileNameAndExtension = tmpFilename
            StripOffExtension tmpFilename
            pdImages(imageID).OriginalFileName = tmpFilename
            
            'Mark this file as having been saved
            pdImages(imageID).UpdateSaveState True
            
            PhotoDemon_SaveImage = True
            
        End If
    
    Else
        
        'If we aren't updating the MRU, something went wrong.  Display that the save was canceled and exit.
        Message "Save canceled."
        PhotoDemon_SaveImage = False
        Exit Function
        
    End If

    Message "Save complete."

End Function
