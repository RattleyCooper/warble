##
## Library and command line utility for embedding/extracting files into 
## the pixel data of an image or the data chunk of a 32 bit wav file.
##

import pixie
import os
import parseopt
import streams
import strutils


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

type
  Wav = ref object
    filename: string
    dataPos: int
    data: seq[uint8]

proc decodeWav*(wav: Wav): seq[uint8] =
  ## Decodes the payload embedded in the LSB of the WAV file's data chunk.
  ## Returns the decoded payload as a sequence of bytes.
  var bitIndex = 0
  var payloadLenBytes: array[8, uint8]  # To store the 8-byte payload length
  var payloadLen: int64 = 0

  # Extract the payload length (8 bytes = 64 bits)
  for i in 0..<8:
    for j in 0..<8:
      let sampleIndex = bitIndex * 4  # Each sample is 4 bytes
      var sample: float32
      copyMem(addr sample, addr wav.data[sampleIndex], 4)  # Read float32 sample
      let byteRep = cast[array[4, uint8]](sample)
      let bit = byteRep[0] and 1  # Extract LSB of the least significant byte
      payloadLenBytes[i] = (payloadLenBytes[i] shl 1) or bit  # Reconstruct byte
      bitIndex += 1

  # Convert the 8-byte array to an int64
  copyMem(addr payloadLen, addr payloadLenBytes[0], 8)

  if isMainModule:
    echo "Decoded payload length: ", payloadLen

  # Extract the payload
  var payload: seq[uint8] = newSeq[uint8](payloadLen)
  for i in 0..<payloadLen:
    for j in 0..<8:
      let sampleIndex = bitIndex * 4  # Each sample is 4 bytes
      var sample: float32
      copyMem(addr sample, addr wav.data[sampleIndex], 4)  # Read float32 sample
      let byteRep = cast[array[4, uint8]](sample)
      let bit = byteRep[0] and 1  # Extract LSB of the least significant byte
      payload[i] = (payload[i] shl 1) or bit  # Reconstruct byte
      bitIndex += 1

  return payload

proc saveDecodedPayload*(payload: seq[uint8], outputFile: string) =
  var f: File
  discard f.open(outputFile, fmWrite)
  defer: f.close()

  discard f.writeBytes(payload, 0, payload.len)

proc extractWavData*(filename: string): Wav =
  result = Wav(filename: "", dataPos: 0, data: newSeq[uint8]())
  result.filename = filename

  let fs = newFileStream(filename, fmRead)
  if fs == nil:
    raise newException(IOError, "Failed to open file")

  defer: fs.close()

  var buffer: array[4, char]
  fs.setPosition(12)  # Skip RIFF header (12 bytes: "RIFF", file size, "WAVE")
  while not fs.atEnd():
    discard fs.readData(addr buffer[0], 4)  # Read 4 bytes (chunk ID)
    let chunkId = buffer.join("")

    var chunkSize: int32
    discard fs.readData(addr chunkSize, 4)  # Read 4-byte chunk size
    
    if chunkId == "data":
      result.dataPos = fs.getPosition()
      result.data = newSeq[uint8](chunkSize)
      discard fs.readData(addr result.data[0], chunkSize)
      return

    fs.setPosition(fs.getPosition() + chunkSize)  # Skip to next chunk

  raise newException(IOError, "No data chunk found")

