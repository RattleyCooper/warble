##
## Example of how to embed any arbitrary file into an image's 
## pixels.
## 
## Shoutout to treeform on github for providing the pixie library
## along with the steganography library that this is based on. Instead
## of encoding a string into an image the bytes that make up a file
## are encoded instead.
## 
## Todo: Figure out way to encode length of data into the first few bytes
##        to avoid using a terminating sequence.
## 


import pixie
import os
import parseopt
import sequtils


let TermBytes* = block:
  let tchs = @[
    'W', 'a', 'r', 'b', 'l', 'e',
    'e', 'l', 'b', 'r', 'a', 'W',
    'W', 'a', 'r', 'b', 'l', 'e'
  ]
  var res: seq[uint8]
  for ch in tchs:
    res.add ord(ch).uint8
  res


const HelpMessage = """
           __   __        ___ 
|  |  /\  |__) |__) |    |__  
|/\| /~~\ |  \ |__) |___ |___ 

Warble is a command line steganography tool/nim library that can embed files 
 into the pixel data of images.

    https://github.com/RattleyCooper/warble

  --h                   show this help message.
  --pr: filepath        shows the amount of bytes 
                         that can be encode into 
                         the image specified by 
                         the given filepath
  --s: filepath         shows the file size in
                         bytes
  
  --i: filepath         input image 
  --o: filepath         output image 
  --p: filepath         payload

Injecting a payload:
  
  If the --i, --o and --p arguments are set, the payload will be embedded 
   into the input image and saved to the output image filepath.

  `./warble --i: test-files/test0.png --o: test-files/test0-inj.png --p: warble`

Extracting a payload:

  if the --i and --p arguments are set, the payload will be extracted from the 
   input image and saved to the path given by --p.

  `./warble --i: test-files/test0-inj.png --p: test-files/warble`
"""


proc encodeData*(image: Image, data: seq[uint8]) =
  ## Hide data inside an image
  #
  var ndata = data.concat(TermBytes)
  for i in 0..ndata.len-1:
    var dataByte: uint8 = ndata[i]
    if i >= ndata.len:
      break
    var
      c1 = image.data[i*2+0]
      c2 = image.data[i*2+1]
    c1.r = (c1.r and 0b11111000) + (dataByte and 0b00000001) shr 0
    c1.g = (c1.g and 0b11111100) + (dataByte and 0b0000110) shr 1
    c1.b = (c1.b and 0b11111000) + (dataByte and 0b0001000) shr 3
    c1.a = 255
    c2.r = (c2.r and 0b11111000) + (dataByte and 0b00110000) shr 4
    c2.g = (c2.g and 0b11111100) + (dataByte and 0b01000000) shr 6
    c2.b = (c2.b and 0b11111000) + (dataByte and 0b10000000) shr 7
    c2.a = 255
    image.data[i*2+0] = c1
    image.data[i*2+1] = c2

proc decodeData*(image: Image): seq[uint8] =
  ## Extract hidden data in the image
  #
  for i in 0..<(image.data.len div 4):
    var dataByte: uint8
    let
      c1 = image.data[i*2+0]
      c2 = image.data[i*2+1]
    dataByte += (c1.r and 0b1) shl 0
    dataByte += (c1.g and 0b11) shl 1
    dataByte += (c1.b and 0b1) shl 3
    dataByte += (c2.r and 0b11) shl 4
    dataByte += (c2.g and 0b1) shl 6
    dataByte += (c2.b and 0b1) shl 7

    if result.len >= TermBytes.len:
      if result[^TermBytes.len..(result.len - 1)] == TermBytes:
        result = result[0..^(TermBytes.len + 1)]
        break
        
    result.add(dataByte)

  # Needed in case decoded data takes up entire space that 
  # can fit into the image.
  if result[^TermBytes.len..(result.len - 1)] == TermBytes:
    result = result[0..^(TermBytes.len + 1)]



proc profileImage*(inImgPath: string): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  var image = readImage(inImgPath)
  result = ((image.width * image.height) div 4) - TermBytes.len

proc profileImage*(image: Image): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  result = ((image.width * image.height) div 4) - TermBytes.len

proc inject*(inImgPath: string, plPath: string, outImgPath: string): seq[uint8] =
  ## Inject the payload into the image and create a new image.
  #
  if isMainModule:
    echo "Inject : \n" 
    echo "  Input Image:\t" & inImgPath
    echo "  Output Image:\t" & outImgPath
    echo "  Payload Path:\t" & plPath
    echo "\nOpening payload..."
  var f: File
  discard f.open(plPath, fmRead)
  
  if isMainModule: echo "Payload size: " & $f.getFileSize
  var bytes = newSeq[uint8](f.getFileSize)
  
  if isMainModule: echo "Reading payload..."
  discard f.readBytes(bytes, 0, f.getFileSize)
  
  if isMainModule: echo "Reading image data..."
  var image = readImage(inImgPath)
  doAssert(
    f.getFileSize <= profileImage(image),
    "Cannot fit payload into the given image."
  )
  
  if isMainModule: echo "Injecting payload... " & $bytes.len
  encodeData(image, bytes)
  
  if isMainModule: echo "Writing image payload.."
  image.writeFile(outImgPath)
  f.close()
  
  if isMainModule: echo "Done."
  result = bytes

proc extract*(inImgPath: string, plPath: string, assertSize: int = 0): seq[uint8] =
  ## Extract payload from an image.
  #
  if isMainModule:
    echo "Extract : \n"
    echo "  Input Image:\t" & inImgPath
    echo "  Payload Path:\t" & plPath
    echo "\nReading image data..."
  var image = readImage(inImgPath)
  
  if isMainModule: echo "Extracting payload..."
  var payload = decodeData(image)

  if isMainModule: echo "Payload size: " & $payload.len
  if assertSize > 0:
    doAssert(payload.len == assertSize, "Size of payload did not match the assertSize")
  
  if isMainModule: echo "Creating payload file..."
  var ouf: File
  discard ouf.open(plPath, fmWrite)
  
  if isMainModule: echo "Writing payload... " & $payload.len
  discard ouf.writeBytes(payload, 0, payload.len)
  ouf.close()
  
  if isMainModule: echo "Done."
  result = payload

proc fileBytesSize*(fsPath: string): int64 =
  if isMainModule: 
    echo "Opening file :\n"
    echo "  Input File: \t" & fsPath
  var f: File
  discard f.open(fsPath, fmRead)
  let fs = f.getFileSize()
  
  if isMainModule: echo "\nFilesize: " & $fs & " bytes"
  f.close()
  fs

if isMainModule:
  var injecting = false
  var extracting = false

  var profilingPath: string
  var fileSizePath: string
  var inputImage: string
  var payloadPath: string
  var outputImage: string

  proc setupApp() =
    ## Set up application
    #
    for kind, key, val in getOpt():
      case key:
      of "i", "inputImage":
        inputImage = expandTilde(val)
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
    echo $profileImage(profilingPath) & " available bytes..."
    quit(QuitSuccess)

  elif injecting:
    doAssert(inputImage != "", "You must specify an input image filepath with --i=/some/input/img.png")
    doAssert(outputImage != "", "You must specify an output image filepath with --o=/some/path/to/save/injected/img.png")
    doAssert(payloadPath != "", "You must specify a payload filepath with --p=/some/path/to/payload")
    discard inject(inputImage, payloadPath, outputImage)
    quit(QuitSuccess)

  elif extracting:
    discard extract(inputImage, payloadPath)
    quit(QuitSuccess)

  else:
    echo HelpMessage
    quit(QuitSuccess)
