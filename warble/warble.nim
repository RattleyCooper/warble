##
## Example of how to embed any arbitrary file into an image's 
## pixels.
## 
## Shoutout to treeform on github for providing the pixie library
## along with the steganography library that this is based on. Instead
## of encoding a string into an image the bytes that make up a file
## are encoded instead.
## 


import pixie
import os
import parseopt
import sequtils


let TermBytes* = @[      # Don't use const or else bytes
  4u8, 20u8, 69u8,      # are compiled into binary and
  0u8, 0u8, 0u8,        # warble cannot be embeded into
  69u8, 4u8, 20u8,      # an image.
  255u8, 254u8, 253u8,
  252u8, 251u8, 250u8 
]


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
      if result[^TermBytes.len..result.len-1] == TermBytes:
        result = result[0..^TermBytes.len+1]
        break
    result.add(dataByte)

proc profileImage*(inImgPath: string): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  var image = readImage(inImgPath)
  result = ((image.width * image.height) div 4) - TermBytes.len

proc profileImage*(image: Image): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  result = ((image.width * image.height) div 4) - TermBytes.len

proc inject*(inImgPath: string, plPath: string, outImgPath: string) =
  ## Inject the payload into the image and create a new image.
  #
  echo "Opening payload..."
  var f: File
  discard f.open(plPath, fmRead)
  echo "Payload size: " & $f.getFileSize

  var bytes = newSeq[uint8](f.getFileSize)
  discard f.readBytes(bytes, 0, f.getFileSize)
  var image = readImage(inImgPath)
  doAssert(f.getFileSize < profileImage(image)-TermBytes.len)
  
  echo "Injecting payload... " & $bytes.len
  encodeData(image, bytes)
  image.writeFile(outImgPath)
  f.close()

proc extract*(inImgPath: string, plPath: string) =
  ## Extract payload from an image.
  #

  echo "Extracting payload..."
  var image = readImage(inImgPath)
  var payload = decodeData(image)
  echo "Payload size: " & $payload.len
  
  var ouf: File
  discard ouf.open(plPath, fmWrite)
  echo "Creating payload... " & $payload.len
  discard ouf.writeBytes(payload, 0, payload.len)
  ouf.close()


if isMainModule:
  var injecting = false
  var extracting = false

  var profilingPath: string
  var inputImage: string
  var payloadPath: string
  var outputImage: string

  proc setupApp() =
    ## Set up application
    #
    for kind, key, val in getOpt():
      case key:
      of "i", "inject":
        injecting = true
      of "e", "extract":
        extracting = true
      of "ii", "inputImage":
        inputImage = expandTilde(val)
      of "p", "payload":
        payloadPath = expandTilde(val)
      of "oi", "outputImage":
        outputImage = expandTilde(val)
      of "pr", "profile":
        profilingPath = expandTilde(val)


  setupApp()
  doAssert(profilingPath != "" or injecting or extracting)

  if profilingPath != "":
    doAssert(injecting == false)
    doAssert(extracting == false)
    echo $profileImage(profilingPath) & " available bytes..."

  if injecting:
    doAssert(injecting != extracting, "You must specify the type of job with -i or -e")
    doAssert(inputImage != "")
    doAssert(outputImage != "")
    inject(inputImage, payloadPath, outputImage)

  if extracting:
    doAssert(injecting != extracting, "You must specify the type of job with -i or -e")
    extract(inputImage, payloadPath)