proc encodeWav*(wav: Wav, plPath: string, newPath: string): Wav =
  var f: File
  discard f.open(plPath, fmRead)
  defer: f.close()

  var dataLen: int64 = f.getFileSize()
  var dataLenSeq: seq[uint8] = newSeq[uint8](8)
  copyMem(addr dataLenSeq[0], unsafeAddr dataLen, sizeOf(dataLen))
  var payload: seq[uint8]
  payload.add dataLenSeq

  if isMainModule:
    echo "Payload size: " & $dataLen
    echo "Reading payload..."
  var pdat = newSeq[uint8](f.getFileSize())
  discard f.readBytes(pdat, 0, f.getFileSize())
  payload.add pdat

  if payload.len * 8 > wav.data.len div 4:  # 32-bit samples (4 bytes per sample)
    raise newException(ValueError, "Not enough space for the payload.")

  var bitIndex = 0
  for i in 0..<payload.len:
    for j in 0..<8:
      let bit = (payload[i] shr (7 - j)) and 1
      let sampleIndex = bitIndex * 4  # Each sample is 4 bytes

      # Convert 4 bytes into a float32
      var sample: float32
      copyMem(addr sample, addr wav.data[sampleIndex], 4)  # Read float32

      # Modify the LSB of the last byte (least significant)
      var byteRep = cast[array[4, uint8]](sample)
      byteRep[0] = (byteRep[0] and 0xFE) or bit  # Modify LSB of least significant byte

      # Store modified sample back
      sample = cast[float32](byteRep)
      copyMem(addr wav.data[sampleIndex], addr sample, 4)

      bitIndex += 1

  # Write modified WAV data to a new file
  var nf: File
  discard nf.open(newPath, fmWrite)
  defer: nf.close()

  var olf: File
  discard olf.open(wav.filename, fmRead)
  defer: olf.close()

  var preData = newSeq[uint8](wav.dataPos + 1)
  discard olf.readBytes(preData, 0, wav.dataPos + 1)
  discard nf.writeBytes(preData, 0, preData.len - 1)
  discard nf.writeBytes(wav.data, 0, wav.data.len)

  let fs = olf.getFileSize()
  if fs > wav.dataPos + wav.data.len + 1:
    let remainder = fs - (wav.dataPos + 1 + wav.data.len)
    var rBytes = newSeq[uint8](remainder)
    olf.setFilePos(olf.getFileSize - remainder - 1)
    discard olf.readBytes(rBytes, 0, remainder)
    discard nf.writeBytes(rBytes, 0, rBytes.len)
  return wav

proc encodeData*(image: Image, data: seq[uint8]) =
  ## Hide data inside an image
  #

  # Prepend the data length to the data.
  var dataLen: int64 = data.len()
  var dataLenSeq: seq[uint8] = newSeq[uint8](8)
  copyMem(addr dataLenSeq[0], unsafeAddr dataLen, sizeOf(dataLen))
  var ndata: seq[uint8]
  ndata.add dataLenSeq
  ndata.add data

  # Encode all of the data
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

  # Extract the data's length.
  var dataLen: int64
  var dataLenBytes: seq[uint8] = newSeq[uint8](8)
  for i in 0..7:
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

    dataLenBytes[i] = dataByte
  
  copyMem(addr dataLen, unsafeAddr dataLenBytes[0], sizeof(dataLen))

  # Extract data from image.
  for i in 8..<(image.data.len div 4):
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

    if result.len >= dataLen:
      break
        
    result.add(dataByte)

proc profileWav*(wavPath: string): int64 =
  var w = extractWavData(wavPath)
  result = (w.data.len div 4) div 8
  if isMainModule: echo "Data Cap: ", result

proc isWav*(filepath: string): bool =
  let fs = newFileStream(filepath, fmRead)
  if fs == nil:
    if isMainModule:
      echo "Could not open ", filepath
    quit QuitFailure

  var header: string = newString(4)
  discard fs.readDataStr(header, 0..3)
  if header == "RIFF":
    return true
  return false

proc profileImage*(inImgPath: string): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  var image = readImage(inImgPath)
  result = ((image.width * image.height) div 4) - 8

proc profileImage*(image: Image): int64 =
  ## The amount of bytes can be stored inside an image.
  #
  result = ((image.width * image.height) div 4) - 8

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
  defer: f.close()
  let fs = f.getFileSize()
  
  if isMainModule: echo "\nFilesize: " & $fs & " bytes"
  fs

if isMainModule:
  var 
    injecting = false
    extracting = false

    profilingPath: string
    fileSizePath: string
    inputImage: string
    payloadPath: string
    outputImage: string

    waveFile: bool

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
      var w = extractWavData(inputImage)
      discard inputImage.profileWav()
      w = w.encodeWav(payloadPath, outputImage)
    else:
      discard inject(inputImage, payloadPath, outputImage)
    quit(QuitSuccess)

  elif extracting:
    if inputImage.isWav():
      var w = extractWavData(inputImage)
      let payload = w.decodeWav()
      payload.saveDecodedPayload(payloadPath)
    else:
      discard extract(inputImage, payloadPath)
    quit(QuitSuccess)

  else:
    echo HelpMessage
    quit(QuitSuccess)
