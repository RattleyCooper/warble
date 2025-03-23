##
## Library and command line utility for embedding/extracting files into 
## the pixel data of an image or the data chunk of a 32 bit wav file.
##

import wav
import image
from os import expandTilde
from parseopt import getopt

const HelpMessage = """
           __   __        ___ 
|  |  /\  |__) |__) |    |__  
|/\| /~~\ |  \ |__) |___ |___ 

Warble is a command line steganography tool/nim library that can embed files 
 into the pixel data of images, or the data chunk of a 32 bit wav file.

    https://github.com/RattleyCooper/warble

  --h                   show this help message.
  --pr: filepath        shows the amount of bytes 
                         that can be encode into 
                         the specified file
  --s: filepath         shows the file size in
                         bytes
  
  --i: filepath         input file 
  --o: filepath         output file 
  --p: filepath         payload

Injecting a payload:
  
  If the --i, --o and --p arguments are set, the payload will be embedded 
   into the input file and saved to the output filepath.

  `./warble --i: test-files/test0.png --o: test-files/test0-inj.png --p: warble`

Extracting a payload:

  if the --i and --p arguments are set, the payload will be extracted from the 
   input file and saved to the path given by --p.

  `./warble --i: test-files/test0-inj.png --p: test-files/warble`
"""

proc save*(payload: seq[uint8], outputFile: string) =
  ## Save the payload to the filepath.
  ## 
  var f: File
  discard f.open(outputFile, fmWrite)
  defer: f.close()

  discard f.writeBytes(payload, 0, payload.len)

proc fileBytesSize*(fsPath: string): int64 =
  if isMainModule: 
    echo "Opening file :\n"
    echo "  Input File: \t" & fsPath
  var f: File
  discard f.open(fsPath, fmRead)
  defer: f.close()
  result = f.getFileSize()
  
  if isMainModule: echo "\nFilesize: " & $result & " bytes"

if isMainModule:
  var 
    injecting = false
    extracting = false

    profilingPath: string
    fileSizePath: string
    inputImage: string
    payloadPath: string
    outputImage: string

    waveFile: bool = false

  proc setupApp() =
    ## Set up application
    #
    for kind, key, val in getOpt():
      case key:
      of "i", "inputImage":
        inputImage = expandTilde(val)
        if inputImage.isWav():
          waveFile = true
      of "p", "payload":
        payloadPath = expandTilde(val)
      of "o", "outputImage":
        outputImage = expandTilde(val)
      of "pr", "profile":
        profilingPath = expandTilde(val)
      of "s", "size":
        fileSizePath = expandTilde(val)
      of "h", "help":
        echo HelpMessage
        quit(QuitSuccess)

  setupApp()

  if inputImage != "" and outputImage != "" and payloadPath != "":
    injecting = true
  elif inputImage != "" and payloadPath != "":
    extracting = true

  if fileSizePath != "":
    echo $fileBytesSize(fileSizePath)
    quit(QuitSuccess)

  elif profilingPath != "":
    if profilingPath.isWav():
      discard profilingPath.profileWav()
      quit QuitSuccess
    else:
      echo $profileImage(profilingPath) & " available bytes..."
    quit(QuitSuccess)

  elif injecting:
    if inputImage.isWav():
      echo "Inject : \n" 
      echo "  Input Wav:\t" & inputImage
      echo "  Output Wav:\t" & outputImage
      echo "  Payload Path:\t" & payloadPath
      echo "Reading wav data..."
      var w = extractWavData(inputImage)
      discard inputImage.profileWav()
      w = w.encodeWav(payloadPath, outputImage)
    else:
      discard inject(inputImage, payloadPath, outputImage)
    quit(QuitSuccess)

  elif extracting:
    if inputImage.isWav():
      echo "Extract : \n"
      echo "  Input Image:\t" & inputImage
      echo "  Payload Path:\t" & payloadPath
      echo "\nReading wav data..."
      var w = extractWavData(inputImage)
      let payload = w.decodeWav()
      echo "Saving payload..."
      payload.save(payloadPath)
      echo "Done."
    else:
      discard extract(inputImage, payloadPath)
    quit(QuitSuccess)

  else:
    echo HelpMessage
    quit(QuitSuccess)
